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

#[cfg(test)]
mod tests {
    use super::*;

    fn now() -> i64 {
        chrono::Utc::now().timestamp()
    }

    // ── WsMessage ──────────────────────────────────────────────────────────

    /// text()：类型为 Text、数据原样保留、时间戳取创建时刻（秒级）
    #[test]
    fn ws_message_text_constructor_and_accessors() {
        let before = now();
        let msg = WsMessage::text("你好，websocket".to_string());
        let after = now();
        assert!(msg.is_text());
        assert!(!msg.is_binary());
        assert!(matches!(msg.msg_type, WsMessageType::Text));
        assert_eq!(msg.get_data(), "你好，websocket");
        assert!(msg.timestamp >= before && msg.timestamp <= after);
        assert_eq!(msg.get_timestamp(), msg.timestamp);
    }

    /// binary()：类型为 Binary（data 为 base64 字符串），与 text 判定互斥
    #[test]
    fn ws_message_binary_constructor_is_not_text() {
        let msg = WsMessage::binary("AAECAw==".to_string());
        assert!(msg.is_binary());
        assert!(!msg.is_text());
        assert_eq!(msg.get_data(), "AAECAw==");
    }

    /// 其它消息类型（Ping/Pong/Close/Auth）既不是 text 也不是 binary
    #[test]
    fn ws_message_other_types_are_neither_text_nor_binary() {
        for t in [
            WsMessageType::Ping,
            WsMessageType::Pong,
            WsMessageType::Close,
            WsMessageType::Auth,
        ] {
            let msg = WsMessage {
                msg_type: t.clone(),
                data: "x".to_string(),
                timestamp: 0,
            };
            assert!(!msg.is_text(), "类型 {t:?} 不应判为文本");
            assert!(!msg.is_binary(), "类型 {t:?} 不应判为二进制");
        }
    }

    /// get_data 返回克隆：修改返回值不影响原消息
    #[test]
    fn ws_message_get_data_returns_clone() {
        let msg = WsMessage::text("abc".to_string());
        let mut got = msg.get_data();
        got.push('d');
        assert_eq!(msg.get_data(), "abc");
    }

    /// serde 往返保留消息类型与内容
    #[test]
    fn ws_message_serde_round_trip() {
        let msg = WsMessage::binary("base64data".to_string());
        let json = serde_json::to_string(&msg).expect("序列化应成功");
        let back: WsMessage = serde_json::from_str(&json).expect("反序列化应成功");
        assert!(back.is_binary());
        assert_eq!(back.get_data(), "base64data");
        assert_eq!(back.timestamp, msg.timestamp);
    }

    // ── ClientInfo ─────────────────────────────────────────────────────────

    /// new()：连接时间与心跳同步初始化、默认未鉴权
    #[test]
    fn client_info_new_initializes_timestamps_and_unauthenticated() {
        let before = now();
        let info = ClientInfo::new("c-1".to_string(), "127.0.0.1:8765".to_string());
        let after = now();
        assert_eq!(info.id, "c-1");
        assert_eq!(info.address, "127.0.0.1:8765");
        assert!(!info.authenticated, "新连接默认未鉴权");
        assert_eq!(info.connected_at, info.last_heartbeat, "初始心跳=连接时间");
        assert!(info.connected_at >= before && info.connected_at <= after);
    }

    /// update_heartbeat：把陈旧心跳刷新到当前时刻
    #[test]
    fn client_info_update_heartbeat_refreshes_timestamp() {
        let mut info = ClientInfo::new("c-2".to_string(), "addr".to_string());
        info.last_heartbeat = 0; // 制造一个「远古」心跳
        info.update_heartbeat();
        assert!(info.last_heartbeat >= now() - 5, "心跳应被刷新为当前时刻");
        // 心跳刷新不应影响连接时间与鉴权标志
        assert!(info.connected_at > 0);
        assert!(!info.authenticated);
    }

    /// 心跳超时判定（严格大于）：未超阈值不超时，超过阈值超时
    /// 注：判定内部读取当前时间，边界留 60s 安全余量避免调度抖动导致偶发失败
    #[test]
    fn client_info_heartbeat_timeout_threshold() {
        let timeout = 300;
        let mut info = ClientInfo::new("c-3".to_string(), "addr".to_string());

        // 刚更新过心跳 ⇒ 远未超时
        assert!(!info.is_heartbeat_timeout(timeout));

        // 恰在阈值内（差值 ≈ 60 < 300）⇒ 不超时
        info.last_heartbeat = now() - 60;
        assert!(!info.is_heartbeat_timeout(timeout));

        // 远超阈值（差值 ≈ 360 > 300）⇒ 超时
        info.last_heartbeat = now() - (timeout + 60);
        assert!(info.is_heartbeat_timeout(timeout));

        // timeout=0：任何历史心跳（≥1 秒前）都会判为超时
        info.last_heartbeat = now() - 5;
        assert!(info.is_heartbeat_timeout(0));
        // 刚刷新的 0 秒阈值：差值 0 ⇒ 严格大于才超时 ⇒ 不超时
        info.update_heartbeat();
        assert!(!info.is_heartbeat_timeout(0), "diff==0 时按严格大于不应超时");
    }

    /// 已鉴权客户端永不判鉴权超时（即使连接时间极旧）
    #[test]
    fn client_info_auth_timeout_skipped_when_authenticated() {
        let mut info = ClientInfo::new("c-4".to_string(), "addr".to_string());
        info.connected_at = 0; // 1970 年连接
        info.authenticated = true;
        assert!(!info.is_auth_timeout(1), "已鉴权必须直接返回 false");
    }

    /// 未鉴权时按连接时间判定：阈值内不超时，阈值外超时
    #[test]
    fn client_info_auth_timeout_threshold() {
        let timeout = 120;
        let mut info = ClientInfo::new("c-5".to_string(), "addr".to_string());
        // 刚连接 ⇒ 不超时
        assert!(!info.is_auth_timeout(timeout));
        // 连接于阈值内（差值 ≈ 60 < 120）
        info.connected_at = now() - 60;
        assert!(!info.is_auth_timeout(timeout));
        // 连接于阈值外（差值 ≈ 180 > 120）
        info.connected_at = now() - (timeout + 60);
        assert!(info.is_auth_timeout(timeout));
    }

    /// ClientInfo serde 往返（心跳事件按 JSON 广播）
    #[test]
    fn client_info_serde_round_trip() {
        let info = ClientInfo::new("c-6".to_string(), "10.0.0.2:9000".to_string());
        let json = serde_json::to_string(&info).expect("序列化应成功");
        let back: ClientInfo = serde_json::from_str(&json).expect("反序列化应成功");
        assert_eq!(back.id, info.id);
        assert_eq!(back.address, info.address);
        assert_eq!(back.connected_at, info.connected_at);
        assert_eq!(back.last_heartbeat, info.last_heartbeat);
        assert!(!back.authenticated);
    }

    // ── 配置默认值 ─────────────────────────────────────────────────────────

    /// 服务器/客户端默认配置符合约定
    #[test]
    fn config_defaults() {
        let s = WsServerConfig::default();
        assert_eq!(s.host, "127.0.0.1");
        assert_eq!(s.port, 8765);
        assert_eq!(s.max_connections, 100);

        let c = WsClientConfig::default();
        assert_eq!(c.url, "ws://127.0.0.1:8765");
        assert!(c.auto_reconnect);
        assert_eq!(c.reconnect_interval_ms, 3000);
        assert_eq!(c.max_reconnect_attempts, 0, "0 表示无限重连");
    }

    /// 连接状态枚举可比较、可拷贝
    #[test]
    fn connection_state_is_copy_and_eq() {
        let a = WsConnectionState::Connected;
        let b = a; // Copy
        assert_eq!(a, b);
        assert_ne!(WsConnectionState::Disconnected, WsConnectionState::Error);
    }
}
