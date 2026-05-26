use flutter_rust_bridge::frb;

#[frb(sync)]
pub fn aliyun_ddns_init(config_json: String) -> Result<String, String> {
    aliyun_module::api::aliyun_ddns_init(config_json)
}

#[frb(sync)]
pub fn aliyun_ddns_update_config(config_json: String) -> Result<(), String> {
    aliyun_module::api::aliyun_ddns_update_config(config_json)
}

#[frb(sync)]
pub fn aliyun_ddns_get_config() -> Result<String, String> {
    aliyun_module::api::aliyun_ddns_get_config()
}

#[frb(sync)]
pub fn aliyun_ddns_set_enabled(enabled: bool) -> Result<(), String> {
    aliyun_module::api::aliyun_ddns_set_enabled(enabled)
}

pub async fn aliyun_ddns_check_and_update() -> Result<String, String> {
    aliyun_module::api::aliyun_ddns_check_and_update().await
}

#[frb(sync)]
pub fn aliyun_ddns_get_status() -> Result<String, String> {
    aliyun_module::api::aliyun_ddns_get_status()
}

#[frb(sync)]
pub fn aliyun_ddns_get_logs() -> Result<String, String> {
    aliyun_module::api::aliyun_ddns_get_logs()
}

#[frb(sync)]
pub fn aliyun_ddns_clear_logs() -> Result<(), String> {
    aliyun_module::api::aliyun_ddns_clear_logs()
}

pub async fn aliyun_ddns_describe_domains(
    access_key_id: String,
    access_key_secret: String,
) -> Result<String, String> {
    aliyun_module::api::aliyun_ddns_describe_domains(access_key_id, access_key_secret).await
}

pub async fn aliyun_ddns_describe_domain_records(
    access_key_id: String,
    access_key_secret: String,
    domain_name: String,
) -> Result<String, String> {
    aliyun_module::api::aliyun_ddns_describe_domain_records(
        access_key_id,
        access_key_secret,
        domain_name,
    )
    .await
}