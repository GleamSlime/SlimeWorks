use serde::{Deserialize, Serialize};
/// 数据捕获模块 - 管理捕获的数据项存储
use std::sync::Mutex;

/// 捕获的数据项
#[derive(Debug, Clone, Serialize, Deserialize)]
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
    let mut storage = CAPTURED_ITEMS.lock().unwrap();
    // 确保存储已初始化
    if storage.is_none() {
        println!("[capture::add_captured_item] Storage not initialized, initializing now");
        *storage = Some(Vec::new());
    }
    if let Some(ref mut items) = *storage {
        items.push(CapturedItem {
            url: url.clone(),
            content_type: content_type.clone(),
            content,
        });
        println!(
            "[capture::add_captured_item] Added item, total count: {}",
            items.len()
        );
    } else {
        println!("[capture::add_captured_item] WARNING: Storage initialization failed!");
    }
}

/// 获取所有捕获项
pub fn get_captured_items() -> Vec<CapturedItem> {
    let mut storage = CAPTURED_ITEMS.lock().unwrap();
    // 确保存储已初始化
    if storage.is_none() {
        println!("[capture::get_captured_items] Storage not initialized, initializing now");
        *storage = Some(Vec::new());
    }
    let result = storage
        .as_ref()
        .map(|items| {
            println!("[capture::get_captured_items] Returning {} items", items.len());
            items.clone()
        })
        .unwrap_or_else(|| {
            println!("[capture::get_captured_items] Unexpected: Storage still not initialized after init attempt");
            Vec::new()
        });
    result
}

/// 清除所有捕获项
pub fn clear_captured_items() {
    if let Some(ref mut items) = *CAPTURED_ITEMS.lock().unwrap() {
        items.clear();
    }
}
