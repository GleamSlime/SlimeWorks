use chrono::Local;
/// 日志系统
///
/// 提供文件日志记录功能，日志保存在安装目录的 logs 子目录下
use std::fs::{create_dir_all, File, OpenOptions};
use std::io::Write;
use std::path::PathBuf;
use std::sync::Mutex;

lazy_static::lazy_static! {
    static ref LOG_FILE: Mutex<Option<File>> = Mutex::new(None);
    static ref LOG_DIR: Mutex<Option<PathBuf>> = Mutex::new(None);
}

/// 初始化日志系统
pub fn init_logger(install_dir: &str) -> Result<String, String> {
    let log_dir = PathBuf::from(install_dir).join("logs");

    // 创建 logs 目录
    create_dir_all(&log_dir).map_err(|e| format!("Failed to create logs directory: {}", e))?;

    // 生成日志文件名（按日期）
    let date = Local::now().format("%Y-%m-%d").to_string();
    let log_file_path = log_dir.join(format!("slime_works_{}.log", date));

    // 打开日志文件（追加模式）
    let file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(&log_file_path)
        .map_err(|e| format!("Failed to open log file: {}", e))?;

    // 保存文件句柄
    {
        // 保存文件句柄并立即释放锁
        let mut log_file = LOG_FILE.lock().unwrap();
        *log_file = Some(file);
    }

    {
        // 保存日志目录并立即释放锁
        let mut dir = LOG_DIR.lock().unwrap();
        *dir = Some(log_dir.clone());
    }

    // 写入启动日志（在释放锁后调用，避免重复锁定导致死锁）
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

/// 写入日志
fn write_log(message: &str) -> Result<(), String> {
    let mut log_file = LOG_FILE.lock().unwrap();

    if let Some(ref mut file) = *log_file {
        writeln!(file, "{}", message).map_err(|e| format!("Failed to write log: {}", e))?;
        file.flush()
            .map_err(|e| format!("Failed to flush log: {}", e))?;
    }

    Ok(())
}

/// 记录信息日志
pub fn log_info(message: &str) {
    let timestamp = Local::now().format("%Y-%m-%d %H:%M:%S");
    let log_msg = format!("[{}] [INFO] {}", timestamp, message);

    // 写入文件
    let _ = write_log(&log_msg);

    // 同时输出到控制台
    println!("{}", log_msg);
}

/// 记录警告日志
pub fn log_warn(message: &str) {
    let timestamp = Local::now().format("%Y-%m-%d %H:%M:%S");
    let log_msg = format!("[{}] [WARN] {}", timestamp, message);

    let _ = write_log(&log_msg);
    println!("{}", log_msg);
}

/// 记录错误日志
pub fn log_error(message: &str) {
    let timestamp = Local::now().format("%Y-%m-%d %H:%M:%S");
    let log_msg = format!("[{}] [ERROR] {}", timestamp, message);

    let _ = write_log(&log_msg);
    eprintln!("{}", log_msg);
}

/// 记录调试日志
pub fn log_debug(message: &str) {
    let timestamp = Local::now().format("%Y-%m-%d %H:%M:%S");
    let log_msg = format!("[{}] [DEBUG] {}", timestamp, message);

    let _ = write_log(&log_msg);
    println!("{}", log_msg);
}

/// 获取日志目录路径
pub fn get_log_dir() -> Option<String> {
    let dir = LOG_DIR.lock().unwrap();
    dir.as_ref().map(|p| p.to_string_lossy().to_string())
}

/// 清理旧日志（保留最近 N 天）
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
                    // 检查文件修改时间
                    if let Ok(metadata) = entry.metadata() {
                        if let Ok(modified) = metadata.modified() {
                            let modified_chrono = chrono::DateTime::<Local>::from(modified);
                            let age = now.signed_duration_since(modified_chrono);

                            if age.num_days() > days_to_keep as i64 {
                                if let Ok(_) = std::fs::remove_file(&path) {
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
