use anyhow::{Context, Result};
use redb::{Database, ReadableTable, TableDefinition};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

/// 数据库存储引擎
pub struct DbStorage {
    db: Arc<Mutex<Database>>,
    db_path: PathBuf,
    tables: Arc<Mutex<HashMap<String, TableDefinition<'static, &'static str, &'static str>>>>,
}

impl DbStorage {
    /// 创建或打开数据库
    pub fn new<P: AsRef<Path>>(db_path: P) -> Result<Self> {
        let db_path = db_path.as_ref().to_path_buf();

        // 确保父目录存在
        if let Some(parent) = db_path.parent() {
            std::fs::create_dir_all(parent).context("Failed to create database directory")?;
        }

        let db = Database::create(&db_path).context("Failed to create/open database")?;

        Ok(Self {
            db: Arc::new(Mutex::new(db)),
            db_path,
            tables: Arc::new(Mutex::new(HashMap::new())),
        })
    }

    /// 注册表（必须在使用前调用）
    pub fn register_table(&self, table_name: &'static str) -> Result<()> {
        let mut tables = self.tables.lock().unwrap();
        if !tables.contains_key(table_name) {
            let table_def = TableDefinition::new(table_name);
            tables.insert(table_name.to_string(), table_def);
        }
        Ok(())
    }

    /// 设置键值
    pub fn set(&self, table_name: &str, key: &str, value: &str) -> Result<()> {
        let tables = self.tables.lock().unwrap();
        let table_def = tables
            .get(table_name)
            .ok_or_else(|| anyhow::anyhow!("Table '{}' not registered", table_name))?;

        let db = self.db.lock().unwrap();
        let write_txn = db.begin_write()?;

        {
            let mut table = write_txn.open_table(*table_def)?;
            table.insert(key, value)?;
        }

        write_txn.commit()?;
        Ok(())
    }

    /// 获取值
    pub fn get(&self, table_name: &str, key: &str) -> Result<Option<String>> {
        let tables = self.tables.lock().unwrap();
        let table_def = tables
            .get(table_name)
            .ok_or_else(|| anyhow::anyhow!("Table '{}' not registered", table_name))?;

        let db = self.db.lock().unwrap();
        let read_txn = db.begin_read()?;
        let table = read_txn.open_table(*table_def)?;

        if let Some(value) = table.get(key)? {
            Ok(Some(value.value().to_string()))
        } else {
            Ok(None)
        }
    }

    /// 删除键
    pub fn delete(&self, table_name: &str, key: &str) -> Result<bool> {
        let tables = self.tables.lock().unwrap();
        let table_def = tables
            .get(table_name)
            .ok_or_else(|| anyhow::anyhow!("Table '{}' not registered", table_name))?;

        let db = self.db.lock().unwrap();
        let write_txn = db.begin_write()?;

        let existed = {
            let mut table = write_txn.open_table(*table_def)?;
            let existed = table.get(key)?.is_some();
            if existed {
                table.remove(key)?;
            }
            existed
        };

        write_txn.commit()?;
        Ok(existed)
    }

    /// 列出所有键
    pub fn list_keys(&self, table_name: &str) -> Result<Vec<String>> {
        let tables = self.tables.lock().unwrap();
        let table_def = tables
            .get(table_name)
            .ok_or_else(|| anyhow::anyhow!("Table '{}' not registered", table_name))?;

        let db = self.db.lock().unwrap();
        let read_txn = db.begin_read()?;
        let table = read_txn.open_table(*table_def)?;

        let mut keys = Vec::new();
        for item in table.iter()? {
            let (key, _) = item?;
            keys.push(key.value().to_string());
        }

        Ok(keys)
    }

    /// 列出所有键值对
    pub fn list_all(&self, table_name: &str) -> Result<Vec<(String, String)>> {
        let tables = self.tables.lock().unwrap();
        let table_def = tables
            .get(table_name)
            .ok_or_else(|| anyhow::anyhow!("Table '{}' not registered", table_name))?;

        let db = self.db.lock().unwrap();
        let read_txn = db.begin_read()?;
        let table = read_txn.open_table(*table_def)?;

        let mut records = Vec::new();
        let iter = table.iter()?;
        for item in iter {
            let (key, value) = item?;
            records.push((key.value().to_string(), value.value().to_string()));
        }

        Ok(records)
    }

    /// 批量设置
    pub fn batch_set(&self, table_name: &str, records: &[(String, String)]) -> Result<()> {
        let tables = self.tables.lock().unwrap();
        let table_def = tables
            .get(table_name)
            .ok_or_else(|| anyhow::anyhow!("Table '{}' not registered", table_name))?;

        let db = self.db.lock().unwrap();
        let write_txn = db.begin_write()?;

        {
            let mut table = write_txn.open_table(*table_def)?;
            for (key, value) in records {
                table.insert(key.as_str(), value.as_str())?;
            }
        }

        write_txn.commit()?;
        Ok(())
    }

    /// 获取表中的记录总数
    pub fn count(&self, table_name: &str) -> Result<usize> {
        let tables = self.tables.lock().unwrap();
        let table_def = tables
            .get(table_name)
            .ok_or_else(|| anyhow::anyhow!("Table '{}' not registered", table_name))?;

        let db = self.db.lock().unwrap();
        let read_txn = db.begin_read()?;
        let table = read_txn.open_table(*table_def)?;

        let mut count = 0;
        for _ in table.iter()? {
            count += 1;
        }

        Ok(count)
    }

    /// 清空表
    pub fn clear_table(&self, table_name: &str) -> Result<()> {
        let tables = self.tables.lock().unwrap();
        let table_def = tables
            .get(table_name)
            .ok_or_else(|| anyhow::anyhow!("Table '{}' not registered", table_name))?;

        let db = self.db.lock().unwrap();
        let write_txn = db.begin_write()?;

        {
            let mut table = write_txn.open_table(*table_def)?;
            // 收集所有 key
            let iter = table.iter()?;
            let keys: Vec<String> = iter
                .filter_map(|item| item.ok())
                .map(|(k, _)| k.value().to_string())
                .collect();

            // 删除所有记录
            for key in &keys {
                table.remove(key.as_str())?;
            }
        }

        write_txn.commit()?;
        Ok(())
    }

    /// 获取数据库路径
    pub fn db_path(&self) -> &Path {
        &self.db_path
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_storage_operations() {
        let temp_dir = std::env::temp_dir().join("db_module_test");
        let db_path = temp_dir.join("test.db");

        let storage = DbStorage::new(&db_path).unwrap();
        storage.register_table("test_table").unwrap();

        // 测试设置和获取
        storage.set("test_table", "key1", "value1").unwrap();
        let value = storage.get("test_table", "key1").unwrap();
        assert_eq!(value, Some("value1".to_string()));

        // 测试删除
        let deleted = storage.delete("test_table", "key1").unwrap();
        assert!(deleted);

        let value = storage.get("test_table", "key1").unwrap();
        assert_eq!(value, None);

        // 清理
        std::fs::remove_dir_all(temp_dir).ok();
    }
}
