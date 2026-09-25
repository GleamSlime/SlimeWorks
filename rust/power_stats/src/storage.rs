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

#[cfg(test)]
mod tests {
    use super::*;

    /// storage 使用进程级全局连接（lazy_static DB_CONN），所有用例必须串行执行
    static STORAGE_TEST_LOCK: Mutex<()> = Mutex::new(());

    fn lock_serial() -> std::sync::MutexGuard<'static, ()> {
        STORAGE_TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner())
    }

    fn sample(ts: i64, kwh: f64, yuan: f64, price: f64) -> PowerSample {
        PowerSample {
            timestamp: ts,
            remaining_kwh: kwh,
            remaining_yuan: yuan,
            price,
        }
    }

    /// 在系统临时目录下创建一次性数据库文件路径（含尚未存在的父目录，
    /// 顺带验证 init_db 会自动建目录），返回 (库路径, 待清理根目录)
    fn temp_db_path(case: &str) -> (PathBuf, PathBuf) {
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let root = std::env::temp_dir().join(format!(
            "power_stats_{}_{}_{}",
            case,
            std::process::id(),
            nanos
        ));
        let db = root.join("nested").join("power.db");
        (db, root)
    }

    /// 未初始化时所有读写接口应返回「未初始化」错误且不 panic
    #[test]
    fn storage_calls_fail_before_init() {
        let _guard = lock_serial();
        close_db(); // 确保干净状态
        assert!(!is_ready());
        let err = insert_sample("m", &sample(1, 1.0, 1.0, 1.0)).unwrap_err();
        assert!(format!("{err:#}").contains("未初始化"), "err = {err:#}");
        assert!(get_samples_range("m", 0, 10).is_err());
        assert!(get_all_samples("m", 10).is_err());
        assert!(get_latest_sample("m").is_err());
        assert!(count_samples("m").is_err());
    }

    /// 完整读写往返：插入/覆盖/范围查询/最新/计数/limit/多表隔离/close_db
    #[test]
    fn storage_roundtrip_insert_query_overwrite() {
        let _guard = lock_serial();
        let (db, root) = temp_db_path("roundtrip");
        // init_db 需自动创建 nested 父目录
        init_db(db.to_str().unwrap()).expect("init_db 应成功并创建目录");
        assert!(db.exists(), "数据库文件应被创建");
        assert!(is_ready());

        // 表 A 插入 3 条（乱序插入验证排序由 SQL 保证）
        insert_sample("A", &sample(300, 3.0, 3.0, 1.0)).unwrap();
        insert_sample("A", &sample(100, 5.0, 4.5, 0.9)).unwrap();
        insert_sample("A", &sample(200, 4.0, 3.6, 0.9)).unwrap();
        // 表 B 一条，验证 meter_id 隔离
        insert_sample("B", &sample(150, 9.9, 8.8, 2.0)).unwrap();

        assert_eq!(count_samples("A").unwrap(), 3);
        assert_eq!(count_samples("B").unwrap(), 1);
        assert_eq!(count_samples("C").unwrap(), 0);

        // 全量查询按时间升序
        let all = get_all_samples("A", 100).unwrap();
        assert_eq!(all.len(), 3);
        assert_eq!(all.iter().map(|s| s.timestamp).collect::<Vec<_>>(), vec![100, 200, 300]);
        assert!((all[1].remaining_kwh - 4.0).abs() < 1e-12);
        assert!((all[2].price - 1.0).abs() < 1e-12);

        // limit 生效且取升序前 N 条
        let limited = get_all_samples("A", 2).unwrap();
        assert_eq!(limited.iter().map(|s| s.timestamp).collect::<Vec<_>>(), vec![100, 200]);

        // 范围查询闭区间 [start, end]
        let ranged = get_samples_range("A", 100, 200).unwrap();
        assert_eq!(ranged.len(), 2);
        assert_eq!(ranged[0].timestamp, 100);
        assert_eq!(ranged[1].timestamp, 200);
        // 边界外：无交集时返回空
        assert!(get_samples_range("A", 101, 199).unwrap().is_empty());

        // 最新一条取 timestamp 最大
        let latest = get_latest_sample("A").unwrap().unwrap();
        assert_eq!(latest.timestamp, 300);
        assert!(get_latest_sample("C").unwrap().is_none());

        // INSERT OR REPLACE：同 (meter_id, timestamp) 覆盖而非追加
        insert_sample("A", &sample(200, 7.7, 6.6, 1.1)).unwrap();
        assert_eq!(count_samples("A").unwrap(), 3, "重复键应覆盖不新增");
        let replaced = get_samples_range("A", 200, 200).unwrap();
        assert_eq!(replaced.len(), 1);
        assert!((replaced[0].remaining_kwh - 7.7).abs() < 1e-12);
        assert!((replaced[0].remaining_yuan - 6.6).abs() < 1e-12);
        assert!((replaced[0].price - 1.1).abs() < 1e-12);

        // 不同 meter_id 相同 timestamp 不冲突
        insert_sample("B", &sample(300, 1.0, 1.0, 1.0)).unwrap();
        assert_eq!(count_samples("B").unwrap(), 2);

        // close_db 后回到未初始化状态
        close_db();
        assert!(!is_ready());
        assert!(count_samples("A").is_err());

        let _ = std::fs::remove_dir_all(&root);
    }

    /// 重复 init_db（幂等重建同一文件）不应因表已存在而失败，旧数据保留
    #[test]
    fn storage_reinit_same_path_keeps_data() {
        let _guard = lock_serial();
        let (db, root) = temp_db_path("reinit");
        init_db(db.to_str().unwrap()).unwrap();
        insert_sample("M", &sample(1, 2.0, 2.0, 1.0)).unwrap();
        close_db();
        // 再次 init：CREATE TABLE IF NOT EXISTS 路径
        init_db(db.to_str().unwrap()).unwrap();
        assert_eq!(count_samples("M").unwrap(), 1, "重开库后旧数据应存在");
        close_db();
        let _ = std::fs::remove_dir_all(&root);
    }
}
