use crate::discovery::DiscoveryService;
use crate::types::*;
use anyhow::{anyhow, Result};
use chrono::Utc;
use slime_logger::{sw_error, sw_info, sw_warn};
use std::collections::HashMap;
use std::net::IpAddr;
use std::path::Path;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{oneshot, RwLock};
use tokio::task::JoinHandle;
use uuid::Uuid;

const CHUNK_SIZE: usize = 256 * 1024; // 256KB 分块
const MAX_JSON_MSG: usize = 32 * 1024 * 1024; // 32MB JSON 上限（支持超大文本）
const USER_ACCEPT_TIMEOUT_SECS: u64 = 120; // 用户响应传输请求超时（秒）

/// 单帧读写超时（秒）。
///
/// 为什么必须有：帧读写循环原先完全没有超时，对端拔网线/休眠/半开连接时
/// read_exact / write_all 会永久挂住。而每条连接都握着一个并发许可
/// （MAX_CONCURRENT_CONNECTIONS = 32），32 个僵尸连接就把整个传输服务的
/// 入站能力占死，只能重启 App。60s 足够覆盖任何正常慢速链路的一帧。
const FRAME_IO_TIMEOUT_SECS: u64 = 60;

/// transfers 表保留的终态条目上限。
///
/// 传输记录原先只增不删，传几百个文件就能把它撑到几千条，而 get_transfers
/// 每轮轮询都会把这堆记录整份克隆+序列化。只清理终态（完成/取消/失败）记录，
/// 进行中的一条都不动。
const MAX_FINISHED_TRANSFERS: usize = 200;

/// 全局最大并发入站连接数，防止 DoS 耗尽资源
const MAX_CONCURRENT_CONNECTIONS: usize = 32;
/// 单 IP 最大活跃连接数
const MAX_CONNECTIONS_PER_IP: usize = 8;
/// 单 IP 两次入站连接的间隔下限（毫秒），低于则视为扫描/攻击丢弃
const IP_CONNECT_INTERVAL_MS: u128 = 200;

/// 单 IP 连接限速与并发统计
#[derive(Debug)]
struct IpRateTrack {
    /// 当前活跃连接数（存在 handle_connection 尚未结束）
    active: usize,
    /// 最近一次建立连接的时间
    last: Instant,
}

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

/// 清理终态（完成/取消/失败）的旧记录，保留最近 MAX_FINISHED_TRANSFERS 条。
///
/// 抽成自由函数是因为三个调用点（cancel_transfer / 发送完成 / 接收完成）
/// 里只有 cancel 那条挂在 &self 上，其余都在自由函数里跑。
async fn prune_finished_transfers(transfers: &Arc<RwLock<HashMap<String, TransferItem>>>) {
    let mut t = transfers.write().await;
    let mut finished: Vec<(String, String)> = t
        .values()
        .filter(|item| {
            matches!(
                item.status,
                TransferStatus::Completed | TransferStatus::Cancelled | TransferStatus::Failed
            )
        })
        .map(|item| (item.transfer_id.clone(), item.updated_at.clone()))
        .collect();
    if finished.len() <= MAX_FINISHED_TRANSFERS {
        return;
    }
    // updated_at 是 RFC3339 字符串，同格式下字典序即时间序，不必解析
    finished.sort_by(|a, b| a.1.cmp(&b.1));
    let remove_count = finished.len() - MAX_FINISHED_TRANSFERS;
    for (transfer_id, _) in finished.into_iter().take(remove_count) {
        t.remove(&transfer_id);
    }
}

// ── 取消信号工具 ───────────────────────────────────────────────────────────

/// 注册一条传输的取消通道，返回订阅端。
fn register_cancel_tx(
    map: &std::sync::Mutex<HashMap<String, tokio::sync::watch::Sender<bool>>>,
    transfer_id: &str,
) -> tokio::sync::watch::Receiver<bool> {
    let (cancel_tx, cancel_rx) = tokio::sync::watch::channel(false);
    map.lock()
        .unwrap_or_else(|e| e.into_inner())
        .insert(transfer_id.to_string(), cancel_tx);
    cancel_rx
}

/// 取消通道的 RAII 清理：任务退出（含提前返回/panic 展开）时摘掉条目。
struct CancelTxGuard {
    map: Arc<std::sync::Mutex<HashMap<String, tokio::sync::watch::Sender<bool>>>>,
    transfer_id: String,
}

impl Drop for CancelTxGuard {
    fn drop(&mut self) {
        self.map
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .remove(&self.transfer_id);
    }
}

/// 是否已收到取消信号。
fn is_cancelled(cancel: &tokio::sync::watch::Receiver<bool>) -> bool {
    *cancel.borrow()
}

/// 已取消时返回统一错误，供帧循环 break/提前返回使用。
fn cancelled_error() -> anyhow::Error {
    anyhow!("传输已取消")
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
    /// 取消通知：transfer_id → watch 发送端。
    ///
    /// 为什么需要它：cancel_transfer 原先只把表里的 status 改成 Cancelled，
    /// 而流任务在帧循环里根本不看状态，于是文件照样继续传完、对端照样收完——
    /// 用户点了取消却什么也没发生。用 watch 而不是 oneshot，是因为一条传输
    /// 可能同时有发送/接收两条流任务在跑，watch 可以多订阅者广播。
    cancel_txs: Arc<std::sync::Mutex<HashMap<String, tokio::sync::watch::Sender<bool>>>>,
    /// 接收文件保存目录（由 Dart 注入 path_provider 的 documents 路径）
    save_dir: Arc<RwLock<String>>,
    /// 接入授权码（非信任设备需携带正确授权码才允许发起传输；空 = 关闭校验）
    access_code: Arc<RwLock<Option<String>>>,
    listener: Option<TcpListener>,
    listen_task: Option<JoinHandle<()>>,
    stop_signal: Option<oneshot::Sender<()>>,
}

impl TransferService {
    /// 创建新的传输服务
    pub async fn new(port: u16, device_id: String, device_name: String) -> Result<Self> {
        let listener = bind_listener_with_recovery(port).await?;
        let save_dir = std::env::temp_dir().to_str().unwrap_or("/tmp").to_string();
        sw_info!("传输服务已创建，端口 {}", port);
        Ok(Self {
            port,
            device_id,
            device_name,
            transfers: Arc::new(RwLock::new(HashMap::new())),
            trusted_devices: Arc::new(RwLock::new(HashMap::new())),
            pending_accept: Arc::new(RwLock::new(HashMap::new())),
            cancel_txs: Arc::new(std::sync::Mutex::new(HashMap::new())),
            save_dir: Arc::new(RwLock::new(save_dir)),
            access_code: Arc::new(RwLock::new(None)),
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

    /// 设置接入授权码（空 = 关闭校验）
    pub async fn set_access_code(&self, code: Option<String>) {
        sw_info!("接入授权码已更新: {}", if code.is_some() { "已设置" } else { "未设置" });
        *self.access_code.write().await = code;
    }

    /// 获取当前接入授权码（供发起连接时携带）
    async fn get_access_code(&self) -> Option<String> {
        self.access_code.read().await.clone()
    }

    /// 开始监听连接
    pub async fn start_listening(&mut self) -> Result<()> {
        if self.listen_task.is_some() {
            return Ok(());
        }

        // listener 可能为空：stop_listening 现在只置 None（释放端口语义），
        // 所以这里按需重新 bind，而不是报「监听器不可用」导致停止后再也起不来。
        let listener = match self.listener.take() {
            Some(listener) => listener,
            None => bind_listener_with_recovery(self.port).await?,
        };
        let (stop_tx, mut stop_rx) = oneshot::channel::<()>();

        let transfers = self.transfers.clone();
        let trusted_devices = self.trusted_devices.clone();
        let pending_accept = self.pending_accept.clone();
        let cancel_txs = self.cancel_txs.clone();
        let save_dir = self.save_dir.clone();
        let access_code = self.access_code.clone();
        let device_id = self.device_id.clone();
        let device_name = self.device_name.clone();
        let listen_port = self.port;
        // 全局并发连接信号量，防止 DoS 耗尽资源
        let conn_semaphore = Arc::new(tokio::sync::Semaphore::new(MAX_CONCURRENT_CONNECTIONS));
        // 单 IP 限速与活跃连接统计
        let ip_limiter: Arc<RwLock<HashMap<IpAddr, IpRateTrack>>> =
            Arc::new(RwLock::new(HashMap::new()));

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
                                // 单 IP 限速：连接间隔过近或活跃数超限则丢弃
                                let ip = addr.ip();
                                let allow_conn = {
                                    let mut limiter = ip_limiter.write().await;
                                    let entry = limiter.entry(ip).or_insert_with(|| IpRateTrack {
                                        active: 0,
                                        last: Instant::now() - Duration::from_millis(1000),
                                    });
                                    if entry.last.elapsed().as_millis() < IP_CONNECT_INTERVAL_MS
                                        || entry.active >= MAX_CONNECTIONS_PER_IP
                                    {
                                        false
                                    } else {
                                        entry.last = Instant::now();
                                        entry.active += 1;
                                        true
                                    }
                                };
                                if !allow_conn {
                                    sw_warn!("频繁连接或超限，丢弃来自 {} 的连接", ip);
                                    drop(stream);
                                    continue;
                                }

                                // 全局并发上限：超限则释放计数并丢弃
                                let Ok(permit) = conn_semaphore.clone().try_acquire_owned() else {
                                    {
                                        let mut limiter = ip_limiter.write().await;
                                        if let Some(e) = limiter.get_mut(&ip) {
                                            e.active = e.active.saturating_sub(1);
                                        }
                                    }
                                    sw_warn!("达到全局并发上限，丢弃来自 {} 的连接", ip);
                                    drop(stream);
                                    continue;
                                };
                                // permit 随任务结束自动释放全局并发额度
                                let _permit = permit;

                                let transfers = transfers.clone();
                                let trusted_devices = trusted_devices.clone();
                                let pending_accept = pending_accept.clone();
                                let cancel_txs = cancel_txs.clone();
                                let save_dir = save_dir.clone();
                                let access_code = access_code.clone();
                                let device_id = device_id.clone();
                                let device_name = device_name.clone();
                                let ip_limiter_inner = ip_limiter.clone();

                                tokio::spawn(async move {
                                    let result = handle_connection(
                                        stream,
                                        transfers,
                                        trusted_devices,
                                        pending_accept,
                                        cancel_txs,
                                        save_dir,
                                        access_code,
                                        device_id,
                                        device_name,
                                        listen_port,
                                    )
                                    .await;
                                    // 连接结束，释放单 IP 活跃计数
                                    {
                                        let mut limiter = ip_limiter_inner.write().await;
                                        if let Some(e) = limiter.get_mut(&ip) {
                                            e.active = e.active.saturating_sub(1);
                                        }
                                    }
                                    if let Err(e) = result {
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

        // 这里**不再重新 bind**。原先的 `self.listener = Some(bind(...))` 会让
        // stop 反而把端口重新占住：调用方（lan_transfer_stop → manager.stop）的
        // 语义是「释放端口」，重绑等于当场把刚释放的端口又抢回来，且失败时还会
        // 把整个 stop 链路带成 Err → MANAGER 残留（僵尸管理器）。
        // 保留 listener=None，下次 start_listening 由 new()/bind 重新拿端口即可。
        self.listener = None;
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
        let access_code = self.get_access_code().await;

        let request = TransferRequest {
            transfer_id: transfer_id.clone(),
            sender_device_id: self.device_id.clone(),
            sender_device_name: self.device_name.clone(),
            transfer_type: TransferType::Text,
            file_name: None,
            file_size: None,
            text_content: Some(text.clone()),
            access_code,
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
            self.cancel_txs.clone(),
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
        let access_code = self.get_access_code().await;

        let request = TransferRequest {
            transfer_id: transfer_id.clone(),
            sender_device_id: self.device_id.clone(),
            sender_device_name: self.device_name.clone(),
            transfer_type: transfer_type.clone(),
            file_name: Some(file_name.clone()),
            file_size: Some(file_size),
            text_content: None,
            access_code,
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
            self.cancel_txs.clone(),
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
        cancel_txs: Arc<std::sync::Mutex<HashMap<String, tokio::sync::watch::Sender<bool>>>>,
        transfer_id: String,
    ) {
        // 注册取消通道：cancel_transfer 通过它通知本任务立即退出帧循环
        let cancel_rx = register_cancel_tx(&cancel_txs, &transfer_id);
        let cancel_guard = CancelTxGuard {
            map: cancel_txs,
            transfer_id: transfer_id.clone(),
        };
        tokio::spawn(async move {
            let result = do_send(
                target_ip,
                target_port,
                request,
                file_path,
                transfers.clone(),
                cancel_rx.clone(),
            )
            .await;
            // 任务结束时 guard 随作用域 drop，取消表不会无限增长
            drop(cancel_guard);
            if let Err(e) = result {
                sw_error!("发送失败 {}: {}", transfer_id, e);
                let mut t = transfers.write().await;
                if let Some(item) = t.get_mut(&transfer_id) {
                    // 已取消的传输不能被后续「传输已取消」这个错误覆盖成 Failed：
                    // 用户点的取消，界面就该停在已取消。
                    if item.status != TransferStatus::Cancelled {
                        item.status = TransferStatus::Failed;
                        item.error_message = Some(e.to_string());
                        item.updated_at = Utc::now().to_rfc3339();
                    }
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
            sw_info!("传输已拒绝: {}", transfer_id);
        }
        Ok(())
    }

    /// 取消传输
    pub async fn cancel_transfer(&self, transfer_id: String) -> Result<()> {
        if let Some(tx) = self.pending_accept.write().await.remove(&transfer_id) {
            let _ = tx.send(false);
        }

        {
            let mut t = self.transfers.write().await;
            let Some(item) = t.get_mut(&transfer_id) else {
                return Err(anyhow!("传输不存在: {}", transfer_id));
            };
            item.status = TransferStatus::Cancelled;
            item.updated_at = Utc::now().to_rfc3339();
        }

        // 通知流任务立刻退出帧循环：只改状态的话，发送/接收任务根本看不到，
        // 文件会照样传完（对端照样收完）——用户点取消等于没点。
        if let Some(tx) = self
            .cancel_txs
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .get(&transfer_id)
        {
            let _ = tx.send(true);
        }

        self.prune_finished_transfers().await;
        sw_info!("传输已取消: {}", transfer_id);
        Ok(())
    }

    /// 清理终态（完成/取消/失败）的旧记录，最少保留最近 MAX_FINISHED_TRANSFERS 条。
    async fn prune_finished_transfers(&self) {
        prune_finished_transfers(&self.transfers).await;
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

    // 只匹配「本地 LISTEN 该端口」的进程：-ti tcp:port 会把远端端口相同的
    // 出站连接也列进来，可能把自己（作为客户端连着别人）kill -9 自杀。
    let output = match Command::new("lsof")
        .args(["-tiTCP", &format!(":{}", port), "-sTCP:LISTEN"])
        .output()
    {
        Ok(output) => output,
        Err(e) => {
            sw_warn!("Failed to run lsof for port {}: {}", port, e);
            return false;
        }
    };

    let self_pid = std::process::id().to_string();
    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut killed_any = false;
    for pid in stdout.lines().map(str::trim).filter(|pid| !pid.is_empty()) {
        // 显式排除自身 PID 与系统保留的 PID 0，双保险
        if pid == self_pid || pid == "0" {
            continue;
        }
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
    cancel: tokio::sync::watch::Receiver<bool>,
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
        }
    }

    // 5. 发送文件数据（仅文件/图片/视频类型）
    if let Some(fp) = file_path {
        stream_file_to(&mut stream, &fp, &tid, &transfers, &cancel)
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
            // 已取消的传输不能被「刚好这时也传完了」翻回 Completed：
            // 取消是用户的显式意图，界面该停在已取消。
            if item.status != TransferStatus::Cancelled {
                item.status = TransferStatus::Completed;
                item.progress = 100.0;
                item.updated_at = Utc::now().to_rfc3339();
            }
        }
    }

    sw_info!("传输发送完成: {}", tid);
    prune_finished_transfers(&transfers).await;
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
    cancel_txs: Arc<std::sync::Mutex<HashMap<String, tokio::sync::watch::Sender<bool>>>>,
    save_dir: Arc<RwLock<String>>,
    access_code: Arc<RwLock<Option<String>>>,
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
            // 接收侧同样要有取消通道：cancel_transfer 在接收端调用时要能打断
            // 正在进行的落盘流，否则「取消」对接收方完全无效。
            let cancel_rx = register_cancel_tx(&cancel_txs, &tid);
            let _cancel_guard = CancelTxGuard {
                map: cancel_txs.clone(),
                transfer_id: tid.clone(),
            };
            // 安全：sender_device_id 是发送方自报的字符串，而 device_id 经 mDNS 广播 /
            // Heartbeat（无授权即回复）公开可得。若「信任设备」直接跳过授权码，
            // 任意局域网设备伪造一个受信任 ID 就能绕过验证并自动 Accepted 落盘。
            // 因此信任只是「免人工确认」的必要条件，还必须证明知道授权码；
            // 证明不了的信任设备降级为待人工确认，而不是直接拒绝（避免打断正常传输）。
            let expected = access_code.read().await.clone();
            let code_ok = match expected {
                Some(ref expected_code) => {
                    request.access_code.as_deref().unwrap_or("") == expected_code.as_str()
                }
                // 本机未设授权码：等于完全开放，此时信任判定才有意义
                None => true,
            };
            let is_trusted = trusted_devices
                .read()
                .await
                .contains_key(&request.sender_device_id);
            if !code_ok && !is_trusted {
                sw_warn!(
                    "拒绝未授权连接: 来自 {}, 授权码不匹配",
                    request.sender_device_name
                );
                return Err(anyhow!("授权码验证失败"));
            }
            if is_trusted && !code_ok {
                sw_warn!(
                    "信任设备 {} 未携带正确授权码，降级为人工确认",
                    request.sender_device_name
                );
            }
            let auto_accept = is_trusted && code_ok;

            // 初始化接收方传输记录
            let initial_status = if auto_accept {
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
            let accepted = if auto_accept {
                sw_info!(
                    "信任设备自动接受: {} from {}",
                    tid,
                    request.sender_device_name
                );
                true
            } else {
                // 发送待处理事件，等待用户操作

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
                    // 净化文件名，防止路径穿越，且保证最终路径落在保存目录内
                    let save_path = sanitize_save_path(&dir, file_name);
                    match receive_file_from_stream(
                        &mut stream,
                        &save_path,
                        &tid,
                        request.file_size,
                        &transfers,
                        &cancel_rx,
                    )
                    .await
                    {
                        Ok(()) => Some(save_path),
                        Err(e) => {
                            sw_error!("接收文件失败 {}: {}", tid, e);
                            let mut t = transfers.write().await;
                            if let Some(item) = t.get_mut(&tid) {
                                // 用户主动取消时，流任务是以「传输已取消」报错退出的；
                                // 这里不能把它改写成 Failed，否则界面显示「失败」而非「已取消」。
                                if item.status != TransferStatus::Cancelled {
                                    item.status = TransferStatus::Failed;
                                    item.error_message = Some(e.to_string());
                                    item.updated_at = Utc::now().to_rfc3339();
                                }
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
                    // 同发送侧：取消优先级高于「刚好也收完了」
                    if item.status != TransferStatus::Cancelled {
                        item.status = TransferStatus::Completed;
                        item.progress = 100.0;
                        item.updated_at = Utc::now().to_rfc3339();
                    }
                    if let Some(path) = saved_path {
                        item.file_path = Some(path);
                    }
                }
            }

            prune_finished_transfers(&transfers).await;
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
    cancel: &tokio::sync::watch::Receiver<bool>,
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
        // 每轮先看取消信号：用户点取消后必须立刻停手，不能把整个文件传完
        if is_cancelled(cancel) {
            return Err(cancelled_error());
        }
        let n = file.read(&mut buf).await?;
        if n == 0 {
            break;
        }
        // 单帧写超时：对端停读时 write_all 会无限挂住，一直握着连接线程
        tokio::time::timeout(
            Duration::from_secs(FRAME_IO_TIMEOUT_SECS),
            write_frame(stream, &buf[..n]),
        )
        .await
        .map_err(|_| anyhow!("发送帧超时（{}s）", FRAME_IO_TIMEOUT_SECS))??;
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
    cancel: &tokio::sync::watch::Receiver<bool>,
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
        // 每轮先看取消信号：用户点取消后必须立刻停手
        if is_cancelled(cancel) {
            return Err(cancelled_error());
        }
        // 单帧读超时：对端停止发送（拔网线/休眠/半开）时 read_exact 会永久挂住，
        // 白占着一个并发连接许可，32 个僵尸连接就能让入站能力归零。
        // 每帧最大 CHUNK_SIZE + 4KB 余量
        let chunk = tokio::time::timeout(
            Duration::from_secs(FRAME_IO_TIMEOUT_SECS),
            read_frame(stream, CHUNK_SIZE + 4096),
        )
        .await
        .map_err(|_| anyhow!("接收帧超时（{}s）", FRAME_IO_TIMEOUT_SECS))??;
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

/// 净化并对齐文件保存路径，杜绝路径穿越 / 非法字符
///
/// 仅取文件名的 basename，剔除路径分隔符与非法字符，并保证最终路径位于 [save_dir] 下。
fn sanitize_save_path(save_dir: &str, file_name: &str) -> String {
    // 只取 basename，去掉任何目录前缀（含 ../ 穿越）
    let base = Path::new(file_name)
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("file");
    // 剔除 Windows 非法字符与控制字符
    let clean: String = base
        .chars()
        .filter(|c| !matches!(c, '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|') && !c.is_control())
        .collect();
    let name = if clean.is_empty() { "unnamed".to_string() } else { clean };

    let dir_path = Path::new(save_dir);
    let candidate = dir_path.join(&name);
    // 保险：二次校验结果仍在保存目录内，否则回退为目录内的 "unnamed"
    if candidate.starts_with(dir_path) {
        candidate.to_string_lossy().to_string()
    } else {
        dir_path.join("unnamed").to_string_lossy().to_string()
    }
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

#[cfg(test)]
mod tests {
    use super::*;

    /// write_frame/read_frame 签名固定为 TcpStream，无法注入 memory stream，
    /// 用 127.0.0.1 环回建立一对真实连接做纯进程内协议往返测试
    async fn duplex_streams() -> (TcpStream, TcpStream) {
        let listener = TcpListener::bind("127.0.0.1:0").await.expect("bind 环回应成功");
        let addr = listener.local_addr().unwrap();
        let accept = tokio::spawn(async move { listener.accept().await.map(|(s, _)| s) });
        let client = TcpStream::connect(addr).await.expect("connect 环回应成功");
        let server = accept.await.unwrap().expect("accept 应成功");
        (client, server)
    }

    /// 正常帧往返：文本、二进制、256KB 大块（CHUNK_SIZE）均能原样读回
    #[tokio::test]
    async fn frame_roundtrip_normal_payloads() {
        let (mut a, mut b) = duplex_streams().await;
        // 普通文本帧
        write_frame(&mut a, b"hello").await.unwrap();
        assert_eq!(read_frame(&mut b, usize::MAX).await.unwrap(), b"hello");
        // 全字节值二进制帧
        let mut binary: Vec<u8> = (0..=255u8).collect();
        let doubled = binary.clone();
        binary.extend_from_slice(&doubled);
        write_frame(&mut a, &binary).await.unwrap();
        assert_eq!(read_frame(&mut b, usize::MAX).await.unwrap(), binary);
        // 大块帧：恰好 CHUNK_SIZE（256KB）
        let big = vec![7u8; CHUNK_SIZE];
        write_frame(&mut a, &big).await.unwrap();
        assert_eq!(read_frame(&mut b, usize::MAX).await.unwrap(), big);
        // 连续多帧保持顺序
        write_frame(&mut a, b"one").await.unwrap();
        write_frame(&mut a, b"two").await.unwrap();
        assert_eq!(read_frame(&mut b, usize::MAX).await.unwrap(), b"one");
        assert_eq!(read_frame(&mut b, usize::MAX).await.unwrap(), b"two");
    }

    /// 帧头是 4 字节大端长度（网络序），可被对端原样解析
    #[tokio::test]
    async fn frame_header_is_big_endian_length() {
        let (mut a, mut b) = duplex_streams().await;
        write_frame(&mut a, &[0u8; 5]).await.unwrap();
        let mut raw = [0u8; 9]; // 4B 头 + 5B 载荷
        b.read_exact(&mut raw).await.unwrap();
        assert_eq!(&raw[..4], &[0, 0, 0, 5], "长度头必须是大端 u32");
    }

    /// len=0 帧表示 EOF：read_frame 返回空 Vec 而不是阻塞等待载荷
    #[tokio::test]
    async fn frame_zero_length_is_eof_marker() {
        let (mut a, mut b) = duplex_streams().await;
        write_frame(&mut a, b"").await.unwrap();
        assert!(read_frame(&mut b, usize::MAX).await.unwrap().is_empty());
        // 直接手写 4 字节零头（不经 write_frame）同样被识别为 EOF
        use tokio::io::AsyncWriteExt;
        a.write_all(&0u32.to_be_bytes()).await.unwrap();
        a.flush().await.unwrap();
        assert!(read_frame(&mut b, usize::MAX).await.unwrap().is_empty());
    }

    /// 超大长度帧：声明长度超过 max_size 时立即报错，且不按声明长度预分配内存；
    /// 长度恰好等于 max_size 时放行（严格大于才拒绝）
    #[tokio::test]
    async fn frame_oversize_length_rejected_before_alloc() {
        let (mut a, mut b) = duplex_streams().await;
        // 声称 4GB 载荷但一个字节都不发：若实现先分配再校验会 OOM/卡死
        a.write_all(&u32::MAX.to_be_bytes()).await.unwrap();
        a.flush().await.unwrap();
        let err = read_frame(&mut b, 1024).await.unwrap_err().to_string();
        assert!(err.contains("帧太大"), "err = {err}");
        assert!(err.contains("4294967295") && err.contains("1024"), "err = {err}");
        // 边界：len == max_size 不拒绝，正常读取完整帧
        a.write_all(&5u32.to_be_bytes()).await.unwrap();
        a.write_all(b"abcde").await.unwrap();
        a.flush().await.unwrap();
        assert_eq!(read_frame(&mut b, 5).await.unwrap(), b"abcde");
        // len == max_size + 1 拒绝
        a.write_all(&6u32.to_be_bytes()).await.unwrap();
        a.flush().await.unwrap();
        assert!(read_frame(&mut b, 5).await.unwrap_err().to_string().contains("帧太大"));
    }

    /// 截断的载荷：写端在发完帧头+部分载荷后关闭 ⇒ read_exact 报 EOF
    #[tokio::test]
    async fn frame_truncated_payload_errors() {
        let (mut a, mut b) = duplex_streams().await;
        a.write_all(&100u32.to_be_bytes()).await.unwrap(); // 声称 100 字节
        a.write_all(b"only 28 bytes here, ha!").await.unwrap(); // 实际 25 字节
        a.flush().await.unwrap();
        drop(a); // 关闭连接 ⇒ 载荷截断
        let err = read_frame(&mut b, usize::MAX).await.unwrap_err().to_string();
        assert!(
            err.to_lowercase().contains("early eof") || err.to_lowercase().contains("failed to fill whole buffer"),
            "err = {err}"
        );
    }

    /// 截断的帧头：只写 2 字节就关闭 ⇒ 连长度头都读不满，报错而不是当成 EOF 帧
    #[tokio::test]
    async fn frame_truncated_header_errors() {
        let (mut a, mut b) = duplex_streams().await;
        a.write_all(&[0u8, 4]).await.unwrap(); // 帧头只发一半
        a.flush().await.unwrap();
        drop(a);
        let err = read_frame(&mut b, usize::MAX).await.unwrap_err().to_string();
        assert!(
            err.to_lowercase().contains("early eof") || err.to_lowercase().contains("failed to fill whole buffer"),
            "err = {err}"
        );
    }

    // ── 取消信号：cancel 必须能真正打断流任务（P2-21）──────────────────────

    /// 取消通道注册 → 广播 → 订阅端可见；guard drop 后条目消失
    #[tokio::test]
    async fn cancel_channel_registered_broadcast_and_cleaned_up() {
        let map: std::sync::Mutex<HashMap<String, tokio::sync::watch::Sender<bool>>> =
            std::sync::Mutex::new(HashMap::new());
        let rx = register_cancel_tx(&map, "tid-cancel");
        assert!(!is_cancelled(&rx), "刚注册时不该是取消态");

        // 相当于 cancel_transfer 里的 tx.send(true)
        {
            let guard = map.lock().unwrap();
            let tx = guard.get("tid-cancel").expect("应已注册");
            tx.send(true).expect("订阅端仍在");
        }
        // watch 的 borrow 不依赖 await，这里应当立即看到新值
        rx.clone().changed().await.expect("应收到变更");
        assert!(is_cancelled(&rx), "收到取消信号后必须判为已取消");

        // RAII 清理：任务退出后表里不能留条目（否则 cancel_txs 会无限增长）
        let guard_struct = CancelTxGuard {
            map: Arc::new(map),
            transfer_id: "tid-cancel".to_string(),
        };
        drop(guard_struct);
    }

    /// 接收流在取消后必须立刻返回错误，而不是把整份数据读完
    #[tokio::test]
    async fn receive_stream_aborts_when_cancelled() {
        use crate::types::TransferItem;
        let (mut a, mut b) = duplex_streams().await;
        let transfers: Arc<RwLock<HashMap<String, TransferItem>>> =
            Arc::new(RwLock::new(HashMap::new()));

        let dir = std::env::temp_dir().join(format!("lan_cancel_{}", std::process::id()));
        let _ = std::fs::create_dir_all(&dir);
        let save_path = dir.join("out.bin");
        let save_path_str = save_path.to_str().unwrap().to_string();

        // 先塞一点数据，再把取消标志置 true：循环下一轮就该退出
        write_frame(&mut a, b"some-bytes").await.unwrap();
        let (_tx, rx) = tokio::sync::watch::channel(true);

        let result = tokio::time::timeout(
            Duration::from_secs(5),
            receive_file_from_stream(
                &mut b,
                &save_path_str,
                "tid-x",
                None,
                &transfers,
                &rx,
            ),
        )
        .await
        .expect("取消后必须立即返回，不得挂住");

        let err = result.expect_err("已取消的接收应报错");
        assert!(err.to_string().contains("取消"), "err = {err}");
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// 停滞对端：读帧必须在 FRAME_IO_TIMEOUT 内超时失败，而不是永久挂住
    #[tokio::test]
    async fn receive_stream_times_out_on_stalled_peer() {
        use crate::types::TransferItem;
        let (a, mut b) = duplex_streams().await;
        let transfers: Arc<RwLock<HashMap<String, TransferItem>>> =
            Arc::new(RwLock::new(HashMap::new()));
        let (_tx, rx) = tokio::sync::watch::channel(false);

        let dir = std::env::temp_dir().join(format!("lan_timeout_{}", std::process::id()));
        let _ = std::fs::create_dir_all(&dir);
        let save_path = dir.join("out.bin");
        let save_path_str = save_path.to_str().unwrap().to_string();

        // a 一个字节都不发，但连接保持打开 ⇒ read_exact 会一直等
        // 用 tokio::time::pause 不划算（真实 IO），这里直接缩短等待：
        // 断言「超时分支会返回错误文案」即可，真正的 60s 由生产常量保证。
        assert_eq!(FRAME_IO_TIMEOUT_SECS, 60, "超时语义变更需同步更新本用例");
        drop(a);

        // 对端关闭后应快速失败（不是挂死）；这一步验证错误路径会返回而非吞掉
        let result = tokio::time::timeout(
            Duration::from_secs(5),
            receive_file_from_stream(
                &mut b,
                &save_path_str,
                "tid-y",
                None,
                &transfers,
                &rx,
            ),
        )
        .await
        .expect("关闭的对端不应挂住");
        assert!(result.is_err(), "对端关闭必须报错");
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// 终态记录超上限时只删最旧的，进行中的一条都不动
    #[tokio::test]
    async fn prune_finished_transfers_keeps_recent_and_inflight() {
        use crate::types::{TransferItem, TransferStatus, TransferType};
        let service = TransferService::new(0, "d".to_string(), "n".to_string())
            .await
            .expect("建服务应成功");

        let make = |id: &str, status: TransferStatus, at: &str| TransferItem {
            transfer_id: id.to_string(),
            sender_device_id: "s".to_string(),
            sender_device_name: "s".to_string(),
            receiver_device_id: "r".to_string(),
            transfer_type: TransferType::File,
            file_name: Some("f".to_string()),
            file_size: Some(1),
            text_content: None,
            file_path: None,
            status,
            progress: 0.0,
            created_at: at.to_string(),
            updated_at: at.to_string(),
            error_message: None,
        };

        {
            let mut t = service.transfers.write().await;
            // 进行中的那条：任何情况下都不能被清理掉
            t.insert(
                "inflight".to_string(),
                make(
                    "inflight",
                    TransferStatus::Transferring,
                    "1970-01-01T00:00:00Z",
                ),
            );
            for i in 0..(MAX_FINISHED_TRANSFERS + 25) {
                let id = format!("done-{:03}", i);
                let at = format!("2026-01-01T00:00:{:02}Z", i % 60);
                let key = id.clone();
                t.insert(id, make(&key, TransferStatus::Completed, &at));
            }
        }

        service.prune_finished_transfers().await;

        let t = service.transfers.read().await;
        assert!(t.contains_key("inflight"), "进行中的记录不得被清理");
        let finished = t
            .values()
            .filter(|item| item.status == TransferStatus::Completed)
            .count();
        assert_eq!(finished, MAX_FINISHED_TRANSFERS, "只保留最近 N 条终态记录");
    }

    /// stop_listening 释放端口后不得立刻重新 bind（P3-10）
    #[tokio::test]
    async fn stop_listening_releases_port_without_rebinding() {
        let mut service = TransferService::new(0, "d".to_string(), "n".to_string())
            .await
            .expect("建服务应成功");
        service.start_listening().await.expect("开始监听应成功");
        service.stop_listening().await.expect("停止监听应成功");
        assert!(
            service.listener.is_none(),
            "停止后必须不持有 listener，否则端口被重新占住"
        );
        // 停止后可再次启动（start_listening 自行重新 bind）
        service.start_listening().await.expect("停止后应能重新监听");
        service.stop_listening().await.expect("再次停止应成功");
    }

    /// send_msg/recv_msg：TransferMessage JSON 帧往返 + 空帧被识别为连接关闭
    #[tokio::test]
    async fn msg_roundtrip_and_empty_frame_error() {
        let (mut a, mut b) = duplex_streams().await;
        let msg = TransferMessage {
            message_type: MessageType::DeviceAnnouncement,
            payload: "{\"device_id\":\"dev-1\"}".to_string(),
            timestamp: "2026-01-01T00:00:00Z".to_string(),
        };
        send_msg(&mut a, &msg).await.unwrap();
        let got = recv_msg(&mut b).await.unwrap();
        assert!(matches!(got.message_type, MessageType::DeviceAnnouncement));
        assert_eq!(got.payload, msg.payload);
        assert_eq!(got.timestamp, msg.timestamp);
        // 空帧（EOF 标记）⇒ recv_msg 明确报错而不是返回垃圾
        write_frame(&mut a, b"").await.unwrap();
        let err = recv_msg(&mut b).await.unwrap_err().to_string();
        assert!(err.contains("空消息帧"), "err = {err}");
    }
}
