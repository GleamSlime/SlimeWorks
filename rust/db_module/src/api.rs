use flutter_rust_bridge::frb;
use std::sync::{Arc, Mutex, OnceLock};

use crate::storage::DbStorage;
use crate::types::*;

static DB_INSTANCE: OnceLock<Arc<Mutex<Option<Arc<DbStorage>>>>> = OnceLock::new();

fn get_db_instance() -> &'static Arc<Mutex<Option<Arc<DbStorage>>>> {
    DB_INSTANCE.get_or_init(|| Arc::new(Mutex::new(None)))
}

/// 初始化数据库
#[frb(sync)]
pub fn db_init(db_path: String) -> DbResult<String> {
    let storage =
        DbStorage::new(&db_path).map_err(|e| format!("Failed to create database: {}", e))?;

    let storage = Arc::new(storage);
    *get_db_instance().lock().unwrap() = Some(storage);

    println!("Database initialized at: {}", db_path);

    Ok(format!("Database initialized at: {}", db_path))
}

/// 注册表
#[frb(sync)]
pub fn db_register_table(table_name: String) -> DbResult<()> {
    let storage = get_db_instance()
        .lock()
        .unwrap()
        .clone()
        .ok_or("Database not initialized")?;

    // 将 String 转换为 'static str（通过泄漏内存）
    let static_name: &'static str = Box::leak(table_name.into_boxed_str());

    storage
        .register_table(static_name)
        .map_err(|e| format!("Failed to register table: {}", e))
}

/// 设置键值
#[frb(sync)]
pub fn db_set(table_name: String, key: String, value: String) -> DbResult<()> {
    let storage = get_db_instance()
        .lock()
        .unwrap()
        .clone()
        .ok_or("Database not initialized")?;

    storage
        .set(&table_name, &key, &value)
        .map_err(|e| format!("Failed to set value: {}", e))
}

/// 获取值
#[frb(sync)]
pub fn db_get(table_name: String, key: String) -> DbResult<Option<String>> {
    let storage = get_db_instance()
        .lock()
        .unwrap()
        .clone()
        .ok_or("Database not initialized")?;

    storage
        .get(&table_name, &key)
        .map_err(|e| format!("Failed to get value: {}", e))
}

/// 删除键
#[frb(sync)]
pub fn db_delete(table_name: String, key: String) -> DbResult<bool> {
    let storage = get_db_instance()
        .lock()
        .unwrap()
        .clone()
        .ok_or("Database not initialized")?;

    storage
        .delete(&table_name, &key)
        .map_err(|e| format!("Failed to delete key: {}", e))
}

/// 列出所有键
#[frb(sync)]
pub fn db_list_keys(table_name: String) -> DbResult<Vec<String>> {
    let storage = get_db_instance()
        .lock()
        .unwrap()
        .clone()
        .ok_or("Database not initialized")?;

    storage
        .list_keys(&table_name)
        .map_err(|e| format!("Failed to list keys: {}", e))
}

/// 列出所有记录
#[frb(sync)]
pub fn db_list_all(table_name: String) -> DbResult<Vec<DbRecord>> {
    let storage = get_db_instance()
        .lock()
        .unwrap()
        .clone()
        .ok_or("Database not initialized")?;

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
    let storage = get_db_instance()
        .lock()
        .unwrap()
        .clone()
        .ok_or("Database not initialized")?;

    let records: Vec<(String, String)> = records.into_iter().map(|r| (r.key, r.value)).collect();

    storage
        .batch_set(&table_name, &records)
        .map_err(|e| format!("Failed to batch set: {}", e))
}

/// 获取记录总数
#[frb(sync)]
pub fn db_count(table_name: String) -> DbResult<i32> {
    let storage = get_db_instance()
        .lock()
        .unwrap()
        .clone()
        .ok_or("Database not initialized")?;

    storage
        .count(&table_name)
        .map(|c| c as i32)
        .map_err(|e| format!("Failed to count records: {}", e))
}

/// 清空表
#[frb(sync)]
pub fn db_clear_table(table_name: String) -> DbResult<()> {
    let storage = get_db_instance()
        .lock()
        .unwrap()
        .clone()
        .ok_or("Database not initialized")?;

    storage
        .clear_table(&table_name)
        .map_err(|e| format!("Failed to clear table: {}", e))
}

/// 获取数据库路径
#[frb(sync)]
pub fn db_get_path() -> DbResult<String> {
    let storage = get_db_instance()
        .lock()
        .unwrap()
        .clone()
        .ok_or("Database not initialized")?;

    Ok(storage.db_path().to_string_lossy().to_string())
}
