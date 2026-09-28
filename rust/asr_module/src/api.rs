use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};

use crate::audio;
use crate::models;
use crate::runtime;
use crate::sidecar;
use crate::srt;
use crate::types::{AsrStatus, AsrSubtitleResult};

/// 同一时刻只允许一个识别任务（SenseVoice 已占用全部线程，并发只会更慢）
static TRANSCRIBE_BUSY: AtomicBool = AtomicBool::new(false);

/// 支持的媒体扩展名（右键菜单"识别字幕"的过滤依据与此一致）
pub fn is_supported_media(path: &str) -> bool {
    matches!(
        Path::new(path)
            .extension()
            .and_then(|e| e.to_str())
            .map(|e| e.to_ascii_lowercase())
            .as_deref(),
        Some("mp4") | Some("mkv") | Some("mov") | Some("avi") | Some("flv") | Some("webm")
            | Some("ts") | Some("m4v") | Some("wmv") | Some("mp3") | Some("wav") | Some("m4a")
            | Some("flac") | Some("aac") | Some("ogg") | Some("opus") | Some("wma")
    )
}

/// 汇总部署状态，供设置页展示
pub fn get_status() -> AsrStatus {
    let exe = runtime::find_sidecar_exec();
    AsrStatus {
        runtime_ready: exe.is_some(),
        runtime_version: runtime::SHERPA_VERSION.to_string(),
        runtime_exec_path: exe.map(|p| p.to_string_lossy().into_owned()),
        model_ready: models::is_model_ready(),
        vad_ready: models::is_vad_ready(),
        model_dir: runtime::asr_root().join("models").to_string_lossy().into_owned(),
        disk_usage_bytes: runtime::runtime_disk_usage() + models::models_disk_usage(),
    }
}

/// 是否已完整部署（运行时 + 两套模型齐备）
pub fn is_ready() -> bool {
    runtime::is_runtime_ready() && models::is_model_ready() && models::is_vad_ready()
}

/// 一键部署：下载 sidecar 运行时 + SenseVoice/VAD 模型（阻塞，需后台线程调用）
pub fn deploy_all() -> Result<(), String> {
    runtime::download_runtime()?;
    models::download_models()?;
    runtime::set_deploy_done();
    slime_logger::sw_info!("[asr] 一键部署完成");
    Ok(())
}

/// 删除本地部署（运行时 + 模型）
pub fn remove_deployment() -> Result<(), String> {
    runtime::remove_runtime()?;
    models::remove_models()?;
    Ok(())
}

/// 部署进度（0~100），空闲返回 -1
pub fn get_deploy_progress() -> f64 {
    runtime::get_deploy_progress()
}

/// 部署阶段：0 空闲 / 1 下载 / 2 解压 / 3 完成 / 4 失败
pub fn get_deploy_stage() -> u8 {
    runtime::get_deploy_stage()
}

/// 识别进度（0~100），空闲返回 -1
pub fn get_transcribe_progress() -> f64 {
    sidecar::get_transcribe_progress()
}

/// 取消正在进行的识别
pub fn cancel_transcribe() -> bool {
    sidecar::cancel()
}

/// 读取并解析磁盘上的字幕文件，供"翻译字幕"流程取段落与时间轴
pub fn read_subtitle_file(srt_path: String) -> Result<Vec<crate::types::AsrSegment>, String> {
    if !Path::new(&srt_path).exists() {
        return Err(format!("字幕文件不存在: {}", srt_path));
    }
    srt::read_srt(&srt_path)
}

/// 识别媒体文件并输出带时间轴的 SRT 字幕
///
/// - `media_path`：mp4/mkv/mp3/wav 等待识别文件
/// - `output_path`：None 表示写到媒体文件同级目录（同名 .srt）；
///   也可以是目录或以 .srt 结尾的文件路径
/// - `language`：zh/en/ja/ko/yue/auto，None 走自动检测
pub fn transcribe_to_srt(
    media_path: String,
    output_path: Option<String>,
    language: Option<String>,
) -> Result<AsrSubtitleResult, String> {
    if TRANSCRIBE_BUSY
        .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
        .is_err()
    {
        return Err("已有识别任务正在进行，请等待其完成".to_string());
    }

    let result = transcribe_inner(&media_path, output_path.as_deref(), language.as_deref());
    TRANSCRIBE_BUSY.store(false, Ordering::SeqCst);

    match &result {
        Ok(r) => slime_logger::sw_info!(
            "[asr] 字幕生成完成: {}（{} 段，耗时 {:.1}s）",
            r.srt_path,
            r.segment_count,
            r.wall_time_secs
        ),
        Err(e) => slime_logger::sw_error!("[asr] 字幕生成失败: {}", e),
    }
    result
}

fn transcribe_inner(
    media_path: &str,
    output_path: Option<&str>,
    language: Option<&str>,
) -> Result<AsrSubtitleResult, String> {
    if !Path::new(media_path).exists() {
        return Err(format!("媒体文件不存在: {}", media_path));
    }
    if !is_ready() {
        return Err("本地语音识别尚未部署，请先在设置中完成一键部署".to_string());
    }

    // 时长用于把 sidecar 输出的段落时间戳换算成百分比进度；探测失败不影响识别
    let duration = audio::probe_duration_secs(media_path);

    let wav = audio::extract_audio_to_wav(media_path)?;
    let recognized = sidecar::recognize(&wav, duration, language, None);
    audio::cleanup_wav(&wav);

    let (segments, wall_time) = recognized?;
    if segments.is_empty() {
        return Err("未识别到任何语音内容（可能是纯音乐或音量过低）".to_string());
    }

    let out_dir: PathBuf = match output_path {
        Some(p) if !p.is_empty() => PathBuf::from(p),
        _ => Path::new(media_path)
            .parent()
            .map(|p| p.to_path_buf())
            .unwrap_or_else(|| PathBuf::from(".")),
    };
    let srt_path = srt::write_srt(media_path, &segments, &out_dir)?;

    Ok(AsrSubtitleResult {
        srt_path,
        segment_count: segments.len(),
        audio_duration_secs: duration,
        wall_time_secs: wall_time,
    })
}
