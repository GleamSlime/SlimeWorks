//! 协议分流的离线测试：只覆盖"不碰网络就能定论"的分支。
//!
//! 关注两件事：
//! 1. 未知/占位协议要返回诚实的错误文本，不能 panic、不能假装成功；
//! 2. 协议名归一化（大小写、连字符、空格）后仍落到同一分支。
//! imap/pop3/smtp 的真实收发会连服务器，这里一律不测。

use email_module::dispatch::{fetch, is_supported, list_folders, normalized, probe};
use email_module::types::{ConnectionReport, EmailAccountConfig};
use email_module::{carddav, eas};

fn cfg(protocol: &str) -> EmailAccountConfig {
    EmailAccountConfig {
        protocol: protocol.to_string(),
        host: "public.example.com".to_string(),
        port: 0,
        use_ssl: false,
        username: "user@example.test".to_string(),
        password: "hunter2".to_string(),
        mailbox: String::new(),
        accept_invalid_certs: false,
        timeout_secs: 0,
    }
}

/// 收信：预期拿到 Err 时把文案取出来（Ok 直接 panic，测试失败）
fn fetch_err(protocol: &str) -> String {
    fetch(&cfg(protocol), 5).expect_err("占位/未知协议不该收信成功").to_string()
}

/// 自检：占位协议返回 Ok(report)，这里取出 report
fn probe_report(protocol: &str) -> ConnectionReport {
    probe(&cfg(protocol), true).expect("占位协议的 probe 应返回 Ok 形状")
}

#[test]
fn protocol_name_normalization() {
    assert_eq!(normalized("  IMAP "), "imap");
    assert_eq!(normalized("Exchange-EAS"), "exchange_eas");
    assert_eq!(normalized("exchange eas"), "exchange_eas");
    assert_eq!(normalized("CardDav"), "carddav");
    assert_eq!(normalized(""), "");
}

#[test]
fn supported_flags_only_the_three_real_protocols() {
    assert!(is_supported("imap"));
    assert!(is_supported(" POP3 "));
    assert!(is_supported("SMTP"));
    // 占位协议与未知协议对 UI 置灰
    assert!(!is_supported("exchange_eas"));
    assert!(!is_supported("eas"));
    assert!(!is_supported("carddav"));
    assert!(!is_supported(""));
    assert!(!is_supported("gmail"));
}

#[test]
fn unknown_protocol_reports_honestly() {
    // 大小写/空格归一化后仍落到"未知"分支，且把归一化后的协议名带回错误里
    let e = fetch_err("Gmail");
    assert!(e.contains("不支持的收件协议"), "实际: {}", e);
    assert!(e.contains("gmail"), "应回显归一化后的协议名，实际: {}", e);
    let e = probe(&cfg("gmail"), false).unwrap_err();
    assert!(e.starts_with("不支持的协议"), "实际: {}", e);
    let e = list_folders(&cfg("gmail")).unwrap_err();
    assert!(e.contains("不支持列出邮箱目录"), "实际: {}", e);
    // 空协议名也不能 panic，也不能被当成 imap 处理
    assert!(fetch_err("").contains("不支持的收件协议"));
    assert!(probe(&cfg(""), false).unwrap_err().starts_with("不支持的协议"));
}

#[test]
fn eas_placeholder_says_not_implemented() {
    // 别名 eas / exchange_eas 都落到同一个占位实现，且不碰网络
    for name in ["eas", "exchange_eas", "Exchange-EAS", "exchange eas"] {
        let e = fetch_err(name);
        assert_eq!(e, eas::REASON, "协议 {} 的占位文案应逐字一致", name);
        assert!(e.contains("尚未实现"), "必须诚实说明未实现");
    }
    // probe 走 Ok + ok=false 的形状（不是 Err），调用方要按 ok 字段判断
    let report = probe_report("eas");
    assert!(!report.ok);
    assert_eq!(report.protocol, "exchange_eas");
    assert_eq!(report.detail, eas::REASON);
    assert!(report.capabilities.is_empty() && report.folders.is_empty());
}

#[test]
fn carddav_placeholder_says_not_implemented() {
    for name in ["carddav", "CardDav", " CARDDAV "] {
        let e = fetch_err(name);
        assert_eq!(e, carddav::REASON, "协议 {} 的占位文案应逐字一致", name);
        assert!(e.contains("尚未接入"), "必须诚实说明未接入");
    }
    let report = probe_report("carddav");
    assert!(!report.ok);
    assert_eq!(report.protocol, "carddav");
    assert_eq!(report.detail, carddav::REASON);
    // 占位实现也承认自己不列目录
    assert!(list_folders(&cfg("carddav")).unwrap_err().contains("不支持列出邮箱目录"));
    assert!(list_folders(&cfg("eas")).unwrap_err().contains("不支持列出邮箱目录"));
}

#[test]
fn smtp_refuses_to_receive_but_is_supported() {
    // SMTP 是发信协议：is_supported=true，但 fetch 给一句能直接展示的话
    assert!(is_supported("smtp"));
    let e = fetch_err(" SMTP ");
    assert!(e.contains("SMTP 是发信协议"), "实际: {}", e);
    assert!(e.contains("IMAP 或 POP3"), "应给出下一步指引，实际: {}", e);
    // list_folders 同样不支持（只有 IMAP 有目录概念）
    assert!(list_folders(&cfg("smtp")).unwrap_err().contains("不支持列出邮箱目录"));
}

#[test]
fn pop3_lists_inbox_without_touching_network() {
    // POP3 无目录概念，按设计返回单元素清单而不是报错
    assert_eq!(list_folders(&cfg("pop3")).unwrap(), vec!["INBOX".to_string()]);
}
