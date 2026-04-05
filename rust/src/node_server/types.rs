use serde::{Deserialize, Serialize};

/// 节点请求数据
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NodeRequest {
    /// 动作名称（例如：list_novels, get_media_collection_items）
    pub action: String,
    /// 参数（JSON 格式）
    #[serde(default)]
    pub params: serde_json::Value,
}

/// 节点响应数据
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NodeResponse {
    /// 是否成功
    pub success: bool,
    /// 返回数据（JSON 格式）
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<serde_json::Value>,
    /// 错误消息
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

impl NodeResponse {
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

    pub fn to_json(&self) -> String {
        serde_json::to_string(self).unwrap_or_else(|_| r#"{"success":false,"error":"serialize error"}"#.to_string())
    }
}
