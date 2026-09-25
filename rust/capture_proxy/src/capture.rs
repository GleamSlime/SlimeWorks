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

#[cfg(test)]
mod tests {
    use super::*;

    /// CAPTURED_ITEMS 是进程级全局存储，所有用例必须串行执行
    static CAPTURE_TEST_LOCK: Mutex<()> = Mutex::new(());

    fn lock_serial() -> std::sync::MutexGuard<'static, ()> {
        CAPTURE_TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// 恢复到「未初始化」的干净全局状态
    fn reset_storage() {
        *CAPTURED_ITEMS.lock().unwrap() = None;
    }

    fn item(url: &str, ctype: &str) -> CapturedItem {
        CapturedItem {
            url: url.to_string(),
            content_type: ctype.to_string(),
            content: None,
        }
    }

    /// add/get/clear 基础往返：顺序保持、字段保真、content 可空
    #[test]
    fn storage_add_get_clear_roundtrip() {
        let _guard = lock_serial();
        init_capture_storage();
        clear_captured_items();
        assert!(get_captured_items().is_empty());

        add_captured_item(
            "https://cdn.example.com/v.mp4".to_string(),
            "video".to_string(),
            Some("body-1".to_string()),
        );
        add_captured_item(
            "https://cdn.example.com/i.png".to_string(),
            "image".to_string(),
            None,
        );

        let items = get_captured_items();
        assert_eq!(items.len(), 2, "两条 add 应全部落库");
        // 入队顺序即读取顺序
        assert_eq!(items[0].url, "https://cdn.example.com/v.mp4");
        assert_eq!(items[0].content_type, "video");
        assert_eq!(items[0].content.as_deref(), Some("body-1"));
        assert_eq!(items[1].content_type, "image");
        assert_eq!(items[1].content, None, "None 内容必须原样保留为 None");

        // clear 只清空数据，不摧毁存储本身
        clear_captured_items();
        assert!(get_captured_items().is_empty());
        assert!(CAPTURED_ITEMS.lock().unwrap().is_some());
        // 空存储上 clear 幂等
        clear_captured_items();
        reset_storage();
    }

    /// get_captured_items 返回克隆：外部改动不污染全局存储
    #[test]
    fn get_returns_clones_not_shared_state() {
        let _guard = lock_serial();
        init_capture_storage();
        clear_captured_items();
        add_captured_item("u1".to_string(), "video".to_string(), None);
        let mut snapshot = get_captured_items();
        snapshot.push(item("u2", "video"));
        snapshot[0].url = "mutated".to_string();
        let again = get_captured_items();
        assert_eq!(again.len(), 1, "克隆改动不应影响全局");
        assert_eq!(again[0].url, "u1");
        reset_storage();
    }

    /// 未初始化直接 add/get：应自愈式自动初始化而不是丢失数据
    #[test]
    fn add_and_get_auto_initialize_when_uninit() {
        let _guard = lock_serial();
        reset_storage();
        assert!(CAPTURED_ITEMS.lock().unwrap().is_none());

        // get 在未初始化时自动建空存储且返回空列表
        assert!(get_captured_items().is_empty());
        assert!(CAPTURED_ITEMS.lock().unwrap().is_some(), "get 应自愈初始化");

        reset_storage();
        // add 在未初始化时同样自动初始化并保存数据
        add_captured_item("u".to_string(), "json".to_string(), Some("{}".to_string()));
        let items = get_captured_items();
        assert_eq!(items.len(), 1);
        assert_eq!(items[0].content_type, "json");
        reset_storage();
    }

    /// contentType 归类：FFI 的视频计数/URL 列表只认 video 前缀（大小写不敏感），
    /// image/json 项保留在全量列表中但不计入视频
    #[test]
    fn classification_videos_vs_images_through_ffi() {
        use crate::ffi::{
            proxy_get_all_items_json, proxy_get_video_count, proxy_get_videos_json,
            proxy_clear_items,
        };
        use std::ffi::CString;
        use std::os::raw::c_char;

        /// 读取 FFI 返回的 C 字符串 JSON 并归还内存
        unsafe fn take_json(ptr: *mut c_char) -> String {
            assert!(!ptr.is_null(), "FFI 不应返回 null");
            let s = CString::from_raw(ptr).to_string_lossy().into_owned();
            s
        }

        let _guard = lock_serial();
        init_capture_storage();
        clear_captured_items();

        add_captured_item("https://a/v1.mp4".to_string(), "video".to_string(), None);
        add_captured_item("https://a/i1.png".to_string(), "image".to_string(), None);
        add_captured_item("https://a/m1.json".to_string(), "json".to_string(), None);
        // 混合大小写也须归类为视频（实现使用 to_lowercase）
        add_captured_item("https://a/v2.ts".to_string(), "VIDEO".to_string(), None);
        // 「videojs」这类前缀命中同样按实现的 starts_with("video") 规则计入视频
        add_captured_item("https://a/p.js".to_string(), "videojs".to_string(), None);

        assert_eq!(proxy_get_video_count(), 3, "video/VIDEO/videojs 前缀应计入");

        let videos_json = unsafe { take_json(proxy_get_videos_json()) };
        let urls: Vec<String> = serde_json::from_str(&videos_json).expect("应为 URL 数组 JSON");
        assert_eq!(
            urls,
            vec![
                "https://a/v1.mp4".to_string(),
                "https://a/v2.ts".to_string(),
                "https://a/p.js".to_string()
            ],
            "视频列表应保持入队顺序且排除 image/json"
        );

        // 全量列表仍包含全部 5 条（image 归类为独立类别，不被视频过滤器吞掉）
        let all_json = unsafe { take_json(proxy_get_all_items_json()) };
        let all: Vec<CapturedItem> = serde_json::from_str(&all_json).expect("应为条目数组 JSON");
        assert_eq!(all.len(), 5);
        let images: Vec<&CapturedItem> = all
            .iter()
            .filter(|i| i.content_type.to_lowercase().starts_with("image"))
            .collect();
        assert_eq!(images.len(), 1);
        assert_eq!(images[0].url, "https://a/i1.png");

        // 清空后视频计数与列表同步归零
        proxy_clear_items();
        assert_eq!(proxy_get_video_count(), 0);
        let empty_list = unsafe { take_json(proxy_get_videos_json()) };
        assert_eq!(empty_list, "[]");
        reset_storage();
    }

    /// CapturedItem serde 往返（FFI 以 JSON 跨语言边界传输）
    #[test]
    fn captured_item_serde_roundtrip() {
        let it = CapturedItem {
            url: "http://x/".into(),
            content_type: "image".into(),
            content: Some("中文 & \"quote\"".into()),
        };
        let json = serde_json::to_string(&it).unwrap();
        let back: CapturedItem = serde_json::from_str(&json).unwrap();
        assert_eq!(back.url, it.url);
        assert_eq!(back.content_type, it.content_type);
        assert_eq!(back.content, it.content);
    }
}
