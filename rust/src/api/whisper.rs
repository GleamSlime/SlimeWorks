use flutter_rust_bridge::frb;

// ── 平台条件编译 ─────────────────────────────────────────────────────────────
// whisper-rs-sys 的 bundled bindings 不支持 32 位 Android (armv7)，
// 且 Whisper 语音识别为桌面端功能，移动端不编译。

#[cfg(not(any(target_os = "android", target_os = "ios")))]
use whisper_module;

// ── FFI 数据类型 ─────────────────────────────────────────────────────────────

/// 模型状态信息
#[derive(Debug, Clone)]
pub struct ModelStatusInfo {
    pub preset_name: String,
    pub display_name: String,
    pub model_file_exists: bool,
    pub model_file_path: Option<String>,
    pub model_file_size: Option<u64>,
    pub approximate_size_mb: u64,
}

/// 识别片段
#[derive(Debug, Clone)]
pub struct TranscriptionSegmentInfo {
    pub start_ms: u64,
    pub end_ms: u64,
    pub text: String,
}

/// 识别结果
#[derive(Debug, Clone)]
pub struct TranscriptionResultInfo {
    pub language: String,
    pub segments: Vec<TranscriptionSegmentInfo>,
    pub full_text: String,
}

// ── 桌面端实现 ───────────────────────────────────────────────────────────────

#[cfg(not(any(target_os = "android", target_os = "ios")))]
fn convert_segment(s: whisper_module::types::TranscriptionSegment) -> TranscriptionSegmentInfo {
    TranscriptionSegmentInfo {
        start_ms: s.start_ms,
        end_ms: s.end_ms,
        text: s.text,
    }
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
fn convert_result(r: whisper_module::types::TranscriptionResult) -> TranscriptionResultInfo {
    TranscriptionResultInfo {
        language: r.language,
        segments: r.segments.into_iter().map(convert_segment).collect(),
        full_text: r.full_text,
    }
}

// ── FFI API ───────────────────────────────────────────────────────────────────

/// 初始化 whisper 配置
#[frb(sync)]
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn whisper_initialize() -> anyhow::Result<()> {
    whisper_module::api::initialize_whisper_db().map_err(|e: String| anyhow::anyhow!(e))
}

/// 初始化 whisper 配置（移动端空实现）
#[frb(sync)]
#[cfg(any(target_os = "android", target_os = "ios"))]
pub fn whisper_initialize() -> anyhow::Result<()> {
    Err(anyhow::anyhow!("Whisper 语音识别不支持当前平台"))
}

/// 获取所有可用模型的状态
#[frb(sync)]
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn whisper_get_model_statuses() -> anyhow::Result<Vec<ModelStatusInfo>> {
    let statuses =
        whisper_module::api::get_all_model_statuses().map_err(|e: String| anyhow::anyhow!(e))?;
    Ok(statuses
        .into_iter()
        .map(|s| {
            let preset = s.selected_model;
            ModelStatusInfo {
                preset_name: preset.as_str().to_string(),
                display_name: preset.display_name(),
                model_file_exists: s.model_file_exists,
                model_file_path: s.model_file_path,
                model_file_size: s.model_file_size,
                approximate_size_mb: preset.approximate_size_mb(),
            }
        })
        .collect())
}

/// 获取所有可用模型的状态（移动端空实现）
#[frb(sync)]
#[cfg(any(target_os = "android", target_os = "ios"))]
pub fn whisper_get_model_statuses() -> anyhow::Result<Vec<ModelStatusInfo>> {
    Ok(vec![])
}

/// 获取当前选中的模型名称
#[frb(sync)]
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn whisper_get_selected_model() -> anyhow::Result<String> {
    Ok(whisper_module::api::get_selected_model()
        .as_str()
        .to_string())
}

/// 获取当前选中的模型名称（移动端空实现）
#[frb(sync)]
#[cfg(any(target_os = "android", target_os = "ios"))]
pub fn whisper_get_selected_model() -> anyhow::Result<String> {
    Ok(String::new())
}

/// 设置当前选中的模型
#[frb(sync)]
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn whisper_set_selected_model(preset_name: String) -> anyhow::Result<bool> {
    whisper_module::api::set_selected_model(preset_name).map_err(|e: String| anyhow::anyhow!(e))
}

/// 设置当前选中的模型（移动端空实现）
#[frb(sync)]
#[cfg(any(target_os = "android", target_os = "ios"))]
pub fn whisper_set_selected_model(_preset_name: String) -> anyhow::Result<bool> {
    Err(anyhow::anyhow!("Whisper 语音识别不支持当前平台"))
}

/// 下载指定模型（阻塞，建议在后台调用）
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn whisper_download_model(preset_name: String) -> anyhow::Result<u64> {
    whisper_module::api::download_model(preset_name).map_err(|e: String| anyhow::anyhow!(e))
}

/// 下载指定模型（移动端空实现）
#[cfg(any(target_os = "android", target_os = "ios"))]
pub fn whisper_download_model(_preset_name: String) -> anyhow::Result<u64> {
    Err(anyhow::anyhow!("Whisper 语音识别不支持当前平台"))
}

/// 删除指定模型
#[frb(sync)]
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn whisper_delete_model(preset_name: String) -> anyhow::Result<bool> {
    whisper_module::api::delete_model(preset_name).map_err(|e: String| anyhow::anyhow!(e))
}

/// 删除指定模型（移动端空实现）
#[frb(sync)]
#[cfg(any(target_os = "android", target_os = "ios"))]
pub fn whisper_delete_model(_preset_name: String) -> anyhow::Result<bool> {
    Err(anyhow::anyhow!("Whisper 语音识别不支持当前平台"))
}

/// 识别音频文件并生成 CUE 文件
/// 返回识别结果（包含片段和完整文本），同时生成 .cue 文件在音频同级目录
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn whisper_transcribe(
    audio_file_path: String,
    language: Option<String>,
) -> anyhow::Result<TranscriptionResultInfo> {
    whisper_module::api::transcribe_and_generate_cue(audio_file_path, language)
        .map(convert_result)
        .map_err(|e: String| anyhow::anyhow!(e))
}

/// 识别音频文件并生成 CUE 文件（移动端空实现）
#[cfg(any(target_os = "android", target_os = "ios"))]
pub fn whisper_transcribe(
    _audio_file_path: String,
    _language: Option<String>,
) -> anyhow::Result<TranscriptionResultInfo> {
    Err(anyhow::anyhow!("Whisper 语音识别不支持当前平台"))
}
