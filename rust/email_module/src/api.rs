//! FFI 侧接口：全部收发 JSON 字符串，与 ledger_module / Dart 的契约一致。
//!
//! 口令只作为入参在这一层出现，绝不写进日志，也不回显在错误里。

use crate::dispatch;
use crate::types::{EmailAccountConfig, FetchOutcome};

fn parse_config(config_json: &str) -> Result<EmailAccountConfig, String> {
    serde_json::from_str::<EmailAccountConfig>(config_json)
        .map_err(|e| format!("邮箱配置解析失败: {}", e))
}

/// 收取最近 limit 封（不写库，纯协议动作）
pub fn email_fetch_json(config_json: String, limit: u64) -> Result<String, String> {
    let cfg = parse_config(&config_json)?;
    let outcome = dispatch::fetch(&cfg, limit)?;
    serde_json::to_string(&outcome).map_err(|e| format!("序列化收信结果失败: {}", e))
}

/// 连接自检：IMAP/POP3 走登录+选信箱，SMTP 走 EHLO+AUTH
pub fn email_probe_json(config_json: String, want_folders: bool) -> Result<String, String> {
    let cfg = parse_config(&config_json)?;
    let report = dispatch::probe(&cfg, want_folders)?;
    serde_json::to_string(&report).map_err(|e| format!("序列化自检结果失败: {}", e))
}

pub fn email_list_folders_json(config_json: String) -> Result<String, String> {
    let cfg = parse_config(&config_json)?;
    let folders = dispatch::list_folders(&cfg)?;
    serde_json::to_string(&folders).map_err(|e| format!("序列化目录列表失败: {}", e))
}

/// 收信结果的摘要（预览面板用，避免把正文整段搬过去）
pub fn email_summarize_json(outcome_json: String) -> Result<String, String> {
    let outcome: FetchOutcome =
        serde_json::from_str(&outcome_json).map_err(|e| format!("收信结果解析失败: {}", e))?;
    let brief: Vec<serde_json::Value> = outcome
        .messages
        .iter()
        .map(|m| {
            serde_json::json!({
                "uid": m.uid,
                "from": m.from,
                "subject": m.subject,
                "date": m.date,
                "size_bytes": m.size_bytes,
                "has_html": !m.body_html.is_empty(),
                "has_text": !m.body_text.is_empty(),
            })
        })
        .collect();
    serde_json::to_string(&serde_json::json!({
        "protocol": outcome.protocol,
        "folder": outcome.folder,
        "uid_validity": outcome.uid_validity,
        "total_seen": outcome.total_seen,
        "messages": brief,
    }))
    .map_err(|e| format!("序列化摘要失败: {}", e))
}

pub fn email_version() -> String {
    "email_module 0.1.0（IMAP/POP3/SMTP 同步客户端，EAS/CardDAV 占位）".to_string()
}
