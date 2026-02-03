use crate::types::{BridgeRequest, BridgeResponse};
use anyhow::Result;

/// HTTP桥接客户端（用于移动端调用服务端）
pub struct HttpBridgeClient {
    base_url: String,
}

impl HttpBridgeClient {
    pub fn new(host: String, port: u16) -> Self {
        Self {
            base_url: format!("http://{}:{}", host, port),
        }
    }

    /// 发起桥接请求
    pub async fn call(
        &self,
        module: String,
        function: String,
        params: serde_json::Value,
    ) -> Result<BridgeResponse> {
        let request = BridgeRequest {
            module,
            function,
            params,
        };

        // 这里需要使用HTTP客户端发送请求
        // 由于hyper的客户端实现比较复杂，这里先返回一个占位实现
        
        // TODO: 实现实际的HTTP客户端调用
        Err(anyhow::anyhow!("HTTP client not yet implemented"))
    }
}

/// 创建HTTP桥接客户端
pub fn create_bridge_client(host: String, port: u16) -> HttpBridgeClient {
    HttpBridgeClient::new(host, port)
}
