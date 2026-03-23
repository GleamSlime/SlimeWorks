use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// 设备信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceInfo {
    /// 设备唯一ID
    pub device_id: String,
    /// 设备名称
    pub device_name: String,
    /// 设备类型（Windows/MacOS/iOS/Android）
    pub device_type: String,
    /// IP地址
    pub ip_address: String,
    /// 端口
    pub port: u16,
    /// 发现时间
    pub discovered_at: String,
    /// 是否在线
    pub is_online: bool,
}

/// 传输类型
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum TransferType {
    File,
    Text,
    Image,
    Video,
}

/// 传输状态
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum TransferStatus {
    Pending,      // 等待接受
    Accepted,     // 已接受
    Rejected,     // 已拒绝
    Transferring, // 传输中
    Completed,    // 已完成
    Failed,       // 失败
    Cancelled,    // 已取消
}

/// 传输项
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransferItem {
    /// 传输ID
    pub transfer_id: String,
    /// 发送方设备ID
    pub sender_device_id: String,
    /// 发送方设备名称
    pub sender_device_name: String,
    /// 接收方设备ID
    pub receiver_device_id: String,
    /// 传输类型
    pub transfer_type: TransferType,
    /// 文件名（仅文件传输）
    pub file_name: Option<String>,
    /// 文件大小（字节）
    pub file_size: Option<u64>,
    /// 文本内容（仅文本传输）
    pub text_content: Option<String>,
    /// 文件路径（仅文件传输）
    pub file_path: Option<String>,
    /// 传输状态
    pub status: TransferStatus,
    /// 传输进度（0-100）
    pub progress: f64,
    /// 创建时间
    pub created_at: String,
    /// 更新时间
    pub updated_at: String,
    /// 错误信息
    pub error_message: Option<String>,
}

/// 信任设备
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrustedDevice {
    pub device_id: String,
    pub device_name: String,
    pub trusted_at: String,
}

/// 消息类型
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum MessageType {
    /// 设备发现广播
    DeviceAnnouncement,
    /// 传输请求
    TransferRequest,
    /// 传输响应
    TransferResponse,
    /// 传输数据
    TransferData,
    /// 传输完成
    TransferComplete,
    /// 传输取消
    TransferCancel,
    /// 心跳
    Heartbeat,
}

/// 传输消息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransferMessage {
    pub message_type: MessageType,
    pub payload: String,
    pub timestamp: String,
}

/// 传输请求数据
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransferRequest {
    pub transfer_id: String,
    pub sender_device_id: String,
    pub sender_device_name: String,
    pub transfer_type: TransferType,
    pub file_name: Option<String>,
    pub file_size: Option<u64>,
    pub text_content: Option<String>,
}

/// 传输响应数据
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransferResponse {
    pub transfer_id: String,
    pub accepted: bool,
    pub receiver_device_id: String,
}

/// 传输数据块
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransferDataChunk {
    pub transfer_id: String,
    pub chunk_index: u64,
    pub total_chunks: u64,
    pub data: Vec<u8>,
}

/// 心跳探测载荷（用于主动发现）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HeartbeatPayload {
    pub device_id: String,
    pub device_name: String,
    pub device_type: String,
    pub port: u16,
}

/// 事件类型
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum EventType {
    DeviceDiscovered,
    DeviceLost,
    TransferRequestReceived,
    TransferAccepted,
    TransferRejected,
    TransferProgress,
    TransferCompleted,
    TransferFailed,
    TransferCancelled,
}

/// 传输事件
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransferEvent {
    pub event_type: EventType,
    pub device_info: Option<DeviceInfo>,
    pub transfer_item: Option<TransferItem>,
    pub message: Option<String>,
    pub timestamp: String,
}
