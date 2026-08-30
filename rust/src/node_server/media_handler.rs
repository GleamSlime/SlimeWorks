use hyper::{Body, Request, Response, StatusCode};
use media_collection::api as media_api;
use std::convert::Infallible;
use std::fs;
use std::path::Path;
use std::sync::atomic::{AtomicU64, Ordering};

/// 视频/音频流式传输的单次切片上限（2MB）
const VIDEO_CHUNK_SIZE: u64 = 2 * 1024 * 1024;

/// 节点端缩略图生成统计（供客户端轮询展示生成进度）。
static THUMB_TOTAL: AtomicU64 = AtomicU64::new(0);
static THUMB_COMPLETED: AtomicU64 = AtomicU64::new(0);

/// 返回节点端缩略图生成进度 (已开始总数, 已完成数)。
pub fn thumb_generation_progress() -> (u64, u64) {
    (
        THUMB_TOTAL.load(Ordering::Relaxed),
        THUMB_COMPLETED.load(Ordering::Relaxed),
    )
}

/// 带统计包装的缩略图生成：记录开始/完成计数。
fn ensure_cover_thumbnail_tracked(file_path: &str, width: u32) -> Option<String> {
    THUMB_TOTAL.fetch_add(1, Ordering::Relaxed);
    let result = media_api::ensure_cover_thumbnail(file_path.to_string(), width);
    THUMB_COMPLETED.fetch_add(1, Ordering::Relaxed);
    result
}

/// 后台为一批媒体文件生成缩略图并计入进度统计（导入后全量生成用）。
pub fn spawn_bulk_thumbnail_generation(files: Vec<String>) {
    if files.is_empty() {
        return;
    }
    THUMB_TOTAL.fetch_add(files.len() as u64, Ordering::Relaxed);
    std::thread::spawn(move || {
        for file_path in files {
            media_api::ensure_cover_thumbnail(file_path.clone(), 480);
            THUMB_COMPLETED.fetch_add(1, Ordering::Relaxed);
        }
    });
}

/// 处理媒体文件请求 GET /node/media
pub async fn handle_media_request(req: Request<Body>) -> Result<Response<Body>, Infallible> {
    let query = req.uri().query().unwrap_or("");
    let params: std::collections::HashMap<String, String> =
        url::form_urlencoded::parse(query.as_bytes())
            .into_owned()
            .collect();

    let file_path = match params.get("path") {
        Some(path) if !path.is_empty() => path.clone(),
        _ => {
            return Ok(error_plain(StatusCode::BAD_REQUEST, "missing path"));
        }
    };

    let path = Path::new(&file_path);
    if !path.exists() {
        return Ok(error_plain(StatusCode::NOT_FOUND, "file not found"));
    }

    let metadata = match fs::metadata(path) {
        Ok(m) => m,
        Err(_) => {
            return Ok(error_plain(
                StatusCode::INTERNAL_SERVER_ERROR,
                "cannot read file metadata",
            ));
        }
    };

    let total_length = metadata.len();
    let content_type = guess_media_content_type(&file_path);

    // 检查是否需要缩略图
    let requested_width = params.get("width").and_then(|s| s.parse::<u32>().ok());
    let is_cover_mode = params.get("mode").map(|m| m == "cover").unwrap_or(false);

    // 检查 Range 请求头
    let range_header = req
        .headers()
        .get("range")
        .and_then(|v| v.to_str().ok())
        .map(|s| s.to_string());
    let is_range_request = range_header.is_some();

    // 如果是图片或封面请求且不是 Range 请求，尝试返回缩略图
    if !is_range_request && (is_image_file(&file_path) || (is_cover_mode && is_av_file(&file_path)))
    {
        let final_width = requested_width.unwrap_or(if is_cover_mode { 240 } else { 0 });
        if final_width > 0 {
            return serve_resized_cover(&file_path, final_width).await;
        }
    }

    // 处理 Range 请求（视频/音频流式切片）
    if let Some(ref range) = range_header {
        return serve_range_request(path, range, total_length, &content_type);
    }

    // 视频/音频文件：无 Range 请求时主动返回 206 首切片（促使客户端改用 Range 请求）
    // 这样视频播放器可以立即开始播放而无需等待整个文件传输完毕
    if is_video_file(&file_path) || is_audio_file(&file_path) {
        let end = (VIDEO_CHUNK_SIZE - 1).min(total_length.saturating_sub(1));
        return serve_range_request(
            path,
            &format!("bytes=0-{}", end),
            total_length,
            &content_type,
        );
    }

    // 图片/普通文件：直接读取返回（通常体积小，不必切片）
    match fs::read(path) {
        Ok(bytes) => Ok(Response::builder()
            .status(StatusCode::OK)
            .header("Content-Type", &content_type)
            .header("Content-Length", total_length.to_string())
            .header("Accept-Ranges", "bytes")
            .body(Body::from(bytes))
            .unwrap()),
        Err(_) => Ok(error_plain(
            StatusCode::INTERNAL_SERVER_ERROR,
            "failed to read file",
        )),
    }
}

/// 服务缩略图
async fn serve_resized_cover(file_path: &str, width: u32) -> Result<Response<Body>, Infallible> {
    // 调用 Rust 的缩略图生成函数（带进度统计）
    if let Some(thumb_path) = ensure_cover_thumbnail_tracked(file_path, width) {
        if !thumb_path.is_empty() {
            let thumb_file = Path::new(&thumb_path);
            if thumb_file.exists() {
                if let Ok(bytes) = fs::read(thumb_file) {
                    return Ok(Response::builder()
                        .status(StatusCode::OK)
                        .header("Content-Type", "image/jpeg")
                        .header("Content-Length", bytes.len().to_string())
                        .body(Body::from(bytes))
                        .unwrap());
                }
            }
        }
    }

    // 如果是音频/视频文件且无法生成封面，返回 404
    if is_av_file(file_path) {
        return Ok(error_plain(StatusCode::NOT_FOUND, "no cover available"));
    }

    // 对于图片文件，回退到原图
    match fs::read(file_path) {
        Ok(bytes) => {
            let content_type = guess_media_content_type(file_path);
            Ok(Response::builder()
                .status(StatusCode::OK)
                .header("Content-Type", &content_type)
                .header("Content-Length", bytes.len().to_string())
                .body(Body::from(bytes))
                .unwrap())
        }
        Err(_) => Ok(error_plain(
            StatusCode::INTERNAL_SERVER_ERROR,
            "failed to read file",
        )),
    }
}

/// 处理 Range 请求：使用文件 seek 只读取所需字节范围，避免将整个大文件载入内存
/// 同时限制单次响应体积（VIDEO_CHUNK_SIZE），让视频播放器通过多个 Range 请求流式播放
fn serve_range_request(
    path: &Path,
    range: &str,
    total_length: u64,
    content_type: &str,
) -> Result<Response<Body>, Infallible> {
    use std::io::{Read, Seek, SeekFrom};

    // 解析 Range: bytes=start-end
    let re = regex::Regex::new(r"bytes=(\d*)-(\d*)").unwrap();
    if let Some(captures) = re.captures(range) {
        let start: u64 = captures
            .get(1)
            .and_then(|m| m.as_str().parse().ok())
            .unwrap_or(0);
        let requested_end: u64 = captures
            .get(2)
            .and_then(|m| m.as_str().parse().ok())
            .unwrap_or(total_length.saturating_sub(1));

        let bounded_end = requested_end.min(total_length.saturating_sub(1));
        // 对视频/音频限制单次切片大小，防止一次性传输超大文件
        let capped_end = if is_av_content_type(content_type) {
            bounded_end.min(start + VIDEO_CHUNK_SIZE - 1)
        } else {
            bounded_end
        };
        let range_length = (capped_end - start + 1) as usize;

        // 打开文件并 seek 到 start，只读取所需字节
        let mut file = match fs::File::open(path) {
            Ok(f) => f,
            Err(_) => {
                return Ok(error_plain(
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "failed to open file",
                ));
            }
        };

        if file.seek(SeekFrom::Start(start)).is_err() {
            return Ok(error_plain(
                StatusCode::INTERNAL_SERVER_ERROR,
                "failed to seek in file",
            ));
        }

        let mut buffer = vec![0u8; range_length];
        if file.read_exact(&mut buffer).is_err() {
            return Ok(error_plain(
                StatusCode::INTERNAL_SERVER_ERROR,
                "failed to read file range",
            ));
        }

        Ok(Response::builder()
            .status(StatusCode::PARTIAL_CONTENT)
            .header("Content-Type", content_type)
            .header("Content-Length", range_length.to_string())
            .header(
                "Content-Range",
                format!("bytes {}-{}/{}", start, capped_end, total_length),
            )
            .header("Accept-Ranges", "bytes")
            .body(Body::from(buffer))
            .unwrap())
    } else {
        Ok(error_plain(StatusCode::BAD_REQUEST, "invalid range header"))
    }
}

/// 判断 Content-Type 是否为视频/音频（需要切片限制）
fn is_av_content_type(ct: &str) -> bool {
    ct.starts_with("video/") || ct.starts_with("audio/")
}

/// 创建纯文本错误响应
fn error_plain(status: StatusCode, message: &str) -> Response<Body> {
    Response::builder()
        .status(status)
        .header("Content-Type", "text/plain; charset=utf-8")
        .body(Body::from(message.to_string()))
        .unwrap()
}

/// 猜测媒体文件的 Content-Type
pub fn guess_media_content_type(path: &str) -> String {
    let lower = path.to_lowercase();
    if lower.ends_with(".jpg") || lower.ends_with(".jpeg") {
        "image/jpeg"
    } else if lower.ends_with(".png") {
        "image/png"
    } else if lower.ends_with(".gif") {
        "image/gif"
    } else if lower.ends_with(".webp") {
        "image/webp"
    } else if lower.ends_with(".bmp") {
        "image/bmp"
    } else if lower.ends_with(".heic") || lower.ends_with(".heif") {
        "image/heic"
    } else if lower.ends_with(".avif") {
        "image/avif"
    } else if lower.ends_with(".mp4") || lower.ends_with(".m4v") {
        "video/mp4"
    } else if lower.ends_with(".mov") {
        "video/quicktime"
    } else if lower.ends_with(".mkv") {
        "video/x-matroska"
    } else if lower.ends_with(".avi") {
        "video/x-msvideo"
    } else if lower.ends_with(".webm") {
        "video/webm"
    } else if lower.ends_with(".mp3") {
        "audio/mpeg"
    } else if lower.ends_with(".flac") {
        "audio/flac"
    } else if lower.ends_with(".m4a") || lower.ends_with(".aac") {
        "audio/mp4"
    } else if lower.ends_with(".ogg") || lower.ends_with(".opus") {
        "audio/ogg"
    } else if lower.ends_with(".wav") {
        "audio/wav"
    } else {
        "application/octet-stream"
    }
    .to_string()
}

/// 判断是否是图片文件
fn is_image_file(path: &str) -> bool {
    const IMAGE_EXTS: [&str; 9] = [
        "jpg", "jpeg", "png", "webp", "bmp", "gif", "heic", "heif", "avif",
    ];
    let lower = path.to_lowercase();
    IMAGE_EXTS.iter().any(|ext| lower.ends_with(ext))
}

/// 判断是否是视频文件
fn is_video_file(path: &str) -> bool {
    const VIDEO_EXTS: [&str; 9] = [
        "mp4", "mov", "m4v", "mkv", "avi", "webm", "wmv", "flv", "ts",
    ];
    let lower = path.to_lowercase();
    VIDEO_EXTS.iter().any(|ext| lower.ends_with(*ext))
}

/// 判断是否是音频文件
fn is_audio_file(path: &str) -> bool {
    const AUDIO_EXTS: [&str; 11] = [
        "mp3", "flac", "aac", "m4a", "ogg", "opus", "wav", "wma", "ape", "aiff", "alac",
    ];
    let lower = path.to_lowercase();
    AUDIO_EXTS.iter().any(|ext| lower.ends_with(*ext))
}

/// 判断是否是音频/视频文件（统一判断）
fn is_av_file(path: &str) -> bool {
    is_video_file(path) || is_audio_file(path)
}

/// 简单媒体请求处理器（不依赖 hyper Request）。
/// query 为 URL query string，例如 "path=/foo.jpg&width=240"。
/// 返回原始字节或错误字符串。
pub async fn handle_media_query(query: &str) -> Result<Vec<u8>, String> {
    use std::path::Path;

    let params: std::collections::HashMap<String, String> =
        url::form_urlencoded::parse(query.as_bytes())
            .into_owned()
            .collect();

    let file_path = params
        .get("path")
        .filter(|p| !p.is_empty())
        .ok_or_else(|| "missing path".to_string())?;

    let path = Path::new(file_path);
    if !path.exists() {
        return Err(format!("file not found: {}", file_path));
    }

    let requested_width = params.get("width").and_then(|s| s.parse::<u32>().ok());
    let is_cover_mode = params.get("mode").map(|m| m == "cover").unwrap_or(false);

    if is_cover_mode || is_image_file(file_path) {
        let width = requested_width.unwrap_or(if is_cover_mode { 240 } else { 0 });
        if width > 0 {
            if let Some(thumb_path) = ensure_cover_thumbnail_tracked(file_path, width) {
                if !thumb_path.is_empty() {
                    if let Ok(bytes) = std::fs::read(&thumb_path) {
                        return Ok(bytes);
                    }
                }
            }
        }
        if is_av_file(file_path) {
            return Err("no cover available".to_string());
        }
    }

    std::fs::read(path).map_err(|e| format!("read file failed: {}", e))
}

/// 判断文件路径是否为图片（公开，供 mod.rs 调用）。
pub fn is_image_path(path: &str) -> bool {
    is_image_file(path)
}

/// 支持 Range 请求的文件服务（供无 hyper 的原生 TCP 服务器调用）。
/// 返回 (状态行, 头部 key-value 列表, 响应体字节)。
/// 单次最大返回 VIDEO_CHUNK_SIZE，视频播放器通过多次 Range 请求流式拉取。
pub fn serve_media_file_with_range(
    file_path: &str,
    range: Option<&str>,
) -> Result<(String, Vec<(String, String)>, Vec<u8>), String> {
    use std::io::{Read, Seek, SeekFrom};

    let path = std::path::Path::new(file_path);
    if !path.exists() {
        return Err(format!("file not found: {}", file_path));
    }
    let metadata = std::fs::metadata(path).map_err(|e| format!("metadata error: {}", e))?;
    let total_length = metadata.len();
    let content_type = guess_media_content_type(file_path);

    // 解析 Range 头，例如 "bytes=0-1048575"
    let (start, end_requested) = if let Some(range_str) = range {
        let re = regex::Regex::new(r"bytes=(\d*)-(\d*)").unwrap();
        if let Some(caps) = re.captures(range_str) {
            let s: u64 = caps
                .get(1)
                .and_then(|m| m.as_str().parse().ok())
                .unwrap_or(0);
            let e: u64 = caps
                .get(2)
                .and_then(|m| m.as_str().parse().ok())
                .unwrap_or(total_length.saturating_sub(1));
            (s, e)
        } else {
            (0, total_length.saturating_sub(1))
        }
    } else {
        // 无 Range 时主动返回首个切片，促使播放器转用 Range 请求
        (
            0,
            (VIDEO_CHUNK_SIZE - 1).min(total_length.saturating_sub(1)),
        )
    };

    let bounded_end = end_requested.min(total_length.saturating_sub(1));
    // 对视频/音频限制单次最大传输量，防止将整个大文件载入内存
    let is_av = is_video_file(file_path) || is_audio_file(file_path);
    let capped_end = if is_av {
        bounded_end.min(start + VIDEO_CHUNK_SIZE - 1)
    } else {
        bounded_end
    };
    let range_length = (capped_end - start + 1) as usize;

    let mut file = std::fs::File::open(path).map_err(|e| format!("open file failed: {}", e))?;
    file.seek(SeekFrom::Start(start))
        .map_err(|e| format!("seek failed: {}", e))?;
    let mut buffer = vec![0u8; range_length];
    file.read_exact(&mut buffer)
        .map_err(|e| format!("read failed: {}", e))?;

    let status = if range.is_some() {
        "206 Partial Content"
    } else {
        "206 Partial Content"
    };
    let headers = vec![
        ("Content-Type".to_string(), content_type),
        ("Content-Length".to_string(), range_length.to_string()),
        (
            "Content-Range".to_string(),
            format!("bytes {}-{}/{}", start, capped_end, total_length),
        ),
        ("Accept-Ranges".to_string(), "bytes".to_string()),
    ];
    Ok((status.to_string(), headers, buffer))
}
