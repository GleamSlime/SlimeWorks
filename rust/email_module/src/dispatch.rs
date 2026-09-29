//! 按协议分流：上层只需要 fetch / probe / list_folders 三个动作。

use crate::types::{ConnectionReport, EmailAccountConfig, FetchOutcome};
use crate::{carddav, eas, imap, pop3, smtp};

/// UI 用来把不支持的协议灰掉
pub fn is_supported(protocol: &str) -> bool {
    matches!(normalized(protocol).as_str(), "imap" | "pop3" | "smtp")
}

pub fn normalized(protocol: &str) -> String {
    protocol.trim().to_ascii_lowercase().replace('-', "_").replace(' ', "_")
}

/// SMTP 不能收信，给它一句能直接展示的话
const SMTP_NOT_FOR_RECEIVING: &str = "SMTP 是发信协议，无法收取邮件；自动记账请选择 IMAP 或 POP3，SMTP 只用于校验授权码。";

pub fn fetch(cfg: &EmailAccountConfig, limit: u64) -> Result<FetchOutcome, String> {
    let cfg = cfg.normalized();
    match normalized(&cfg.protocol).as_str() {
        "imap" => imap::fetch(&cfg, limit),
        "pop3" => pop3::fetch(&cfg, limit),
        "smtp" => Err(SMTP_NOT_FOR_RECEIVING.to_string()),
        "exchange_eas" | "eas" => eas::fetch(&cfg),
        "carddav" => carddav::fetch(&cfg),
        other => Err(format!("不支持的收件协议: {}（可选 imap / pop3）", other)),
    }
}

pub fn probe(cfg: &EmailAccountConfig, want_folders: bool) -> Result<ConnectionReport, String> {
    let cfg = cfg.normalized();
    match normalized(&cfg.protocol).as_str() {
        "imap" => imap::probe(&cfg, want_folders),
        "pop3" => pop3::probe(&cfg, want_folders),
        "smtp" => smtp::probe(&cfg, want_folders),
        "exchange_eas" | "eas" => eas::probe(&cfg, want_folders),
        "carddav" => carddav::probe(&cfg, want_folders),
        other => Err(format!("不支持的协议: {}", other)),
    }
}

/// 只有 IMAP 有目录概念；其它协议返回空清单而不是报错
pub fn list_folders(cfg: &EmailAccountConfig) -> Result<Vec<String>, String> {
    let cfg = cfg.normalized();
    match normalized(&cfg.protocol).as_str() {
        "imap" => {
            let mut session = imap::ImapSession::open(&cfg)?;
            let folders = session.list()?;
            session.close();
            Ok(folders)
        }
        "pop3" => Ok(vec!["INBOX".to_string()]),
        other => Err(format!("{} 协议不支持列出邮箱目录", other)),
    }
}
