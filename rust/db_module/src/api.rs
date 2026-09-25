use flutter_rust_bridge::frb;
use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};

use crate::storage::DbStorage;
use crate::types::*;

/// 多数据库实例表：路径 -> 存储实例。
/// 各模块通过各自的文件路径访问自己的数据库，互不干扰。
static DB_INSTANCES: OnceLock<Mutex<HashMap<String, Arc<DbStorage>>>> = OnceLock::new();

/// 表 -> 路径 路由表。模块调用 [db_bind_table] 后，该表的所有读写固定路由到绑定的文件，
/// 彻底消除历史上「全局单例先到先得」导致的数据写错文件问题。
static TABLE_ROUTES: OnceLock<Mutex<HashMap<String, String>>> = OnceLock::new();

/// 首个初始化的数据库路径（兼容 db_get_path）
static FIRST_PATH: OnceLock<Mutex<Option<String>>> = OnceLock::new();

fn instances() -> &'static Mutex<HashMap<String, Arc<DbStorage>>> {
    DB_INSTANCES.get_or_init(|| Mutex::new(HashMap::new()))
}

fn routes() -> &'static Mutex<HashMap<String, String>> {
    TABLE_ROUTES.get_or_init(|| Mutex::new(HashMap::new()))
}

fn first_path() -> &'static Mutex<Option<String>> {
    FIRST_PATH.get_or_init(|| Mutex::new(None))
}

/// 获取或创建指定路径的数据库实例（同一路径共享同一实例）。
fn get_or_open(db_path: &str) -> DbResult<Arc<DbStorage>> {
    let map = instances().lock().unwrap();
    if let Some(existing) = map.get(db_path) {
        return Ok(existing.clone());
    }
    drop(map);
    let storage = Arc::new(
        DbStorage::new(db_path).map_err(|e| format!("Failed to create database: {}", e))?,
    );
    let mut map = instances().lock().unwrap();
    // 并发创建保护：若另一线程已插入则复用
    if let Some(existing) = map.get(db_path) {
        return Ok(existing.clone());
    }
    map.insert(db_path.to_string(), storage.clone());
    Ok(storage)
}

/// 按表名解析其绑定的存储实例。
fn resolve(table_name: &str) -> DbResult<Arc<DbStorage>> {
    let path = routes()
        .lock()
        .unwrap()
        .get(table_name)
        .cloned()
        .ok_or_else(|| {
            format!(
                "Table '{}' not bound to any database, call db_bind_table first",
                table_name
            )
        })?;
    get_or_open(&path)
}

/// 初始化数据库（按路径打开实例，可多次调用不同路径，互不影响）。
#[frb(sync)]
pub fn db_init(db_path: String) -> DbResult<String> {
    let _ = get_or_open(&db_path)?;
    let mut first = first_path().lock().unwrap();
    if first.is_none() {
        *first = Some(db_path.clone());
    }
    Ok(format!("Database initialized at: {}", db_path))
}

/// 将表绑定到指定数据库文件：打开对应实例并注册表。
/// 之后该表的所有 db_set/db_get 等操作固定路由到此文件。重复绑定幂等。
pub fn db_bind_table(table_name: String, db_path: String) -> DbResult<()> {
    let storage = get_or_open(&db_path)?;
    let already_routed = routes().lock().unwrap().get(&table_name).cloned();
    match already_routed {
        Some(existing) if existing == db_path => return Ok(()),
        Some(_) => {
            return Err(format!(
                "Table '{}' already bound to another database",
                table_name
            ))
        }
        None => {}
    }
    // 将 String 转换为 'static str（通过泄漏内存，每表仅泄漏一次）
    let static_name: &'static str = Box::leak(table_name.clone().into_boxed_str());
    storage
        .register_table(static_name)
        .map_err(|e| format!("Failed to register table: {}", e))?;
    routes().lock().unwrap().insert(table_name, db_path);
    Ok(())
}

/// 注册表（兼容旧接口：仅当表已绑定时在其绑定的实例上注册；未绑定时为空操作）。
#[frb(sync)]
pub fn db_register_table(table_name: String) -> DbResult<()> {
    if let Some(storage) = resolve(&table_name).ok() {
        let static_name: &'static str = Box::leak(table_name.into_boxed_str());
        return storage
            .register_table(static_name)
            .map_err(|e| format!("Failed to register table: {}", e));
    }
    Ok(())
}

/// 设置键值
#[frb(sync)]
pub fn db_set(table_name: String, key: String, value: String) -> DbResult<()> {
    let storage = resolve(&table_name)?;
    storage
        .set(&table_name, &key, &value)
        .map_err(|e| format!("Failed to set value: {}", e))
}

/// 获取值
#[frb(sync)]
pub fn db_get(table_name: String, key: String) -> DbResult<Option<String>> {
    let storage = resolve(&table_name)?;
    storage
        .get(&table_name, &key)
        .map_err(|e| format!("Failed to get value: {}", e))
}

/// 删除键
#[frb(sync)]
pub fn db_delete(table_name: String, key: String) -> DbResult<bool> {
    let storage = resolve(&table_name)?;
    storage
        .delete(&table_name, &key)
        .map_err(|e| format!("Failed to delete key: {}", e))
}

/// 列出所有键
#[frb(sync)]
pub fn db_list_keys(table_name: String) -> DbResult<Vec<String>> {
    let storage = resolve(&table_name)?;
    storage
        .list_keys(&table_name)
        .map_err(|e| format!("Failed to list keys: {}", e))
}

/// 列出所有记录
#[frb(sync)]
pub fn db_list_all(table_name: String) -> DbResult<Vec<DbRecord>> {
    let storage = resolve(&table_name)?;
    let records = storage
        .list_all(&table_name)
        .map_err(|e| format!("Failed to list records: {}", e))?;

    Ok(records
        .into_iter()
        .map(|(key, value)| DbRecord { key, value })
        .collect())
}

/// 批量设置
#[frb(sync)]
pub fn db_batch_set(table_name: String, records: Vec<DbRecord>) -> DbResult<()> {
    let storage = resolve(&table_name)?;
    let records: Vec<(String, String)> = records.into_iter().map(|r| (r.key, r.value)).collect();

    storage
        .batch_set(&table_name, &records)
        .map_err(|e| format!("Failed to batch set: {}", e))
}

/// 在同一事务内完成批量写入与批量删除，返回实际操作的记录数。
///
/// 仅供 Rust 业务层调用（不加 `#[frb]`，不导出到 Dart）：导入/重建索引这类
/// 需要一次落盘成百上千条变更的场景应使用本函数，替代逐条 `db_set`/`db_delete`。
pub fn db_batch_write(
    table_name: String,
    sets: Vec<DbRecord>,
    deletes: Vec<String>,
) -> DbResult<u32> {
    let storage = resolve(&table_name)?;
    let sets: Vec<(String, String)> = sets.into_iter().map(|r| (r.key, r.value)).collect();

    storage
        .batch_write(&table_name, &sets, &deletes)
        .map(|n| n as u32)
        .map_err(|e| format!("Failed to batch write: {}", e))
}

/// 获取记录总数
#[frb(sync)]
pub fn db_count(table_name: String) -> DbResult<i32> {
    let storage = resolve(&table_name)?;
    storage
        .count(&table_name)
        .map(|c| c as i32)
        .map_err(|e| format!("Failed to count records: {}", e))
}

/// 清空表
#[frb(sync)]
pub fn db_clear_table(table_name: String) -> DbResult<()> {
    let storage = resolve(&table_name)?;
    storage
        .clear_table(&table_name)
        .map_err(|e| format!("Failed to clear table: {}", e))
}

/// 获取首个初始化的数据库路径
#[frb(sync)]
pub fn db_get_path() -> DbResult<String> {
    first_path()
        .lock()
        .unwrap()
        .clone()
        .ok_or_else(|| "No database initialized yet".to_string())
}

/// 将源数据库中指定表的记录合并到目标数据库：目标缺失的键补齐，
/// `overwrite` 为 true 时覆盖目标已有记录。源文件不存在或源表不存在时跳过。
/// 返回实际写入的记录数。
pub fn db_merge_tables(
    src_path: String,
    dst_path: String,
    tables: Vec<String>,
    overwrite: bool,
) -> DbResult<u64> {
    if src_path == dst_path || !std::path::Path::new(&src_path).exists() {
        return Ok(0);
    }
    let src = get_or_open(&src_path)?;
    let dst = get_or_open(&dst_path)?;
    let mut copied = 0u64;
    for table in &tables {
        // 在两个实例上注册表定义（不影响全局路由）
        let src_name: &'static str = Box::leak(table.clone().into_boxed_str());
        let _ = src.register_table(src_name);
        let dst_name: &'static str = Box::leak(table.clone().into_boxed_str());
        let _ = dst.register_table(dst_name);

        // 单次读事务拉取源表全部记录
        let src_records = match src.list_all(table) {
            Ok(records) => records,
            Err(_) => continue,
        };
        if src_records.is_empty() {
            continue;
        }

        // 计算需写入的记录：覆盖模式直接全量；补齐模式用 list_keys 一次取目标键集合
        let to_write: Vec<(String, String)> = if overwrite {
            src_records
        } else {
            let dst_keys: std::collections::HashSet<String> = match dst.list_keys(table) {
                Ok(keys) => keys.into_iter().collect(),
                Err(_) => continue,
            };
            src_records
                .into_iter()
                .filter(|(k, _)| !dst_keys.contains(k))
                .collect()
        };

        if to_write.is_empty() {
            continue;
        }

        let n = to_write.len() as u64;
        // 单次写事务批量插入，避免逐条 commit 造成 fsync 风暴
        if let Err(e) = dst.batch_set(table, &to_write) {
            return Err(format!("Failed to merge records: {}", e));
        }
        copied += n;
    }
    Ok(copied)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::storage::DbStorage;
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    /// 全局自增序号 + 纳秒时间戳，保证测试内表名/路径唯一。
    static SEQ: AtomicU64 = AtomicU64::new(0);

    fn unique_tag() -> String {
        let seq = SEQ.fetch_add(1, Ordering::SeqCst);
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        format!("{}{}_{}", std::process::id(), seq, nanos)
    }

    /// 说明：api.rs 依赖进程级全局静态（DB_INSTANCES / TABLE_ROUTES），且 redb
    /// 对打开中的数据库文件持有文件锁、缓存实例没有对外关闭/剔除接口。
    /// 因此各测试用例使用唯一表名 + 独立临时数据库文件避免互相干扰；
    /// 而必须共享同一目标文件路径的多个合并场景（默认补齐 / overwrite /
    /// 源不存在 / 源表不存在）会命中同一全局实例缓存，无法并行执行，
    /// 全部合并进同一个 #[test] 函数内串行验证。
    fn temp_root(tag: &str) -> PathBuf {
        let root = std::env::temp_dir().join(format!("db_module_api_test_{}", tag));
        std::fs::create_dir_all(&root).expect("应能创建测试临时目录");
        root
    }

    #[test]
    fn test_db_bind_table_idempotent_and_conflict() {
        let tag = unique_tag();
        let root = temp_root(&tag);
        let table = format!("bind_tbl_{}", tag);
        let p1 = root.join("p1.db");
        let p2 = root.join("p2.db");
        let s1 = p1.to_str().unwrap().to_string();
        let s2 = p2.to_str().unwrap().to_string();

        // 首次绑定：绑定后应能正常读写
        db_bind_table(table.clone(), s1.clone()).expect("首次绑定应成功");
        db_set(table.clone(), "k".into(), "v1".into()).expect("绑定后 db_set 应成功");
        assert_eq!(
            db_get(table.clone(), "k".into()).unwrap(),
            Some("v1".to_string()),
            "绑定后写入的数据应能读回"
        );

        // 重复绑定同一文件：应幂等成功，且数据不受影响
        db_bind_table(table.clone(), s1.clone()).expect("重复绑定同一文件应幂等成功");
        assert_eq!(
            db_get(table.clone(), "k".into()).unwrap(),
            Some("v1".to_string()),
            "幂等重绑后原数据应仍可读"
        );

        // 绑定到其他文件：应报冲突错误
        let err = db_bind_table(table.clone(), s2.clone())
            .expect_err("绑定到另一个数据库文件应报冲突错误");
        assert!(
            err.contains("already bound"),
            "冲突错误信息应包含 'already bound'，实际: {}",
            err
        );

        // 冲突绑定失败后路由保持不变，仍指向 p1
        assert_eq!(
            db_get(table.clone(), "k".into()).unwrap(),
            Some("v1".to_string()),
            "绑定冲突不应改变已有路由"
        );

        std::fs::remove_dir_all(root).ok();
    }

    #[test]
    fn test_db_unbound_table_operations_error() {
        let table = format!("unbound_tbl_{}", unique_tag());

        // 未绑定的表：所有路由型接口应报 "not bound" 错误
        let results: Vec<(String, DbResult<()>)> = vec![
            ("db_get".to_string(), db_get(table.clone(), "k".into()).map(|_| ())),
            (
                "db_set".to_string(),
                db_set(table.clone(), "k".into(), "v".into()),
            ),
            ("db_delete".to_string(), db_delete(table.clone(), "k".into()).map(|_| ())),
            ("db_list_keys".to_string(), db_list_keys(table.clone()).map(|_| ())),
            ("db_list_all".to_string(), db_list_all(table.clone()).map(|_| ())),
            (
                "db_batch_set".to_string(),
                db_batch_set(
                    table.clone(),
                    vec![DbRecord {
                        key: "k".into(),
                        value: "v".into(),
                    }],
                ),
            ),
            (
                "db_batch_write".to_string(),
                db_batch_write(table.clone(), vec![], vec!["k".into()]).map(|_| ()),
            ),
            ("db_count".to_string(), db_count(table.clone()).map(|_| ())),
            ("db_clear_table".to_string(), db_clear_table(table.clone())),
        ];

        for (name, result) in results {
            let err = result.err().unwrap_or_else(|| panic!("{} 对未绑定表应返回错误", name));
            assert!(
                err.contains("not bound"),
                "{} 的错误信息应包含 'not bound'，实际: {}",
                name,
                err
            );
        }
    }

    #[test]
    fn test_db_merge_tables_all_scenarios() {
        // 本函数串行覆盖 db_merge_tables 的全部场景，原因见上方注释：
        // 各场景共享 dst_path 的全局缓存实例，无法拆分并行。
        let tag = unique_tag();
        let root = temp_root(&tag);
        let table = format!("merge_tbl_{}", tag);
        let src_path = root.join("src.db");
        let dst_path = root.join("dst.db");
        let src_str = src_path.to_str().unwrap().to_string();
        let dst_str = dst_path.to_str().unwrap().to_string();

        // 1. 预置源库：直接用临时 DbStorage 写入后 drop 释放文件锁，
        //    避免与后续 db_merge_tables 内部 get_or_open 的实例缓存冲突。
        {
            let src = DbStorage::new(&src_path).expect("应能打开源库文件");
            let leaked: &'static str = Box::leak(table.clone().into_boxed_str());
            src.register_table(leaked).expect("源库表注册应成功");
            src
                .batch_set(
                    &table,
                    &[
                        ("k1".to_string(), "src_v1".to_string()),
                        ("k2".to_string(), "src_v2".to_string()),
                    ],
                )
                .expect("源库预置数据应成功");
            drop(src);
        }

        // 2. 表绑定到目标库并预置 k2（用于验证默认补齐模式不覆盖已有 key）
        db_bind_table(table.clone(), dst_str.clone()).expect("表绑定到目标库应成功");
        db_set(table.clone(), "k2".into(), "dst_v2".into())
            .expect("目标库预置 k2 应成功");

        // 3. 默认补齐模式：仅复制缺失的 k1，已有 k2 保持不变
        let copied = db_merge_tables(src_str.clone(), dst_str.clone(), vec![table.clone()], false)
            .expect("默认补齐合并应成功");
        assert_eq!(copied, 1, "补齐模式应仅复制 1 条缺失记录（k1）");
        assert_eq!(
            db_get(table.clone(), "k1".into()).unwrap(),
            Some("src_v1".to_string()),
            "缺失的 k1 应从源库补齐"
        );
        assert_eq!(
            db_get(table.clone(), "k2".into()).unwrap(),
            Some("dst_v2".to_string()),
            "默认补齐模式不得覆盖目标库已有的 k2"
        );

        // 4. 再次补齐：源键已全部存在，应复制 0 条
        let copied = db_merge_tables(src_str.clone(), dst_str.clone(), vec![table.clone()], false)
            .expect("二次补齐合并应成功");
        assert_eq!(copied, 0, "无缺失 key 时补齐模式应复制 0 条");

        // 5. overwrite=true：全量覆盖目标已有记录
        let copied = db_merge_tables(src_str.clone(), dst_str.clone(), vec![table.clone()], true)
            .expect("覆盖模式合并应成功");
        assert_eq!(copied, 2, "覆盖模式应复制源表全部 2 条记录");
        assert_eq!(
            db_get(table.clone(), "k2".into()).unwrap(),
            Some("src_v2".to_string()),
            "overwrite=true 应使用源库值覆盖目标 k2"
        );

        // 6. 源文件不存在：跳过并返回 0，且不报错
        let missing_src = root.join("not_exist.db");
        let copied = db_merge_tables(
            missing_src.to_str().unwrap().to_string(),
            dst_str.clone(),
            vec![table.clone()],
            false,
        )
        .expect("源文件不存在时合并不应报错");
        assert_eq!(copied, 0, "源文件不存在时应跳过并返回 0");
        assert!(
            !missing_src.exists(),
            "源文件不存在时不应创建源文件"
        );

        // 7. 源与目标为同一路径：直接返回 0
        let copied = db_merge_tables(
            dst_str.clone(),
            dst_str.clone(),
            vec![table.clone()],
            true,
        )
        .expect("同源同目标合并不应报错");
        assert_eq!(copied, 0, "源路径等于目标路径时应返回 0");

        // 8. 源文件存在但不含该表：视为源表不存在，跳过并返回 0
        let src_no_table = root.join("src_no_table.db");
        {
            let s = DbStorage::new(&src_no_table).expect("应能打开无目标表的源库");
            let other: &'static str =
                Box::leak(format!("other_tbl_{}", tag).into_boxed_str());
            s.register_table(other).unwrap();
            s.set(other, "x", "y").expect("无关表数据写入应成功");
            drop(s);
        }
        let copied = db_merge_tables(
            src_no_table.to_str().unwrap().to_string(),
            dst_str.clone(),
            vec![table.clone()],
            false,
        )
        .expect("源表不存在时合并不应报错");
        assert_eq!(copied, 0, "源文件存在但源表不存在时应跳过并返回 0");

        // 9. 空表列表：返回 0
        let copied =
            db_merge_tables(src_str.clone(), dst_str.clone(), vec![], false).expect("空表列表合并不应报错");
        assert_eq!(copied, 0, "表列表为空时应返回 0");

        // 注意：dst 实例被全局缓存持有（文件锁不释放），清理尽力而为
        std::fs::remove_dir_all(root).ok();
    }
}
