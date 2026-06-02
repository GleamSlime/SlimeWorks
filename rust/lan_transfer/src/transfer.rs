use crate::discovery::DiscoveryService;
use crate::types::*;
use anyhow::{anyhow, Result};
use async_channel::{Receiver, Sender};
use chrono::Utc;
use slime_logger::{sw_error, sw_info, sw_warn};
use std::collections::HashMap;
use std::path::Path;
use std::sync::Arc;
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{oneshot, RwLock};
use tokio::task::JoinHandle;
use uuid::Uuid;

const CHUNK_SIZE: usize = 256 * 1024; // 256KB 分块
const MAX_JSON_MSG: usize = 32 * 1024 * 1024; // 32MB JSON 上限（支持超大文本）
const USER_ACCEPT_TIMEOUT_SECS: u64 = 120; // 用户响应传输请求超时（秒）

// ── 底层 I/O 帧化工具 ──────────────────────────────────────────────────────

/// 写入一帧：[4B 大端 len][payload]；len=0 表示 EOF
async fn write_frame(stream: &mut TcpStream, data: &[u8]) -> Result<()> {
    let len = data.len() as u32;
    stream.write_all(&len.to_be_bytes()).await?;
    if !data.is_empty() {
        stream.write_all(data).await?;
    }
    stream.flush().await?;
    Ok(())
}

/// 读取一帧；返回空 Vec 表示 EOF
async fn read_frame(stream: &mut TcpStream, max_size: usize) -> Result<Vec<u8>> {
    let mut len_buf = [0u8; 4];
    stream.read_exact(&mut len_buf).await?;
    let msg_len = u32::from_be_bytes(len_buf) as usize;
    if msg_len == 0 {
        return Ok(vec![]);
    }
    if msg_len > max_size {
        return Err(anyhow!("帧太大: {} 字节（最大 {}）", msg_len, max_size));
    }
    let mut buf = vec![0u8; msg_len];
    stream.read_exact(&mut buf).await?;
    Ok(buf)
}

/// 发送 JSON 序列化的 TransferMessage
async fn send_msg(stream: &mut TcpStream, msg: &TransferMessage) -> Result<()> {
    let bytes = serde_json::to_vec(msg)?;
    write_frame(stream, &bytes).await
}

/// 接收 JSON 序列化的 TransferMessage
async fn recv_msg(stream: &mut TcpStream) -> Result<TransferMessage> {
    let buf = read_frame(stream, MAX_JSON_MSG).await?;
    if buf.is_empty() {
        return Err(anyhow!("收到空消息帧（连接已关闭）"));
    }
    Ok(serde_json::from_slice(&buf)?)
}

// ── 传输服务 ───────────────────────────────────────────────────────────────

/// 传输服务
pub struct TransferService {
    port: u16,
    device_id: String,
    device_name: String,
    transfers: Arc<RwLock<HashMap<String, TransferItem>>>,
    trusted_devices: Arc<RwLock<HashMap<String, TrustedDevice>>>,
    /// 等待用户接受/拒绝的通道：transfer_id → oneshot::Sender<bool>
    pending_accept: Arc<RwLock<HashMap<String, oneshot::Sender<bool>>>>,
    /// 接收文件保存目录（由 Dart 注入 path_provider 的 documents 路径）
    save_dir: Arc<RwLock<String>>,
    event_sender: Sender<TransferEvent>,
    #[allow(dead_code)]
    event_receiver: Receiver<TransferEvent>,
    listener: Option<TcpListener>,
    listen_task: Option<JoinHandle<()>>,
    stop_signal: Option<oneshot::Sender<()>>,
}

impl TransferService {
    /// 创建新的传输服务
    pub async fn new(port: u16, device_id: String, device_name: String) -> Result<Self> {
        let listener = bind_listener_with_recovery(port).await?;
        let (event_sender, event_receiver) = async_channel::unbounded();
        let save_dir = std::env::temp_dir().to_str().unwrap_or("/tmp").to_string();
        sw_info!("传输服务已创建，端口 {}", port);
        Ok(Self {
            port,
            device_id,
            device_name,
            transfers: Arc::new(RwLock::new(HashMap::new())),
            trusted_devices: Arc::new(RwLock::new(HashMap::new())),
            pending_accept: Arc::new(RwLock::new(HashMap::new())),
            save_dir: Arc::new(RwLock::new(save_dir)),
            event_sender,
            event_receiver,
            listener: Some(listener),
            listen_task: None,
            stop_signal: None,
        })
    }

    /// 设置文件保存目录（由 Dart 注入 path_provider 的 documents 路径）
    pub async fn set_save_dir(&self, dir: String) {
        sw_info!("文件保存目录: {}", dir);
        *self.save_dir.write().await = dir;
    }

    /// 开始监听连接
    pub async fn start_listening(&mut self) -> Result<()> {
        if self.listen_task.is_some() {
            return Ok(());
        }

        let listener = self
            .listener
            .take()
            .ok_or_else(|| anyhow!("监听器不可用"))?;
        let (stop_tx, mut stop_rx) = oneshot::channel::<()>();

        let transfers = self.transfers.clone();
        let trusted_devices = self.trusted_devices.clone();
        let pending_accept = self.pending_accept.clone();
        let save_dir = self.save_dir.clone();
        let event_sender = self.event_sender.clone();
        let device_id = self.device_id.clone();
        let device_name = self.device_name.clone();
        let listen_port = self.port;

        let handle = tokio::spawn(async move {
            loop {
                tokio::select! {
                    _ = &mut stop_rx => {
                        sw_info!("传输监听器收到停止信号");
                        break;
                    }
                    result = listener.accept() => {
                        match result {
                            Ok((stream, addr)) => {
                                let transfers = transfers.clone();
                                let trusted_devices = trusted_devices.clone();
                                let pending_accept = pending_accept.clone();
                                let save_dir = save_dir.clone();
                                let event_sender = event_sender.clone();
                                let device_id = device_id.clone();
                                let device_name = device_name.clone();

                                tokio::spawn(async move {
                                    if let Err(e) = handle_connection(
                                        stream,
                                        transfers,
                                        trusted_devices,
                                        pending_accept,
                                        save_dir,
                                        event_sender,
                                        device_id,
                                        device_name,
                                        listen_port,
                                    )
                                    .await
                                    {
                                        let msg = e.to_string();
                                        if !msg.contains("connection reset")
                                            && !msg.contains("unexpected eof")
                                            && !msg.contains("broken pipe")
                                        {
                                            sw_error!("处理连接 {} 错误: {}", addr, e);
                                        }
                                    }
                                });
                            }
                            Err(e) => {
                                sw_error!("接受连接失败: {}", e);
                                tokio::time::sleep(Duration::from_millis(50)).await;
                            }
                        }
                    }
                }
            }
            sw_info!("传输监听器已停止");
        });

        self.stop_signal = Some(stop_tx);
        self.listen_task = Some(handle);

        sw_info!("已开始监听传入连接");
        Ok(())
    }

    /// 停止监听连接并释放端口
    pub async fn stop_listening(&mut self) -> Result<()> {
        if let Some(tx) = self.stop_signal.take() {
            let _ = tx.send(());
        }

        if let Some(handle) = self.listen_task.take() {
            match tokio::time::timeout(Duration::from_secs(2), handle).await {
                Ok(Ok(())) => {}
                Ok(Err(e)) => {
                    sw_warn!("传输监听任务异常: {}", e);
                }
                Err(_) => {
                    sw_warn!("等待传输监听任务超时");
                }
            }
        }

        self.listener = Some(bind_listener_with_recovery(self.port).await?);
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

        let item = TransferItem {
            transfer_id: transfer_id.clone(),
            sender_device_id: self.device_id.clone(),
            sender_device_name: self.device_name.clone(),
            receiver_device_id: target_device_id,
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

        self.transfers
            .write()
            .await
            .insert(transfer_id.clone(), item);

        Self::spawn_send(
            target_ip,
            target_port,
            request,
            None,
            self.transfers.clone(),
            self.event_sender.clone(),
            transfer_id.clone(),
        );

        Ok(transfer_id)
    }

    /// 发送文件（图片/视频/普通文件统一入口）
    pub async fn send_file(
        &self,
        target_ip: String,
        target_port: u16,
        target_device_id: String,
        file_path: String,
    ) -> Result<String> {
        let path = Path::new(&file_path);

        if !path.exists() {
            return Err(anyhow!("文件不存在: {}", file_path));
        }

        let file_name = path
            .file_name()
            .and_then(|n| n.to_str())
            .ok_or_else(|| anyhow!("无效文件名"))?
            .to_string();

        let file_size = tokio::fs::metadata(&file_path).await?.len();

        let transfer_type = if is_image(&file_name) {
            TransferType::Image
        } else if is_video(&file_name) {
            TransferType::Video
        } else {
            TransferType::File
        };

        let transfer_id = Uuid::new_v4().to_string();

        let request = TransferRequest {
            transfer_id: transfer_id.clone(),
            sender_device_id: self.device_id.clone(),
            sender_device_name: self.device_name.clone(),
            transfer_type: transfer_type.clone(),
            file_name: Some(file_name.clone()),
            file_size: Some(file_size),
            text_content: None,
        };

        let item = TransferItem {
            transfer_id: transfer_id.clone(),
            sender_device_id: self.device_id.clone(),
            sender_device_name: self.device_name.clone(),
            receiver_device_id: target_device_id,
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

        self.transfers
            .write()
            .await
            .insert(transfer_id.clone(), item);

        Self::spawn_send(
            target_ip,
            target_port,
            request,
            Some(file_path),
            self.transfers.clone(),
            self.event_sender.clone(),
            transfer_id.clone(),
        );

        Ok(transfer_id)
    }

    /// 启动异步发送任务（do_send 保持 TCP 连接直到传输完毕）
    fn spawn_send(
        target_ip: String,
        target_port: u16,
        request: TransferRequest,
        file_path: Option<String>,
        transfers: Arc<RwLock<HashMap<String, TransferItem>>>,
        event_sender: Sender<TransferEvent>,
        transfer_id: String,
    ) {
        tokio::spawn(async move {
            if let Err(e) = do_send(
                target_ip,
                target_port,
                request,
                file_path,
                transfers.clone(),
                event_sender.clone(),
            )
            .await
            {
                sw_error!("发送失败 {}: {}", transfer_id, e);
                let mut t = transfers.write().await;
                if let Some(item) = t.get_mut(&transfer_id) {
                    item.status = TransferStatus::Failed;
                    item.error_message = Some(e.to_string());
                    item.updated_at = Utc::now().to_rfc3339();
                    let _ = event_sender
                        .send(TransferEvent {
                            event_type: EventType::TransferFailed,
                            device_info: None,
                            transfer_item: Some(item.clone()),
                            message: Some(e.to_string()),
                            timestamp: Utc::now().to_rfc3339(),
                        })
                        .await;
                }
            }
        });
    }

    /// 接受传输（接收方操作）
    pub async fn accept_transfer(&self, transfer_id: String) -> Result<()> {
        // 若 handle_connection 正在等待用户操作，通过 channel 通知接受
        if let Some(tx) = self.pending_accept.write().await.remove(&transfer_id) {
            let _ = tx.send(true);
        }

        let mut t = self.transfers.write().await;
        if let Some(item) = t.get_mut(&transfer_id) {
            if item.status == TransferStatus::Pending {
                item.status = TransferStatus::Accepted;
                item.updated_at = Utc::now().to_rfc3339();
            }
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
            sw_info!("传输已接受: {}", transfer_id);
        }
        Ok(())
    }

    /// 拒绝传输（接收方操作）
    pub async fn reject_transfer(&self, transfer_id: String) -> Result<()> {
        // 通知等待中的 handle_connection 拒绝
        if let Some(tx) = self.pending_accept.write().await.remove(&transfer_id) {
            let _ = tx.send(false);
        }

        let mut t = self.transfers.write().await;
        if let Some(item) = t.get_mut(&transfer_id) {
            item.status = TransferStatus::Rejected;
            item.updated_at = Utc::now().to_rfc3339();
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
            sw_info!("传输已拒绝: {}", transfer_id);
        }
        Ok(())
    }

    /// 取消传输
    pub async fn cancel_transfer(&self, transfer_id: String) -> Result<()> {
        if let Some(tx) = self.pending_accept.write().await.remove(&transfer_id) {
            let _ = tx.send(false);
        }

        let mut t = self.transfers.write().await;
        if let Some(item) = t.get_mut(&transfer_id) {
            item.status = TransferStatus::Cancelled;
            item.updated_at = Utc::now().to_rfc3339();
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
            sw_info!("传输已取消: {}", transfer_id);
            Ok(())
        } else {
            Err(anyhow!("传输不存在: {}", transfer_id))
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
    #[allow(dead_code)]
    pub fn get_event_receiver(&self) -> Receiver<TransferEvent> {
        self.event_receiver.clone()
    }
}

async fn bind_listener_with_recovery(port: u16) -> Result<TcpListener> {
    let addr = format!("0.0.0.0:{}", port);
    match TcpListener::bind(&addr).await {
        Ok(listener) => return Ok(listener),
        Err(first_err) => {
            if first_err.kind() != std::io::ErrorKind::AddrInUse {
                return Err(anyhow!("Failed to bind to port {}: {}", port, first_err));
            }

            // 桌面端：尝试强杀占用进程后重试
            #[cfg(any(target_os = "macos", target_os = "windows", target_os = "linux"))]
            {
                if force_kill_port_process(port) {
                    sw_warn!(
                        "Port {} was occupied; killed process and retrying bind once",
                        port
                    );
                    tokio::time::sleep(Duration::from_millis(250)).await;
                    if let Ok(listener) = TcpListener::bind(&addr).await {
                        return Ok(listener);
                    }
                }
            }

            // 移动端（iOS/Android）无法 kill 进程，等待 OS 释放端口后多次重试
            // 这通常发生在 App 被杀死又快速重启时端口处于 TIME_WAIT 状态
            #[cfg(any(target_os = "ios", target_os = "android"))]
            {
                sw_warn!(
                    "Port {} in use on mobile, waiting for OS to release (TIME_WAIT)...",
                    port
                );
                let retry_delays_ms: &[u64] = &[600, 1200, 2000];
                for &delay in retry_delays_ms {
                    tokio::time::sleep(Duration::from_millis(delay)).await;
                    if let Ok(listener) = TcpListener::bind(&addr).await {
                        sw_info!("Port {} bind succeeded after {}ms delay", port, delay);
                        return Ok(listener);
                    }
                }
            }

            Err(anyhow!("Failed to bind to port {}: {}", port, first_err))
        }
    }
}

#[cfg(any(target_os = "macos", target_os = "linux"))]
fn force_kill_port_process(port: u16) -> bool {
    use std::process::Command;

    let output = match Command::new("lsof")
        .args(["-ti", &format!("tcp:{}", port)])
        .output()
    {
        Ok(output) => output,
        Err(e) => {
            sw_warn!("Failed to run lsof for port {}: {}", port, e);
            return false;
        }
    };

    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut killed_any = false;
    for pid in stdout.lines().map(str::trim).filter(|pid| !pid.is_empty()) {
        match Command::new("kill").args(["-9", pid]).status() {
            Ok(status) if status.success() => {
                killed_any = true;
                sw_info!("Killed process {} on tcp:{}", pid, port);
            }
            Ok(status) => {
                sw_warn!(
                    "Failed to kill process {} on tcp:{} (status={})",
                    pid,
                    port,
                    status
                );
            }
            Err(e) => {
                sw_warn!(
                    "Failed to execute kill for pid {} on tcp:{}: {}",
                    pid,
                    port,
                    e
                );
            }
        }
    }

    killed_any
}

#[cfg(target_os = "windows")]
fn force_kill_port_process(port: u16) -> bool {
    use std::collections::HashSet;
    use std::process::Command;

    let output = match Command::new("netstat").args(["-ano", "-p", "tcp"]).output() {
        Ok(output) => output,
        Err(e) => {
            sw_warn!("Failed to run netstat for port {}: {}", port, e);
            return false;
        }
    };

    let stdout = String::from_utf8_lossy(&output.stdout);
    let port_suffix = format!(":{}", port);
    let mut pids: HashSet<String> = HashSet::new();

    for line in stdout.lines() {
        if !line.contains(&port_suffix) || !line.contains("LISTENING") {
            continue;
        }

        let parts: Vec<&str> = line.split_whitespace().collect();
        if let Some(pid) = parts.last() {
            if !pid.is_empty() {
                pids.insert((*pid).to_string());
            }
        }
    }

    let mut killed_any = false;
    for pid in pids {
        match Command::new("taskkill").args(["/F", "/PID", &pid]).status() {
            Ok(status) if status.success() => {
                killed_any = true;
                sw_info!("Killed process {} on tcp:{}", pid, port);
            }
            Ok(status) => {
                sw_warn!(
                    "Failed to kill process {} on tcp:{} (status={})",
                    pid,
                    port,
                    status
                );
            }
            Err(e) => {
                sw_warn!(
                    "Failed to execute taskkill for pid {} on tcp:{}: {}",
                    pid,
                    port,
                    e
                );
            }
        }
    }

    killed_any
}

// ── 核心发送流程（持有 TCP 连接直到传输完毕）─────────────────────────────

/// 执行完整发送流程：建立 TCP 连接 → 发送请求 → 等待接受响应 → 发送文件 → 完成
async fn do_send(
    target_ip: String,
    target_port: u16,
    request: TransferRequest,
    file_path: Option<String>,
    transfers: Arc<RwLock<HashMap<String, TransferItem>>>,
    event_sender: Sender<TransferEvent>,
) -> Result<()> {
    let tid = request.transfer_id.clone();

    // 1. 连接（12 秒超时）
    let mut stream = tokio::time::timeout(
        Duration::from_secs(12),
        TcpStream::connect(format!("{}:{}", target_ip, target_port)),
    )
    .await
    .map_err(|_| anyhow!("连接超时"))?
    .map_err(|e| anyhow!("连接失败: {}", e))?;

    sw_info!("已连接到 {}:{}, 发送请求 {}", target_ip, target_port, tid);

    // 2. 发送 TransferRequest
    send_msg(
        &mut stream,
        &TransferMessage {
            message_type: MessageType::TransferRequest,
            payload: serde_json::to_string(&request)?,
            timestamp: Utc::now().to_rfc3339(),
        },
    )
    .await?;

    // 3. 等待 TransferResponse（最多 150 秒，接收方可能要等用户操作）
    let resp_buf = tokio::time::timeout(
        Duration::from_secs(150),
        read_frame(&mut stream, MAX_JSON_MSG),
    )
    .await
    .map_err(|_| anyhow!("等待接受响应超时（150秒）"))?
    .map_err(|e| anyhow!("读取响应失败: {}", e))?;

    if resp_buf.is_empty() {
        return Err(anyhow!("接收到空响应帧"));
    }

    let resp_msg: TransferMessage = serde_json::from_slice(&resp_buf)?;
    if !matches!(resp_msg.message_type, MessageType::TransferResponse) {
        return Err(anyhow!(
            "期望 TransferResponse，收到 {:?}",
            resp_msg.message_type
        ));
    }
    let response: TransferResponse = serde_json::from_str(&resp_msg.payload)?;

    if !response.accepted {
        let mut t = transfers.write().await;
        if let Some(item) = t.get_mut(&tid) {
            item.status = TransferStatus::Rejected;
            item.updated_at = Utc::now().to_rfc3339();
            let _ = event_sender
                .send(TransferEvent {
                    event_type: EventType::TransferRejected,
                    device_info: None,
                    transfer_item: Some(item.clone()),
                    message: None,
                    timestamp: Utc::now().to_rfc3339(),
                })
                .await;
        }
        sw_info!("传输被拒绝: {}", tid);
        return Ok(());
    }

    // 4. 已接受 → 传输中
    {
        let mut t = transfers.write().await;
        if let Some(item) = t.get_mut(&tid) {
            item.status = TransferStatus::Transferring;
            item.updated_at = Utc::now().to_rfc3339();
            let _ = event_sender
                .send(TransferEvent {
                    event_type: EventType::TransferAccepted,
                    device_info: None,
                    transfer_item: Some(item.clone()),
                    message: None,
                    timestamp: Utc::now().to_rfc3339(),
                })
                .await;
        }
    }

    // 5. 发送文件数据（仅文件/图片/视频类型）
    if let Some(fp) = file_path {
        stream_file_to(&mut stream, &fp, &tid, &transfers, &event_sender)
            .await
            .map_err(|e| anyhow!("发送文件数据失败: {}", e))?;
    }

    // 6. 发送 TransferComplete
    send_msg(
        &mut stream,
        &TransferMessage {
            message_type: MessageType::TransferComplete,
            payload: tid.clone(),
            timestamp: Utc::now().to_rfc3339(),
        },
    )
    .await?;

    // 7. 标记完成
    {
        let mut t = transfers.write().await;
        if let Some(item) = t.get_mut(&tid) {
            item.status = TransferStatus::Completed;
            item.progress = 100.0;
            item.updated_at = Utc::now().to_rfc3339();
            let _ = event_sender
                .send(TransferEvent {
                    event_type: EventType::TransferCompleted,
                    device_info: None,
                    transfer_item: Some(item.clone()),
                    message: None,
                    timestamp: Utc::now().to_rfc3339(),
                })
                .await;
        }
    }

    sw_info!("传输发送完成: {}", tid);
    Ok(())
}

// ── 接收方连接处理 ─────────────────────────────────────────────────────────

/// 处理传入连接
#[allow(clippy::too_many_arguments)]
async fn handle_connection(
    mut stream: TcpStream,
    transfers: Arc<RwLock<HashMap<String, TransferItem>>>,
    trusted_devices: Arc<RwLock<HashMap<String, TrustedDevice>>>,
    pending_accept: Arc<RwLock<HashMap<String, oneshot::Sender<bool>>>>,
    save_dir: Arc<RwLock<String>>,
    event_sender: Sender<TransferEvent>,
    device_id: String,
    device_name: String,
    listen_port: u16,
) -> Result<()> {
    // 读取第一条消息（30 秒超时）
    let msg = tokio::time::timeout(Duration::from_secs(30), recv_msg(&mut stream))
        .await
        .map_err(|_| anyhow!("等待首消息超时"))?
        .map_err(|e| anyhow!("读取消息失败: {}", e))?;

    match msg.message_type {
        // ── 心跳探测 ──────────────────────────────────────────────────────
        MessageType::Heartbeat => {
            let local_ip = stream
                .local_addr()
                .map(|a| a.ip().to_string())
                .unwrap_or_else(|_| "127.0.0.1".to_string());

            let response_device = DeviceInfo {
                device_id,
                device_name,
                device_type: DiscoveryService::get_device_type(),
                ip_address: local_ip,
                port: listen_port,
                discovered_at: Utc::now().to_rfc3339(),
                is_online: true,
            };
            send_msg(
                &mut stream,
                &TransferMessage {
                    message_type: MessageType::Heartbeat,
                    payload: serde_json::to_string(&response_device)?,
                    timestamp: Utc::now().to_rfc3339(),
                },
            )
            .await?;
        }

        // ── 传输请求 ───────────────────────────────────────────────────────
        MessageType::TransferRequest => {
            let request: TransferRequest = serde_json::from_str(&msg.payload)?;
            let tid = request.transfer_id.clone();
            let is_trusted = trusted_devices
                .read()
                .await
                .contains_key(&request.sender_device_id);

            // 初始化接收方传输记录
            let initial_status = if is_trusted {
                TransferStatus::Accepted
            } else {
                TransferStatus::Pending
            };

            let transfer_item = TransferItem {
                transfer_id: tid.clone(),
                sender_device_id: request.sender_device_id.clone(),
                sender_device_name: request.sender_device_name.clone(),
                receiver_device_id: device_id.clone(),
                transfer_type: request.transfer_type.clone(),
                file_name: request.file_name.clone(),
                file_size: request.file_size,
                text_content: request.text_content.clone(),
                file_path: None,
                status: initial_status,
                progress: 0.0,
                created_at: Utc::now().to_rfc3339(),
                updated_at: Utc::now().to_rfc3339(),
                error_message: None,
            };

            transfers
                .write()
                .await
                .insert(tid.clone(), transfer_item.clone());

            // 判断是否接受
            let accepted = if is_trusted {
                sw_info!(
                    "信任设备自动接受: {} from {}",
                    tid,
                    request.sender_device_name
                );
                let _ = event_sender
                    .send(TransferEvent {
                        event_type: EventType::TransferAccepted,
                        device_info: None,
                        transfer_item: Some(transfer_item.clone()),
                        message: None,
                        timestamp: Utc::now().to_rfc3339(),
                    })
                    .await;
                true
            } else {
                // 发送待处理事件，等待用户操作
                let _ = event_sender
                    .send(TransferEvent {
                        event_type: EventType::TransferRequestReceived,
                        device_info: None,
                        transfer_item: Some(transfer_item.clone()),
                        message: None,
                        timestamp: Utc::now().to_rfc3339(),
                    })
                    .await;

                let (accept_tx, accept_rx) = oneshot::channel::<bool>();
                pending_accept.write().await.insert(tid.clone(), accept_tx);

                match tokio::time::timeout(Duration::from_secs(USER_ACCEPT_TIMEOUT_SECS), accept_rx)
                    .await
                {
                    Ok(Ok(v)) => {
                        sw_info!("用户{}传输 {}", if v { "接受" } else { "拒绝" }, tid);
                        v
                    }
                    _ => {
                        sw_info!("传输请求超时自动拒绝: {}", tid);
                        pending_accept.write().await.remove(&tid);
                        false
                    }
                }
            };

            // 回应发送方（同一 TCP 连接）
            let response = TransferResponse {
                transfer_id: tid.clone(),
                accepted,
                receiver_device_id: device_id.clone(),
            };
            send_msg(
                &mut stream,
                &TransferMessage {
                    message_type: MessageType::TransferResponse,
                    payload: serde_json::to_string(&response)?,
                    timestamp: Utc::now().to_rfc3339(),
                },
            )
            .await?;

            if !accepted {
                let mut t = transfers.write().await;
                if let Some(item) = t.get_mut(&tid) {
                    item.status = TransferStatus::Rejected;
                    item.updated_at = Utc::now().to_rfc3339();
                    let _ = event_sender
                        .send(TransferEvent {
                            event_type: EventType::TransferRejected,
                            device_info: None,
                            transfer_item: Some(item.clone()),
                            message: None,
                            timestamp: Utc::now().to_rfc3339(),
                        })
                        .await;
                }
                return Ok(());
            }

            // 更新为传输中
            {
                let mut t = transfers.write().await;
                if let Some(item) = t.get_mut(&tid) {
                    item.status = TransferStatus::Transferring;
                    item.updated_at = Utc::now().to_rfc3339();
                }
            }

            // 接收文件数据（仅文件/图片/视频类型）
            let is_file_transfer = matches!(
                request.transfer_type,
                TransferType::File | TransferType::Image | TransferType::Video
            );

            let saved_path = if is_file_transfer {
                if let Some(file_name) = &request.file_name {
                    let dir = save_dir.read().await.clone();
                    let save_path = format!("{}/{}", dir, file_name);
                    match receive_file_from_stream(
                        &mut stream,
                        &save_path,
                        &tid,
                        request.file_size,
                        &transfers,
                        &event_sender,
                    )
                    .await
                    {
                        Ok(()) => Some(save_path),
                        Err(e) => {
                            sw_error!("接收文件失败 {}: {}", tid, e);
                            let mut t = transfers.write().await;
                            if let Some(item) = t.get_mut(&tid) {
                                item.status = TransferStatus::Failed;
                                item.error_message = Some(e.to_string());
                                item.updated_at = Utc::now().to_rfc3339();
                            }
                            return Err(e);
                        }
                    }
                } else {
                    None
                }
            } else {
                None
            };

            // 等待发送方的 TransferComplete 消息（30 秒）
            let _ = tokio::time::timeout(Duration::from_secs(30), recv_msg(&mut stream)).await;

            // 标记完成
            {
                let mut t = transfers.write().await;
                if let Some(item) = t.get_mut(&tid) {
                    item.status = TransferStatus::Completed;
                    item.progress = 100.0;
                    item.updated_at = Utc::now().to_rfc3339();
                    if let Some(path) = saved_path {
                        item.file_path = Some(path);
                    }
                    let _ = event_sender
                        .send(TransferEvent {
                            event_type: EventType::TransferCompleted,
                            device_info: None,
                            transfer_item: Some(item.clone()),
                            message: None,
                            timestamp: Utc::now().to_rfc3339(),
                        })
                        .await;
                }
            }

            sw_info!("传输接收完成: {}", tid);
        }

        _ => {
            sw_warn!("未处理的消息类型: {:?}", msg.message_type);
        }
    }

    Ok(())
}

// ── 文件流式传输工具 ────────────────────────────────────────────────────────

/// 将本地文件流式发送到 stream（EOF 后发送 0 长度帧）
async fn stream_file_to(
    stream: &mut TcpStream,
    file_path: &str,
    transfer_id: &str,
    transfers: &Arc<RwLock<HashMap<String, TransferItem>>>,
    _event_sender: &Sender<TransferEvent>,
) -> Result<()> {
    use tokio::fs::File;
    let mut file = File::open(file_path)
        .await
        .map_err(|e| anyhow!("打开文件失败 {}: {}", file_path, e))?;
    let total_size = tokio::fs::metadata(file_path)
        .await
        .map(|m| m.len())
        .unwrap_or(0);
    let mut buf = vec![0u8; CHUNK_SIZE];
    let mut bytes_sent: u64 = 0;
    let mut last_update = std::time::Instant::now();

    loop {
        let n = file.read(&mut buf).await?;
        if n == 0 {
            break;
        }
        write_frame(stream, &buf[..n]).await?;
        bytes_sent += n as u64;

        // 每 500ms 更新一次进度
        if last_update.elapsed().as_millis() >= 500 || bytes_sent == total_size {
            let progress = if total_size > 0 {
                (bytes_sent as f64 / total_size as f64 * 100.0).min(99.0)
            } else {
                50.0
            };
            let mut t = transfers.write().await;
            if let Some(item) = t.get_mut(transfer_id) {
                item.progress = progress;
                item.updated_at = Utc::now().to_rfc3339();
            }
            drop(t);
            last_update = std::time::Instant::now();
        }
    }

    // 发送 EOF 标记（长度为 0 的帧）
    write_frame(stream, &[]).await?;
    sw_info!("文件流发送完成: {} ({} bytes)", file_path, bytes_sent);
    Ok(())
}

/// 从 stream 接收文件数据并保存到磁盘
async fn receive_file_from_stream(
    stream: &mut TcpStream,
    save_path: &str,
    transfer_id: &str,
    file_size: Option<u64>,
    transfers: &Arc<RwLock<HashMap<String, TransferItem>>>,
    _event_sender: &Sender<TransferEvent>,
) -> Result<()> {
    use tokio::fs::File;
    if let Some(parent) = Path::new(save_path).parent() {
        tokio::fs::create_dir_all(parent).await?;
    }
    let mut file = File::create(save_path)
        .await
        .map_err(|e| anyhow!("创建文件失败 {}: {}", save_path, e))?;
    let mut bytes_received: u64 = 0;
    let mut last_update = std::time::Instant::now();

    loop {
        // 每帧最大 CHUNK_SIZE + 4KB 余量
        let chunk = read_frame(stream, CHUNK_SIZE + 4096).await?;
        if chunk.is_empty() {
            break; // EOF 标记
        }
        file.write_all(&chunk).await?;
        bytes_received += chunk.len() as u64;

        if last_update.elapsed().as_millis() >= 500 {
            let progress = if let Some(total) = file_size {
                if total > 0 {
                    (bytes_received as f64 / total as f64 * 100.0).min(99.0)
                } else {
                    50.0
                }
            } else {
                50.0
            };
            let mut t = transfers.write().await;
            if let Some(item) = t.get_mut(transfer_id) {
                item.progress = progress;
                item.updated_at = Utc::now().to_rfc3339();
            }
            drop(t);
            last_update = std::time::Instant::now();
        }
    }

    file.flush().await?;
    sw_info!("文件接收完成: {} ({} bytes)", save_path, bytes_received);
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
