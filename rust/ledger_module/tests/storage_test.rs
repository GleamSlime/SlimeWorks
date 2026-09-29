//! 存储层离线测试：去重、待确认队列、统计口径都在这里兜底。
//! 库连接是进程级单例，所以每个用例都要先占锁再开自己的临时库。

use lazy_static::lazy_static;
use ledger_module::storage;
use ledger_module::storage::TxFilter;
use ledger_module::types::*;
use std::sync::{Mutex, MutexGuard};

lazy_static! {
    static ref DB_LOCK: Mutex<()> = Mutex::new(());
}

struct TempDb {
    path: String,
    _guard: MutexGuard<'static, ()>,
}

impl TempDb {
    fn open(tag: &str) -> TempDb {
        // 中毒锁也要继续跑：上一个用例的 panic 不该让后面的用例全跳过
        let guard = DB_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        storage::close_db();
        let path = std::env::temp_dir()
            .join(format!("slime_ledger_{}_{}.sqlite", tag, std::process::id()))
            .to_string_lossy()
            .to_string();
        let _ = std::fs::remove_file(&path);
        storage::init_db(&path).expect("初始化临时账本失败");
        TempDb { path, _guard: guard }
    }

    fn account_id(&self) -> i64 {
        storage::list_accounts(true)
            .unwrap()
            .first()
            .map(|a| a.id)
            .unwrap_or(0)
    }
}

impl Drop for TempDb {
    fn drop(&mut self) {
        storage::close_db();
        for suffix in ["", "-wal", "-shm"] {
            let _ = std::fs::remove_file(format!("{}{}", self.path, suffix));
        }
    }
}

fn tx(merchant: &str, amount: f64, bill_date: &str) -> Transaction {
    Transaction {
        id: 0,
        occurred_at: format!("{} 12:00:00", bill_date),
        bill_date: bill_date.to_string(),
        direction: DIRECTION_EXPENSE.to_string(),
        amount,
        currency: "CNY".to_string(),
        account_id: 0,
        category_id: 0,
        merchant: merchant.to_string(),
        note: String::new(),
        source: SOURCE_MANUAL.to_string(),
        rule_id: 0,
        email_uid: String::new(),
        dedup_key: String::new(),
        status: STATUS_POSTED.to_string(),
        created_at: String::new(),
        updated_at: String::new(),
        account_name: String::new(),
        category_name: String::new(),
        category_icon: String::new(),
        category_direction: String::new(),
    }
}

fn category_id(name: &str) -> i64 {    storage::list_categories("")
        .unwrap()
        .into_iter()
        .find(|c| c.name == name)
        .map(|c| c.id)
        .unwrap_or(0)
}

/// 邮件来源的流水：去重索引只对 (rule_id, email_uid, dedup_key) 生效
fn email_tx(rule_id: i64, uid: &str, dedup: &str, amount: f64, occurred: &str) -> Transaction {
    Transaction {
        occurred_at: occurred.to_string(),
        bill_date: occurred.chars().take(10).collect(),
        amount,
        source: SOURCE_EMAIL.to_string(),
        rule_id,
        email_uid: uid.to_string(),
        dedup_key: dedup.to_string(),
        status: STATUS_PENDING.to_string(),
        ..tx("示例支付-示例商户", amount, "")
    }
}

#[test]
fn init_seeds_builtin_categories_and_cash_account() {
    let db = TempDb::open("seed");
    assert!(storage::is_ready());

    let accounts = storage::list_accounts(false).unwrap();
    assert!(
        accounts.iter().any(|a| a.name == "现金" && a.account_type == "cash"),
        "首启必须有一个能直接记的现金账户"
    );

    let cats = storage::list_categories("").unwrap();
    assert!(cats.len() >= 20, "内置类别至少要覆盖日常场景");
    assert!(cats.iter().all(|c| c.is_builtin));
    assert!(cats.iter().any(|c| c.name == "餐饮美食" && c.direction == DIRECTION_EXPENSE));
    assert!(cats.iter().any(|c| c.name == "退款退货" && c.direction == DIRECTION_INCOME));
    // 按方向过滤不能把另一个方向的类别漏进来
    let income_only = storage::list_categories(DIRECTION_INCOME).unwrap();
    assert!(income_only.iter().all(|c| c.direction == DIRECTION_INCOME));

    // 二次 init 走升级路径，不能把用户改过的类别重置
    let custom = storage::upsert_category(&Category {
        id: 0,
        name: "宠物医疗".to_string(),
        icon: "paw".to_string(),
        direction: DIRECTION_EXPENSE.to_string(),
        sort_order: 99,
        is_builtin: false,
    })
    .unwrap();
    storage::init_db(&db.path).unwrap();
    let after = storage::list_categories("").unwrap();
    assert!(after.iter().any(|c| c.id == custom && c.name == "宠物医疗"));
    assert_eq!(after.iter().filter(|c| c.name == "餐饮美食").count(), 1, "播种必须幂等");
}

#[test]
fn transaction_crud_and_merchant_memory() {
    let db = TempDb::open("tx_crud");
    let account = db.account_id();
    let food = category_id("餐饮美食");

    let mut a = tx("示例便利店", 12.50, "2026-01-15");
    a.account_id = account;
    a.category_id = food;
    let id = storage::insert_transaction(&a).unwrap();
    assert!(id > 0);

    let got = storage::get_transaction(id).unwrap().expect("刚写的流水要能读到");
    assert_eq!(got.amount, 12.50);
    assert_eq!(got.account_name, "现金", "列表联查字段要带出账户名");
    assert_eq!(got.category_name, "餐饮美食");

    let mut b = tx("示例便利店", 30.00, "2026-01-16");
    b.account_id = account;
    // 没指定类别时按历史习惯猜：同一个商户第二笔应自动落进"餐饮美食"
    storage::remember_merchant("示例便利店", food).unwrap();
    let id_b = storage::insert_transaction(&b).unwrap();
    assert_eq!(storage::get_transaction(id_b).unwrap().unwrap().category_name, "餐饮美食");

    let mut patch = storage::get_transaction(id_b).unwrap().unwrap();
    patch.note = "改备注".to_string();
    patch.direction = DIRECTION_INCOME.to_string();
    storage::update_transaction(&patch).unwrap();
    let after = storage::get_transaction(id_b).unwrap().unwrap();
    assert_eq!(after.note, "改备注");
    assert_eq!(after.direction, DIRECTION_INCOME);

    assert!(storage::delete_transaction(id_b).unwrap());
    assert!(storage::get_transaction(id_b).unwrap().is_none());
    assert!(!storage::delete_transaction(id_b).unwrap());
}

#[test]
fn category_guardrails() {
    let db = TempDb::open("category");
    let account = db.account_id();
    let custom = storage::upsert_category(&Category {
        id: 0,
        name: "宠物医疗".to_string(),
        icon: "paw".to_string(),
        direction: DIRECTION_EXPENSE.to_string(),
        sort_order: 99,
        is_builtin: false,
    })
    .unwrap();
    let mut t = tx("示例宠物医院", 300.00, "2026-02-01");
    t.account_id = account;
    t.category_id = custom;
    let tx_id = storage::insert_transaction(&t).unwrap();

    // 删自建类别不能把流水变成孤儿：整批发回"其他支出"
    let msg = storage::delete_category(custom).unwrap();
    assert!(msg.contains("其他支出"), "实际文案：{}", msg);
    assert_eq!(storage::get_transaction(tx_id).unwrap().unwrap().category_name, "其他支出");

    let builtin = storage::list_categories("").unwrap().into_iter().find(|c| c.is_builtin).unwrap();
    assert!(storage::delete_category(builtin.id).unwrap_err().to_string().contains("内置"));
    assert!(storage::delete_category(999999).unwrap_err().to_string().contains("类别不存在"));
}

#[test]
fn email_dedup_is_keyed_by_rule_uid_and_dedup_key() {
    let db = TempDb::open("dedup");
    let rule = 7i64;

    let first = storage::insert_transaction(&email_tx(rule, "UID-1", "2026-01-15 10:00:00|33.00|示例|消费", 33.00, "2026-01-15 10:00:00")).unwrap();
    assert!(first > 0);
    // 同一封邮件重收：完全相同的键必须被唯一索引挡下（返回 0 而不是报错）
    let again = storage::insert_transaction(&email_tx(rule, "UID-1", "2026-01-15 10:00:00|33.00|示例|消费", 33.00, "2026-01-15 10:00:00")).unwrap();
    assert_eq!(again, 0, "重复入账必须挡下");

    // 同一天两笔等额的真实重复扣款：时刻不同就得各记一笔
    let second = storage::insert_transaction(&email_tx(rule, "UID-2", "2026-01-15 11:00:00|33.00|示例|消费", 33.00, "2026-01-15 11:00:00")).unwrap();
    assert!(second > 0, "等额但不同时刻的两笔不能互相挡掉");
    assert_eq!(storage::count_transactions(&TxFilter::default()).unwrap(), 2);

    // 换个规则收同一个 UID：归属不同，不该被旧规则的去重键挡下
    let other_rule = storage::insert_transaction(&email_tx(rule + 1, "UID-1", "2026-01-15 10:00:00|33.00|示例|消费", 33.00, "2026-01-15 10:00:00")).unwrap();
    assert!(other_rule > 0);
    let db_account = db.account_id();
    // 手工流水没有邮件归属，走去重索引之外
    let mut manual = tx("示例商户", 33.00, "2026-01-15");
    manual.account_id = db_account;
    assert!(storage::insert_transaction(&manual).unwrap() > 0);
}

#[test]
fn stats_only_count_posted_transactions() {
    let db = TempDb::open("stats");
    let account = db.account_id();
    let food = category_id("餐饮美食");

    let mut posted = tx("示例便利店", 100.00, "2026-03-01");
    posted.account_id = account;
    posted.category_id = food;
    storage::insert_transaction(&posted).unwrap();

    let mut refund = tx("示例商户", 40.00, "2026-03-02");
    refund.account_id = account;
    refund.category_id = category_id("退款退货");
    refund.direction = DIRECTION_INCOME.to_string();
    storage::insert_transaction(&refund).unwrap();

    let mut pending = tx("示例商户", 999.00, "2026-03-03");
    pending.account_id = account;
    pending.status = STATUS_PENDING.to_string();
    let pending_id = storage::insert_transaction(&pending).unwrap();

    let summary = storage::stats_summary(&TxFilter::default()).unwrap();
    assert_eq!(summary["expense"], serde_json::json!(100.0));
    assert_eq!(summary["income"], serde_json::json!(40.0));
    assert_eq!(summary["net"], serde_json::json!(-60.0));
    assert_eq!(summary["count"], serde_json::json!(2), "待确认不该进统计");
    assert_eq!(summary["min_date"], serde_json::json!("2026-03-01"));
    assert_eq!(summary["max_date"], serde_json::json!("2026-03-02"));

    let days = storage::stats_by_day(&TxFilter::default()).unwrap();
    assert_eq!(days.len(), 2);

    let cats = storage::stats_by_category(&TxFilter::default()).unwrap();
    assert_eq!(cats.len(), 2);
    assert!(cats.iter().any(|c| c["category_name"] == serde_json::json!("餐饮美食")));

    // 商户汇总只看支出：退款那笔不该混进来
    let merchants = storage::stats_by_merchant(&TxFilter::default(), 10).unwrap();
    assert_eq!(merchants.len(), 1);
    assert_eq!(merchants[0]["merchant"], serde_json::json!("示例便利店"));

    // 确认入账后统计口径立刻跟着变
    storage::set_tx_status(pending_id, STATUS_POSTED).unwrap();
    assert_eq!(storage::stats_summary(&TxFilter::default()).unwrap()["count"], serde_json::json!(3));

    // 区间与关键词过滤
    let mut filter = TxFilter::default();
    filter.start_date = "2026-03-02".to_string();
    assert_eq!(storage::count_transactions(&filter).unwrap(), 2);
    filter.keyword = "便利".to_string();
    assert_eq!(storage::count_transactions(&filter).unwrap(), 0);
    let listed = storage::list_transactions(&filter).unwrap();
    assert!(listed.is_empty());

    let months = storage::stats_by_month(6).unwrap();
    assert!(months.iter().any(|m| m["month"] == serde_json::json!("2026-03")));
}

#[test]
fn soft_duplicate_detects_posted_only() {
    let db = TempDb::open("soft_dup");
    let account = db.account_id();
    let mut t = tx("示例商户", 66.00, "2026-04-01");
    t.account_id = account;
    let id = storage::insert_transaction(&t).unwrap();

    let hit = storage::find_soft_duplicate("2026-04-01", 66.00, "示例商户", account)
        .unwrap()
        .expect("同日同额同商户应提示疑似重复");
    assert_eq!(hit.id, id);
    assert!(storage::find_soft_duplicate("2026-04-02", 66.00, "示例商户", account).unwrap().is_none());
    assert!(storage::find_soft_duplicate("2026-04-01", 66.01, "示例商户", account).unwrap().is_none());

    storage::set_tx_status(id, STATUS_PENDING).unwrap();
    assert!(
        storage::find_soft_duplicate("2026-04-01", 66.00, "示例商户", account).unwrap().is_none(),
        "没确认的流水不该被当成重复证据"
    );
}

#[test]
fn email_rule_crud_and_secret_ref() {
    let _db = TempDb::open("rule");
    let mut rule = EmailRule {
        name: "招行每日账单".to_string(),
        host: "imap.example.com".to_string(),
        username: "me@example.com".to_string(),
        sender_match: "bill@cmbchina".to_string(),
        subject_match: "每日账单".to_string(),
        ..EmailRule::default()
    };
    let id = storage::upsert_email_rule(&rule).unwrap();
    assert!(id > 0);
    rule.id = id;
    rule.interval_minutes = 720;
    rule.daily_time = "09:30".to_string();
    storage::upsert_email_rule(&rule).unwrap();

    let got = storage::get_email_rule(id).unwrap().expect("规则要能读回");
    assert_eq!(got.name, "招行每日账单");
    assert_eq!(got.interval_minutes, 720);
    assert_eq!(got.daily_time, "09:30");
    assert_eq!(got.protocol, "imap");
    assert_eq!(got.template_id, "auto");
    assert_eq!(storage::list_email_rules().unwrap().len(), 1, "更新不能长出新行");

    // 口令只存指针，正文里绝不落库
    storage::set_rule_secret_ref(id, "secure://ledger/rule/7").unwrap();
    assert_eq!(storage::rule_secret_ref(id).unwrap(), "secure://ledger/rule/7");

    storage::touch_rule_run(id, "收取 1 封").unwrap();
    let touched = storage::get_email_rule(id).unwrap().unwrap();
    assert_eq!(touched.last_result, "收取 1 封");
    assert!(!touched.last_run_at.is_empty());

    storage::set_email_rule_enabled(id, false).unwrap();
    assert!(!storage::get_email_rule(id).unwrap().unwrap().enabled);
    storage::delete_email_rule(id).unwrap();
    assert!(storage::get_email_rule(id).unwrap().is_none());
    assert!(storage::get_email_rule(12345).unwrap().is_none());
}

#[test]
fn pending_email_queue_round_trip() {
    let _db = TempDb::open("queue");
    let account = _db.account_id();
    let rule = storage::upsert_email_rule(&EmailRule {
        name: "招行".to_string(),
        host: "imap.example.com".to_string(),
        ..EmailRule::default()
    })
    .unwrap();

    let mut t = email_tx(rule, "UID-9", "2026-05-01 09:00:00|17.10|示例|消费", 17.10, "2026-05-01 09:00:00");
    t.account_id = account;
    let tx_id = storage::insert_transaction(&t).unwrap();

    let warnings = vec!["第 3 行未识别到金额".to_string()];
    assert!(storage::record_email(
        rule, "UID-9", "<m9@cmb>", "bill@cmbchina.com", "每日账单",
        "2026-05-01 09:30:00", "2026-05-01", 1, false,
        Some(20000.0), Some(1000), &warnings, 79729
    ).unwrap());
    // 同一封邮件第二次收下必须失败（唯一索引 rule_id + message_uid）
    assert!(!storage::record_email(
        rule, "UID-9", "<m9@cmb>", "bill@cmbchina.com", "每日账单",
        "2026-05-01 09:30:00", "2026-05-01", 1, false,
        None, None, &[], 79729
    ).unwrap());

    assert_eq!(storage::known_email_uids(rule).unwrap(), vec!["UID-9".to_string()]);
    assert_eq!(storage::count_pending_emails().unwrap(), 1);

    let pending = storage::list_pending_email(false, 50).unwrap();
    assert_eq!(pending.len(), 1);
    let mail = &pending[0];
    assert_eq!(mail.subject, "每日账单");
    assert_eq!(mail.tx_count, 1);
    assert_eq!(mail.available_credit, Some(20000.0));
    assert_eq!(mail.points_balance, Some(1000));
    assert_eq!(mail.warnings, warnings);
    assert_eq!(mail.rule_name, "招行", "队列要能看出是哪条规则收的");
    assert_eq!(mail.html_len, 79729);

    let detail = storage::pending_email_detail(mail.id).unwrap().unwrap();
    assert_eq!(detail.message_uid, "UID-9");
    let txs = storage::transactions_of_email(mail.id).unwrap();
    assert_eq!(txs.len(), 1);
    assert_eq!(txs[0].id, tx_id);

    // 整封确认：邮件标记已入账，队列从待确认挪到已收
    storage::mark_email_applied(mail.id).unwrap();
    assert_eq!(storage::set_tx_status_by_email(mail.id, STATUS_POSTED).unwrap(), 1);
    assert!(storage::list_pending_email(false, 50).unwrap().is_empty());
    assert_eq!(storage::list_pending_email(true, 50).unwrap().len(), 1);
    assert_eq!(storage::count_pending_emails().unwrap(), 0);
    assert_eq!(storage::get_transaction(tx_id).unwrap().unwrap().status, STATUS_POSTED);
}

#[test]
fn fetch_log_lifecycle() {
    let _db = TempDb::open("log");
    let rule = storage::upsert_email_rule(&EmailRule {
        name: "日志规则".to_string(),
        host: "imap.example.com".to_string(),
        ..EmailRule::default()
    })
    .unwrap();

    let log_id = storage::begin_fetch_log(rule).unwrap();
    assert!(log_id > 0);
    storage::finish_fetch_log(log_id, true, 2, 5, 1, "收取 2 封新邮件").unwrap();
    let logs = storage::list_fetch_logs(10).unwrap();
    assert_eq!(logs.len(), 1);
    assert_eq!(logs[0].rule_id, rule);
    assert!(logs[0].ok);
    assert_eq!(logs[0].new_emails, 2);
    assert_eq!(logs[0].new_tx, 5);
    assert_eq!(logs[0].skipped_tx, 1);
    assert!(logs[0].detail.contains("2 封"));

    let failed = storage::begin_fetch_log(rule).unwrap();
    storage::finish_fetch_log(failed, false, 0, 0, 0, "收信失败: 连接超时").unwrap();
    let logs = storage::list_fetch_logs(10).unwrap();
    assert_eq!(logs.len(), 2);
    assert!(!logs[0].ok, "最新的排前面");

    storage::clear_fetch_logs().unwrap();
    assert!(storage::list_fetch_logs(10).unwrap().is_empty());
}

#[test]
fn reading_without_init_fails_loudly() {
    let _db = TempDb::open("uninit");
    storage::close_db();
    let err = storage::list_accounts(false).unwrap_err().to_string();
    assert!(err.contains("未初始化"), "实际报错：{}", err);
}
