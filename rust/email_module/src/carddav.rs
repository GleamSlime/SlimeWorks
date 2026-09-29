//! CardDAV 占位。
//!
//! CardDAV 是通讯录协议（RFC6352），只能读写 vCard，收不到邮件；
//! 记账链路上它没有位置。这里保留配置项，是为了让"通讯录/日历同步"
//! 以后接进来时协议枚举不用再改一遍。

use crate::types::{ConnectionReport, EmailAccountConfig, FetchOutcome};

pub const REASON: &str = "CardDAV 尚未接入：它是通讯录协议（vCard），无法收取邮件，与记账链路无关。若要自动记账请选 IMAP/POP3。";

pub fn fetch(_cfg: &EmailAccountConfig) -> Result<FetchOutcome, String> {
    Err(REASON.to_string())
}

pub fn probe(_cfg: &EmailAccountConfig, _want_folders: bool) -> Result<ConnectionReport, String> {
    Ok(ConnectionReport::fail("carddav", REASON))
}
