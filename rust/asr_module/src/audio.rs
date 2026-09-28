use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::RwLock;

/// ffmpeg/ffprobe 可执行文件路径（由上层在初始化时注入，未注入时回退到 PATH）
static FFMPEG: RwLock<Option<String>> = RwLock::new(None);
static FFPROBE: RwLock<Option<String>> = RwLock::new(None);

pub fn set_ffmpeg_paths(ffmpeg: Option<String>, ffprobe: Option<String>) {
    if let Some(p) = ffmpeg {
        if !p.is_empty() {
            if let Ok(mut g) = FFMPEG.write() {
                *g = Some(p);
            }
        }
    }
    if let Some(p) = ffprobe {
        if !p.is_empty() {
            if let Ok(mut g) = FFPROBE.write() {
                *g = Some(p);
            }
        }
    }
}

fn ffmpeg_cmd() -> String {
    FFMPEG
        .read()
        .ok()
        .and_then(|g| g.clone())
        .unwrap_or_else(|| "ffmpeg".to_string())
}

fn ffprobe_cmd() -> String {
    FFPROBE
        .read()
        .ok()
        .and_then(|g| g.clone())
        .unwrap_or_else(|| "ffprobe".to_string())
}

/// Windows 下隐藏子进程控制台窗口
#[cfg(target_os = "windows")]
pub(crate) fn suppress_console_for(cmd: &mut Command) {
    use std::os::windows::process::CommandExt;
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;
    cmd.creation_flags(CREATE_NO_WINDOW);
}

#[cfg(not(target_os = "windows"))]
pub(crate) fn suppress_console_for(_cmd: &mut Command) {}

/// 用 ffmpeg 抽取音轨并转成 16kHz 单声道 16bit WAV（SenseVoice 要求的输入格式）
/// 返回临时 wav 路径，调用方负责用完删除
pub fn extract_audio_to_wav(media_path: &str) -> Result<PathBuf, String> {
    let out = temp_wav_path(media_path);
    if let Some(parent) = out.parent() {
        std::fs::create_dir_all(parent).map_err(|e| format!("创建临时目录失败: {}", e))?;
    }

    slime_logger::sw_info!("[asr] 抽取音频轨: {} -> {:?}", media_path, out);

    let mut cmd = Command::new(ffmpeg_cmd());
    cmd.args(["-hide_banner", "-loglevel", "error", "-nostdin"])
        .args(["-i", media_path])
        .args(["-vn", "-sn", "-dn"])
        .args(["-ac", "1", "-ar", "16000"])
        .args(["-f", "wav", "-y"])
        .arg(&out)
        .stdout(Stdio::null())
        .stderr(Stdio::piped());
    suppress_console_for(&mut cmd);

    let child = cmd.spawn().map_err(|e| {
        format!(
            "启动 ffmpeg 失败（{}）: {}。请确认 ffmpeg 可用",
            ffmpeg_cmd(),
            e
        )
    })?;
    let status = child
        .wait_with_output()
        .map_err(|e| format!("等待 ffmpeg 结束失败: {}", e))?;

    if !status.status.success() {
        let err = String::from_utf8_lossy(&status.stderr);
        let _ = std::fs::remove_file(&out);
        return Err(format!("ffmpeg 抽取音频失败: {}", err.trim()));
    }
    if !out.exists() {
        return Err("ffmpeg 未生成音频文件".to_string());
    }
    Ok(out)
}

/// 用 ffprobe 读取媒体时长（秒）；失败返回 None（仅影响进度估算，不影响识别）
pub fn probe_duration_secs(media_path: &str) -> Option<f64> {
    let mut cmd = Command::new(ffprobe_cmd());
    cmd.args([
        "-v",
        "error",
        "-show_entries",
        "format=duration",
        "-of",
        "default=noprint_wrappers=1:nokey=1",
    ])
    .arg(media_path)
    .stdout(Stdio::piped())
    .stderr(Stdio::null());
    suppress_console_for(&mut cmd);
    let out = cmd.spawn().ok()?.wait_with_output().ok()?;
    if !out.status.success() {
        return None;
    }
    let text = String::from_utf8_lossy(&out.stdout).trim().to_string();
    let value: f64 = text.parse().ok()?;
    if value > 0.0 {
        Some(value)
    } else {
        None
    }
}

fn temp_wav_path(media_path: &str) -> PathBuf {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};
    let mut hasher = DefaultHasher::new();
    media_path.hash(&mut hasher);
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or(0);
    std::env::temp_dir().join(format!(
        "slimeworks_asr_{}_{}.wav",
        hasher.finish(),
        stamp
    ))
}

/// 删除临时文件（忽略失败）
pub fn cleanup_wav(path: &Path) {
    let _ = std::fs::remove_file(path);
}
