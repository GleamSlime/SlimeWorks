use anyhow::{Context, Result};
use lazy_static::lazy_static;
use rusqlite::{params, Connection};
use std::path::PathBuf;
use std::sync::Mutex;

use crate::types::PowerSample;

lazy_static! {
    static ref DB_CONN: Mutex<Option<Connection>> = Mutex::new(None);
}

/// 初始化SQLite数据库
pub fn init_db(db_path: &str) -> Result<()> {
    let path = PathBuf::from(db_path);
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).context("创建电力统计数据库目录失败")?;
    }
    let conn = Connection::open(path).context("打开电力统计数据库失败")?;
    conn.execute_batch(
        r#"
        CREATE TABLE IF NOT EXISTS power_samples (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            meter_id TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            remaining_kwh REAL NOT NULL,
            remaining_yuan REAL NOT NULL,
            price REAL NOT NULL,
            UNIQUE(meter_id, timestamp)
        );
        CREATE INDEX IF NOT EXISTS idx_power_meter_ts ON power_samples(meter_id, timestamp);
        "#,
    )
    .context("初始化电力统计表失败")?;

    let mut guard = DB_CONN.lock().unwrap();
    *guard = Some(conn);
    Ok(())
}

pub fn is_ready() -> bool {
    DB_CONN.lock().unwrap().is_some()
}

pub fn close_db() {
    let mut guard = DB_CONN.lock().unwrap();
    *guard = None;
}

/// 写入单条采样（存在则覆盖）
pub fn insert_sample(meter_id: &str, sample: &PowerSample) -> Result<()> {
    let guard = DB_CONN.lock().unwrap();
    let conn = guard.as_ref().context("电力统计数据库未初始化")?;
    conn.execute(
        "INSERT OR REPLACE INTO power_samples (meter_id, timestamp, remaining_kwh, remaining_yuan, price) VALUES (?1, ?2, ?3, ?4, ?5)",
        params![meter_id, sample.timestamp, sample.remaining_kwh, sample.remaining_yuan, sample.price],
    )?;
    Ok(())
}

/// 查询时间范围内的采样（按时间升序）
pub fn get_samples_range(meter_id: &str, start_ts: i64, end_ts: i64) -> Result<Vec<PowerSample>> {
    let guard = DB_CONN.lock().unwrap();
    let conn = guard.as_ref().context("电力统计数据库未初始化")?;
    let mut stmt = conn.prepare(
        "SELECT timestamp, remaining_kwh, remaining_yuan, price FROM power_samples WHERE meter_id = ?1 AND timestamp >= ?2 AND timestamp <= ?3 ORDER BY timestamp ASC",
    )?;
    let rows = stmt.query_map(params![meter_id, start_ts, end_ts], |row| {
        Ok(PowerSample {
            timestamp: row.get(0)?,
            remaining_kwh: row.get(1)?,
            remaining_yuan: row.get(2)?,
            price: row.get(3)?,
        })
    })?;
    let mut samples = Vec::new();
    for row in rows {
        samples.push(row?);
    }
    Ok(samples)
}

/// 查询全部采样（按时间升序），限制最大数量避免内存溢出
pub fn get_all_samples(meter_id: &str, limit: u64) -> Result<Vec<PowerSample>> {
    let guard = DB_CONN.lock().unwrap();
    let conn = guard.as_ref().context("电力统计数据库未初始化")?;
    let mut stmt = conn.prepare(
        "SELECT timestamp, remaining_kwh, remaining_yuan, price FROM power_samples WHERE meter_id = ?1 ORDER BY timestamp ASC LIMIT ?2",
    )?;
    let rows = stmt.query_map(params![meter_id, limit as i64], |row| {
        Ok(PowerSample {
            timestamp: row.get(0)?,
            remaining_kwh: row.get(1)?,
            remaining_yuan: row.get(2)?,
            price: row.get(3)?,
        })
    })?;
    let mut samples = Vec::new();
    for row in rows {
        samples.push(row?);
    }
    Ok(samples)
}

/// 获取最近一条采样
pub fn get_latest_sample(meter_id: &str) -> Result<Option<PowerSample>> {
    let guard = DB_CONN.lock().unwrap();
    let conn = guard.as_ref().context("电力统计数据库未初始化")?;
    let mut stmt = conn.prepare(
        "SELECT timestamp, remaining_kwh, remaining_yuan, price FROM power_samples WHERE meter_id = ?1 ORDER BY timestamp DESC LIMIT 1",
    )?;
    let mut rows = stmt.query_map(params![meter_id], |row| {
        Ok(PowerSample {
            timestamp: row.get(0)?,
            remaining_kwh: row.get(1)?,
            remaining_yuan: row.get(2)?,
            price: row.get(3)?,
        })
    })?;
    match rows.next() {
        Some(Ok(s)) => Ok(Some(s)),
        Some(Err(e)) => Err(anyhow::anyhow!("读取最新采样失败: {}", e)),
        None => Ok(None),
    }
}

/// 统计采样总数
pub fn count_samples(meter_id: &str) -> Result<u64> {
    let guard = DB_CONN.lock().unwrap();
    let conn = guard.as_ref().context("电力统计数据库未初始化")?;
    let count: i64 = conn.query_row(
        "SELECT COUNT(*) FROM power_samples WHERE meter_id = ?1",
        params![meter_id],
        |row| row.get(0),
    )?;
    Ok(count as u64)
}
