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

        // 源库中不存在该表时跳过
        let records = match src.list_all(table) {
            Ok(records) => records,
            Err(_) => continue,
        };
        for (key, value) in records {
            let exists = dst.get(table, &key).map(|v| v.is_some()).unwrap_or(false);
            if !exists || overwrite {
                dst.set(table, &key, &value)
                    .map_err(|e| format!("Failed to merge record: {}", e))?;
                copied += 1;
            }
        }
    }
    Ok(copied)
}
