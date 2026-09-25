//! 归档上传端点：`POST /node/upload/archive?dest=<urlencoded>`
//!
//! 请求体是一个 zip 的原始字节（客户端用 `zip_directory_to_tmp` 打包本地目录）。
//! 这里刻意**不进内存**：节点服务器原来的通用 body 读取是 `vec![0u8; content_length]`，
//! 一个几百 MB 的目录会把节点直接打爆，所以这条路由在读取 body 之前分流出来，
//! 用 `io::copy` 流式落到临时文件，再交给 extract_module 解压到目标目录。

use std::io::{BufReader, Read, Write};
use std::net::TcpStream;
use std::path::Path;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

/// 单次归档上传的体积上限。给的是家庭媒体库一个目录的量级，
/// 超过就拒绝——上限存在的意义是拒绝，不是提示。
pub const MAX_UPLOAD_BYTES: u64 = 8 * 1024 * 1024 * 1024;

/// 上传+解压结果
pub struct UploadOutcome {
    pub status: u16,
    pub message: String,
    /// 解压后的目标目录（成功时回给客户端，用于后续 import_media_folder）
    pub dest: String,
    pub bytes: u64,
}

/// 从 query string 取参数（已做百分号解码）。
fn query_param(query: &str, key: &str) -> Option<String> {
    url::form_urlencoded::parse(query.as_bytes())
        .into_owned()
        .find(|(k, _)| k == key)
        .map(|(_, v)| v)
}

/// 校验目标目录：必须是绝对路径、已存在、且是目录。
///
/// 刻意不接受不存在的目录——节点不能因为一个请求就在磁盘上凭空建目录树。
fn validate_dest(raw: &str) -> Result<(), String> {
    if raw.is_empty() {
        return Err("缺少 dest 参数".to_string());
    }
    if raw.contains('\0') {
        return Err("dest 含非法字符".to_string());
    }
    let path = Path::new(raw);
    if !path.is_absolute() {
        return Err("dest 必须是绝对路径".to_string());
    }
    if !path.is_dir() {
        return Err(format!("目标目录不存在: {raw}"));
    }
    Ok(())
}

fn temp_zip_path() -> std::path::PathBuf {
    let millis = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or(0);
    std::env::temp_dir().join(format!("sw_upload_{millis}.zip"))
}

/// 处理归档上传：流式落盘 → 解压 → 删除临时 zip。
///
/// 任何一步失败都立即回 HTTP 错误，并尽量清理临时文件，避免节点 temp 目录堆积。
pub fn handle_archive_upload(
    mut stream: TcpStream,
    reader: &mut BufReader<TcpStream>,
    query: &str,
    content_length: usize,
) {
    // 读完整个归档的时间远超普通请求的 10s 读超时：按最坏情况放宽到 30 分钟。
    // 注意超时挂在 reader 内部的那个 socket 句柄上，不是 stream 这个句柄。
    let _ = reader
        .get_ref()
        .set_read_timeout(Some(Duration::from_secs(30 * 60)));
    let outcome = receive_and_extract(reader, query, content_length);
    let body = if outcome.status == 200 {
        serde_json::json!({
            "success": true,
            "data": {
                "dest": outcome.dest,
                "bytes": outcome.bytes.to_string(),
                "message": outcome.message,
            }
        })
        .to_string()
    } else {
        serde_json::json!({"success": false, "error": outcome.message}).to_string()
    };
    let head = format!(
        "HTTP/1.1 {}\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: {}\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n",
        status_line(outcome.status),
        body.len()
    );
    let _ = stream.write_all(head.as_bytes());
    let _ = stream.write_all(body.as_bytes());
    let _ = stream.flush();
}

fn status_line(code: u16) -> String {
    let reason = match code {
        200 => "OK",
        400 => "Bad Request",
        413 => "Payload Too Large",
        500 => "Internal Server Error",
        _ => "Internal Server Error",
    };
    format!("{code} {reason}")
}

fn fail(status: u16, message: String, dest: String) -> UploadOutcome {
    UploadOutcome {
        status,
        message,
        dest,
        bytes: 0,
    }
}

fn receive_and_extract<R: Read>(
    reader: &mut R,
    query: &str,
    content_length: usize,
) -> UploadOutcome {
    let dest = query_param(query, "dest").unwrap_or_default();
    if let Err(e) = validate_dest(&dest) {
        return fail(400, e, dest);
    }
    if content_length == 0 {
        return fail(400, "空的上传请求体".to_string(), dest);
    }
    if content_length as u64 > MAX_UPLOAD_BYTES {
        return fail(
            413,
            format!(
                "归档过大: {} 字节，上限 {} 字节",
                content_length, MAX_UPLOAD_BYTES
            ),
            dest,
        );
    }

    let tmp = temp_zip_path();
    let mut file = match std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&tmp)
    {
        Ok(f) => f,
        Err(e) => return fail(500, format!("创建临时文件失败: {e}"), dest),
    };

    let copied = match take_body(reader, content_length as u64, &mut file) {
        Ok(n) => n,
        Err(e) => {
            let _ = std::fs::remove_file(&tmp);
            return fail(500, format!("接收归档失败: {e}"), dest);
        }
    };
    drop(file);

    if copied != content_length as u64 {
        let _ = std::fs::remove_file(&tmp);
        return fail(
            400,
            format!("归档不完整: 期望 {content_length} 字节，实收 {copied} 字节"),
            dest,
        );
    }

    let tmp_str = tmp.to_string_lossy().to_string();
    let extract_result = extract_module::extractor::extract_archive(&tmp_str, &dest, None, &|_| {});
    // 无论解压成败，临时 zip 都不该留在节点上
    let _ = std::fs::remove_file(&tmp);

    match extract_result {
        Ok(_) => UploadOutcome {
            status: 200,
            message: "归档已解压".to_string(),
            dest,
            bytes: copied,
        },
        Err(e) => fail(500, format!("解压失败: {e}"), dest),
    }
}

/// 把请求体流式写进文件，返回实际写入字节数。
///
/// `take(limit)` 是关键：客户端谎报 Content-Length 时也只会写满 limit 就停，
/// 不会把后续连接的字节吞进这个文件。
fn take_body<R: Read, W: Write>(reader: &mut R, limit: u64, writer: &mut W) -> std::io::Result<u64> {
    let mut limited = reader.take(limit);
    std::io::copy(&mut limited, writer)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    #[test]
    fn dest_must_be_existing_absolute_dir() {
        assert!(validate_dest("").is_err());
        assert!(validate_dest("relative/path").is_err());
        assert!(validate_dest("/no/such/dir/at/all").is_err());
        assert!(validate_dest("/tmp\0evil").is_err());
        // 存在的目录才放行
        assert!(validate_dest(std::env::temp_dir().to_str().unwrap()).is_ok());
    }

    #[test]
    fn query_param_decodes_percent_escapes() {
        let q = "dest=%2Ftmp%2Fmy%20folder&x=1";
        assert_eq!(query_param(q, "dest").as_deref(), Some("/tmp/my folder"));
        assert_eq!(query_param(q, "missing"), None);
    }

    #[test]
    fn oversized_or_empty_body_rejected_before_write() {
        let dest = std::env::temp_dir().to_str().unwrap().to_string();
        let query = format!("dest={dest}");
        let mut reader = Cursor::new(Vec::<u8>::new());
        // 谎报超过上限：必须在建临时文件之前就 413
        assert_eq!(
            receive_and_extract(&mut reader, &query, (MAX_UPLOAD_BYTES + 1) as usize).status,
            413
        );
        assert_eq!(receive_and_extract(&mut reader, &query, 0).status, 400);
        // 非法 dest 优先于 body 检查
        assert_eq!(
            receive_and_extract(&mut reader, "dest=/no/such/dir", 1024).status,
            400
        );
    }

    #[test]
    fn body_copy_stops_at_limit() {
        let payload = vec![7u8; 4096];
        let mut cursor = Cursor::new(payload);
        let mut sink: Vec<u8> = Vec::new();
        let written = take_body(&mut cursor, 1024, &mut sink).unwrap();
        assert_eq!(written, 1024);
        assert_eq!(sink.len(), 1024);
    }

    /// 端到端：客户端打包用的 zip → 本端点接收 → 解压到目标目录。
    #[test]
    fn archive_upload_extracts_into_dest() {
        let work = std::env::temp_dir().join(format!(
            "sw_upload_test_{}",
            std::process::id()
        ));
        let src = work.join("payload");
        let _ = std::fs::remove_dir_all(&src);
        std::fs::create_dir_all(src.join("sub")).unwrap();
        std::fs::write(src.join("sub/a.txt"), b"hello").unwrap();

        // 用 extract_module 的打包函数造 zip（与真实客户端同一条代码路径）
        let zip_path = extract_module::zip_directory_to_tmp(
            src.to_str().unwrap().to_string(),
            "payload".to_string(),
        )
        .expect("zip");
        let bytes = std::fs::read(&zip_path).unwrap();
        let _ = std::fs::remove_file(&zip_path);

        let dest = work.join("node_side");
        std::fs::create_dir_all(&dest).unwrap();
        let query = format!("dest={}", dest.to_str().unwrap());

        // 直接跑接收+解压这条完整路径（与 handle_connection 分流后进的是同一个函数）
        let mut cursor = Cursor::new(bytes.clone());
        let outcome = receive_and_extract(&mut cursor, &query, bytes.len());
        assert_eq!((outcome.status, outcome.bytes), (200, bytes.len() as u64));
        assert_eq!(
            std::fs::read(dest.join("payload/sub/a.txt")).unwrap(),
            b"hello"
        );
        // 临时 zip 必须已被清理
        assert!(!temp_zip_path().exists());
        let _ = std::fs::remove_dir_all(&work);
    }
}

