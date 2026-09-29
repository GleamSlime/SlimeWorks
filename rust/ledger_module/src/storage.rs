use anyhow::{anyhow, Context, Result};
use chrono::Local;
use lazy_static::lazy_static;
use rusqlite::{params, params_from_iter, Connection, Row};
use std::path::PathBuf;
use std::sync::Mutex;

use crate::types::*;

// 进程级单库连接：账本是"一个应用一份账"的定位，不做多库切换。
// 所有读写都过这把锁，SQLite 单写多读的特性下够用，也避免各处传 Connection。
lazy_static! {
    static ref DB_CONN: Mutex<Option<Connection>> = Mutex::new(None);
}

/// 列表查询用的联查形态：账户名/类别名一次带出
const TX_JOIN: &str = "SELECT t.id, t.occurred_at, t.bill_date, t.direction, t.amount, t.currency, t.account_id, \
     t.category_id, t.merchant, t.note, t.source, t.rule_id, t.email_uid, t.dedup_key, t.status, t.created_at, \
     t.updated_at, a.name, c.name, c.icon, c.direction \
     FROM transactions t \
     LEFT JOIN accounts a ON a.id = t.account_id \
     LEFT JOIN categories c ON c.id = t.category_id";

fn now_str() -> String {
    Local::now().format("%Y-%m-%d %H:%M:%S").to_string()
}

fn today_str() -> String {
    Local::now().format("%Y-%m-%d").to_string()
}

/// 建表 + 内置数据播种
pub fn init_db(db_path: &str) -> Result<()> {
    let path = PathBuf::from(db_path);
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).context("创建账本数据库目录失败")?;
    }
    let conn = Connection::open(path).context("打开账本数据库失败")?;
    conn.execute_batch(
        r#"
        PRAGMA journal_mode = WAL;

        CREATE TABLE IF NOT EXISTS accounts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            type TEXT NOT NULL DEFAULT 'credit_card',
            last4 TEXT NOT NULL DEFAULT '',
            currency TEXT NOT NULL DEFAULT 'CNY',
            credit_limit REAL NOT NULL DEFAULT 0,
            balance REAL NOT NULL DEFAULT 0,
            sort_order INTEGER NOT NULL DEFAULT 0,
            enabled INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS categories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            icon TEXT NOT NULL DEFAULT '',
            direction TEXT NOT NULL DEFAULT 'expense',
            sort_order INTEGER NOT NULL DEFAULT 0,
            is_builtin INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            occurred_at TEXT NOT NULL,
            bill_date TEXT NOT NULL,
            direction TEXT NOT NULL DEFAULT 'expense',
            amount REAL NOT NULL,
            currency TEXT NOT NULL DEFAULT 'CNY',
            account_id INTEGER NOT NULL DEFAULT 0,
            category_id INTEGER NOT NULL DEFAULT 0,
            merchant TEXT NOT NULL DEFAULT '',
            note TEXT NOT NULL DEFAULT '',
            source TEXT NOT NULL DEFAULT 'manual',
            rule_id INTEGER NOT NULL DEFAULT 0,
            email_uid TEXT NOT NULL DEFAULT '',
            dedup_key TEXT NOT NULL DEFAULT '',
            status TEXT NOT NULL DEFAULT 'posted',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        -- 邮件重复投递（同 UID 再取一次）必须撞这个唯一键，天然幂等
        CREATE UNIQUE INDEX IF NOT EXISTS idx_tx_dedup ON transactions(rule_id, email_uid, dedup_key)
            WHERE source = 'email';
        CREATE INDEX IF NOT EXISTS idx_tx_date ON transactions(bill_date);
        CREATE INDEX IF NOT EXISTS idx_tx_account ON transactions(account_id);
        CREATE INDEX IF NOT EXISTS idx_tx_category ON transactions(category_id);
        CREATE INDEX IF NOT EXISTS idx_tx_status ON transactions(status);

        CREATE TABLE IF NOT EXISTS email_rules (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            enabled INTEGER NOT NULL DEFAULT 1,
            protocol TEXT NOT NULL DEFAULT 'imap',
            host TEXT NOT NULL DEFAULT '',
            port INTEGER NOT NULL DEFAULT 0,
            use_ssl INTEGER NOT NULL DEFAULT 1,
            username TEXT NOT NULL DEFAULT '',
            mailbox TEXT NOT NULL DEFAULT 'INBOX',
            sender_match TEXT NOT NULL DEFAULT '',
            subject_match TEXT NOT NULL DEFAULT '',
            match_is_regex INTEGER NOT NULL DEFAULT 0,
            template_id TEXT NOT NULL DEFAULT 'cmb_daily_bill',
            template_config TEXT NOT NULL DEFAULT '{}',
            interval_minutes INTEGER NOT NULL DEFAULT 0,
            daily_time TEXT NOT NULL DEFAULT '',
            default_account_id INTEGER NOT NULL DEFAULT 0,
            auto_apply INTEGER NOT NULL DEFAULT 0,
            accept_invalid_certs INTEGER NOT NULL DEFAULT 0,
            last_run_at TEXT NOT NULL DEFAULT '',
            last_result TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL
        );
        -- 密码不落这张表：由 Dart 侧 flutter_secure_storage 保管，运行期内存注入
        CREATE TABLE IF NOT EXISTS email_rule_secrets (
            rule_id INTEGER PRIMARY KEY,
            secret_ref TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS emails (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            rule_id INTEGER NOT NULL,
            message_uid TEXT NOT NULL,
            message_id TEXT NOT NULL DEFAULT '',
            from_addr TEXT NOT NULL DEFAULT '',
            subject TEXT NOT NULL DEFAULT '',
            received_at TEXT NOT NULL DEFAULT '',
            bill_date TEXT NOT NULL DEFAULT '',
            fetched_at TEXT NOT NULL,
            tx_count INTEGER NOT NULL DEFAULT 0,
            applied INTEGER NOT NULL DEFAULT 0,
            available_credit REAL,
            points_balance INTEGER,
            warnings_json TEXT NOT NULL DEFAULT '[]',
            html_len INTEGER NOT NULL DEFAULT 0
        );
        CREATE UNIQUE INDEX IF NOT EXISTS idx_email_uid ON emails(rule_id, message_uid);

        CREATE TABLE IF NOT EXISTS fetch_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            rule_id INTEGER NOT NULL,
            started_at TEXT NOT NULL,
            finished_at TEXT NOT NULL DEFAULT '',
            ok INTEGER NOT NULL DEFAULT 0,
            new_emails INTEGER NOT NULL DEFAULT 0,
            new_tx INTEGER NOT NULL DEFAULT 0,
            skipped_tx INTEGER NOT NULL DEFAULT 0,
            detail TEXT NOT NULL DEFAULT ''
        );

        -- 商户 → 类别 的记账习惯记忆：确认一次后同类商户自动归类
        CREATE TABLE IF NOT EXISTS merchant_memory (
            merchant_key TEXT PRIMARY KEY,
            category_id INTEGER NOT NULL,
            hits INTEGER NOT NULL DEFAULT 1,
            updated_at TEXT NOT NULL
        );
        "#,
    )
    .context("初始化账本表结构失败")?;

    seed_builtins(&conn)?;

    let mut guard = DB_CONN.lock().unwrap();
    *guard = Some(conn);
    Ok(())
}

/// 首次建库播种内置类别与一个默认账户；已有数据时不动用户改过的内容
fn seed_builtins(conn: &Connection) -> Result<()> {
    let category_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM categories", [], |r| r.get(0))
        .unwrap_or(0);
    if category_count == 0 {
        for (idx, (name, icon, direction)) in BUILTIN_CATEGORIES.iter().enumerate() {
            conn.execute(
                "INSERT INTO categories (name, icon, direction, sort_order, is_builtin) VALUES (?1, ?2, ?3, ?4, 1)",
                params![name, icon, direction, idx as i64],
            )?;
        }
    } else {
        // 升级路径：新版本加了内置类别时补插，按名字幂等
        for (idx, (name, icon, direction)) in BUILTIN_CATEGORIES.iter().enumerate() {
            conn.execute(
                "INSERT OR IGNORE INTO categories (name, icon, direction, sort_order, is_builtin) VALUES (?1, ?2, ?3, ?4, 1)",
                params![name, icon, direction, idx as i64],
            )?;
        }
    }

    let account_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM accounts", [], |r| r.get(0))
        .unwrap_or(0);
    if account_count == 0 {
        conn.execute(
            "INSERT INTO accounts (name, type, last4, currency, credit_limit, balance, sort_order, enabled, created_at) \
             VALUES ('现金', 'cash', '', 'CNY', 0, 0, 10, 1, ?1)",
            params![now_str()],
        )?;
    }
    Ok(())
}

/// (名称, 图标标识, 方向)。图标标识由 Dart 侧映射到 StrokeIcons。
const BUILTIN_CATEGORIES: &[(&str, &str, &str)] = &[
    ("餐饮美食", "restaurant", DIRECTION_EXPENSE),
    ("交通出行", "bus", DIRECTION_EXPENSE),
    ("购物消费", "shoppingCart", DIRECTION_EXPENSE),
    ("休闲娱乐", "game", DIRECTION_EXPENSE),
    ("居家缴费", "home", DIRECTION_EXPENSE),
    ("医疗健康", "firstAid", DIRECTION_EXPENSE),
    ("学习进修", "book", DIRECTION_EXPENSE),
    ("住房物业", "building", DIRECTION_EXPENSE),
    ("人情往来", "gift", DIRECTION_EXPENSE),
    ("宠物", "paw", DIRECTION_EXPENSE),
    ("美容美发", "scissors", DIRECTION_EXPENSE),
    ("旅行", "plane", DIRECTION_EXPENSE),
    ("通讯网络", "deviceSimChat", DIRECTION_EXPENSE),
    ("日用百货", "deviceDesktop", DIRECTION_EXPENSE),
    ("其他支出", "dots", DIRECTION_EXPENSE),
    ("工资收入", "money", DIRECTION_INCOME),
    ("奖金补贴", "giftCard", DIRECTION_INCOME),
    ("理财收益", "chartLine", DIRECTION_INCOME),
    ("报销款", "receipt", DIRECTION_INCOME),
    ("退款退货", "refund", DIRECTION_INCOME),
    ("其他收入", "dots", DIRECTION_INCOME),
    ("转账", "exchange", DIRECTION_EXPENSE),
];

pub fn is_ready() -> bool {
    DB_CONN.lock().unwrap().is_some()
}

pub fn close_db() {
    let mut guard = DB_CONN.lock().unwrap();
    *guard = None;
}

/// 取连接引用；未初始化返回错误而不是 panic
fn with_db<T>(f: impl FnOnce(&Connection) -> Result<T>) -> Result<T> {
    let guard = DB_CONN.lock().unwrap();
    let conn = guard.as_ref().context("账本数据库未初始化")?;
    f(conn)
}

fn map_account(row: &Row) -> rusqlite::Result<Account> {
    Ok(Account {
        id: row.get(0)?,
        name: row.get(1)?,
        account_type: row.get(2)?,
        last4: row.get(3)?,
        currency: row.get(4)?,
        credit_limit: row.get(5)?,
        balance: row.get(6)?,
        sort_order: row.get(7)?,
        enabled: row.get::<_, i64>(8)? != 0,
        created_at: row.get(9)?,
    })
}

fn map_category(row: &Row) -> rusqlite::Result<Category> {
    Ok(Category {
        id: row.get(0)?,
        name: row.get(1)?,
        icon: row.get(2)?,
        direction: row.get(3)?,
        sort_order: row.get(4)?,
        is_builtin: row.get::<_, i64>(5)? != 0,
    })
}

fn map_transaction(row: &Row) -> rusqlite::Result<Transaction> {
    Ok(Transaction {
        id: row.get(0)?,
        occurred_at: row.get(1)?,
        bill_date: row.get(2)?,
        direction: row.get(3)?,
        amount: row.get(4)?,
        currency: row.get(5)?,
        account_id: row.get(6)?,
        category_id: row.get(7)?,
        merchant: row.get(8)?,
        note: row.get(9)?,
        source: row.get(10)?,
        rule_id: row.get(11)?,
        email_uid: row.get(12)?,
        dedup_key: row.get(13)?,
        status: row.get(14)?,
        created_at: row.get(15)?,
        updated_at: row.get(16)?,
        account_name: row.get(17)?,
        category_name: row.get(18)?,
        category_icon: row.get(19)?,
        category_direction: row.get(20)?,
    })
}

fn map_rule(row: &Row) -> rusqlite::Result<EmailRule> {
    Ok(EmailRule {
        id: row.get(0)?,
        name: row.get(1)?,
        enabled: row.get::<_, i64>(2)? != 0,
        protocol: row.get(3)?,
        host: row.get(4)?,
        port: row.get::<_, i64>(5)? as u16,
        use_ssl: row.get::<_, i64>(6)? != 0,
        username: row.get(7)?,
        mailbox: row.get(8)?,
        sender_match: row.get(9)?,
        subject_match: row.get(10)?,
        match_is_regex: row.get::<_, i64>(11)? != 0,
        template_id: row.get(12)?,
        template_config: row.get(13)?,
        interval_minutes: row.get::<_, i64>(14)? as u64,
        daily_time: row.get(15)?,
        default_account_id: row.get(16)?,
        auto_apply: row.get::<_, i64>(17)? != 0,
        accept_invalid_certs: row.get::<_, i64>(18)? != 0,
        last_run_at: row.get(19)?,
        last_result: row.get(20)?,
        created_at: row.get(21)?,
    })
}

fn map_pending(row: &Row) -> rusqlite::Result<PendingEmail> {
    let warnings_json: String = row.get(11)?;
    let warnings: Vec<String> =
        serde_json::from_str(&warnings_json).unwrap_or_default();
    Ok(PendingEmail {
        id: row.get(0)?,
        rule_id: row.get(1)?,
        rule_name: row.get(2)?,
        message_uid: row.get(3)?,
        message_id: row.get(4)?,
        from_addr: row.get(5)?,
        subject: row.get(6)?,
        received_at: row.get(7)?,
        bill_date: row.get(8)?,
        tx_count: row.get(9)?,
        applied: row.get::<_, i64>(10)? != 0,
        available_credit: row.get(12)?,
        points_balance: row.get(13)?,
        warnings,
        html_len: row.get(14)?,
    })
}

// ── 账户 ─────────────────────────────────────────────────────────────────────

pub fn list_accounts(enabled_only: bool) -> Result<Vec<Account>> {
    with_db(|conn| {
        let sql = format!(
            "SELECT id, name, type, last4, currency, credit_limit, balance, sort_order, enabled, created_at \
             FROM accounts {} ORDER BY sort_order ASC, id ASC",
            if enabled_only { "WHERE enabled = 1" } else { "" }
        );
        let mut stmt = conn.prepare(&sql)?;
        let rows = stmt.query_map([], map_account)?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    })
}

pub fn get_account(id: i64) -> Result<Account> {
    with_db(|conn| {
        conn.query_row(
            "SELECT id, name, type, last4, currency, credit_limit, balance, sort_order, enabled, created_at FROM accounts WHERE id = ?1",
            params![id],
            map_account,
        )
        .map_err(Into::into)
    })
}

pub fn find_account_by_last4(last4: &str) -> Result<Option<Account>> {
    if last4.is_empty() {
        return Ok(None);
    }
    with_db(|conn| {
        let mut stmt =
            conn.prepare("SELECT id, name, type, last4, currency, credit_limit, balance, sort_order, enabled, created_at FROM accounts WHERE last4 = ?1 LIMIT 1")?;
        let mut rows = stmt.query_map(params![last4], map_account)?;
        match rows.next() {
            Some(Ok(a)) => Ok(Some(a)),
            _ => Ok(None),
        }
    })
}

/// 写入；id 为 0 表示新增
pub fn upsert_account(account: &Account) -> Result<i64> {
    with_db(|conn| {
        if account.id > 0 {
            conn.execute(
                "UPDATE accounts SET name=?1, type=?2, last4=?3, currency=?4, credit_limit=?5, balance=?6, sort_order=?7, enabled=?8 WHERE id=?9",
                params![
                    account.name,
                    account.account_type,
                    account.last4,
                    account.currency,
                    account.credit_limit,
                    account.balance,
                    account.sort_order,
                    account.enabled as i64,
                    account.id
                ],
            )?;
            Ok(account.id)
        } else {
            conn.execute(
                "INSERT INTO accounts (name, type, last4, currency, credit_limit, balance, sort_order, enabled, created_at) VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9)",
                params![
                    account.name,
                    account.account_type,
                    account.last4,
                    account.currency,
                    account.credit_limit,
                    account.balance,
                    account.sort_order,
                    account.enabled as i64,
                    now_str()
                ],
            )?;
            Ok(conn.last_insert_rowid())
        }
    })
}

/// 有流水的账户只禁用不删除，历史账目不能因为删账户而失真
pub fn delete_account(id: i64) -> Result<String> {
    with_db(|conn| {
        let used: i64 = conn.query_row(
            "SELECT COUNT(*) FROM transactions WHERE account_id = ?1",
            params![id],
            |r| r.get(0),
        )?;
        if used > 0 {
            conn.execute("UPDATE accounts SET enabled = 0 WHERE id = ?1", params![id])?;
            Ok(format!("该账户已有 {} 笔流水，已改为停用（保留历史账目）", used))
        } else {
            conn.execute("DELETE FROM accounts WHERE id = ?1", params![id])?;
            Ok("账户已删除".to_string())
        }
    })
}

// ── 类别 ─────────────────────────────────────────────────────────────────────

pub fn list_categories(direction: &str) -> Result<Vec<Category>> {
    with_db(|conn| {
        let sql = if direction.is_empty() {
            "SELECT id, name, icon, direction, sort_order, is_builtin FROM categories ORDER BY direction DESC, sort_order ASC, id ASC".to_string()
        } else {
            "SELECT id, name, icon, direction, sort_order, is_builtin FROM categories WHERE direction = ?1 ORDER BY sort_order ASC, id ASC".to_string()
        };
        let mut stmt = conn.prepare(&sql)?;
        let rows = if direction.is_empty() {
            stmt.query_map([], map_category)?
        } else {
            stmt.query_map(params![direction], map_category)?
        };
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    })
}

pub fn get_category(id: i64) -> Result<Option<Category>> {
    with_db(|conn| {
        let mut stmt = conn.prepare(
            "SELECT id, name, icon, direction, sort_order, is_builtin FROM categories WHERE id = ?1",
        )?;
        let mut rows = stmt.query_map(params![id], map_category)?;
        Ok(rows.next().and_then(|r| r.ok()))
    })
}

/// 名称唯一：同名视为更新该类别而不是新增，避免统计里出现两个"餐饮"
pub fn upsert_category(category: &Category) -> Result<i64> {
    with_db(|conn| {
        let existing: Option<i64> = conn
            .query_row(
                "SELECT id FROM categories WHERE name = ?1",
                params![category.name],
                |r| r.get(0),
            )
            .ok();
        if let Some(id) = existing {
            conn.execute(
                "UPDATE categories SET icon=?1, direction=?2, sort_order=?3 WHERE id=?4",
                params![category.icon, category.direction, category.sort_order, id],
            )?;
            Ok(id)
        } else {
            conn.execute(
                "INSERT INTO categories (name, icon, direction, sort_order, is_builtin) VALUES (?1,?2,?3,?4,0)",
                params![category.name, category.icon, category.direction, category.sort_order],
            )?;
            Ok(conn.last_insert_rowid())
        }
    })
}

pub fn delete_category(id: i64) -> Result<String> {
    with_db(|conn| {
        let cat: Option<Category> = conn
            .query_row(
                "SELECT id, name, icon, direction, sort_order, is_builtin FROM categories WHERE id = ?1",
                params![id],
                map_category,
            )
            .ok();
        let cat = cat.context("类别不存在")?;
        if cat.is_builtin {
            return Err(anyhow!("内置类别不可删除"));
        }
        let used: i64 = conn.query_row(
            "SELECT COUNT(*) FROM transactions WHERE category_id = ?1",
            params![id],
            |r| r.get(0),
        )?;
        if used > 0 {
            let fallback: i64 = conn
                .query_row(
                    "SELECT id FROM categories WHERE name = '其他支出'",
                    [],
                    |r| r.get(0),
                )
                .unwrap_or(0);
            conn.execute(
                "UPDATE transactions SET category_id = ?1 WHERE category_id = ?2",
                params![fallback, id],
            )?;
        }
        conn.execute("DELETE FROM categories WHERE id = ?1", params![id])?;
        conn.execute(
            "DELETE FROM merchant_memory WHERE category_id = ?1",
            params![id],
        )?;
        Ok(format!("类别已删除（{} 笔流水归入其他支出）", used))
    })
}

/// 类别名 → id，找不到返回"其他支出"，再找不到返回 0
pub fn resolve_category_id(conn: &Connection, name: &str) -> i64 {
    let by_name: Option<i64> = conn
        .query_row(
            "SELECT id FROM categories WHERE name = ?1",
            params![name],
            |r| r.get(0),
        )
        .ok();
    by_name
        .or_else(|| {
            conn.query_row(
                "SELECT id FROM categories WHERE name = '其他支出'",
                [],
                |r| r.get(0),
            )
            .ok()
        })
        .unwrap_or(0)
}

// ── 流水 ─────────────────────────────────────────────────────────────────────

/// 邮件流水的去重键：同封邮件里同一天同金额同摘要视为同一笔
pub fn dedup_key_of(bill_date: &str, amount: f64, merchant: &str, note: &str) -> String {
    format!(
        "{}|{:.2}|{}|{}",
        bill_date,
        amount,
        merchant.trim(),
        note.trim()
    )
}

/// 插入一笔流水。返回新行 id；0 表示被去重键挡下（没有写入）。
pub fn insert_transaction(tx: &Transaction) -> Result<i64> {
    with_db(|conn| {
        let mut tx = tx.clone();
        if tx.dedup_key.is_empty() {
            tx.dedup_key = dedup_key_of(&tx.bill_date, tx.amount, &tx.merchant, &tx.note);
        }
        if tx.occurred_at.is_empty() {
            tx.occurred_at = format!("{} 00:00:00", tx.bill_date);
        }
        if tx.bill_date.is_empty() {
            tx.bill_date = tx.occurred_at.chars().take(10).collect();
        }
        if tx.category_id == 0 && !tx.merchant.is_empty() {
            // 没指定类别时按历史习惯猜一次，猜不中就落"其他支出"
            let guessed = lookup_merchant_category(conn, &tx.merchant)?.unwrap_or_default();
            tx.category_id = if guessed > 0 {
                guessed
            } else {
                resolve_category_id(conn, "其他支出")
            };
        }
        let stamp = now_str();
        let affected = conn.execute(
            "INSERT OR IGNORE INTO transactions \
             (occurred_at, bill_date, direction, amount, currency, account_id, category_id, merchant, note, \
              source, rule_id, email_uid, dedup_key, status, created_at, updated_at) \
             VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16)",
            params![
                tx.occurred_at,
                tx.bill_date,
                tx.direction,
                round2(tx.amount),
                tx.currency,
                tx.account_id,
                tx.category_id,
                tx.merchant,
                tx.note,
                tx.source,
                tx.rule_id,
                tx.email_uid,
                tx.dedup_key,
                tx.status,
                stamp,
                stamp
            ],
        )?;
        if affected > 0 {
            Ok(conn.last_insert_rowid())
        } else {
            Ok(0)
        }
    })
}

/// 记账习惯记忆：按商户名取类别（先精确后包含）
fn lookup_merchant_category(conn: &Connection, merchant: &str) -> Result<Option<i64>> {
    let exact: Option<i64> = conn
        .query_row(
            "SELECT category_id FROM merchant_memory WHERE merchant_key = ?1",
            params![merchant],
            |r| r.get(0),
        )
        .ok();
    if exact.is_some() {
        return Ok(exact);
    }
    let mut stmt = conn.prepare(
        "SELECT merchant_key, category_id FROM merchant_memory WHERE length(merchant_key) >= 4 ORDER BY hits DESC LIMIT 50",
    )?;
    let rows = stmt.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?)))?;
    for row in rows {
        let (key, cid) = row?;
        if merchant.contains(&key) || key.contains(merchant) {
            return Ok(Some(cid));
        }
    }
    Ok(None)
}

/// 用户在待确认队列里改了类别，就记住这个商户的归类
pub fn remember_merchant(merchant: &str, category_id: i64) -> Result<()> {
    let key = merchant.trim();
    if key.is_empty() || category_id <= 0 {
        return Ok(());
    }
    with_db(|conn| {
        conn.execute(
            "INSERT INTO merchant_memory (merchant_key, category_id, hits, updated_at) VALUES (?1, ?2, 1, ?3) \
             ON CONFLICT(merchant_key) DO UPDATE SET category_id = excluded.category_id, hits = hits + 1, updated_at = excluded.updated_at",
            params![key, category_id, now_str()],
        )?;
        Ok(())
    })
}

pub fn list_merchant_memory() -> Result<Vec<(String, i64)>> {
    with_db(|conn| {
        let mut stmt =
            conn.prepare("SELECT merchant_key, category_id FROM merchant_memory ORDER BY hits DESC LIMIT 200")?;
        let rows = stmt.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?)))?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    })
}

pub fn forget_merchant(merchant_key: &str) -> Result<()> {
    with_db(|conn| {
        conn.execute(
            "DELETE FROM merchant_memory WHERE merchant_key = ?1",
            params![merchant_key],
        )?;
        Ok(())
    })
}

pub fn update_transaction(tx: &Transaction) -> Result<()> {
    with_db(|conn| {
        conn.execute(
            "UPDATE transactions SET occurred_at=?1, bill_date=?2, direction=?3, amount=?4, currency=?5, \
             account_id=?6, category_id=?7, merchant=?8, note=?9, status=?10, updated_at=?11 WHERE id=?12",
            params![
                tx.occurred_at,
                if tx.bill_date.is_empty() {
                    tx.occurred_at.chars().take(10).collect::<String>()
                } else {
                    tx.bill_date.clone()
                },
                tx.direction,
                round2(tx.amount),
                tx.currency,
                tx.account_id,
                tx.category_id,
                tx.merchant,
                tx.note,
                tx.status,
                now_str(),
                tx.id
            ],
        )?;
        Ok(())
    })
}

pub fn delete_transaction(id: i64) -> Result<bool> {
    with_db(|conn| Ok(conn.execute("DELETE FROM transactions WHERE id = ?1", params![id])? > 0))
}

pub fn get_transaction(id: i64) -> Result<Option<Transaction>> {
    with_db(|conn| {
        let mut stmt = conn.prepare(&format!("{} WHERE t.id = ?1", TX_JOIN))?;
        let mut rows = stmt.query_map(params![id], map_transaction)?;
        Ok(rows.next().and_then(|r| r.ok()))
    })
}

/// 列表查询条件：时间区间 + 各维过滤 + 关键词
#[derive(Debug, Clone, Default)]
pub struct TxFilter {
    pub start_date: String,
    pub end_date: String,
    pub direction: String,
    pub account_id: i64,
    pub category_id: i64,
    pub source: String,
    pub status: String,
    pub keyword: String,
    pub limit: i64,
    pub offset: i64,
}

impl TxFilter {
    fn build(&self) -> (String, Vec<Box<dyn rusqlite::ToSql>>) {
        let mut where_parts: Vec<String> = Vec::new();
        let mut args: Vec<Box<dyn rusqlite::ToSql>> = Vec::new();
        if !self.start_date.is_empty() {
            where_parts.push(format!("t.bill_date >= ?{}", args.len() + 1));
            args.push(Box::new(self.start_date.clone()));
        }
        if !self.end_date.is_empty() {
            where_parts.push(format!("t.bill_date <= ?{}", args.len() + 1));
            args.push(Box::new(self.end_date.clone()));
        }
        if !self.direction.is_empty() {
            where_parts.push(format!("t.direction = ?{}", args.len() + 1));
            args.push(Box::new(self.direction.clone()));
        }
        if self.account_id > 0 {
            where_parts.push(format!("t.account_id = ?{}", args.len() + 1));
            args.push(Box::new(self.account_id));
        }
        if self.category_id > 0 {
            where_parts.push(format!("t.category_id = ?{}", args.len() + 1));
            args.push(Box::new(self.category_id));
        }
        if !self.source.is_empty() {
            where_parts.push(format!("t.source = ?{}", args.len() + 1));
            args.push(Box::new(self.source.clone()));
        }
        if !self.status.is_empty() {
            where_parts.push(format!("t.status = ?{}", args.len() + 1));
            args.push(Box::new(self.status.clone()));
        }
        if !self.keyword.is_empty() {
            where_parts.push(format!(
                "(t.merchant LIKE ?{n} OR t.note LIKE ?{n})",
                n = args.len() + 1
            ));
            args.push(Box::new(format!("%{}%", self.keyword)));
        }
        let clause = if where_parts.is_empty() {
            String::new()
        } else {
            format!(" WHERE {}", where_parts.join(" AND "))
        };
        (clause, args)
    }
}

pub fn list_transactions(filter: &TxFilter) -> Result<Vec<Transaction>> {
    with_db(|conn| {
        let (clause, args) = filter.build();
        let limit = if filter.limit <= 0 { 500 } else { filter.limit };
        let sql = format!(
            "{}{} ORDER BY t.bill_date DESC, t.occurred_at DESC, t.id DESC LIMIT ?{} OFFSET ?{}",
            TX_JOIN,
            clause,
            args.len() + 1,
            args.len() + 2
        );
        args_iter_to_query(&conn, &sql, args, limit, filter.offset)
    })
}

/// rusqlite 要求参数切片；把拥有所有权的 Box 列表摊成引用切片
fn args_iter_to_query(
    conn: &Connection,
    sql: &str,
    args: Vec<Box<dyn rusqlite::ToSql>>,
    limit: i64,
    offset: i64,
) -> Result<Vec<Transaction>> {
    let refs: Vec<&dyn rusqlite::ToSql> = args.iter().map(|a| a.as_ref()).collect();
    let mut stmt = conn.prepare(sql)?;
    let mut all = refs;
    all.push(&limit);
    all.push(&offset);
    let rows = stmt.query_map(params_from_iter(all), map_transaction)?;
    Ok(rows.collect::<Result<Vec<_>, _>>()?)
}

pub fn count_transactions(filter: &TxFilter) -> Result<i64> {
    with_db(|conn| {
        let (clause, args) = filter.build();
        let sql = format!("SELECT COUNT(*) FROM transactions t{}", clause);
        let refs: Vec<&dyn rusqlite::ToSql> = args.iter().map(|a| a.as_ref()).collect();
        Ok(conn.query_row(&sql, params_from_iter(refs), |r| r.get(0))?)
    })
}

/// 聚合口径固定为"已入账"，待确认的记录不该污染余额视图
fn append_posted(clause: &str) -> String {
    if clause.is_empty() {
        " WHERE t.status = 'posted'".to_string()
    } else if clause.contains("t.status") {
        clause.to_string()
    } else {
        format!("{} AND t.status = 'posted'", clause)
    }
}

/// 按天分组汇总，供流水页"日期头 + 当日小计"
pub fn stats_by_day(filter: &TxFilter) -> Result<Vec<serde_json::Value>> {
    with_db(|conn| {
        let (clause, args) = filter.build();
        let sql = format!(
            "SELECT t.bill_date, \
             COALESCE(SUM(CASE WHEN t.direction = 'income' THEN t.amount ELSE 0 END), 0) AS income, \
             COALESCE(SUM(CASE WHEN t.direction = 'expense' THEN t.amount ELSE 0 END), 0) AS expense, \
             COUNT(*) AS cnt \
             FROM transactions t{} GROUP BY t.bill_date ORDER BY t.bill_date DESC",
            append_posted(&clause)
        );
        let refs: Vec<&dyn rusqlite::ToSql> = args.iter().map(|a| a.as_ref()).collect();
        let mut stmt = conn.prepare(&sql)?;
        let rows = stmt.query_map(params_from_iter(refs), |r| {
            Ok(serde_json::json!({
                "bill_date": r.get::<_, String>(0)?,
                "income": round2(r.get::<_, f64>(1)?),
                "expense": round2(r.get::<_, f64>(2)?),
                "count": r.get::<_, i64>(3)?,
            }))
        })?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    })
}

/// 按类别汇总（含占比所需的分母）
pub fn stats_by_category(filter: &TxFilter) -> Result<Vec<serde_json::Value>> {
    with_db(|conn| {
        let (clause, args) = filter.build();
        let sql = format!(
            "SELECT c.id, c.name, c.icon, t.direction, \
             COALESCE(SUM(t.amount), 0) AS total, COUNT(*) AS cnt \
             FROM transactions t LEFT JOIN categories c ON c.id = t.category_id{} \
             GROUP BY t.category_id, t.direction ORDER BY total DESC",
            append_posted(&clause)
        );
        let refs: Vec<&dyn rusqlite::ToSql> = args.iter().map(|a| a.as_ref()).collect();
        let mut stmt = conn.prepare(&sql)?;
        let rows = stmt.query_map(params_from_iter(refs), |r| {
            Ok(serde_json::json!({
                "category_id": r.get::<_, Option<i64>>(0)?.unwrap_or(0),
                "category_name": r.get::<_, Option<String>>(1)?.unwrap_or_else(|| "未归类".to_string()),
                "category_icon": r.get::<_, Option<String>>(2)?.unwrap_or_default(),
                "direction": r.get::<_, String>(3)?,
                "total": round2(r.get::<_, f64>(4)?),
                "count": r.get::<_, i64>(5)?,
            }))
        })?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    })
}

/// 按商户汇总，用于"最大几笔消费"
pub fn stats_by_merchant(filter: &TxFilter, top: i64) -> Result<Vec<serde_json::Value>> {
    with_db(|conn| {
        let (clause, args) = filter.build();
        let extra = " AND t.merchant <> '' AND t.direction = 'expense'";
        let limit = if top <= 0 { 10 } else { top };
        let sql = format!(
            "SELECT t.merchant, COALESCE(SUM(t.amount), 0) AS total, COUNT(*) AS cnt, MAX(t.bill_date) AS last_date \
             FROM transactions t{}{} \
             GROUP BY t.merchant ORDER BY total DESC LIMIT ?{}",
            append_posted(&clause),
            extra,
            args.len() + 1
        );
        let mut refs: Vec<&dyn rusqlite::ToSql> = args.iter().map(|a| a.as_ref()).collect();
        refs.push(&limit);
        let mut stmt = conn.prepare(&sql)?;
        let rows = stmt.query_map(params_from_iter(refs), |r| {
            Ok(serde_json::json!({
                "merchant": r.get::<_, String>(0)?,
                "total": round2(r.get::<_, f64>(1)?),
                "count": r.get::<_, i64>(2)?,
                "last_date": r.get::<_, String>(3)?,
            }))
        })?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    })
}

/// 区间收支合计
pub fn stats_summary(filter: &TxFilter) -> Result<serde_json::Value> {
    with_db(|conn| {
        let (clause, args) = filter.build();
        let sql = format!(
            "SELECT COALESCE(SUM(CASE WHEN t.direction = 'income' THEN t.amount ELSE 0 END), 0), \
             COALESCE(SUM(CASE WHEN t.direction = 'expense' THEN t.amount ELSE 0 END), 0), \
             COUNT(*), MIN(t.bill_date), MAX(t.bill_date) \
             FROM transactions t{}",
            append_posted(&clause)
        );
        let refs: Vec<&dyn rusqlite::ToSql> = args.iter().map(|a| a.as_ref()).collect();
        let (income, expense, count, min_d, max_d) = conn.query_row(&sql, params_from_iter(refs), |r| {
            Ok((
                r.get::<_, f64>(0)?,
                r.get::<_, f64>(1)?,
                r.get::<_, i64>(2)?,
                r.get::<_, Option<String>>(3)?,
                r.get::<_, Option<String>>(4)?,
            ))
        })?;

        // 本月合计：页头卡片固定展示，放在同一次连接里查，省一次往返
        let month: String = today_str().chars().take(7).collect();
        let (m_income, m_expense) = conn.query_row(
            "SELECT COALESCE(SUM(CASE WHEN direction = 'income' THEN amount ELSE 0 END), 0), \
             COALESCE(SUM(CASE WHEN direction = 'expense' THEN amount ELSE 0 END), 0) \
             FROM transactions WHERE status = 'posted' AND bill_date BETWEEN ?1 AND ?2",
            params![format!("{}-01", month), month_last_day(&month)],
            |r| Ok((r.get::<_, f64>(0)?, r.get::<_, f64>(1)?)),
        )?;
        Ok(serde_json::json!({
            "income": round2(income),
            "expense": round2(expense),
            "net": round2(income - expense),
            "count": count,
            "min_date": min_d.unwrap_or_default(),
            "max_date": max_d.unwrap_or_default(),
            "month": month,
            "month_income": round2(m_income),
            "month_expense": round2(m_expense),
            "month_net": round2(m_income - m_expense),
        }))
    })
}

/// 逐月收支，供趋势柱/折线
pub fn stats_by_month(months: i64) -> Result<Vec<serde_json::Value>> {
    let span = if months <= 0 { 12 } else { months } as usize;
    let month = Local::now().format("%Y-%m").to_string();
    with_db(|conn| {
        let mut stmt = conn.prepare(
            "SELECT substr(bill_date, 1, 7) AS m, \
             COALESCE(SUM(CASE WHEN direction = 'income' THEN amount ELSE 0 END), 0), \
             COALESCE(SUM(CASE WHEN direction = 'expense' THEN amount ELSE 0 END), 0), COUNT(*) \
             FROM transactions WHERE status = 'posted' AND substr(bill_date, 1, 7) <= ?1 \
             GROUP BY m ORDER BY m DESC LIMIT ?2",
        )?;
        let rows = stmt.query_map(params![month, span as i64], |r| {
            Ok(serde_json::json!({
                "month": r.get::<_, String>(0)?,
                "income": round2(r.get::<_, f64>(1)?),
                "expense": round2(r.get::<_, f64>(2)?),
                "net": round2(r.get::<_, f64>(1)? - r.get::<_, f64>(2)?),
                "count": r.get::<_, i64>(3)?,
            }))
        })?;
        let mut out = rows.collect::<Result<Vec<_>, _>>()?;
        out.reverse();
        Ok(out)
    })
}

fn month_last_day(month: &str) -> String {
    // month 形如 2026-09；只用于 BETWEEN 上界，闰年/月末交给日期加减
    let y: i32 = month.chars().take(4).collect::<String>().parse().unwrap_or(1970);
    let m: u32 = month[5..].parse().unwrap_or(1);
    let (ny, nm) = if m == 12 { (y + 1, 1) } else { (y, m + 1) };
    let next_first = chrono::NaiveDate::from_ymd_opt(ny, nm, 1)
        .unwrap_or_else(|| chrono::NaiveDate::from_ymd_opt(1970, 1, 1).unwrap());
    let last = next_first - chrono::Duration::days(1);
    last.format("%Y-%m-%d").to_string()
}

/// 软重复提示：手工记一笔时告诉用户"今天已有一笔同额同商户"
pub fn find_soft_duplicate(
    bill_date: &str,
    amount: f64,
    merchant: &str,
    account_id: i64,
) -> Result<Option<Transaction>> {
    with_db(|conn| {
        let mut stmt = conn.prepare(&format!(
            "{} WHERE t.bill_date = ?1 AND t.account_id = ?2 AND abs(t.amount - ?3) < 0.005 AND t.merchant = ?4 AND t.status = 'posted' LIMIT 1",
            TX_JOIN
        ))?;
        let mut rows = stmt.query_map(
            params![bill_date, account_id, round2(amount), merchant],
            map_transaction,
        )?;
        Ok(rows.next().and_then(|r| r.ok()))
    })
}

// ── 邮件规则 ─────────────────────────────────────────────────────────────────

pub fn list_email_rules() -> Result<Vec<EmailRule>> {
    with_db(|conn| {
        let mut stmt = conn.prepare(RULE_SELECT)?;
        let rows = stmt.query_map([], map_rule)?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    })
}

const RULE_SELECT: &str = "SELECT id, name, enabled, protocol, host, port, use_ssl, username, mailbox, \
     sender_match, subject_match, match_is_regex, template_id, template_config, interval_minutes, daily_time, \
     default_account_id, auto_apply, accept_invalid_certs, last_run_at, last_result, created_at FROM email_rules";

pub fn get_email_rule(id: i64) -> Result<Option<EmailRule>> {
    with_db(|conn| {
        let mut stmt = conn.prepare(&format!("{} WHERE id = ?1", RULE_SELECT))?;
        let mut rows = stmt.query_map(params![id], map_rule)?;
        Ok(rows.next().and_then(|r| r.ok()))
    })
}

pub fn upsert_email_rule(rule: &EmailRule) -> Result<i64> {
    with_db(|conn| {
        if rule.id > 0 {
            conn.execute(
                "UPDATE email_rules SET name=?1, enabled=?2, protocol=?3, host=?4, port=?5, use_ssl=?6, username=?7, \
                 mailbox=?8, sender_match=?9, subject_match=?10, match_is_regex=?11, template_id=?12, \
                 template_config=?13, interval_minutes=?14, daily_time=?15, default_account_id=?16, auto_apply=?17, \
                 accept_invalid_certs=?18 WHERE id=?19",
                params![
                    rule.name,
                    rule.enabled as i64,
                    rule.protocol,
                    rule.host,
                    rule.port as i64,
                    rule.use_ssl as i64,
                    rule.username,
                    rule.mailbox,
                    rule.sender_match,
                    rule.subject_match,
                    rule.match_is_regex as i64,
                    rule.template_id,
                    rule.template_config,
                    rule.interval_minutes as i64,
                    rule.daily_time,
                    rule.default_account_id,
                    rule.auto_apply as i64,
                    rule.accept_invalid_certs as i64,
                    rule.id
                ],
            )?;
            Ok(rule.id)
        } else {
            conn.execute(
                "INSERT INTO email_rules (name, enabled, protocol, host, port, use_ssl, username, mailbox, sender_match, \
                 subject_match, match_is_regex, template_id, template_config, interval_minutes, daily_time, \
                 default_account_id, auto_apply, accept_invalid_certs, created_at) \
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16,?17,?18,?19)",
                params![
                    rule.name,
                    rule.enabled as i64,
                    rule.protocol,
                    rule.host,
                    rule.port as i64,
                    rule.use_ssl as i64,
                    rule.username,
                    rule.mailbox,
                    rule.sender_match,
                    rule.subject_match,
                    rule.match_is_regex as i64,
                    rule.template_id,
                    rule.template_config,
                    rule.interval_minutes as i64,
                    rule.daily_time,
                    rule.default_account_id,
                    rule.auto_apply as i64,
                    rule.accept_invalid_certs as i64,
                    now_str()
                ],
            )?;
            Ok(conn.last_insert_rowid())
        }
    })
}

pub fn set_email_rule_enabled(id: i64, enabled: bool) -> Result<()> {
    with_db(|conn| {
        conn.execute(
            "UPDATE email_rules SET enabled = ?1 WHERE id = ?2",
            params![enabled as i64, id],
        )?;
        Ok(())
    })
}

pub fn delete_email_rule(id: i64) -> Result<()> {
    with_db(|conn| {
        conn.execute("DELETE FROM email_rules WHERE id = ?1", params![id])?;
        conn.execute(
            "DELETE FROM email_rule_secrets WHERE rule_id = ?1",
            params![id],
        )?;
        Ok(())
    })
}

/// 记录 Dart 侧安全存储的键名引用（不存密码本身）
pub fn set_rule_secret_ref(rule_id: i64, secret_ref: &str) -> Result<()> {
    with_db(|conn| {
        conn.execute(
            "INSERT INTO email_rule_secrets (rule_id, secret_ref) VALUES (?1, ?2) \
             ON CONFLICT(rule_id) DO UPDATE SET secret_ref = excluded.secret_ref",
            params![rule_id, secret_ref],
        )?;
        Ok(())
    })
}

pub fn rule_secret_ref(rule_id: i64) -> Result<String> {
    with_db(|conn| {
        Ok(conn.query_row(
            "SELECT secret_ref FROM email_rule_secrets WHERE rule_id = ?1",
            params![rule_id],
            |r| r.get::<_, String>(0),
        )?)
    })
}

pub fn touch_rule_run(id: i64, result: &str) -> Result<()> {
    with_db(|conn| {
        conn.execute(
            "UPDATE email_rules SET last_run_at = ?1, last_result = ?2 WHERE id = ?3",
            params![now_str(), result, id],
        )?;
        Ok(())
    })
}

// ── 邮件与待确认队列 ─────────────────────────────────────────────────────────

/// 登记一封已收取的邮件。返回 false 表示该 UID 已收过（重复投递）。
pub fn record_email(
    rule_id: i64,
    message_uid: &str,
    message_id: &str,
    from_addr: &str,
    subject: &str,
    received_at: &str,
    bill_date: &str,
    tx_count: i64,
    applied: bool,
    available_credit: Option<f64>,
    points_balance: Option<i64>,
    warnings: &[String],
    html_len: i64,
) -> Result<bool> {
    with_db(|conn| {
        let affected = conn.execute(
            "INSERT OR IGNORE INTO emails (rule_id, message_uid, message_id, from_addr, subject, received_at, \
             bill_date, fetched_at, tx_count, applied, available_credit, points_balance, warnings_json, html_len) \
             VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14)",
            params![
                rule_id,
                message_uid,
                message_id,
                from_addr,
                subject,
                received_at,
                bill_date,
                now_str(),
                tx_count,
                applied as i64,
                available_credit,
                points_balance,
                serde_json::to_string(warnings).unwrap_or_else(|_| "[]".to_string()),
                html_len
            ],
        )?;
        Ok(affected > 0)
    })
}

pub fn known_email_uids(rule_id: i64) -> Result<Vec<String>> {
    with_db(|conn| {
        let mut stmt = conn.prepare("SELECT message_uid FROM emails WHERE rule_id = ?1")?;
        let rows = stmt.query_map(params![rule_id], |r| r.get::<_, String>(0))?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    })
}

const PENDING_SELECT: &str = "SELECT e.id, e.rule_id, r.name, e.message_uid, e.message_id, e.from_addr, e.subject, \
     e.received_at, e.bill_date, e.tx_count, e.applied, e.warnings_json, e.available_credit, e.points_balance, e.html_len \
     FROM emails e LEFT JOIN email_rules r ON r.id = e.rule_id";

/// 未入账（applied=0）或已入账的邮件记录，按 need 过滤
pub fn list_pending_email(applied: bool, limit: i64) -> Result<Vec<PendingEmail>> {
    with_db(|conn| {
        let sql = format!(
            "{} WHERE e.applied = ?1 ORDER BY e.received_at DESC, e.id DESC LIMIT ?2",
            PENDING_SELECT
        );
        let mut stmt = conn.prepare(&sql)?;
        let rows = stmt.query_map(params![applied as i64, limit], map_pending)?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    })
}

pub fn pending_email_detail(id: i64) -> Result<Option<PendingEmail>> {
    with_db(|conn| {
        let mut stmt = conn.prepare(&format!("{} WHERE e.id = ?1", PENDING_SELECT))?;
        let mut rows = stmt.query_map(params![id], map_pending)?;
        Ok(rows.next().and_then(|r| r.ok()))
    })
}

pub fn mark_email_applied(id: i64) -> Result<()> {
    with_db(|conn| {
        conn.execute("UPDATE emails SET applied = 1 WHERE id = ?1", params![id])?;
        Ok(())
    })
}

/// 待确认队列里的某笔流水直接改状态
pub fn set_tx_status_by_email(id: i64, status: &str) -> Result<i64> {
    with_db(|conn| {
        Ok(conn.execute(
            "UPDATE transactions SET status = ?1, updated_at = ?2 WHERE source = 'email' AND rule_id = \
             (SELECT rule_id FROM emails WHERE id = ?3) AND email_uid = (SELECT message_uid FROM emails WHERE id = ?3)",
            params![status, now_str(), id],
        )? as i64)
    })
}

/// 单笔流水改状态（确认/忽略都走这里）
pub fn set_tx_status(tx_id: i64, status: &str) -> Result<()> {
    with_db(|conn| {
        conn.execute(
            "UPDATE transactions SET status = ?1, updated_at = ?2 WHERE id = ?3",
            params![status, now_str(), tx_id],
        )?;
        Ok(())
    })
}

/// 该邮件解析出的流水（待确认列表展开用）
pub fn transactions_of_email(email_id: i64) -> Result<Vec<Transaction>> {
    with_db(|conn| {
        let mut stmt = conn.prepare(&format!(
            "{} WHERE t.source = 'email' AND t.rule_id = (SELECT rule_id FROM emails WHERE id = ?1) \
             AND t.email_uid = (SELECT message_uid FROM emails WHERE id = ?1) \
             ORDER BY t.occurred_at ASC",
            TX_JOIN
        ))?;
        let rows = stmt.query_map(params![email_id], map_transaction)?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    })
}

pub fn count_pending_emails() -> Result<i64> {
    with_db(|conn| {
        Ok(conn.query_row(
            "SELECT COUNT(*) FROM emails WHERE applied = 0 AND tx_count > 0",
            [],
            |r| r.get(0),
        )?)
    })
}

// ── 抓取日志 ─────────────────────────────────────────────────────────────────

pub fn begin_fetch_log(rule_id: i64) -> Result<i64> {
    with_db(|conn| {
        conn.execute(
            "INSERT INTO fetch_logs (rule_id, started_at, ok) VALUES (?1, ?2, 0)",
            params![rule_id, now_str()],
        )?;
        Ok(conn.last_insert_rowid())
    })
}

pub fn finish_fetch_log(
    id: i64,
    ok: bool,
    new_emails: i64,
    new_tx: i64,
    skipped_tx: i64,
    detail: &str,
) -> Result<()> {
    with_db(|conn| {
        conn.execute(
            "UPDATE fetch_logs SET finished_at = ?1, ok = ?2, new_emails = ?3, new_tx = ?4, skipped_tx = ?5, detail = ?6 WHERE id = ?7",
            params![now_str(), ok as i64, new_emails, new_tx, skipped_tx, detail, id],
        )?;
        Ok(())
    })
}

pub fn list_fetch_logs(limit: i64) -> Result<Vec<FetchLog>> {
    let limit = if limit <= 0 { 100 } else { limit };
    with_db(|conn| {
        let mut stmt = conn.prepare(
            "SELECT id, rule_id, started_at, finished_at, ok, new_emails, new_tx, skipped_tx, detail \
             FROM fetch_logs ORDER BY id DESC LIMIT ?1",
        )?;
        let rows = stmt.query_map(params![limit], |r| {
            Ok(FetchLog {
                id: r.get(0)?,
                rule_id: r.get(1)?,
                started_at: r.get(2)?,
                finished_at: r.get(3)?,
                ok: r.get::<_, i64>(4)? != 0,
                new_emails: r.get(5)?,
                new_tx: r.get(6)?,
                skipped_tx: r.get(7)?,
                detail: r.get(8)?,
            })
        })?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    })
}

pub fn clear_fetch_logs() -> Result<()> {
    with_db(|conn| {
        conn.execute("DELETE FROM fetch_logs", [])?;
        Ok(())
    })
}
