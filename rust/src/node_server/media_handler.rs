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

/// 按需生成节点缩略图：只走内存缓存（1 小时 TTL），不落盘、不污染本地邻近缓存。
///
/// 不计入批量进度：浏览时每个封面请求都会走到这里，若一并计数，
/// 客户端状态栏会长期显示「节点封面生成中」且数字只增不减。
fn generate_thumbnail_bytes_on_demand(file_path: &str, width: u32) -> Option<Vec<u8>> {
    media_api::generate_thumbnail_bytes(file_path.to_string(), width)
}

/// 开始一批批量生成任务：上一批已全部完成时先清零，再累加本批总数。
///
/// 节点进度计数器是进程级累计值；不复位的话客户端看到的永远是
/// 「已完成数与历史总数的比例」，比如新一批 10 个任务却显示 400/500。
fn begin_bulk_batch(count: u64) {
    static BATCH_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());
    let _guard = BATCH_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let completed = THUMB_COMPLETED.load(Ordering::Relaxed);
    let total = THUMB_TOTAL.load(Ordering::Relaxed);
    if completed >= total {
        THUMB_TOTAL.store(0, Ordering::Relaxed);
        THUMB_COMPLETED.store(0, Ordering::Relaxed);
    }
    THUMB_TOTAL.fetch_add(count, Ordering::Relaxed);
}

/// 后台为一批媒体文件生成缩略图并计入进度统计（导入后全量生成用）。
///
/// [width] 必须与客户端封面请求的实际宽度一致：内存缓存 key 含宽度，
/// 预热用别的宽度会导致客户端请求仍然未命中、只能现场重新生成。
///
/// 并发度取 CPU 逻辑核数：缩略图生成是 CPU 密集（解码+缩放）而非纯 IO 等待，
/// 单线程串行时 N 张图的总耗时就是 N 倍。ffmpeg 子进程另有全局信号量限流，
/// 因此并行的是「常规位图的纯 Rust 缩放」这条大头路径。
pub fn spawn_bulk_thumbnail_generation(files: Vec<String>, width: u32) {
    // 原图档（width=0）无需预生成；空列表直接返回，不白起线程、不动计数器
    if files.is_empty() || width == 0 {
        return;
    }
    begin_bulk_batch(files.len() as u64);

    let workers = std::thread::available_parallelism()
        .map(|n| n.get())
        .unwrap_or(4)
        .min(files.len());
    let pending = std::sync::Arc::new(std::sync::Mutex::new(
        files.into_iter().collect::<std::collections::VecDeque<String>>(),
    ));

    // 保持原有的「立即返回、后台跑完」语义：scope 会等待 worker 结束，
    // 因此整块并行放到一个后台线程里执行。
    std::thread::spawn(move || {
        std::thread::scope(|scope| {
            for _ in 0..workers {
                let pending = std::sync::Arc::clone(&pending);
                scope.spawn(move || loop {
                    // 每个 worker 取一个再做，避免静态切片在文件耗时不均时出现长尾
                    let Some(file_path) =
                        pending.lock().unwrap_or_else(|e| e.into_inner()).pop_back()
                    else {
                        break;
                    };
                    media_api::generate_thumbnail_bytes(file_path, width);
                    THUMB_COMPLETED.fetch_add(1, Ordering::Relaxed);
                });
            }
        });
    });
}

/// 媒体路径校验的失败类别。
///
/// 只给语义、不绑状态码：两个调用方对状态码的映射不同——
/// hyper 分支能直接回 400/404，原生 TCP 分支只能返回错误字符串再由
/// `mod.rs` 拼响应，所以判定逻辑放在这里共用，映射各自处理。
#[derive(Debug, PartialEq, Eq)]
pub enum MediaPathError {
    /// 缺 `path` 参数
    Missing,
    /// 含 NUL 或不是绝对路径
    Invalid,
    /// 路径不存在，或存在但不是普通文件
    NotFound,
}

impl MediaPathError {
    pub fn message(&self) -> String {
        match self {
            MediaPathError::Missing => "missing path".to_string(),
            MediaPathError::Invalid => "path must be absolute without NUL".to_string(),
            MediaPathError::NotFound => "file not found".to_string(),
        }
    }
}

/// 媒体路径的唯一校验口。
///
/// **为什么必须共用**：这段逻辑原先只写在 hyper 分支
/// （`handle_media_request`）里，而生产跑的是原生 TCP 分支
/// （`handle_media_query_blocking`）——两套实现各写一份的结果就是
/// 「修在了没人走的路上，真在跑的路径照样不校验」。
///
/// 三道检查缺一不可：
/// 1. NUL——`Path::new` 收 NUL 后到系统调用才报错，报错位置更靠近 IO 层，
///    不利于回一个干净 400；
/// 2. 绝对路径——相对路径会按节点进程的 CWD 解析，等于让调用方借节点的工作目录
///    猜文件位置；
/// 3. 存在且是普通文件——目录也能通过 `exists()`，但后续 `fs::read` 会失败，
///    提前判掉能让错误语义准确（404 而不是 500）。
pub fn validate_media_path(raw: &str) -> Result<&Path, MediaPathError> {
    if raw.is_empty() {
        return Err(MediaPathError::Missing);
    }
    if raw.contains('\0') {
        return Err(MediaPathError::Invalid);
    }
    let path = Path::new(raw);
    if !path.is_absolute() {
        return Err(MediaPathError::Invalid);
    }
    if !path.is_file() {
        return Err(MediaPathError::NotFound);
    }
    Ok(path)
}

/// 处理媒体文件请求 GET /node/media
pub async fn handle_media_request(req: Request<Body>) -> Result<Response<Body>, Infallible> {
    let query = req.uri().query().unwrap_or("");
    let params: std::collections::HashMap<String, String> =
        url::form_urlencoded::parse(query.as_bytes())
            .into_owned()
            .collect();

    let file_path = params.get("path").cloned().unwrap_or_default();

    let path = match validate_media_path(&file_path) {
        Ok(p) => p,
        Err(e) => {
            let status = match e {
                MediaPathError::Missing | MediaPathError::Invalid => StatusCode::BAD_REQUEST,
                MediaPathError::NotFound => StatusCode::NOT_FOUND,
            };
            return Ok(error_plain(status, &e.message()));
        }
    };

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

    // 图片/普通文件：在后台线程异步读取，避免阻塞 tokio worker，并限制单次内存读取上限
    if total_length > MAX_DIRECT_READ_BYTES {
        return Ok(error_plain(
            StatusCode::PAYLOAD_TOO_LARGE,
            "file too large for direct read, please use range request",
        ));
    }
    let path_buf = path.to_path_buf();
    let read_result = tokio::task::spawn_blocking(move || fs::read(&path_buf))
        .await
        .unwrap_or_else(|e| Err(std::io::Error::new(std::io::ErrorKind::Other, e)));

    match read_result {
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
    // 同 handle_media_query：生成与读取都阻塞，移入 spawn_blocking 以免占住 worker
    let file_path = file_path.to_string();
    let result = tokio::task::spawn_blocking(move || {
        read_cover_bytes_blocking(&file_path, width)
    })
    .await
    .unwrap_or(None);

    match result {
        Some((bytes, content_type)) => Ok(Response::builder()
            .status(StatusCode::OK)
            .header("Content-Type", content_type)
            .header("Content-Length", bytes.len().to_string())
            .body(Body::from(bytes))
            .unwrap()),
        None => Ok(error_plain(StatusCode::NOT_FOUND, "no cover available")),
    }
}

/// 读取（必要时生成）封面缩略图字节。返回 None 表示音视频无内嵌封面。
fn read_cover_bytes_blocking(file_path: &str, width: u32) -> Option<(Vec<u8>, String)> {
    // 节点服务期缩略图只走内存缓存（1 小时 TTL），不写资源旁邻近缓存，避免污染本地资源缩略图
    if let Some(bytes) = generate_thumbnail_bytes_on_demand(file_path, width) {
        return Some((bytes, "image/jpeg".to_string()));
    }

    // 如果是音频/视频文件且无法生成封面，返回 404
    if is_av_file(file_path) {
        return None;
    }

    // 对于图片文件，回退到原图
    fs::read(file_path)
        .ok()
        .map(|bytes| (bytes, guess_media_content_type(file_path)))
}

/// Range 头解析用正则，只编译一次。
/// 原先 `Regex::new` 写在每个媒体请求的处理路径上，模式编译+堆分配是纯浪费。
static RANGE_RE: std::sync::OnceLock<regex::Regex> = std::sync::OnceLock::new();

fn range_regex() -> &'static regex::Regex {
    RANGE_RE.get_or_init(|| {
        regex::Regex::new(r"bytes=(\d*)-(\d*)").expect("固定的 Range 正则应可编译")
    })
}

/// 把请求的 `[start, requested_end]` 裁剪到文件实际范围内，并套用单次传输上限。
///
/// 关键是不变式 `start <= capped_end`：两个调用方都用 `capped_end - start + 1`
/// 求长度，起点越界时这个 u64 减法会回绕成天文数字（release 下变成超大分配、
/// debug 下直接 panic），远程反复触发即可拖垮服务。
fn clamp_range(
    start: u64,
    requested_end: u64,
    total_length: u64,
    limit_chunk: bool,
) -> (u64, u64) {
    let bounded_end = requested_end.min(total_length.saturating_sub(1));
    let start = start.min(bounded_end);
    let capped_end = if limit_chunk {
        bounded_end.min(start.saturating_add(VIDEO_CHUNK_SIZE - 1))
    } else {
        bounded_end
    };
    (start, capped_end)
}

/// 解析 `Range: bytes=start-end` 并裁剪；格式不合法时返回 None。
fn resolve_range(
    range: &str,
    total_length: u64,
    limit_chunk: bool,
) -> Option<(u64, u64)> {
    let captures = range_regex().captures(range)?;
    let start: u64 = captures.get(1)?.as_str().parse().ok()?;
    let requested_end: u64 = captures
        .get(2)
        .and_then(|m| m.as_str().parse().ok())
        .unwrap_or(total_length.saturating_sub(1));
    Some(clamp_range(start, requested_end, total_length, limit_chunk))
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
    if let Some((start, capped_end)) = resolve_range(range, total_length, is_av_content_type(content_type))
    {
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
    let params: std::collections::HashMap<String, String> =
        url::form_urlencoded::parse(query.as_bytes())
            .into_owned()
            .collect();

    let file_path = params
        .get("path")
        .filter(|p| !p.is_empty())
        .cloned()
        .ok_or_else(|| "missing path".to_string())?;

    let requested_width = params.get("width").and_then(|s| s.parse::<u32>().ok());
    let is_cover_mode = params.get("mode").map(|m| m == "cover").unwrap_or(false);

    // stat + 缩略图生成（解码/缩放，内部还要同步等待 ffmpeg 子进程）+ 文件读取
    // 全是阻塞操作。跑在 runtime worker 上会让本可并发的其它请求排队等待，
    // 因此整体移入 spawn_blocking。
    tokio::task::spawn_blocking(move || {
        handle_media_query_blocking(&file_path, requested_width, is_cover_mode)
    })
    .await
    .map_err(|e| format!("媒体任务 join 失败: {}", e))?
}

fn handle_media_query_blocking(
    file_path: &str,
    requested_width: Option<u32>,
    is_cover_mode: bool,
) -> Result<Vec<u8>, String> {
    // 生产路径的入口校验：与 hyper 分支共用同一个判定函数。
    // 历史上这段逻辑只写在 hyper 分支，而真实请求走的是这里，
    // 等于「校验写在没人走的路上」——详见 validate_media_path 的注释。
    let path = validate_media_path(file_path).map_err(|e| e.message())?;

    if is_cover_mode || is_image_file(file_path) {
        let width = requested_width.unwrap_or(if is_cover_mode { 240 } else { 0 });
        if width > 0 {
            // 节点服务期缩略图只走内存缓存，不落盘、不污染本地邻近缓存
            if let Some(bytes) = generate_thumbnail_bytes_on_demand(file_path, width) {
                return Ok(bytes);
            }
        }
        if is_av_file(file_path) {
            return Err("no cover available".to_string());
        }
    }

    // 回退读原图前先卡体积：整文件读进内存是这条路径唯一的无界分配点。
    // 超限交给调用方回 413（mod.rs 按错误文案前缀分流），
    // 与 hyper 分支的 MAX_DIRECT_READ_BYTES 保持同一个阈值。
    let file_size = std::fs::metadata(path)
        .map_err(|e| format!("metadata error: {}", e))?
        .len();
    if file_size > MAX_DIRECT_READ_BYTES {
        return Err(payload_too_large_message(file_size));
    }

    std::fs::read(path).map_err(|e| format!("read file failed: {}", e))
}

/// 内部整文件读取的体积上限（50 MiB）。
///
/// 这条路径是「不带 width 的图片/普通文件直读」，超限后不回退到整读，
/// 而是让调用方回 413 提示改用缩略图或 Range。50 MiB 的依据：
/// 走这条路径的是原图预览（最大一般是相机 RAW 转出的 30 MiB 级 JPG/PNG），
/// 再大的文件客户端本就该带 width 参数走缩略图分支。
const MAX_DIRECT_READ_BYTES: u64 = 50 * 1024 * 1024;

/// 体积超限的错误文案前缀。
///
/// `mod.rs` 靠它把错误映射成 413 而不是 404：字符串错误在两个进程内模块之间
/// 流转，只能靠前缀区分语义，改前缀时两处必须同改（有测试钉住）。
const PAYLOAD_TOO_LARGE_PREFIX: &str = "payload too large";

fn payload_too_large_message(size: u64) -> String {
    format!(
        "{}: {} bytes exceeds limit {} bytes",
        PAYLOAD_TOO_LARGE_PREFIX, size, MAX_DIRECT_READ_BYTES
    )
}

/// 错误文案是否属于「体积超限」。
pub fn is_payload_too_large_error(message: &str) -> bool {
    message.starts_with(PAYLOAD_TOO_LARGE_PREFIX)
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

    // 与出图分支共用同一个入口校验：这条路径是真正的文件流服务，
    // 同样不能接受相对路径/NUL/目录。
    let path = validate_media_path(file_path).map_err(|e| e.message())?;
    let metadata = std::fs::metadata(path).map_err(|e| format!("metadata error: {}", e))?;
    let total_length = metadata.len();
    let content_type = guess_media_content_type(file_path);

    // 对视频/音频限制单次最大传输量，防止将整个大文件载入内存
    let is_av = is_video_file(file_path) || is_audio_file(file_path);
    let (start, capped_end) = match range {
        Some(range_str) => resolve_range(range_str, total_length, is_av)
            .ok_or_else(|| "invalid range header".to_string())?,
        // 无 Range 时的分档：
        // - 音视频：主动只回首个切片，促使播放器改用 Range 请求，避免整片进内存；
        // - 其它文件（字幕、文档、小图）：**整份给完**。历史上这里不分档，
        //   一律截到 2 MB，结果超过 2 MB 的非音视频文件被静默截断——
        //   客户端拿到的是一份残缺文件却仍然 206，属于静默数据损坏。
        None if is_av => clamp_range(
            0,
            (VIDEO_CHUNK_SIZE - 1).min(total_length.saturating_sub(1)),
            total_length,
            false,
        ),
        None => (0, total_length.saturating_sub(1)),
    };
    let range_length = (capped_end - start + 1) as usize;

    let mut file = std::fs::File::open(path).map_err(|e| format!("open file failed: {}", e))?;
    file.seek(SeekFrom::Start(start))
        .map_err(|e| format!("seek failed: {}", e))?;
    let mut buffer = vec![0u8; range_length];
    file.read_exact(&mut buffer)
        .map_err(|e| format!("read failed: {}", e))?;

    // 非音视频且客户端没要 Range：这是「整份文件」的语义，回 200 才准确。
    // 回 206 会让严格实现的分片下载器认为「还有后续片段」，反复重拉同一段。
    let whole_file = range.is_none() && !is_av;
    let status = if whole_file {
        "200 OK"
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

#[cfg(test)]
mod tests {
    use super::*;
    use hyper::{Body, Request};

    /// 构造带唯一后缀的临时媒体目录（与 handlers.rs 测试同一套路：
    /// 纯文件级依赖，不碰 db_module 全局绑定）
    fn test_dir(label: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "sw_media_{}_{}",
            std::process::id(),
            label
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    /// query 参数值走 form 解码，用官方 Serializer 做百分号编码最稳妥
    fn media_uri(path: &str) -> String {
        let mut ser = url::form_urlencoded::Serializer::new(String::new());
        ser.append_pair("path", path);
        format!("/node/media?{}", ser.finish())
    }

    fn path_query(path: &str) -> String {
        let mut ser = url::form_urlencoded::Serializer::new(String::new());
        ser.append_pair("path", path);
        ser.finish()
    }

    fn block_on<F: std::future::Future<Output = R>, R>(f: F) -> R {
        // 复用节点服务器全局 runtime（spawn_blocking 需要它）
        super::super::shared_runtime().block_on(f)
    }

    /// handle_media_request 返回 Result<_, Infallible>，测试里统一拆掉
    fn media_request(uri: &str, range: Option<&str>) -> Response<Body> {
        let mut builder = Request::builder().method("GET").uri(uri);
        if let Some(r) = range {
            builder = builder.header("range", r);
        }
        let req = builder.body(Body::empty()).unwrap();
        block_on(handle_media_request(req)).unwrap()
    }

    fn body_bytes(resp: Response<Body>) -> Vec<u8> {
        block_on(hyper::body::to_bytes(resp.into_body()))
            .unwrap()
            .to_vec()
    }

    fn sample_payload() -> Vec<u8> {
        (0u32..300).map(|i| (i % 251) as u8).collect()
    }

    // ── handle_media_request：hyper 全路径 ────────────────────────────────

    #[test]
    fn media_request_hit_returns_full_content() {
        let dir = test_dir("hit");
        let file = dir.join("a.jpg");
        let payload = sample_payload();
        fs::write(&file, &payload).unwrap();

        let resp = media_request(&media_uri(file.to_str().unwrap()), None);

        assert_eq!(resp.status(), StatusCode::OK);
        assert_eq!(
            resp.headers().get("Content-Type").unwrap().to_str().unwrap(),
            "image/jpeg"
        );
        assert_eq!(body_bytes(resp), payload);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn media_request_miss_returns_404() {
        // 不存在的文件必须 404，而不是 500 或空 200
        let resp = media_request(&media_uri("/tmp/sw_no_such_media_file.jpg"), None);
        assert_eq!(resp.status(), StatusCode::NOT_FOUND);
        assert_eq!(body_bytes(resp), b"file not found".to_vec());
    }

    #[test]
    fn media_request_missing_path_param_returns_400() {
        let resp = media_request("/node/media?width=100", None);
        assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
        let resp2 = media_request("/node/media?path=", None);
        assert_eq!(resp2.status(), StatusCode::BAD_REQUEST);
    }

    #[test]
    fn media_request_range_returns_partial_slice() {
        let dir = test_dir("range");
        let file = dir.join("b.jpg");
        let payload = sample_payload();
        fs::write(&file, &payload).unwrap();

        let resp = media_request(&media_uri(file.to_str().unwrap()), Some("bytes=10-19"));
        assert_eq!(resp.status(), StatusCode::PARTIAL_CONTENT);
        assert_eq!(
            resp.headers()
                .get("Content-Range")
                .unwrap()
                .to_str()
                .unwrap(),
            "bytes 10-19/300"
        );
        assert_eq!(body_bytes(resp), payload[10..20].to_vec());
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn media_request_av_without_range_returns_first_chunk() {
        // 视频文件无 Range 时主动回 206 首切片，促使播放器走流式拉取
        let dir = test_dir("av_first");
        let file = dir.join("c.mp4");
        let payload = vec![42u8; 100];
        fs::write(&file, &payload).unwrap();

        let resp = media_request(&media_uri(file.to_str().unwrap()), None);
        assert_eq!(resp.status(), StatusCode::PARTIAL_CONTENT);
        assert_eq!(
            resp.headers()
                .get("Content-Range")
                .unwrap()
                .to_str()
                .unwrap(),
            "bytes 0-99/100"
        );
        assert_eq!(body_bytes(resp), payload);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn media_request_out_of_bounds_range_is_clamped_not_panicked() {
        // clamp_range 的不变式回归：起点越界曾被 u64 减法回绕成超大分配
        let dir = test_dir("clamp");
        let file = dir.join("d.jpg");
        let payload = sample_payload();
        fs::write(&file, &payload).unwrap();

        let resp = media_request(&media_uri(file.to_str().unwrap()), Some("bytes=1000-2000"));
        assert_eq!(resp.status(), StatusCode::PARTIAL_CONTENT);
        assert_eq!(
            resp.headers()
                .get("Content-Range")
                .unwrap()
                .to_str()
                .unwrap(),
            "bytes 299-299/300"
        );
        assert_eq!(body_bytes(resp).len(), 1);
        let _ = fs::remove_dir_all(&dir);
    }

    // ── handle_media_query：query-string 轻量入口 ─────────────────────────

    #[test]
    fn media_query_hit_and_miss() {
        let dir = test_dir("q");
        let file = dir.join("e.bin");
        let payload = b"query-payload-bytes".to_vec();
        fs::write(&file, &payload).unwrap();

        // 命中：返回完整文件字节
        let got = block_on(handle_media_query(&path_query(file.to_str().unwrap()))).unwrap();
        assert_eq!(got, payload);

        // 未命中：报 file not found（上层据此回 404）
        let err = block_on(handle_media_query(&path_query("/tmp/sw_no_such_media_query.jpg")))
            .expect_err("未命中必须报错");
        assert!(err.contains("file not found"), "got: {err}");

        // 缺 path 参数
        assert_eq!(
            block_on(handle_media_query("width=100")).unwrap_err(),
            "missing path"
        );
        let _ = fs::remove_dir_all(&dir);
    }

    // ── serve_media_file_with_range：无 hyper 的原生 TCP 路径 ─────────────

    #[test]
    fn serve_with_range_hit_miss_and_bad_header() {
        let dir = test_dir("served");
        let file = dir.join("f.mp3");
        let payload = sample_payload();
        fs::write(&file, &payload).unwrap();
        let path = file.to_str().unwrap();

        // 命中 + Range：状态行/头部/字节三处都必须对齐
        let (status, headers, body) = serve_media_file_with_range(path, Some("bytes=5-14")).unwrap();
        assert_eq!(status, "206 Partial Content");
        let get = |k: &str| {
            headers
                .iter()
                .find(|(name, _)| name == k)
                .map(|(_, v)| v.clone())
        };
        assert_eq!(get("Content-Type").as_deref(), Some("audio/mpeg"));
        assert_eq!(get("Content-Range").as_deref(), Some("bytes 5-14/300"));
        assert_eq!(get("Content-Length").as_deref(), Some("10"));
        assert_eq!(body, payload[5..15].to_vec());

        // 命中无 Range：整文件首切片语义，仍回 206
        let (status2, headers2, body2) = serve_media_file_with_range(path, None).unwrap();
        assert_eq!(status2, "206 Partial Content");
        assert_eq!(
            headers2
                .iter()
                .find(|(n, _)| n == "Content-Range")
                .unwrap()
                .1,
            "bytes 0-299/300"
        );
        assert_eq!(body2, payload);

        // 未命中：Err(file not found)，对应连接层 404
        let miss = serve_media_file_with_range("/tmp/sw_no_such_served_file.mp3", None)
            .expect_err("未命中必须报错");
        assert!(miss.contains("file not found"), "got: {miss}");

        // 非法 Range 头：明确报错而不是静默回全文件
        assert!(serve_media_file_with_range(path, Some("garbage")).is_err());
        let _ = fs::remove_dir_all(&dir);
    }

    // ── validate_media_path：生产路径与 hyper 路径共用的唯一入口 ──────────

    #[test]
    fn validate_media_path_rejects_missing_relative_nul_and_dir() {
        let dir = test_dir("validate");
        let file = dir.join("ok.txt");
        fs::write(&file, b"hi").unwrap();

        // 正常绝对路径 + 普通文件
        assert!(validate_media_path(file.to_str().unwrap()).is_ok());

        // 缺参数
        assert_eq!(validate_media_path("").unwrap_err(), MediaPathError::Missing);

        // 相对路径：会按节点进程 CWD 解析，必须拒绝
        assert_eq!(validate_media_path("a.txt").unwrap_err(), MediaPathError::Invalid);
        assert_eq!(
            validate_media_path("./a.txt").unwrap_err(),
            MediaPathError::Invalid
        );

        // 含 NUL：到系统调用才报错，提前拦下换干净的 400
        let nul = format!("{}\0hack", dir.display());
        assert_eq!(validate_media_path(&nul).unwrap_err(), MediaPathError::Invalid);

        // 目录能过 exists() 但不是普通文件：要判 404 而不是让后面 fs::read 报 500
        assert_eq!(
            validate_media_path(dir.to_str().unwrap()).unwrap_err(),
            MediaPathError::NotFound
        );

        // 不存在的绝对路径
        assert_eq!(
            validate_media_path("/tmp/sw_no_such_validate_file.txt").unwrap_err(),
            MediaPathError::NotFound
        );

        let _ = fs::remove_dir_all(&dir);
    }

    /// 生产路径（handle_media_query / serve_media_file_with_range）必须同享校验，
    /// 否则等于「校验写在没人走的 hyper 分支上」，这一条就是钉住那件事。
    #[test]
    fn production_paths_reject_relative_path() {
        let err = block_on(handle_media_query(&path_query("relative/a.jpg"))).unwrap_err();
        assert!(err.contains("must be absolute"), "got: {err}");

        let err = serve_media_file_with_range("relative/a.srt", None).unwrap_err();
        assert!(err.contains("must be absolute"), "got: {err}");

        // 目录同样要拒绝（不是「能打开就往下走」）
        let dir = test_dir("prod_dir");
        let err = block_on(handle_media_query(&path_query(dir.to_str().unwrap()))).unwrap_err();
        assert!(err.contains("file not found"), "got: {err}");
        let _ = fs::remove_dir_all(&dir);
    }

    // ── 非音视频文件不带 Range 时整份返回，不再被截到 2MB ─────────────────

    #[test]
    fn non_av_without_range_returns_whole_file_not_2mb_chunk() {
        let dir = test_dir("whole");
        // 3 MiB：超过 VIDEO_CHUNK_SIZE（2 MiB），历史上会被静默截断
        let file = dir.join("big.srt");
        let payload = vec![b'a'; 3 * 1024 * 1024];
        fs::write(&file, &payload).unwrap();

        let (status, headers, body) = serve_media_file_with_range(file.to_str().unwrap(), None).unwrap();
        // 整份语义要回 200，回 206 会让分片下载器反复重拉同一段
        assert_eq!(status, "200 OK");
        let content_length = headers
            .iter()
            .find(|(k, _)| k == "Content-Length")
            .map(|(_, v)| v.clone())
            .expect("必须有 Content-Length");
        assert_eq!(content_length, payload.len().to_string());
        assert_eq!(body.len(), payload.len(), "非音视频文件被截断了");

        // 音视频仍保留 2 MiB 首切片的行为，不受这条改动影响
        let av = dir.join("clip.mp4");
        fs::write(&av, vec![0u8; 3 * 1024 * 1024]).unwrap();
        let (av_status, av_headers, av_body) =
            serve_media_file_with_range(av.to_str().unwrap(), None).unwrap();
        assert_eq!(av_status, "206 Partial Content");
        assert_eq!(av_body.len(), (VIDEO_CHUNK_SIZE) as usize);
        assert_eq!(
            av_headers
                .iter()
                .find(|(k, _)| k == "Content-Length")
                .unwrap()
                .1,
            VIDEO_CHUNK_SIZE.to_string()
        );

        let _ = fs::remove_dir_all(&dir);
    }

    // ── 直读原图：超 50 MiB 时报 payload too large 供上层映射 413 ─────────

    #[test]
    fn oversized_direct_read_reports_payload_too_large() {
        let dir = test_dir("oversize");
        let file = dir.join("huge.bin");
        // 稀疏文件：只声明长度，不真写 50 MiB，避免测试变慢吃磁盘
        {
            let f = fs::File::create(&file).unwrap();
            f.set_len(MAX_DIRECT_READ_BYTES + 1).unwrap();
        }

        let err = block_on(handle_media_query(&path_query(file.to_str().unwrap())))
            .expect_err("超限必须报错");
        assert!(is_payload_too_large_error(&err), "got: {err}");

        // 前缀与判定函数必须同源：改文案忘了改判定会让上层错回 404
        assert!(err.starts_with(PAYLOAD_TOO_LARGE_PREFIX));

        let _ = fs::remove_dir_all(&dir);
    }

    // ── 纯函数：内容类型猜测 ──────────────────────────────────────────────
    #[test]
    fn guess_content_type_basics() {
        assert_eq!(guess_media_content_type("/x/a.JPG"), "image/jpeg");
        assert_eq!(guess_media_content_type("/x/a.png"), "image/png");
        assert_eq!(guess_media_content_type("/x/a.mkv"), "video/x-matroska");
        assert_eq!(guess_media_content_type("/x/a.flac"), "audio/flac");
        assert_eq!(guess_media_content_type("/x/a.unknown_ext"), "application/octet-stream");
    }

    // ── 缩略图进度计数：不触媒体生成也要成对 ─────────────────────────────

    #[test]
    fn bulk_thumbnail_empty_input_is_noop() {
        // 空列表必须直接返回，不给 runtime 白起线程、不动计数器
        let (before_total, before_completed) = thumb_generation_progress();
        spawn_bulk_thumbnail_generation(vec![], 480);
        let (after_total, after_completed) = thumb_generation_progress();
        assert_eq!((before_total, before_completed), (after_total, after_completed));
    }
}
