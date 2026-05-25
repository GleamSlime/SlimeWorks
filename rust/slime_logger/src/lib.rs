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
