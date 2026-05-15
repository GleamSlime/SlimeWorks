use std::sync::{Arc, Mutex, OnceLock};

use crate::extractor;
use crate::types::*;

static PROGRESS_STATE: OnceLock<Arc<Mutex<Option<ExtractProgress>>>> = OnceLock::new();
static RESULT_STATE: OnceLock<Arc<Mutex<Option<ExtractResult>>>> = OnceLock::new();

fn get_progress_state() -> &'static Arc<Mutex<Option<ExtractProgress>>> {
    PROGRESS_STATE.get_or_init(|| Arc::new(Mutex::new(None)))
}

fn get_result_state() -> &'static Arc<Mutex<Option<ExtractResult>>> {
    RESULT_STATE.get_or_init(|| Arc::new(Mutex::new(None)))
}

const EXTRACT_PASSWORDS_TABLE: &str = "extract_passwords";

pub fn extract_init_password_table(db_path: String) {
    if let Err(e) = db_module::db_init(db_path) {
        log::error!("初始化数据库失败: {}", e);
    }
    if let Err(e) = db_module::db_register_table(EXTRACT_PASSWORDS_TABLE.to_string()) {
        log::error!("注册密码表失败: {}", e);
    }
}

pub fn extract_list_passwords_json() -> String {
    match db_module::db_list_all(EXTRACT_PASSWORDS_TABLE.to_string()) {
        Ok(records) => {
            let entries: Vec<PasswordEntry> = records
                .into_iter()
                .filter_map(|r| serde_json::from_str::<PasswordEntry>(&r.value).ok())
                .collect();
            serde_json::to_string(&entries).unwrap_or_else(|_| "[]".to_string())
        }
        Err(_) => "[]".to_string(),
    }
}

pub fn extract_add_password(password: String, remark: Option<String>) -> String {
    let entry = PasswordEntry {
        id: chrono::Utc::now().timestamp_millis().to_string(),
        password,
        remark,
        created_at: chrono::Utc::now().timestamp_millis(),
    };
    let json = serde_json::to_string(&entry).unwrap_or_default();
    if let Err(e) = db_module::db_set(EXTRACT_PASSWORDS_TABLE.to_string(), entry.id.clone(), json) {
        log::error!("保存密码失败: {}", e);
    }
    serde_json::to_string(&entry).unwrap_or_default()
}

pub fn extract_remove_password(id: String) -> bool {
    db_module::db_delete(EXTRACT_PASSWORDS_TABLE.to_string(), id).unwrap_or(false)
}

pub fn extract_update_password_remark(id: String, remark: Option<String>) -> bool {
    let existing = match db_module::db_get(EXTRACT_PASSWORDS_TABLE.to_string(), id.clone()) {
        Ok(Some(json)) => serde_json::from_str::<PasswordEntry>(&json).ok(),
        _ => None,
    };
    match existing {
        Some(mut entry) => {
            entry.remark = remark;
            let json = serde_json::to_string(&entry).unwrap_or_default();
            db_module::db_set(EXTRACT_PASSWORDS_TABLE.to_string(), id, json).is_ok()
        }
        None => false,
    }
}

pub fn extract_scan_archives_json(dir: String) -> String {
    match extractor::scan_archives(&dir) {
        Ok(archives) => serde_json::to_string(&archives).unwrap_or_else(|_| "[]".to_string()),
        Err(_) => "[]".to_string(),
    }
}

pub fn extract_get_progress_json() -> String {
    let state = get_progress_state().lock().unwrap();
    match state.as_ref() {
        Some(p) => serde_json::to_string(p).unwrap_or_else(|_| "{}".to_string()),
        None => "{}".to_string(),
    }
}

pub fn extract_get_result_json() -> String {
    let state = get_result_state().lock().unwrap();
    match state.as_ref() {
        Some(r) => serde_json::to_string(r).unwrap_or_else(|_| "{}".to_string()),
        None => "{}".to_string(),
    }
}

pub fn extract_run_async(config_json: String) {
    let config: ExtractConfig = match serde_json::from_str(&config_json) {
        Ok(c) => c,
        Err(e) => {
            let progress = ExtractProgress {
                total_archives: 0,
                current_archive_index: 0,
                current_archive_name: String::new(),
                current_archive_progress: 0.0,
                total_progress: 0.0,
                total_file_size: 0,
                extracted_file_size: 0,
                elapsed_seconds: 0.0,
                estimated_remaining_seconds: 0.0,
                status: ExtractStatus::Failed,
            };
            *get_progress_state().lock().unwrap() = Some(progress);
            *get_result_state().lock().unwrap() = Some(ExtractResult {
                success: false,
                total_archives: 0,
                total_file_size: 0,
                extracted_size: 0,
                elapsed_seconds: 0.0,
                failed_archives: vec![],
                error_message: Some(format!("解析配置失败: {}", e)),
            });
            log::error!("解析配置失败: {}", e);
            return;
        }
    };

    *get_result_state().lock().unwrap() = None;
    extractor::reset_cancel();

    let progress_state = get_progress_state().clone();

    let result = extractor::run_extract(&config, &|p| {
        *progress_state.lock().unwrap() = Some(p);
    });

    let final_progress = ExtractProgress {
        total_archives: result.total_archives,
        current_archive_index: result.total_archives,
        current_archive_name: String::new(),
        current_archive_progress: 1.0,
        total_progress: 1.0,
        total_file_size: result.total_file_size,
        extracted_file_size: result.extracted_size,
        elapsed_seconds: result.elapsed_seconds,
        estimated_remaining_seconds: 0.0,
        status: if result.success {
            ExtractStatus::Completed
        } else {
            ExtractStatus::Failed
        },
    };
    *progress_state.lock().unwrap() = Some(final_progress);
    *get_result_state().lock().unwrap() = Some(result);
}

pub fn extract_start(config_json: String) {
    let config_json_clone = config_json.clone();
    std::thread::spawn(move || {
        extract_run_async(config_json_clone);
    });
}

pub fn extract_cancel() {
    extractor::request_cancel();
}

pub fn extract_format_file_size(bytes: u64) -> String {
    const KB: u64 = 1024;
    const MB: u64 = 1024 * KB;
    const GB: u64 = 1024 * MB;
    const TB: u64 = 1024 * GB;

    if bytes >= TB {
        format!("{:.2} TB", bytes as f64 / TB as f64)
    } else if bytes >= GB {
        format!("{:.2} GB", bytes as f64 / GB as f64)
    } else if bytes >= MB {
        format!("{:.2} MB", bytes as f64 / MB as f64)
    } else if bytes >= KB {
        format!("{:.2} KB", bytes as f64 / KB as f64)
    } else {
        format!("{} B", bytes)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn format_file_size_bytes() {
        assert_eq!(extract_format_file_size(0), "0 B");
        assert_eq!(extract_format_file_size(512), "512 B");
    }

    #[test]
    fn format_file_size_kb() {
        assert_eq!(extract_format_file_size(1024), "1.00 KB");
        assert_eq!(extract_format_file_size(1536), "1.50 KB");
    }

    #[test]
    fn format_file_size_mb() {
        assert_eq!(extract_format_file_size(1024 * 1024), "1.00 MB");
        assert_eq!(extract_format_file_size(5 * 1024 * 1024 + 512 * 1024), "5.50 MB");
    }

    #[test]
    fn format_file_size_gb() {
        assert_eq!(extract_format_file_size(1024 * 1024 * 1024), "1.00 GB");
        assert_eq!(extract_format_file_size(2 * 1024 * 1024 * 1024 + 512 * 1024 * 1024), "2.50 GB");
    }

    #[test]
    fn format_file_size_tb() {
        assert_eq!(extract_format_file_size(1024u64 * 1024 * 1024 * 1024), "1.00 TB");
    }
}
