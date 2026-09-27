use serde::{Deserialize, Serialize};

/// ASR 部署状态（供设置页"一键部署"展示）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AsrStatus {
    /// sidecar 运行时（sherpa-onnx CLI + 依赖库）是否已就绪
    pub runtime_ready: bool,
    /// 运行时版本号，如 "v1.13.8"
    pub runtime_version: String,
    /// 运行时可执行文件绝对路径
    pub runtime_exec_path: Option<String>,
    /// SenseVoice 模型（model.int8.onnx + tokens.txt）是否已就绪
    pub model_ready: bool,
    /// Silero VAD 模型是否已就绪
    pub vad_ready: bool,
    /// 模型目录
    pub model_dir: String,
    /// 已占用磁盘字节数（运行时 + 模型）
    pub disk_usage_bytes: u64,
}

/// 识别片段（时间为相对音频起始的毫秒）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AsrSegment {
    pub start_ms: u64,
    pub end_ms: u64,
    pub text: String,
}

/// 识别结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AsrSubtitleResult {
    /// 生成的 SRT 文件路径
    pub srt_path: String,
    /// 识别片段数
    pub segment_count: usize,
    /// 音频总时长（秒），ffprobe 不可用时为 None
    pub audio_duration_secs: Option<f64>,
    /// sidecar 进程自身报告的墙钟耗时（秒），可估算 RTF
    pub wall_time_secs: f64,
}
