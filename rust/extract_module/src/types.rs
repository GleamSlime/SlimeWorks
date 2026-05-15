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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extract_status_serde_round_trip() {
        let statuses = [
            ExtractStatus::Idle,
            ExtractStatus::Scanning,
            ExtractStatus::Extracting,
            ExtractStatus::Completed,
            ExtractStatus::Failed,
            ExtractStatus::Cancelled,
        ];
        for status in &statuses {
            let json = serde_json::to_string(status).expect("serialize");
            let restored: ExtractStatus = serde_json::from_str(&json).expect("deserialize");
            assert_eq!(&restored, status);
        }
    }

    #[test]
    fn extract_output_mode_serde_round_trip() {
        let modes = [
            ExtractOutputMode::SameDirectory,
            ExtractOutputMode::FlatToOutput,
            ExtractOutputMode::ByArchiveName,
            ExtractOutputMode::PreserveStructure,
        ];
        for mode in &modes {
            let json = serde_json::to_string(mode).expect("serialize");
            let restored: ExtractOutputMode = serde_json::from_str(&json).expect("deserialize");
            assert_eq!(&restored, mode);
        }
    }

    #[test]
    fn archive_info_serde_round_trip() {
        let info = ArchiveInfo {
            path: "/archives/test.zip".to_string(),
            file_name: "test.zip".to_string(),
            file_size: 1024,
            is_password_protected: true,
        };
        let json = serde_json::to_string(&info).expect("serialize");
        let restored: ArchiveInfo = serde_json::from_str(&json).expect("deserialize");
        assert_eq!(restored.path, info.path);
        assert_eq!(restored.file_name, info.file_name);
        assert_eq!(restored.file_size, info.file_size);
        assert_eq!(restored.is_password_protected, info.is_password_protected);
    }

    #[test]
    fn extract_config_serde_round_trip() {
        let config = ExtractConfig {
            source_dir: "/source".to_string(),
            output_dir: "/output".to_string(),
            output_mode: ExtractOutputMode::ByArchiveName,
            password: Some("secret".to_string()),
            parallel_count: 4,
            delete_after_extract: false,
        };
        let json = serde_json::to_string(&config).expect("serialize");
        let restored: ExtractConfig = serde_json::from_str(&json).expect("deserialize");
        assert_eq!(restored.source_dir, config.source_dir);
        assert_eq!(restored.output_mode, config.output_mode);
        assert_eq!(restored.password, config.password);
        assert_eq!(restored.parallel_count, config.parallel_count);
    }

    #[test]
    fn password_entry_serde_round_trip() {
        let entry = PasswordEntry {
            id: "pw-001".to_string(),
            password: "mypass".to_string(),
            remark: Some("备注".to_string()),
            created_at: 1700000000000,
        };
        let json = serde_json::to_string(&entry).expect("serialize");
        let restored: PasswordEntry = serde_json::from_str(&json).expect("deserialize");
        assert_eq!(restored.id, entry.id);
        assert_eq!(restored.password, entry.password);
        assert_eq!(restored.remark, entry.remark);
    }

    #[test]
    fn extract_result_serde_round_trip() {
        let result = ExtractResult {
            success: false,
            total_archives: 5,
            total_file_size: 10000,
            extracted_size: 8000,
            elapsed_seconds: 30.5,
            failed_archives: vec!["a.zip".to_string()],
            error_message: Some("部分失败".to_string()),
        };
        let json = serde_json::to_string(&result).expect("serialize");
        let restored: ExtractResult = serde_json::from_str(&json).expect("deserialize");
        assert_eq!(restored.success, result.success);
        assert_eq!(restored.failed_archives, result.failed_archives);
        assert_eq!(restored.error_message, result.error_message);
    }
}
