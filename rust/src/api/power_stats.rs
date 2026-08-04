use flutter_rust_bridge::frb;

#[frb(sync)]
pub fn power_stats_init(config_json: String) -> Result<String, String> {
    power_stats::api::power_stats_init(config_json)
}

#[frb(sync)]
pub fn power_stats_update_config(config_json: String) -> Result<(), String> {
    power_stats::api::power_stats_update_config(config_json)
}

#[frb(sync)]
pub fn power_stats_get_config() -> Result<String, String> {
    power_stats::api::power_stats_get_config()
}

#[frb(sync)]
pub fn power_stats_set_enabled(enabled: bool) -> Result<(), String> {
    power_stats::api::power_stats_set_enabled(enabled)
}

pub async fn power_stats_fetch_once() -> Result<String, String> {
    power_stats::api::power_stats_fetch_once().await
}

pub async fn power_stats_start_polling() -> Result<(), String> {
    power_stats::api::power_stats_start_polling().await
}

pub async fn power_stats_stop_polling() -> Result<(), String> {
    power_stats::api::power_stats_stop_polling().await
}

#[frb(sync)]
pub fn power_stats_get_status() -> Result<String, String> {
    power_stats::api::power_stats_get_status()
}

#[frb(sync)]
pub fn power_stats_get_aggregated(range: String) -> Result<String, String> {
    power_stats::api::power_stats_get_aggregated(range)
}

#[frb(sync)]
pub fn power_stats_get_summary() -> Result<String, String> {
    power_stats::api::power_stats_get_summary()
}

#[frb(sync)]
pub fn power_stats_get_logs() -> Result<String, String> {
    power_stats::api::power_stats_get_logs()
}

#[frb(sync)]
pub fn power_stats_clear_logs() -> Result<(), String> {
    power_stats::api::power_stats_clear_logs()
}
