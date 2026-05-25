use slime_logger;

pub fn init_logger(install_dir: &str) -> Result<String, String> {
    slime_logger::init_logger(install_dir)
}

pub fn log_info(message: &str) {
    slime_logger::log_info(message);
}

pub fn log_warn(message: &str) {
    slime_logger::log_warn(message);
}

pub fn log_error(message: &str) {
    slime_logger::log_error(message);
}

pub fn log_debug(message: &str) {
    slime_logger::log_debug(message);
}

pub fn get_log_dir() -> Option<String> {
    slime_logger::get_log_dir()
}

pub fn cleanup_old_logs(days_to_keep: u32) -> Result<usize, String> {
    slime_logger::cleanup_old_logs(days_to_keep)
}

#[macro_export]
macro_rules! sw_info {
    ($($arg:tt)*) => {
        slime_logger::sw_info!($($arg)*)
    };
}

#[macro_export]
macro_rules! sw_warn {
    ($($arg:tt)*) => {
        slime_logger::sw_warn!($($arg)*)
    };
}

#[macro_export]
macro_rules! sw_error {
    ($($arg:tt)*) => {
        slime_logger::sw_error!($($arg)*)
    };
}

#[macro_export]
macro_rules! sw_debug {
    ($($arg:tt)*) => {
        slime_logger::sw_debug!($($arg)*)
    };
}
