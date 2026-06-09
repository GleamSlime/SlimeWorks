use serde::{Deserialize, Serialize};

/// Whisper 模型预设
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum WhisperModelPreset {
    Tiny,
    Base,
    Small,
    Medium,
    LargeV3,
    LargeV3Turbo,
}

impl WhisperModelPreset {
    pub fn as_str(&self) -> &'static str {
        match self {
            WhisperModelPreset::Tiny => "tiny",
            WhisperModelPreset::Base => "base",
            WhisperModelPreset::Small => "small",
            WhisperModelPreset::Medium => "medium",
            WhisperModelPreset::LargeV3 => "large-v3",
            WhisperModelPreset::LargeV3Turbo => "large-v3-turbo",
        }
    }

    pub fn as_str_list() -> Vec<String> {
        vec![
            "tiny".to_string(),
            "base".to_string(),
            "small".to_string(),
            "medium".to_string(),
            "large-v3".to_string(),
            "large-v3-turbo".to_string(),
        ]
    }

    pub fn from_str_name(name: &str) -> Self {
        match name {
            "tiny" => WhisperModelPreset::Tiny,
            "base" => WhisperModelPreset::Base,
            "small" => WhisperModelPreset::Small,
            "medium" => WhisperModelPreset::Medium,
            "large-v3-turbo" => WhisperModelPreset::LargeV3Turbo,
            _ => WhisperModelPreset::LargeV3,
        }
    }

    /// 模型文件名（ggml 格式）
    pub fn model_filename(&self) -> String {
        format!("ggml-{}.bin", self.as_str())
    }

    /// 模型大约大小（MB）
    pub fn approximate_size_mb(&self) -> u64 {
        match self {
            WhisperModelPreset::Tiny => 75,
            WhisperModelPreset::Base => 142,
            WhisperModelPreset::Small => 466,
            WhisperModelPreset::Medium => 1467,
            WhisperModelPreset::LargeV3 => 2900,
            WhisperModelPreset::LargeV3Turbo => 1600,
        }
    }

    /// 模型下载 URL
    pub fn download_url(&self) -> String {
        format!(
            "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/{}",
            self.model_filename()
        )
    }

    /// 显示名称
    pub fn display_name(&self) -> String {
        match self {
            WhisperModelPreset::Tiny => "Tiny (75MB, 快速但精度低)".to_string(),
            WhisperModelPreset::Base => "Base (142MB, 平衡)".to_string(),
            WhisperModelPreset::Small => "Small (466MB, 推荐)".to_string(),
            WhisperModelPreset::Medium => "Medium (1.5GB, 高精度)".to_string(),
            WhisperModelPreset::LargeV3 => "Large-v3 (2.9GB, 最高精度)".to_string(),
            WhisperModelPreset::LargeV3Turbo => "Large-v3 Turbo (1.6GB, 高精度快速)".to_string(),
        }
    }
}

/// 识别结果片段
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranscriptionSegment {
    /// 开始时间（毫秒）
    pub start_ms: u64,
    /// 结束时间（毫秒）
    pub end_ms: u64,
    /// 识别文本
    pub text: String,
}

/// 识别结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranscriptionResult {
    /// 识别的语言
    pub language: String,
    /// 所有片段
    pub segments: Vec<TranscriptionSegment>,
    /// 完整文本
    pub full_text: String,
}

/// 模型状态信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelStatus {
    /// 当前选择的模型预设
    pub selected_model: WhisperModelPreset,
    /// 模型文件是否存在
    pub model_file_exists: bool,
    /// 模型文件路径
    pub model_file_path: Option<String>,
    /// 模型文件大小（字节）
    pub model_file_size: Option<u64>,
}
