use chrono::Utc;
use slime_logger::{sw_debug, sw_info, sw_warn};
use std::collections::HashMap;
use std::path::Path;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex, OnceLock, RwLock};

use crate::scanner::MediaFolderScanner;
use crate::types::{
    MediaCollection, MediaFolder, MediaItem, MediaKind, SmartFolder, SmartFolderFileType,
    SmartFolderRegexTarget,
};

// ── FFmpeg/FFprobe 可执行文件路径（由外部初始化时注入）───────────────────────
static FFMPEG_PATH: std::sync::RwLock<Option<String>> = std::sync::RwLock::new(None);
static FFPROBE_PATH: std::sync::RwLock<Option<String>> = std::sync::RwLock::new(None);

/// 注册 ffmpeg 可执行文件的绝对路径。
/// 必须在调用任何缩略图生成函数之前调用（通常在应用启动时由 api/ffmpeg.rs 注入）。
/// 可多次调用以更新路径（如 ffmpeg 下载完成后重新注册）。
pub fn register_ffmpeg_path(path: String) {
    if let Ok(mut guard) = FFMPEG_PATH.write() {
        *guard = Some(path);
    }
}

/// 注册 ffprobe 可执行文件的绝对路径。
pub fn register_ffprobe_path(path: String) {
    if let Ok(mut guard) = FFPROBE_PATH.write() {
        *guard = Some(path);
    }
}

/// 获取已注册的 ffmpeg 路径，若未注册则回退到系统 PATH 中的 "ffmpeg"。
pub fn ffmpeg_cmd() -> String {
    FFMPEG_PATH
        .read()
        .ok()
        .and_then(|g| g.clone())
        .unwrap_or_else(|| "ffmpeg".to_string())
}

/// 获取已注册的 ffprobe 路径，若未注册则回退到系统 PATH 中的 "ffprobe"。
pub fn ffprobe_cmd() -> String {
    FFPROBE_PATH
        .read()
        .ok()
        .and_then(|g| g.clone())
        .unwrap_or_else(|| "ffprobe".to_string())
}

/// 全局 ffmpeg 子进程并发上限（由 Flutter 端通过 register_ffmpeg_concurrency 设置）。
/// 默认 2，所有启动 ffmpeg/ffprobe 的函数（ensure_cover_thumbnail / extract_video_scrub_frames 等）
/// 共享此信号量，确保同一时刻 ffmpeg 进程数不超过此值。
static FFMPEG_CONCURRENCY: std::sync::RwLock<usize> = std::sync::RwLock::new(2);

/// 并发信号量：计数器 + 条件变量。OnceLock 保证只初始化一次，
/// 内部 Mutex/Condvar 本身线程安全，无需外层 RwLock。
static THUMB_PERMITS: OnceLock<(Mutex<usize>, Condvar)> = OnceLock::new();

/// 注册 ffmpeg 子进程并发上限。由 Flutter 端 mediaPrefs.concurrency 调用。
pub fn register_ffmpeg_concurrency(limit: usize) {
    let effective = limit.max(1);
    sw_info!(
        "[thumb-permit] 并发上限更新: {} → {}",
        max_concurrent_ffmpeg(),
        effective
    );
    if let Ok(mut guard) = FFMPEG_CONCURRENCY.write() {
        *guard = effective;
    }
    // 唤醒可能正在等待的线程，让它们用新的上限重新检查
    if let Some((_, cvar)) = THUMB_PERMITS.get() {
        cvar.notify_all();
    }
}

fn max_concurrent_ffmpeg() -> usize {
    FFMPEG_CONCURRENCY.read().map(|g| *g).unwrap_or(2)
}

fn acquire_thumb_permit() {
    let (lock, cvar) = THUMB_PERMITS.get_or_init(|| (Mutex::new(0), Condvar::new()));
    let mut count = cvar
        .wait_while(lock.lock().unwrap(), |c| *c >= max_concurrent_ffmpeg())
        .unwrap();
    *count += 1;
    sw_info!(
        "[thumb-permit] acquired | current={}/{}",
        *count,
        max_concurrent_ffmpeg()
    );
}

fn release_thumb_permit() {
    if let Some((lock, cvar)) = THUMB_PERMITS.get() {
        let mut count = lock.lock().unwrap();
        *count -= 1;
        sw_info!(
            "[thumb-permit] released | current={}/{}",
            *count,
            max_concurrent_ffmpeg()
        );
        cvar.notify_all();
    }
}

/// 全局 ffmpeg/ffprobe 子进程 PID 集合，用于应用退出时清理残留进程。
static FFMPEG_PIDS: RwLock<Vec<u32>> = RwLock::new(Vec::new());

/// 记录一个子进程 PID（在 ffmpeg/ffprobe 启动后调用）。
fn track_ffmpeg_pid(pid: u32) {
    if let Ok(mut guard) = FFMPEG_PIDS.write() {
        guard.push(pid);
    }
}

/// 从跟踪列表中移除一个 PID（在子进程结束后调用）。
fn untrack_ffmpeg_pid(pid: u32) {
    if let Ok(mut guard) = FFMPEG_PIDS.write() {
        guard.retain(|&p| p != pid);
    }
}

/// 清理所有残留的 ffmpeg/ffprobe 子进程。应用退出时调用。
pub fn kill_all_ffmpeg_processes() {
    let pids: Vec<u32> = FFMPEG_PIDS.read().map(|g| g.clone()).unwrap_or_default();
    if pids.is_empty() {
        return;
    }
    sw_info!(
        "[ffmpeg-cleanup] 清理 {} 个残留 ffmpeg/ffprobe 进程",
        pids.len()
    );
    for pid in pids {
        #[cfg(windows)]
        {
            // Windows: 使用 taskkill 强制终止进程树
            let _ = std::process::Command::new("taskkill")
                .args(["/F", "/T", "/PID", &pid.to_string()])
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null())
                .status();
        }
        #[cfg(not(windows))]
        {
            // Unix: 发送 SIGKILL
            unsafe {
                libc::kill(pid as i32, libc::SIGKILL);
            }
        }
        sw_info!("[ffmpeg-cleanup] 已终止 PID={}", pid);
    }
    if let Ok(mut guard) = FFMPEG_PIDS.write() {
        guard.clear();
    }
}

/// 启动 ffmpeg/ffprobe 子进程并跟踪 PID，等待其完成后返回退出状态。
/// 使用 spawn + wait 代替 .status()，以便在启动后立即获取 PID 用于清理跟踪。
pub fn run_tracked_command(
    cmd: &mut std::process::Command,
) -> std::io::Result<std::process::ExitStatus> {
    let mut child = cmd.spawn()?;
    let pid = child.id();
    if pid > 0 {
        track_ffmpeg_pid(pid);
    }
    let result = child.wait();
    // 进程结束后从跟踪列表移除（无论成功/失败）
    if pid > 0 {
        untrack_ffmpeg_pid(pid);
    }
    result
}

/// 启动 ffmpeg/ffprobe 子进程并跟踪 PID，等待其完成后返回输出。
/// 与 run_tracked_command 类似，但使用 wait_with_output() 捕获 stdout。
pub fn run_tracked_command_output(
    cmd: &mut std::process::Command,
) -> std::io::Result<std::process::Output> {
    let child = cmd.spawn()?;
    let pid = child.id();
    if pid > 0 {
        track_ffmpeg_pid(pid);
    }
    let result = child.wait_with_output();
    if pid > 0 {
        untrack_ffmpeg_pid(pid);
    }
    result
}

/// RAII 守卫，确保信号量在任意返回路径上均自动释放
struct ThumbPermit;
impl Drop for ThumbPermit {
    fn drop(&mut self) {
        release_thumb_permit();
    }
}

/// 资源旁的相邻缓存路径：`<资源父目录>/.SlimeWorks/tmp/<文件名>_w<宽度>.jpg`。
///
/// key 只用「文件名 + 宽度」（不含全路径 hash），保证缓存随资源目录一起移动时
/// 跨设备/跨盘符仍可命中（如 Mac 生成、Windows 读取）。同一目录内文件名唯一，不会冲突。
fn adjacent_cache_path(file_path: &std::path::Path, width: u32) -> Option<std::path::PathBuf> {
    let parent = file_path.parent()?;
    let file_name = file_path.file_name()?.to_string_lossy();
    if file_name.is_empty() {
        return None;
    }
    Some(
        parent
            .join(".SlimeWorks")
            .join("tmp")
            .join(format!("{}_w{}.jpg", file_name, width)),
    )
}

/// Windows 下给 `.SlimeWorks` 目录设置隐藏属性（macOS 靠 `.` 前缀天然隐藏，无需处理）。
#[cfg(target_os = "windows")]
fn ensure_hidden_attr(dir: &std::path::Path) {
    use std::os::windows::ffi::OsStrExt;
    let wide: Vec<u16> = dir
        .as_os_str()
        .encode_wide()
        .chain(std::iter::once(0))
        .collect();
    unsafe {
        let attrs = winapi::um::fileapi::GetFileAttributesW(wide.as_ptr());
        if attrs != winapi::um::fileapi::INVALID_FILE_ATTRIBUTES
            && attrs & winapi::um::winnt::FILE_ATTRIBUTE_HIDDEN == 0
        {
            winapi::um::fileapi::SetFileAttributesW(
                wide.as_ptr(),
                attrs | winapi::um::winnt::FILE_ATTRIBUTE_HIDDEN,
            );
        }
    }
}

/// 判断缓存文件是否有效命中（存在且非空）。零字节残留会被删除以便重新生成。
fn is_valid_cache_hit(cache_path: &std::path::Path) -> bool {
    if !cache_path.exists() {
        return false;
    }
    match std::fs::metadata(cache_path) {
        Ok(meta) if meta.len() > 0 => true,
        _ => {
            // zero-byte artefact from a previous failed write — remove and regenerate
            let _ = std::fs::remove_file(cache_path);
            false
        }
    }
}

/// 在集合目录树内搜索 `.SlimeWorks` 缓存目录（广度优先，限深限条目）。
///
/// 缓存目录按 `<资源父目录>/.SlimeWorks/tmp/` 规则建立在媒体文件实际所在目录旁，
/// 不一定位于集合根目录；且为懒创建（生成过缩略图才存在）。
/// 返回首个命中的路径；未命中返回 None（尚未生成过缩略图或目录被清理）。
pub fn find_collection_config_dir(root_dir: String) -> Option<String> {
    let root = std::path::Path::new(&root_dir);
    if !root.is_dir() {
        return None;
    }
    // 快速路径：集合根目录下直接存在 .SlimeWorks
    let direct = root.join(".SlimeWorks");
    if direct.is_dir() {
        return Some(direct.to_string_lossy().into_owned());
    }
    // 限深限条目搜索，避免超大集合目录树造成磁盘扫描开销过大
    const MAX_DEPTH: usize = 8;
    const MAX_ENTRIES: usize = 20000;
    let mut queue = std::collections::VecDeque::new();
    queue.push_back((root.to_path_buf(), 0usize));
    let mut visited_entries = 0usize;
    while let Some((dir, depth)) = queue.pop_front() {
        if depth >= MAX_DEPTH {
            continue;
        }
        let entries = match std::fs::read_dir(&dir) {
            Ok(e) => e,
            Err(_) => continue,
        };
        for entry in entries.flatten() {
            visited_entries += 1;
            if visited_entries > MAX_ENTRIES {
                return None;
            }
            let path = entry.path();
            if !path.is_dir() {
                continue;
            }
            let name = entry.file_name();
            if name == ".SlimeWorks" {
                return Some(path.to_string_lossy().into_owned());
            }
            // 跳过隐藏目录（含缓存目录自身）避免无谓递归；
            // 但媒体资源可能存放在隐藏子目录内的场景极少，可接受。
            if name.to_string_lossy().starts_with('.') {
                continue;
            }
            queue.push_back((path, depth + 1));
        }
    }
    None
}

/// 获取集合配置目录（`.SlimeWorks`），不存在时在集合根目录创建。
///
/// 优先复用 [find_collection_config_dir] 的搜索：若缓存目录已在某个子目录旁存在，
/// 直接返回而不重复创建；均未命中时在集合根目录创建（Windows 下设隐藏属性）。
/// 集合根目录不存在或创建失败时返回 None。
pub fn ensure_collection_config_dir(root_dir: String) -> Option<String> {
    if let Some(found) = find_collection_config_dir(root_dir.clone()) {
        return Some(found);
    }
    let root = std::path::Path::new(&root_dir);
    if !root.is_dir() {
        return None;
    }
    let dir = root.join(".SlimeWorks");
    match std::fs::create_dir_all(&dir) {
        Ok(_) => {
            #[cfg(target_os = "windows")]
            ensure_hidden_attr(&dir);
            sw_info!("[media_scan] 已创建配置目录: {}", dir.display());
            Some(dir.to_string_lossy().into_owned())
        }
        Err(e) => {
            sw_warn!("[media_scan] 创建配置目录失败: {}", e);
            None
        }
    }
}

/// Generate (or retrieve from disk cache) a JPEG thumbnail for `file_path`
/// resized to `width` px (aspect-preserving). Returns the path to the cached
/// thumbnail, or `None` if the original file is not a supported image or
/// ffmpeg/image processing fails.
pub fn ensure_cover_thumbnail(file_path: String, width: u32) -> Option<String> {
    // ① quick extension check
    let lower = file_path.to_lowercase();
    let is_image = lower.ends_with(".jpg")
        || lower.ends_with(".jpeg")
        || lower.ends_with(".png")
        || lower.ends_with(".webp")
        || lower.ends_with(".bmp")
        || lower.ends_with(".gif")
        || lower.ends_with(".heic")
        || lower.ends_with(".heif")
        || lower.ends_with(".avif");
    let is_video = lower.ends_with(".mp4")
        || lower.ends_with(".mkv")
        || lower.ends_with(".mov")
        || lower.ends_with(".avi")
        || lower.ends_with(".webm")
        || lower.ends_with(".m4v")
        || lower.ends_with(".flv")
        || lower.ends_with(".wmv")
        || lower.ends_with(".ts")
        || lower.ends_with(".m2ts")
        || lower.ends_with(".mpg")
        || lower.ends_with(".mpeg");
    let is_audio = lower.ends_with(".mp3")
        || lower.ends_with(".flac")
        || lower.ends_with(".aac")
        || lower.ends_with(".m4a")
        || lower.ends_with(".ogg")
        || lower.ends_with(".opus")
        || lower.ends_with(".wav")
        || lower.ends_with(".wma")
        || lower.ends_with(".ape")
        || lower.ends_with(".aiff")
        || lower.ends_with(".alac");
    if !is_image && !is_video && !is_audio {
        sw_debug!("[thumb] skip non-visual: {}", file_path);
        return None;
    }

    // ② 缓存路径：资源旁的相邻缓存（跨设备可移植，随资源目录一起移动）
    let src_path = std::path::Path::new(&file_path);
    let adjacent_path = adjacent_cache_path(src_path, width);

    // 记录原始文件大小（调试用）
    let orig_size = std::fs::metadata(&file_path).map(|m| m.len()).unwrap_or(0);

    // ③ disk cache hit — 相邻缓存命中时不再重新生成
    if let Some(ref p) = adjacent_path {
        if is_valid_cache_hit(p) {
            sw_debug!(
                "[thumb] cache-hit(adjacent) | src={} | orig={}B | w={}",
                file_path,
                orig_size,
                width
            );
            return Some(p.to_string_lossy().into_owned());
        }
    }

    // ③b 确定写入目标：相邻缓存目录；创建失败（只读盘等）时无法生成缓存
    let cache_path: std::path::PathBuf = match adjacent_path.as_ref() {
        Some(p) => {
            let mut writable = false;
            if let Some(dir) = p.parent() {
                if std::fs::create_dir_all(dir).is_ok() {
                    writable = true;
                    #[cfg(target_os = "windows")]
                    if let Some(sw_dir) = src_path.parent().map(|pp| pp.join(".SlimeWorks")) {
                        ensure_hidden_attr(&sw_dir);
                    }
                }
            }
            if writable {
                p.clone()
            } else {
                sw_warn!(
                    "[thumb] 相邻缓存目录不可写，跳过缓存生成 | src={}",
                    file_path
                );
                return None;
            }
        }
        None => {
            sw_warn!("[thumb] 无法计算相邻缓存路径，跳过缓存生成 | src={}", file_path);
            return None;
        }
    };

    // ④ 取获并发信号量，限制同时运行的缩略图生成任务数
    acquire_thumb_permit();
    let _permit = ThumbPermit; // 自动释放信号量，无论从哪条路径返回

    let t0 = std::time::Instant::now();
    sw_info!(
        "[thumb] generate | src={} | orig={}B | w={}",
        file_path,
        orig_size,
        width
    );

    // ⑤ for videos: extract a frame via ffmpeg (seek to 3s, fallback to 0s)
    if is_video {
        if try_ffmpeg_video_frame(&file_path, &cache_path, width, t0, orig_size) {
            return Some(cache_path.to_string_lossy().into_owned());
        }
        sw_warn!("[thumb] video frame extraction failed | src={}", file_path);
        return None;
    }

    // ④b for audio: extract embedded cover art via ffmpeg
    if is_audio {
        if try_ffmpeg_audio_cover(&file_path, &cache_path, width, t0, orig_size) {
            return Some(cache_path.to_string_lossy().into_owned());
        }
        sw_debug!(
            "[thumb] audio has no embedded cover art | src={}",
            file_path
        );
        return None;
    }

    // ⑤ try ffmpeg for images first (fastest, supports HEIC/AVIF via system codecs)
    if try_ffmpeg_resize(&file_path, &cache_path, width, t0, orig_size) {
        return Some(cache_path.to_string_lossy().into_owned());
    }

    // ⑥ fallback: pure-Rust `image` crate (supports JPEG/PNG/WebP/BMP/GIF)
    if try_rust_image_resize(&file_path, &cache_path, width, t0, orig_size) {
        return Some(cache_path.to_string_lossy().into_owned());
    }

    sw_warn!(
        "[thumb] all methods failed | src={} | w={} | elapsed={:?}",
        file_path,
        width,
        t0.elapsed()
    );
    None
}

fn try_ffmpeg_audio_cover(
    src: &str,
    dst: &std::path::Path,
    width: u32,
    t0: std::time::Instant,
    orig_size: u64,
) -> bool {
    // Extract embedded album art from audio file using ffmpeg.
    // The artwork is stored as a video stream (stream 0:v:0) in most formats.
    sw_info!("[ffmpeg-start] audio-cover | src={}", src);
    let ok = run_tracked_command(
        std::process::Command::new(ffmpeg_cmd())
            .args([
                "-i",
                src,
                "-map",
                "0:v:0",
                "-vf",
                &format!("scale={}:-1", width),
                "-q:v",
                "3",
                "-frames:v",
                "1",
                "-y",
                &dst.to_string_lossy(),
            ])
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null()),
    )
    .map(|s| s.success())
    .unwrap_or(false);
    let success = ok && dst.exists() && dst.metadata().map(|m| m.len() > 0).unwrap_or(false);
    if success {
        let thumb_size = dst.metadata().map(|m| m.len()).unwrap_or(0);
        sw_debug!(
            "[thumb] audio-cover OK | orig={}B | thumb={}B | w={} | elapsed={:?}",
            orig_size,
            thumb_size,
            width,
            t0.elapsed()
        );
    } else {
        if dst.exists() {
            let _ = std::fs::remove_file(dst);
        }
        sw_debug!(
            "[thumb] audio-cover failed (no embedded art?) | src={} | elapsed={:?}",
            src,
            t0.elapsed()
        );
    }
    success
}

fn try_ffmpeg_video_frame(
    src: &str,
    dst: &std::path::Path,
    width: u32,
    t0: std::time::Instant,
    orig_size: u64,
) -> bool {
    // Try seeking to 3s first; if the output is empty/missing, fall back to t=0
    for seek_secs in &["00:00:03", "00:00:00"] {
        sw_info!("[ffmpeg-start] video-frame ss={} | src={}", seek_secs, src);
        let ok = run_tracked_command(
            std::process::Command::new(ffmpeg_cmd())
                .args([
                    "-ss",
                    seek_secs,
                    "-i",
                    src,
                    "-vf",
                    &format!("scale={}:-1", width),
                    "-q:v",
                    "3",
                    "-frames:v",
                    "1",
                    "-y",
                    &dst.to_string_lossy(),
                ])
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null()),
        )
        .map(|s| s.success())
        .unwrap_or(false);
        let success = ok && dst.exists() && dst.metadata().map(|m| m.len() > 0).unwrap_or(false);
        if success {
            let thumb_size = dst.metadata().map(|m| m.len()).unwrap_or(0);
            sw_debug!(
                "[thumb] ffmpeg video-frame OK | ss={} | orig={}B | thumb={}B | w={} | elapsed={:?}",
                seek_secs, orig_size, thumb_size, width, t0.elapsed()
            );
            return true;
        }
        // Remove zero-byte artifact before retrying
        if dst.exists() {
            let _ = std::fs::remove_file(dst);
        }
    }
    sw_warn!(
        "[thumb] ffmpeg video-frame failed | src={} | elapsed={:?}",
        src,
        t0.elapsed()
    );
    false
}

fn try_ffmpeg_resize(
    src: &str,
    dst: &std::path::Path,
    width: u32,
    t0: std::time::Instant,
    orig_size: u64,
) -> bool {
    sw_info!("[ffmpeg-start] image-resize | src={}", src);
    let ok = run_tracked_command(
        std::process::Command::new(ffmpeg_cmd())
            .args([
                "-i",
                src,
                "-vf",
                &format!("scale={}:-1", width),
                "-q:v",
                "3",
                "-frames:v",
                "1",
                "-y",
                &dst.to_string_lossy(),
            ])
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null()),
    )
    .map(|s| s.success())
    .unwrap_or(false);
    let success = ok && dst.exists() && dst.metadata().map(|m| m.len() > 0).unwrap_or(false);
    if success {
        let thumb_size = dst.metadata().map(|m| m.len()).unwrap_or(0);
        let ratio = if orig_size > 0 {
            thumb_size * 100 / orig_size
        } else {
            0
        };
        sw_debug!(
            "[thumb] ffmpeg OK | orig={}B | thumb={}B | ratio={}% | w={} | elapsed={:?}",
            orig_size,
            thumb_size,
            ratio,
            width,
            t0.elapsed()
        );
    } else {
        sw_debug!(
            "[thumb] ffmpeg failed | src={} | elapsed={:?}",
            src,
            t0.elapsed()
        );
    }
    success
}

fn try_rust_image_resize(
    src: &str,
    dst: &std::path::Path,
    width: u32,
    t0: std::time::Instant,
    orig_size: u64,
) -> bool {
    let bytes = match std::fs::read(src) {
        Ok(b) => b,
        Err(e) => {
            sw_warn!("[thumb] rust-image read failed | src={} | err={}", src, e);
            return false;
        }
    };
    let img = match image::load_from_memory(&bytes) {
        Ok(i) => i,
        Err(e) => {
            sw_warn!("[thumb] rust-image decode failed | src={} | err={}", src, e);
            return false;
        }
    };
    let orig_w = img.width();
    let orig_h = img.height();
    let target_w = if width < orig_w { width } else { orig_w };
    let target_h = ((orig_h as f64) * (target_w as f64) / (orig_w as f64)) as u32;
    let resized = img.resize_exact(target_w, target_h, image::imageops::FilterType::Triangle);
    match resized.save_with_format(dst, image::ImageFormat::Jpeg) {
        Ok(_) => {
            let thumb_size = dst.metadata().map(|m| m.len()).unwrap_or(0);
            let ratio = if orig_size > 0 {
                thumb_size * 100 / orig_size
            } else {
                0
            };
            sw_debug!(
                "[thumb] rust-image OK | orig={}x{} | orig={}B | thumb={}B | ratio={}% | w={} | elapsed={:?}",
                orig_w, orig_h, orig_size, thumb_size, ratio, width, t0.elapsed()
            );
            dst.exists() && thumb_size > 0
        }
        Err(e) => {
            sw_warn!(
                "[thumb] rust-image save failed | src={} | err={} | elapsed={:?}",
                src,
                e,
                t0.elapsed()
            );
            false
        }
    }
}

static MEDIA_COLLECTIONS: OnceLock<Arc<Mutex<Vec<MediaCollection>>>> = OnceLock::new();
/// MEDIA_ITEMS 使用可清除模式：OnceLock 持有 Mutex，Mutex 持有 Option<Vec>。
/// - None  = 未加载（首次或被 release_items_from_memory 清除后）
/// - Some  = 已从数据库加载到内存
/// 通过 release_items_from_memory() 可将 Option 设为 None，Vec 被 drop，内存立刻归还给 OS。
static MEDIA_ITEMS: OnceLock<Mutex<Option<Vec<MediaItem>>>> = OnceLock::new();
/// 最近一次访问 MEDIA_ITEMS 的 Unix 时间戳（秒）。供空闲检测使用。
static LAST_MEDIA_ITEMS_ACCESS_SECS: AtomicU64 = AtomicU64::new(0);
static MEDIA_FOLDERS: OnceLock<Arc<Mutex<Vec<MediaFolder>>>> = OnceLock::new();
/// 数据库初始化成功标记。只缓存「成功」结果：失败时不写入，
/// 下次调用会重试（若数据库文件被另一进程独占锁定，锁定解除后即可恢复，
/// 避免失败被永久缓存导致本进程内收藏等数据读写永久失效）。
static DB_INIT_RESULT: OnceLock<()> = OnceLock::new();

/// Returns the platform-specific default base dir for app data.
fn app_data_base() -> String {
    #[cfg(windows)]
    return std::env::var("APPDATA").unwrap_or_else(|_| ".".to_string());
    #[cfg(target_os = "macos")]
    return {
        let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
        format!("{}/Library/Application Support", home)
    };
    #[cfg(not(any(windows, target_os = "macos")))]
    return std::env::var("XDG_DATA_HOME").unwrap_or_else(|_| {
        let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
        format!("{}/.local/share", home)
    });
}

/// Returns the platform-specific default path for the media DB file.
fn default_db_path() -> String {
    let dir = std::path::Path::new(&app_data_base()).join("SlimeWorks");
    let _ = std::fs::create_dir_all(&dir);
    dir.join("media.db").to_string_lossy().into_owned()
}

/// Returns the directory used for video thumbnails / scrub frames.
fn thumbnail_cache_dir() -> std::path::PathBuf {
    let dir = std::path::Path::new(&app_data_base())
        .join("SlimeWorks")
        .join("library")
        .join("media")
        .join("thumbnails");
    let _ = std::fs::create_dir_all(&dir);
    dir
}

/// 媒体库内部元数据表（迁移标记等）
fn meta_table_name() -> String {
    "media_meta".to_string()
}

/// 媒体库需要绑定的全部表。
fn media_table_names() -> Vec<String> {
    vec![
        collection_table_name(),
        item_table_name(),
        folder_table_name(),
        collection_order_table_name(),
        favorites_table_name(),
        smart_folder_table_name(),
        meta_table_name(),
    ]
}

/// Initialise the DB exactly once.  Returns the error string on failure.
/// Exposed publicly so Dart can call it explicitly at startup.
pub fn initialize_db() -> Result<(), String> {
    // 已成功过：直接返回（幂等）
    if DB_INIT_RESULT.get().is_some() {
        return Ok(());
    }
    let path = default_db_path();
    sw_info!("[media_db] Initializing DB at: {}", path);
    match db_module::db_init(path.clone()) {
        Ok(_) => {
            sw_info!("[media_db] DB initialized successfully");
            // 将媒体库全部表绑定到 media.db，避免历史上多模块共享全局单例
            // 时因初始化顺序不同导致数据写入错误文件的问题
            for table in media_table_names() {
                if let Err(e) = db_module::db_bind_table(table.clone(), path.clone()) {
                    sw_warn!("[media_db] 绑定表 {} 失败: {}", table, e);
                }
            }
            migrate_scattered_media_data(&path);
            // 仅在成功时写入标记；失败不缓存，下次调用可重试
            let _ = DB_INIT_RESULT.set(());
            Ok(())
        }
        Err(e) => {
            sw_info!("[media_db] DB init failed: {}", e);
            Err(e)
        }
    }
}

/// 一次性迁移：历史上全局 db 单例「先到先得」时，媒体数据可能被写入其他模块的
/// 文件（如 music_player.db）。这里把散落记录合并回 media.db（幂等，只执行一次）。
fn migrate_scattered_media_data(media_db_path: &str) {
    // 幂等标记：已迁移过则跳过
    if let Ok(Some(flag)) = db_module::db_get(meta_table_name(), "scatter_merged_v1".to_string())
    {
        if flag == "1" {
            return;
        }
    }

    let base = std::path::Path::new(&app_data_base()).join("SlimeWorks");
    let candidates = [base.join("music_player.db"), base.join("db.redb")];
    let tables: Vec<String> = media_table_names()
        .into_iter()
        .filter(|t| *t != meta_table_name())
        .collect();

    let dst_modified = std::fs::metadata(media_db_path).and_then(|m| m.modified()).ok();

    for candidate in &candidates {
        let src = candidate.to_string_lossy().into_owned();
        if src == media_db_path || !candidate.exists() {
            continue;
        }
        // 常规表：只补齐目标缺失的记录，不覆盖已有数据
        match db_module::db_merge_tables(src.clone(), media_db_path.to_string(), tables.clone(), false)
        {
            Ok(n) if n > 0 => sw_info!("[media_db] 从 {} 合并散落记录 {} 条", src, n),
            Ok(_) => {}
            Err(e) => sw_warn!("[media_db] 合并 {} 失败: {}", src, e),
        }
        // 收藏/排序：若候选文件比 media.db 更新，说明最近会话写在了候选文件，
        // 用候选文件的收藏与排序覆盖（取最新状态）
        let src_newer = match (
            std::fs::metadata(candidate).and_then(|m| m.modified()).ok(),
            dst_modified,
        ) {
            (Some(s), Some(d)) => s > d,
            _ => false,
        };
        if src_newer {
            for table in [favorites_table_name(), collection_order_table_name()] {
                match db_module::db_merge_tables(
                    src.clone(),
                    media_db_path.to_string(),
                    vec![table.clone()],
                    true,
                ) {
                    Ok(n) if n > 0 => {
                        sw_info!("[media_db] 从 {} 覆盖合并 {} {} 条", src, table, n)
                    }
                    Ok(_) => {}
                    Err(e) => sw_warn!("[media_db] 覆盖合并 {} 失败: {}", table, e),
                }
            }
        }
    }
    let _ = db_module::db_set(
        meta_table_name(),
        "scatter_merged_v1".to_string(),
        "1".to_string(),
    );
}

/// Ensures the DB is initialized (idempotent, no-op after first call).
fn ensure_db_initialized() {
    let _ = initialize_db();
}

/// Simple FNV-1a hash for deriving a stable short key from a path string.
fn path_key(path: &str) -> String {
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for b in path.bytes() {
        hash ^= b as u64;
        hash = hash.wrapping_mul(0x100_0000_01b3);
    }
    format!("{:016x}", hash)
}

/// Try to extract a single thumbnail frame from `video_path` using the system
/// ffmpeg binary.  The frame is cached at `thumbnails/{id}.jpg` and the path
/// returned on success.
#[allow(dead_code)]
fn try_extract_video_thumbnail(video_path: &str, thumb_id: &str) -> Option<String> {
    let dir = thumbnail_cache_dir();
    let out = dir.join(format!("{}.jpg", thumb_id));
    if out.exists() {
        return Some(out.to_string_lossy().into_owned());
    }
    let out_str = out.to_string_lossy().into_owned();
    // Try progressively earlier seek positions in case the video is short.
    for seek in &["00:00:10", "00:00:03", "00:00:00"] {
        let ok = run_tracked_command(
            std::process::Command::new(ffmpeg_cmd())
                .args([
                    "-i", video_path, "-ss", seek, "-vframes", "1", "-q:v", "3", "-y", &out_str,
                ])
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null()),
        )
        .map(|s| s.success())
        .unwrap_or(false);
        if ok && out.exists() {
            return Some(out_str);
        }
    }
    None
}

/// Use ffprobe to get the video duration in seconds.
fn video_duration_secs(video_path: &str) -> Option<f64> {
    sw_info!("[ffprobe-start] duration | src={}", video_path);
    let out = run_tracked_command_output(
        std::process::Command::new(ffprobe_cmd())
            .args([
                "-v",
                "error",
                "-show_entries",
                "format=duration",
                "-of",
                "default=noprint_wrappers=1:nokey=1",
                video_path,
            ])
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::null()),
    )
    .ok()?;
    String::from_utf8_lossy(&out.stdout)
        .trim()
        .parse::<f64>()
        .ok()
}

/// Extract `frame_count` evenly-spaced frames from a video using system ffmpeg.
/// Frames are cached in `thumbnails/scrub/<path_key>/frame_NN.jpg`.
/// Returns the list of frame file paths that were successfully created.
/// 受全局 ffmpeg 并发信号量控制，确保不会超过用户设置的并发上限。
pub fn extract_video_scrub_frames(
    video_path: String,
    frame_count: u32,
) -> Result<Vec<String>, String> {
    let n = (frame_count.max(2)) as usize;
    let key = path_key(&video_path);
    let frame_dir = thumbnail_cache_dir().join("scrub").join(&key);

    // Return cached frames if they all exist.
    let cached: Vec<String> = (0..n)
        .map(|i| {
            frame_dir
                .join(format!("frame_{:02}.jpg", i))
                .to_string_lossy()
                .into_owned()
        })
        .collect();
    if cached.iter().all(|p| std::path::Path::new(p).exists()) {
        return Ok(cached);
    }
    let _ = std::fs::create_dir_all(&frame_dir);

    // 获取全局 ffmpeg 并发信号量（整个函数执行期间持有，内部串行启动 ffmpeg）
    acquire_thumb_permit();
    let _permit = ThumbPermit; // RAII 自动释放

    let duration = video_duration_secs(&video_path).unwrap_or(60.0).max(1.0);
    let mut paths = Vec::new();
    for i in 0..n {
        let t = duration * i as f64 / (n - 1) as f64;
        let secs = t as u64;
        let seek = format!(
            "{:02}:{:02}:{:02}",
            secs / 3600,
            (secs % 3600) / 60,
            secs % 60
        );
        let out = frame_dir.join(format!("frame_{:02}.jpg", i));
        let out_str = out.to_string_lossy().into_owned();
        sw_info!(
            "[ffmpeg-start] scrub-frame {}/{} ss={} | src={}",
            i + 1,
            n,
            seek,
            video_path
        );
        let ok = run_tracked_command(
            std::process::Command::new(ffmpeg_cmd())
                .args([
                    "-i",
                    &video_path,
                    "-ss",
                    &seek,
                    "-vframes",
                    "1",
                    "-vf",
                    "scale=320:-1",
                    "-q:v",
                    "5",
                    "-y",
                    &out_str,
                ])
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null()),
        )
        .map(|s| s.success())
        .unwrap_or(false);
        if ok && out.exists() {
            paths.push(out_str);
        }
    }
    if paths.is_empty() {
        Err("ffmpeg not available or failed to extract frames".to_string())
    } else {
        Ok(paths)
    }
}

fn normalize_folder_path(path: &Path) -> Result<String, String> {
    let canonical = std::fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
    let s = canonical.to_string_lossy().into_owned();
    // Windows canonicalize adds \\?\ prefix – strip it for consistent storage/comparison
    #[cfg(windows)]
    let s = s
        .strip_prefix("\\\\?\\")
        .map(|v| v.to_string())
        .unwrap_or(s);
    Ok(s)
}

fn collection_table_name() -> String {
    "media_collections".to_string()
}

fn item_table_name() -> String {
    "media_items".to_string()
}

fn folder_table_name() -> String {
    "media_folders".to_string()
}

fn get_collections() -> &'static Arc<Mutex<Vec<MediaCollection>>> {
    MEDIA_COLLECTIONS.get_or_init(|| {
        ensure_db_initialized();
        let collections = Arc::new(Mutex::new(Vec::new()));
        let _ = db_module::db_register_table(collection_table_name());
        if let Ok(records) = db_module::db_list_all(collection_table_name()) {
            if let Ok(mut guard) = collections.lock() {
                for record in records {
                    if let Ok(collection) = serde_json::from_str::<MediaCollection>(&record.value) {
                        guard.push(collection);
                    }
                }
            }
        }
        collections
    })
}

/// 返回 MEDIA_ITEMS 静态 Mutex 的引用。
/// OnceLock 保证 Mutex 本身只初始化一次；其内 Option<Vec> 可随时清空再重载。
fn items_mutex() -> &'static Mutex<Option<Vec<MediaItem>>> {
    MEDIA_ITEMS.get_or_init(|| {
        ensure_db_initialized();
        let _ = db_module::db_register_table(item_table_name());
        Mutex::new(None) // 不立即加载，懒加载以节省启动内存
    })
}

/// 若 guard 中的 Option 为 None，则从数据库中加载所有条目到内存；
/// 同时记录访问时间戳供空闲检测使用。
fn ensure_items_loaded(items: &mut Option<Vec<MediaItem>>) {
    // 更新最近访问时间戳
    let now_secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    LAST_MEDIA_ITEMS_ACCESS_SECS.store(now_secs, Ordering::Relaxed);

    if items.is_none() {
        let mut data = Vec::new();
        if let Ok(records) = db_module::db_list_all(item_table_name()) {
            for record in records {
                if let Ok(item) = serde_json::from_str::<MediaItem>(&record.value) {
                    data.push(item);
                }
            }
        }
        sw_info!(
            "[media_cache] 从数据库加载媒体条目到内存，共 {} 条",
            data.len()
        );
        *items = Some(data);
    }
}

/// 将 MEDIA_ITEMS 内存缓存清空（设回 None），Vec 被 drop，内存立即归还给 OS。
/// 下次调用 items_mutex() 后仍可通过 ensure_items_loaded 重新从 DB 加载。
pub fn release_items_from_memory() {
    if let Some(mutex) = MEDIA_ITEMS.get() {
        if let Ok(mut guard) = mutex.lock() {
            let count = guard.as_ref().map(|v| v.len()).unwrap_or(0);
            if count > 0 {
                *guard = None;
                LAST_MEDIA_ITEMS_ACCESS_SECS.store(0, Ordering::Relaxed);
                sw_info!("[media_cache] 已释放媒体条目内存缓存，共 {} 条", count);
            }
        }
    }
}

/// 若距最近一次访问超过 idle_threshold_secs 秒且缓存非空，则自动释放内存。
/// 供节点服务器空闲检测线程调用。返回是否触发了释放操作。
pub fn check_and_release_if_idle(idle_threshold_secs: u64) -> bool {
    let last_access = LAST_MEDIA_ITEMS_ACCESS_SECS.load(Ordering::Relaxed);
    if last_access == 0 {
        return false; // 未曾加载过，无需释放
    }
    let now_secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    if now_secs.saturating_sub(last_access) > idle_threshold_secs {
        release_items_from_memory();
        true
    } else {
        false
    }
}

fn get_folders() -> &'static Arc<Mutex<Vec<MediaFolder>>> {
    MEDIA_FOLDERS.get_or_init(|| {
        ensure_db_initialized();
        let folders = Arc::new(Mutex::new(Vec::new()));
        let _ = db_module::db_register_table(folder_table_name());
        if let Ok(records) = db_module::db_list_all(folder_table_name()) {
            if let Ok(mut guard) = folders.lock() {
                for record in records {
                    if let Ok(folder) = serde_json::from_str::<MediaFolder>(&record.value) {
                        guard.push(folder);
                    }
                }
            }
        }
        folders
    })
}

fn persist_collection(collection: &MediaCollection) -> Result<(), String> {
    let json = serde_json::to_string(collection).map_err(|error| error.to_string())?;
    db_module::db_set(collection_table_name(), collection.id.clone(), json)
        .map_err(|error| error.to_string())
}

fn persist_item(item: &MediaItem) -> Result<(), String> {
    let json = serde_json::to_string(item).map_err(|error| error.to_string())?;
    db_module::db_set(item_table_name(), item.id.clone(), json).map_err(|error| error.to_string())
}

fn persist_folder(folder: &MediaFolder) -> Result<(), String> {
    let json = serde_json::to_string(folder).map_err(|error| error.to_string())?;
    db_module::db_set(folder_table_name(), folder.id.clone(), json)
        .map_err(|error| error.to_string())
}

fn delete_item_from_db(item_id: &str) {
    let _ = db_module::db_delete(item_table_name(), item_id.to_string());
}

fn delete_collection_from_db(collection_id: &str) {
    let _ = db_module::db_delete(collection_table_name(), collection_id.to_string());
}

fn delete_folder_from_db(folder_id: &str) {
    let _ = db_module::db_delete(folder_table_name(), folder_id.to_string());
}

fn default_collection_title(path: &Path) -> String {
    path.file_name()
        .and_then(|value| value.to_str())
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "未命名集合".to_string())
}

/// Choose cover: prefer first image item; fall back to first video path.
/// Actual video thumbnail generation happens lazily from the Dart side.
fn pick_cover_path(items: &[MediaItem]) -> Option<String> {
    items
        .iter()
        .find(|item| matches!(item.kind, MediaKind::Image))
        .or_else(|| items.first())
        .map(|item| item.file_path.clone())
}

fn upsert_collection_from_folder(
    folder: &Path,
    recursive: bool,
) -> Result<MediaCollection, String> {
    sw_debug!(
        "[media_scan] upsert_collection_from_folder: {:?} (recursive={})",
        folder,
        recursive
    );
    if !folder.exists() || !folder.is_dir() {
        let err = format!("Path is not a directory: {:?}", folder);
        sw_debug!("[media_scan] {}", err);
        return Err(err);
    }

    let normalized_path = normalize_folder_path(folder)?;
    sw_debug!("[media_scan] normalized_path = {:?}", normalized_path);

    let existing = {
        let collections = get_collections()
            .lock()
            .map_err(|error| error.to_string())?;
        collections
            .iter()
            .find(|collection| collection.folder_path == normalized_path)
            .cloned()
    };

    let collection_id = existing
        .as_ref()
        .map(|collection| collection.id.clone())
        .unwrap_or_else(|| format!("media_collection_{}", uuid::Uuid::new_v4()));

    let items = MediaFolderScanner::collect_media_items(&collection_id, folder, recursive)
        .map_err(|error| error.to_string())?;
    sw_debug!(
        "[media_scan] collect_media_items returned {} items for {:?}",
        items.len(),
        folder
    );
    if items.is_empty() {
        let err = format!("No media found in {:?}", folder);
        sw_debug!("[media_scan] {}", err);
        return Err(err);
    }

    {
        let mut guard = items_mutex().lock().map_err(|error| error.to_string())?;
        ensure_items_loaded(&mut guard);
        let stored_items = guard.as_mut().unwrap();
        let removed_ids = stored_items
            .iter()
            .filter(|item| item.collection_id == collection_id)
            .map(|item| item.id.clone())
            .collect::<Vec<String>>();
        stored_items.retain(|item| item.collection_id != collection_id);
        for item_id in removed_ids {
            delete_item_from_db(&item_id);
        }
        for item in &items {
            if let Err(error) = persist_item(item) {
                sw_debug!(
                    "[media_scan] persist_item failed for {:?}: {}",
                    item.file_path,
                    error
                );
            }
        }
        stored_items.extend(items.iter().cloned());
    }

    let now = Utc::now();
    let updated_collection = MediaCollection {
        id: collection_id.clone(),
        title: existing
            .as_ref()
            .map(|collection| collection.title.clone())
            .unwrap_or_else(|| default_collection_title(folder)),
        folder_path: normalized_path,
        folder_id: existing
            .as_ref()
            .and_then(|collection| collection.folder_id.clone()),
        cover_path: pick_cover_path(&items),
        item_count: items.len(),
        created_at: existing
            .as_ref()
            .map(|collection| collection.created_at)
            .unwrap_or(now),
        updated_at: now,
    };

    {
        let mut collections = get_collections()
            .lock()
            .map_err(|error| error.to_string())?;
        if let Some(existing_collection) = collections
            .iter_mut()
            .find(|collection| collection.id == updated_collection.id)
        {
            *existing_collection = updated_collection.clone();
        } else {
            collections.push(updated_collection.clone());
        }
    }
    persist_collection(&updated_collection)?;
    sw_debug!(
        "[media_scan] collection persisted: id={} title={:?} item_count={}",
        updated_collection.id,
        updated_collection.title,
        updated_collection.item_count
    );
    // 导入时预生成封面缩略图：懒创建资源旁的 .SlimeWorks 缓存目录，
    // 并预热封面缓存（命中磁盘缓存时开销极小，重复导入不会重复生成）
    if let Some(cover) = updated_collection.cover_path.as_deref() {
        match ensure_cover_thumbnail(cover.to_string(), 320) {
            Some(thumb) => sw_info!("[media_scan] 封面缩略图已预生成: {}", thumb),
            None => sw_debug!("[media_scan] 封面缩略图预生成失败或不支持: {}", cover),
        }
    }
    Ok(updated_collection)
}

pub fn get_all_media_folders() -> Result<Vec<MediaFolder>, String> {
    let folders = get_folders().lock().map_err(|error| error.to_string())?;
    let mut result = folders.clone();
    result.sort_by(|left, right| {
        left.order
            .cmp(&right.order)
            .then_with(|| left.name.to_lowercase().cmp(&right.name.to_lowercase()))
    });
    Ok(result)
}

pub fn get_child_media_folders(parent_id: String) -> Result<Vec<MediaFolder>, String> {
    let folders = get_folders().lock().map_err(|error| error.to_string())?;
    let mut result = folders
        .iter()
        .filter(|folder| folder.parent_id.as_deref() == Some(parent_id.as_str()))
        .cloned()
        .collect::<Vec<MediaFolder>>();
    result.sort_by(|left, right| {
        left.order
            .cmp(&right.order)
            .then_with(|| left.name.to_lowercase().cmp(&right.name.to_lowercase()))
    });
    Ok(result)
}

pub fn create_media_folder(name: String) -> Result<MediaFolder, String> {
    let normalized_name = name.trim();
    if normalized_name.is_empty() {
        return Err("文件夹名称不能为空".to_string());
    }

    let mut folders = get_folders().lock().map_err(|error| error.to_string())?;
    let folder = MediaFolder {
        id: format!("media_folder_{}", uuid::Uuid::new_v4()),
        name: normalized_name.to_string(),
        created_at: Utc::now(),
        order: folders
            .iter()
            .filter(|folder| folder.parent_id.is_none())
            .count() as i32,
        parent_id: None,
    };
    folders.push(folder.clone());
    persist_folder(&folder)?;
    Ok(folder)
}

pub fn create_child_media_folder(name: String, parent_id: String) -> Result<MediaFolder, String> {
    let normalized_name = name.trim();
    if normalized_name.is_empty() {
        return Err("文件夹名称不能为空".to_string());
    }

    let mut folders = get_folders().lock().map_err(|error| error.to_string())?;
    let folder = MediaFolder {
        id: format!("media_folder_{}", uuid::Uuid::new_v4()),
        name: normalized_name.to_string(),
        created_at: Utc::now(),
        order: folders
            .iter()
            .filter(|folder| folder.parent_id.as_deref() == Some(parent_id.as_str()))
            .count() as i32,
        parent_id: Some(parent_id),
    };
    folders.push(folder.clone());
    persist_folder(&folder)?;
    Ok(folder)
}

pub fn rename_media_folder(folder_id: String, name: String) -> Result<bool, String> {
    let normalized_name = name.trim();
    if normalized_name.is_empty() {
        return Err("文件夹名称不能为空".to_string());
    }

    let mut folders = get_folders().lock().map_err(|error| error.to_string())?;
    if let Some(folder) = folders.iter_mut().find(|folder| folder.id == folder_id) {
        folder.name = normalized_name.to_string();
        persist_folder(folder)?;
        Ok(true)
    } else {
        Ok(false)
    }
}

pub fn delete_media_folder(folder_id: String) -> Result<bool, String> {
    let parent_id = {
        let mut folders = get_folders().lock().map_err(|error| error.to_string())?;
        let parent_id = folders
            .iter()
            .find(|folder| folder.id == folder_id)
            .and_then(|folder| folder.parent_id.clone());
        let previous_len = folders.len();
        folders.retain(|folder| folder.id != folder_id);
        if folders.len() == previous_len {
            return Ok(false);
        }
        for child in folders
            .iter_mut()
            .filter(|folder| folder.parent_id.as_deref() == Some(folder_id.as_str()))
        {
            child.parent_id = parent_id.clone();
            persist_folder(child)?;
        }
        parent_id
    };

    {
        let mut collections = get_collections()
            .lock()
            .map_err(|error| error.to_string())?;
        for collection in collections
            .iter_mut()
            .filter(|collection| collection.folder_id.as_deref() == Some(folder_id.as_str()))
        {
            collection.folder_id = parent_id.clone();
            persist_collection(collection)?;
        }
    }

    delete_folder_from_db(&folder_id);
    Ok(true)
}

pub fn move_media_collection_to_folder(
    collection_id: String,
    folder_id: Option<String>,
) -> Result<bool, String> {
    let mut collections = get_collections()
        .lock()
        .map_err(|error| error.to_string())?;
    if let Some(collection) = collections
        .iter_mut()
        .find(|collection| collection.id == collection_id)
    {
        collection.folder_id = folder_id;
        collection.updated_at = Utc::now();
        persist_collection(collection)?;
        Ok(true)
    } else {
        Ok(false)
    }
}

pub fn get_all_media_collections() -> Result<Vec<MediaCollection>, String> {
    let collections = get_collections()
        .lock()
        .map_err(|error| error.to_string())?;
    let mut result = collections.clone();
    result.sort_by(|left, right| {
        right
            .updated_at
            .cmp(&left.updated_at)
            .then_with(|| left.title.to_lowercase().cmp(&right.title.to_lowercase()))
    });
    Ok(result)
}

pub fn get_media_collection_items(collection_id: String) -> Result<Vec<MediaItem>, String> {
    let mut guard = items_mutex().lock().map_err(|error| error.to_string())?;
    ensure_items_loaded(&mut guard);
    let items = guard.as_ref().unwrap();
    let mut result = items
        .iter()
        .filter(|item| item.collection_id == collection_id)
        .cloned()
        .collect::<Vec<MediaItem>>();
    result.sort_by(|left, right| {
        left.order
            .cmp(&right.order)
            .then_with(|| left.title.to_lowercase().cmp(&right.title.to_lowercase()))
    });
    Ok(result)
}

/// Aggregated per-collection stats: total file size and all file paths.
/// Used by the Dart layer to populate size/path caches in a single FFI call
/// instead of calling `get_media_collection_items` once per collection.
pub struct CollectionStats {
    pub collection_id: String,
    pub total_size: u64,
    pub file_paths: Vec<String>,
}

/// Return size + file-path list for every collection in one pass over MEDIA_ITEMS.
pub fn get_all_collection_stats() -> Result<Vec<CollectionStats>, String> {
    let mut guard = items_mutex().lock().map_err(|e| e.to_string())?;
    ensure_items_loaded(&mut guard);
    let items = guard.as_ref().unwrap();
    let mut map: HashMap<String, CollectionStats> = HashMap::new();
    for item in items.iter() {
        let entry = map
            .entry(item.collection_id.clone())
            .or_insert_with(|| CollectionStats {
                collection_id: item.collection_id.clone(),
                total_size: 0,
                file_paths: Vec::new(),
            });
        entry.total_size += item.file_size;
        entry.file_paths.push(item.file_path.clone());
    }
    Ok(map.into_values().collect())
}

/// 轻量级集合统计（不含文件路径列表），用于轮询检测文件数量变化。
#[derive(Debug, Clone)]
pub struct CollectionCount {
    pub collection_id: String,
    pub item_count: u32,
    pub total_size: u64,
}

pub fn get_all_collection_counts() -> Result<Vec<CollectionCount>, String> {
    let mut guard = items_mutex().lock().map_err(|e| e.to_string())?;
    ensure_items_loaded(&mut guard);
    let items = guard.as_ref().unwrap();
    let mut map: HashMap<String, (u32, u64)> = HashMap::new();
    for item in items.iter() {
        let entry = map.entry(item.collection_id.clone()).or_insert((0, 0));
        entry.0 += 1;
        entry.1 += item.file_size;
    }
    Ok(map
        .into_iter()
        .map(|(id, (count, size))| CollectionCount {
            collection_id: id,
            item_count: count,
            total_size: size,
        })
        .collect())
}

pub fn check_paths_exist(paths: Vec<String>) -> Vec<bool> {
    paths
        .iter()
        .map(|p| std::path::Path::new(p).exists())
        .collect()
}

pub fn import_media_folder(folder_path: String) -> Result<MediaCollection, String> {
    let normalized = normalize_folder_path(Path::new(&folder_path))?;
    if is_collection_path_imported(&normalized) {
        sw_debug!(
            "[media_scan] import_media_folder: folder already imported: {:?}",
            folder_path
        );
        return Err(format!("该文件夹已导入: {}", folder_path));
    }
    upsert_collection_from_folder(Path::new(&folder_path), true)
}

pub fn scan_media_folders(folder_path: String) -> Result<Vec<MediaCollection>, String> {
    let root = Path::new(&folder_path);
    sw_debug!("[media_scan] scan_media_folders called: {:?}", root);
    sw_debug!(
        "[media_scan] root.exists()={} root.is_dir()={}",
        root.exists(),
        root.is_dir()
    );
    let directories = MediaFolderScanner::scan_media_directories(root).map_err(|error| {
        sw_debug!("[media_scan] scan_media_directories error: {}", error);
        error.to_string()
    })?;
    sw_debug!(
        "[media_scan] scan_media_directories found {} dirs with media under {:?}",
        directories.len(),
        root
    );
    for (i, dir) in directories.iter().enumerate() {
        sw_debug!("[media_scan]   dir[{}] = {:?}", i, dir);
    }
    let mut collections = Vec::new();
    let mut skipped = 0;
    for directory in &directories {
        let normalized = match normalize_folder_path(directory) {
            Ok(p) => p,
            Err(e) => {
                sw_debug!(
                    "[media_scan] skip directory (normalization failed): {:?}: {}",
                    directory,
                    e
                );
                continue;
            }
        };
        if is_collection_path_imported(&normalized) {
            sw_debug!(
                "[media_scan] scan_media_folders: skipping already imported: {:?}",
                directory
            );
            skipped += 1;
            continue;
        }
        match upsert_collection_from_folder(directory, false) {
            Ok(collection) => {
                sw_debug!(
                    "scan_media_folders: imported '{}' from {:?}",
                    collection.title,
                    directory
                );
                collections.push(collection);
            }
            Err(error) => sw_debug!("scan_media_folders: failed {:?}: {}", directory, error),
        }
    }
    sw_debug!(
        "scan_media_folders: result {}/{} collections imported, {} skipped (already imported)",
        collections.len(),
        directories.len(),
        skipped
    );
    collections.sort_by(|left, right| right.updated_at.cmp(&left.updated_at));
    Ok(collections)
}

fn is_collection_path_imported(normalized_path: &str) -> bool {
    if let Ok(collections) = get_collections().lock() {
        collections.iter().any(|c| c.folder_path == normalized_path)
    } else {
        false
    }
}

pub fn rename_media_collection(collection_id: String, title: String) -> Result<bool, String> {
    let normalized_title = title.trim();
    if normalized_title.is_empty() {
        return Err("集合名称不能为空".to_string());
    }

    let mut collections = get_collections()
        .lock()
        .map_err(|error| error.to_string())?;
    if let Some(collection) = collections
        .iter_mut()
        .find(|collection| collection.id == collection_id)
    {
        collection.title = normalized_title.to_string();
        collection.updated_at = Utc::now();
        persist_collection(collection)?;
        Ok(true)
    } else {
        Ok(false)
    }
}

pub fn delete_media_collection(collection_id: String) -> Result<bool, String> {
    {
        let mut collections = get_collections()
            .lock()
            .map_err(|error| error.to_string())?;
        let previous_len = collections.len();
        collections.retain(|collection| collection.id != collection_id);
        if collections.len() == previous_len {
            return Ok(false);
        }
    }

    {
        let mut guard = items_mutex().lock().map_err(|error| error.to_string())?;
        ensure_items_loaded(&mut guard);
        let items = guard.as_mut().unwrap();
        let removed_ids = items
            .iter()
            .filter(|item| item.collection_id == collection_id)
            .map(|item| item.id.clone())
            .collect::<Vec<String>>();
        items.retain(|item| item.collection_id != collection_id);
        for item_id in removed_ids {
            delete_item_from_db(&item_id);
        }
    }

    delete_collection_from_db(&collection_id);
    Ok(true)
}

/// 删除单个媒体文件的物理文件，然后重新导入集合目录以同步数据库。
/// 返回 (删除成功, 重新导入后的集合ID)。
pub fn delete_media_item_file(item_file_path: String) -> Result<bool, String> {
    let path = std::path::Path::new(&item_file_path);
    let deleted = if path.exists() {
        std::fs::remove_file(path).map_err(|e| format!("删除文件失败: {}", e))?;
        true
    } else {
        false
    };
    // 重新导入父目录以同步数据库
    if let Some(parent) = path.parent() {
        let _ = import_media_folder(parent.to_string_lossy().into_owned());
    }
    Ok(deleted)
}

/// 删除集合内所有媒体文件的物理文件，返回已删除的文件数量。
pub fn delete_collection_local_files(collection_id: String) -> Result<usize, String> {
    let items = get_media_collection_items(collection_id.clone())?;
    let mut deleted_count = 0;
    for item in &items {
        let path = std::path::Path::new(&item.file_path);
        if path.exists() {
            match std::fs::remove_file(path) {
                Ok(_) => deleted_count += 1,
                Err(e) => sw_warn!(
                    "[delete_collection_local_files] 删除失败: {} err={}",
                    item.file_path,
                    e
                ),
            }
        }
    }
    Ok(deleted_count)
}

/// 将集合物理转移到目标目录，包括文件移动和数据库更新。
/// 返回成功转移的集合数量。
pub fn transfer_collections(
    collection_ids: Vec<String>,
    target_dir: String,
) -> Result<usize, String> {
    let target = std::path::Path::new(&target_dir);
    if !target.exists() {
        std::fs::create_dir_all(target).map_err(|e| format!("创建目标目录失败: {}", e))?;
    }
    let mut success_count = 0;
    let collections = get_collections().lock().map_err(|e| e.to_string())?.clone();
    for col_id in &collection_ids {
        let collection = match collections.iter().find(|c| &c.id == col_id) {
            Some(c) => c.clone(),
            None => continue,
        };
        let dest_dir = target.join(&collection.title);
        if let Err(e) = std::fs::create_dir_all(&dest_dir) {
            sw_warn!(
                "[transfer] 创建目标子目录失败: {} err={}",
                dest_dir.display(),
                e
            );
            continue;
        }
        let items = match get_media_collection_items(collection.id.clone()) {
            Ok(items) => items,
            Err(e) => {
                sw_warn!("[transfer] 获取集合项失败: {} err={}", collection.id, e);
                continue;
            }
        };
        for item in &items {
            let src = std::path::Path::new(&item.file_path);
            if !src.exists() {
                continue;
            }
            let file_name = match src.file_name() {
                Some(n) => n.to_owned(),
                None => continue,
            };
            let dest = dest_dir.join(&file_name);
            // 优先 rename（同分区快速），失败则 copy+delete
            if let Err(_) = std::fs::rename(src, &dest) {
                if let Err(e) = std::fs::copy(src, &dest).and_then(|_| std::fs::remove_file(src)) {
                    sw_warn!("[transfer] copy+delete 失败: {} err={}", item.file_path, e);
                    continue;
                }
            }
        }
        // 重新导入目标目录以在数据库中创建新记录
        match import_media_folder(dest_dir.to_string_lossy().into_owned()) {
            Ok(new_collection) => {
                // 将新集合移动到原集合所属的文件夹
                if collection.folder_id.is_some() {
                    let _ = move_media_collection_to_folder(
                        new_collection.id.clone(),
                        collection.folder_id.clone(),
                    );
                }
                // 删除旧集合记录
                let _ = delete_media_collection(collection.id.clone());
                // 尝试删除空的原目录
                let old_dir = std::path::Path::new(&collection.folder_path);
                if old_dir.exists() {
                    if let Ok(mut entries) = std::fs::read_dir(old_dir) {
                        if entries.next().is_none() {
                            let _ = std::fs::remove_dir(old_dir);
                        }
                    }
                }
            }
            Err(e) => {
                sw_warn!("[transfer] 重新导入失败: {} err={}", dest_dir.display(), e);
            }
        }
        success_count += 1;
    }
    Ok(success_count)
}

/// 打开文件所在目录（跨平台）
pub fn open_in_file_manager(file_path: String) -> Result<(), String> {
    let path = std::path::Path::new(&file_path);
    // 文件不存在时直接报错，避免 Explorer 打开错误目录（如“文档”）
    if !path.exists() {
        return Err("文件不存在，可能已被删除或移动".to_string());
    }
    #[cfg(target_os = "macos")]
    {
        std::process::Command::new("open")
            .arg("-R")
            .arg(path)
            .spawn()
            .map_err(|e| format!("打开失败: {}", e))?;
    }
    #[cfg(target_os = "windows")]
    {
        use std::os::windows::process::CommandExt;
        // 规范化路径并剥离 \\?\ 前缀，保证 Explorer 可识别
        let select_path = match path.canonicalize() {
            Ok(p) => {
                let s = p.to_string_lossy().into_owned();
                s.strip_prefix(r"\\?\")
                    .map(str::to_string)
                    .unwrap_or(s)
            }
            Err(_) => path.display().to_string(),
        };
        // 用 raw_arg 绕过 Command 的自动加引号：否则 "/select,路径" 会被整体加引号，
        // Explorer 无法解析 /select 开关，会回退打开默认目录（文档）
        let spawn_result = std::process::Command::new("explorer.exe")
            .raw_arg(format!("/select,{}", select_path))
            .spawn();
        if spawn_result.is_err() {
            // 回退：直接打开父目录（不选中文件）
            if let Some(parent) = path.parent() {
                std::process::Command::new("explorer.exe")
                    .arg(parent)
                    .spawn()
                    .map_err(|e| format!("打开失败: {}", e))?;
            }
        }
    }
    #[cfg(target_os = "linux")]
    {
        std::process::Command::new("xdg-open")
            .arg(path.parent().unwrap_or(path))
            .spawn()
            .map_err(|e| format!("打开失败: {}", e))?;
    }
    Ok(())
}

// ── 集合排序持久化 ────────────────────────────────────────────────────────────

fn collection_order_table_name() -> String {
    "media_collection_orders".to_string()
}

/// 获取指定 orderKey 的集合排序 ID 列表。
pub fn get_collection_order(order_key: String) -> Result<Vec<String>, String> {
    ensure_db_initialized();
    let _ = db_module::db_register_table(collection_order_table_name());
    match db_module::db_get(collection_order_table_name(), order_key.clone()) {
        Ok(Some(json)) => {
            let ids: Vec<String> = serde_json::from_str(&json).unwrap_or_default();
            Ok(ids)
        }
        _ => Ok(Vec::new()),
    }
}

/// 保存指定 orderKey 的集合排序 ID 列表。
pub fn save_collection_order(order_key: String, ids: Vec<String>) -> Result<(), String> {
    ensure_db_initialized();
    let _ = db_module::db_register_table(collection_order_table_name());
    if ids.is_empty() {
        let _ = db_module::db_delete(collection_order_table_name(), order_key);
    } else {
        let json = serde_json::to_string(&ids).map_err(|e| e.to_string())?;
        db_module::db_set(collection_order_table_name(), order_key, json)
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

/// 获取所有集合排序记录（用于批量加载）。
pub fn get_all_collection_orders() -> Result<Vec<(String, Vec<String>)>, String> {
    ensure_db_initialized();
    let _ = db_module::db_register_table(collection_order_table_name());
    match db_module::db_list_all(collection_order_table_name()) {
        Ok(records) => {
            let result: Vec<(String, Vec<String>)> = records
                .into_iter()
                .filter_map(|rec| {
                    let ids: Vec<String> = serde_json::from_str(&rec.value).ok()?;
                    Some((rec.key, ids))
                })
                .collect();
            Ok(result)
        }
        Err(e) => Err(e.to_string()),
    }
}

// ── 收藏集合持久化 ────────────────────────────────────────────────────────────

fn favorites_table_name() -> String {
    "media_library_favorites".to_string()
}

/// 获取收藏集合 ID 列表。
pub fn get_favorite_collection_ids() -> Result<Vec<String>, String> {
    ensure_db_initialized();
    let _ = db_module::db_register_table(favorites_table_name());
    match db_module::db_get(favorites_table_name(), "favorites".to_string()) {
        Ok(Some(json)) => {
            let ids: Vec<String> = serde_json::from_str(&json).unwrap_or_default();
            Ok(ids)
        }
        _ => Ok(Vec::new()),
    }
}

/// 保存收藏集合 ID 列表。
pub fn save_favorite_collection_ids(ids: Vec<String>) -> Result<(), String> {
    ensure_db_initialized();
    let _ = db_module::db_register_table(favorites_table_name());
    if ids.is_empty() {
        let _ = db_module::db_delete(favorites_table_name(), "favorites".to_string());
    } else {
        let json = serde_json::to_string(&ids).map_err(|e| e.to_string())?;
        db_module::db_set(favorites_table_name(), "favorites".to_string(), json)
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

// ── 智能文件夹 CRUD ──────────────────────────────────────────────────────────

static SMART_FOLDERS: OnceLock<Arc<Mutex<Vec<SmartFolder>>>> = OnceLock::new();

fn smart_folder_table_name() -> String {
    "smart_folders".to_string()
}

fn get_smart_folders() -> &'static Arc<Mutex<Vec<SmartFolder>>> {
    SMART_FOLDERS.get_or_init(|| {
        ensure_db_initialized();
        let folders = Arc::new(Mutex::new(Vec::new()));
        let _ = db_module::db_register_table(smart_folder_table_name());
        if let Ok(records) = db_module::db_list_all(smart_folder_table_name()) {
            if let Ok(mut guard) = folders.lock() {
                for record in records {
                    if let Ok(sf) = serde_json::from_str::<SmartFolder>(&record.value) {
                        guard.push(sf);
                    }
                }
            }
        }
        folders
    })
}

fn persist_smart_folder(sf: &SmartFolder) -> Result<(), String> {
    let json = serde_json::to_string(sf).map_err(|error| error.to_string())?;
    db_module::db_set(smart_folder_table_name(), sf.id.clone(), json)
        .map_err(|error| error.to_string())
}

fn delete_smart_folder_from_db(id: &str) {
    let _ = db_module::db_delete(smart_folder_table_name(), id.to_string());
}

/// 迁移旧 JSON 文件数据到 redb（仅执行一次）
fn migrate_smart_folders_from_json() {
    let path = get_app_data_path("smart_folders_data.json");
    if !std::path::Path::new(&path).exists() {
        return;
    }
    let content = match std::fs::read_to_string(&path) {
        Ok(c) => c,
        Err(_) => return,
    };
    if content.trim().is_empty() {
        return;
    }
    let legacy_list: Vec<serde_json::Value> = match serde_json::from_str(&content) {
        Ok(v) => v,
        Err(_) => return,
    };
    // 只在 redb 表为空时迁移
    {
        let sfs = get_smart_folders();
        if let Ok(guard) = sfs.lock() {
            if !guard.is_empty() {
                return;
            }
        }
    }
    let mut count = 0;
    if let Ok(mut guard) = get_smart_folders().lock() {
        for item in &legacy_list {
            if let Ok(mut sf) = serde_json::from_value::<SmartFolder>(item.clone()) {
                // 修正旧格式 ID：sf_ 前缀改为 smart-folder: 前缀
                if sf.id.starts_with("sf_") {
                    sf.id = format!("smart-folder:{}", &sf.id[3..]);
                }
                if persist_smart_folder(&sf).is_ok() {
                    guard.push(sf);
                    count += 1;
                }
            }
        }
    }
    if count > 0 {
        sw_info!("[smart_folder] 从 JSON 迁移 {} 条记录到 redb", count);
        // 迁移成功后删除旧文件
        let _ = std::fs::rename(&path, format!("{}.migrated", path));
    }
}

/// 获取 App 数据路径（与 node_server/handlers.rs 中的 get_app_data_path 一致）
fn get_app_data_path(filename: &str) -> String {
    let dir = std::path::Path::new(&app_data_base()).join("SlimeWorks");
    dir.join(filename).to_string_lossy().into_owned()
}

pub fn get_all_smart_folders() -> Result<Vec<SmartFolder>, String> {
    // 首次访问时尝试从 JSON 迁移
    migrate_smart_folders_from_json();
    let sfs = get_smart_folders()
        .lock()
        .map_err(|error| error.to_string())?;
    Ok(sfs.clone())
}

pub fn create_smart_folder(
    name: String,
    regex_pattern: String,
    keywords: Vec<String>,
    regex_target: String,
    file_type_filter: String,
    target_folder_ids: Vec<String>,
) -> Result<SmartFolder, String> {
    let normalized_name = name.trim();
    if normalized_name.is_empty() {
        return Err("智能文件夹名称不能为空".to_string());
    }

    let sf = SmartFolder {
        id: format!("smart-folder:{}", uuid::Uuid::new_v4()),
        name: normalized_name.to_string(),
        regex_pattern: regex_pattern.trim().to_string(),
        keywords,
        regex_target: SmartFolderRegexTarget::from_str_name(&regex_target),
        file_type_filter: SmartFolderFileType::from_str_name(&file_type_filter),
        target_folder_ids,
    };

    let mut sfs = get_smart_folders()
        .lock()
        .map_err(|error| error.to_string())?;
    persist_smart_folder(&sf)?;
    sfs.push(sf.clone());
    Ok(sf)
}

pub fn update_smart_folder(
    id: String,
    name: String,
    regex_pattern: String,
    keywords: Vec<String>,
    regex_target: String,
    file_type_filter: String,
    target_folder_ids: Vec<String>,
) -> Result<SmartFolder, String> {
    let normalized_name = name.trim();
    if normalized_name.is_empty() {
        return Err("智能文件夹名称不能为空".to_string());
    }

    let mut sfs = get_smart_folders()
        .lock()
        .map_err(|error| error.to_string())?;
    let idx = sfs
        .iter()
        .position(|sf| sf.id == id)
        .ok_or_else(|| format!("智能文件夹不存在: {}", id))?;

    let updated = SmartFolder {
        id: id.clone(),
        name: normalized_name.to_string(),
        regex_pattern: regex_pattern.trim().to_string(),
        keywords,
        regex_target: SmartFolderRegexTarget::from_str_name(&regex_target),
        file_type_filter: SmartFolderFileType::from_str_name(&file_type_filter),
        target_folder_ids,
    };

    persist_smart_folder(&updated)?;
    sfs[idx] = updated.clone();
    Ok(updated)
}

pub fn delete_smart_folder(id: String) -> Result<bool, String> {
    let mut sfs = get_smart_folders()
        .lock()
        .map_err(|error| error.to_string())?;
    let previous_len = sfs.len();
    sfs.retain(|sf| sf.id != id);
    if sfs.len() == previous_len {
        return Ok(false);
    }
    delete_smart_folder_from_db(&id);
    Ok(true)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    // ── default_collection_title ───────────────────────────────────────────

    #[test]
    fn default_title_uses_folder_name() {
        let path = Path::new("/some/深夜影院");
        assert_eq!(default_collection_title(path), "深夜影院");
    }

    #[test]
    fn default_title_uses_plain_directory_name() {
        let path = Path::new("/Users/user/Pictures/Vacation");
        assert_eq!(default_collection_title(path), "Vacation");
    }

    #[test]
    fn default_title_trims_whitespace() {
        // 使用 OsStr 路径模拟名称带空格的目录
        let path = Path::new("/tmp/ test ");
        // file_name 返回整个 " test " 字符串，trim 后应为 "test"
        assert_eq!(default_collection_title(path), "test");
    }

    #[test]
    fn default_title_fallback_when_empty() {
        // 根路径无 file_name
        let path = Path::new("/");
        assert_eq!(default_collection_title(path), "未命名集合");
    }

    // ── adjacent_cache_path ──────────────────────────────────────────────

    #[test]
    fn adjacent_cache_path_basic() {
        // 拼接规则：<资源父目录>/.SlimeWorks/tmp/<文件名>_w<宽度>.jpg
        let p = Path::new("/media/photos/a.jpg");
        assert_eq!(
            adjacent_cache_path(p, 320),
            Some(std::path::PathBuf::from(
                "/media/photos/.SlimeWorks/tmp/a.jpg_w320.jpg"
            ))
        );
    }

    #[test]
    fn adjacent_cache_path_key_ignores_full_path() {
        // key 只含文件名+宽度：同一文件改换盘符/挂载点不影响缓存文件名（跨设备可移植）
        let p1 = Path::new("D:/Photos/a.jpg");
        let p2 = Path::new("E:/Photos/a.jpg");
        let name1 = adjacent_cache_path(p1, 320).unwrap();
        let name2 = adjacent_cache_path(p2, 320).unwrap();
        assert_eq!(name1.file_name(), name2.file_name());
        assert_eq!(name1.file_name().unwrap(), "a.jpg_w320.jpg");
    }

    #[test]
    fn adjacent_cache_path_falls_back_when_no_parent() {
        // 根路径无父目录/文件名 → 回退全局缓存（返回 None）
        let p = Path::new("/");
        assert_eq!(adjacent_cache_path(p, 320), None);
    }

    // ── pick_cover_path ────────────────────────────────────────────────────

    fn make_item(id: &str, kind: MediaKind, path: &str) -> MediaItem {
        use chrono::Utc;
        MediaItem {
            id: id.to_string(),
            collection_id: "col".to_string(),
            title: id.to_string(),
            file_path: path.to_string(),
            kind,
            file_size: 0,
            modified_at: Utc::now(),
            width: None,
            height: None,
            duration_ms: None,
            order: 0,
        }
    }

    #[test]
    fn pick_cover_prefers_first_image_over_video() {
        let items = vec![
            make_item("v1", MediaKind::Video, "/a/b/clip.mp4"),
            make_item("i1", MediaKind::Image, "/a/b/cover.jpg"),
        ];
        assert_eq!(pick_cover_path(&items), Some("/a/b/cover.jpg".to_string()));
    }

    #[test]
    fn pick_cover_falls_back_to_first_item_when_no_image() {
        let items = vec![
            make_item("v1", MediaKind::Video, "/a/b/clip.mp4"),
            make_item("v2", MediaKind::Video, "/a/b/clip2.mp4"),
        ];
        assert_eq!(pick_cover_path(&items), Some("/a/b/clip.mp4".to_string()));
    }

    #[test]
    fn pick_cover_returns_none_for_empty_list() {
        assert_eq!(pick_cover_path(&[]), None);
    }

    // ── normalize_folder_path（无文件系统依赖的分支）─────────────────────

    #[test]
    fn normalize_folder_path_returns_string_without_error() {
        // 路径不存在时，canonicalize 会失败，函数应回退到原始路径字符串
        let path = Path::new("/nonexistent/path/slime_test_8675309");
        let result = normalize_folder_path(path);
        assert!(result.is_ok());
        let s = result.unwrap();
        // 应包含路径末段
        assert!(s.contains("slime_test_8675309"), "got: {s}");
    }
}
