use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::Mutex;
use std::time::Instant;

use crate::audio::suppress_console_for;
use crate::models;
use crate::runtime;
use crate::types::AsrSegment;

/// 识别进度（百分比 × 100），u32::MAX 表示空闲
static TRANSCRIBE_PROGRESS: AtomicU32 = AtomicU32::new(u32::MAX);
/// 取消请求标记，由读取循环检查并 kill 子进程
static CANCEL_REQUESTED: AtomicBool = AtomicBool::new(false);
/// 当前正在运行的 sidecar 子进程句柄
static RUNNING_CHILD: Mutex<Option<Child>> = Mutex::new(None);

/// 读取识别进度（0~100），空闲时返回 -1
pub fn get_transcribe_progress() -> f64 {
    let val = TRANSCRIBE_PROGRESS.load(Ordering::Relaxed);
    if val == u32::MAX {
        -1.0
    } else {
        val as f64 / 100.0
    }
}

fn set_progress(pct: u32) {
    TRANSCRIBE_PROGRESS.store(pct.min(10000), Ordering::Relaxed);
}

fn mark_idle() {
    TRANSCRIBE_PROGRESS.store(u32::MAX, Ordering::Relaxed);
}

/// 是否有识别任务正在运行
pub fn is_running() -> bool {
    TRANSCRIBE_PROGRESS.load(Ordering::Relaxed) != u32::MAX
}

/// 请求取消当前识别任务（直接 kill 子进程）
pub fn cancel() -> bool {
    if !is_running() {
        return false;
    }
    CANCEL_REQUESTED.store(true, Ordering::SeqCst);
    if let Ok(mut guard) = RUNNING_CHILD.lock() {
        if let Some(child) = guard.as_mut() {
            let _ = child.kill();
        }
    }
    true
}

/// sidecar 单行输出格式：`起始秒 -- 结束秒: 文本`
fn parse_segment_line(line: &str) -> Option<AsrSegment> {
    let (head, text) = line.split_once(": ").or_else(|| line.split_once(':'))?;
    let text = text.trim();
    if text.is_empty() {
        return None;
    }
    let (start_s, end_s) = head.split_once("--")?;
    let start_ms = (start_s.trim().parse::<f64>().ok()? * 1000.0).max(0.0) as u64;
    let end_ms = (end_s.trim().parse::<f64>().ok()? * 1000.0).max(0.0) as u64;
    if end_ms <= start_ms {
        return None;
    }
    Some(AsrSegment {
        start_ms,
        end_ms,
        text: text.to_string(),
    })
}

/// 运行 sidecar 对 wav 做 VAD 分段 + 非流式识别
///
/// - `wav_path`：16kHz 单声道 wav
/// - `duration_secs`：音频总时长，用于换算进度（None 时进度不可用）
/// - `language`：auto/zh/en/ja/ko/yue，None 视为 auto
///
/// 返回（识别片段，墙钟耗时秒）
pub fn recognize(
    wav_path: &Path,
    duration_secs: Option<f64>,
    language: Option<&str>,
    num_threads: Option<u32>,
) -> Result<(Vec<AsrSegment>, f64), String> {
    let exe = runtime::find_sidecar_exec().ok_or("sidecar 运行时未部署，请先完成一键部署")?;
    let model = models::sense_voice_model_path().ok_or("SenseVoice 模型未下载")?;
    let tokens = models::tokens_path().ok_or("tokens.txt 未下载")?;
    let vad = models::vad_model_path().ok_or("silero VAD 模型未下载")?;

    CANCEL_REQUESTED.store(false, Ordering::SeqCst);
    set_progress(0);

    let started = Instant::now();
    let result = run_child(
        &exe,
        wav_path,
        &model,
        &tokens,
        &vad,
        language,
        num_threads,
        duration_secs,
    );
    mark_idle();

    let segments = result?;
    if CANCEL_REQUESTED.load(Ordering::SeqCst) {
        return Err("识别已取消".to_string());
    }
    Ok((segments, started.elapsed().as_secs_f64()))
}

#[allow(clippy::too_many_arguments)]
fn run_child(
    exe: &PathBuf,
    wav_path: &Path,
    model: &Path,
    tokens: &Path,
    vad: &Path,
    language: Option<&str>,
    num_threads: Option<u32>,
    duration_secs: Option<f64>,
) -> Result<Vec<AsrSegment>, String> {
    let threads = num_threads.unwrap_or_else(|| {
        std::thread::available_parallelism()
            .map(|n| n.get().min(8) as u32)
            .unwrap_or(4)
    });
    let lang = language.unwrap_or("auto");

    let mut cmd = Command::new(exe);
    cmd.arg(format!("--silero-vad-model={}", vad.to_string_lossy()))
        .arg(format!("--sense-voice-model={}", model.to_string_lossy()))
        .arg(format!("--tokens={}", tokens.to_string_lossy()))
        .arg(format!("--sense-voice-language={}", lang))
        .arg("--sense-voice-use-itn=true")
        .arg(format!("--num-threads={}", threads))
        .arg("--provider=cpu")
        .arg(wav_path)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    // Windows 下 GUI 进程拉起控制台程序会闪黑窗，需显式抑制
    suppress_console_for(&mut cmd);
    add_library_search_paths(&mut cmd, exe.parent().unwrap_or(Path::new(".")));

    slime_logger::sw_info!(
        "[asr] 启动 sidecar: {}（线程 {}，语言 {}）",
        exe.display(),
        threads,
        lang
    );

    let mut child = cmd
        .spawn()
        .map_err(|e| format!("启动 sidecar 失败: {} ({})", e, exe.display()))?;

    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| "无法读取 sidecar 输出".to_string())?;
    let stderr = child.stderr.take();

    // stderr 必须持续排空，否则管道写满会让子进程假死；内容落到应用日志便于排查
    let stderr_thread =
        stderr.map(|err| {
            std::thread::spawn(move || {
                for line in BufReader::new(err).lines().map_while(Result::ok) {
                    if !line.trim().is_empty() {
                        slime_logger::sw_debug!("[asr-sidecar] {}", line);
                    }
                }
            })
        });

    let store_err = {
        match RUNNING_CHILD.lock() {
            Ok(mut guard) => {
                *guard = Some(child);
                None
            }
            Err(_) => Some("sidecar 进程锁异常".to_string()),
        }
    };
    if let Some(e) = store_err {
        if let Some(t) = stderr_thread {
            let _ = t.join();
        }
        return Err(e);
    }

    let mut segments: Vec<AsrSegment> = Vec::new();
    let mut read_err: Option<String> = None;

    for line_result in BufReader::new(stdout).lines() {
        match line_result {
            Ok(line) => {
                if let Some(seg) = parse_segment_line(&line) {
                    if let Some(total) = duration_secs {
                        set_progress((seg.end_ms as f64 / (total * 1000.0) * 10000.0) as u32);
                    }
                    segments.push(seg);
                }
            }
            Err(e) => {
                read_err = Some(format!("读取 sidecar 输出失败: {}", e));
                break;
            }
        }
        if CANCEL_REQUESTED.load(Ordering::SeqCst) {
            break;
        }
    }

    let output = {
        let mut guard = RUNNING_CHILD
            .lock()
            .map_err(|_| "sidecar 进程锁异常".to_string())?;
        match guard.take() {
            Some(c) => c
                .wait_with_output()
                .map_err(|e| format!("等待 sidecar 结束失败: {}", e))?,
            None => return Err("sidecar 进程句柄丢失".to_string()),
        }
    };
    if let Some(t) = stderr_thread {
        let _ = t.join();
    }

    if CANCEL_REQUESTED.load(Ordering::SeqCst) {
        return Err("识别已取消".to_string());
    }
    if let Some(e) = read_err {
        return Err(e);
    }
    if !output.status.success() {
        let err = String::from_utf8_lossy(&output.stderr);
        return Err(format!(
            "sidecar 退出码 {:?}：{}",
            output.status.code(),
            err.trim()
        ));
    }

    Ok(segments)
}

/// 把 sidecar 所在的 bin 目录与同级 lib 目录加入子进程动态库搜索路径
/// （Windows 走 PATH，macOS 走 DYLD_LIBRARY_PATH）
fn add_library_search_paths(cmd: &mut Command, bin_dir: &Path) {
    let lib_dir = bin_dir
        .parent()
        .map(|p| p.join("lib"))
        .unwrap_or_else(|| bin_dir.join("lib"));
    let sep = if cfg!(target_os = "windows") {
        ';'
    } else {
        ':'
    };
    let key = if cfg!(target_os = "macos") {
        "DYLD_LIBRARY_PATH"
    } else {
        "PATH"
    };
    let dirs = format!("{}{}{}", bin_dir.display(), sep, lib_dir.display());
    let existing = std::env::var(key).unwrap_or_default();
    let value = if existing.is_empty() {
        dirs
    } else {
        format!("{}{}{}", dirs, sep, existing)
    };
    cmd.env(key, value);
}

#[cfg(test)]
mod tests {
    use super::parse_segment_line;

    #[test]
    fn parse_standard_segment_line() {
        let seg = parse_segment_line("1.23 -- 4.56: 今天天气不错").unwrap();
        assert_eq!(seg.start_ms, 1230);
        assert_eq!(seg.end_ms, 4560);
        assert_eq!(seg.text, "今天天气不错");
    }

    #[test]
    fn ignore_non_segment_lines() {
        assert!(parse_segment_line("Started: 1727438000").is_none());
        assert!(parse_segment_line("0.10 -- 0.20: ").is_none());
        // sidecar 会丢弃时长不足 0.1s 的片段，这里对非法时间轴同样兜底
        assert!(parse_segment_line("5.00 -- 5.00: ok").is_none());
    }
}
