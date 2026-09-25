use chrono::Local;
use std::fs::{create_dir_all, File, OpenOptions};
use std::io::Write;
use std::path::PathBuf;
use std::sync::Mutex;

lazy_static::lazy_static! {
    static ref LOG_FILE: Mutex<Option<File>> = Mutex::new(None);
    static ref LOG_DIR: Mutex<Option<PathBuf>> = Mutex::new(None);
}

pub fn init_logger(install_dir: &str) -> Result<String, String> {
    let log_dir = PathBuf::from(install_dir).join("logs");
    println!("Initializing logger at: {}", log_dir.display());

    create_dir_all(&log_dir).map_err(|e| format!("Failed to create logs directory: {}", e))?;

    let date = Local::now().format("%Y-%m-%d").to_string();
    let log_file_path = log_dir.join(format!("slime_works_{}.log", date));

    let file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(&log_file_path)
        .map_err(|e| format!("Failed to open log file: {}", e))?;

    {
        let mut log_file = LOG_FILE.lock().unwrap();
        *log_file = Some(file);
    }

    {
        let mut dir = LOG_DIR.lock().unwrap();
        *dir = Some(log_dir.clone());
    }

    let msg = format!(
        "[{}] SlimeWorks started",
        Local::now().format("%Y-%m-%d %H:%M:%S")
    );
    let _ = write_log(&msg);

    Ok(format!(
        "Logs will be saved to: {}",
        log_file_path.display()
    ))
}

fn write_log(message: &str) -> Result<(), String> {
    let mut log_file = LOG_FILE.lock().unwrap();

    if let Some(ref mut file) = *log_file {
        writeln!(file, "{}", message).map_err(|e| format!("Failed to write log: {}", e))?;
        file.flush()
            .map_err(|e| format!("Failed to flush log: {}", e))?;
    }

    Ok(())
}

pub fn log_info(message: &str) {
    let timestamp = Local::now().format("%Y-%m-%d %H:%M:%S");
    let log_msg = format!("[{}] [INFO] {}", timestamp, message);
    let _ = write_log(&log_msg);
    println!("{}", log_msg);
}

pub fn log_warn(message: &str) {
    let timestamp = Local::now().format("%Y-%m-%d %H:%M:%S");
    let log_msg = format!("[{}] [WARN] {}", timestamp, message);
    let _ = write_log(&log_msg);
    println!("{}", log_msg);
}

pub fn log_error(message: &str) {
    let timestamp = Local::now().format("%Y-%m-%d %H:%M:%S");
    let log_msg = format!("[{}] [ERROR] {}", timestamp, message);
    let _ = write_log(&log_msg);
    eprintln!("{}", log_msg);
}

pub fn log_debug(message: &str) {
    let timestamp = Local::now().format("%Y-%m-%d %H:%M:%S");
    let log_msg = format!("[{}] [DEBUG] {}", timestamp, message);
    let _ = write_log(&log_msg);
    println!("{}", log_msg);
}

pub fn get_log_dir() -> Option<String> {
    let dir = LOG_DIR.lock().unwrap();
    dir.as_ref().map(|p| p.to_string_lossy().to_string())
}

pub fn cleanup_old_logs(days_to_keep: u32) -> Result<usize, String> {
    let log_dir = LOG_DIR.lock().unwrap();

    if let Some(ref dir) = *log_dir {
        let now = Local::now();
        let mut deleted_count = 0;

        let entries =
            std::fs::read_dir(dir).map_err(|e| format!("Failed to read log directory: {}", e))?;

        for entry in entries {
            if let Ok(entry) = entry {
                let path = entry.path();

                if path.is_file() && path.extension().and_then(|s| s.to_str()) == Some("log") {
                    if let Ok(metadata) = entry.metadata() {
                        if let Ok(modified) = metadata.modified() {
                            let modified_chrono = chrono::DateTime::<Local>::from(modified);
                            let age = now.signed_duration_since(modified_chrono);

                            if age.num_days() > days_to_keep as i64 {
                                if std::fs::remove_file(&path).is_ok() {
                                    deleted_count += 1;
                                    log_info(&format!("Deleted old log file: {}", path.display()));
                                }
                            }
                        }
                    }
                }
            }
        }

        Ok(deleted_count)
    } else {
        Err("Logger not initialized".to_string())
    }
}

/// 信息日志宏
#[macro_export]
macro_rules! sw_info {
    ($($arg:tt)*) => {
        $crate::log_info(&format!($($arg)*))
    };
}

/// 警告日志宏
#[macro_export]
macro_rules! sw_warn {
    ($($arg:tt)*) => {
        $crate::log_warn(&format!($($arg)*))
    };
}

/// 错误日志宏
#[macro_export]
macro_rules! sw_error {
    ($($arg:tt)*) => {
        $crate::log_error(&format!($($arg)*))
    };
}

/// 调试日志宏
#[macro_export]
macro_rules! sw_debug {
    ($($arg:tt)*) => {
        $crate::log_debug(&format!($($arg)*))
    };
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{Duration, SystemTime};

    /// LOG_DIR / LOG_FILE 为进程级全局，清理用例必须串行执行
    static LOGGER_TEST_LOCK: Mutex<()> = Mutex::new(());

    fn lock_serial() -> std::sync::MutexGuard<'static, ()> {
        LOGGER_TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// 一次性隔离目录（不触碰用户安装目录）
    fn fresh_install_dir(tag: &str) -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!(
            "slime_logger_test_{}_{}_{}",
            tag,
            std::process::id(),
            nanos
        ));
        std::fs::create_dir_all(&dir).expect("创建隔离目录失败");
        dir
    }

    /// 在 logs 目录下造一个指定「年龄」的日志文件（通过 mtime 模拟）
    fn write_log_with_age(logs_dir: &std::path::Path, name: &str, age: Duration) -> PathBuf {
        write_file_with_age(logs_dir, name, age, true)
    }

    fn write_file_with_age(
        logs_dir: &std::path::Path,
        name: &str,
        age: Duration,
        log_ext: bool,
    ) -> PathBuf {
        let path = logs_dir.join(if log_ext {
            format!("{name}.log")
        } else {
            format!("{name}.txt")
        });
        let file = File::create(&path).expect("创建测试日志文件失败");
        let mtime = SystemTime::now() - age;
        file.set_modified(mtime).expect("设置 mtime 失败（需 Rust 1.75+）");
        path
    }

    /// 未初始化：cleanup_old_logs 必须返回 "Logger not initialized"
    #[test]
    fn cleanup_errors_when_logger_not_initialized() {
        let _guard = lock_serial();
        // 显式恢复未初始化状态，测试不依赖用例执行顺序
        *LOG_DIR.lock().unwrap() = None;
        let err = cleanup_old_logs(7).unwrap_err();
        assert_eq!(err, "Logger not initialized");
    }

    /// init_logger：创建 logs 目录、当日日志文件与全局目录登记
    #[test]
    fn init_logger_creates_daily_log_file() {
        let _guard = lock_serial();
        let install = fresh_install_dir("init");
        let summary = init_logger(&install.to_string_lossy()).expect("init_logger 应成功");
        let logs_dir = install.join("logs");
        assert!(logs_dir.is_dir(), "init 应创建 logs 目录");
        let date = Local::now().format("%Y-%m-%d").to_string();
        let today_log = logs_dir.join(format!("slime_works_{date}.log"));
        assert!(today_log.is_file(), "应生成当日日志文件: {today_log:?}");
        assert!(summary.contains("slime_works_"), "summary = {summary}");
        assert_eq!(
            get_log_dir().as_deref(),
            Some(logs_dir.to_str().unwrap()),
            "get_log_dir 应反映最后一次 init"
        );
        let _ = std::fs::remove_dir_all(&install);
    }

    /// 按日期清理的边界：严格「大于保留天数的整天数」才删（age.num_days() 截断语义）
    #[test]
    fn cleanup_boundary_days_to_keep_seven() {
        let _guard = lock_serial();
        let install = fresh_install_dir("keep7");
        init_logger(&install.to_string_lossy()).unwrap();
        let logs_dir = install.join("logs");
        let day = Duration::from_secs(86_400);

        let keep_fresh = write_log_with_age(&logs_dir, "fresh", Duration::from_secs(0));
        // 7 天 23 小时：num_days()==7，不大于 7 ⇒ 保留
        let keep_edge_under =
            write_log_with_age(&logs_dir, "edge_under", 8 * day - Duration::from_secs(3600));
        // 恰好 7 天再加 1 分钟：num_days()==7 ⇒ 保留（边界为严格大于）
        let keep_exact = write_log_with_age(&logs_dir, "exact7", 7 * day + Duration::from_secs(60));
        // 8 天：num_days()==8 > 7 ⇒ 删除
        let del_8d = write_log_with_age(&logs_dir, "old8", 8 * day + Duration::from_secs(60));
        // 30 天 ⇒ 删除
        let del_30d = write_log_with_age(&logs_dir, "old30", 30 * day);
        // 30 天前的非 .log 文件：不受扩展名的项必须被跳过
        let keep_txt = write_file_with_age(&logs_dir, "ancient", 30 * day, false);
        // 名字像日志的目录：is_file 过滤应跳过（尽力把 mtime 也调旧，失败则保持为“新目录”，两种情形都不该被删）
        let dir_like = logs_dir.join("olddir.log");
        std::fs::create_dir_all(&dir_like).unwrap();
        if let Ok(df) = File::open(&dir_like) {
            let _ = df.set_modified(SystemTime::now() - 30 * day);
        }
        // 当日 slime_works 日志本身也必须被保留（年龄 0）
        let date = Local::now().format("%Y-%m-%d").to_string();
        let today_log = logs_dir.join(format!("slime_works_{date}.log"));
        assert!(today_log.is_file());

        let deleted = cleanup_old_logs(7).expect("清理应成功");
        assert_eq!(deleted, 2, "应恰好删除 8d 与 30d 两个文件");
        assert!(keep_fresh.exists() && keep_edge_under.exists() && keep_exact.exists());
        assert!(keep_txt.exists(), "非 .log 文件不应被动");
        assert!(dir_like.is_dir(), ".log 命名的目录不应被删除");
        assert!(today_log.exists(), "当日主日志不应被删除");
        assert!(!del_8d.exists() && !del_30d.exists(), "超期日志必须真的删除");

        // 幂等：再次清理没有可删项
        assert_eq!(cleanup_old_logs(7).unwrap(), 0);
        let _ = std::fs::remove_dir_all(&install);
    }

    /// days_to_keep=0：任何「满 1 天」的日志都删，当天的留
    #[test]
    fn cleanup_days_to_keep_zero() {
        let _guard = lock_serial();
        let install = fresh_install_dir("keep0");
        init_logger(&install.to_string_lossy()).unwrap();
        let logs_dir = install.join("logs");
        let day = Duration::from_secs(86_400);

        let keep_hours23 = write_log_with_age(&logs_dir, "h23", 23 * Duration::from_secs(3600));
        let del_yesterday = write_log_with_age(&logs_dir, "y1d", day + Duration::from_secs(60));
        let deleted = cleanup_old_logs(0).unwrap();
        assert_eq!(deleted, 1, "只有满 1 天的应被删");
        assert!(keep_hours23.exists());
        assert!(!del_yesterday.exists());
        let _ = std::fs::remove_dir_all(&install);
    }

    /// 日志目录被外部删除后：cleanup 返回读目录失败错误而非 panic
    #[test]
    fn cleanup_returns_error_when_log_dir_gone() {
        let _guard = lock_serial();
        let install = fresh_install_dir("gone");
        init_logger(&install.to_string_lossy()).unwrap();
        // 整个安装目录（含 logs）删掉 ⇒ read_dir 失败
        std::fs::remove_dir_all(&install).unwrap();
        let err = cleanup_old_logs(7).unwrap_err();
        assert!(err.contains("Failed to read log directory"), "err = {err}");
    }
}
