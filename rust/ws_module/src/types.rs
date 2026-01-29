/// WebSocket 数据类型定义
use serde::{Deserialize, Serialize};

/// WebSocket 消息类型
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum WsMessageType {
    /// 文本消息
    Text,
    /// 二进制消息
    Binary,
    /// Ping
    Ping,
    /// Pong
    Pong,
    /// 关闭连接
    Close,
    /// 鉴权消息
    Auth,
}

/// WebSocket 消息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WsMessage {
    /// 消息类型
    pub msg_type: WsMessageType,
    /// 消息内容（文本或 base64 编码的二进制）
    pub data: String,
    /// 时间戳
    pub timestamp: i64,
}

impl WsMessage {
    /// 创建文本消息
    pub fn text(data: String) -> Self {
        Self {
            msg_type: WsMessageType::Text,
            data,
            timestamp: chrono::Utc::now().timestamp(),
        }
    }

    /// 创建二进制消息（data 为 base64 编码）
    pub fn binary(data: String) -> Self {
        Self {
            msg_type: WsMessageType::Binary,
            data,
            timestamp: chrono::Utc::now().timestamp(),
        }
    }

    /// 获取消息数据
    pub fn get_data(&self) -> String {
        self.data.clone()
    }

    /// 获取时间戳
    pub fn get_timestamp(&self) -> i64 {
        self.timestamp
    }

    /// 检查是否为文本消息
    pub fn is_text(&self) -> bool {
        matches!(self.msg_type, WsMessageType::Text)
    }

    /// 检查是否为二进制消息
    pub fn is_binary(&self) -> bool {
        matches!(self.msg_type, WsMessageType::Binary)
    }
}

/// WebSocket 连接状态
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WsConnectionState {
    /// 已连接
    Connected,
    /// 连接中
    Connecting,
    /// 已断开
    Disconnected,
    /// 错误
    Error,
}

/// WebSocket 服务器配置
#[derive(Debug, Clone)]
pub struct WsServerConfig {
    /// 监听地址
    pub host: String,
    /// 监听端口
    pub port: u16,
    /// 最大连接数
    pub max_connections: usize,
}

impl Default for WsServerConfig {
    fn default() -> Self {
        Self {
            host: "127.0.0.1".to_string(),
            port: 8765,
            max_connections: 100,
        }
    }
}

/// WebSocket 客户端配置
#[derive(Debug, Clone)]
pub struct WsClientConfig {
    /// 服务器地址（例如：ws://127.0.0.1:8765）
    pub url: String,
    /// 自动重连
    pub auto_reconnect: bool,
    /// 重连间隔（毫秒）
    pub reconnect_interval_ms: u64,
    /// 最大重连次数（0 表示无限）
    pub max_reconnect_attempts: u32,
}

impl Default for WsClientConfig {
    fn default() -> Self {
        Self {
            url: "ws://127.0.0.1:8765".to_string(),
            auto_reconnect: true,
            reconnect_interval_ms: 3000,
            max_reconnect_attempts: 0,
        }
    }
}

/// 客户端连接信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClientInfo {
    /// 客户端唯一标识
    pub id: String,
    /// 连接时间（时间戳，秒）
    pub connected_at: i64,
    /// 最后一次心跳时间（时间戳，秒）
    pub last_heartbeat: i64,
    /// 是否已鉴权
    pub authenticated: bool,
    /// 客户端地址
    pub address: String,
}

impl ClientInfo {
    /// 创建新的客户端信息
    pub fn new(id: String, address: String) -> Self {
        let now = chrono::Utc::now().timestamp();
        Self {
            id,
            connected_at: now,
            last_heartbeat: now,
            authenticated: false,
            address,
        }
    }

    /// 更新心跳时间
    pub fn update_heartbeat(&mut self) {
        self.last_heartbeat = chrono::Utc::now().timestamp();
    }

    /// 检查心跳是否超时（秒）
    pub fn is_heartbeat_timeout(&self, timeout_secs: i64) -> bool {
        let now = chrono::Utc::now().timestamp();
        now - self.last_heartbeat > timeout_secs
    }

    /// 检查鉴权是否超时（秒）
    pub fn is_auth_timeout(&self, timeout_secs: i64) -> bool {
        if self.authenticated {
            return false;
        }
        let now = chrono::Utc::now().timestamp();
        now - self.connected_at > timeout_secs
    }
}
