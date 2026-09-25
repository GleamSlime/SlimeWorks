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
/// 默认 8，所有启动 ffmpeg/ffprobe 的函数（ensure_cover_thumbnail / extract_video_scrub_frames 等）
/// 共享此信号量，确保同一时刻 ffmpeg 进程数不超过此值。
static FFMPEG_CONCURRENCY: std::sync::RwLock<usize> = std::sync::RwLock::new(8);

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
    FFMPEG_CONCURRENCY.read().map(|g| *g).unwrap_or(8)
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
    // exists() + metadata() 是两次 stat；缓存命中是本函数的主场景，
    // 直接用一次 metadata() 的 Err 分支表达「不存在」。
    match std::fs::metadata(cache_path) {
        Ok(meta) if meta.is_file() && meta.len() > 0 => true,
        Ok(_) => {
            // zero-byte artefact from a previous failed write — remove and regenerate
            let _ = std::fs::remove_file(cache_path);
            false
        }
        Err(_) => false,
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

    // ③ disk cache hit — 相邻缓存命中时不再重新生成
    if let Some(ref p) = adjacent_path {
        if is_valid_cache_hit(p) {
            sw_debug!("[thumb] cache-hit(adjacent) | src={} | w={}", file_path, width);
            return Some(p.to_string_lossy().into_owned());
        }
    }

    // 记录原始文件大小（仅供生成阶段的耗时/压缩比日志使用）：
    // 放在缓存命中判断之后，避免命中时也付一次 stat。
    let orig_size = std::fs::metadata(&file_path).map(|m| m.len()).unwrap_or(0);

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

    // 标记任务为 running 并持久化（重启可恢复，failed/done 状态由 guard 在 drop 时写回）
    mark_thumbnail_task_running(&file_path, width);
    let mut task_guard = ThumbTaskGuard {
        file_path: file_path.clone(),
        width,
        success: false,
    }; // drop 时自动调用 complete_thumbnail_task 持久化最终状态

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
            task_guard.success = true;
            return Some(cache_path.to_string_lossy().into_owned());
        }
        sw_warn!("[thumb] video frame extraction failed | src={}", file_path);
        return None;
    }

    // ④b for audio: extract embedded cover art via ffmpeg
    if is_audio {
        if try_ffmpeg_audio_cover(&file_path, &cache_path, width, t0, orig_size) {
            task_guard.success = true;
            return Some(cache_path.to_string_lossy().into_owned());
        }
        sw_debug!(
            "[thumb] audio has no embedded cover art | src={}",
            file_path
        );
        return None;
    }

    // ⑦ 统一 ffmpeg 优先（含常规位图）：未打包的 debug 构建里 image crate 慢一个数量级
    //    （release 实测 ~196ms/张，debug 实测 ~1.9s/张），而 ffmpeg 子进程不受构建
    //    profile 影响。代价是位图也占 ffmpeg 信号量、批量生成按并发上限串行，
    //    且 ffmpeg 缺失时仍会回退纯 Rust，不会丢功能。
    if try_ffmpeg_resize(&file_path, &cache_path, width, t0, orig_size) {
        task_guard.success = true;
        return Some(cache_path.to_string_lossy().into_owned());
    }

    // ⑧ fallback: ffmpeg 不可用/解码失败时释放信号量，回退纯 Rust `image` crate
    drop(_permit);
    if try_rust_image_resize(&file_path, &cache_path, width, t0, orig_size) {
        task_guard.success = true;
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
                "-nostdin",
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
            .stdin(std::process::Stdio::null())
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
                    "-nostdin",
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
                .stdin(std::process::Stdio::null())
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
                "-nostdin",
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
            .stdin(std::process::Stdio::null())
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

// ── 节点服务期内存缩略图缓存（不落盘）─────────────────────────────────────────
//
// 节点对外服务 / bulk 预热只使用这份内存缓存：远程客户端请求什么宽度，
// 都不再把该宽度的 jpg 写进资源旁的 .SlimeWorks/tmp 邻近缓存，
// 避免远程请求宽度污染本地资源缩略图（邻近缓存只由本地链路按「本地缩略图质量」写入）。
// 条目最长存活 1 小时：读取时判过期 + 清扫线程每 5 分钟主动回收，保证到期释放。

/// 节点内存缩略图缓存条目。
struct NodeThumbEntry {
    bytes: Vec<u8>,
    inserted_at: std::time::Instant,
}

const NODE_THUMB_TTL_SECS: u64 = 60 * 60;
const NODE_THUMB_SWEEP_SECS: u64 = 5 * 60;
/// 内存占用上限：超过时按最早插入顺序逐出（缩略图单张几十 KB，64MB 可存约千张）。
const NODE_THUMB_MAX_BYTES: usize = 64 * 1024 * 1024;

static NODE_THUMB_CACHE: OnceLock<Mutex<HashMap<String, NodeThumbEntry>>> = OnceLock::new();
static NODE_THUMB_TOTAL_BYTES: AtomicU64 = AtomicU64::new(0);
static NODE_THUMB_TEMP_SEQ: AtomicU64 = AtomicU64::new(0);

/// 获取（并按需启动）节点内存缓存的锁；首次初始化时拉起清扫线程。
fn node_thumb_lock() -> &'static Mutex<HashMap<String, NodeThumbEntry>> {
    NODE_THUMB_CACHE.get_or_init(|| {
        std::thread::spawn(|| loop {
            std::thread::sleep(std::time::Duration::from_secs(NODE_THUMB_SWEEP_SECS));
            if let Some(lock) = NODE_THUMB_CACHE.get() {
                let mut map = lock.lock().unwrap_or_else(|e| e.into_inner());
                let expired: Vec<String> = map
                    .iter()
                    .filter(|(_, e)| e.inserted_at.elapsed().as_secs() >= NODE_THUMB_TTL_SECS)
                    .map(|(k, _)| k.clone())
                    .collect();
                for k in expired {
                    if let Some(entry) = map.remove(&k) {
                        NODE_THUMB_TOTAL_BYTES.fetch_sub(
                            entry.bytes.len() as u64,
                            Ordering::Relaxed,
                        );
                    }
                }
            }
        });
        Mutex::new(HashMap::new())
    })
}

fn node_thumb_get(key: &str) -> Option<Vec<u8>> {
    let mut map = node_thumb_lock()
        .lock()
        .unwrap_or_else(|e| e.into_inner());
    if let Some(entry) = map.get(key) {
        if entry.inserted_at.elapsed().as_secs() < NODE_THUMB_TTL_SECS {
            return Some(entry.bytes.clone());
        }
        // 已过期：移除并归还计数，走重新生成
        let len = map.remove(key).map(|e| e.bytes.len()).unwrap_or(0);
        NODE_THUMB_TOTAL_BYTES.fetch_sub(len as u64, Ordering::Relaxed);
    }
    None
}

fn node_thumb_put(key: &str, bytes: Vec<u8>) {
    let mut map = node_thumb_lock()
        .lock()
        .unwrap_or_else(|e| e.into_inner());
    let mut total = NODE_THUMB_TOTAL_BYTES.load(Ordering::Relaxed) as usize;
    // 先清过期，再按最早插入逐出到容量以内
    let expired: Vec<String> = map
        .iter()
        .filter(|(_, e)| e.inserted_at.elapsed().as_secs() >= NODE_THUMB_TTL_SECS)
        .map(|(k, _)| k.clone())
        .collect();
    for k in &expired {
        if let Some(entry) = map.remove(k) {
            total = total.saturating_sub(entry.bytes.len());
        }
    }
    while total + bytes.len() > NODE_THUMB_MAX_BYTES {
        let oldest = map
            .iter()
            .min_by_key(|(_, e)| e.inserted_at)
            .map(|(k, _)| k.clone());
        match oldest {
            Some(k) => {
                if let Some(entry) = map.remove(&k) {
                    total = total.saturating_sub(entry.bytes.len());
                }
            }
            None => break,
        }
    }
    total = total.saturating_add(bytes.len());
    map.insert(
        key.to_string(),
        NodeThumbEntry {
            bytes,
            inserted_at: std::time::Instant::now(),
        },
    );
    NODE_THUMB_TOTAL_BYTES.store(total as u64, Ordering::Relaxed);
}

/// 生成节点服务用的 JPEG 缩略图字节：命中内存缓存直接返回；未命中则现场生成，
/// 只存内存缓存，**绝不写资源旁邻近缓存**（与 ensure_cover_thumbnail 的关键区别）。
/// 不支持的扩展名或生成失败返回 None。
pub fn generate_thumbnail_bytes(file_path: String, width: u32) -> Option<Vec<u8>> {
    let lower = file_path.to_lowercase();
    let is_plain_image = [".jpg", ".jpeg", ".png", ".webp", ".bmp", ".gif"]
        .iter()
        .any(|e| lower.ends_with(e));
    let is_image = is_plain_image
        || [".heic", ".heif", ".avif"].iter().any(|e| lower.ends_with(e));
    let is_video = [
        ".mp4", ".mkv", ".mov", ".avi", ".webm", ".m4v", ".flv", ".wmv", ".ts", ".m2ts", ".mpg",
        ".mpeg",
    ]
    .iter()
    .any(|e| lower.ends_with(e));
    let is_audio = [
        ".mp3", ".flac", ".aac", ".m4a", ".ogg", ".opus", ".wav", ".wma", ".ape", ".aiff",
        ".alac",
    ]
    .iter()
    .any(|e| lower.ends_with(e));
    if !is_image && !is_video && !is_audio {
        return None;
    }

    let key = format!("{}|{}", file_path, width);
    if let Some(cached) = node_thumb_get(&key) {
        return Some(cached);
    }

    let t0 = std::time::Instant::now();
    let orig_size = std::fs::metadata(&file_path).map(|m| m.len()).unwrap_or(0);
    let generated = if is_plain_image {
        resize_to_jpeg_bytes(&file_path, width)
    } else {
        // 视频/音频/HEIC/AVIF：ffmpeg 只能输出到文件，写系统临时文件、读完立即删除，不留持久产物
        generate_via_ffmpeg_temp(&file_path, width, is_video, is_audio, t0, orig_size)
    };

    match generated {
        Some(bytes) if !bytes.is_empty() => {
            sw_debug!(
                "[node-thumb] generate | src={} | w={} | bytes={}B | elapsed={:?}",
                file_path,
                width,
                bytes.len(),
                t0.elapsed()
            );
            let out = bytes.clone();
            node_thumb_put(&key, bytes);
            Some(out)
        }
        _ => {
            sw_debug!("[node-thumb] generate failed | src={} | w={}", file_path, width);
            None
        }
    }
}

/// 纯内存位图缩放：解码 → Triangle 缩放 → JPEG 编码到内存缓冲，全程不落盘。
fn resize_to_jpeg_bytes(src: &str, width: u32) -> Option<Vec<u8>> {
    let bytes = std::fs::read(src).ok()?;
    let img = image::load_from_memory(&bytes).ok()?;
    let orig_w = img.width();
    let orig_h = img.height();
    if orig_w == 0 {
        return None;
    }
    let target_w = width.min(orig_w);
    let target_h = ((orig_h as f64) * (target_w as f64) / (orig_w as f64)) as u32;
    let resized = img.resize_exact(target_w, target_h, image::imageops::FilterType::Triangle);
    let mut buf = std::io::Cursor::new(Vec::new());
    resized
        .write_to(&mut buf, image::ImageFormat::Jpeg)
        .ok()?;
    Some(buf.into_inner())
}

/// 借 ffmpeg 生成到系统临时文件（复用既有 try_ffmpeg_* 逻辑），读回字节后立即删除，
/// 不在资源旁留下任何缓存产物。
fn generate_via_ffmpeg_temp(
    src: &str,
    width: u32,
    is_video: bool,
    is_audio: bool,
    t0: std::time::Instant,
    orig_size: u64,
) -> Option<Vec<u8>> {
    let seq = NODE_THUMB_TEMP_SEQ.fetch_add(1, Ordering::Relaxed);
    let dst = std::env::temp_dir().join(format!(
        "slimeworks_node_thumb_{}_{:x}_w{}.jpg",
        std::process::id(),
        seq,
        width
    ));
    acquire_thumb_permit();
    let _permit = ThumbPermit;
    let ok = if is_video {
        try_ffmpeg_video_frame(src, &dst, width, t0, orig_size)
    } else if is_audio {
        try_ffmpeg_audio_cover(src, &dst, width, t0, orig_size)
    } else {
        try_ffmpeg_resize(src, &dst, width, t0, orig_size)
    };
    let bytes = if ok {
        std::fs::read(&dst).ok().filter(|b| !b.is_empty())
    } else {
        None
    };
    let _ = std::fs::remove_file(&dst);
    bytes
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
        thumbnail_task_table_name(),
        meta_table_name(),
    ]
}

// ── 缩略图任务持久化（重启后可恢复）──────────────────────────────────────────

/// 缩略图任务状态。
/// - Pending: 已入队等待执行（持久化时直接写 running 字符串，未直接使用此变体）
/// - Running: 正在执行中（进程崩溃后重启会作为 pending 重投）
/// - Done: 已成功（理论上不入库，磁盘缓存即真相）
/// - Failed: 生成失败（重启时也会重新入队重试）
#[allow(dead_code)]
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ThumbnailTaskStatus {
    Pending,
    Running,
    Done,
    Failed,
}

impl ThumbnailTaskStatus {
    fn as_str(&self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::Running => "running",
            Self::Done => "done",
            Self::Failed => "failed",
        }
    }
}

/// 缩略图任务持久化记录（存储于 media_thumbnail_tasks 表）。
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ThumbnailTaskRecord {
    pub file_path: String,
    pub width: u32,
    pub status: String,
    pub retries: u32,
    pub updated_at: i64,
}

fn thumbnail_task_table_name() -> String {
    "media_thumbnail_tasks".to_string()
}

fn thumb_task_key(file_path: &str, width: u32) -> String {
    format!("{}|{}", file_path, width)
}

/// 本次会话内各缩略图任务的累计重试次数，key 同 `thumb_task_key`。
///
/// 取代 mark/complete 里各一次 `db_get`：读回旧记录纯粹只为了拿 retries，
/// 而这条记录刚刚就是本函数自己写的。放内存后单张缩略图的任务状态落库
/// 从 3 次事务降到 2 次。启动恢复与按路径清理时会同步维护，保证跨重启连续。
static THUMB_RETRY_COUNTS: OnceLock<Mutex<HashMap<String, u32>>> = OnceLock::new();

fn thumb_retry_map() -> &'static Mutex<HashMap<String, u32>> {
    THUMB_RETRY_COUNTS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn bump_thumb_retry_count(key: &str) -> u32 {
    let mut map = thumb_retry_map()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let next = map.get(key).copied().unwrap_or(0) + 1;
    map.insert(key.to_string(), next);
    next
}

fn thumb_retry_count(key: &str) -> u32 {
    let map = thumb_retry_map()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    map.get(key).copied().unwrap_or(0)
}

fn forget_thumb_retry_count(key: &str) {
    if let Ok(mut map) = thumb_retry_map().lock() {
        map.remove(key);
    }
}

/// 标记缩略图任务为 running（若不存在则插入），retries 自增。
/// 在真正开始生成（acquire permit 后、调用 ffmpeg 之前）调用。
fn mark_thumbnail_task_running(file_path: &str, width: u32) {
    let key = thumb_task_key(file_path, width);
    let now = Utc::now().timestamp();
    let record = ThumbnailTaskRecord {
        file_path: file_path.to_string(),
        width,
        status: ThumbnailTaskStatus::Running.as_str().to_string(),
        retries: bump_thumb_retry_count(&key),
        updated_at: now,
    };
    if let Ok(json) = serde_json::to_string(&record) {
        let _ = db_module::db_set(thumbnail_task_table_name(), key, json);
    }
}

/// 标记缩略图任务完成（成功或失败）。
/// - 成功：删除任务记录（磁盘缓存即真相，无需保留任务状态）
/// - 失败：更新为 failed 状态保留记录以便重启时重投重试
fn complete_thumbnail_task(file_path: &str, width: u32, success: bool) {
    let key = thumb_task_key(file_path, width);
    if success {
        forget_thumb_retry_count(&key);
        let _ = db_module::db_delete(thumbnail_task_table_name(), key);
        return;
    }
    let now = Utc::now().timestamp();
    let record = ThumbnailTaskRecord {
        file_path: file_path.to_string(),
        width,
        status: ThumbnailTaskStatus::Failed.as_str().to_string(),
        retries: thumb_retry_count(&key),
        updated_at: now,
    };
    if let Ok(json) = serde_json::to_string(&record) {
        let _ = db_module::db_set(thumbnail_task_table_name(), key, json);
    }
}

/// 获取所有未完成缩略图任务（pending/running/failed 全部）。
/// 用于应用启动时恢复未完成任务队列，failed 也会重新入队让用户能重试。
pub fn get_all_pending_thumbnail_tasks() -> Result<Vec<ThumbnailTaskRecord>, String> {
    ensure_db_initialized();
    let _ = db_module::db_register_table(thumbnail_task_table_name());
    let records = db_module::db_list_all(thumbnail_task_table_name())
        .map_err(|e| format!("读取缩略图任务表失败: {}", e))?;
    let mut result = Vec::new();
    for record in records {
        if let Ok(task) = serde_json::from_str::<ThumbnailTaskRecord>(&record.value) {
            if task.status != ThumbnailTaskStatus::Done.as_str() {
                // 顺带把 retries 灌回内存表，保证跨重启的重试计数连续
                // （见 `THUMB_RETRY_COUNTS`，落库路径上已不再回读 DB）。
                if let Ok(mut map) = thumb_retry_map().lock() {
                    map.entry(thumb_task_key(&task.file_path, task.width))
                        .or_insert(task.retries);
                }
                result.push(task);
            }
        }
    }
    Ok(result)
}

/// 按 file_path 删除所有关联的缩略图任务记录（含不同 width 的所有变体）。
/// 在删除集合/文件时调用，避免"幽灵任务"在重启后被重新入队反复重试已不存在的文件。
/// thumbnail_task_key 格式为 `file_path|width`，相同 file_path 的 key 共享前缀。
fn delete_thumbnail_tasks_for_file_path(file_path: &str) {
    delete_thumbnail_tasks_for_file_paths(std::slice::from_ref(&file_path.to_string()));
}

/// 批量版本：一趟 `db_list_all` + 一个删除事务。
/// 单路径版本被集合删除按文件逐个调用时，代价是「文件数 × 全表扫描」；
/// 合并后与文件数无关。
fn delete_thumbnail_tasks_for_file_paths(file_paths: &[String]) {
    if file_paths.is_empty() {
        return;
    }
    let _ = db_module::db_register_table(thumbnail_task_table_name());
    let targets: std::collections::HashSet<&str> =
        file_paths.iter().map(|p| p.as_str()).collect();
    let Ok(records) = db_module::db_list_all(thumbnail_task_table_name()) else {
        return;
    };
    // key 形如 `file_path|width`，width 不含 '|'，故按最后一段切分即可还原 file_path。
    // 用集合查找替代逐前缀比对，否则「文件数 × 记录数」的字符串比较又绕回原问题。
    let keys: Vec<String> = records
        .into_iter()
        .map(|r| r.key)
        .filter(|key| match key.rsplit_once('|') {
            Some((file_path, _)) => targets.contains(file_path),
            None => false,
        })
        .collect();
    if keys.is_empty() {
        return;
    }
    let deleted = keys.len();
    // 同步清掉内存里的重试计数，避免长期驻留
    if let Ok(mut map) = thumb_retry_map().lock() {
        for key in &keys {
            map.remove(key);
        }
    }
    if let Err(error) = db_module::db_batch_write(thumbnail_task_table_name(), Vec::new(), keys) {
        sw_debug!("[thumb-task] 批量清理任务记录失败: {}", error);
        return;
    }
    sw_debug!(
        "[thumb-task] 清理 {} 个 file_path 关联任务 {} 条",
        file_paths.len(),
        deleted
    );
}

/// RAII 守卫：drop 时自动调用 complete_thumbnail_task 标记任务完成状态。
/// 配合 `success` 字段，调用方在 return 前设置 success=true 即可让 drop 自动持久化。
struct ThumbTaskGuard {
    file_path: String,
    width: u32,
    success: bool,
}

impl Drop for ThumbTaskGuard {
    fn drop(&mut self) {
        complete_thumbnail_task(&self.file_path, self.width, self.success);
    }
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
                    "-nostdin", "-i", video_path, "-ss", seek, "-vframes", "1", "-q:v", "3", "-y", &out_str,
                ])
                .stdin(std::process::Stdio::null())
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
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::null()),
    )
    .ok()?;
    String::from_utf8_lossy(&out.stdout)
        .trim()
        .parse::<f64>()
        .ok()
}

/// 视频旁的邻近预览帧目录：`<视频父目录>/.SlimeWorks/video/tmp/scrub/<视频文件名>/`。
/// 与封面邻近缓存同属资源目录树，键只用文件名（不含路径），
/// 保证整个资源文件夹跨设备/跨盘符移动后缓存仍可命中。
fn adjacent_scrub_dir(video_path: &str) -> Option<std::path::PathBuf> {
    let parent = Path::new(video_path).parent()?;
    let file_name = Path::new(video_path).file_name()?;
    Some(
        parent
            .join(".SlimeWorks")
            .join("video")
            .join("tmp")
            .join("scrub")
            .join(file_name),
    )
}

/// Extract `frame_count` evenly-spaced frames from a video using system ffmpeg.
/// Frames are cached in `<视频父目录>/.SlimeWorks/video/tmp/scrub/<视频文件名>/frame_NN.jpg`.
/// Returns the list of frame file paths that were successfully created.
/// 受全局 ffmpeg 并发信号量控制，确保不会超过用户设置的并发上限。
pub fn extract_video_scrub_frames(
    video_path: String,
    frame_count: u32,
) -> Result<Vec<String>, String> {
    let n = (frame_count.max(2)) as usize;
    let frame_dir = adjacent_scrub_dir(&video_path)
        .ok_or_else(|| format!("无法计算视频邻近预览帧目录: {}", video_path))?;

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
    std::fs::create_dir_all(&frame_dir)
        .map_err(|e| format!("创建预览帧目录失败（只读盘？）: {} | {}", frame_dir.display(), e))?;
    #[cfg(target_os = "windows")]
    if let Some(sw_dir) = Path::new(&video_path).parent().map(|p| p.join(".SlimeWorks")) {
        ensure_hidden_attr(&sw_dir);
    }

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
                    "-nostdin",
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
                .stdin(std::process::Stdio::null())
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

fn item_to_record(item: &MediaItem) -> Option<db_module::DbRecord> {
    serde_json::to_string(item)
        .ok()
        .map(|value| db_module::DbRecord {
            key: item.id.clone(),
            value,
        })
}

fn persist_folder(folder: &MediaFolder) -> Result<(), String> {
    let json = serde_json::to_string(folder).map_err(|error| error.to_string())?;
    db_module::db_set(folder_table_name(), folder.id.clone(), json)
        .map_err(|error| error.to_string())
}

/// 批量删除条目记录：合并为单个事务，避免逐条 delete 触发逐次磁盘刷写。
fn delete_items_from_db(item_ids: &[String]) {
    if item_ids.is_empty() {
        return;
    }
    if let Err(error) = db_module::db_batch_write(
        item_table_name(),
        Vec::new(),
        item_ids.to_vec(),
    ) {
        sw_debug!("[media_scan] 批量删除媒体条目失败: {}", error);
    }
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

        // 同一次导入的增删合并到单个 redb 事务：逐条 db_set/db_delete 会让 N 个
        // 条目触发 N 次 commit（每次一趟磁盘刷写），导入上千文件时是分钟级差距。
        let sets = items
            .iter()
            .filter_map(item_to_record)
            .collect::<Vec<_>>();
        match db_module::db_batch_write(item_table_name(), sets, removed_ids) {
            Ok(_) => {
                stored_items.retain(|item| item.collection_id != collection_id);
                stored_items.extend(items.iter().cloned());
            }
            Err(error) => sw_debug!("[media_scan] 批量写入媒体条目失败: {}", error),
        }
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
    // 排序键先算好：把 `to_lowercase()` 写在比较函数里会让每次比较都新分配两个
    // String，一次排序就是 O(n log n) 次堆分配。
    let mut keyed = collections
        .iter()
        .map(|c| (c.updated_at, c.title.to_lowercase(), c.clone()))
        .collect::<Vec<_>>();
    keyed.sort_by(|left, right| right.0.cmp(&left.0).then_with(|| left.1.cmp(&right.1)));
    Ok(keyed.into_iter().map(|(_, _, c)| c).collect())
}

pub fn get_media_collection_items(collection_id: String) -> Result<Vec<MediaItem>, String> {
    let mut guard = items_mutex().lock().map_err(|error| error.to_string())?;
    ensure_items_loaded(&mut guard);
    let items = guard.as_ref().unwrap();
    let mut keyed = items
        .iter()
        .filter(|item| item.collection_id == collection_id)
        .map(|item| (item.order, item.title.to_lowercase(), item.clone()))
        .collect::<Vec<_>>();
    // 同上：排序键预计算，避免比较函数里反复 to_lowercase 分配
    keyed.sort_by(|left, right| left.0.cmp(&right.0).then_with(|| left.1.cmp(&right.1)));
    Ok(keyed.into_iter().map(|(_, _, item)| item).collect())
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

/// 重新扫描已导入集合的物理目录：跳过"已导入"拦截，直接走 upsert 覆盖入库。
/// 条目按集合整体删旧插新，磁盘新增文件被拾取、已删文件被清理，天然不产生重复。
pub fn rescan_media_folder(folder_path: String) -> Result<MediaCollection, String> {
    let normalized = normalize_folder_path(Path::new(&folder_path))?;
    sw_debug!("[media_scan] rescan_media_folder: 重新扫描 {:?}", normalized);
    upsert_collection_from_folder(Path::new(&normalized), true)
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
    // 先收集待删除 item 的 file_path，用于同步清理关联的缩略图任务记录
    let file_paths_to_clean: Vec<String> = {
        let mut guard = items_mutex().lock().map_err(|error| error.to_string())?;
        ensure_items_loaded(&mut guard);
        let items = guard.as_ref().unwrap();
        items
            .iter()
            .filter(|item| item.collection_id == collection_id)
            .map(|item| item.file_path.clone())
            .collect()
    };

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
        delete_items_from_db(&removed_ids);
    }

    // 同步清理关联的缩略图任务记录，避免重启后被重新入队反复重试已不存在的文件
    delete_thumbnail_tasks_for_file_paths(&file_paths_to_clean);

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
    // 同步清理关联的缩略图任务记录，避免重启后被重新入队反复重试已不存在的文件
    delete_thumbnail_tasks_for_file_path(&item_file_path);
    // 重新导入父目录以同步数据库
    if let Some(parent) = path.parent() {
        let _ = import_media_folder(parent.to_string_lossy().into_owned());
    }
    Ok(deleted)
}

/// 删除集合内所有媒体文件的物理文件，返回已删除的文件数量。
/// 资源清完后顺带清理该集合目录树内的 `.SlimeWorks` 缓存目录，集合目录因此变空时
/// 连目录一起删（只删集合目录自身，不碰上级目录）。
pub fn delete_collection_local_files(collection_id: String) -> Result<usize, String> {
    let items = get_media_collection_items(collection_id.clone())?;
    let mut deleted_count = 0;
    let mut deleted_paths = Vec::new();
    for item in &items {
        let path = std::path::Path::new(&item.file_path);
        if path.exists() {
            match std::fs::remove_file(path) {
                Ok(_) => {
                    // 物理文件删除成功后同步清理缩略图任务记录（循环外一次性批量清）
                    deleted_paths.push(item.file_path.clone());
                    deleted_count += 1;
                }
                Err(e) => sw_warn!(
                    "[delete_collection_local_files] 删除失败: {} err={}",
                    item.file_path,
                    e
                ),
            }
        }
    }
    delete_thumbnail_tasks_for_file_paths(&deleted_paths);
    // 即使一个文件都没删到（DB 有记录但文件早已被外部清掉）也要走目录清理，
    // 否则残留的空集合目录和 .SlimeWorks 永远没人收。
    cleanup_collection_physical_dirs(&collection_id);
    Ok(deleted_count)
}

/// 收集 `root` 目录树内**所有** `.SlimeWorks` 缓存目录（广度优先，限深限条目）。
///
/// 与 [find_collection_config_dir] 只取首个命中不同：缓存是按媒体文件的父目录就近
/// 懒创建的，一个集合树内可能存在多个，清理时必须收全。
fn collect_collection_config_dirs(root: &Path) -> Vec<std::path::PathBuf> {
    const MAX_DEPTH: usize = 8;
    const MAX_ENTRIES: usize = 20000;
    let mut found = Vec::new();
    let mut queue = std::collections::VecDeque::new();
    queue.push_back((root.to_path_buf(), 0usize));
    let mut visited_entries = 0usize;
    while let Some((dir, depth)) = queue.pop_front() {
        if depth >= MAX_DEPTH {
            continue;
        }
        let entries = match std::fs::read_dir(&dir) {
            Ok(entries) => entries,
            Err(_) => continue,
        };
        for entry in entries.flatten() {
            visited_entries += 1;
            if visited_entries > MAX_ENTRIES {
                sw_warn!("[delete_collection_local_files] 目录树过大，缓存目录搜索提前结束");
                return found;
            }
            let path = entry.path();
            if !path.is_dir() {
                continue;
            }
            let name = entry.file_name();
            if name == ".SlimeWorks" {
                found.push(path);
                continue;
            }
            // 隐藏目录不递归（缓存目录自身已单独处理），命中概率极低且省扫描开销
            if name.to_string_lossy().starts_with('.') {
                continue;
            }
            queue.push_back((path, depth + 1));
        }
    }
    found
}

/// 清理集合的物理目录残留：先删掉目录树内的 `.SlimeWorks` 缓存目录，再在集合目录
/// 已空时删除该目录本身。
fn cleanup_collection_physical_dirs(collection_id: &str) {
    let Ok(collections) = get_collections().lock() else {
        return;
    };
    let Some(folder_path) = collections
        .iter()
        .find(|collection| collection.id == collection_id)
        .map(|collection| collection.folder_path.clone())
    else {
        return;
    };
    drop(collections);

    cleanup_empty_collection_dir(Path::new(&folder_path));
}

/// 删除 `root` 目录树内所有 `.SlimeWorks` 缓存目录，并在 `root` 因此变空时删掉它。
///
/// 刻意只判断 `root` 自身、只删这一层，绝不向上传播删除父目录——上层的扫描根目录
/// 可能还挂着其他集合，删错不可恢复。
fn cleanup_empty_collection_dir(root: &Path) {
    if !root.is_dir() {
        return;
    }

    for config_dir in collect_collection_config_dirs(root) {
        match std::fs::remove_dir_all(&config_dir) {
            Ok(_) => sw_info!(
                "[delete_collection_local_files] 已删除缓存目录: {}",
                config_dir.display()
            ),
            Err(e) => sw_warn!(
                "[delete_collection_local_files] 缓存目录删除失败: {} err={}",
                config_dir.display(),
                e
            ),
        }
    }

    // 媒体文件是按子目录分布的，缓存清完后集合内会剩一串空壳目录，
    // 不先收掉它们集合根永远判不为空。
    let root_now_empty = prune_empty_dirs_inside(root, 0);
    if !root_now_empty {
        return;
    }
    match std::fs::remove_dir(root) {
        Ok(_) => sw_info!(
            "[delete_collection_local_files] 集合目录已空，一并删除: {}",
            root.display()
        ),
        Err(e) => sw_warn!(
            "[delete_collection_local_files] 空集合目录删除失败: {} err={}",
            root.display(),
            e
        ),
    }
}

/// 自底向上删除 `dir` 内部已变空的子目录，返回处理完后 `dir` 自身是否为空。
///
/// 递归严格以 `dir` 为界，不会删除 `dir` 本身，也就永远不会波及集合目录的上级。
/// 限深只为防御异常深的目录树导致递归过深；超限的分支直接按"非空"处理，宁可不删。
fn prune_empty_dirs_inside(dir: &Path, depth: usize) -> bool {
    const MAX_DEPTH: usize = 32;
    if depth >= MAX_DEPTH {
        return false;
    }
    let Ok(entries) = std::fs::read_dir(dir) else {
        return false;
    };
    let sub_dirs: Vec<std::path::PathBuf> = entries
        .flatten()
        .map(|entry| entry.path())
        .filter(|path| path.is_dir())
        .collect();
    for sub_dir in sub_dirs {
        if prune_empty_dirs_inside(&sub_dir, depth + 1) {
            // 符号链接指向的目录 remove_dir 会失败，失败即保留，保守不误删
            let _ = std::fs::remove_dir(&sub_dir);
        }
    }
    std::fs::read_dir(dir)
        .map(|mut entries| entries.next().is_none())
        .unwrap_or(false)
}

/// 清空本地媒体库：单事务清空各业务表（保留 media_meta 迁移标记），
/// 同时清空内存中 MEDIA_COLLECTIONS / MEDIA_ITEMS / MEDIA_FOLDERS / SMART_FOLDERS。
/// 可选清理缩略图缓存：
/// - clear_app_thumbnail_cache：清理应用数据目录内的 thumbnail_cache_dir()
/// - clear_resource_thumbnail_cache：清理各 collection.folder_path 父目录下的 .SlimeWorks/tmp
/// 不删除任何原始媒体文件。返回 (清空表数, 已清理缓存文件数)。
pub fn clear_all_local_media(
    clear_app_thumbnail_cache: bool,
    clear_resource_thumbnail_cache: bool,
) -> Result<(u32, u32), String> {
    ensure_db_initialized();

    // 先收集所有集合的 folder_path（清空后无法再获取），用于资源缓存清理
    let folder_paths: Vec<String> = if clear_resource_thumbnail_cache {
        let collections = get_collections()
            .lock()
            .map_err(|e| e.to_string())?;
        collections.iter().map(|c| c.folder_path.clone()).collect()
    } else {
        Vec::new()
    };

    // 每表一次事务清空（远好于逐条删除）
    let tables_to_clear = vec![
        collection_table_name(),
        item_table_name(),
        folder_table_name(),
        collection_order_table_name(),
        favorites_table_name(),
        smart_folder_table_name(),
        thumbnail_task_table_name(), // 同步清空缩略图任务，避免幽灵任务在重启后被重新入队
    ];
    let mut cleared_tables = 0u32;
    for table_name in &tables_to_clear {
        let _ = db_module::db_register_table(table_name.clone());
        match db_module::db_clear_table(table_name.clone()) {
            Ok(_) => cleared_tables += 1,
            Err(e) => sw_warn!("[clear_all] 清空表 {} 失败: {}", table_name, e),
        }
    }

    // 清空内存缓存（保留 media_meta 表）
    if let Some(mutex) = MEDIA_COLLECTIONS.get() {
        if let Ok(mut guard) = mutex.lock() {
            guard.clear();
        }
    }
    if let Some(mutex) = MEDIA_ITEMS.get() {
        if let Ok(mut guard) = mutex.lock() {
            *guard = None; // 直接 drop 内部 Vec，下次访问时懒加载
        }
    }
    if let Some(mutex) = MEDIA_FOLDERS.get() {
        if let Ok(mut guard) = mutex.lock() {
            guard.clear();
        }
    }
    if let Some(mutex) = SMART_FOLDERS.get() {
        if let Ok(mut guard) = mutex.lock() {
            guard.clear();
        }
    }
    sw_info!("[clear_all] 已清空 {} 张表 + 内存缓存", cleared_tables);

    // 可选：清理应用数据目录内的缩略图缓存
    let mut cleared_files = 0u32;
    if clear_app_thumbnail_cache {
        let cache_dir = thumbnail_cache_dir();
        cleared_files += cleanup_dir_contents(&cache_dir);
    }

    // 可选：清理各资源目录 .SlimeWorks/tmp（向上查找首个命中目录）
    if clear_resource_thumbnail_cache {
        let mut visited: std::collections::HashSet<std::path::PathBuf> =
            std::collections::HashSet::new();
        for folder_path in &folder_paths {
            let path = std::path::Path::new(folder_path);
            let mut current = Some(path);
            while let Some(dir) = current {
                let sw_tmp = dir.join(".SlimeWorks").join("tmp");
                if sw_tmp.exists() && sw_tmp.is_dir() {
                    // 用 canonicalize 去重，避免同目录被多个 collection 重复清理
                    if let Ok(canonical) = sw_tmp.canonicalize() {
                        if visited.insert(canonical.clone()) {
                            cleared_files += cleanup_dir_contents(&canonical);
                        }
                    }
                    break; // 命中后停止向上查找
                }
                current = dir.parent();
            }
        }
    }

    Ok((cleared_tables, cleared_files))
}

/// 清空指定目录下所有文件与子目录（递归删除），保留目录本身。
/// 返回已删除的条目数（文件或子目录均计 +1）。
fn cleanup_dir_contents(dir: &std::path::Path) -> u32 {
    if !dir.exists() {
        return 0;
    }
    let entries = match std::fs::read_dir(dir) {
        Ok(e) => e,
        Err(e) => {
            sw_warn!("[cleanup] 读取目录失败: {:?} err={}", dir, e);
            return 0;
        }
    };
    let mut count = 0u32;
    for entry in entries.flatten() {
        let path = entry.path();
        let result = if path.is_dir() {
            std::fs::remove_dir_all(&path)
        } else {
            std::fs::remove_file(&path)
        };
        if result.is_ok() {
            count += 1;
        } else if let Err(e) = result {
            sw_warn!("[cleanup] 删除失败: {:?} err={}", path, e);
        }
    }
    count
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

    // ── cleanup_empty_collection_dir / collect_collection_config_dirs ──────

    /// 在临时目录下搭一棵独立的集合目录树，返回 (集合根目录, 其父目录)。
    /// 父目录里放一个兄弟目录，用来断言清理绝不会波及上级。
    /// 固定名（case 全局唯一，不再拼 pid）+ 开跑前清旧 + 用例结尾删除归零
    fn make_collection_tree(case: &str) -> (std::path::PathBuf, std::path::PathBuf) {
        let parent = std::env::temp_dir().join(format!("slime_sw_cleanup_{}", case));
        let root = parent.join("vol01");
        let _ = std::fs::remove_dir_all(&parent);
        std::fs::create_dir_all(parent.join("sibling")).unwrap();
        std::fs::create_dir_all(root.join("pages")).unwrap();
        std::fs::create_dir_all(root.join(".SlimeWorks/tmp")).unwrap();
        std::fs::create_dir_all(root.join("pages/.SlimeWorks/tmp")).unwrap();
        std::fs::write(root.join(".SlimeWorks/tmp/a.jpg_w320.jpg"), b"x").unwrap();
        std::fs::write(root.join("pages/.SlimeWorks/tmp/b.jpg_w320.jpg"), b"x").unwrap();
        (root, parent)
    }

    #[test]
    fn collect_config_dirs_finds_all_nested_cache_dirs() {
        let (root, parent) = make_collection_tree("collect_all");
        let mut found = collect_collection_config_dirs(&root);
        found.sort();
        let names: Vec<String> = found
            .iter()
            .map(|p| p.strip_prefix(&root).unwrap().display().to_string())
            .collect();
        assert_eq!(
            names,
            vec![".SlimeWorks".to_string(), "pages/.SlimeWorks".to_string()],
            "嵌套的缓存目录必须全部收齐，got: {names:?}"
        );
        let _ = std::fs::remove_dir_all(&parent);
    }

    #[test]
    fn cleanup_removes_cache_dirs_and_empty_collection_dir() {
        let (root, parent) = make_collection_tree("all_empty");
        // 媒体文件按子目录分布，真实流程里由 delete_collection_local_files 逐个删；
        // 这里模拟删完后的状态：只剩空壳子目录和缓存目录
        std::fs::write(root.join("pages/001.jpg"), b"x").unwrap();
        std::fs::remove_file(root.join("pages/001.jpg")).unwrap();

        cleanup_empty_collection_dir(&root);

        assert!(!root.exists(), "集合目录已空时应连目录一起删除");
        assert!(
            parent.join("sibling").exists() && parent.exists(),
            "父级目录必须原样保留，不得向上传播删除"
        );
        let _ = std::fs::remove_dir_all(&parent);
    }

    #[test]
    fn cleanup_prunes_empty_subdirs_but_keeps_dir_with_content() {
        let (root, parent) = make_collection_tree("partial_left");
        // 集合根里留一个非媒体残留文件，子目录 pages 则彻底空掉
        std::fs::write(root.join("说明.txt"), b"x").unwrap();

        cleanup_empty_collection_dir(&root);

        assert!(!root.join(".SlimeWorks").exists(), "缓存目录应先被清掉");
        assert!(
            !root.join("pages").exists(),
            "空壳子目录必须收掉，否则集合根永远判不为空"
        );
        assert!(root.join("说明.txt").exists());
        assert!(root.exists(), "仍有残留内容时不得删除集合目录");
        let _ = std::fs::remove_dir_all(&parent);
    }

    #[test]
    fn cleanup_is_noop_when_collection_dir_missing() {
        // 固定名，任何用例都不会创建该目录
        let parent = std::env::temp_dir().join("slime_sw_cleanup_missing");
        // 目录压根不存在时不应 panic，也不应凭空造出父目录
        cleanup_empty_collection_dir(&parent.join("vol01"));
        assert!(!parent.exists());
    }

    // ════════════════════════════ DB 隔离环境 ════════════════════════════
    //
    // default_db_path() 完全由 $HOME 推导（macOS: ~/Library/Application Support/SlimeWorks/media.db），
    // 且 db_module 的实例表/表路由是进程级静态。这里在所有 DB 用例第一次触发
    // initialize_db 之前，把 HOME 重定向到独立临时目录：
    // - 媒体表全部绑定到临时目录下的 redb 文件，真实用户库文件从头到尾不会被打开；
    // - OnceLock 之后取 db_path 自校验确实位于临时 HOME 内，双保险；
    // - 所有走 DB / 进程全局静态（ffmpeg 路径、PID 表、内存任务表）的用例统一持
    //   DB_TEST_LOCK 串行执行，避免共享表与内存缓存互踩。

    /// DB 用例全局串行锁
    static DB_TEST_LOCK: Mutex<()> = Mutex::new(());

    struct DbTestEnv {
        /// 隔离 HOME 路径（固定名临时目录，每次运行开跑前清旧重建，避免按
        /// 随机后缀在系统临时目录里无限累积）
        #[allow(dead_code)]
        home_path: std::path::PathBuf,
        #[allow(dead_code)]
        db_path: String,
    }

    /// 初始化（且只初始化一次）隔离 DB 环境
    fn db_test_env() -> &'static DbTestEnv {
        static ENV: OnceLock<DbTestEnv> = OnceLock::new();
        ENV.get_or_init(|| {
            let home_path = std::env::temp_dir().join("media_db_test_home");
            assert_eq!(
                home_path.parent(),
                Some(std::env::temp_dir().as_path()),
                "清理目标必须恰好位于系统临时目录下，防误删"
            );
            let _ = std::fs::remove_dir_all(&home_path);
            std::fs::create_dir_all(&home_path).expect("创建隔离 HOME 失败");
            // edition 2021：set_var 是安全接口；只在 OnceLock 初始化闭包里调用一次，
            // 之后 HOME 永不再变化，DB 用例又全部串行，不存在反复改环境变量的竞态
            std::env::set_var("HOME", &home_path);
            initialize_db().expect("隔离 HOME 下 initialize_db 应成功");
            // initialize_db 必须幂等
            initialize_db().expect("initialize_db 应幂等");
            let db_path = default_db_path();
            assert!(
                db_path.starts_with(home_path.to_string_lossy().as_ref()),
                "DB 路径必须位于隔离 HOME 内，绝不触碰真实用户库: {db_path}"
            );
            DbTestEnv {
                home_path,
                db_path,
            }
        })
    }

    /// 取 DB 串行锁，并在持锁状态下确保隔离环境已初始化
    fn lock_db_test_serial() -> std::sync::MutexGuard<'static, ()> {
        let guard = DB_TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        db_test_env();
        guard
    }

    /// 生成一张可解码的位图（未压缩 BMP，约 300KB）：
    /// 满足 scanner 的 ≥10KB / ≥100x100 阈值，且 image crate 一定能解码，
    /// 缩略图生成（ffmpeg 成功或纯 Rust 回退）不依赖 ffmpeg 是否存在
    fn write_test_image(path: &Path) {
        let img = image::RgbImage::from_fn(320, 240, |x, y| {
            image::Rgb([
                (x as u32 * 73 ^ y as u32 * 151) as u8,
                (x as u32 * 17 + y as u32 * 91) as u8,
                (x as u32 * 223 ^ y as u32 * 3) as u8,
            ])
        });
        img.save(path).expect("写入测试图片失败");
        assert!(
            std::fs::metadata(path).unwrap().len() >= 10 * 1024 + 1,
            "测试图片必须超过 scanner 的 10KB 过滤阈值"
        );
    }

    /// 在系统临时目录（非隔离 HOME）下建一棵独立媒体目录树，返回其根目录。
    /// 固定名（case 全局唯一，不再拼 pid）+ 开跑前清旧 + 用例结尾 remove_dir_all 归零
    fn fake_media_root(case: &str) -> std::path::PathBuf {
        let root = std::env::temp_dir().join(format!("slime_mc_{}", case));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        root
    }

    fn db_row(table: String, key: &str) -> Option<String> {
        db_module::db_get(table, key.to_string()).unwrap()
    }

    fn row_count_for_collection(table: String, collection_id: &str) -> usize {
        let marker = format!("\"collection_id\":\"{}\"", collection_id);
        db_module::db_list_all(table)
            .unwrap_or_default()
            .into_iter()
            .filter(|r| r.value.contains(&marker))
            .count()
    }

    // ── 文件夹 CRUD 落库 ───────────────────────────────────────────────────

    #[test]
    fn db_folder_crud_persists_to_real_table() {
        let _serial = lock_db_test_serial();
        let tag = format!("folder_{}", std::process::id());

        // 空名字/纯空白拒绝
        assert!(create_media_folder("   ".to_string()).is_err());

        let root = create_media_folder(format!("根目录 {tag}")).unwrap();
        let child = create_child_media_folder(format!("子目录 {tag}"), root.id.clone()).unwrap();
        assert_eq!(child.parent_id.as_deref(), Some(root.id.as_str()));

        // 内存列表可见 + 独立子节点查询
        let children = get_child_media_folders(root.id.clone()).unwrap();
        assert!(children.iter().any(|f| f.id == child.id));

        // 真正落库：直接从 media_folders 表读回 JSON 并反解
        let raw = db_row(folder_table_name(), &root.id).expect("根文件夹应已落库");
        let stored: MediaFolder = serde_json::from_str(&raw).unwrap();
        assert_eq!(stored.name, format!("根目录 {tag}"));

        // 改名：DB 侧应同步更新
        assert!(rename_media_folder(child.id.clone(), format!("改名 {tag}")).unwrap());
        let raw = db_row(folder_table_name(), &child.id).unwrap();
        let stored: MediaFolder = serde_json::from_str(&raw).unwrap();
        assert_eq!(stored.name, format!("改名 {tag}"));
        // 不存在的 id → false
        assert!(!rename_media_folder("no_such_folder".into(), "x".into()).unwrap());

        // 删除父目录：子目录应上挂（parent 变 None）且 DB 同步
        assert!(delete_media_folder(root.id.clone()).unwrap());
        assert!(db_row(folder_table_name(), &root.id).is_none());
        let raw = db_row(folder_table_name(), &child.id).expect("子目录不应被连带删除");
        let stored: MediaFolder = serde_json::from_str(&raw).unwrap();
        assert!(stored.parent_id.is_none());
        assert!(!delete_media_folder(root.id.clone()).unwrap());

        // 清理本用例数据
        let _ = delete_media_folder(child.id);
    }

    #[test]
    fn db_smart_folder_crud_persists_to_db() {
        let _serial = lock_db_test_serial();
        let tag = format!("sf_{}", std::process::id());

        let sf = create_smart_folder(
            format!("智能夹 {tag}"),
            "关键词".into(),
            vec!["k1".into()],
            "fileName".into(),
            "images".into(),
            vec!["folder_1".into()],
        )
        .unwrap();
        assert!(sf.id.starts_with("smart-folder:"));
        assert_eq!(sf.regex_target, SmartFolderRegexTarget::FileName);
        assert_eq!(sf.file_type_filter, SmartFolderFileType::Images);

        // 落库校验：smart_folders 表可直接读回
        let raw = db_row(smart_folder_table_name(), &sf.id).expect("智能文件夹应落库");
        let stored: SmartFolder = serde_json::from_str(&raw).unwrap();
        assert_eq!(stored.name, format!("智能夹 {tag}"));

        // 更新后 DB 同步；名称空白拒绝；不存在报错
        assert!(create_smart_folder("  ".into(), String::new(), vec![], String::new(), String::new(), vec![]).is_err());
        let updated = update_smart_folder(
            sf.id.clone(),
            format!("改名 {tag}"),
            ".*".into(),
            vec![],
            "collectionName".into(),
            "all".into(),
            vec![],
        )
        .unwrap();
        assert_eq!(updated.file_type_filter, SmartFolderFileType::All);
        let raw = db_row(smart_folder_table_name(), &sf.id).unwrap();
        assert!(raw.contains(&format!("改名 {tag}")));
        assert!(update_smart_folder("no_such_id".into(), "x".into(), String::new(), vec![], String::new(), String::new(), vec![]).is_err());

        assert!(get_all_smart_folders().unwrap().iter().any(|s| s.id == sf.id));
        assert!(delete_smart_folder(sf.id.clone()).unwrap());
        assert!(!delete_smart_folder(sf.id.clone()).unwrap());
        assert!(db_row(smart_folder_table_name(), &sf.id).is_none());
    }

    // ── 集合排序 / 收藏 持久化 ────────────────────────────────────────────

    #[test]
    fn db_collection_order_roundtrip_delete_and_corruption() {
        let _serial = lock_db_test_serial();
        let key = format!("order_case_{}", std::process::id());

        // 未写入时为空列表
        assert_eq!(get_collection_order(key.clone()).unwrap(), Vec::<String>::new());

        // 保存 → 读回 + 确认落库
        save_collection_order(key.clone(), vec!["a".into(), "b".into()]).unwrap();
        assert_eq!(
            get_collection_order(key.clone()).unwrap(),
            vec!["a".to_string(), "b".to_string()]
        );
        let raw = db_row(collection_order_table_name(), &key)
            .expect("排序应落在 media_collection_orders 表");
        let stored_ids: Vec<String> = serde_json::from_str(&raw).unwrap();
        assert_eq!(stored_ids, vec!["a".to_string(), "b".to_string()]);

        // 全量列表接口应包含本条
        let all = get_all_collection_orders().unwrap();
        assert!(all.iter().any(|(k, ids)| k == &key && ids.len() == 2));

        // 损坏 JSON 容错：读取侧回退空列表而不是报错
        db_module::db_set(collection_order_table_name(), key.clone(), "{坏数据".into()).unwrap();
        assert_eq!(get_collection_order(key.clone()).unwrap(), Vec::<String>::new());

        // 空列表 = 删除语义
        save_collection_order(key.clone(), vec![]).unwrap();
        assert!(db_row(collection_order_table_name(), &key).is_none());
    }

    #[test]
    fn db_favorite_collection_ids_persist() {
        let _serial = lock_db_test_serial();
        let id = format!("fav_{}", std::process::id());
        save_favorite_collection_ids(vec![id.clone()]).unwrap();
        assert_eq!(get_favorite_collection_ids().unwrap(), vec![id.clone()]);
        assert!(db_row(favorites_table_name(), "favorites")
            .unwrap()
            .contains(&id));
        // 空列表清掉记录
        save_favorite_collection_ids(vec![]).unwrap();
        assert!(db_row(favorites_table_name(), "favorites").is_none());
        assert!(get_favorite_collection_ids().unwrap().is_empty());
    }

    // ── 导入/重扫/删除 主链路（走真实 DB + 文件落盘）──────────────────────

    #[test]
    fn db_import_rescan_delete_full_cycle() {
        let _serial = lock_db_test_serial();
        let root = fake_media_root("import_cycle");
        std::fs::create_dir_all(root.join("sub")).unwrap();
        write_test_image(&root.join("a.bmp"));
        write_test_image(&root.join("sub/b.bmp"));
        std::fs::write(root.join("readme.txt"), b"not media").unwrap();

        let folder_path = std::fs::canonicalize(&root).unwrap();
        let collection = import_media_folder(folder_path.to_string_lossy().into_owned())
            .expect("导入应成功");
        assert_eq!(collection.item_count, 2, "只应统计受支持的媒体文件");
        assert_eq!(
            collection.title,
            root.file_name().unwrap().to_string_lossy(),
            "默认标题取集合目录名"
        );
        assert_eq!(collection.folder_path, folder_path.to_string_lossy());
        assert!(collection.cover_path.is_some(), "首个图片应被选为封面");

        // 集合与条目均已落库
        assert!(db_row(collection_table_name(), &collection.id)
            .expect("集合应落 media_collections 表")
            .contains("import_cycle"));
        assert_eq!(
            row_count_for_collection(item_table_name(), &collection.id),
            2,
            "两条条目应落 media_items 表"
        );

        // 导入链路应已预生成封面邻近缓存（不依赖 ffmpeg：Rust 回退兜底）
        let cache = adjacent_cache_path(Path::new(&collection.cover_path.clone().unwrap()), 320)
            .unwrap();
        assert!(
            is_valid_cache_hit(&cache),
            "导入后封面缩略图应已写入: {}",
            cache.display()
        );

        // 统计组装
        let stats = get_all_collection_stats()
            .unwrap()
            .into_iter()
            .find(|s| s.collection_id == collection.id)
            .expect("stats 应包含本集合");
        assert_eq!(stats.file_paths.len(), 2);
        let expected_size: u64 = stats
            .file_paths
            .iter()
            .map(|p| std::fs::metadata(p).unwrap().len())
            .sum();
        assert_eq!(stats.total_size, expected_size);
        let counts = get_all_collection_counts()
            .unwrap()
            .into_iter()
            .find(|c| c.collection_id == collection.id)
            .expect("counts 应包含本集合");
        assert_eq!(counts.item_count, 2);
        assert_eq!(counts.total_size, expected_size);

        // 重复导入被拦截
        let err = import_media_folder(folder_path.to_string_lossy().into_owned())
            .expect_err("重复导入应报错");
        assert!(err.contains("已导入"), "got: {err}");

        // 重扫：同 id 覆盖，新增文件被拾取且不产生重复条目
        write_test_image(&root.join("c.bmp"));
        let rescanned =
            rescan_media_folder(folder_path.to_string_lossy().into_owned()).expect("重扫应成功");
        assert_eq!(rescanned.id, collection.id, "重扫应复用既有集合 id");
        assert_eq!(rescanned.item_count, 3);
        assert_eq!(row_count_for_collection(item_table_name(), &collection.id), 3);
        let items = get_media_collection_items(collection.id.clone()).unwrap();
        assert_eq!(items.len(), 3);
        assert_eq!(
            items.iter().map(|i| i.title.as_str()).collect::<Vec<_>>(),
            vec!["a", "c", "b"],
            "条目应按扫描排序后的 order 稳定输出（根目录文件先于子目录）"
        );

        // 删除集合：内存 + 两张表 + 关联缩略图任务全部清理
        assert!(delete_media_collection(collection.id.clone()).unwrap());
        assert!(db_row(collection_table_name(), &collection.id).is_none());
        assert_eq!(row_count_for_collection(item_table_name(), &collection.id), 0);
        assert!(!delete_media_collection("no_such_collection".into()).unwrap());
        let pending = get_all_pending_thumbnail_tasks().unwrap();
        assert!(
            !pending.iter().any(|t| t.file_path.starts_with(&root.to_string_lossy().into_owned())
                || t.file_path.starts_with(
                    &std::fs::canonicalize(&root).unwrap().to_string_lossy().into_owned()
                )),
            "删除集合后不应残留该目录的缩略图任务: {pending:?}"
        );
        assert!(
            get_all_collection_stats()
                .unwrap()
                .iter()
                .all(|s| s.collection_id != collection.id),
            "stats 不应再包含已删集合"
        );

        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn db_scan_media_folders_imports_each_media_dir() {
        let _serial = lock_db_test_serial();
        let root = fake_media_root("scan_root");
        std::fs::create_dir_all(root.join("volA")).unwrap();
        std::fs::create_dir_all(root.join("volB/nested")).unwrap();
        std::fs::create_dir_all(root.join("notes")).unwrap();
        write_test_image(&root.join("volA/a.bmp"));
        write_test_image(&root.join("volB/b1.bmp"));
        write_test_image(&root.join("volB/b2.bmp"));
        std::fs::write(root.join("notes/readme.txt"), b"x").unwrap();

        // 递归=false：只有直接含媒体的目录各自成集合；notes 与空根目录被排除
        let collections = scan_media_folders(root.to_string_lossy().into_owned()).unwrap();
        let titles: Vec<&str> = collections.iter().map(|c| c.title.as_str()).collect();
        assert!(titles.contains(&"volA") && titles.contains(&"volB"), "got: {titles:?}");
        assert!(!titles.contains(&"notes"));
        let vol_b = collections.iter().find(|c| c.title == "volB").unwrap();
        assert_eq!(vol_b.item_count, 2);

        // 已导入的目录再扫一遍：全部跳过，返回空列表
        let again = scan_media_folders(root.to_string_lossy().into_owned()).unwrap();
        assert!(again.is_empty(), "重复扫描应跳过所有已导入目录");

        for c in collections {
            assert!(delete_media_collection(c.id).unwrap());
        }
        let _ = std::fs::remove_dir_all(&root);
    }

    // ── 本地文件删除（走 DB 拿条目 + 纯文件断言）──────────────────────────

    #[test]
    fn db_delete_collection_local_files_removes_only_media_and_caches() {
        let _serial = lock_db_test_serial();
        let root = fake_media_root("local_files");
        std::fs::create_dir_all(root.join("sub")).unwrap();
        write_test_image(&root.join("a.bmp"));
        write_test_image(&root.join("sub/b.bmp"));
        std::fs::write(root.join("stray.txt"), b"keep me").unwrap();

        let folder_path = std::fs::canonicalize(&root).unwrap();
        let collection =
            import_media_folder(folder_path.to_string_lossy().into_owned()).unwrap();

        let deleted = delete_collection_local_files(collection.id.clone()).unwrap();
        assert_eq!(deleted, 2, "只应删除媒体文件");
        assert!(!root.join("a.bmp").exists());
        assert!(!root.join("sub").exists(), "空壳子目录应被收掉");
        assert!(
            !root.join(".SlimeWorks").exists(),
            "资源旁缓存目录应一并清理"
        );
        assert!(root.join("stray.txt").exists(), "非媒体残留文件不得误删");
        assert!(root.exists(), "目录非空时不得删除集合根目录");
        assert!(
            root.parent().unwrap().exists(),
            "清理绝不向上传播到父目录"
        );

        // 本函数刻意不动数据库：集合与条目记录仍在库里（后续由 delete_media_collection 收口）
        assert!(db_row(collection_table_name(), &collection.id).is_some());
        assert_eq!(row_count_for_collection(item_table_name(), &collection.id), 2);

        assert!(delete_media_collection(collection.id).unwrap());
        let _ = std::fs::remove_dir_all(&root);
    }

    // ── clear_all_local_media：表清空 + 资源缓存清理，绝不动原始媒体 ──────

    #[test]
    fn db_clear_all_local_media_keeps_original_files() {
        let _serial = lock_db_test_serial();
        let root = fake_media_root("clear_all");
        write_test_image(&root.join("a.bmp"));
        let folder_path = std::fs::canonicalize(&root).unwrap();
        let collection =
            import_media_folder(folder_path.to_string_lossy().into_owned()).unwrap();

        // 模拟历史残留的资源缓存文件（另有导入链路生成的封面缓存同目录）
        let tmp_dir = root.join(".SlimeWorks").join("tmp");
        std::fs::create_dir_all(&tmp_dir).unwrap();
        std::fs::write(tmp_dir.join("stale.jpg_w200.jpg"), b"stale").unwrap();
        // 顺带制造一些其他表数据
        let folder = create_media_folder(format!("clear_probe_{}", std::process::id())).unwrap();
        save_collection_order("clear_probe_key".into(), vec!["x".into()]).unwrap();

        let (tables, files) = clear_all_local_media(false, true).unwrap();
        assert_eq!(tables, 7, "应清空 7 张业务表（保留 media_meta）");
        assert!(files >= 2, "stale + 封面缓存至少清掉 2 个文件, got {files}");

        // 原始媒体文件必须原样保留
        assert!(root.join("a.bmp").exists(), "清库绝不删除用户原始媒体文件");
        assert!(!tmp_dir.join("stale.jpg_w200.jpg").exists());
        assert!(tmp_dir.exists(), "只清缓存内容，保留 tmp 目录本身");

        // 各表与内存缓存均已清空
        assert!(db_row(collection_table_name(), &collection.id).is_none());
        assert!(db_row(folder_table_name(), &folder.id).is_none());
        assert!(db_row(collection_order_table_name(), "clear_probe_key").is_none());
        assert!(get_all_media_collections().unwrap().is_empty());
        assert!(get_all_media_folders().unwrap().is_empty());
        assert!(get_all_pending_thumbnail_tasks().unwrap().is_empty());

        // 清库后"已导入"拦截同步失效：同一目录可再次导入
        let reimported = import_media_folder(folder_path.to_string_lossy().into_owned())
            .expect("清库后应允许重新导入");
        assert_ne!(reimported.id, collection.id);
        assert!(delete_media_collection(reimported.id).unwrap());

        let _ = std::fs::remove_dir_all(&root);
    }

    // ── 缩略图任务持久化（失败重投链路）───────────────────────────────────

    #[test]
    fn db_failed_thumbnail_task_persists_and_completes() {
        let _serial = lock_db_test_serial();
        let root = fake_media_root("thumb_task");
        // 内容是垃圾数据的 .jpg：ffmpeg 与纯 Rust 解码都必然失败，结果不依赖 ffmpeg
        let bogus = root.join("bogus.jpg");
        std::fs::write(&bogus, b"this is definitely not a jpeg").unwrap();
        let bogus_str = bogus.to_string_lossy().into_owned();

        assert!(ensure_cover_thumbnail(bogus_str.clone(), 320).is_none());

        // 失败任务应持久化为 failed + 重试计数自增
        let pending = get_all_pending_thumbnail_tasks().unwrap();
        let task = pending
            .iter()
            .find(|t| t.file_path == bogus_str && t.width == 320)
            .expect("失败任务应留在 media_thumbnail_tasks 表");
        assert_eq!(task.status, "failed");
        assert_eq!(task.retries, 1);
        assert_eq!(thumb_retry_count(&thumb_task_key(&bogus_str, 320)), 1);

        // 再试一次：重试计数应连续累加（内存表跨调用保持）
        assert!(ensure_cover_thumbnail(bogus_str.clone(), 320).is_none());
        let pending = get_all_pending_thumbnail_tasks().unwrap();
        let task = pending
            .iter()
            .find(|t| t.file_path == bogus_str && t.width == 320)
            .unwrap();
        assert_eq!(task.retries, 2);

        // 任务记录在表里真实存在（非仅内存）
        assert!(db_row(thumbnail_task_table_name(), &thumb_task_key(&bogus_str, 320)).is_some());

        // 成功语义：删除记录 + 忘掉重试计数（磁盘缓存即真相）
        complete_thumbnail_task(&bogus_str, 320, true);
        assert!(db_row(thumbnail_task_table_name(), &thumb_task_key(&bogus_str, 320)).is_none());
        assert_eq!(thumb_retry_count(&thumb_task_key(&bogus_str, 320)), 0);

        let _ = std::fs::remove_dir_all(&root);
    }

    // ── ensure_cover_thumbnail：不依赖 ffmpeg 的分支 ──────────────────────

    #[test]
    fn cover_thumb_cache_hit_returns_without_touching_db() {
        // 本用例走的是 mark_thumbnail_task_running 之前的提前返回分支，不触碰 DB
        let root = fake_media_root("thumb_hit");
        let src = root.join("cover_src.bmp");
        write_test_image(&src);
        // 预先塞一个非空邻近缓存 → 应直接命中并原样返回
        let cached = adjacent_cache_path(&src, 250).unwrap();
        std::fs::create_dir_all(cached.parent().unwrap()).unwrap();
        std::fs::write(&cached, b"cached-bytes").unwrap();
        assert_eq!(
            ensure_cover_thumbnail(src.to_string_lossy().into_owned(), 250),
            Some(cached.to_string_lossy().into_owned())
        );
        // 命中时不得改写缓存内容
        assert_eq!(std::fs::read(&cached).unwrap(), b"cached-bytes");

        // 不支持的扩展名在入口就被拒绝（返回 None，不建任何缓存目录）
        let txt = root.join("note.txt");
        std::fs::write(&txt, b"x").unwrap();
        assert!(ensure_cover_thumbnail(txt.to_string_lossy().into_owned(), 320).is_none());
        assert!(!root.join("sub").exists());

        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn is_valid_cache_hit_semantics() {
        let root = fake_media_root("cache_hit");
        // 不存在 → false
        assert!(!is_valid_cache_hit(&root.join("missing.jpg")));
        // 非空文件 → true
        let ok = root.join("ok.jpg");
        std::fs::write(&ok, b"x").unwrap();
        assert!(is_valid_cache_hit(&ok));
        // 零字节残留 → false 且当场删除，给重新生成让路
        let zero = root.join("zero.jpg");
        std::fs::write(&zero, b"").unwrap();
        assert!(!is_valid_cache_hit(&zero));
        assert!(!zero.exists(), "零字节缓存残留应被删除");
        // 目录不是有效命中
        assert!(!is_valid_cache_hit(&root));
        let _ = std::fs::remove_dir_all(&root);
    }

    // ── 节点内存缩略图缓存（纯内存，不落盘，不依赖 ffmpeg）───────────────

    #[test]
    fn generate_thumbnail_bytes_plain_image_and_memory_cache() {
        let root = fake_media_root("node_thumb");
        let img = root.join("plain.bmp");
        write_test_image(&img);
        let img_str = img.to_string_lossy().into_owned();
        let key = format!("{}|200", img_str);

        // 首次：唯一路径必然未命中内存缓存，走纯 Rust 缩放（BMP 属位图，不经过 ffmpeg）
        let bytes = generate_thumbnail_bytes(img_str.clone(), 200).expect("应能生成缩略图字节");
        assert!(bytes.len() > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8, "输出应是 JPEG 字节流");

        // 用哨兵值污染内存缓存：再次调用应原样返回哨兵 → 证明命中走的是内存缓存
        let probe = b"__mem_cache_probe__".to_vec();
        node_thumb_put(&key, probe.clone());
        assert_eq!(generate_thumbnail_bytes(img_str.clone(), 200).unwrap(), probe);
        // 不同宽度是另一个 key，不受哨兵影响
        assert_ne!(
            generate_thumbnail_bytes(img_str.clone(), 99).unwrap(),
            probe
        );

        // 全程不落盘：内存缓存路径绝不能在资源旁建 .SlimeWorks
        assert!(
            !root.join(".SlimeWorks").exists(),
            "节点内存缓存不得向资源目录写任何文件"
        );

        // 不支持的扩展名 → None
        assert!(generate_thumbnail_bytes(root.join("x.txt").to_string_lossy().into_owned(), 200)
            .is_none());
        let _ = std::fs::remove_dir_all(&root);
    }

    // ── find / ensure_collection_config_dir 边界补充 ──────────────────────

    #[test]
    fn config_dir_search_skips_hidden_and_respects_depth() {
        // 根目录不存在：find/ensure 都是 None（固定名，任何用例都不会创建它）
        let missing = std::env::temp_dir().join("slime_mc_cfg_missing");
        assert!(find_collection_config_dir(missing.to_string_lossy().into_owned()).is_none());
        assert!(ensure_collection_config_dir(missing.to_string_lossy().into_owned()).is_none());

        let root = fake_media_root("cfg_search");
        // 藏在隐藏目录里的 .SlimeWorks：BFS 不进入隐藏目录 → 找不到
        std::fs::create_dir_all(root.join(".hidden/.SlimeWorks")).unwrap();
        assert!(find_collection_config_dir(root.to_string_lossy().into_owned()).is_none());
        // ensure 找不到现成的就在根目录新建
        let ensured = ensure_collection_config_dir(root.to_string_lossy().into_owned()).unwrap();
        assert_eq!(ensured, root.join(".SlimeWorks").to_string_lossy());
        assert!(Path::new(&ensured).is_dir());
        // 已有根级命中时 ensure 不再重复创建、也不改变位置
        assert_eq!(
            ensure_collection_config_dir(root.to_string_lossy().into_owned()).unwrap(),
            ensured
        );
        let _ = std::fs::remove_dir_all(&root);

        // 深度边界：MAX_DEPTH=8 → 第 7 层可见、第 8 层不可见
        let root2 = fake_media_root("cfg_depth");
        let mut at_depth7 = root2.clone();
        for i in 0..7 {
            at_depth7 = at_depth7.join(format!("d{}", i));
        }
        std::fs::create_dir_all(at_depth7.join(".SlimeWorks")).unwrap();
        assert!(find_collection_config_dir(root2.to_string_lossy().into_owned()).is_some());
        let root3 = fake_media_root("cfg_depth_overflow");
        let mut deep = root3.clone();
        for i in 0..8 {
            deep = deep.join(format!("d{}", i));
        }
        std::fs::create_dir_all(deep.join(".SlimeWorks")).unwrap();
        assert!(
            find_collection_config_dir(root3.to_string_lossy().into_owned()).is_none(),
            "超过 MAX_DEPTH 的分支应按未命中处理"
        );
        let _ = std::fs::remove_dir_all(&root2);
        let _ = std::fs::remove_dir_all(&root3);
    }

    // ── check_paths_exist / cleanup_dir_contents ──────────────────────────

    #[test]
    fn check_paths_exist_mixes_existing_and_missing() {
        let root = fake_media_root("paths_exist");
        let file = root.join("f.txt");
        std::fs::write(&file, b"x").unwrap();
        let dir = root.join("d");
        std::fs::create_dir_all(&dir).unwrap();
        let result = check_paths_exist(vec![
            file.to_string_lossy().into_owned(),
            dir.to_string_lossy().into_owned(),
            root.join("missing").to_string_lossy().into_owned(),
            String::new(),
        ]);
        assert_eq!(result, vec![true, true, false, false]);
        assert!(check_paths_exist(vec![]).is_empty());
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn cleanup_dir_contents_removes_entries_but_keeps_dir() {
        let root = fake_media_root("cleanup_contents");
        std::fs::create_dir_all(root.join("sub/inner")).unwrap();
        std::fs::write(root.join("a.jpg"), b"x").unwrap();
        std::fs::write(root.join("sub/b.jpg"), b"x").unwrap();
        // 一个目录条目 + 一个文件条目，各计 1
        assert_eq!(cleanup_dir_contents(&root), 2);
        assert!(root.exists(), "目录本身必须保留");
        assert!(!root.join("sub").exists(), "子目录应被递归删除");
        // 空目录再清 → 0；不存在的路径 → 0
        assert_eq!(cleanup_dir_contents(&root), 0);
        assert_eq!(cleanup_dir_contents(&root.join("nope")), 0);
        let _ = std::fs::remove_dir_all(&root);
    }

    // ── ffmpeg 全局路径注册 / 进程清理 ────────────────────────────────────

    #[test]
    fn ffmpeg_path_registration_roundtrip_with_restore() {
        // 与其他用例串行，避免中途改全局路径影响并发缩略图链路
        let _serial = lock_db_test_serial();
        let original = ffmpeg_cmd();
        let probe = format!("/tmp/fake_ffmpeg_{}", std::process::id());
        register_ffmpeg_path(probe.clone());
        assert_eq!(ffmpeg_cmd(), probe);
        // 还原，避免污染同进程其他用例
        register_ffmpeg_path(original.clone());
        assert_eq!(ffmpeg_cmd(), original);
        // ffprobe 独立注册互不串台
        let ffprobe_original = ffprobe_cmd();
        register_ffprobe_path("/tmp/fake_ffprobe".into());
        assert_eq!(ffprobe_cmd(), "/tmp/fake_ffprobe");
        assert_ne!(ffmpeg_cmd(), ffprobe_cmd());
        register_ffprobe_path(ffprobe_original);
    }

    #[cfg(unix)]
    #[test]
    fn kill_all_terminates_tracked_child_process() {
        use std::os::unix::process::ExitStatusExt;
        let _serial = lock_db_test_serial();
        // 起一个真实子进程并登记 PID，验证 kill_all 会终止它并清空跟踪列表
        let mut child = std::process::Command::new("sleep")
            .arg("30")
            .spawn()
            .expect("应能启动 sleep 子进程");
        let pid = child.id();
        assert!(pid > 0);
        track_ffmpeg_pid(pid);
        kill_all_ffmpeg_processes();
        let status = child.wait().expect("等待被杀子进程回收");
        assert!(
            status.signal().is_some(),
            "跟踪列表中的 PID 应被 SIGKILL 终止"
        );
        // 跟踪列表已清空：再调一次是安全空操作
        kill_all_ffmpeg_processes();
        assert!(FFMPEG_PIDS.read().unwrap().is_empty());
    }
}
