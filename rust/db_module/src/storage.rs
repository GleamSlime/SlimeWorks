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

    /// 同一事务内批量写入并批量删除。
    ///
    /// redb 每次 `commit()` 都会落盘一次 WAL/fsync，因此导入类场景下逐条
    /// `set`/`delete` 的代价是 O(n) 次磁盘刷写。把一次导入的全部增删合并到
    /// 本方法后，代价降为常数 1 次提交。
    pub fn batch_write(
        &self,
        table_name: &str,
        sets: &[(String, String)],
        deletes: &[String],
    ) -> Result<usize> {
        if sets.is_empty() && deletes.is_empty() {
            return Ok(0);
        }

        let tables = self.tables.lock().unwrap();
        let table_def = tables
            .get(table_name)
            .ok_or_else(|| anyhow::anyhow!("Table '{}' not registered", table_name))?;

        let db = self.db.lock().unwrap();
        let write_txn = db.begin_write()?;

        {
            let mut table = write_txn.open_table(*table_def)?;
            for key in deletes {
                table.remove(key.as_str())?;
            }
            for (key, value) in sets {
                table.insert(key.as_str(), value.as_str())?;
            }
        }

        write_txn.commit()?;
        Ok(sets.len() + deletes.len())
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
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    /// 全局自增序号，配合进程 ID + 纳秒时间戳生成唯一临时目录，
    /// 避免并发执行的测试用例互相争抢数据库文件（redb 对打开中的文件持有锁）。
    static SEQ: AtomicU64 = AtomicU64::new(0);

    /// 为每个测试用例创建独立的临时数据库路径，返回 (根目录, 数据库文件路径)
    /// 临时根目录守卫：用例结束（含显式删除后 Drop）自动整树删除，写入即归零
    struct TempRoot(PathBuf);
    impl std::ops::Deref for TempRoot {
        type Target = PathBuf;
        fn deref(&self) -> &PathBuf {
            &self.0
        }
    }
    impl AsRef<std::path::Path> for TempRoot {
        fn as_ref(&self) -> &std::path::Path {
            &self.0
        }
    }
    impl Drop for TempRoot {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    fn temp_db_paths(tag: &str) -> (TempRoot, PathBuf) {
        let seq = SEQ.fetch_add(1, Ordering::SeqCst);
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let root = std::env::temp_dir().join(format!(
            "db_module_test_{}_{}_{}_{}",
            std::process::id(),
            tag,
            seq,
            nanos
        ));
        std::fs::create_dir_all(&root).expect("应能创建临时测试目录");
        let db_path = root.join("test.db");
        (TempRoot(root), db_path)
    }

    #[test]
    fn test_storage_operations() {
        let (_root, db_path) = temp_db_paths("basic");

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
    }

    #[test]
    fn test_batch_set() {
        let (root, db_path) = temp_db_paths("batch_set");

        let storage = DbStorage::new(&db_path).expect("数据库应能打开");
        storage.register_table("t_batch").unwrap();

        let records: Vec<(String, String)> = (0..10)
            .map(|i| (format!("key{}", i), format!("value{}", i)))
            .collect();
        storage
            .batch_set("t_batch", &records)
            .expect("批量写入 10 条记录应成功");

        // 逐条回读验证
        for (key, value) in &records {
            let got = storage
                .get("t_batch", key)
                .expect("读取应成功")
                .unwrap_or_else(|| panic!("批量写入后 key '{}' 应能读回", key));
            assert_eq!(&got, value, "key '{}' 的值应与批量写入时一致", key);
        }

        // 空输入应为无害的空操作
        storage
            .batch_set("t_batch", &[])
            .expect("空批量写入应直接成功");
        assert_eq!(
            storage.count("t_batch").unwrap(),
            10,
            "空批量写入不应改变记录数"
        );

        std::fs::remove_dir_all(root).ok();
    }

    #[test]
    fn test_batch_write_mixed_sets_and_deletes() {
        let (root, db_path) = temp_db_paths("batch_write_mixed");

        let storage = DbStorage::new(&db_path).expect("数据库应能打开");
        storage.register_table("t_mixed").unwrap();
        storage
            .batch_set(
                "t_mixed",
                &[
                    ("old1".to_string(), "v_old1".to_string()),
                    ("old2".to_string(), "v_old2".to_string()),
                ],
            )
            .unwrap();

        // 同一事务内混合写入与删除：2 条 set + 1 条 delete，返回值应为 3
        let n = storage
            .batch_write(
                "t_mixed",
                &[
                    ("new1".to_string(), "v_new1".to_string()),
                    ("new2".to_string(), "v_new2".to_string()),
                ],
                &["old1".to_string()],
            )
            .expect("混合批量写入应成功");
        assert_eq!(n, 3, "batch_write 返回值应等于 sets + deletes 条数");

        assert_eq!(
            storage.get("t_mixed", "old1").unwrap(),
            None,
            "被删除的 key 'old1' 读取应为 None"
        );
        assert_eq!(
            storage.get("t_mixed", "old2").unwrap(),
            Some("v_old2".to_string()),
            "未在删除列表中的 'old2' 应保留"
        );
        assert_eq!(
            storage.get("t_mixed", "new1").unwrap(),
            Some("v_new1".to_string()),
            "新写入的 'new1' 应存在"
        );
        assert_eq!(
            storage.count("t_mixed").unwrap(),
            3,
            "混合写入后应剩 3 条记录（old2 + new1 + new2）"
        );

        // set 覆盖已有 key 也应正常工作
        let n = storage
            .batch_write(
                "t_mixed",
                &[("new1".to_string(), "v_new1_updated".to_string())],
                &[],
            )
            .expect("仅含 set 的 batch_write 应成功");
        assert_eq!(n, 1, "1 条 set + 0 条 delete 返回值应为 1");
        assert_eq!(
            storage.get("t_mixed", "new1").unwrap(),
            Some("v_new1_updated".to_string()),
            "batch_write 应覆盖已有 key"
        );

        std::fs::remove_dir_all(root).ok();
    }

    #[test]
    fn test_batch_write_empty_input() {
        let (root, db_path) = temp_db_paths("batch_write_empty");

        let storage = DbStorage::new(&db_path).expect("数据库应能打开");
        storage.register_table("t_empty").unwrap();
        storage
            .set("t_empty", "keep", "v")
            .expect("预置数据写入应成功");

        // 空输入直接返回 Ok(0)，不开启事务
        let n = storage
            .batch_write("t_empty", &[], &[])
            .expect("空输入 batch_write 应返回 Ok");
        assert_eq!(n, 0, "空输入 batch_write 返回值应为 0");
        assert_eq!(
            storage.count("t_empty").unwrap(),
            1,
            "空输入不应改变表内容"
        );

        // 注意当前实现特性：空输入早于表注册检查，未注册表名 + 空输入也返回 0
        let n = storage
            .batch_write("t_not_registered", &[], &[])
            .expect("未注册表名 + 空输入按当前实现应短路返回 Ok(0)");
        assert_eq!(n, 0, "未注册表名的空输入返回值应为 0");

        std::fs::remove_dir_all(root).ok();
    }

    #[test]
    fn test_list_keys_and_list_all() {
        let (root, db_path) = temp_db_paths("list");

        let storage = DbStorage::new(&db_path).expect("数据库应能打开");
        storage.register_table("t_list").unwrap();

        // redb 语义：表注册仅是内存态，物理表在首次写入后才存在。
        // 因此对从未写入过的新表执行读取会报错 "does not exist"。
        let err = storage
            .list_keys("t_list")
            .err()
            .expect("未写入过的新表 list_keys 应报错");
        assert!(
            format!("{}", err).contains("does not exist"),
            "未写入过的新表 list_keys 错误信息应包含 'does not exist'，实际: {}",
            err
        );

        storage
            .batch_set(
                "t_list",
                &[
                    ("a".to_string(), "1".to_string()),
                    ("b".to_string(), "2".to_string()),
                    ("c".to_string(), "3".to_string()),
                ],
            )
            .unwrap();

        // redb 按 key 有序迭代
        let keys = storage.list_keys("t_list").expect("list_keys 应成功");
        assert_eq!(
            keys,
            vec!["a".to_string(), "b".to_string(), "c".to_string()],
            "list_keys 应返回全部 key 且按字典序排列"
        );

        let all = storage.list_all("t_list").expect("list_all 应成功");
        assert_eq!(
            all,
            vec![
                ("a".to_string(), "1".to_string()),
                ("b".to_string(), "2".to_string()),
                ("c".to_string(), "3".to_string()),
            ],
            "list_all 应返回全部键值对"
        );

        // 物理表已存在时清空：list_keys / list_all 返回空集合而非报错
        storage.clear_table("t_list").expect("清空表应成功");
        assert!(
            storage.list_keys("t_list").unwrap().is_empty(),
            "清空后 list_keys 应返回空集合"
        );
        assert!(
            storage.list_all("t_list").unwrap().is_empty(),
            "清空后 list_all 应返回空集合"
        );

        std::fs::remove_dir_all(root).ok();
    }

    #[test]
    fn test_count() {
        let (root, db_path) = temp_db_paths("count");

        let storage = DbStorage::new(&db_path).expect("数据库应能打开");
        storage.register_table("t_count").unwrap();
        // 先写入一条再删除，确保物理表已创建
        storage
            .set("t_count", "tmp", "v")
            .expect("预置写入应成功");
        storage.delete("t_count", "tmp").unwrap();
        assert_eq!(
            storage.count("t_count").unwrap(),
            0,
            "空表记录数应为 0"
        );

        storage
            .batch_set(
                "t_count",
                &(0..5)
                    .map(|i| (format!("k{}", i), format!("v{}", i)))
                    .collect::<Vec<_>>(),
            )
            .unwrap();
        assert_eq!(
            storage.count("t_count").unwrap(),
            5,
            "写入 5 条后记录数应为 5"
        );

        // 覆盖写不应增加计数
        storage.set("t_count", "k0", "v0_again").unwrap();
        assert_eq!(
            storage.count("t_count").unwrap(),
            5,
            "覆盖已有 key 后记录数应仍为 5"
        );

        storage.delete("t_count", "k0").unwrap();
        assert_eq!(
            storage.count("t_count").unwrap(),
            4,
            "删除 1 条后记录数应为 4"
        );

        std::fs::remove_dir_all(root).ok();
    }

    #[test]
    fn test_clear_table() {
        let (root, db_path) = temp_db_paths("clear");

        let storage = DbStorage::new(&db_path).expect("数据库应能打开");
        storage.register_table("t_clear").unwrap();
        storage.register_table("t_keep").unwrap();
        storage
            .batch_set(
                "t_clear",
                &[
                    ("x".to_string(), "1".to_string()),
                    ("y".to_string(), "2".to_string()),
                ],
            )
            .unwrap();
        storage
            .set("t_keep", "z", "untouched")
            .expect("其他表预置数据应成功");

        storage.clear_table("t_clear").expect("清空表应成功");

        assert_eq!(
            storage.count("t_clear").unwrap(),
            0,
            "清空后 t_clear 记录数应为 0"
        );
        assert!(
            storage.list_keys("t_clear").unwrap().is_empty(),
            "清空后 list_keys 应为空"
        );
        assert_eq!(
            storage.get("t_clear", "x").unwrap(),
            None,
            "清空后原 key 应不可读"
        );
        // 其他表不受影响
        assert_eq!(
            storage.get("t_keep", "z").unwrap(),
            Some("untouched".to_string()),
            "clear_table 不应影响其他表"
        );

        // 再次清空空表应无害
        storage
            .clear_table("t_clear")
            .expect("清空已为空的表应成功");

        std::fs::remove_dir_all(root).ok();
    }

    #[test]
    fn test_unregistered_table_errors() {
        let (root, db_path) = temp_db_paths("unregistered");

        let storage = DbStorage::new(&db_path).expect("数据库应能打开");
        let table = "t_never_registered";

        // 所有读写方法在未注册表名上均应报错，且错误信息包含 "not registered"
        let cases: Vec<(&str, Result<()>)> = vec![
            ("set", storage.set(table, "k", "v").map(|_| ())),
            ("get", storage.get(table, "k").map(|_| ())),
            ("delete", storage.delete(table, "k").map(|_| ())),
            ("list_keys", storage.list_keys(table).map(|_| ())),
            ("list_all", storage.list_all(table).map(|_| ())),
            (
                "batch_set",
                storage
                    .batch_set(table, &[("k".to_string(), "v".to_string())])
                    .map(|_| ()),
            ),
            (
                "batch_write",
                storage
                    .batch_write(
                        table,
                        &[("k".to_string(), "v".to_string())],
                        &["k2".to_string()],
                    )
                    .map(|_| ()),
            ),
            ("count", storage.count(table).map(|_| ())),
            ("clear_table", storage.clear_table(table).map(|_| ())),
        ];

        for (method, result) in cases {
            let err = result
                .err()
                .unwrap_or_else(|| panic!("未注册表名调用 {} 应返回错误", method));
            let msg = format!("{}", err);
            assert!(
                msg.contains("not registered"),
                "{} 的错误信息应包含 'not registered'，实际: {}",
                method,
                msg
            );
        }

        std::fs::remove_dir_all(root).ok();
    }

    #[test]
    fn test_persistence_across_reopen() {
        let (root, db_path) = temp_db_paths("persistence");

        // 入库：写入数据后关闭数据库（drop 释放 redb 文件锁）
        {
            let storage = DbStorage::new(&db_path).expect("首次打开数据库应成功");
            storage.register_table("t_persist").unwrap();
            storage
                .batch_set(
                    "t_persist",
                    &[
                        ("pk1".to_string(), "pv1".to_string()),
                        ("pk2".to_string(), "pv2".to_string()),
                    ],
                )
                .expect("入库数据应成功");
            drop(storage);
        }

        // 出库：重新打开同一文件，数据应持久化
        {
            let storage = DbStorage::new(&db_path).expect("重新打开数据库应成功");
            // 表注册是内存态，重开后需再次注册
            storage.register_table("t_persist").unwrap();
            assert_eq!(
                storage.get("t_persist", "pk1").unwrap(),
                Some("pv1".to_string()),
                "关闭重开后 pk1 的值应持久保留"
            );
            assert_eq!(
                storage.get("t_persist", "pk2").unwrap(),
                Some("pv2".to_string()),
                "关闭重开后 pk2 的值应持久保留"
            );
            assert_eq!(
                storage.count("t_persist").unwrap(),
                2,
                "关闭重开后记录数应持久保留"
            );
            // 未注册的新表在重开后仍不可用（注册不落盘）
            assert!(
                storage.get("t_not_registered_after_reopen", "k").is_err(),
                "重开后未注册的表应仍报错"
            );
            drop(storage);
        }

        std::fs::remove_dir_all(root).ok();
    }
}
