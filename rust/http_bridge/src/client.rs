use crate::types::{BridgeRequest, BridgeResponse};
use anyhow::Result;

/// HTTP桥接客户端（用于移动端调用服务端）
pub struct HttpBridgeClient {
    #[allow(dead_code)]
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
        let _request = BridgeRequest {
            module,
            function,
            params,
        };

        Err(anyhow::anyhow!("HTTP client not yet implemented"))
    }
}

/// 创建HTTP桥接客户端
pub fn create_bridge_client(host: String, port: u16) -> HttpBridgeClient {
    HttpBridgeClient::new(host, port)
}
