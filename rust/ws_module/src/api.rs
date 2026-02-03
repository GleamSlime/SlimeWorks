/// WebSocket 模块 API
///
/// 对外暴露的 Flutter Rust Bridge API
// 重新导出类型
pub use super::client::WsClient;
pub use super::types::*;

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
#[cfg(not(any(target_os = "ios", target_os = "android")))]
pub use super::server::WsServer;

// 将需要生成绑定的顶层包装函数放在 api 模块中，确保 codegen 能检测到它们
#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
#[cfg(not(any(target_os = "ios", target_os = "android")))]
mod frb_exports {
    use super::*;
    use flutter_rust_bridge::frb;

    #[frb]
    pub async fn ws_server_send_to_client(
        server: &WsServer,
        client_id: String,
        message: String,
    ) -> Result<(), String> {
        server.send_to_client(client_id, message).await
    }

    #[frb]
    pub async fn ws_server_disconnect_client(
        server: &WsServer,
        client_id: String,
    ) -> Result<(), String> {
        server.disconnect_client(client_id).await
    }

    #[frb]
    pub async fn ws_server_get_clients_json(server: &WsServer) -> Result<Vec<String>, String> {
        match server.get_clients().await {
            Ok(list) => {
                let mut out = Vec::with_capacity(list.len());
                for info in list {
                    match serde_json::to_string(&info) {
                        Ok(s) => out.push(s),
                        Err(e) => return Err(format!("Serialize error: {}", e)),
                    }
                }
                Ok(out)
            }
            Err(e) => Err(e),
        }
    }
}

// 只在桌面平台导出 frb 生成的绑定，移动端（iOS/Android）不会包含该模块
#[cfg(all(
    any(target_os = "windows", target_os = "macos", target_os = "linux"),
    not(any(target_os = "ios", target_os = "android"))
))]
pub use frb_exports::*;
