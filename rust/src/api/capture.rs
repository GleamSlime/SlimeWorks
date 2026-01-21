use flutter_rust_bridge::frb;
use lazy_static::lazy_static;
use std::sync::Mutex;
use tokio::runtime::Runtime;

/// 捕获的数据类型
#[derive(Debug, Clone)]
pub enum CaptureType {
    Video,
    Image,
    Json,
    Javascript,
}

/// 捕获统计数据
#[derive(Debug, Clone)]
pub struct CaptureStats {
    pub total: i32,
    pub videos: i32,
    pub images: i32,
    pub json: i32,
    pub javascript: i32,
}

lazy_static! {
    static ref RUNTIME: Mutex<Option<Runtime>> = Mutex::new(None);
    static ref IS_RUNNING: Mutex<bool> = Mutex::new(false);
}

/// 启动代理服务器
#[frb(sync)]
pub fn start_capture_proxy(port: u16) -> Result<String, String> {
    let mut is_running = IS_RUNNING.lock().unwrap();
    if *is_running {
        return Err("代理已经在运行中".to_string());
    }

    // 创建运行时
    let rt = Runtime::new().map_err(|e| format!("创建运行时失败: {}", e))?;
    
    // 在运行时中启动代理服务器
    rt.spawn(async move {
        if let Err(e) = capture_proxy::start_proxy_server(port).await {
            eprintln!("代理服务器错误: {}", e);
        }
    });

    *RUNTIME.lock().unwrap() = Some(rt);
    *is_running = true;

    Ok(format!("代理服务器已启动在端口 {}", port))
}

/// 停止代理服务器
#[frb(sync)]
pub fn stop_capture_proxy() -> Result<String, String> {
    let mut is_running = IS_RUNNING.lock().unwrap();
    if !*is_running {
        return Err("代理未运行".to_string());
    }

    // 清除系统代理
    let rt = Runtime::new().map_err(|e| format!("创建运行时失败: {}", e))?;
    rt.block_on(async {
        let _ = capture_proxy::system_proxy2::close_proxy().await;
    });

    // 清理运行时
    *RUNTIME.lock().unwrap() = None;
    *is_running = false;

    Ok("代理服务器已停止".to_string())
}

/// 获取捕获状态
#[frb(sync)]
pub fn is_proxy_running() -> bool {
    *IS_RUNNING.lock().unwrap()
}

/// 获取所有捕获的视频链接
#[frb(sync)]
pub fn get_captured_videos() -> Vec<String> {
    capture_proxy::get_captured_items()
        .into_iter()
        .filter(|item| item.content_type == "video")
        .map(|item| item.url)
        .collect()
}

/// 获取所有捕获的图片链接
#[frb(sync)]
pub fn get_captured_images() -> Vec<String> {
    capture_proxy::get_captured_items()
        .into_iter()
        .filter(|item| item.content_type == "image")
        .map(|item| item.url)
        .collect()
}

/// 获取所有捕获的JSON数据
#[frb(sync)]
pub fn get_captured_json() -> Vec<String> {
    capture_proxy::get_captured_items()
        .into_iter()
        .filter(|item| item.content_type == "json")
        .map(|item| item.url)
        .collect()
}

/// 获取所有捕获的JavaScript链接
#[frb(sync)]
pub fn get_captured_javascript() -> Vec<String> {
    capture_proxy::get_captured_items()
        .into_iter()
        .filter(|item| item.content_type == "javascript")
        .map(|item| item.url)
        .collect()
}

/// 清除所有捕获的数据
#[frb(sync)]
pub fn clear_captured_data() {
    capture_proxy::clear_captured_items();
}

/// 获取捕获数据的数量统计
#[frb(sync)]
pub fn get_capture_stats() -> CaptureStats {
    let items = capture_proxy::get_captured_items();
    
    CaptureStats {
        total: items.len() as i32,
        videos: items.iter().filter(|item| item.content_type == "video").count() as i32,
        images: items.iter().filter(|item| item.content_type == "image").count() as i32,
        json: items.iter().filter(|item| item.content_type == "json").count() as i32,
        javascript: items.iter().filter(|item| item.content_type == "javascript").count() as i32,
    }
}
