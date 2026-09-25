use slime_logger::sw_error;
use std::sync::{Arc, Mutex, OnceLock};

use crate::extractor;
use crate::types::*;

static PROGRESS_STATE: OnceLock<Arc<Mutex<Option<ExtractProgress>>>> = OnceLock::new();
static RESULT_STATE: OnceLock<Arc<Mutex<Option<ExtractResult>>>> = OnceLock::new();

fn get_progress_state() -> &'static Arc<Mutex<Option<ExtractProgress>>> {
    PROGRESS_STATE.get_or_init(|| Arc::new(Mutex::new(None)))
}

fn get_result_state() -> &'static Arc<Mutex<Option<ExtractResult>>> {
    RESULT_STATE.get_or_init(|| Arc::new(Mutex::new(None)))
}

const EXTRACT_PASSWORDS_TABLE: &str = "extract_passwords";

pub fn extract_init_password_table(db_path: String) {
    if let Err(e) = db_module::db_init(db_path.clone()) {
        sw_error!("初始化数据库失败: {}", e);
    }
    // 绑定到专属文件，避免历史上全局单例被其他模块抢先导致密码写错文件
    if let Err(e) = db_module::db_bind_table(EXTRACT_PASSWORDS_TABLE.to_string(), db_path.clone())
    {
        sw_error!("注册密码表失败: {}", e);
    }
    // 一次性迁移：历史上密码可能被写入 media.db / music_player.db
    migrate_scattered_passwords(&db_path);
}

/// 一次性迁移：把散落在其他数据库文件中的解压密码合并回专属文件（幂等）。
fn migrate_scattered_passwords(db_path: &str) {
    // 幂等标记存于独立的 extract_meta 表（避免污染密码列表）
    let _ = db_module::db_bind_table("extract_meta".to_string(), db_path.to_string());
    if let Ok(Some(flag)) =
        db_module::db_get("extract_meta".to_string(), "scatter_merged_v1".to_string())
    {
        if flag == "1" {
            return;
        }
    }
    // 候选：其他模块的历史数据库文件（Windows 下位于 %APPDATA%\SlimeWorks）
    // 显式标注类型：非 Windows 平台无 push 分支，否则类型推导失败（E0282）
    let mut candidates: Vec<std::path::PathBuf> = Vec::new();
    #[cfg(windows)]
    if let Ok(appdata) = std::env::var("APPDATA") {
        let base = std::path::Path::new(&appdata).join("SlimeWorks");
        candidates.push(base.join("media.db"));
        candidates.push(base.join("music_player.db"));
    }
    for candidate in &candidates {
        let src = candidate.to_string_lossy().into_owned();
        if src == db_path || !candidate.exists() {
            continue;
        }
        let _ = db_module::db_merge_tables(
            src,
            db_path.to_string(),
            vec![EXTRACT_PASSWORDS_TABLE.to_string()],
            false,
        );
    }
    let _ = db_module::db_set(
        "extract_meta".to_string(),
        "scatter_merged_v1".to_string(),
        "1".to_string(),
    );
}

pub fn extract_list_passwords_json() -> String {
    match db_module::db_list_all(EXTRACT_PASSWORDS_TABLE.to_string()) {
        Ok(records) => {
            let entries: Vec<PasswordEntry> = records
                .into_iter()
                .filter_map(|r| serde_json::from_str::<PasswordEntry>(&r.value).ok())
                .collect();
            serde_json::to_string(&entries).unwrap_or_else(|_| "[]".to_string())
        }
        Err(_) => "[]".to_string(),
    }
}

pub fn extract_add_password(password: String, remark: Option<String>) -> String {
    let entry = PasswordEntry {
        id: chrono::Utc::now().timestamp_millis().to_string(),
        password,
        remark,
        created_at: chrono::Utc::now().timestamp_millis(),
    };
    let json = serde_json::to_string(&entry).unwrap_or_default();
    if let Err(e) = db_module::db_set(EXTRACT_PASSWORDS_TABLE.to_string(), entry.id.clone(), json) {
        sw_error!("保存密码失败: {}", e);
    }
    serde_json::to_string(&entry).unwrap_or_default()
}

pub fn extract_remove_password(id: String) -> bool {
    db_module::db_delete(EXTRACT_PASSWORDS_TABLE.to_string(), id).unwrap_or(false)
}

pub fn extract_update_password_remark(id: String, remark: Option<String>) -> bool {
    let existing = match db_module::db_get(EXTRACT_PASSWORDS_TABLE.to_string(), id.clone()) {
        Ok(Some(json)) => serde_json::from_str::<PasswordEntry>(&json).ok(),
        _ => None,
    };
    match existing {
        Some(mut entry) => {
            entry.remark = remark;
            let json = serde_json::to_string(&entry).unwrap_or_default();
            db_module::db_set(EXTRACT_PASSWORDS_TABLE.to_string(), id, json).is_ok()
        }
        None => false,
    }
}

pub fn extract_scan_archives_json(dir: String) -> String {
    match extractor::scan_archives(&dir) {
        Ok(archives) => serde_json::to_string(&archives).unwrap_or_else(|_| "[]".to_string()),
        Err(_) => "[]".to_string(),
    }
}

pub fn extract_get_progress_json() -> String {
    let state = get_progress_state().lock().unwrap();
    match state.as_ref() {
        Some(p) => serde_json::to_string(p).unwrap_or_else(|_| "{}".to_string()),
        None => "{}".to_string(),
    }
}

pub fn extract_get_result_json() -> String {
    let state = get_result_state().lock().unwrap();
    match state.as_ref() {
        Some(r) => serde_json::to_string(r).unwrap_or_else(|_| "{}".to_string()),
        None => "{}".to_string(),
    }
}

pub fn extract_run_async(config_json: String) {
    let config: ExtractConfig = match serde_json::from_str(&config_json) {
        Ok(c) => c,
        Err(e) => {
            let progress = ExtractProgress {
                total_archives: 0,
                current_archive_index: 0,
                current_archive_name: String::new(),
                current_archive_progress: 0.0,
                total_progress: 0.0,
                total_file_size: 0,
                extracted_file_size: 0,
                elapsed_seconds: 0.0,
                estimated_remaining_seconds: 0.0,
                status: ExtractStatus::Failed,
            };
            *get_progress_state().lock().unwrap() = Some(progress);
            *get_result_state().lock().unwrap() = Some(ExtractResult {
                success: false,
                total_archives: 0,
                total_file_size: 0,
                extracted_size: 0,
                elapsed_seconds: 0.0,
                failed_archives: vec![],
                error_message: Some(format!("解析配置失败: {}", e)),
            });
            sw_error!("解析配置失败: {}", e);
            return;
        }
    };

    *get_result_state().lock().unwrap() = None;
    extractor::reset_cancel();

    let progress_state = get_progress_state().clone();

    let result = extractor::run_extract(&config, &|p| {
        *progress_state.lock().unwrap() = Some(p);
    });

    let final_progress = ExtractProgress {
        total_archives: result.total_archives,
        current_archive_index: result.total_archives,
        current_archive_name: String::new(),
        current_archive_progress: 1.0,
        total_progress: 1.0,
        total_file_size: result.total_file_size,
        extracted_file_size: result.extracted_size,
        elapsed_seconds: result.elapsed_seconds,
        estimated_remaining_seconds: 0.0,
        status: if result.success {
            ExtractStatus::Completed
        } else {
            ExtractStatus::Failed
        },
    };
    *progress_state.lock().unwrap() = Some(final_progress);
    *get_result_state().lock().unwrap() = Some(result);
}

pub fn extract_start(config_json: String) {
    let config_json_clone = config_json.clone();
    std::thread::spawn(move || {
        extract_run_async(config_json_clone);
    });
}

pub fn extract_cancel() {
    extractor::request_cancel();
}

/// 把本地目录整棵打包成系统临时目录下的 zip，返回 zip 的绝对路径。
/// 用于「拖目录到远程节点文件夹」链路：客户端打包→上传→节点解压→导入。
pub fn zip_directory_to_tmp(src_dir: String, entry_root: String) -> Result<String, String> {
    extractor::zip_directory_to_tmp(&src_dir, &entry_root)
        .map_err(|e| format!("打包目录失败: {}", e))
}

pub fn extract_format_file_size(bytes: u64) -> String {
    const KB: u64 = 1024;
    const MB: u64 = 1024 * KB;
    const GB: u64 = 1024 * MB;
    const TB: u64 = 1024 * GB;

    if bytes >= TB {
        format!("{:.2} TB", bytes as f64 / TB as f64)
    } else if bytes >= GB {
        format!("{:.2} GB", bytes as f64 / GB as f64)
    } else if bytes >= MB {
        format!("{:.2} MB", bytes as f64 / MB as f64)
    } else if bytes >= KB {
        format!("{:.2} KB", bytes as f64 / KB as f64)
    } else {
        format!("{} B", bytes)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn format_file_size_bytes() {
        assert_eq!(extract_format_file_size(0), "0 B");
        assert_eq!(extract_format_file_size(512), "512 B");
    }

    #[test]
    fn format_file_size_kb() {
        assert_eq!(extract_format_file_size(1024), "1.00 KB");
        assert_eq!(extract_format_file_size(1536), "1.50 KB");
    }

    #[test]
    fn format_file_size_mb() {
        assert_eq!(extract_format_file_size(1024 * 1024), "1.00 MB");
        assert_eq!(extract_format_file_size(5 * 1024 * 1024 + 512 * 1024), "5.50 MB");
    }

    #[test]
    fn format_file_size_gb() {
        assert_eq!(extract_format_file_size(1024 * 1024 * 1024), "1.00 GB");
        assert_eq!(extract_format_file_size(2 * 1024 * 1024 * 1024 + 512 * 1024 * 1024), "2.50 GB");
    }

    #[test]
    fn format_file_size_tb() {
        assert_eq!(extract_format_file_size(1024u64 * 1024 * 1024 * 1024), "1.00 TB");
    }

    // ── 密码表 DB 往返测试 ─────────────────────────────────────────────────
    //
    // 红线：绝不触碰用户真实密码库。extract_init_password_table 的 db_path
    // 为显式注入参数（不经过 $HOME 推导），因此直接传入系统临时目录下的
    // 一次性文件路径即可完全隔离；又因 db_module 的表绑定路由是进程级全局，
    // 全部密码用例必须串行执行。

    /// 串行锁：db_module 全局路由 + extract_passwords 表单实例
    static PWD_TEST_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

    /// 进程内只初始化一次的隔离测试库环境
    fn pwd_env() -> &'static std::path::PathBuf {
        static DB_PATH: OnceLock<std::path::PathBuf> = OnceLock::new();
        DB_PATH.get_or_init(|| {
            // 固定目录名 + 开跑前清旧：每次运行从空库开始，不在临时目录按
            // pid/时间戳累积残留（写入后归零）
            let dir = std::env::temp_dir().join("extract_pwd_test");
            assert_eq!(
                dir.parent(),
                Some(std::env::temp_dir().as_path()),
                "清理目标必须恰好位于系统临时目录下，防误删"
            );
            let _ = std::fs::remove_dir_all(&dir);
            std::fs::create_dir_all(&dir).expect("创建测试临时目录失败");
            let path = dir.join("extract_passwords.db");
            // 防御性断言：测试库必须位于系统临时目录，绝不允许是用户数据目录
            assert!(path.starts_with(std::env::temp_dir()), "隔离路径异常: {path:?}");
            extract_init_password_table(path.to_string_lossy().into_owned());
            // 二次 init 走幂等分支（同路径重复绑定 + 迁移标记已置位），不得报错也不得清数据
            extract_init_password_table(path.to_string_lossy().into_owned());
            path
        })
    }

    /// 取串行锁并确保隔离库已初始化
    fn lock_pwd_serial() -> std::sync::MutexGuard<'static, ()> {
        let guard = PWD_TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        pwd_env();
        guard
    }

    fn list_entries() -> Vec<PasswordEntry> {
        serde_json::from_str::<Vec<PasswordEntry>>(&extract_list_passwords_json())
            .expect("list_json 必须是合法的 PasswordEntry 数组")
    }

    /// 同一毫秒内的连续 add 可能撞 id（timestamp_millis 作键），测试主动隔开
    fn ensure_unique_add() {
        std::thread::sleep(std::time::Duration::from_millis(2));
    }

    /// 新增→列表→改备注→删除 的完整往返
    #[test]
    fn password_table_add_list_update_remove_roundtrip() {
        let _guard = lock_pwd_serial();
        let before = list_entries().len();

        ensure_unique_add();
        let added_json = extract_add_password("pwd-abc".to_string(), Some("首条备注".to_string()));
        let added: PasswordEntry = serde_json::from_str(&added_json).expect("add 返回合法 JSON");
        assert_eq!(added.password, "pwd-abc");
        assert_eq!(added.remark.as_deref(), Some("首条备注"));
        assert!(!added.id.is_empty());
        // created_at 应为毫秒级时间戳（与当前时刻相差 < 60s）
        let now_ms = chrono::Utc::now().timestamp_millis();
        assert!((now_ms - added.created_at).abs() < 60_000);

        let entries = list_entries();
        assert_eq!(entries.len(), before + 1);
        let stored = entries.iter().find(|e| e.id == added.id).expect("列表应含新条目");
        assert_eq!(stored.password, "pwd-abc");

        // 更新备注成功：id/password/created_at 均不变，只有 remark 变
        assert!(extract_update_password_remark(
            added.id.clone(),
            Some("改过的备注".to_string())
        ));
        let updated = list_entries().into_iter().find(|e| e.id == added.id).unwrap();
        assert_eq!(updated.remark.as_deref(), Some("改过的备注"));
        assert_eq!(updated.password, "pwd-abc");
        assert_eq!(updated.created_at, added.created_at);

        // 备注可置空（Option<String> → None）
        assert!(extract_update_password_remark(added.id.clone(), None));
        let nulled = list_entries().into_iter().find(|e| e.id == added.id).unwrap();
        assert_eq!(nulled.remark, None);

        // 删除：成功一次，重复删除返回 false
        assert!(extract_remove_password(added.id.clone()));
        assert_eq!(list_entries().len(), before);
        assert!(!extract_remove_password(added.id.clone()));
    }

    /// 特殊字符/Unicode 密码与备注经 JSON 序列化后原样取回
    #[test]
    fn password_table_preserves_special_characters() {
        let _guard = lock_pwd_serial();
        ensure_unique_add();
        let tricky = "密码 p@ss & = ? / \\ \" ' 中文 emoji 🎉 空格 制表\t换行\n";
        let json = extract_add_password(tricky.to_string(), Some("备注 \" 引号 & \\".to_string()));
        let entry: PasswordEntry = serde_json::from_str(&json).unwrap();

        let stored = list_entries()
            .into_iter()
            .find(|e| e.id == entry.id)
            .expect("特殊字符条目应能取回");
        assert_eq!(stored.password, tricky);
        assert_eq!(stored.remark.as_deref(), Some("备注 \" 引号 & \\"));

        assert!(extract_remove_password(entry.id));
    }

    /// 不存在的 id：update_remark / remove 都必须返回 false 且不影响列表
    #[test]
    fn password_table_missing_id_operations_return_false() {
        let _guard = lock_pwd_serial();
        let before = list_entries().len();
        assert!(!extract_update_password_remark("no-such-id".to_string(), Some("x".to_string())));
        assert!(!extract_update_password_remark("".to_string(), None));
        assert!(!extract_remove_password("no-such-id".to_string()));
        assert_eq!(list_entries().len(), before, "失败操作不应改动数据");
    }

    /// add 允许 remark 为空；空密码原样存储（业务上由上层校验，这里只测往返保真）
    #[test]
    fn password_table_empty_remark_and_empty_password_roundtrip() {
        let _guard = lock_pwd_serial();
        ensure_unique_add();
        let json = extract_add_password("".to_string(), None);
        let entry: PasswordEntry = serde_json::from_str(&json).unwrap();
        assert_eq!(entry.password, "");
        assert_eq!(entry.remark, None);

        let stored = list_entries().into_iter().find(|e| e.id == entry.id).unwrap();
        assert_eq!(stored.password, "");
        assert_eq!(stored.remark, None);
        let id = entry.id.clone();
        assert!(extract_remove_password(id.clone()));
        assert_eq!(list_entries().iter().filter(|e| e.id == id).count(), 0);
    }

    /// 库文件确实生成在隔离临时目录（防止误写用户目录的最后防线）
    #[test]
    fn password_db_stays_inside_temp_dir() {
        let _guard = lock_pwd_serial();
        let path = pwd_env();
        assert!(path.starts_with(std::env::temp_dir()));
        assert!(!path.to_string_lossy().contains("SlimeWorks"));
        assert!(path.exists() || path.parent().unwrap().exists(), "隔离目录应已创建");
    }
}
