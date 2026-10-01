use flutter_rust_bridge::frb;

/// 流水账模块 API：把 ledger_module 的 FFI 面原样转发出来。
///
/// 约定与 power_stats 一致：入参出参都是 snake_case 的 JSON 字符串，
/// 字段增删只在这里报错，不会把 ledger 的类型扩散到主 crate。
/// 只有纯本地读写用 `#[frb(sync)]`，凡是可能联网的（收信、连接自检）都走 async，
/// 否则同步调用会卡住 UI isolate。

// ── 生命周期 ─────────────────────────────────────────────────────────────────

#[frb(sync)]
pub fn ledger_init(db_path_json: String) -> Result<String, String> {
    ledger_module::api::ledger_init(db_path_json)
}

#[frb(sync)]
pub fn ledger_is_ready() -> bool {
    ledger_module::api::ledger_is_ready()
}

#[frb(sync)]
pub fn ledger_version() -> String {
    ledger_module::api::ledger_version()
}

// ── 账户与类别 ───────────────────────────────────────────────────────────────

#[frb(sync)]
pub fn ledger_list_accounts() -> Result<String, String> {
    ledger_module::api::ledger_list_accounts()
}

#[frb(sync)]
pub fn ledger_upsert_account(account_json: String) -> Result<i64, String> {
    ledger_module::api::ledger_upsert_account(account_json)
}

#[frb(sync)]
pub fn ledger_delete_account(id: i64) -> Result<String, String> {
    ledger_module::api::ledger_delete_account(id)
}

#[frb(sync)]
pub fn ledger_list_categories(direction: String) -> Result<String, String> {
    ledger_module::api::ledger_list_categories(direction)
}

#[frb(sync)]
pub fn ledger_upsert_category(category_json: String) -> Result<i64, String> {
    ledger_module::api::ledger_upsert_category(category_json)
}

#[frb(sync)]
pub fn ledger_delete_category(id: i64) -> Result<String, String> {
    ledger_module::api::ledger_delete_category(id)
}

#[frb(sync)]
pub fn ledger_list_merchant_memory() -> Result<String, String> {
    ledger_module::api::ledger_list_merchant_memory()
}

#[frb(sync)]
pub fn ledger_forget_merchant(merchant_key: String) -> Result<(), String> {
    ledger_module::api::ledger_forget_merchant(merchant_key)
}

// ── 流水 ─────────────────────────────────────────────────────────────────────

#[frb(sync)]
pub fn ledger_list_transactions(filter_json: String) -> Result<String, String> {
    ledger_module::api::ledger_list_transactions(filter_json)
}

#[frb(sync)]
pub fn ledger_count_transactions(filter_json: String) -> Result<i64, String> {
    ledger_module::api::ledger_count_transactions(filter_json)
}

#[frb(sync)]
pub fn ledger_add_transaction(tx_json: String) -> Result<i64, String> {
    ledger_module::api::ledger_add_transaction(tx_json)
}

#[frb(sync)]
pub fn ledger_update_transaction(tx_json: String) -> Result<(), String> {
    ledger_module::api::ledger_update_transaction(tx_json)
}

#[frb(sync)]
pub fn ledger_delete_transaction(id: i64) -> Result<bool, String> {
    ledger_module::api::ledger_delete_transaction(id)
}

#[frb(sync)]
pub fn ledger_check_duplicate(dup_json: String) -> Result<String, String> {
    ledger_module::api::ledger_check_duplicate(dup_json)
}

// ── 统计 ─────────────────────────────────────────────────────────────────────

#[frb(sync)]
pub fn ledger_stats_by_day(filter_json: String) -> Result<String, String> {
    ledger_module::api::ledger_stats_by_day(filter_json)
}

#[frb(sync)]
pub fn ledger_stats_by_category(filter_json: String) -> Result<String, String> {
    ledger_module::api::ledger_stats_by_category(filter_json)
}

#[frb(sync)]
pub fn ledger_stats_by_merchant(filter_json: String, top: i64) -> Result<String, String> {
    ledger_module::api::ledger_stats_by_merchant(filter_json, top)
}

#[frb(sync)]
pub fn ledger_stats_summary(filter_json: String) -> Result<String, String> {
    ledger_module::api::ledger_stats_summary(filter_json)
}

#[frb(sync)]
pub fn ledger_stats_by_month(months: i64) -> Result<String, String> {
    ledger_module::api::ledger_stats_by_month(months)
}

// ── 邮箱规则 ─────────────────────────────────────────────────────────────────

#[frb(sync)]
pub fn ledger_list_rules() -> Result<String, String> {
    ledger_module::api::ledger_list_rules()
}

#[frb(sync)]
pub fn ledger_upsert_rule(rule_json: String, password: String) -> Result<i64, String> {
    ledger_module::api::ledger_upsert_rule(rule_json, password)
}

#[frb(sync)]
pub fn ledger_delete_rule(id: i64) -> Result<(), String> {
    ledger_module::api::ledger_delete_rule(id)
}

#[frb(sync)]
pub fn ledger_set_rule_enabled(id: i64, enabled: bool) -> Result<(), String> {
    ledger_module::api::ledger_set_rule_enabled(id, enabled)
}

#[frb(sync)]
pub fn ledger_set_rule_password(rule_id: i64, password: String) -> Result<(), String> {
    ledger_module::api::ledger_set_rule_password(rule_id, password)
}

#[frb(sync)]
pub fn ledger_has_rule_password(rule_id: i64) -> Result<bool, String> {
    ledger_module::api::ledger_has_rule_password(rule_id)
}

#[frb(sync)]
pub fn ledger_rule_detail(id: i64) -> Result<String, String> {
    ledger_module::api::ledger_rule_detail(id)
}

#[frb(sync)]
pub fn ledger_templates() -> Result<String, String> {
    ledger_module::api::ledger_templates()
}

#[frb(sync)]
pub fn ledger_parse_preview(html: String, template_id: String, template_config: String) -> Result<String, String> {
    ledger_module::api::ledger_parse_preview(html, template_id, template_config)
}

// ── 收取与入账（联网，必须异步）─────────────────────────────────────────────

pub async fn ledger_check_rule(rule_id: i64, password: String) -> Result<String, String> {
    ledger_module::api::ledger_check_rule(rule_id, password)
}

/// 历史回补：一次拉几百封全文逐封解析，比日常收取慢一个数量级，
/// 必须离开 async worker 线程，否则整段 TLS 抓取会占死 runtime。
pub async fn ledger_backfill_rule(rule_id: i64, password: String, limit: u64) -> Result<String, String> {
    tokio::task::spawn_blocking(move || {
        ledger_module::api::ledger_backfill_rule(rule_id, password, limit)
    })
    .await
    .map_err(|e| format!("历史回补任务调度失败: {}", e))?
}

pub async fn ledger_fetch_emails(config_json: String, password: String, limit: u64) -> Result<String, String> {
    ledger_module::api::ledger_fetch_emails(config_json, password, limit)
}

pub async fn ledger_test_connection(config_json: String, password: String, want_folders: bool) -> Result<String, String> {
    ledger_module::api::ledger_test_connection(config_json, password, want_folders)
}

pub async fn ledger_list_folders(config_json: String, password: String) -> Result<String, String> {
    ledger_module::api::ledger_list_folders(config_json, password)
}

// ── 待确认队列 ───────────────────────────────────────────────────────────────

#[frb(sync)]
pub fn ledger_list_pending(limit: i64) -> Result<String, String> {
    ledger_module::api::ledger_list_pending(limit)
}

#[frb(sync)]
pub fn ledger_list_received_emails(limit: i64) -> Result<String, String> {
    ledger_module::api::ledger_list_received_emails(limit)
}

#[frb(sync)]
pub fn ledger_email_transactions(email_id: i64) -> Result<String, String> {
    ledger_module::api::ledger_email_transactions(email_id)
}

#[frb(sync)]
pub fn ledger_pending_count() -> Result<i64, String> {
    ledger_module::api::ledger_pending_count()
}

#[frb(sync)]
pub fn ledger_confirm_tx(tx_id: i64, patch_json: String) -> Result<(), String> {
    ledger_module::api::ledger_confirm_tx(tx_id, patch_json)
}

#[frb(sync)]
pub fn ledger_confirm_all(email_id: i64, patch_json: String) -> Result<i64, String> {
    ledger_module::api::ledger_confirm_all(email_id, patch_json)
}

#[frb(sync)]
pub fn ledger_ignore_email(email_id: i64) -> Result<i64, String> {
    ledger_module::api::ledger_ignore_email(email_id)
}

#[frb(sync)]
pub fn ledger_ignore_tx(tx_id: i64) -> Result<(), String> {
    ledger_module::api::ledger_ignore_tx(tx_id)
}

#[frb(sync)]
pub fn ledger_purge_email(email_id: i64) -> Result<i64, String> {
    ledger_module::api::ledger_purge_email(email_id)
}

// ── 调度与日志 ───────────────────────────────────────────────────────────────

#[frb(sync)]
pub fn ledger_scheduler_start() -> Result<(), String> {
    ledger_module::api::ledger_scheduler_start()
}

#[frb(sync)]
pub fn ledger_scheduler_stop() -> Result<(), String> {
    ledger_module::api::ledger_scheduler_stop()
}

#[frb(sync)]
pub fn ledger_scheduler_status() -> Result<String, String> {
    ledger_module::api::ledger_scheduler_status()
}

#[frb(sync)]
pub fn ledger_get_logs(limit: i64) -> Result<String, String> {
    ledger_module::api::ledger_get_logs(limit)
}

#[frb(sync)]
pub fn ledger_clear_logs() -> Result<(), String> {
    ledger_module::api::ledger_clear_logs()
}
