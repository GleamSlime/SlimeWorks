use serde::{Deserialize, Serialize};

/// 账本模块的数据结构定义。
///
/// 约定：对外 FFI 接口都收发 snake_case 的 JSON 字符串（对齐 power_stats），
/// 这些结构只服务 serde，不直接出现在生成的 Dart 绑定里。

pub const DIRECTION_EXPENSE: &str = "expense";
pub const DIRECTION_INCOME: &str = "income";
pub const DIRECTION_TRANSFER: &str = "transfer";

/// 入账来源
pub const SOURCE_MANUAL: &str = "manual";
pub const SOURCE_EMAIL: &str = "email";

/// 流水状态：邮件解析出的记录先进待确认，确认后转 posted
pub const STATUS_PENDING: &str = "pending";
pub const STATUS_POSTED: &str = "posted";
pub const STATUS_IGNORED: &str = "ignored";

/// `#[serde(default)]`：Dart 的 toJson() 只带 UI 字段，缺的一律按 Default 补
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Account {
    pub id: i64,
    pub name: String,
    /// credit_card | debit_card | cash | deposit | other
    #[serde(rename = "type")]
    pub account_type: String,
    pub last4: String,
    pub currency: String,
    pub credit_limit: f64,
    pub balance: f64,
    pub sort_order: i64,
    pub enabled: bool,
    pub created_at: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Category {
    pub id: i64,
    pub name: String,
    /// 图标标识（前端映射到描边图标名）；空表示用默认
    pub icon: String,
    /// expense | income
    pub direction: String,
    pub sort_order: i64,
    pub is_builtin: bool,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Transaction {
    pub id: i64,
    pub occurred_at: String,
    /// YYYY-MM-DD，冗余存储用于按天/月分组并建索引
    pub bill_date: String,
    pub direction: String,
    /// 恒为正数，正负由 direction 决定，避免减法歧义
    pub amount: f64,
    pub currency: String,
    pub account_id: i64,
    pub category_id: i64,
    pub merchant: String,
    pub note: String,
    pub source: String,
    pub rule_id: i64,
    pub email_uid: String,
    pub dedup_key: String,
    pub status: String,
    pub created_at: String,
    pub updated_at: String,
    // ── 联查字段：列表查询带出，省掉一次账户/类别往返 ──
    pub account_name: String,
    pub category_name: String,
    pub category_icon: String,
    pub category_direction: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct EmailRule {
    pub id: i64,
    pub name: String,
    pub enabled: bool,
    /// imap | pop3 | smtp | exchange_eas | carddav（后两者当前仅占位）
    pub protocol: String,
    pub host: String,
    pub port: u16,
    pub use_ssl: bool,
    pub username: String,
    pub mailbox: String,
    pub sender_match: String,
    pub subject_match: String,
    pub match_is_regex: bool,
    /// cmb_daily_bill | generic_keyword | custom_regex
    pub template_id: String,
    /// 模板参数 JSON（自定义正则/关键字映射等）
    pub template_config: String,
    /// 0 表示不按间隔轮询，只由每日检查点或手动触发
    pub interval_minutes: u64,
    /// HH:MM 到点自动检查，空表示不启用
    pub daily_time: String,
    /// 命中邮件默认落哪个账户
    pub default_account_id: i64,
    pub auto_apply: bool,
    pub accept_invalid_certs: bool,
    pub last_run_at: String,
    pub last_result: String,
    pub created_at: String,
}

/// 新建规则的起点值：与 storage 的 INSERT 默认列保持一致，
/// 预览用的"伪规则"也从这里长出来，避免两处各写一份。
impl Default for EmailRule {
    fn default() -> Self {
        Self {
            id: 0,
            name: String::new(),
            enabled: true,
            protocol: "imap".to_string(),
            host: String::new(),
            port: 0,
            use_ssl: true,
            username: String::new(),
            mailbox: "INBOX".to_string(),
            sender_match: String::new(),
            subject_match: String::new(),
            match_is_regex: false,
            template_id: "auto".to_string(),
            template_config: "{}".to_string(),
            interval_minutes: 0,
            daily_time: String::new(),
            default_account_id: 0,
            auto_apply: false,
            accept_invalid_certs: false,
            last_run_at: String::new(),
            last_result: String::new(),
            created_at: String::new(),
        }
    }
}

/// 待确认队列里的一封邮件
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PendingEmail {
    pub id: i64,
    pub rule_id: i64,
    pub rule_name: String,
    pub message_uid: String,
    pub message_id: String,
    pub from_addr: String,
    pub subject: String,
    pub received_at: String,
    pub bill_date: String,
    pub tx_count: i64,
    pub applied: bool,
    pub available_credit: Option<f64>,
    pub points_balance: Option<i64>,
    pub warnings: Vec<String>,
    pub html_len: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FetchLog {
    pub id: i64,
    pub rule_id: i64,
    pub started_at: String,
    pub finished_at: String,
    pub ok: bool,
    pub new_emails: i64,
    pub new_tx: i64,
    pub skipped_tx: i64,
    pub detail: String,
}

/// 调度器状态快照
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SchedulerStatus {
    pub running: bool,
    pub enabled: bool,
    pub check_interval_secs: u64,
    pub last_check_at: String,
    pub next_check_at: String,
    pub active_rules: usize,
    pub last_summary: String,
}

impl Default for SchedulerStatus {
    fn default() -> Self {
        Self {
            running: false,
            enabled: false,
            check_interval_secs: 60,
            last_check_at: String::new(),
            next_check_at: String::new(),
            active_rules: 0,
            last_summary: String::new(),
        }
    }
}

/// 金额格式化：SQLite 里存 REAL，展示交给前端，聚合在这里做四舍五入收敛，
/// 避免 0.1+0.2 类误差在月度统计里累积成可见的差值。
pub fn round2(v: f64) -> f64 {
    (v * 100.0).round() / 100.0
}
