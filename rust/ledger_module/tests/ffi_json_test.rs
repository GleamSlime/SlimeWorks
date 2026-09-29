//! FFI 入参容缺的回归锚点。
//!
//! Dart 侧的 `toJson()` 只带 UI 关心的字段（`created_at`、联查字段、`dedup_key`
//! 这些由 Rust 补齐），所以这些 JSON 直接反查进 `types.rs` 的结构体时必须成立。
//! 少一个 default 就会在写入路径上炸成"缺少字段"，而 UI 上只表现为"保存失败"。

use ledger_module::types::{Account, Category, EmailRule, Transaction};
use serde_json::json;

/// 与 lib/pages/ledger/models/ledger_models.dart 的 LedgerAccount.toJson() 逐字一致
#[test]
fn account_accepts_json_without_server_side_fields() {
    let a: Account = serde_json::from_value(json!({
        "id": 0,
        "name": "示例信用卡",
        "type": "credit_card",
        "last4": "0000",
        "currency": "CNY",
        "credit_limit": 20000.0,
        "balance": 0.0,
        "sort_order": 0,
        "enabled": true,
    }))
    .expect("账户 JSON 应当容忍缺 created_at");
    assert_eq!(a.id, 0);
    assert!(a.enabled);
    assert_eq!(a.created_at, "");
    assert_eq!(a.currency, "CNY");
}

#[test]
fn category_accepts_json_without_is_builtin() {
    let c: Category = serde_json::from_value(json!({
        "id": 7,
        "name": "餐饮",
        "icon": "restaurant",
        "direction": "expense",
        "sort_order": 3,
    }))
    .expect("类别 JSON 应当容忍缺 is_builtin");
    assert_eq!(c.id, 7);
    assert!(!c.is_builtin, "用户新建的类别绝不能被当成内置");
}

#[test]
fn transaction_accepts_json_without_dedup_and_join_fields() {
    let t: Transaction = serde_json::from_value(json!({
        "id": 0,
        "occurred_at": "2026-09-28 12:34:56",
        "bill_date": "2026-09-28",
        "direction": "expense",
        "amount": 12.5,
        "currency": "CNY",
        "account_id": 1,
        "category_id": 2,
        "merchant": "示例商户",
        "note": "",
        "source": "manual",
        "rule_id": 0,
        "email_uid": "",
        "status": "posted",
    }))
    .expect("流水 JSON 应当容忍缺 dedup_key / 时间戳 / 联查字段");
    assert_eq!(t.direction, "expense");
    assert_eq!(t.dedup_key, "");
    assert_eq!(t.account_name, "");
}

#[test]
fn email_rule_accepts_json_without_run_history() {
    let r: EmailRule = serde_json::from_value(json!({
        "id": 0,
        "name": "招行每日账单",
        "enabled": true,
        "protocol": "imap",
        "host": "imap.example.com",
        "port": 993,
        "use_ssl": true,
        "username": "someone@example.com",
        "mailbox": "INBOX",
        "sender_match": "ccservice@example.com",
        "subject_match": "信用卡每日账单",
        "match_is_regex": false,
        "template_id": "cmb_daily_bill",
        "template_config": "{}",
        "interval_minutes": 0,
        "daily_time": "09:30",
        "default_account_id": 1,
        "auto_apply": false,
        "accept_invalid_certs": false,
    }))
    .expect("规则 JSON 应当容忍缺 last_run_at / last_result / created_at");
    assert_eq!(r.port, 993);
    assert!(r.use_ssl);
    assert_eq!(r.last_result, "");
}

/// 空串和缺字段在 bool 上的语义不同：`enabled` 缺失必须是 false（不默认放行）
#[test]
fn missing_bool_flags_default_to_false() {
    let minimal: Category =
        serde_json::from_value(json!({"name": "交通"})).expect("只给 name 也应能解析");
    assert_eq!(minimal.id, 0);
    assert_eq!(minimal.direction, "");
    assert!(!minimal.is_builtin);
}
