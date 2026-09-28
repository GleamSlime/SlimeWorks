use flutter_rust_bridge::frb;

// ── 平台条件编译 ─────────────────────────────────────────────────────────────
// 本地语音识别依赖 sherpa-onnx sidecar（桌面发行包），移动端不提供本地引擎，
// 移动端仍可通过内网大模型接口做转写（纯 Dart HTTP 实现）。

// ── FFI 数据类型 ─────────────────────────────────────────────────────────────

/// 本地 ASR 部署状态
#[derive(Debug, Clone)]
pub struct AsrStatusInfo {
    pub runtime_ready: bool,
    pub runtime_version: String,
    pub runtime_exec_path: Option<String>,
    pub model_ready: bool,
    pub vad_ready: bool,
    pub model_dir: String,
    pub disk_usage_bytes: u64,
}

/// 字幕生成结果
#[derive(Debug, Clone)]
pub struct AsrSubtitleResultInfo {
    pub srt_path: String,
    pub segment_count: usize,
    pub audio_duration_secs: Option<f64>,
    pub wall_time_secs: f64,
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
fn convert_status(s: asr_module::types::AsrStatus) -> AsrStatusInfo {
    AsrStatusInfo {
        runtime_ready: s.runtime_ready,
        runtime_version: s.runtime_version,
        runtime_exec_path: s.runtime_exec_path,
        model_ready: s.model_ready,
        vad_ready: s.vad_ready,
        model_dir: s.model_dir,
        disk_usage_bytes: s.disk_usage_bytes,
    }
}

// ── 桌面端实现 ───────────────────────────────────────────────────────────────

/// 获取本地语音识别部署状态
#[frb(sync)]
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn asr_get_status() -> AsrStatusInfo {
    convert_status(asr_module::api::get_status())
}

/// 本地引擎是否已就绪（运行时 + 模型齐备）
#[frb(sync)]
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn asr_is_ready() -> bool {
    asr_module::api::is_ready()
}

/// 该文件是否可送去识别字幕
#[frb(sync)]
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn asr_is_supported_media(file_path: String) -> bool {
    asr_module::api::is_supported_media(&file_path)
}

/// 一键部署：下载 sherpa-onnx 运行时 + SenseVoice/VAD 模型（阻塞，Dart 侧为 Future）
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn asr_deploy() -> anyhow::Result<()> {
    asr_module::api::deploy_all().map_err(anyhow::Error::msg)
}

/// 删除本地部署
#[frb(sync)]
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn asr_remove_deployment() -> anyhow::Result<()> {
    asr_module::api::remove_deployment().map_err(anyhow::Error::msg)
}

/// 部署进度（0~100），空闲时 -1
#[frb(sync)]
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn asr_get_deploy_progress() -> f64 {
    asr_module::api::get_deploy_progress()
}

/// 部署阶段：0 空闲 / 1 下载 / 2 解压 / 3 完成 / 4 失败
#[frb(sync)]
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn asr_get_deploy_stage() -> i32 {
    asr_module::api::get_deploy_stage() as i32
}

/// 识别媒体文件并输出带时间轴的 SRT 字幕
///
/// * `output_path` - None 表示写到媒体文件同级目录（同名 .srt）
/// * `language`    - zh/en/ja/ko/yue/auto，None 为自动检测
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn asr_transcribe_to_srt(
    media_path: String,
    output_path: Option<String>,
    language: Option<String>,
) -> anyhow::Result<AsrSubtitleResultInfo> {
    // ffmpeg/ffprobe 路径由媒体模块统一管理，这里在调用前注入最新值
    asr_module::audio::set_ffmpeg_paths(
        Some(media_collection::ffmpeg_cmd()),
        Some(media_collection::ffprobe_cmd()),
    );

    let result = asr_module::api::transcribe_to_srt(media_path, output_path, language)
        .map_err(anyhow::Error::msg)?;
    Ok(AsrSubtitleResultInfo {
        srt_path: result.srt_path,
        segment_count: result.segment_count,
        audio_duration_secs: result.audio_duration_secs,
        wall_time_secs: result.wall_time_secs,
    })
}

/// 取消正在进行的识别
#[frb(sync)]
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn asr_cancel_transcribe() -> bool {
    asr_module::api::cancel_transcribe()
}

/// 识别进度（0~100），空闲时 -1
#[frb(sync)]
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn asr_get_transcribe_progress() -> f64 {
    asr_module::api::get_transcribe_progress()
}

/// 字幕片段（远程转写结果回传给 Rust 落盘用）
#[derive(Debug, Clone)]
pub struct AsrSegmentInfo {
    pub start_ms: u64,
    pub end_ms: u64,
    pub text: String,
}

/// 把（可能是内网大模型返回的）字幕片段写成标准 SRT 文件
///
/// 文件写入统一放在 Rust 侧，Dart 只负责传数据与展示
#[frb(sync)]
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn asr_write_srt(
    media_path: String,
    segments: Vec<AsrSegmentInfo>,
    output_dir: String,
) -> anyhow::Result<String> {
    let converted: Vec<asr_module::types::AsrSegment> = segments
        .into_iter()
        .map(|s| asr_module::types::AsrSegment {
            start_ms: s.start_ms,
            end_ms: s.end_ms,
            text: s.text,
        })
        .collect();
    asr_module::srt::write_srt(&media_path, &converted, std::path::Path::new(&output_dir))
        .map_err(anyhow::Error::msg)
}

/// 读取并解析已有的 .srt 字幕（翻译流程的入口）
#[frb(sync)]
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn asr_parse_srt(srt_path: String) -> anyhow::Result<Vec<AsrSegmentInfo>> {
    let segments = asr_module::api::read_subtitle_file(srt_path).map_err(anyhow::Error::msg)?;
    Ok(segments
        .into_iter()
        .map(|s| AsrSegmentInfo {
            start_ms: s.start_ms,
            end_ms: s.end_ms,
            text: s.text,
        })
        .collect())
}

// ── 移动端空实现 ─────────────────────────────────────────────────────────────

/// 获取部署状态（移动端恒为未部署）
#[frb(sync)]
#[cfg(any(target_os = "android", target_os = "ios"))]
pub fn asr_get_status() -> AsrStatusInfo {
    AsrStatusInfo {
        runtime_ready: false,
        runtime_version: String::new(),
        runtime_exec_path: None,
        model_ready: false,
        vad_ready: false,
        model_dir: String::new(),
        disk_usage_bytes: 0,
    }
}

/// 本地引擎是否就绪（移动端不支持）
#[frb(sync)]
#[cfg(any(target_os = "android", target_os = "ios"))]
pub fn asr_is_ready() -> bool {
    false
}

/// 该文件是否可送去识别字幕（移动端交由内网接口处理，一律放行）
#[frb(sync)]
#[cfg(any(target_os = "android", target_os = "ios"))]
pub fn asr_is_supported_media(_file_path: String) -> bool {
    true
}

/// 一键部署（移动端不支持本地引擎）
#[cfg(any(target_os = "android", target_os = "ios"))]
pub fn asr_deploy() -> anyhow::Result<()> {
    Err(anyhow::anyhow!("移动端不支持本地语音识别引擎，请配置内网大模型"))
}

/// 删除本地部署（移动端不支持）
#[frb(sync)]
#[cfg(any(target_os = "android", target_os = "ios"))]
pub fn asr_remove_deployment() -> anyhow::Result<()> {
    Err(anyhow::anyhow!("移动端不支持本地语音识别引擎"))
}

/// 部署进度（移动端恒为空闲）
#[frb(sync)]
#[cfg(any(target_os = "android", target_os = "ios"))]
pub fn asr_get_deploy_progress() -> f64 {
    -1.0
}

/// 部署阶段（移动端恒为空闲）
#[frb(sync)]
#[cfg(any(target_os = "android", target_os = "ios"))]
pub fn asr_get_deploy_stage() -> i32 {
    0
}

/// 识别字幕（移动端不支持本地识别）
#[cfg(any(target_os = "android", target_os = "ios"))]
pub fn asr_transcribe_to_srt(
    _media_path: String,
    _output_path: Option<String>,
    _language: Option<String>,
) -> anyhow::Result<AsrSubtitleResultInfo> {
    Err(anyhow::anyhow!("移动端不支持本地语音识别引擎，请配置内网大模型"))
}

/// 取消识别（移动端无本地任务）
#[frb(sync)]
#[cfg(any(target_os = "android", target_os = "ios"))]
pub fn asr_cancel_transcribe() -> bool {
    false
}

/// 识别进度（移动端恒为空闲）
#[frb(sync)]
#[cfg(any(target_os = "android", target_os = "ios"))]
pub fn asr_get_transcribe_progress() -> f64 {
    -1.0
}

/// 写入 SRT 字幕文件（移动端暂不支持本地媒体文件写入）
#[frb(sync)]
#[cfg(any(target_os = "android", target_os = "ios"))]
pub fn asr_write_srt(
    _media_path: String,
    _segments: Vec<AsrSegmentInfo>,
    _output_dir: String,
) -> anyhow::Result<String> {
    Err(anyhow::anyhow!("移动端暂不支持本地字幕文件读写"))
}

/// 解析字幕文件（移动端暂不支持本地字幕文件读写）
#[frb(sync)]
#[cfg(any(target_os = "android", target_os = "ios"))]
pub fn asr_parse_srt(_srt_path: String) -> anyhow::Result<Vec<AsrSegmentInfo>> {
    Err(anyhow::anyhow!("移动端暂不支持本地字幕文件读写"))
}
