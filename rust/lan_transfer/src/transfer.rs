use crate::types::*;
use anyhow::{anyhow, Result};
use async_channel::{Receiver, Sender};
use chrono::Utc;
use log::{debug, error, info, warn};
use serde_json;
use std::collections::HashMap;
use std::path::Path;
use std::sync::Arc;
use tokio::fs::File;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::RwLock;
use uuid::Uuid;

const CHUNK_SIZE: usize = 64 * 1024; // 64KB chunks
const MAX_MESSAGE_SIZE: usize = 10 * 1024 * 1024; // 10MB max message

/// 传输服务
pub struct TransferService {
    port: u16,
    device_id: String,
    device_name: String,
    transfers: Arc<RwLock<HashMap<String, TransferItem>>>,
    trusted_devices: Arc<RwLock<HashMap<String, TrustedDevice>>>,
    event_sender: Sender<TransferEvent>,
    event_receiver: Receiver<TransferEvent>,
    listener: Option<TcpListener>,
}

impl TransferService {
    /// 创建新的传输服务
    pub async fn new(port: u16, device_id: String, device_name: String) -> Result<Self> {
        let listener = TcpListener::bind(format!("0.0.0.0:{}", port))
            .await
            .map_err(|e| anyhow!("Failed to bind to port {}: {}", port, e))?;

        let (event_sender, event_receiver) = async_channel::unbounded();

        info!("Transfer service listening on port {}", port);

        Ok(Self {
            port,
            device_id,
            device_name,
            transfers: Arc::new(RwLock::new(HashMap::new())),
            trusted_devices: Arc::new(RwLock::new(HashMap::new())),
            event_sender,
            event_receiver,
            listener: Some(listener),
        })
    }

    /// 开始监听连接
    pub async fn start_listening(&mut self) -> Result<()> {
        let listener = self
            .listener
            .take()
            .ok_or_else(|| anyhow!("Listener already taken"))?;

        let transfers = self.transfers.clone();
        let trusted_devices = self.trusted_devices.clone();
        let event_sender = self.event_sender.clone();
        let device_id = self.device_id.clone();

        tokio::spawn(async move {
            loop {
                match listener.accept().await {
                    Ok((stream, addr)) => {
                        debug!("New connection from: {}", addr);
                        let transfers = transfers.clone();
                        let trusted_devices = trusted_devices.clone();
                        let event_sender = event_sender.clone();
                        let device_id = device_id.clone();

                        tokio::spawn(async move {
                            if let Err(e) = handle_connection(
                                stream,
                                transfers,
                                trusted_devices,
                                event_sender,
                                device_id,
                            )
                            .await
                            {
                                error!("Error handling connection: {}", e);
                            }
                        });
                    }
                    Err(e) => {
                        error!("Failed to accept connection: {}", e);
                    }
                }
            }
        });

        info!("Started listening for incoming transfers");
        Ok(())
    }

    /// 发送文本消息
    pub async fn send_text(
        &self,
        target_ip: String,
        target_port: u16,
        target_device_id: String,
        text: String,
    ) -> Result<String> {
        let transfer_id = Uuid::new_v4().to_string();

        let request = TransferRequest {
            transfer_id: transfer_id.clone(),
            sender_device_id: self.device_id.clone(),
            sender_device_name: self.device_name.clone(),
            transfer_type: TransferType::Text,
            file_name: None,
            file_size: None,
            text_content: Some(text.clone()),
        };

        let transfer_item = TransferItem {
            transfer_id: transfer_id.clone(),
            sender_device_id: self.device_id.clone(),
            sender_device_name: self.device_name.clone(),
            receiver_device_id: target_device_id.clone(),
            transfer_type: TransferType::Text,
            file_name: None,
            file_size: None,
            text_content: Some(text),
            file_path: None,
            status: TransferStatus::Pending,
            progress: 0.0,
            created_at: Utc::now().to_rfc3339(),
            updated_at: Utc::now().to_rfc3339(),
            error_message: None,
        };

        // 保存传输项
        self.transfers
            .write()
            .await
            .insert(transfer_id.clone(), transfer_item.clone());

        // 连接并发送请求
        let transfers = self.transfers.clone();
        let event_sender = self.event_sender.clone();
        let tid = transfer_id.clone();

        tokio::spawn(async move {
            if let Err(e) = send_transfer_request(
                target_ip,
                target_port,
                request,
                transfers.clone(),
                event_sender.clone(),
            )
            .await
            {
                error!("Failed to send text: {}", e);

                // 更新状态为失败
                if let Some(item) = transfers.write().await.get_mut(&tid) {
                    item.status = TransferStatus::Failed;
                    item.error_message = Some(e.to_string());
                    item.updated_at = Utc::now().to_rfc3339();
                }
            }
        });

        Ok(transfer_id)
    }

    /// 发送文件
    pub async fn send_file(
        &self,
        target_ip: String,
        target_port: u16,
        target_device_id: String,
        file_path: String,
    ) -> Result<String> {
        let transfer_id = Uuid::new_v4().to_string();
        let path = Path::new(&file_path);

        if !path.exists() {
            return Err(anyhow!("File does not exist: {}", file_path));
        }

        let file_name = path
            .file_name()
            .and_then(|n| n.to_str())
            .ok_or_else(|| anyhow!("Invalid file name"))?
            .to_string();

        let metadata = tokio::fs::metadata(&file_path).await?;
        let file_size = metadata.len();

        // 判断文件类型
        let transfer_type = if is_image(&file_name) {
            TransferType::Image
        } else if is_video(&file_name) {
            TransferType::Video
        } else {
            TransferType::File
        };

        let request = TransferRequest {
            transfer_id: transfer_id.clone(),
            sender_device_id: self.device_id.clone(),
            sender_device_name: self.device_name.clone(),
            transfer_type: transfer_type.clone(),
            file_name: Some(file_name.clone()),
            file_size: Some(file_size),
            text_content: None,
        };

        let transfer_item = TransferItem {
            transfer_id: transfer_id.clone(),
            sender_device_id: self.device_id.clone(),
            sender_device_name: self.device_name.clone(),
            receiver_device_id: target_device_id.clone(),
            transfer_type,
            file_name: Some(file_name),
            file_size: Some(file_size),
            text_content: None,
            file_path: Some(file_path.clone()),
            status: TransferStatus::Pending,
            progress: 0.0,
            created_at: Utc::now().to_rfc3339(),
            updated_at: Utc::now().to_rfc3339(),
            error_message: None,
        };

        // 保存传输项
        self.transfers
            .write()
            .await
            .insert(transfer_id.clone(), transfer_item.clone());

        // 连接并发送请求
        let transfers = self.transfers.clone();
        let event_sender = self.event_sender.clone();
        let tid = transfer_id.clone();

        tokio::spawn(async move {
            if let Err(e) = send_transfer_request(
                target_ip,
                target_port,
                request,
                transfers.clone(),
                event_sender.clone(),
            )
            .await
            {
                error!("Failed to send file: {}", e);

                // 更新状态为失败
                if let Some(item) = transfers.write().await.get_mut(&tid) {
                    item.status = TransferStatus::Failed;
                    item.error_message = Some(e.to_string());
                    item.updated_at = Utc::now().to_rfc3339();
                }
            } else {
                // 等待响应后开始传输文件
                // 这里简化处理，实际应该等待accept响应
                tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;

                if let Some(item) = transfers.read().await.get(&tid) {
                    if item.status == TransferStatus::Accepted {
                        // 重新连接并发送文件数据
                        // 这里需要实现文件分块传输
                    }
                }
            }
        });

        Ok(transfer_id)
    }

    /// 接受传输
    pub async fn accept_transfer(&self, transfer_id: String) -> Result<()> {
        let mut transfers = self.transfers.write().await;

        if let Some(item) = transfers.get_mut(&transfer_id) {
            item.status = TransferStatus::Accepted;
            item.updated_at = Utc::now().to_rfc3339();

            // 发送事件
            let _ = self
                .event_sender
                .send(TransferEvent {
                    event_type: EventType::TransferAccepted,
                    device_info: None,
                    transfer_item: Some(item.clone()),
                    message: None,
                    timestamp: Utc::now().to_rfc3339(),
                })
                .await;

            info!("Transfer accepted: {}", transfer_id);
            Ok(())
        } else {
            Err(anyhow!("Transfer not found: {}", transfer_id))
        }
    }

    /// 拒绝传输
    pub async fn reject_transfer(&self, transfer_id: String) -> Result<()> {
        let mut transfers = self.transfers.write().await;

        if let Some(item) = transfers.get_mut(&transfer_id) {
            item.status = TransferStatus::Rejected;
            item.updated_at = Utc::now().to_rfc3339();

            // 发送事件
            let _ = self
                .event_sender
                .send(TransferEvent {
                    event_type: EventType::TransferRejected,
                    device_info: None,
                    transfer_item: Some(item.clone()),
                    message: None,
                    timestamp: Utc::now().to_rfc3339(),
                })
                .await;

            info!("Transfer rejected: {}", transfer_id);
            Ok(())
        } else {
            Err(anyhow!("Transfer not found: {}", transfer_id))
        }
    }

    /// 取消传输
    pub async fn cancel_transfer(&self, transfer_id: String) -> Result<()> {
        let mut transfers = self.transfers.write().await;

        if let Some(item) = transfers.get_mut(&transfer_id) {
            item.status = TransferStatus::Cancelled;
            item.updated_at = Utc::now().to_rfc3339();

            // 发送事件
            let _ = self
                .event_sender
                .send(TransferEvent {
                    event_type: EventType::TransferCancelled,
                    device_info: None,
                    transfer_item: Some(item.clone()),
                    message: None,
                    timestamp: Utc::now().to_rfc3339(),
                })
                .await;

            info!("Transfer cancelled: {}", transfer_id);
            Ok(())
        } else {
            Err(anyhow!("Transfer not found: {}", transfer_id))
        }
    }

    /// 获取所有传输记录
    pub async fn get_transfers(&self) -> Vec<TransferItem> {
        self.transfers.read().await.values().cloned().collect()
    }

    /// 添加信任设备
    pub async fn add_trusted_device(&self, device_id: String, device_name: String) -> Result<()> {
        let trusted = TrustedDevice {
            device_id: device_id.clone(),
            device_name,
            trusted_at: Utc::now().to_rfc3339(),
        };

        self.trusted_devices
            .write()
            .await
            .insert(device_id, trusted);
        Ok(())
    }

    /// 移除信任设备
    pub async fn remove_trusted_device(&self, device_id: String) -> Result<()> {
        self.trusted_devices.write().await.remove(&device_id);
        Ok(())
    }

    /// 检查是否为信任设备
    pub async fn is_trusted_device(&self, device_id: &str) -> bool {
        self.trusted_devices.read().await.contains_key(device_id)
    }

    /// 获取信任设备列表
    pub async fn get_trusted_devices(&self) -> Vec<TrustedDevice> {
        self.trusted_devices
            .read()
            .await
            .values()
            .cloned()
            .collect()
    }

    /// 获取事件接收器
    pub fn get_event_receiver(&self) -> Receiver<TransferEvent> {
        self.event_receiver.clone()
    }
}

/// 处理传入连接
async fn handle_connection(
    mut stream: TcpStream,
    transfers: Arc<RwLock<HashMap<String, TransferItem>>>,
    trusted_devices: Arc<RwLock<HashMap<String, TrustedDevice>>>,
    event_sender: Sender<TransferEvent>,
    device_id: String,
) -> Result<()> {
    // 读取消息长度（4字节）
    let mut len_buf = [0u8; 4];
    stream.read_exact(&mut len_buf).await?;
    let msg_len = u32::from_be_bytes(len_buf) as usize;

    if msg_len > MAX_MESSAGE_SIZE {
        return Err(anyhow!("Message too large: {} bytes", msg_len));
    }

    // 读取消息内容
    let mut msg_buf = vec![0u8; msg_len];
    stream.read_exact(&mut msg_buf).await?;

    let msg_str = String::from_utf8(msg_buf)?;
    let message: TransferMessage = serde_json::from_str(&msg_str)?;

    match message.message_type {
        MessageType::TransferRequest => {
            let request: TransferRequest = serde_json::from_str(&message.payload)?;

            let transfer_item = TransferItem {
                transfer_id: request.transfer_id.clone(),
                sender_device_id: request.sender_device_id.clone(),
                sender_device_name: request.sender_device_name.clone(),
                receiver_device_id: device_id,
                transfer_type: request.transfer_type.clone(),
                file_name: request.file_name.clone(),
                file_size: request.file_size,
                text_content: request.text_content.clone(),
                file_path: None,
                status: TransferStatus::Pending,
                progress: 0.0,
                created_at: Utc::now().to_rfc3339(),
                updated_at: Utc::now().to_rfc3339(),
                error_message: None,
            };

            // 保存传输项
            transfers
                .write()
                .await
                .insert(request.transfer_id.clone(), transfer_item.clone());

            // 发送事件
            let _ = event_sender
                .send(TransferEvent {
                    event_type: EventType::TransferRequestReceived,
                    device_info: None,
                    transfer_item: Some(transfer_item),
                    message: None,
                    timestamp: Utc::now().to_rfc3339(),
                })
                .await;

            info!("Received transfer request: {}", request.transfer_id);
        }
        _ => {
            warn!("Unhandled message type: {:?}", message.message_type);
        }
    }

    Ok(())
}

/// 发送传输请求
async fn send_transfer_request(
    target_ip: String,
    target_port: u16,
    request: TransferRequest,
    transfers: Arc<RwLock<HashMap<String, TransferItem>>>,
    event_sender: Sender<TransferEvent>,
) -> Result<()> {
    let mut stream = TcpStream::connect(format!("{}:{}", target_ip, target_port)).await?;

    let message = TransferMessage {
        message_type: MessageType::TransferRequest,
        payload: serde_json::to_string(&request)?,
        timestamp: Utc::now().to_rfc3339(),
    };

    let msg_bytes = serde_json::to_vec(&message)?;
    let msg_len = msg_bytes.len() as u32;

    // 发送消息长度
    stream.write_all(&msg_len.to_be_bytes()).await?;
    // 发送消息内容
    stream.write_all(&msg_bytes).await?;
    stream.flush().await?;

    info!("Sent transfer request: {}", request.transfer_id);
    Ok(())
}

/// 判断是否为图片文件
fn is_image(filename: &str) -> bool {
    let ext = filename.rsplit('.').next().unwrap_or("").to_lowercase();
    matches!(
        ext.as_str(),
        "jpg" | "jpeg" | "png" | "gif" | "bmp" | "webp" | "svg"
    )
}

/// 判断是否为视频文件
fn is_video(filename: &str) -> bool {
    let ext = filename.rsplit('.').next().unwrap_or("").to_lowercase();
    matches!(
        ext.as_str(),
        "mp4" | "avi" | "mkv" | "mov" | "wmv" | "flv" | "webm"
    )
}
