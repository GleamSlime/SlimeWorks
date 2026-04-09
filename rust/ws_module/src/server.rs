/// PC 端 WebSocket 服务器
use super::types::*;
use flutter_rust_bridge::frb;
use futures_util::{SinkExt, StreamExt};
use lazy_static::lazy_static;
use std::collections::HashMap;
use std::fs::OpenOptions;
use std::io::Write;
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
}

/// WebSocket 服务器（Opaque 类型供 Flutter 使用）
#[frb(opaque)]
pub struct WsServer {
    config: WsServerConfig,
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

        let handle = WsServerHandle {
            config: self.config.clone(),
            shutdown_tx,
            clients: clients.clone(),
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
            loop {
                tokio::time::sleep(tokio::time::Duration::from_millis(
                    HEARTBEAT_CHECK_INTERVAL_MS,
                ))
                .await;

                let mut clients_guard = clients_for_heartbeat.lock().await;
                let mut to_remove = Vec::new();

                for (client_id, handle) in clients_guard.iter_mut() {
                    // 检查鉴权超时
                    if handle.info.is_auth_timeout(AUTH_TIMEOUT_SECS) {
                        println!("Client {} auth timeout, closing connection", client_id);
                        let _ = handle.sender.send(Message::Close(None)).await;
                        to_remove.push(client_id.clone());
                        continue;
                    }

                    // 检查心跳超时
                    if handle.info.is_heartbeat_timeout(HEARTBEAT_TIMEOUT_SECS) {
                        println!("Client {} heartbeat timeout, closing connection", client_id);
                        let _ = handle.sender.send(Message::Close(None)).await;
                        to_remove.push(client_id.clone());
                    }
                }

                // 移除超时的客户端
                for client_id in to_remove {
                    clients_guard.remove(&client_id);
                }
            }
        });

        Ok(())
    }

    /// 停止服务器
    pub async fn stop(&self) -> Result<(), String> {
        let mut server_guard = SERVER_INSTANCE.write().await;
        if let Some(handle) = server_guard.take() {
            handle
                .shutdown_tx
                .send(())
                .await
                .map_err(|e| format!("Failed to send shutdown signal: {}", e))?;

            // 关闭所有客户端连接
            let clients = handle.clients.lock().await;
            for (_, client_handle) in clients.iter() {
                let _ = client_handle.sender.send(Message::Close(None)).await;
            }

            println!("WebSocket server stopped");
            Ok(())
        } else {
            Err("Server is not running".to_string())
        }
    }

    /// 广播消息到所有客户端
    pub async fn broadcast(&self, message: String) -> Result<(), String> {
        let server_guard = SERVER_INSTANCE.read().await;
        if let Some(handle) = server_guard.as_ref() {
            let clients = handle.clients.lock().await;
            // 支持路由前缀：
            // - 以 "TO:{client_id}:" 开头的消息只发送给指定客户端
            // - 以 "DISCONNECT:{client_id}" 开头的消息用于断开指定客户端
            // - "GET_CLIENTS" 返回所有客户端的 JSON 列表
            if message.starts_with("TO:") {
                if let Some(rest) = message.strip_prefix("TO:") {
                    if let Some(pos) = rest.find(':') {
                        let (client_id, payload) = rest.split_at(pos);
                        let payload = &payload[1..];
                        if let Some(client_handle) = clients.get(client_id) {
                            let msg = Message::Text(payload.to_string().into());
                            if let Err(e) = client_handle.sender.send(msg).await {
                                println!(
                                    "Failed to send routed message to client {}: {}",
                                    client_id, e
                                );
                            }
                        } else {
                            return Err(format!("Client {} not found", client_id));
                        }
                    }
                }
            } else if message.starts_with("DISCONNECT:") {
                drop(clients);
                let mut clients_mut = handle.clients.lock().await;
                if let Some(client_id) = message.strip_prefix("DISCONNECT:") {
                    if let Some(client_handle) = clients_mut.remove(client_id) {
                        let _ = client_handle.sender.send(Message::Close(None)).await;
                        println!("Disconnected and removed client {}", client_id);
                    } else {
                        return Err(format!("Client {} not found", client_id));
                    }
                }
            } else if message == "GET_CLIENTS" {
                // 收到 GET_CLIENTS 请求，返回客户端列表的 JSON
                println!("GET_CLIENTS command received via wsServerBroadcast");
                // 也写入临时调试文件，便于排查运行时日志是否被捕获
                if let Ok(mut f) = OpenOptions::new()
                    .create(true)
                    .append(true)
                    .open(std::env::temp_dir().join("ws_debug.log"))
                {
                    let _ = writeln!(
                        f,
                        "GET_CLIENTS received: {} clients currently",
                        clients.len()
                    );
                }
                let client_list: Vec<&ClientInfo> =
                    clients.iter().map(|(_, handle)| &handle.info).collect();
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
                        for (client_id, client_handle) in clients.iter() {
                            if let Err(e) = client_handle.sender.send(msg.clone()).await {
                                println!("Failed to send client list to {}: {}", client_id, e);
                            }
                        }
                    }
                    Err(e) => {
                        return Err(format!("Failed to serialize client list: {}", e));
                    }
                }
            } else {
                let msg = Message::Text(message.clone().into());
                for (client_id, client_handle) in clients.iter() {
                    if let Err(e) = client_handle.sender.send(msg.clone()).await {
                        println!("Failed to send message to client {}: {}", client_id, e);
                    }
                }
            }

            Ok(())
        } else {
            Err("Server is not running".to_string())
        }
    }

    /// 发送消息到指定客户端
    pub async fn send_to_client(&self, client_id: String, message: String) -> Result<(), String> {
        let server_guard = SERVER_INSTANCE.read().await;
        if let Some(handle) = server_guard.as_ref() {
            let clients = handle.clients.lock().await;
            if let Some(client_handle) = clients.get(&client_id) {
                let msg = Message::Text(message.into());
                client_handle.sender.send(msg).await.map_err(|e| {
                    format!("Failed to send message to client {}: {}", client_id, e)
                })?;
                Ok(())
            } else {
                Err(format!("Client {} not found", client_id))
            }
        } else {
            Err("Server is not running".to_string())
        }
    }

    /// 断开指定客户端连接
    pub async fn disconnect_client(&self, client_id: String) -> Result<(), String> {
        let server_guard = SERVER_INSTANCE.read().await;
        if let Some(handle) = server_guard.as_ref() {
            let mut clients = handle.clients.lock().await;
            if let Some(client_handle) = clients.get(&client_id) {
                let _ = client_handle.sender.send(Message::Close(None)).await;
                clients.remove(&client_id);
                println!("Disconnected client: {}", client_id);
                Ok(())
            } else {
                Err(format!("Client {} not found", client_id))
            }
        } else {
            Err("Server is not running".to_string())
        }
    }

    /// 获取当前连接的客户端数量
    pub async fn get_client_count(&self) -> Result<usize, String> {
        let server_guard = SERVER_INSTANCE.read().await;
        if let Some(handle) = server_guard.as_ref() {
            let clients = handle.clients.lock().await;
            if let Ok(mut f) = OpenOptions::new()
                .create(true)
                .append(true)
                .open(std::env::temp_dir().join("ws_debug.log"))
            {
                let _ = writeln!(f, "get_client_count: {}", clients.len());
                for (k, _) in clients.iter() {
                    let _ = writeln!(f, " * {}", k);
                }
            }
            Ok(clients.len())
        } else {
            Err("Server is not running".to_string())
        }
    }

    /// 获取所有连接的客户端信息列表
    pub async fn get_clients(&self) -> Result<Vec<ClientInfo>, String> {
        let server_guard = SERVER_INSTANCE.read().await;
        if let Some(handle) = server_guard.as_ref() {
            let clients = handle.clients.lock().await;
            let client_list = clients
                .iter()
                .map(|(_, handle)| handle.info.clone())
                .collect();
            Ok(client_list)
        } else {
            Err("Server is not running".to_string())
        }
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
    let (tx, mut rx) = mpsc::channel::<Message>(100);

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
            for (k, _) in clients_guard.iter() {
                let _ = writeln!(f, " - {}", k);
            }
        }
    }

    // 发送任务：从 channel 接收消息并发送给客户端
    let send_task = tokio::spawn(async move {
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
    let receive_task = tokio::spawn(async move {
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

    // 等待任务完成
    tokio::select! {
        _ = send_task => {},
        _ = receive_task => {},
    }

    // 移除客户端
    {
        let mut clients_guard = clients.lock().await;
        clients_guard.remove(&client_id);
    }

    println!("Client {} disconnected", client_id);
}
