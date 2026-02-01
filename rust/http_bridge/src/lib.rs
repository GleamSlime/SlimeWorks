pub mod client;
/// HTTP Bridge 模块
///
/// 功能：
/// - 为移动端提供HTTP接口，将HTTP请求转发到FRB函数
/// - 桌面端启动HTTP服务器
/// - 移动端作为客户端调用HTTP接口
///
/// 使用场景：
/// - 当Rust功能无法在移动端完全实现时
/// - 通过HTTP请求让服务端（桌面端）执行逻辑后返回数据
pub mod server;
pub mod types;

pub use client::*;
pub use server::*;
pub use types::*;

use lazy_static::lazy_static;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;

// HTTP请求处理函数类型
pub type HandlerFn =
    Arc<dyn Fn(serde_json::Value) -> Result<serde_json::Value, String> + Send + Sync>;

lazy_static! {
    static ref SERVER_INSTANCE: Arc<Mutex<Option<HttpBridgeServer>>> = Arc::new(Mutex::new(None));

    // 注册的接口处理器：(module, function) -> handler
    static ref HANDLER_REGISTRY: Arc<Mutex<HashMap<(String, String), HandlerFn>>> =
        Arc::new(Mutex::new(HashMap::new()));
}

/// 注册HTTP桥接接口
pub async fn register_handler(
    module: String,
    function: String,
    handler: HandlerFn,
) -> anyhow::Result<()> {
    let mut registry = HANDLER_REGISTRY.lock().await;
    registry.insert((module, function), handler);
    Ok(())
}

/// 获取已注册的接口列表
pub async fn get_registered_handlers() -> Vec<(String, String)> {
    let registry = HANDLER_REGISTRY.lock().await;
    registry.keys().cloned().collect()
}

/// 调用已注册的处理器
pub async fn call_handler(
    module: String,
    function: String,
    params: serde_json::Value,
) -> Result<serde_json::Value, String> {
    let registry = HANDLER_REGISTRY.lock().await;

    if let Some(handler) = registry.get(&(module.clone(), function.clone())) {
        handler(params)
    } else {
        Err(format!("Handler not found: {}::{}", module, function))
    }
}

/// 启动HTTP桥接服务器（仅桌面端）
pub async fn start_bridge_server(host: String, port: u16) -> anyhow::Result<()> {
    let mut server = HttpBridgeServer::new(host, port)?;
    server.start().await?;

    let mut instance = SERVER_INSTANCE.lock().await;
    *instance = Some(server);

    Ok(())
}

/// 停止HTTP桥接服务器
pub async fn stop_bridge_server() -> anyhow::Result<()> {
    let mut instance = SERVER_INSTANCE.lock().await;
    if let Some(server) = instance.take() {
        server.stop().await?;
    }
    Ok(())
}

/// 获取服务器运行状态
pub async fn is_server_running() -> bool {
    let instance = SERVER_INSTANCE.lock().await;
    instance.is_some()
}
