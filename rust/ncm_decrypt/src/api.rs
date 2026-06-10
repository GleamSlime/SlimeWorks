use slime_logger::sw_error;
use std::sync::{Arc, Mutex, OnceLock};

use crate::decrypt;
use crate::types::*;

static PROGRESS_STATE: OnceLock<Arc<Mutex<Option<NcmDecryptProgress>>>> = OnceLock::new();
static RESULT_STATE: OnceLock<Arc<Mutex<Option<NcmDecryptResult>>>> = OnceLock::new();

fn get_progress_state() -> &'static Arc<Mutex<Option<NcmDecryptProgress>>> {
    PROGRESS_STATE.get_or_init(|| Arc::new(Mutex::new(None)))
}

fn get_result_state() -> &'static Arc<Mutex<Option<NcmDecryptResult>>> {
    RESULT_STATE.get_or_init(|| Arc::new(Mutex::new(None)))
}

/// 扫描目录下的 NCM 文件，返回 JSON
pub fn ncm_scan_files_json(dir: String) -> String {
    match decrypt::scan_ncm_files(&dir) {
        Ok(files) => serde_json::to_string(&files).unwrap_or_else(|_| "[]".to_string()),
        Err(_) => "[]".to_string(),
    }
}

/// 获取当前解密进度 JSON
pub fn ncm_get_progress_json() -> String {
    let state = get_progress_state().lock().unwrap();
    match state.as_ref() {
        Some(p) => serde_json::to_string(p).unwrap_or_else(|_| "{}".to_string()),
        None => "{}".to_string(),
    }
}

/// 获取解密结果 JSON
pub fn ncm_get_result_json() -> String {
    let state = get_result_state().lock().unwrap();
    match state.as_ref() {
        Some(r) => serde_json::to_string(r).unwrap_or_else(|_| "{}".to_string()),
        None => "{}".to_string(),
    }
}

/// 启动解密任务（后台线程）
pub fn ncm_decrypt_start(config_json: String) {
    let config_json_clone = config_json.clone();
    std::thread::spawn(move || {
        ncm_decrypt_run(config_json_clone);
    });
}

/// 取消解密任务
pub fn ncm_decrypt_cancel() {
    let mut state = get_progress_state().lock().unwrap();
    if let Some(ref mut progress) = *state {
        progress.status = NcmDecryptStatus::Cancelled;
    }
}

/// 后台执行解密
fn ncm_decrypt_run(config_json: String) {
    let config: NcmDecryptConfig = match serde_json::from_str(&config_json) {
        Ok(c) => c,
        Err(e) => {
            let progress = NcmDecryptProgress {
                total_files: 0,
                current_file_index: 0,
                current_file_name: String::new(),
                total_progress: 0.0,
                elapsed_seconds: 0.0,
                status: NcmDecryptStatus::Failed,
            };
            *get_progress_state().lock().unwrap() = Some(progress);
            *get_result_state().lock().unwrap() = Some(NcmDecryptResult {
                success: false,
                total_files: 0,
                success_count: 0,
                failed_count: 0,
                elapsed_seconds: 0.0,
                failed_files: vec![],
                error_message: Some(format!("解析配置失败: {}", e)),
            });
            sw_error!("解析配置失败: {}", e);
            return;
        }
    };

    *get_result_state().lock().unwrap() = None;

    let progress_state = get_progress_state().clone();

    let result = decrypt::run_decrypt(&config, &|p| {
        *progress_state.lock().unwrap() = Some(p);
    });

    let final_progress = NcmDecryptProgress {
        total_files: result.total_files,
        current_file_index: result.total_files,
        current_file_name: String::new(),
        total_progress: 100.0,
        elapsed_seconds: result.elapsed_seconds,
        status: if result.success {
            NcmDecryptStatus::Completed
        } else {
            NcmDecryptStatus::Failed
        },
    };
    *get_progress_state().lock().unwrap() = Some(final_progress);
    *get_result_state().lock().unwrap() = Some(result);
}
