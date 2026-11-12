use chrono::Local;
use slime_logger::{sw_info, sw_warn};

use crate::parse_glue::{
    self, EmailAccountWire, WireFetchOutcome,
};
use crate::scheduler;
use crate::storage::{self, TxFilter};
use crate::types::*;

/// 收信条数上限：账单邮件一天一封，取最近几封足够补漏
const DEFAULT_FETCH_LIMIT: u64 = 10;

/// 历史回补的默认扫描条数：一次手动点按要把大半年的账单都过一遍，
/// 又不至于把上千封全文拖下 TLS（每封一次 UID FETCH 往返）。
const BACKFILL_FETCH_LIMIT: u64 = 200;

fn json<T: serde::Serialize>(v: &T) -> Result<String, String> {
    serde_json::to_string(v).map_err(|e| format!("序列化失败: {}", e))
}

fn from_json<T: serde::de::DeserializeOwned>(s: &str, what: &str) -> Result<T, String> {
    serde_json::from_str(s).map_err(|e| format!("解析{}失败: {}", what, e))
}

fn today() -> String {
    Local::now().format("%Y-%m-%d").to_string()
}

// ── 初始化 ───────────────────────────────────────────────────────────────────

pub fn ledger_init(db_path_json: String) -> Result<String, String> {
    #[derive(serde::Deserialize)]
    struct DbPath {
        #[serde(default)]
        db_path: String,
    }
    let cfg: DbPath = from_json(&db_path_json, "账本路径")?;
    if cfg.db_path.is_empty() {
        return Err("账本数据库路径为空".to_string());
    }
    if storage::is_ready() {
        return Ok("账本模块已初始化".to_string());
    }
    storage::init_db(&cfg.db_path).map_err(|e| format!("初始化账本失败: {}", e))?;
    sw_info!("[ledger] 账本初始化完成: {}", cfg.db_path);
    Ok(format!("账本初始化完成: {}", cfg.db_path))
}

pub fn ledger_is_ready() -> bool {
    storage::is_ready()
}

// ── 账户 ─────────────────────────────────────────────────────────────────────

pub fn ledger_list_accounts() -> Result<String, String> {
    json(&storage::list_accounts(false).map_err(|e| e.to_string())?)
}

pub fn ledger_upsert_account(account_json: String) -> Result<i64, String> {
    let mut account: Account = from_json(&account_json, "账户")?;
    if account.name.trim().is_empty() {
        return Err("账户名称不能为空".to_string());
    }
    // 入参容缺后这两项可能是空串，落库前补成默认口径
    if account.account_type.is_empty() {
        account.account_type = "credit_card".to_string();
    }
    if account.currency.is_empty() {
        account.currency = "CNY".to_string();
    }
    storage::upsert_account(&account).map_err(|e| e.to_string())
}

pub fn ledger_delete_account(id: i64) -> Result<String, String> {
    storage::delete_account(id).map_err(|e| e.to_string())
}

// ── 类别 ─────────────────────────────────────────────────────────────────────

pub fn ledger_list_categories(direction: String) -> Result<String, String> {
    json(&storage::list_categories(&direction).map_err(|e| e.to_string())?)
}

pub fn ledger_upsert_category(category_json: String) -> Result<i64, String> {
    let mut category: Category = from_json(&category_json, "类别")?;
    if category.name.trim().is_empty() {
        return Err("类别名称不能为空".to_string());
    }
    if category.direction.is_empty() {
        category.direction = DIRECTION_EXPENSE.to_string();
    }
    storage::upsert_category(&category).map_err(|e| e.to_string())
}

pub fn ledger_delete_category(id: i64) -> Result<String, String> {
    storage::delete_category(id).map_err(|e| e.to_string())
}

pub fn ledger_list_merchant_memory() -> Result<String, String> {
    let rows = storage::list_merchant_memory().map_err(|e| e.to_string())?;
    let out: Vec<_> = rows
        .into_iter()
        .map(|(key, cid)| serde_json::json!({ "merchant_key": key, "category_id": cid }))
        .collect();
    json(&out)
}

pub fn ledger_forget_merchant(merchant_key: String) -> Result<(), String> {
    storage::forget_merchant(&merchant_key).map_err(|e| e.to_string())
}

// ── 流水 ─────────────────────────────────────────────────────────────────────

pub fn ledger_list_transactions(filter_json: String) -> Result<String, String> {
    let filter: TxFilter = parse_filter(&filter_json)?;
    json(&storage::list_transactions(&filter).map_err(|e| e.to_string())?)
}

pub fn ledger_count_transactions(filter_json: String) -> Result<i64, String> {
    let filter: TxFilter = parse_filter(&filter_json)?;
    storage::count_transactions(&filter).map_err(|e| e.to_string())
}

pub fn ledger_add_transaction(tx_json: String) -> Result<i64, String> {
    let mut tx: Transaction = from_json(&tx_json, "流水")?;
    if tx.amount <= 0.0 {
        return Err("金额必须大于 0".to_string());
    }
    if tx.direction.is_empty() {
        tx.direction = DIRECTION_EXPENSE.to_string();
    }
    if tx.currency.is_empty() {
        tx.currency = "CNY".to_string();
    }
    if tx.source.is_empty() {
        tx.source = SOURCE_MANUAL.to_string();
    }
    if tx.status.is_empty() {
        tx.status = STATUS_POSTED.to_string();
    }
    if tx.account_id == 0 {
        tx.account_id = default_account_id()?;
    }
    if tx.category_id == 0 {
        tx.category_id = default_category_id_for(&tx.direction)?;
    }
    storage::insert_transaction(&tx).map_err(|e| e.to_string())
}

pub fn ledger_update_transaction(tx_json: String) -> Result<(), String> {
    let tx: Transaction = from_json(&tx_json, "流水")?;
    if tx.id <= 0 {
        return Err("缺少流水 id".to_string());
    }
    if tx.amount <= 0.0 {
        return Err("金额必须大于 0".to_string());
    }
    if tx.category_id > 0 && tx.source == SOURCE_EMAIL && !tx.merchant.is_empty() {
        // 用户改归类 = 教一次记账习惯，后续同类商户自动跟上
        let _ = storage::remember_merchant(&tx.merchant, tx.category_id);
    }
    storage::update_transaction(&tx).map_err(|e| e.to_string())
}

pub fn ledger_delete_transaction(id: i64) -> Result<bool, String> {
    storage::delete_transaction(id).map_err(|e| e.to_string())
}

pub fn ledger_check_duplicate(dup_json: String) -> Result<String, String> {
    #[derive(serde::Deserialize)]
    struct Dup {
        #[serde(default)]
        bill_date: String,
        #[serde(default)]
        amount: f64,
        #[serde(default)]
        merchant: String,
        #[serde(default)]
        account_id: i64,
    }
    let d: Dup = from_json(&dup_json, "查重条件")?;
    let hit = storage::find_soft_duplicate(&d.bill_date, d.amount, &d.merchant, d.account_id)
        .map_err(|e| e.to_string())?;
    match hit {
        Some(t) => json(&serde_json::json!({
            "duplicated": true,
            "existing_id": t.id,
            "existing_desc": format!("{} {} {:.2}", t.bill_date, t.merchant, t.amount),
        })),
        None => Ok(r#"{"duplicated":false,"existing_id":0,"existing_desc":""}"#.to_string()),
    }
}

// ── 统计 ─────────────────────────────────────────────────────────────────────

pub fn ledger_stats_by_day(filter_json: String) -> Result<String, String> {
    let filter: TxFilter = parse_filter(&filter_json)?;
    json(&storage::stats_by_day(&filter).map_err(|e| e.to_string())?)
}

pub fn ledger_stats_by_category(filter_json: String) -> Result<String, String> {
    let filter: TxFilter = parse_filter(&filter_json)?;
    json(&storage::stats_by_category(&filter).map_err(|e| e.to_string())?)
}

pub fn ledger_stats_by_merchant(filter_json: String, top: i64) -> Result<String, String> {
    let filter: TxFilter = parse_filter(&filter_json)?;
    json(&storage::stats_by_merchant(&filter, top).map_err(|e| e.to_string())?)
}

pub fn ledger_stats_summary(filter_json: String) -> Result<String, String> {
    let filter: TxFilter = parse_filter(&filter_json)?;
    json(&storage::stats_summary(&filter).map_err(|e| e.to_string())?)
}

pub fn ledger_stats_by_month(months: i64) -> Result<String, String> {
    json(&storage::stats_by_month(months).map_err(|e| e.to_string())?)
}

/// filter_json → TxFilter（前端只传字符串，避免为每个统计口都开一个 FFI 函数）
fn parse_filter(filter_json: &str) -> Result<TxFilter, String> {
    if filter_json.trim().is_empty() {
        return Ok(TxFilter::default());
    }
    from_json::<serde_json::Value>(filter_json, "查询条件").map(|v| TxFilter {
        start_date: str_of(&v, "start_date"),
        end_date: str_of(&v, "end_date"),
        direction: str_of(&v, "direction"),
        account_id: i64_of(&v, "account_id"),
        category_id: i64_of(&v, "category_id"),
        source: str_of(&v, "source"),
        status: str_of(&v, "status"),
        keyword: str_of(&v, "keyword"),
        limit: i64_of(&v, "limit"),
        offset: i64_of(&v, "offset"),
    })
}

fn str_of(v: &serde_json::Value, key: &str) -> String {
    v.get(key).and_then(|x| x.as_str()).unwrap_or_default().to_string()
}

fn i64_of(v: &serde_json::Value, key: &str) -> i64 {
    v.get(key).and_then(|x| x.as_i64()).unwrap_or(0)
}

fn default_account_id() -> Result<i64, String> {
    let accounts = storage::list_accounts(true).map_err(|e| e.to_string())?;
    accounts
        .first()
        .map(|a| a.id)
        .ok_or_else(|| "还没有任何账户，请先新建一个账户".to_string())
}

// ── 邮件规则 ─────────────────────────────────────────────────────────────────

pub fn ledger_list_rules() -> Result<String, String> {
    json(&storage::list_email_rules().map_err(|e| e.to_string())?)
}

pub fn ledger_upsert_rule(rule_json: String, password: String) -> Result<i64, String> {
    let rule: EmailRule = from_json(&rule_json, "邮件规则")?;
    if rule.name.trim().is_empty() {
        return Err("规则名称不能为空".to_string());
    }
    if rule.host.trim().is_empty() {
        return Err("邮件服务器地址不能为空".to_string());
    }
    if matches!(rule.protocol.as_str(), "exchange_eas" | "carddav") {
        return Err(format!(
            "{} 当前版本尚未实现，仅支持 IMAP/POP3/SMTP",
            rule.protocol
        ));
    }
    let id = storage::upsert_email_rule(&rule).map_err(|e| e.to_string())?;
    if !password.is_empty() {
        ledger_set_rule_password(id, password)?;
    }
    Ok(id)
}

pub fn ledger_delete_rule(id: i64) -> Result<(), String> {
    storage::delete_email_rule(id).map_err(|e| e.to_string())?;
    scheduler::set_secret(id, "");
    Ok(())
}

pub fn ledger_set_rule_enabled(id: i64, enabled: bool) -> Result<(), String> {
    storage::set_email_rule_enabled(id, enabled).map_err(|e| e.to_string())
}

/// 密码只进内存与 Dart 侧安全存储，本函数不外泄任何回显
pub fn ledger_set_rule_password(rule_id: i64, password: String) -> Result<(), String> {
    scheduler::set_secret(rule_id, &password);
    storage::set_rule_secret_ref(rule_id, &format!("secure:ledger_rule_{}", rule_id))
        .map_err(|e| e.to_string())
}

pub fn ledger_has_rule_password(rule_id: i64) -> Result<bool, String> {
    if !scheduler::secret_of(rule_id).is_empty() {
        return Ok(true);
    }
    // 内存里没有再查 Dart 侧是否存过（secret_ref 存在即代表曾配置）
    let stored = storage::rule_secret_ref(rule_id).unwrap_or_default();
    Ok(!stored.is_empty())
}

pub fn ledger_rule_detail(id: i64) -> Result<String, String> {
    let rule = storage::get_email_rule(id)
        .map_err(|e| e.to_string())?
        .ok_or_else(|| "规则不存在".to_string())?;
    json(&rule)
}

// ── 模板 ─────────────────────────────────────────────────────────────────────

pub fn ledger_templates() -> Result<String, String> {
    json(&parse_glue::template_list())
}

/// 直接喂一段 HTML 走模板引擎，便于改版时先验证再改规则
pub fn ledger_parse_preview(html: String, template_id: String, template_config: String) -> Result<String, String> {
    let result = parse_glue::parse_message(&template_id, &template_config, &html, "")?;
    json(&result)
}

// ── 收取与入账 ───────────────────────────────────────────────────────────────

/// 核心编排：按规则收信 → 匹配 → 解析 → 去重落库
pub fn ledger_check_rule(rule_id: i64, password: String) -> Result<String, String> {
    check_by_rule(rule_id, &password)
}

/// 历史回补：从收件箱最近的 `limit` 封里（传 0 用 [BACKFILL_FETCH_LIMIT]）把命中
/// 规则的账单邮件全部补录入账。
///
/// 定时收取只看最新 10 封：账单一来就够快，但首次配规则、口令失效停摆几天、
/// 或者那 10 封里恰好夹了广告时，过去的账单就永远补不回来——银行邮件是有历史
/// 价值的，不能只认"从此刻开始收"。重复入账由两道现有兜底挡住：已收 UID 直接
/// 跳过，流水表的 UNIQUE(rule_id, email_uid, dedup_key) 又挡一遍，所以这个入口
/// 可以放心反复点。
pub fn ledger_backfill_rule(rule_id: i64, password: String, limit: u64) -> Result<String, String> {
    let limit = if limit == 0 { BACKFILL_FETCH_LIMIT } else { limit };
    check_with_limit(rule_id, &password, limit, true)
}

pub fn check_by_rule(rule_id: i64, password: &str) -> Result<String, String> {
    check_with_limit(rule_id, password, DEFAULT_FETCH_LIMIT, false)
}

fn check_with_limit(rule_id: i64, password: &str, limit: u64, history: bool) -> Result<String, String> {
    let rule = storage::get_email_rule(rule_id)
        .map_err(|e| e.to_string())?
        .ok_or_else(|| format!("规则 {} 不存在", rule_id))?;
    let log_id = storage::begin_fetch_log(rule_id).unwrap_or(0);
    let started = std::time::Instant::now();

    // 收信失败单独处理：它发生在批量入账之前，没有部分写入需要交代
    let outcome = match fetch_outcome(&rule, password, limit) {
        Ok(o) => o,
        Err(detail) => {
            finish_log(log_id, false, 0, 0, 0, &detail);
            let _ = storage::touch_rule_run(rule_id, &detail);
            return Err(detail);
        }
    };

    let mut new_emails = 0i64;
    let mut new_tx = 0i64;
    let mut skipped = 0i64;
    // 真正写库失败（非"已存在"去重跳过）的笔数。必须与 skipped 区分开：
    // 混在一起会 finish_log(ok=true) 并推进 last_run_at，每日规则当天不再重试，
    // 而 record_email 已记下 UID，下次收取直接跳过 → 账单永久丢失且日志看不出异常。
    let mut write_failed = 0i64;
    // 命中规则却解析不了的封数：单独记，改版要有数可看
    let mut parse_failed = 0i64;
    // 批中任何 DB 错误都要收尾日志：早期用 `?` 直接 return，finish_log 被跳过，
    // 日志永久停在「进行中」，用户看不出这一轮到底失败了没有。
    // 所以整段放闭包，提前返回的错误收敛到 batch_result，后面统一 finish_log。
    let batch_result: Result<(), String> = (|| {
        let known = storage::known_email_uids(rule_id).map_err(|e| e.to_string())?;
        // 账户尾号/类别名/商户习惯一次载入：一封账单十几笔逐笔回表在 WAL 上就是十几趟 I/O
        let lookup = storage::TxLookup::load().map_err(|e| e.to_string())?;
        for msg in &outcome.messages {
            if !parse_glue::message_matches(&rule, &msg.from, &msg.subject) {
                continue;
            }
            let template_id =
                parse_glue::resolve_template_id(&rule, &msg.subject, &msg.body_html);
            // 留档要留解析器真正吃过的那份：没 HTML 时它退而用纯文本
            let body = if msg.body_html.is_empty() { msg.body_text.as_str() } else { msg.body_html.as_str() };
            let parsed = match parse_glue::parse_message(
                &template_id,
                &rule.template_config,
                &msg.body_html,
                &msg.body_text,
            ) {
                Ok(p) => p,
                Err(e) => {
                    let archived = archive_parse_failure(rule_id, &msg.uid, &msg.subject, body);
                    sw_warn!(
                        "[ledger] 邮件《{}》解析失败: {}{}",
                        msg.subject,
                        e,
                        match &archived {
                            Some(p) => format!("；原文已留档 {}", p.display()),
                            None => String::new(),
                        }
                    );
                    if archived.is_some() {
                        parse_failed += 1;
                    }
                    skipped += 1;
                    continue;
                }
            };
            if parsed.transactions.is_empty() {
                // 命中了规则却没解析出任何一笔：多半是银行改了模板，必须可见
                if archive_parse_failure(rule_id, &msg.uid, &msg.subject, body).is_some() {
                    parse_failed += 1;
                }
                skipped += 1;
                continue;
            }
            if known.iter().any(|u| u == &msg.uid) {
                // 已收过：不重复入账，也不重复计数
                continue;
            }
            let received = if msg.date.is_empty() { now_text() } else { msg.date.clone() };
            let bill_date = pick_bill_date(&parsed.bill_date, &received);

            // 一封邮件的所有流水攒成一批：单事务提交，索引也已载入
            let mut batch: Vec<Transaction> = Vec::with_capacity(parsed.transactions.len());
            for (seq, item) in parsed.transactions.iter().enumerate() {
                let mut tx = parse_glue::tx_from_parsed(
                    item,
                    &rule,
                    &msg.uid,
                    &bill_date,
                    lookup.account_for(&item.card_tail, rule.default_account_id)?,
                    seq,
                );
                tx.bill_date = bill_date.clone();
                if rule.auto_apply {
                    tx.status = STATUS_POSTED.to_string();
                    // 类别映射已在批前载入，这里不再逐笔回表查 categories
                    tx.category_id = lookup.default_category_for(&tx.direction);
                }
                batch.push(tx);
            }
            let mut stored_tx = 0i64;
            match storage::insert_transactions(&batch) {
                Ok((inserted, deduped)) => {
                    new_tx += inserted;
                    stored_tx = inserted;
                    skipped += deduped;
                }
                Err(e) => {
                    // 整批回滚：这批既没入账也没记账，记失败让下一轮重试
                    sw_warn!("[ledger] 流水批量写入失败: {}", e);
                    write_failed += batch.len() as i64;
                }
            }

            let applied = rule.auto_apply && stored_tx > 0;
            let recorded = storage::record_email(
                rule_id,
                &msg.uid,
                &msg.message_id,
                &msg.from,
                &msg.subject,
                &received,
                &bill_date,
                stored_tx,
                applied,
                parsed.available_credit,
                parsed.points_balance,
                &parsed.warnings,
                msg.body_html.len() as i64,
            )
            .unwrap_or(false);
            if recorded {
                new_emails += 1;
            } else {
                skipped += stored_tx;
            }
        }
        Ok(())
    })();

    // 闭包里的任何提前返回都收敛到这里：日志无论如何都要收尾
    if let Err(e) = &batch_result {
        return Err(abort_batch(log_id, rule_id, &rule.name, new_emails, new_tx, skipped, e));
    }

    let elapsed = started.elapsed().as_secs();
    let scanned = outcome.messages.len();
    // 解析失败要留档：银行一改模板，没有原文就只能靠猜，猜一次错一次
    let archive_note = if parse_failed > 0 {
        match storage::db_dir() {
            Some(dir) => format!(
                "，{} 封解析失败（原文已存 {}，把这里的文件发给作者才改得动模板）",
                parse_failed,
                dir.join("parse_failures").display()
            ),
            None => format!("，{} 封解析失败", parse_failed),
        }
    } else {
        String::new()
    };
    let failed_note = if write_failed > 0 {
        format!("，{} 笔写库失败（下一轮会重试）", write_failed)
    } else {
        String::new()
    };
    let detail = if history {
        // 扫描条数要写出来：「扫了 200 封一封没命中」和「只扫到 10 封」在日志里
        // 长得一样，用户就会以为回补没生效。
        format!(
            "历史回补：扫描 {} 封，新增 {} 封账单 / {} 笔流水，跳过 {} 笔{}（{} 秒）{}",
            scanned,
            new_emails,
            new_tx,
            skipped,
            failed_note,
            elapsed,
            archive_note
        )
    } else {
        format!(
            "收取 {} 封新邮件，新增 {} 笔流水，跳过 {} 笔{}（{} 秒）{}",
            new_emails, new_tx, skipped, failed_note, elapsed, archive_note
        )
    };
    // 有写库失败时不能报成功：每日模式下 finish_log(ok=false) + 不推进 last_run_at，
    // 让下一轮自动收信重试，而不是把账单静默丢掉
    let ok = write_failed == 0;
    finish_log(log_id, ok, new_emails, new_tx, skipped, &detail);
    if ok {
        let _ = storage::touch_rule_run(rule_id, &detail);
    }
    sw_info!("[ledger] 规则《{}》检查完成：{}", rule.name, detail);
    Ok(detail)
}

/// 只做一次远程收取并解析，不落库；设置页"预览"用
pub fn ledger_fetch_emails(config_json: String, password: String, limit: u64) -> Result<String, String> {
    #[derive(serde::Deserialize)]
    struct Inline {
        #[serde(default)]
        rule_id: i64,
        #[serde(flatten)]
        rest: serde_json::Value,
    }
    let inline: Inline = from_json(&config_json, "邮箱配置")?;
    let mut merged = inline.rest.clone();
    if let Some(obj) = merged.as_object_mut() {
        if obj.get("password").and_then(|p| p.as_str()).unwrap_or("").is_empty() {
            obj.insert("password".into(), serde_json::json!(password));
        }
    }
    let cfg: EmailAccountWire = from_json(&merged.to_string(), "邮箱配置")?;
    let outcome: WireFetchOutcome = from_json(
        &email_module::api::email_fetch_json(json(&cfg)?, if limit == 0 { DEFAULT_FETCH_LIMIT } else { limit })?,
        "收信结果",
    )?;

    let rule = if inline.rule_id > 0 {
        storage::get_email_rule(inline.rule_id)
            .unwrap_or_default()
            .unwrap_or_else(default_rule_for_preview)
    } else {
        default_rule_for_preview()
    };

    let mut out: Vec<serde_json::Value> = Vec::new();
    for msg in &outcome.messages {
        let matched = parse_glue::message_matches(&rule, &msg.from, &msg.subject);
        let template_id = parse_glue::resolve_template_id(&rule, &msg.subject, &msg.body_html);
        let parsed = if matched {
            parse_glue::parse_message(&template_id, &rule.template_config, &msg.body_html, &msg.body_text).ok()
        } else {
            None
        };
        out.push(serde_json::json!({
            "uid": msg.uid,
            "from": msg.from,
            "subject": msg.subject,
            "date": msg.date,
            "size_bytes": msg.size_bytes,
            "html_len": msg.body_html.len(),
            "matched": matched,
            "template_id": template_id,
            "tx_count": parsed.as_ref().map(|p| p.transactions.len()).unwrap_or(0),
            "bill_date": parsed.as_ref().map(|p| p.bill_date.clone()).unwrap_or_default(),
            "transactions": parsed.as_ref().map(|p| p.transactions.clone()).unwrap_or_default(),
            "warnings": parsed.as_ref().map(|p| p.warnings.clone()).unwrap_or_default(),
            "available_credit": parsed.as_ref().and_then(|p| p.available_credit),
            "points_balance": parsed.as_ref().and_then(|p| p.points_balance),
            "body_text_head": msg.body_text.chars().take(400).collect::<String>(),
        }));
    }
    json(&serde_json::json!({
        "protocol": outcome.protocol,
        "folder": outcome.folder,
        "uid_validity": outcome.uid_validity,
        "total_seen": outcome.total_seen,
        "messages": out,
    }))
}

/// 命中规则却解析不了的邮件，原文留到账本旁边的 `parse_failures/`。
///
/// 银行一改模板，"解析失败"这四个字对修模板毫无帮助，只有原文能说明新结构长什么样；
/// 反过来，没命中规则的邮件一封都不落盘，免得把整个收件箱抄到磁盘上。
/// 同名文件（同规则同 UID）直接覆盖，磁盘上始终每封一份。
fn archive_parse_failure(rule_id: i64, uid: &str, subject: &str, body: &str) -> Option<std::path::PathBuf> {
    if body.trim().is_empty() {
        return None;
    }
    let dir = storage::db_dir()?.join("parse_failures");
    std::fs::create_dir_all(&dir).ok()?;
    // 主题里可能有 / \ : 这类不能进文件名的字符，替掉但不删内容，认得出是哪封
    let slug: String = subject
        .chars()
        .take(40)
        .map(|c| match c {
            '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' | ' ' => '_',
            other => other,
        })
        .collect();
    let file = dir.join(format!("rule{}_{}_{}.html", rule_id, uid, slug));
    std::fs::write(&file, body).ok()?;
    Some(file)
}

/// 连接自检（IMAP/POP3/SMTP），同时可列出邮箱目录
pub fn ledger_test_connection(config_json: String, password: String, want_folders: bool) -> Result<String, String> {
    #[derive(serde::Deserialize)]
    struct Inline {
        #[serde(flatten)]
        rest: serde_json::Value,
    }
    let inline: Inline = from_json(&config_json, "邮箱配置")?;
    let mut merged = inline.rest;
    if let Some(obj) = merged.as_object_mut() {
        if obj.get("password").and_then(|p| p.as_str()).unwrap_or("").is_empty() {
            obj.insert("password".into(), serde_json::json!(password));
        }
    }
    let cfg: EmailAccountWire = from_json(&merged.to_string(), "邮箱配置")?;
    email_module::api::email_probe_json(json(&cfg)?, want_folders)
}

pub fn ledger_list_folders(config_json: String, password: String) -> Result<String, String> {
    ledger_test_connection(config_json, password, true)
}

// ── 待确认队列 ───────────────────────────────────────────────────────────────

pub fn ledger_list_pending(limit: i64) -> Result<String, String> {
    json(&storage::list_pending_email(false, if limit <= 0 { 100 } else { limit }).map_err(|e| e.to_string())?)
}

pub fn ledger_list_received_emails(limit: i64) -> Result<String, String> {
    json(&storage::list_pending_email(true, if limit <= 0 { 100 } else { limit }).map_err(|e| e.to_string())?)
}

pub fn ledger_email_transactions(email_id: i64) -> Result<String, String> {
    json(&storage::transactions_of_email(email_id).map_err(|e| e.to_string())?)
}

pub fn ledger_pending_count() -> Result<i64, String> {
    storage::count_pending_emails().map_err(|e| e.to_string())
}

/// 确认入账：body 可选地带上 account_id / category_id 覆盖
pub fn ledger_confirm_tx(tx_id: i64, patch_json: String) -> Result<(), String> {
    let tx = storage::get_transaction(tx_id)
        .map_err(|e| e.to_string())?
        .ok_or_else(|| "流水不存在".to_string())?;
    let patch: serde_json::Value = if patch_json.trim().is_empty() {
        serde_json::json!({})
    } else {
        from_json(&patch_json, "确认参数")?
    };
    let account_id = if i64_of(&patch, "account_id") > 0 {
        i64_of(&patch, "account_id")
    } else {
        tx.account_id
    };
    let category_id = if i64_of(&patch, "category_id") > 0 {
        i64_of(&patch, "category_id")
    } else {
        tx.category_id
    };
    let mut next = tx.clone();
    next.status = STATUS_POSTED.to_string();
    next.account_id = account_id;
    next.category_id = if category_id > 0 {
        category_id
    } else {
        default_category_id_for(&tx.direction)?
    };
    if !str_of(&patch, "merchant").is_empty() {
        next.merchant = str_of(&patch, "merchant");
    }
    if !str_of(&patch, "note").is_empty() {
        next.note = str_of(&patch, "note");
    }
    storage::update_transaction(&next).map_err(|e| e.to_string())?;
    storage::remember_merchant(&next.merchant, next.category_id).map_err(|e| e.to_string())?;
    Ok(())
}

pub fn ledger_confirm_all(email_id: i64, patch_json: String) -> Result<i64, String> {
    let txs = storage::transactions_of_email(email_id).map_err(|e| e.to_string())?;
    let mut count = 0i64;
    for tx in txs.iter().filter(|t| t.status == STATUS_PENDING) {
        ledger_confirm_tx(tx.id, patch_json.clone())?;
        count += 1;
    }
    if count > 0 {
        storage::mark_email_applied(email_id).map_err(|e| e.to_string())?;
    }
    Ok(count)
}

/// 忽略一封待确认邮件：流水标 ignored，邮件标 applied，不再打扰
pub fn ledger_ignore_email(email_id: i64) -> Result<i64, String> {
    let changed = storage::set_tx_status_by_email(email_id, STATUS_IGNORED).map_err(|e| e.to_string())?;
    storage::mark_email_applied(email_id).map_err(|e| e.to_string())?;
    Ok(changed)
}

pub fn ledger_ignore_tx(tx_id: i64) -> Result<(), String> {
    storage::set_tx_status(tx_id, STATUS_IGNORED).map_err(|e| e.to_string())
}

/// 删除一封邮件带来的全部流水（模板改版后清场用）
pub fn ledger_purge_email(email_id: i64) -> Result<i64, String> {
    let txs = storage::transactions_of_email(email_id).map_err(|e| e.to_string())?;
    let mut removed = 0i64;
    for tx in txs {
        if storage::delete_transaction(tx.id).unwrap_or(false) {
            removed += 1;
        }
    }
    Ok(removed)
}

fn default_category_id_for(direction: &str) -> Result<i64, String> {
    let wanted = parse_glue::default_category_name(direction);
    Ok(storage::list_categories(direction)
        .unwrap_or_default()
        .into_iter()
        .find(|c| c.name == wanted)
        .map(|c| c.id)
        .unwrap_or(0))
}


fn pick_bill_date(parsed_date: &str, received_at: &str) -> String {
    if parsed_date.len() >= 10 {
        return parsed_date.chars().take(10).collect();
    }
    if received_at.len() >= 10 {
        return received_at.chars().take(10).collect();
    }
    today()
}

/// 批量中止的收尾：日志必须从「进行中」变成「失败」，否则用户在日志页看到
/// 一条永远不结束的记录，既不知道失败也不知道该不该重试。
/// 刻意**不**推进 last_run_at：和「写库失败」同口径，让下一轮自动收信重试。
/// 收信一步：失败文案统一成「收信失败: …」，供日志与返回值复用
fn fetch_outcome(rule: &EmailRule, password: &str, limit: u64) -> Result<WireFetchOutcome, String> {
    let cfg = EmailAccountWire::of(rule, password);
    let cfg_json = json(&cfg)?;
    let text = email_module::api::email_fetch_json(cfg_json, limit)
        .map_err(|e| format!("收信失败: {}", e))?;
    from_json(&text, "收信结果")
}

fn abort_batch(
    log_id: i64,
    rule_id: i64,
    rule_name: &str,
    new_emails: i64,
    new_tx: i64,
    skipped: i64,
    reason: &str,
) -> String {
    let detail = format!("批量入账中止: {}", reason);
    finish_log(log_id, false, new_emails, new_tx, skipped, &detail);
    sw_warn!("[ledger] 规则《{}》(id={}) 中止: {}", rule_name, rule_id, reason);
    detail
}

fn finish_log(log_id: i64, ok: bool, new_emails: i64, new_tx: i64, skipped: i64, detail: &str) {
    if log_id > 0 {
        let _ = storage::finish_fetch_log(log_id, ok, new_emails, new_tx, skipped, detail);
    }
}

fn now_text() -> String {
    Local::now().format("%Y-%m-%d %H:%M:%S").to_string()
}

/// 预览时没有规则也要能跑解析，给一个"不限发件人/标题"的临时规则
fn default_rule_for_preview() -> EmailRule {
    EmailRule {
        id: 0,
        name: "预览".to_string(),
        ..EmailRule::default()
    }
}

// ── 调度与日志 ───────────────────────────────────────────────────────────────

pub fn ledger_scheduler_start() -> Result<(), String> {
    scheduler::set_enabled(true);
    scheduler::start()
}

pub fn ledger_scheduler_stop() -> Result<(), String> {
    scheduler::set_enabled(false);
    scheduler::stop()
}

pub fn ledger_scheduler_status() -> Result<String, String> {
    json(&scheduler::status())
}

pub fn ledger_get_logs(limit: i64) -> Result<String, String> {
    json(&storage::list_fetch_logs(limit).map_err(|e| e.to_string())?)
}

pub fn ledger_clear_logs() -> Result<(), String> {
    storage::clear_fetch_logs().map_err(|e| e.to_string())
}

pub fn ledger_version() -> String {
    "ledger_module 0.1.0（邮件协议：email_module ".to_string() + &email_module::api::email_version() + "）"
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 留档落在账本旁边、文件名认得出是哪封、没正文不建空文件
    #[test]
    fn parse_failure_archive_lands_next_to_the_ledger() {
        let dir = std::env::temp_dir().join(format!("sw_ledger_archive_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        storage::init_db(dir.join("ledger.db").to_str().unwrap()).unwrap();

        let file = archive_parse_failure(
            3,
            "8123",
            "招商银行信用卡/电子账单 2026-09",
            "<html>正文</html>",
        )
        .expect("留档要成功");
        assert_eq!(file.parent().unwrap(), dir.join("parse_failures").as_path());
        assert_eq!(
            file.file_name().unwrap().to_str().unwrap(),
            "rule3_8123_招商银行信用卡_电子账单_2026-09.html"
        );
        assert_eq!(std::fs::read_to_string(&file).unwrap(), "<html>正文</html>");
        assert!(
            archive_parse_failure(3, "8124", "空正文", "").is_none(),
            "没有正文就别在磁盘上留一个空文件"
        );

        storage::close_db();
        assert!(archive_parse_failure(3, "8125", "未初始化", "<b/>").is_none(), "账本没开就别写盘");
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// 建库要能被并发首次调用安全执行：节点上多个 ledger_* 请求会同时到达，
    /// 以前是 check-then-init，会撞 categories.name UNIQUE 并让 DB_CONN 被顶掉。
    #[test]
    fn init_db_is_safe_under_concurrent_first_calls() {
        let dir = std::env::temp_dir().join(format!("sw_ledger_conc_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let db = dir.join("ledger.db");
        let path = db.to_str().unwrap().to_string();

        let handles: Vec<_> = (0..8)
            .map(|_| {
                let p = path.clone();
                std::thread::spawn(move || storage::init_db(&p))
            })
            .collect();
        for h in handles {
            h.join().unwrap().expect("并发首次建库不得失败");
        }

        // 内置数据只应播种一份（INSERT OR IGNORE + 双检锁）
        let conn = rusqlite::Connection::open(&db).unwrap();
        let cash: i64 = conn
            .query_row("SELECT COUNT(*) FROM accounts WHERE name = '现金'", [], |r| r.get(0))
            .unwrap();
        assert_eq!(cash, 1, "默认账户只能有一份");
        let dup_categories: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM (SELECT name FROM categories GROUP BY name HAVING COUNT(*) > 1)",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(dup_categories, 0, "内置类别不得重复播种");
        drop(conn);

        storage::close_db();
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// P2-18：批量写入必须是单事务——一封账单的十几笔要么全进要么全不进。
    /// 半截入账最难收拾：用户看到几条、重试又撞去重键，账目永远对不上。
    #[test]
    fn batch_insert_is_atomic_and_dedups_within_batch() {
        let dir = std::env::temp_dir().join(format!("sw_ledger_batch_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        storage::init_db(dir.join("ledger.db").to_str().unwrap()).unwrap();

        let account = storage::list_accounts(false).unwrap()[0].id;
        let mk = |merchant: &str, amount: f64| crate::types::Transaction {
            id: 0,
            occurred_at: "2026-09-01 10:00:00".into(),
            bill_date: "2026-09-01".into(),
            direction: DIRECTION_EXPENSE.into(),
            amount,
            currency: "CNY".into(),
            account_id: account,
            category_id: 0,
            merchant: merchant.into(),
            note: String::new(),
            source: SOURCE_EMAIL.into(),
            rule_id: 1,
            email_uid: "u1".into(),
            dedup_key: format!("2026-09-01|{:.2}|{}|r0", amount, merchant),
            status: STATUS_PENDING.into(),
            created_at: String::new(),
            updated_at: String::new(),
            account_name: String::new(),
            category_name: String::new(),
            category_icon: String::new(),
            category_direction: String::new(),
        };

        let batch = vec![mk("咖啡", 18.0), mk("地铁", 6.0), mk("超市", 88.0)];
        let (inserted, deduped) = storage::insert_transactions(&batch).unwrap();
        assert_eq!((inserted, deduped), (3, 0));
        let filter = crate::storage::TxFilter::default();
        assert_eq!(storage::count_transactions(&filter).unwrap(), 3);

        // 同批再插一次：全被去重键挡下，不新增（单事务里的 INSERT OR IGNORE 仍生效）
        let (inserted, deduped) = storage::insert_transactions(&batch).unwrap();
        assert_eq!((inserted, deduped), (0, 3), "重复投递必须被去重键挡下");
        assert_eq!(storage::count_transactions(&filter).unwrap(), 3);

        // 空批不给事务，直接 (0,0)
        assert_eq!(storage::insert_transactions(&[]).unwrap(), (0, 0));

        storage::close_db();
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// P2-18：老库升级要能补上新索引（CREATE INDEX IF NOT EXISTS），
    /// 并顺手锁住 synchronous=NORMAL —— 它一旦退回 FULL，逐笔提交就会重新卡顿。
    #[test]
    fn init_creates_merchant_index_and_sets_normal_sync() {
        let dir = std::env::temp_dir().join(format!("sw_ledger_idx_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let db = dir.join("ledger.db");
        storage::init_db(db.to_str().unwrap()).unwrap();
        storage::close_db();

        let conn = rusqlite::Connection::open(&db).unwrap();
        let idx: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name='idx_merchant_hits'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(idx, 1, "商户 hits 索引必须在建库时创建");
        drop(conn);

        // early-return 分支（同路径二次 init）不能因索引已存在而失败
        storage::init_db(db.to_str().unwrap()).unwrap();
        // NORMAL = 1；FULL = 2。synchronous 是**每连接**设置，必须读 init_db 建立的那条连接
        let sync_mode: i64 = storage::with_db(|c| Ok(c.query_row("PRAGMA synchronous", [], |r| r.get(0))?))
            .unwrap();
        assert_eq!(sync_mode, 1, "WAL 下同步级别应为 NORMAL(1)");
        storage::close_db();
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// P2-19：批中失败时日志必须收尾成「失败」，不能停在「进行中」
    #[test]
    fn aborted_batch_finishes_the_fetch_log_as_failed() {
        let dir = std::env::temp_dir().join(format!("sw_ledger_abort_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        storage::init_db(dir.join("ledger.db").to_str().unwrap()).unwrap();

        let rule_id = storage::upsert_email_rule(&crate::types::EmailRule {
            name: "中止用例".to_string(),
            ..Default::default()
        })
        .unwrap();
        let log_id = storage::begin_fetch_log(rule_id).unwrap();
        assert!(log_id > 0);

        let detail = abort_batch(log_id, rule_id, "中止用例", 1, 2, 3, "数据库被锁");
        assert!(detail.contains("数据库被锁"), "detail = {detail}");

        let logs = storage::list_fetch_logs(10).unwrap();
        let log = logs.iter().find(|l| l.id == log_id).expect("日志必须存在");
        assert!(!log.ok, "失败必须记为失败");
        assert!(
            !log.finished_at.is_empty(),
            "finished_at 必须写上，否则前端一直显示进行中"
        );
        assert!(log.detail.contains("中止"), "detail = {}", log.detail);
        assert_eq!((log.new_emails, log.new_tx, log.skipped_tx), (1, 2, 3));

        // 失败不推进 last_run_at：下一轮自动收信还要重试
        let rule = storage::get_email_rule(rule_id).unwrap().unwrap();
        assert!(rule.last_run_at.is_empty(), "失败不该推进 last_run_at");

        storage::close_db();
        let _ = std::fs::remove_dir_all(&dir);
    }
}
