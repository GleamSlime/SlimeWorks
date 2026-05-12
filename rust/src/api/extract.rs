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
