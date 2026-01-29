use anyhow::Result;
/// WebSocket 模块 API
///
/// 为 Flutter Rust Bridge 提供 WebSocket 功能
use flutter_rust_bridge::frb;

// 重新导出类型（FRB 需要）
pub use ws_module::{
    WsClient, WsClientConfig, WsConnectionState, WsMessage, WsMessageType, WsServerConfig,
};

// PC 端服务器 API
#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
#[cfg(not(any(target_os = "ios", target_os = "android")))]
pub use ws_module::WsServer;

// ============ 客户端 API（所有平台）============

/// 创建 WebSocket 客户端
#[frb(sync)]
pub fn ws_client_new(url: String) -> WsClient {
    WsClient::new(url)
}

/// 连接到 WebSocket 服务器
pub async fn ws_client_connect(client: &WsClient) -> Result<()> {
    client.connect().await.map_err(|e| anyhow::anyhow!(e))
}

/// 断开连接
pub async fn ws_client_disconnect(client: &WsClient) -> Result<()> {
    client.disconnect().await.map_err(|e| anyhow::anyhow!(e))
}

/// 发送文本消息
pub async fn ws_client_send_text(client: &WsClient, message: String) -> Result<()> {
    client
        .send_text(message)
        .await
        .map_err(|e| anyhow::anyhow!(e))
}

/// 发送二进制消息
pub async fn ws_client_send_binary(client: &WsClient, data: Vec<u8>) -> Result<()> {
    client
        .send_binary(data)
        .await
        .map_err(|e| anyhow::anyhow!(e))
}

/// 检查是否已连接
pub async fn ws_client_is_connected(client: &WsClient) -> bool {
    client.is_connected().await
}

/// 获取连接状态
pub async fn ws_client_get_state(client: &WsClient) -> WsConnectionState {
    client.get_state().await
}

/// 接收消息（非阻塞）
pub async fn ws_client_receive_message(client: &WsClient) -> Option<WsMessage> {
    client.receive_message().await
}

/// 获取消息数据
#[frb(sync)]
pub fn ws_message_get_data(message: &WsMessage) -> String {
    message.get_data()
}

/// 获取消息时间戳
#[frb(sync)]
pub fn ws_message_get_timestamp(message: &WsMessage) -> i64 {
    message.get_timestamp()
}

/// 检查是否为文本消息
#[frb(sync)]
pub fn ws_message_is_text(message: &WsMessage) -> bool {
    message.is_text()
}

/// 检查是否为二进制消息
#[frb(sync)]
pub fn ws_message_is_binary(message: &WsMessage) -> bool {
    message.is_binary()
}

// ============ 服务器 API（仅 PC 端）============

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
#[cfg(not(any(target_os = "ios", target_os = "android")))]
#[frb(sync)]
pub fn ws_server_new(host: String, port: u16) -> WsServer {
    WsServer::new(host, port)
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
#[cfg(not(any(target_os = "ios", target_os = "android")))]
pub async fn ws_server_start(server: &WsServer) -> Result<()> {
    server.start().await.map_err(|e| anyhow::anyhow!(e))
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
#[cfg(not(any(target_os = "ios", target_os = "android")))]
pub async fn ws_server_stop(server: &WsServer) -> Result<()> {
    server.stop().await.map_err(|e| anyhow::anyhow!(e))
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
#[cfg(not(any(target_os = "ios", target_os = "android")))]
pub async fn ws_server_broadcast(server: &WsServer, message: String) -> Result<()> {
    server
        .broadcast(message)
        .await
        .map_err(|e| anyhow::anyhow!(e))
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
#[cfg(not(any(target_os = "ios", target_os = "android")))]
pub async fn ws_server_get_client_count(server: &WsServer) -> Result<usize> {
    server
        .get_client_count()
        .await
        .map_err(|e| anyhow::anyhow!(e))
}
