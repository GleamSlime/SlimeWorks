use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ArchiveInfo {
    pub path: String,
    pub file_name: String,
    pub file_size: u64,
    pub is_password_protected: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExtractProgress {
    pub total_archives: u32,
    pub current_archive_index: u32,
    pub current_archive_name: String,
    pub current_archive_progress: f64,
    pub total_progress: f64,
    pub total_file_size: u64,
    pub extracted_file_size: u64,
    pub elapsed_seconds: f64,
    pub estimated_remaining_seconds: f64,
    pub status: ExtractStatus,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum ExtractStatus {
    Idle,
    Scanning,
    Extracting,
    Completed,
    Failed,
    Cancelled,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExtractResult {
    pub success: bool,
    pub total_archives: u32,
    pub total_file_size: u64,
    pub extracted_size: u64,
    pub elapsed_seconds: f64,
    pub failed_archives: Vec<String>,
    pub error_message: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExtractConfig {
    pub source_dir: String,
    pub output_dir: String,
    pub output_mode: ExtractOutputMode,
    pub password: Option<String>,
    pub parallel_count: u32,
    pub delete_after_extract: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum ExtractOutputMode {
    SameDirectory,
    FlatToOutput,
    ByArchiveName,
    PreserveStructure,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PasswordEntry {
    pub id: String,
    pub password: String,
    pub remark: Option<String>,
    pub created_at: i64,
}
