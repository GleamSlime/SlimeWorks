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

/// 月度电子账单（2026 版）的回归样本：合成数据，结构与真实邮件同形
fn cmb_statement_html() -> String {
    let path = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/cmb_monthly_statement_sample.html");
    std::fs::read_to_string(path).expect("读不到招行月度账单 fixture")
}

/// 真实留档账单只能本地验：里面是本人姓名、商户和金额，绝不进仓库。
/// 用法：`CMB_STATEMENT_SAMPLE=<留档 html 路径> cargo test -p ledger_module cmb_statement_sample -- --ignored --nocapture`
#[test]
#[ignore = "样本是本机留档的真实账单，只在本地按需跑"]
fn cmb_statement_sample_parses() {
    let path = std::env::var("CMB_STATEMENT_SAMPLE").expect("先设 CMB_STATEMENT_SAMPLE 指向留档 HTML");
    let html = std::fs::read_to_string(&path).expect("读不到样本");
    let result = parse_cmb_daily_bill(&html).expect("真实样本解析失败");
    // 只报结构不报内容：金额、商户、姓名都不往测试输出里印
    let dates: Vec<&str> =
        result.transactions.iter().filter(|t| t.datetime.len() >= 10).map(|t| &t.datetime[..10]).collect();
    println!(
        "解析 {} 笔，账单日 {}，警告 {} 条，能定到具体日期的 {} 笔，日期跨度 {} ~ {}",
        result.transactions.len(),
        result.bill_date,
        result.warnings.len(),
        dates.len(),
        dates.iter().min().unwrap_or(&""),
        dates.iter().max().unwrap_or(&""),
    );
    for w in &result.warnings {
        println!("警告：{}", w);
    }
    assert!(result.transactions.iter().all(|t| t.datetime.len() >= 10), "有流水没定到具体日期");
}

#[test]
fn cmb_monthly_statement_reads_positional_columns() {
    let result = parse_cmb_daily_bill(&cmb_statement_html()).expect("月度账单解析失败");
    assert_eq!(result.template_id, "cmb_daily_bill");
    // 账单日取期间结束日，不是期间开始日
    assert_eq!(result.bill_date, "2026-01-21");

    let rows: Vec<(String, f64, String, String, String, String)> = result
        .transactions
        .iter()
        .map(|t| {
            (
                t.datetime.clone(),
                t.amount,
                t.entry_type.clone(),
                t.direction.clone(),
                t.card_tail.clone(),
                t.merchant.clone(),
            )
        })
        .collect();
    assert_eq!(
        rows,
        vec![
            // 还款行没有交易日，退回入账日；负数按收入
            ("2026-01-21 00:00:00".into(), 3000.00, "还款".into(), "income".into(), "0001".into(), "自动还款".into()),
            ("2026-01-05 00:00:00".into(), 33.00, "支付".into(), "expense".into(), "0001".into(), "示例支付-京东商城业务".into()),
            // 同日同额同商户的第二笔：真实重复扣款，必须还在
            ("2026-01-05 00:00:00".into(), 33.00, "支付".into(), "expense".into(), "0001".into(), "示例支付-京东商城业务".into()),
            ("2026-01-08 00:00:00".into(), 35.00, String::new(), "expense".into(), "0001".into(), "示例外卖平台示例烧烤店".into()),
            // 期间跨到去年 12 月的行，年份要退回期间起始那年
            ("2025-12-25 00:00:00".into(), 12.00, "退款".into(), "income".into(), "0002".into(), "示例支付-示例游戏平台退款".into()),
            // 外币行按银行折算好的人民币金额入账，行尾多出的空白格不能把列位带偏
            ("2026-01-12 00:00:00".into(), 30.45, "消费".into(), "expense".into(), "0001".into(), "示例境外平台消费".into()),
        ]
    );
    assert!(result.transactions.iter().all(|t| t.currency == "CNY"));
    assert!(result.available_credit.is_none() && result.points_balance.is_none());
    // 只允许"摘要没有类型词"那一条聚合警告，逐行噪声不算成功
    assert_eq!(result.warnings.len(), 1, "警告不符: {:?}", result.warnings);
    assert!(result.warnings[0].contains("没有已知交易类型"));
}

#[test]
fn cmb_monthly_statement_email_hits_cmb_fingerprint() {
    // 月度账单的栏目名全是图片，只有标题里的"电子账单"能认，正文靠招行资源域名定性
    let html = cmb_statement_html();
    assert_eq!(resolve_template_id(&rule(), "招商银行信用卡电子账单", &html), "cmb_daily_bill");
    // 没有招行特征的正文即使标题带"账单"也不该被内置模板认领
    assert_eq!(resolve_template_id(&rule(), "您的账单已出", "<html>没有任何招行特征</html>"), "generic_keyword");
}

#[test]
fn identical_statement_rows_keep_distinct_dedup_keys() {
    // 月账单没有时分，同一天两笔 33.00 的同商户扣款只能靠行序分开
    let result = parse_cmb_daily_bill(&cmb_statement_html()).expect("月度账单解析失败");
    let rule = EmailRule {
        id: 7,
        ..Default::default()
    };
    let keys: Vec<String> = result
        .transactions
        .iter()
        .enumerate()
        .map(|(seq, t)| {
            ledger_module::parse_glue::tx_from_parsed(t, &rule, "6873", "2026-01-21", 1, seq).dedup_key
        })
        .collect();
    let stem = |k: &str| k.rsplit_once('|').map(|(s, _)| s).unwrap_or(k).to_string();
    // 去掉行序尾巴后两笔一模一样，说明它们本来会撞在同一个去重键上
    assert_eq!(stem(&keys[1]), stem(&keys[2]));
    assert_ne!(keys[1], keys[2], "重复扣款的去重键撞车了: {:?}", (&keys[1], &keys[2]));
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
