/// 数据捕获模块 - 管理捕获的数据项存储
use std::sync::Mutex;

/// 捕获的数据项
#[derive(Debug, Clone)]
pub struct CapturedItem {
    pub url: String,
    pub content_type: String,
    pub content: Option<String>,
}

/// 全局捕获数据存储
pub static CAPTURED_ITEMS: Mutex<Option<Vec<CapturedItem>>> = Mutex::new(None);

/// 初始化捕获数据存储
pub fn init_capture_storage() {
    let mut storage = CAPTURED_ITEMS.lock().unwrap();
    *storage = Some(Vec::new());
}

/// 添加捕获项
pub fn add_captured_item(url: String, content_type: String, content: Option<String>) {
    if let Some(ref mut items) = *CAPTURED_ITEMS.lock().unwrap() {
        items.push(CapturedItem {
            url,
            content_type,
            content,
        });
    }
}

/// 获取所有捕获项
pub fn get_captured_items() -> Vec<CapturedItem> {
    CAPTURED_ITEMS
        .lock()
        .unwrap()
        .as_ref()
        .map(|items| items.clone())
        .unwrap_or_default()
}

/// 清除所有捕获项
pub fn clear_captured_items() {
    if let Some(ref mut items) = *CAPTURED_ITEMS.lock().unwrap() {
        items.clear();
    }
}
