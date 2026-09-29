//! Exchange ActiveSync (EAS) 占位。
//!
//! 本期不实现，原因写在返回值里，让调用方拿到明确结论而不是超时：
//! EAS 需要 WBXML 编解码 + Provisioning 命令链 + 设备证书/策略协商，
//! 依赖（activesync/wbxml 一类）在本项目的离线依赖集里不存在。

use crate::types::{ConnectionReport, EmailAccountConfig, FetchOutcome};

pub const REASON: &str = "Exchange (EAS) 尚未实现：需要 WBXML 协议栈与设备证书下发，当前离线依赖集内没有可用实现。请改用该邮箱的 IMAP/POP3 入口（多数企业 Exchange 会同时开 IMAP），或等后续版本补齐。";

pub fn fetch(_cfg: &EmailAccountConfig) -> Result<FetchOutcome, String> {
    Err(REASON.to_string())
}

pub fn probe(_cfg: &EmailAccountConfig, _want_folders: bool) -> Result<ConnectionReport, String> {
    Ok(ConnectionReport::fail("exchange_eas", REASON))
}
