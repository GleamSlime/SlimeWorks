use serde::{Deserialize, Serialize};

/// 邮件模块对外只收发 snake_case 的 JSON 字符串，字段名是 Rust/Dart 之间的契约。

/// 收信/自检入参
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EmailAccountConfig {
    /// imap | pop3 | smtp | exchange_eas | carddav
    pub protocol: String,
    #[serde(default)]
    pub host: String,
    /// 0 表示按协议取默认端口
    #[serde(default)]
    pub port: u16,
    #[serde(default = "default_true")]
    pub use_ssl: bool,
    #[serde(default)]
    pub username: String,
    #[serde(default)]
    pub password: String,
    /// IMAP 邮箱路径，空按 INBOX
    #[serde(default = "default_inbox")]
    pub mailbox: String,
    /// 自签证书服务器：仅在内网/测试环境打开
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

impl EmailAccountConfig {
    pub fn normalized(&self) -> EmailAccountConfig {
        let mut cfg = self.clone();
        cfg.protocol = cfg.protocol.trim().to_lowercase();
        cfg.host = cfg.host.trim().to_string();
        cfg.mailbox = if cfg.mailbox.trim().is_empty() {
            "INBOX".to_string()
        } else {
            cfg.mailbox.trim().to_string()
        };
        if cfg.port == 0 {
            cfg.port = default_port(&cfg.protocol, cfg.use_ssl);
        }
        if cfg.timeout_secs == 0 {
            cfg.timeout_secs = default_timeout();
        }
        cfg
    }

    pub fn is_tls_required_by_policy(&self) -> bool {
        // 明文 IMAP/POP3/SMTP 会把口令整条链路裸奔，默认拒绝；本机测试走 loopback 例外
        self.use_ssl || is_loopback(&self.host)
    }
}

fn is_loopback(host: &str) -> bool {
    host == "localhost" || host.starts_with("127.") || host == "::1"
}

pub fn default_port(protocol: &str, use_ssl: bool) -> u16 {
    match (protocol, use_ssl) {
        ("imap", true) => 993,
        ("imap", false) => 143,
        ("pop3", true) => 995,
        ("pop3", false) => 110,
        ("smtp", true) => 465,
        ("smtp", false) => 587,
        _ => 993,
    }
}

/// 一封邮件的解析结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EmailMessage {
    /// IMAP UID / POP3 UIDL
    pub uid: String,
    #[serde(default)]
    pub message_id: String,
    /// 发件人地址（已去掉显示名）
    #[serde(default)]
    pub from: String,
    #[serde(default)]
    pub from_name: String,
    #[serde(default)]
    pub to: String,
    #[serde(default)]
    pub subject: String,
    /// 归一化成 `YYYY-MM-DD HH:MM:SS`，读不出来就原样带回
    #[serde(default)]
    pub date: String,
    #[serde(default)]
    pub body_html: String,
    #[serde(default)]
    pub body_text: String,
    #[serde(default)]
    pub size_bytes: u64,
}

/// 一次收取的结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FetchOutcome {
    pub protocol: String,
    pub folder: String,
    /// IMAP 的 UIDVALIDITY；POP3 固定为 pop3-uidl
    pub uid_validity: String,
    pub total_seen: u64,
    pub messages: Vec<EmailMessage>,
}

/// 连接自检结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConnectionReport {
    pub ok: bool,
    pub protocol: String,
    pub detail: String,
    pub capabilities: Vec<String>,
    pub folders: Vec<String>,
}

impl ConnectionReport {
    pub fn fail(protocol: &str, detail: &str) -> ConnectionReport {
        ConnectionReport {
            ok: false,
            protocol: protocol.to_string(),
            detail: detail.to_string(),
            capabilities: Vec::new(),
            folders: Vec::new(),
        }
    }

    pub fn to_json(&self) -> String {
        serde_json::to_string(self).unwrap_or_else(|e| format!(r#"{{"ok":false,"detail":"{}"}}"#, e))
    }
}
