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
    // UNIQUE(meter_id, timestamp) 本身就会建一个 (meter_id, timestamp) 索引，
    // 早先额外建的 idx_power_meter_ts 是同一列对的重复索引，只多一份写入开销和空间，
    // 所以这里不再创建，并主动 DROP 掉老版本库里已经存在的那个
    // （CREATE INDEX IF NOT EXISTS 不会清理已发布库里的遗留索引）。
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
        DROP INDEX IF EXISTS idx_power_meter_ts;
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

/// 查询最近 `range_secs` 秒窗口内的采样（按时间升序），并额外带回窗口之前的最后一条。
///
/// 两条设计约束：
/// 1. 窗口锚定在**最新采样时间**而非当前时间，和聚合器保持一致——节点离线一段时间时
///    窗口跟着数据走，不会返回空表。
/// 2. 必须带回窗口前那条基准行：`aggregator` 用「相邻采样点的下降差值」算耗电，
///    少了首桶之前的那个点，整段窗口第一项就会凭空丢掉。
///
/// 结果规模由 range_secs 决定，与库内总行数无关，因此刷新页面不再随历史增长变慢。
pub fn get_samples_window(meter_id: &str, range_secs: i64) -> Result<Vec<PowerSample>> {
    let guard = DB_CONN.lock().unwrap();
    let conn = guard.as_ref().context("电力统计数据库未初始化")?;
    let last_ts: Option<i64> = conn
        .query_row(
            "SELECT MAX(timestamp) FROM power_samples WHERE meter_id = ?1",
            params![meter_id],
            |row| row.get(0),
        )
        .ok()
        .flatten();
    let Some(last_ts) = last_ts else {
        return Ok(Vec::new());
    };
    let start_ts = last_ts - range_secs;
    let mut stmt = conn.prepare(
        "SELECT timestamp, remaining_kwh, remaining_yuan, price FROM power_samples
         WHERE meter_id = ?1
           AND (timestamp >= ?2
                OR id = (SELECT id FROM power_samples
                         WHERE meter_id = ?1 AND timestamp < ?2
                         ORDER BY timestamp DESC LIMIT 1))
         ORDER BY timestamp ASC",
    )?;
    let rows = stmt.query_map(params![meter_id, start_ts], |row| {
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

/// 删除早于 `cutoff_ts` 的采样，返回删除条数（保留策略，防止库无限增长）
pub fn purge_samples_before(meter_id: &str, cutoff_ts: i64) -> Result<usize> {
    let guard = DB_CONN.lock().unwrap();
    let conn = guard.as_ref().context("电力统计数据库未初始化")?;
    Ok(conn.execute(
        "DELETE FROM power_samples WHERE meter_id = ?1 AND timestamp < ?2",
        params![meter_id, cutoff_ts],
    )?)
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
        assert!(get_samples_window("m", 60).is_err());
        assert!(purge_samples_before("m", 10).is_err());
        assert!(get_latest_sample("m").is_err());
        assert!(count_samples("m").is_err());
    }

    /// 窗口查询：锚定最新采样时间、升序、且只带回一条窗口前基准行
    ///
    /// 回归护栏：早先这里是 `ORDER BY timestamp ASC LIMIT 50000`，行数一旦超过上限
    /// 返回的就是**最老**的 5 万条，最新采样永远读不到，图表和统计卡片会静默冻结在
    /// 旧值上（不报错也不掉帧）。现在窗口以 MAX(timestamp) 为锚点，结果规模只由
    /// range_secs 决定，与库内总行数无关。
    #[test]
    fn storage_window_query_anchors_on_latest_with_baseline() {
        let _guard = lock_serial();
        let (db, root) = temp_db_path("window");
        init_db(db.to_str().unwrap()).unwrap();
        for (i, ts) in [100i64, 200, 300, 400, 500].iter().enumerate() {
            let kwh = 5.0 - i as f64;
            insert_sample("W", &sample(*ts, kwh, kwh, 1.0)).unwrap();
        }

        // 窗口 150 秒：锚点 last_ts=500 → start=350，窗口内取 400/500，
        // 基准行只带 300 这一条（100/200 必须被排除，否则等于没做窗口裁剪）
        let w = get_samples_window("W", 150).unwrap();
        assert_eq!(
            w.iter().map(|s| s.timestamp).collect::<Vec<_>>(),
            vec![300, 400, 500]
        );
        assert!((w[0].remaining_kwh - 3.0).abs() < 1e-12, "基准行内容应正确");

        // 窗口起点正好落在已有采样点上时，该点算窗口内（边界不重复计入基准行）
        let w = get_samples_window("W", 100).unwrap();
        assert_eq!(
            w.iter().map(|s| s.timestamp).collect::<Vec<_>>(),
            vec![300, 400, 500]
        );

        // 窗口大于全部历史：返回所有行且不多不少
        assert_eq!(get_samples_window("W", 100_000).unwrap().len(), 5);

        // 只有孤立一条时，没有基准行也不报错
        assert_eq!(
            get_samples_window("SINGLE", 1).unwrap().len(),
            0,
            "无数据的表号应返回空"
        );

        // purge 按 meter_id 隔离，只删严格早于 cutoff 的行
        assert_eq!(purge_samples_before("W", 300).unwrap(), 2);
        assert_eq!(count_samples("W").unwrap(), 3);
        assert_eq!(
            get_samples_window("W", 100_000)
                .unwrap()
                .iter()
                .map(|s| s.timestamp)
                .collect::<Vec<_>>(),
            vec![300, 400, 500]
        );

        close_db();
        let _ = std::fs::remove_dir_all(&root);
    }

    /// 完整读写往返：插入/覆盖/最新/计数/多表隔离/close_db
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

        // 全窗口查询按时间升序（排序由 SQL 保证，与插入顺序无关）
        let all = get_samples_window("A", 100_000).unwrap();
        assert_eq!(all.len(), 3);
        assert_eq!(
            all.iter().map(|s| s.timestamp).collect::<Vec<_>>(),
            vec![100, 200, 300]
        );
        assert!((all[1].remaining_kwh - 4.0).abs() < 1e-12);
        assert!((all[2].price - 1.0).abs() < 1e-12);

        // 无数据的表号返回空而非报错
        assert!(get_samples_window("C", 100_000).unwrap().is_empty());

        // 最新一条取 timestamp 最大
        let latest = get_latest_sample("A").unwrap().unwrap();
        assert_eq!(latest.timestamp, 300);
        assert!(get_latest_sample("C").unwrap().is_none());

        // INSERT OR REPLACE：同 (meter_id, timestamp) 覆盖而非追加
        insert_sample("A", &sample(200, 7.7, 6.6, 1.1)).unwrap();
        assert_eq!(count_samples("A").unwrap(), 3, "重复键应覆盖不新增");
        let replaced = get_samples_window("A", 100_000)
            .unwrap()
            .into_iter()
            .find(|s| s.timestamp == 200)
            .unwrap();
        assert!((replaced.remaining_kwh - 7.7).abs() < 1e-12);
        assert!((replaced.remaining_yuan - 6.6).abs() < 1e-12);
        assert!((replaced.price - 1.1).abs() < 1e-12);

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

    /// 老版本库里那个和 UNIQUE 重复的 idx_power_meter_ts，重开时必须被清掉，
    /// 同时 UNIQUE 自带的隐式索引（负责去重 + 范围查询）要留着
    #[test]
    fn storage_reinit_drops_legacy_duplicate_index() {
        let _guard = lock_serial();
        let (db, root) = temp_db_path("legacy_index");
        std::fs::create_dir_all(root.join("nested")).unwrap();
        // 用旧版 DDL 造一个"已经带重复索引"的库
        {
            let legacy = Connection::open(&db).unwrap();
            legacy
                .execute_batch(
                    "CREATE TABLE power_samples (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        meter_id TEXT NOT NULL,
                        timestamp INTEGER NOT NULL,
                        remaining_kwh REAL NOT NULL,
                        remaining_yuan REAL NOT NULL,
                        price REAL NOT NULL,
                        UNIQUE(meter_id, timestamp)
                     );
                     CREATE INDEX idx_power_meter_ts ON power_samples(meter_id, timestamp);",
                )
                .unwrap();
        }
        init_db(db.to_str().unwrap()).unwrap();

        let conn = Connection::open(&db).unwrap();
        let legacy_count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name='idx_power_meter_ts'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(legacy_count, 0, "遗留的重复索引应被 DROP");
        let autoindex_count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND tbl_name='power_samples' AND name LIKE 'sqlite_autoindex%'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(autoindex_count, 1, "UNIQUE 隐式索引应保持唯一");
        drop(conn);

        // 去重语义不受影响：同键仍然覆盖
        insert_sample("L", &sample(10, 1.0, 1.0, 1.0)).unwrap();
        insert_sample("L", &sample(10, 2.0, 2.0, 1.0)).unwrap();
        assert_eq!(count_samples("L").unwrap(), 1);
        close_db();
        let _ = std::fs::remove_dir_all(&root);
    }
}
