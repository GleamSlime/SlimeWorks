use serde::{Deserialize, Serialize};

use crate::parser::template_ids;
use crate::types::*;

/// email_module 的 JSON 返回形态在本 crate 的镜像。
/// 走 JSON 而不是直接引用对方类型，是为了让两个 crate 的字段增删只在这里报错，
/// 不会把编译期依赖扩散到 storage/api。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WireEmailMessage {
    pub uid: String,
    #[serde(default)]
    pub message_id: String,
    #[serde(default)]
    pub from: String,
    #[serde(default)]
    pub from_name: String,
    #[serde(default)]
    pub to: String,
    #[serde(default)]
    pub subject: String,
    #[serde(default)]
    pub date: String,
    #[serde(default)]
    pub body_html: String,
    #[serde(default)]
    pub body_text: String,
    #[serde(default)]
    pub size_bytes: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WireFetchOutcome {
    #[serde(default)]
    pub protocol: String,
    #[serde(default)]
    pub folder: String,
    #[serde(default)]
    pub uid_validity: String,
    #[serde(default)]
    pub total_seen: u64,
    #[serde(default)]
    pub messages: Vec<WireEmailMessage>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WireConnectionReport {
    pub ok: bool,
    #[serde(default)]
    pub protocol: String,
    #[serde(default)]
    pub detail: String,
    #[serde(default)]
    pub capabilities: Vec<String>,
    #[serde(default)]
    pub folders: Vec<String>,
}

/// 模板引擎的统一出参（parser 侧同名结构，这里做序列化成桥）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ParsedTx {
    pub time: String,
    pub datetime: String,
    pub currency: String,
    pub amount: f64,
    pub raw_amount: String,
    pub description: String,
    pub card_tail: String,
    pub entry_type: String,
    pub merchant: String,
    pub direction: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ParseResult {
    pub template_id: String,
    pub bill_date: String,
    pub transactions: Vec<ParsedTx>,
    pub available_credit: Option<f64>,
    pub points_balance: Option<i64>,
    pub warnings: Vec<String>,
}

/// email_module 的入参形态在本 crate 的镜像（字段名逐字对齐，serde 默认容缺）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EmailAccountWire {
    pub protocol: String,
    #[serde(default)]
    pub host: String,
    #[serde(default)]
    pub port: u16,
    #[serde(default = "default_true")]
    pub use_ssl: bool,
    #[serde(default)]
    pub username: String,
    #[serde(default)]
    pub password: String,
    #[serde(default = "default_inbox")]
    pub mailbox: String,
    #[serde(default)]
    pub accept_invalid_certs: bool,
    #[serde(default = "default_timeout")]
    pub timeout_secs: u64,
}

fn default_true() -> bool {
    true
}
fn default_inbox() -> String {
    "INBOX".to_string()
}
fn default_timeout() -> u64 {
    25
}

impl EmailAccountWire {
    /// 规则 + 运行期密码 → 收信入参；port 0 交给收信层按协议取默认
    pub fn of(rule: &EmailRule, password: &str) -> EmailAccountWire {
        EmailAccountWire {
            protocol: if rule.protocol.is_empty() {
                "imap".to_string()
            } else {
                rule.protocol.clone()
            },
            host: rule.host.clone(),
            port: rule.port,
            use_ssl: rule.use_ssl,
            username: rule.username.clone(),
            password: password.to_string(),
            mailbox: if rule.mailbox.is_empty() {
                "INBOX".to_string()
            } else {
                rule.mailbox.clone()
            },
            accept_invalid_certs: rule.accept_invalid_certs,
            timeout_secs: 25,
        }
    }
}

/// 模板清单：id + 中文名 + 适用说明，设置页下拉直接用
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TemplateInfo {
    pub id: String,
    pub name: String,
    pub description: String,
}

pub fn template_list() -> Vec<TemplateInfo> {
    template_ids()
        .into_iter()
        .map(|id| TemplateInfo {
            name: template_name(&id).to_string(),
            description: template_hint(&id).to_string(),
            id,
        })
        .collect()
}

fn template_name(id: &str) -> &'static str {
    match id {
        "cmb_daily_bill" => "招商银行账单（每日明细 / 月度电子账单）",
        "generic_keyword" => "通用关键字匹配",
        "custom_regex" => "自定义正则",
        _ => "未知模板",
    }
}

fn template_hint(id: &str) -> &'static str {
    match id {
        "cmb_daily_bill" => "招行账单邮件内置模板：每日明细走 时间 + CNY 金额 + 尾号XXXX 类型 商户 三段式，\
                              月度电子账单走七列位置表（交易日/入账日/摘要/交易金额/卡号/币种/人民币金额）",
        "generic_keyword" => "按日期/金额/摘要关键字抓行，适合格式已知但没有内置模板的账单邮件",
        "custom_regex" => "一条带命名组的正则吃整行，最灵活也最容易写错，改完务必用预览验证",
        _ => "该模板无内置说明",
    }
}

/// 模板自动识别：命中招行账单指纹就走内置模板，否则落通用模板
pub fn resolve_template_id(rule: &EmailRule, subject: &str, html: &str) -> String {
    if !rule.template_id.is_empty() && rule.template_id != "auto" {
        return rule.template_id.clone();
    }
    let text = format!("{} {}", subject, html);
    // 「电子账单」是 2026 版月度账单只在标题里出现的说法，正文的栏目名全是图片；
    // 真正定性靠后面的招行资源域名，缺一律不走内置模板。
    let is_cmb = (text.contains("每日账单")
        || text.contains("消费明细")
        || text.contains("交易明细")
        || text.contains("电子账单"))
        && (text.contains("bill_templet_resource")
            || text.contains("s3gw.cmbimg.com")
            || text.contains("cmbchina")
            || text.contains("c.cmbimg.com"));
    if is_cmb {
        "cmb_daily_bill".to_string()
    } else {
        "generic_keyword".to_string()
    }
}

/// 解析一封邮件正文
pub fn parse_message(
    template_id: &str,
    template_config: &str,
    html: &str,
    text: &str,
) -> Result<ParseResult, String> {
    let body = if html.is_empty() { text } else { html };
    if body.trim().is_empty() {
        return Err("邮件正文为空，无法解析".to_string());
    }
    // 桥接层负责按模板分流并做 serde 形态转换，parser 只认自己的入参
    let raw = match template_id {
        "generic_keyword" => crate::parser::parse_generic_keyword(body, template_config)?,
        "custom_regex" => crate::parser::parse_custom_regex(body, template_config)?,
        _ => crate::parser::parse_cmb_daily_bill(body)?,
    };
    serde_json::to_string(&raw)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .ok_or_else(|| "解析结果转换失败".to_string())
}

/// 发件人/标题匹配：留空即不限制；勾选正则时按正则，否则按不区分大小写子串
pub fn message_matches(rule: &EmailRule, from: &str, subject: &str) -> bool {
    let one = |pat: &str, value: &str| -> bool {
        let pat = pat.trim();
        if pat.is_empty() {
            return true;
        }
        if rule.match_is_regex {
            compile_ci(pat)
                .map(|re| re.is_match(value))
                .unwrap_or(false)
        } else {
            let lower_pat = pat.to_lowercase();
            value.to_lowercase().contains(&lower_pat)
        }
    };
    one(&rule.sender_match, from) && one(&rule.subject_match, subject)
}

fn compile_ci(pat: &str) -> Option<regex::Regex> {
    regex::RegexBuilder::new(pat)
        .case_insensitive(true)
        .build()
        .ok()
}

/// 解析出的一笔 → 待入账流水
///
/// `seq` 是这一笔在邮件里的行序，只用来把去重键分开，不参与展示。
pub fn tx_from_parsed(
    parsed: &ParsedTx,
    rule: &EmailRule,
    email_uid: &str,
    fallback_date: &str,
    account_id: i64,
    seq: usize,
) -> Transaction {
    let occurred = if parsed.datetime.len() >= 19 {
        parsed.datetime.chars().take(19).collect()
    } else if !parsed.time.is_empty() {
        format!("{} {}", fallback_date, parsed.time)
    } else {
        format!("{} 00:00:00", fallback_date)
    };
    let bill_date: String = occurred.chars().take(10).collect();
    let direction = if parsed.direction == DIRECTION_INCOME {
        DIRECTION_INCOME
    } else {
        DIRECTION_EXPENSE
    };
    // 邮件行必须精确到时刻去重：同一天两笔 33.00 的 示例游戏平台消费是真实重复扣款，
    // 若只按"日期+金额+商户"去重就会把第二笔当重复挡掉。
    // 招行的月账单连时分都不给，同日的重复扣款只剩行序能分开，所以把行序也编进键。
    let dedup_key = format!(
        "{}|{:.2}|{}|{}|r{}",
        occurred, parsed.amount, parsed.merchant, parsed.entry_type, seq
    );
    Transaction {
        id: 0,
        occurred_at: occurred,
        bill_date,
        direction: direction.to_string(),
        amount: round2(parsed.amount),
        currency: if parsed.currency.is_empty() {
            "CNY".to_string()
        } else {
            parsed.currency.clone()
        },
        account_id,
        category_id: 0,
        merchant: parsed.merchant.clone(),
        note: if parsed.entry_type.is_empty() {
            String::new()
        } else {
            // 银行给的交易类型先留在备注里，用户改名类别时不至于丢掉原始信息
            format!("银行类型:{}", parsed.entry_type)
        },
        source: SOURCE_EMAIL.to_string(),
        rule_id: rule.id,
        email_uid: email_uid.to_string(),
        dedup_key,
        status: STATUS_PENDING.to_string(),
        created_at: String::new(),
        updated_at: String::new(),
        account_name: String::new(),
        category_name: String::new(),
        category_icon: String::new(),
        category_direction: String::new(),
    }
}

/// 收入类默认落"退款退货"，支出类落"其他支出"；有历史习惯时 storage 会自己改猜
pub fn default_category_name(direction: &str) -> &'static str {
    match direction {
        DIRECTION_INCOME => "退款退货",
        _ => "其他支出",
    }
}
