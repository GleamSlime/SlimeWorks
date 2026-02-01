use serde::{Deserialize, Serialize};

/// HTTP请求数据
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BridgeRequest {
    /// 模块名称（例如：novel_reader）
    pub module: String,
    /// 函数名称（例如：get_novel_content）
    pub function: String,
    /// 参数（JSON格式）
    pub params: serde_json::Value,
}

/// HTTP响应数据
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BridgeResponse {
    /// 是否成功
    pub success: bool,
    /// 返回数据（JSON格式）
    pub data: Option<serde_json::Value>,
    /// 错误消息
    pub error: Option<String>,
}

impl BridgeResponse {
    pub fn success(data: serde_json::Value) -> Self {
        Self {
            success: true,
            data: Some(data),
            error: None,
        }
    }

    pub fn error(message: String) -> Self {
        Self {
            success: false,
            data: None,
            error: Some(message),
        }
    }
}
