use serde::{Deserialize, Serialize};

/// NCM 文件信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NcmFileInfo {
    pub path: String,
    pub file_name: String,
    pub file_size: u64,
}

/// 解密进度
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NcmDecryptProgress {
    pub total_files: u32,
    pub current_file_index: u32,
    pub current_file_name: String,
    pub total_progress: f64,
    pub elapsed_seconds: f64,
    pub status: NcmDecryptStatus,
}

/// 解密状态
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum NcmDecryptStatus {
    Idle,
    Scanning,
    Decrypting,
    Completed,
    Failed,
    Cancelled,
}

/// 解密结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NcmDecryptResult {
    pub success: bool,
    pub total_files: u32,
    pub success_count: u32,
    pub failed_count: u32,
    pub elapsed_seconds: f64,
    pub failed_files: Vec<NcmFailedFile>,
    pub error_message: Option<String>,
}

/// 解密失败的文件信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NcmFailedFile {
    pub path: String,
    pub reason: String,
}

/// 解密配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NcmDecryptConfig {
    pub source_dir: String,
    pub delete_after_decrypt: bool,
}
