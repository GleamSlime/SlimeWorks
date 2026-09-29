//! 招行每日账单模板的回归用例：用真实邮件（已脱敏）逐笔核对。
//!
//! 这个 fixture 是"银行改版就必须在这里留痕"的最后一道闸，
//! 所以断言写的是每一笔的具体数值，而不是"解析出 N 笔"。

use ledger_module::parse_glue::{resolve_template_id, EmailAccountWire};
use ledger_module::parser::{parse_cmb_daily_bill, parse_custom_regex, parse_generic_keyword};
use ledger_module::types::EmailRule;

fn cmb_html() -> String {
    let path = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/cmb_daily_bill_sample.html");
    std::fs::read_to_string(path).expect("读不到招行账单 fixture")
}

fn rule() -> EmailRule {
    EmailRule {
        id: 1,
        name: "招行每日账单".to_string(),
        ..Default::default()
    }
}

#[test]
fn cmb_daily_bill_parses_every_transaction() {
    let html = cmb_html();
    let result = parse_cmb_daily_bill(&html).expect("招行账单解析失败");

    assert_eq!(result.template_id, "cmb_daily_bill");
    assert_eq!(result.bill_date, "2026-01-15");
    assert_eq!(result.available_credit, Some(20000.00));
    assert_eq!(result.points_balance, Some(1000));

    let rows: Vec<(String, String, f64, String, String, String)> = result
        .transactions
        .iter()
        .map(|t| {
            (
                t.time.clone(),
                t.raw_amount.clone(),
                t.amount,
                t.entry_type.clone(),
                t.direction.clone(),
                t.merchant.clone(),
            )
        })
        .collect();

    assert_eq!(
        rows,
        vec![
            ("00:09:22".into(), "17.10".into(), 17.10, "消费".into(), "expense".into(), "示例支付-外卖平台示例烧烤店".into()),
            ("08:15:34".into(), "15.60".into(), 15.60, "消费".into(), "expense".into(), "示例支付-外卖平台示例粥铺（示例店）".into()),
            ("12:40:31".into(), "15.67".into(), 15.67, "消费".into(), "expense".into(), "示例支付-示例礼品卡自营旗舰店".into()),
            ("15:09:18".into(), "33.00".into(), 33.00, "消费".into(), "expense".into(), "示例支付-示例游戏平台".into()),
            ("15:13:08".into(), "33.00".into(), 33.00, "消费".into(), "expense".into(), "示例支付-示例游戏平台".into()),
            ("16:21:52".into(), "-33.00".into(), 33.00, "退货".into(), "income".into(), "示例支付-示例游戏平台".into()),
            ("18:23:00".into(), "26.50".into(), 26.50, "消费".into(), "expense".into(), "示例支付-外卖平台示例牛蛙店".into()),
        ]
    );

    // 时刻必须进到 datetime：同一天两笔 33.00 靠它区分，不能让去重键撞车
    assert_eq!(result.transactions[4].datetime, "2026-01-15 15:13:08");
    assert!(result.transactions.iter().all(|t| t.card_tail == "0001"));
    assert!(result.transactions.iter().all(|t| t.currency == "CNY"));
    // 模板改版时才会出现：这里应当一笔都不该漏
    assert!(result.warnings.is_empty(), "意外警告: {:?}", result.warnings);
}

#[test]
fn cmb_email_is_recognised_by_fingerprint() {
    let html = cmb_html();
    let auto = resolve_template_id(&rule(), "尊敬的客户，您的每日账单已生成", &html);
    assert_eq!(auto, "cmb_daily_bill");
    // 规则里显式指定模板时，指纹判定要让位于用户选择
    let forced = EmailRule {
        template_id: "custom_regex".to_string(),
        ..rule()
    };
    assert_eq!(resolve_template_id(&forced, "随便什么标题", &html), "custom_regex");
    let other = resolve_template_id(&rule(), "您的账单已出", "<html>没有任何招行特征</html>");
    assert_eq!(other, "generic_keyword");
}

#[test]
fn cmb_template_change_is_not_silent() {
    // 银行把明细行整块去掉时，必须报错而不是"解析成功 0 笔"
    let err = parse_cmb_daily_bill("<html><body>今日无消费</body></html>").unwrap_err();
    assert!(err.contains("fixBand4"), "报错文案要能指出改版：{}", err);
}

#[test]
fn generic_keyword_reads_plain_text_statement() {
    let text = "交易日期 摘要 金额\n2026-01-15 消费 示例便利店 12.50\n2026-01-16 退款 示例便利店 12.50\n合计 25.00";
    let cfg = r#"{"include_keywords":["消费","退款"],"exclude_keywords":["合计"]}"#;
    let result = parse_generic_keyword(text, cfg).expect("通用模板解析失败");
    assert_eq!(result.transactions.len(), 2);
    assert_eq!(result.transactions[0].amount, 12.50);
    assert_eq!(result.transactions[0].direction, "expense");
    assert_eq!(result.transactions[1].direction, "income");
    assert_eq!(result.transactions[0].datetime, "2026-01-15 00:00:00");
}

#[test]
fn generic_keyword_without_rows_reports_error() {
    let err = parse_generic_keyword("尊敬的客户，请登录查看详情", "").unwrap_err();
    assert!(err.contains("没有解析到"), "应当显式失败：{}", err);
}

#[test]
fn custom_regex_named_groups() {
    let text = "2026-01-15 示例商户 17.10 元\n2026-01-16 交通卡 充值 200.00 元";
    let cfg = r#"{"pattern":"(?<date>\\d{4}-\\d{2}-\\d{2})\\s+(?<merchant>\\S+)[^\\d]*(?<amount>\\d+\\.\\d{2})"}"#;
    let result = parse_custom_regex(text, cfg).expect("自定义正则解析失败");
    assert_eq!(result.transactions.len(), 2);
    assert_eq!(result.transactions[1].merchant, "交通卡");
    assert_eq!(result.transactions[1].amount, 200.00);
    assert_eq!(result.transactions[0].datetime, "2026-01-15 00:00:00");
    assert_eq!(result.bill_date, "2026-01-15");
    assert!(result.warnings.is_empty());
}

#[test]
fn custom_regex_rejects_partial_date() {
    // 缺年份的 MM-DD 不能当日期：留空 + 警告，让入账层用邮件日期兜底
    let cfg = r#"{"pattern":"(?<date>\\d{2}-\\d{2})\\s+(?<merchant>\\S+)[^\\d]*(?<amount>\\d+\\.\\d{2})"}"#;
    let result = parse_custom_regex("01-15 便利店 12.00", cfg).expect("应能解析出金额");
    assert_eq!(result.transactions.len(), 1);
    assert_eq!(result.transactions[0].datetime, "");
    assert_eq!(result.transactions[0].merchant, "便利店");
    assert!(result.warnings.iter().any(|w| w.contains("不是完整日期")));
}

#[test]
fn custom_regex_without_hit_reports_error() {
    let err = parse_custom_regex("今天没有消费", r#"{"pattern":"(?<amount>\\d+\\.\\d{2})"}"#).unwrap_err();
    assert!(err.contains("没有命中"), "应当显式失败：{}", err);
}

#[test]
fn wire_config_defaults_match_ledger_side() {
    // email_module 的入参默认值要和 ledger 的期望一致，否则端口/信箱会悄悄跑偏
    let json = serde_json::to_string(&EmailAccountWire::of(&rule(), "pw")).unwrap();
    let cfg: serde_json::Value = serde_json::from_str(&json).unwrap();
    assert_eq!(cfg["protocol"], "imap");
    assert_eq!(cfg["mailbox"], "INBOX");
    assert_eq!(cfg["use_ssl"], true);
    assert_eq!(cfg["password"], "pw");
}
