use hyper::{Body, Request, Response, StatusCode};
use media_collection::api as media_api;
use std::convert::Infallible;
use std::fs;
use std::path::Path;

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
    if !is_range_request
        && (is_image_file(&file_path)
            || (is_cover_mode && is_av_file(&file_path)))
    {
        let final_width = requested_width.unwrap_or(if is_cover_mode { 240 } else { 0 });
        if final_width > 0 {
            return serve_resized_cover(&file_path, final_width).await;
        }
    }

    // 处理 Range 请求
    if let Some(ref range) = range_header {
        return serve_range_request(path, range, total_length, &content_type);
    }

    // 返回完整文件
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
    // 调用 Rust 的缩略图生成函数
    if let Some(thumb_path) = media_api::ensure_cover_thumbnail(file_path.to_string(), width) {
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

/// 处理 Range 请求
fn serve_range_request(
    path: &Path,
    range: &str,
    total_length: u64,
    content_type: &str,
) -> Result<Response<Body>, Infallible> {
    // 解析 Range: bytes=start-end
    let re = regex::Regex::new(r"bytes=(\d*)-(\d*)").unwrap();
    if let Some(captures) = re.captures(range) {
        let start: u64 = captures
            .get(1)
            .and_then(|m| m.as_str().parse().ok())
            .unwrap_or(0);
        let end: u64 = captures
            .get(2)
            .and_then(|m| m.as_str().parse().ok())
            .unwrap_or(total_length.saturating_sub(1));

        let bounded_end = end.min(total_length.saturating_sub(1));
        let range_length = bounded_end - start + 1;

        match fs::read(path) {
            Ok(bytes) => {
                let slice = bytes[(start as usize)..=(bounded_end as usize)].to_vec();
                Ok(Response::builder()
                    .status(StatusCode::PARTIAL_CONTENT)
                    .header("Content-Type", content_type)
                    .header("Content-Length", range_length.to_string())
                    .header(
                        "Content-Range",
                        format!("bytes {}-{}/{}", start, bounded_end, total_length),
                    )
                    .header("Accept-Ranges", "bytes")
                    .body(Body::from(slice))
                    .unwrap())
            }
            Err(_) => Ok(error_plain(
                StatusCode::INTERNAL_SERVER_ERROR,
                "failed to read file",
            )),
        }
    } else {
        Ok(error_plain(StatusCode::BAD_REQUEST, "invalid range header"))
    }
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

/// 判断是否是音频/视频文件
fn is_av_file(path: &str) -> bool {
    const AV_EXTS: [&str; 20] = [
        "mp4", "mov", "m4v", "mkv", "avi", "webm", "wmv", "flv", "ts",
        "mp3", "flac", "aac", "m4a", "ogg", "opus", "wav", "wma", "ape", "aiff", "alac",
    ];
    let lower = path.to_lowercase();
    AV_EXTS.iter().any(|ext| lower.ends_with(*ext))
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
            if let Some(thumb_path) = media_collection::api::ensure_cover_thumbnail(file_path.to_string(), width) {
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
