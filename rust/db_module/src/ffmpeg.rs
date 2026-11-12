//! 外部 ffmpeg/ffprobe 可执行文件路径的进程级注册表。
//!
//! 抽到基础层是因为不止一个业务 crate 要起 ffmpeg：media_collection 生成缩略图、
//! music_player 抽内嵌封面。各抄一份注册表的结果是「Dart 侧只注册到了其中一个」，
//! 另一个仍按裸名 `ffmpeg` 去 PATH 里找——用户装了内置 ffmpeg 而 PATH 里没有时，
//! 那条链路静默失效。注册表只有一份，谁用谁来读。

use std::sync::RwLock;

static FFMPEG_PATH: RwLock<Option<String>> = RwLock::new(None);
static FFPROBE_PATH: RwLock<Option<String>> = RwLock::new(None);

/// 注册 ffmpeg 可执行文件的绝对路径。
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

/// 已注册的 ffmpeg 路径；未注册时退回系统 PATH 中的 "ffmpeg"。
pub fn ffmpeg_cmd() -> String {
    FFMPEG_PATH
        .read()
        .ok()
        .and_then(|g| g.clone())
        .unwrap_or_else(|| "ffmpeg".to_string())
}

/// 已注册的 ffprobe 路径；未注册时退回系统 PATH 中的 "ffprobe"。
pub fn ffprobe_cmd() -> String {
    FFPROBE_PATH
        .read()
        .ok()
        .and_then(|g| g.clone())
        .unwrap_or_else(|| "ffprobe".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 串行锁：这两个静态量是进程级的，并发用例会互相覆盖
    static LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

    fn lock() -> std::sync::MutexGuard<'static, ()> {
        LOCK.lock().unwrap_or_else(|e| e.into_inner())
    }

    #[test]
    fn register_then_read_back_and_restore() {
        let _serial = lock();
        let original = ffmpeg_cmd();
        let original_probe = ffprobe_cmd();

        register_ffmpeg_path("/opt/slime/ffmpeg".to_string());
        assert_eq!(ffmpeg_cmd(), "/opt/slime/ffmpeg");
        // 重复注册覆盖旧值
        register_ffmpeg_path("/opt/slime/ffmpeg2".to_string());
        assert_eq!(ffmpeg_cmd(), "/opt/slime/ffmpeg2");

        register_ffprobe_path("/opt/slime/ffprobe".to_string());
        assert_eq!(ffprobe_cmd(), "/opt/slime/ffprobe");

        // ffmpeg 与 ffprobe 是两条独立注册项，不能串
        register_ffmpeg_path(original.clone());
        assert_eq!(ffmpeg_cmd(), original);
        assert_eq!(ffprobe_cmd(), "/opt/slime/ffprobe");

        register_ffprobe_path(original_probe);
    }
}
