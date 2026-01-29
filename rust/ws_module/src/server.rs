/// PC 端 WebSocket 服务器
use super::types::*;
use flutter_rust_bridge::frb;
use futures_util::{SinkExt, StreamExt};
use lazy_static::lazy_static;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{mpsc, Mutex, RwLock};
use tokio_tungstenite::tungstenite::protocol::Message;
use tokio_tungstenite::accept_async;

lazy_static! {
    /// 全局服务器实例
    static ref SERVER_INSTANCE: Arc<RwLock<Option<WsServerHandle>>> = Arc::new(RwLock::new(None));
}

/// WebSocket 服务器句柄
pub struct WsServerHandle {
    config: WsServerConfig,
    shutdown_tx: mpsc::Sender<()>,
    clients: Arc<Mutex<HashMap<String, mpsc::Sender<Message>>>>,
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

        log::info!("WebSocket server listening on {}", addr);

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
                                log::info!("New connection from: {}", addr);
                                let clients = clients_clone.clone();
                                tokio::spawn(handle_connection(stream, addr.to_string(), clients));
                            }
                            Err(e) => {
                                log::error!("Failed to accept connection: {}", e);
                            }
                        }
                    }
                    _ = shutdown_rx.recv() => {
                        log::info!("Server shutdown signal received");
                        break;
                    }
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
            for (_, tx) in clients.iter() {
                let _ = tx.send(Message::Close(None)).await;
            }

            log::info!("WebSocket server stopped");
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
            let msg = Message::Text(message.clone().into());

            for (client_id, tx) in clients.iter() {
                if let Err(e) = tx.send(msg.clone()).await {
                    log::error!("Failed to send message to client {}: {}", client_id, e);
                }
            }

            Ok(())
        } else {
            Err("Server is not running".to_string())
        }
    }

    /// 获取当前连接的客户端数量
    pub async fn get_client_count(&self) -> Result<usize, String> {
        let server_guard = SERVER_INSTANCE.read().await;
        if let Some(handle) = server_guard.as_ref() {
            let clients = handle.clients.lock().await;
            Ok(clients.len())
        } else {
            Err("Server is not running".to_string())
        }
    }
}

/// 处理单个 WebSocket 连接
async fn handle_connection(
    stream: TcpStream,
    client_id: String,
    clients: Arc<Mutex<HashMap<String, mpsc::Sender<Message>>>>,
) {
    let ws_stream = match accept_async(stream).await {
        Ok(ws) => ws,
        Err(e) => {
            log::error!("WebSocket handshake failed for {}: {}", client_id, e);
            return;
        }
    };

    log::info!("WebSocket connection established: {}", client_id);

    let (mut ws_sender, mut ws_receiver) = ws_stream.split();
    let (tx, mut rx) = mpsc::channel::<Message>(100);

    // 注册客户端
    {
        let mut clients_guard = clients.lock().await;
        clients_guard.insert(client_id.clone(), tx);
    }

    // 发送任务：从 channel 接收消息并发送给客户端
    let send_task = tokio::spawn(async move {
        while let Some(msg) = rx.recv().await {
            if let Err(e) = ws_sender.send(msg).await {
                log::error!("Failed to send message: {}", e);
                break;
            }
        }
    });

    // 接收任务：从客户端接收消息
    let client_id_clone = client_id.clone();
    let receive_task = tokio::spawn(async move {
        while let Some(result) = ws_receiver.next().await {
            match result {
                Ok(msg) => {
                    match msg {
                        Message::Text(text) => {
                            log::info!("Received text from {}: {}", client_id_clone, text);
                            // 这里可以处理接收到的消息
                        }
                        Message::Binary(data) => {
                            log::info!("Received binary from {}: {} bytes", client_id_clone, data.len());
                        }
                        Message::Close(_) => {
                            log::info!("Client {} closed connection", client_id_clone);
                            break;
                        }
                        _ => {}
                    }
                }
                Err(e) => {
                    log::error!("Error receiving message from {}: {}", client_id_clone, e);
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

    log::info!("Client {} disconnected", client_id);
}
