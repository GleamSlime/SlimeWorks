use flutter_rust_bridge::frb;

#[frb(sync)]
pub fn ncm_scan_files_json(dir: String) -> String {
    ncm_decrypt::ncm_scan_files_json(dir)
}

#[frb(sync)]
pub fn ncm_get_progress_json() -> String {
    ncm_decrypt::ncm_get_progress_json()
}

#[frb(sync)]
pub fn ncm_get_result_json() -> String {
    ncm_decrypt::ncm_get_result_json()
}

#[frb(sync)]
pub fn ncm_decrypt_start(config_json: String) {
    ncm_decrypt::ncm_decrypt_start(config_json);
}

#[frb(sync)]
pub fn ncm_decrypt_cancel() {
    ncm_decrypt::ncm_decrypt_cancel();
}
