use flutter_rust_bridge::frb;

#[frb(sync)]
pub fn extract_init_password_table(db_path: String) {
    extract_module::extract_init_password_table(db_path);
}

#[frb(sync)]
pub fn extract_list_passwords_json() -> String {
    extract_module::extract_list_passwords_json()
}

#[frb(sync)]
pub fn extract_add_password(password: String, remark: Option<String>) -> String {
    extract_module::extract_add_password(password, remark)
}

#[frb(sync)]
pub fn extract_remove_password(id: String) -> bool {
    extract_module::extract_remove_password(id)
}

#[frb(sync)]
pub fn extract_update_password_remark(id: String, remark: Option<String>) -> bool {
    extract_module::extract_update_password_remark(id, remark)
}

#[frb(sync)]
pub fn extract_scan_archives_json(dir: String) -> String {
    extract_module::extract_scan_archives_json(dir)
}

#[frb(sync)]
pub fn extract_get_progress_json() -> String {
    extract_module::extract_get_progress_json()
}

#[frb(sync)]
pub fn extract_get_result_json() -> String {
    extract_module::extract_get_result_json()
}

#[frb(sync)]
pub fn extract_start(config_json: String) {
    extract_module::extract_start(config_json);
}

#[frb(sync)]
pub fn extract_cancel() {
    extract_module::extract_cancel();
}

#[frb(sync)]
pub fn extract_format_file_size(bytes: u64) -> String {
    extract_module::extract_format_file_size(bytes)
}

/// 把本地目录整棵打包成临时 zip，返回 zip 绝对路径（上传到远程节点用）。
/// 打包是重 IO + CPU 操作，移入 spawn_blocking，避免卡住 Dart 侧。
pub async fn zip_directory_to_tmp(
    src_dir: String,
    entry_root: String,
) -> Result<String, String> {
    tokio::task::spawn_blocking(move || extract_module::zip_directory_to_tmp(src_dir, entry_root))
        .await
        .map_err(|e| format!("打包任务调度失败: {}", e))?
}
