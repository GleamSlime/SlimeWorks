/// PC 端 WebSocket 服务器
use super::types::*;
use flutter_rust_bridge::frb;
use futures_util::{SinkExt, StreamExt};
use lazy_static::lazy_static;
use std::collections::HashMap;
use std::fs::OpenOptions;
use std::io::Write;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{mpsc, Mutex, RwLock};
use tokio_tungstenite::accept_async;
use tokio_tungstenite::tungstenite::protocol::Message;

lazy_static! {
    /// 全局服务器实例
    static ref SERVER_INSTANCE: Arc<RwLock<Option<WsServerHandle>>> = Arc::new(RwLock::new(None));
}

/// 心跳超时时间（秒）
const HEARTBEAT_TIMEOUT_SECS: i64 = 30;
/// 鉴权超时时间（秒）
const AUTH_TIMEOUT_SECS: i64 = 10;
/// 心跳检查间隔（毫秒）
const HEARTBEAT_CHECK_INTERVAL_MS: u64 = 5000;

/// 单客户端发送通道容量。
///
/// 这个数字就是「慢客户端」的判定阈值：通道攒满 = 该客户端连续
/// [CLIENT_CHANNEL_CAPACITY] 条消息没读走，判定为停滞，移除并断开。
/// 历史上这里是阻塞式 send，而发送时刻正持着全局 clients 锁——
/// 一个停滞客户端就能把心跳、广播、单发、新连接注册全部冻结。
const CLIENT_CHANNEL_CAPACITY: usize = 100;

/// 客户端连接句柄
struct ClientHandle {
    sender: mpsc::Sender<Message>,
    info: ClientInfo,
}

/// WebSocket 服务器句柄
pub struct WsServerHandle {
    #[allow(dead_code)]
    config: WsServerConfig,
    shutdown_tx: mpsc::Sender<()>,
    clients: Arc<Mutex<HashMap<String, ClientHandle>>>,
    /// 心跳/检查任务的退出标志。
    ///
    /// 为什么必须显式存在：心跳任务是 start() 里 spawn 的裸 loop，没有任何
    /// 退出条件，每次 start/stop 就漏一个（P3-11）。用 AtomicBool 而不是再加
    /// 一条 channel，是因为这里只需要一个「该退出了」的语义，不需要传递数据。
    shutdown_flag: Arc<AtomicBool>,
}

/// WebSocket 服务器（Opaque 类型供 Flutter 使用）
#[frb(opaque)]
pub struct WsServer {
    config: WsServerConfig,
}


// ── 全局锁的用法约定 ─────────────────────────────────────────────────────────
//
// 下面三个 helper 是本模块唯一的 clients 表访问方式。铁律：
// **持有 clients 锁期间绝不做任何 .await（尤其是 send().await）**。
// 锁内只克隆 mpsc::Sender（廉价句柄），释放锁之后再用 try_send 发送；
// 通道满就是慢客户端，直接移除断开，绝不阻塞。

/// 克隆一份 (client_id, Sender) 快照，锁在函数返回前就已释放。
async fn client_snapshot(
    clients: &Arc<Mutex<HashMap<String, ClientHandle>>>,
) -> Vec<(String, mpsc::Sender<Message>)> {
    let guard = clients.lock().await;
    guard
        .iter()
        .map(|(id, handle)| (id.clone(), handle.sender.clone()))
        .collect()
}

/// 向快照里的每个客户端非阻塞发送；返回「通道已满或已关闭」的 client_id。
///
/// 返回的这批 id 就是慢客户端：调用方负责把它们从表里摘掉——
/// 摘掉 Sender 会让该连接的 send 任务收到 None 后退出，socket 随之关闭。
fn try_send_snapshot(
    snapshot: &[(String, mpsc::Sender<Message>)],
    message: &Message,
) -> Vec<String> {
    let mut stalled = Vec::new();
    for (client_id, sender) in snapshot {
        if sender.try_send(message.clone()).is_err() {
            stalled.push(client_id.clone());
        }
    }
    stalled
}

/// 断开并移除客户端（等价于断开连接，见 [try_send_snapshot] 的说明）。
///
/// 签名收 `&[&str]` 而不是 `&[String]`：调用点大多是「手上已有一个 id」，
/// 收 String 会逼出一个只为传参而 clone 的临时切片，白复制一次 id。
async fn evict_clients(clients: &Arc<Mutex<HashMap<String, ClientHandle>>>, ids: &[&str]) {
    if ids.is_empty() {
        return;
    }
    let mut guard = clients.lock().await;
    for id in ids {
        if guard.remove(*id).is_some() {
            println!("慢客户端已移除并断开: {}", id);
        }
    }
}

/// 只读地取某个客户端的 Sender 快照（用于单发/路由发送）。
async fn sender_of(
    clients: &Arc<Mutex<HashMap<String, ClientHandle>>>,
    client_id: &str,
) -> Option<mpsc::Sender<Message>> {
    let guard = clients.lock().await;
    guard.get(client_id).map(|handle| handle.sender.clone())
}


impl WsServer {
    /// 创建 WebSocket 服务器
    pub fn new(host: String, port: u16) -> Self {
        Self {
            config: WsServerConfig {
                host,
                port,
                max_connections: 100,
            },
        }
    }

    /// 启动服务器
    pub async fn start(&self) -> Result<(), String> {
        let addr = format!("{}:{}", self.config.host, self.config.port);
        let listener = TcpListener::bind(&addr)
            .await
            .map_err(|e| format!("Failed to bind to {}: {}", addr, e))?;

        println!("WebSocket server listening on {}", addr);

        let (shutdown_tx, mut shutdown_rx) = mpsc::channel::<()>(1);
        let clients = Arc::new(Mutex::new(HashMap::new()));
        let shutdown_flag = Arc::new(AtomicBool::new(false));

        let handle = WsServerHandle {
            config: self.config.clone(),
            shutdown_tx,
            clients: clients.clone(),
            shutdown_flag: shutdown_flag.clone(),
        };

        // 保存全局实例
        {
            let mut server_guard = SERVER_INSTANCE.write().await;
            *server_guard = Some(handle);
        }

        let clients_clone = clients.clone();

        // 启动接受连接的任务
        tokio::spawn(async move {
            loop {
                tokio::select! {
                    result = listener.accept() => {
                        match result {
                            Ok((stream, addr)) => {
                                println!("New connection from: {}", addr);
                                let clients = clients_clone.clone();
                                tokio::spawn(handle_connection(stream, addr.to_string(), clients));
                            }
                            Err(e) => {
                                println!("Failed to accept connection: {}", e);
                            }
                        }
                    }
                    _ = shutdown_rx.recv() => {
                        println!("Server shutdown signal received");
                        break;
                    }
                }
            }
        });

        // 启动心跳和鉴权检查任务
        let clients_for_heartbeat = clients.clone();
        tokio::spawn(async move {
            let mut ticker = tokio::time::interval(tokio::time::Duration::from_millis(
                HEARTBEAT_CHECK_INTERVAL_MS,
            ));
            // 第一次 tick 会立即就绪，跳过它，避免启动瞬间就做一轮检查
            ticker.tick().await;
            loop {
                ticker.tick().await;
                // 退出标志：stop() 置位后本任务在下一次 tick（≤5s）内退出，
                // 不再像以前那样每次 start/stop 泄漏一个永不停歇的任务。
                if shutdown_flag.load(Ordering::SeqCst) {
                    println!("心跳检查任务退出");
                    break;
                }

                // 锁内只收集判定结果，发送与移除都放到锁外做
                let (timed_out, snapshot) = {
                    let mut clients_guard = clients_for_heartbeat.lock().await;
                    let mut timed_out = Vec::new();

                    for (client_id, handle) in clients_guard.iter_mut() {
                        // 检查鉴权超时
                        if handle.info.is_auth_timeout(AUTH_TIMEOUT_SECS) {
                            println!("Client {} auth timeout, closing connection", client_id);
                            timed_out.push(client_id.clone());
                            continue;
                        }

                        // 检查心跳超时
                        if handle.info.is_heartbeat_timeout(HEARTBEAT_TIMEOUT_SECS) {
                            println!("Client {} heartbeat timeout, closing connection", client_id);
                            timed_out.push(client_id.clone());
                        }
                    }

                    let snapshot: Vec<(String, mpsc::Sender<Message>)> = timed_out
                        .iter()
                        .filter_map(|id| {
                            clients_guard
                                .get(id)
                                .map(|handle| (id.clone(), handle.sender.clone()))
                        })
                        .collect();
                    (timed_out, snapshot)
                };

                // 发送 Close 与移除都在锁外：这里以前持锁 send().await，
                // 一个不读数据的客户端就能把整轮心跳卡死。
                if !timed_out.is_empty() {
                    // 送 Close 失败（通道满）也要移除——移除即断开
                    let _ = try_send_snapshot(&snapshot, &Message::Close(None));
                    let ids: Vec<&str> = timed_out.iter().map(|id| id.as_str()).collect();
                    evict_clients(&clients_for_heartbeat, &ids).await;
                }
            }
        });

        Ok(())
    }

    /// 停止服务器
    pub async fn stop(&self) -> Result<(), String> {
        // 先把 handle 取出来并立刻释放全局写锁：
        // 后续对每个客户端发送 Close 属于网络操作，不能压在全局锁下。
        let handle = {
            let mut server_guard = SERVER_INSTANCE.write().await;
            server_guard.take()
        };
        let Some(handle) = handle else {
            return Err("Server is not running".to_string());
        };

        // 置退出标志，让心跳/检查任务自己收尾（P3-11）
        handle.shutdown_flag.store(true, Ordering::SeqCst);
        // accept 任务若已自行退出，这里 send 会失败，属正常情况，不影响停止语义
        let _ = handle.shutdown_tx.send(()).await;

        // 关闭所有客户端连接：快照 + 锁外 try_send
        let snapshot = client_snapshot(&handle.clients).await;
        let _ = try_send_snapshot(&snapshot, &Message::Close(None));
        // 全部摘掉 Sender ⇒ 各自的 send 任务收到 None 后退出、socket 关闭
        let ids: Vec<&str> = snapshot.iter().map(|(id, _)| id.as_str()).collect();
        evict_clients(&handle.clients, &ids).await;

        println!("WebSocket server stopped");
        Ok(())
    }


    /// 广播消息到所有客户端
    pub async fn broadcast(&self, message: String) -> Result<(), String> {
        // 只把 Arc 克隆出来就释放 SERVER_INSTANCE 的读锁
        let clients = {
            let server_guard = SERVER_INSTANCE.read().await;
            match server_guard.as_ref() {
                Some(handle) => handle.clients.clone(),
                None => return Err("Server is not running".to_string()),
            }
        };

        // 支持路由前缀：
        // - 以 "TO:{client_id}:" 开头的消息只发送给指定客户端
        // - 以 "DISCONNECT:{client_id}" 开头的消息用于断开指定客户端
        // - "GET_CLIENTS" 返回所有客户端的 JSON 列表
        if message.starts_with("TO:") {
            if let Some(rest) = message.strip_prefix("TO:") {
                if let Some(pos) = rest.find(':') {
                    let (client_id, payload) = rest.split_at(pos);
                    let payload = &payload[1..];
                    let Some(sender) = sender_of(&clients, client_id).await else {
                        return Err(format!("Client {} not found", client_id));
                    };
                    let msg = Message::Text(payload.to_string().into());
                    // 单发同样用 try_send：目标客户端停滞时不能拖住调用方
                    if sender.try_send(msg).is_err() {
                        println!("Routed message dropped (client {} stalled), evicting", client_id);
                        evict_clients(&clients, &[client_id]).await;
                        return Err(format!("Client {} is not consuming messages", client_id));
                    }
                }
            }
        } else if message.starts_with("DISCONNECT:") {
            if let Some(client_id) = message.strip_prefix("DISCONNECT:") {
                let Some(sender) = sender_of(&clients, client_id).await else {
                    return Err(format!("Client {} not found", client_id));
                };
                // 先移除（断开），再尽力送出 Close
                evict_clients(&clients, &[client_id]).await;
                let _ = sender.try_send(Message::Close(None));
                println!("Disconnected and removed client {}", client_id);
            }
        } else if message == "GET_CLIENTS" {
            // 收到 GET_CLIENTS 请求，返回客户端列表的 JSON
            println!("GET_CLIENTS command received via wsServerBroadcast");
            // 锁内只克隆 ClientInfo，序列化与发送都在锁外
            let client_infos: Vec<ClientInfo> = {
                let clients_guard = clients.lock().await;
                clients_guard
                    .values()
                    .map(|handle| handle.info.clone())
                    .collect()
            };
            let client_list: Vec<&ClientInfo> = client_infos.iter().collect();
            // 也写入临时调试文件，便于排查运行时日志是否被捕获
            if let Ok(mut f) = OpenOptions::new()
                .create(true)
                .append(true)
                .open(std::env::temp_dir().join("ws_debug.log"))
            {
                let _ = writeln!(
                    f,
                    "GET_CLIENTS received: {} clients currently",
                    client_list.len()
                );
            }
            match serde_json::to_string(&client_list) {
                Ok(json_str) => {
                    // 向所有客户端广播（UI 会接收并解析）
                    println!("Broadcasting CLIENTS_LIST to {} clients", client_list.len());
                    if let Ok(mut f) = OpenOptions::new()
                        .create(true)
                        .append(true)
                        .open(std::env::temp_dir().join("ws_debug.log"))
                    {
                        let _ = writeln!(
                            f,
                            "Broadcasting CLIENTS_LIST to {} clients",
                            client_list.len()
                        );
                        let _ = writeln!(f, "payload: {}", json_str);
                    }
                    let response = format!("CLIENTS_LIST:{}", json_str);
                    let msg = Message::Text(response.into());
                    let snapshot = client_snapshot(&clients).await;
                    let stalled = try_send_snapshot(&snapshot, &msg);
                    let ids: Vec<&str> = stalled.iter().map(|id| id.as_str()).collect();
                    evict_clients(&clients, &ids).await;
                }
                Err(e) => {
                    return Err(format!("Failed to serialize client list: {}", e));
                }
            }
        } else {
            let msg = Message::Text(message.clone().into());
            // 快照 → 锁外 try_send → 清理满通道的慢客户端。
            // 这条路径以前是「持锁 send().await」，正是「一个慢客户端冻结整个服务器」的现场。
            let snapshot = client_snapshot(&clients).await;
            let stalled = try_send_snapshot(&snapshot, &msg);
            for client_id in &stalled {
                println!("Failed to send message to client {}: channel full", client_id);
            }
            let ids: Vec<&str> = stalled.iter().map(|id| id.as_str()).collect();
            evict_clients(&clients, &ids).await;
        }

        Ok(())
    }

    /// 发送消息到指定客户端
    pub async fn send_to_client(&self, client_id: String, message: String) -> Result<(), String> {
        let clients = {
            let server_guard = SERVER_INSTANCE.read().await;
            match server_guard.as_ref() {
                Some(handle) => handle.clients.clone(),
                None => return Err("Server is not running".to_string()),
            }
        };
        let Some(sender) = sender_of(&clients, &client_id).await else {
            return Err(format!("Client {} not found", client_id));
        };
        let msg = Message::Text(message.into());
        // try_send 而非 send：目标客户端停滞时不能让调用方（心跳/业务线程）陪着等
        if sender.try_send(msg).is_err() {
            evict_clients(&clients, &[client_id.as_str()]).await;
            return Err(format!(
                "Failed to send message to client {}: channel full, client evicted",
                client_id
            ));
        }
        Ok(())
    }

    /// 断开指定客户端连接
    pub async fn disconnect_client(&self, client_id: String) -> Result<(), String> {
        let clients = {
            let server_guard = SERVER_INSTANCE.read().await;
            match server_guard.as_ref() {
                Some(handle) => handle.clients.clone(),
                None => return Err("Server is not running".to_string()),
            }
        };
        let Some(sender) = sender_of(&clients, &client_id).await else {
            return Err(format!("Client {} not found", client_id));
        };
        // 先摘掉条目（断开），再尽力送出 Close
        evict_clients(&clients, &[client_id.as_str()]).await;
        let _ = sender.try_send(Message::Close(None));
        println!("Disconnected client: {}", client_id);
        Ok(())
    }

    /// 获取当前连接的客户端数量
    pub async fn get_client_count(&self) -> Result<usize, String> {
        let clients = {
            let server_guard = SERVER_INSTANCE.read().await;
            match server_guard.as_ref() {
                Some(handle) => handle.clients.clone(),
                None => return Err("Server is not running".to_string()),
            }
        };
        let clients_guard = clients.lock().await;
        if let Ok(mut f) = OpenOptions::new()
            .create(true)
            .append(true)
            .open(std::env::temp_dir().join("ws_debug.log"))
        {
            let _ = writeln!(f, "get_client_count: {}", clients_guard.len());
            for k in clients_guard.keys() {
                let _ = writeln!(f, " * {}", k);
            }
        }
        Ok(clients_guard.len())
    }

    /// 获取所有连接的客户端信息列表
    pub async fn get_clients(&self) -> Result<Vec<ClientInfo>, String> {
        let clients = {
            let server_guard = SERVER_INSTANCE.read().await;
            match server_guard.as_ref() {
                Some(handle) => handle.clients.clone(),
                None => return Err("Server is not running".to_string()),
            }
        };
        let clients_guard = clients.lock().await;
        let client_list = clients_guard
            .values()
            .map(|handle| handle.info.clone())
            .collect();
        Ok(client_list)
    }
}
/// 处理单个 WebSocket 连接
async fn handle_connection(
    stream: TcpStream,
    client_id: String,
    clients: Arc<Mutex<HashMap<String, ClientHandle>>>,
) {
    let ws_stream = match accept_async(stream).await {
        Ok(ws) => ws,
        Err(e) => {
            println!("WebSocket handshake failed for {}: {}", client_id, e);
            return;
        }
    };

    println!("WebSocket connection established: {}", client_id);

    let (mut ws_sender, mut ws_receiver) = ws_stream.split();
    let (tx, mut rx) = mpsc::channel::<Message>(CLIENT_CHANNEL_CAPACITY);

    // 创建客户端信息
    let client_info = ClientInfo::new(client_id.clone(), client_id.clone());

    // 注册客户端
    {
        let mut clients_guard = clients.lock().await;
        clients_guard.insert(
            client_id.clone(),
            ClientHandle {
                sender: tx,
                info: client_info,
            },
        );
        // 写入调试文件记录当前客户端列表
        if let Ok(mut f) = OpenOptions::new()
            .create(true)
            .append(true)
            .open(std::env::temp_dir().join("ws_debug.log"))
        {
            let _ = writeln!(
                f,
                "Registered client: {}. Total clients: {}",
                client_id,
                clients_guard.len()
            );
            for k in clients_guard.keys() {
                let _ = writeln!(f, " - {}", k);
            }
        }
    }

    // 发送任务：从 channel 接收消息并发送给客户端
    let mut send_task = tokio::spawn(async move {
        while let Some(msg) = rx.recv().await {
            if let Err(e) = ws_sender.send(msg).await {
                println!("Failed to send message: {}", e);
                break;
            }
        }
    });

    // 接收任务：从客户端接收消息
    let client_id_clone = client_id.clone();
    let clients_clone = clients.clone();
    let mut receive_task = tokio::spawn(async move {
        while let Some(result) = ws_receiver.next().await {
            match result {
                Ok(msg) => {
                    match msg {
                        Message::Text(text) => {
                            println!("Received text from {}: {}", client_id_clone, text);

                            // 尝试解析消息类型
                            if text.starts_with("AUTH:") {
                                // 处理鉴权消息
                                let mut clients_guard = clients_clone.lock().await;
                                if let Some(handle) = clients_guard.get_mut(&client_id_clone) {
                                    handle.info.authenticated = true;
                                    handle.info.update_heartbeat();
                                    println!("Client {} authenticated", client_id_clone);
                                }
                            } else if text == "PING" || text == "ping" {
                                // 处理心跳消息
                                let mut clients_guard = clients_clone.lock().await;
                                if let Some(handle) = clients_guard.get_mut(&client_id_clone) {
                                    handle.info.update_heartbeat();
                                    println!("Client {} heartbeat updated", client_id_clone);
                                }
                            } else {
                                // 普通消息，更新心跳
                                let mut clients_guard = clients_clone.lock().await;
                                if let Some(handle) = clients_guard.get_mut(&client_id_clone) {
                                    handle.info.update_heartbeat();
                                }
                            }
                        }
                        Message::Binary(data) => {
                            println!(
                                "Received binary from {}: {} bytes",
                                client_id_clone,
                                data.len()
                            );
                            // 更新心跳
                            let mut clients_guard = clients_clone.lock().await;
                            if let Some(handle) = clients_guard.get_mut(&client_id_clone) {
                                handle.info.update_heartbeat();
                            }
                        }
                        Message::Ping(_) | Message::Pong(_) => {
                            // 更新心跳
                            let mut clients_guard = clients_clone.lock().await;
                            if let Some(handle) = clients_guard.get_mut(&client_id_clone) {
                                handle.info.update_heartbeat();
                            }
                        }
                        Message::Close(_) => {
                            println!("Client {} closed connection", client_id_clone);
                            break;
                        }
                        _ => {}
                    }
                }
                Err(e) => {
                    println!("Error receiving message from {}: {}", client_id_clone, e);
                    break;
                }
            }
        }
    });

    // 等待任一任务完成
    tokio::select! {
        _ = &mut send_task => {},
        _ = &mut receive_task => {},
    }

    // 落败的任务必须主动 abort（P3-11）：不然它是孤儿——发送任务会一直挂在
    // rx.recv().await 上等这条连接的下一条消息，而 socket 早已由另一方关闭，
    // 每来一个客户端就泄漏一个永不退出的任务。
    send_task.abort();
    receive_task.abort();

    // 移除客户端
    {
        let mut clients_guard = clients.lock().await;
        clients_guard.remove(&client_id);
    }

    println!("Client {} disconnected", client_id);
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    fn text(s: &str) -> Message {
        Message::Text(s.to_string().into())
    }

    /// 造一个「不读 rx」的停滞客户端：通道塞满 CLIENT_CHANNEL_CAPACITY 条后
    /// 再也发不进去，且全程没有任何 recv。
    fn stalled_client(id: &str) -> (String, mpsc::Sender<Message>, mpsc::Receiver<Message>) {
        let (tx, rx) = mpsc::channel::<Message>(CLIENT_CHANNEL_CAPACITY);
        for i in 0..CLIENT_CHANNEL_CAPACITY {
            tx.try_send(text(&format!("filler-{}", i)))
                .expect("容量内应能塞满");
        }
        (id.to_string(), tx, rx)
    }

    /// 一个客户端不读数据时：广播必须立即返回，其他客户端照常收到；
    /// 停滞客户端被识别并移除（P2-1 的核心验收）。
    #[tokio::test]
    async fn broadcast_is_not_blocked_by_stalled_client() {
        let clients: Arc<Mutex<HashMap<String, ClientHandle>>> =
            Arc::new(Mutex::new(HashMap::new()));

        // 健康客户端：会正常取走消息
        let (healthy_tx, mut healthy_rx) = mpsc::channel::<Message>(CLIENT_CHANNEL_CAPACITY);
        // 停滞客户端：先塞满，之后一条都进不去
        let (stalled_id, stalled_tx, _stalled_rx) = stalled_client("stalled");

        {
            let mut guard = clients.lock().await;
            guard.insert(
                "healthy".to_string(),
                ClientHandle {
                    sender: healthy_tx,
                    info: ClientInfo::new("healthy".to_string(), "healthy".to_string()),
                },
            );
            guard.insert(
                stalled_id.clone(),
                ClientHandle {
                    sender: stalled_tx,
                    info: ClientInfo::new(stalled_id.clone(), stalled_id.clone()),
                },
            );
        }

        // 「立即返回」是硬性断言：锁内阻塞 send 的旧实现会在这里挂死
        let broadcast = tokio::time::timeout(Duration::from_secs(2), async {
            let snapshot = client_snapshot(&clients).await;
            let stalled = try_send_snapshot(&snapshot, &text("hello"));
            let ids: Vec<&str> = stalled.iter().map(|id| id.as_str()).collect();
            evict_clients(&clients, &ids).await;
            stalled
        })
        .await
        .expect("广播不得被停滞客户端阻塞");

        assert_eq!(broadcast, vec![stalled_id.clone()], "只有停滞客户端应被判定慢");

        // 健康客户端正常收到
        let got = healthy_rx.recv().await.expect("健康客户端应收到消息");
        assert_eq!(got, text("hello"));

        // 停滞客户端被摘出表（摘掉 Sender ⇒ 其 send 任务退出 ⇒ socket 关闭）
        let guard = clients.lock().await;
        assert!(!guard.contains_key(&stalled_id), "停滞客户端应已被移除");
        assert!(guard.contains_key("healthy"), "健康客户端不得被误杀");
    }

    /// 单发路径同样用 try_send：目标客户端通道满时立即报错而不是阻塞
    #[tokio::test]
    async fn try_send_to_stalled_client_does_not_block() {
        let clients: Arc<Mutex<HashMap<String, ClientHandle>>> =
            Arc::new(Mutex::new(HashMap::new()));
        let (stalled_id, stalled_tx, _rx) = stalled_client("stalled2");
        clients.lock().await.insert(
            stalled_id.clone(),
            ClientHandle {
                sender: stalled_tx,
                info: ClientInfo::new(stalled_id.clone(), stalled_id.clone()),
            },
        );

        let result = tokio::time::timeout(Duration::from_secs(2), async {
            let snapshot = client_snapshot(&clients).await;
            let stalled = try_send_snapshot(&snapshot, &text("x"));
            let ids: Vec<&str> = stalled.iter().map(|id| id.as_str()).collect();
            evict_clients(&clients, &ids).await;
            stalled
        })
        .await
        .expect("单发不得阻塞");

        assert_eq!(result, vec![stalled_id.clone()]);
        assert!(!clients.lock().await.contains_key(&stalled_id));
    }

    /// 客户端不在表里时 sender_of 返回 None（调用方据此回 not found）
    #[tokio::test]
    async fn sender_of_missing_client_is_none() {
        let clients: Arc<Mutex<HashMap<String, ClientHandle>>> =
            Arc::new(Mutex::new(HashMap::new()));
        assert!(super::sender_of(&clients, "nobody").await.is_none());
    }
}
