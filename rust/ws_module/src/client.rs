/// 移动端 WebSocket 客户端
use super::types::*;
use flutter_rust_bridge::frb;
use futures_util::{SinkExt, StreamExt};
use std::sync::Arc;
use tokio::sync::{mpsc, Mutex, RwLock};
use tokio_tungstenite::{connect_async, tungstenite::protocol::Message};

/// WebSocket 客户端（Opaque 类型供 Flutter 使用）
#[frb(opaque)]
pub struct WsClient {
    config: WsClientConfig,
    state: Arc<RwLock<WsConnectionState>>,
    message_tx: Arc<Mutex<Option<mpsc::Sender<Message>>>>,
    shutdown_tx: Arc<Mutex<Option<mpsc::Sender<()>>>>,
    // 消息接收通道
    message_rx: Arc<Mutex<Option<mpsc::Receiver<WsMessage>>>>,
}

impl WsClient {
    /// 创建 WebSocket 客户端
    pub fn new(url: String) -> Self {
        Self {
            config: WsClientConfig {
                url,
                auto_reconnect: true,
                reconnect_interval_ms: 3000,
                max_reconnect_attempts: 0,
            },
            state: Arc::new(RwLock::new(WsConnectionState::Disconnected)),
            message_tx: Arc::new(Mutex::new(None)),
            shutdown_tx: Arc::new(Mutex::new(None)),
            message_rx: Arc::new(Mutex::new(None)),
        }
    }

    /// 连接到 WebSocket 服务器
    pub async fn connect(&self) -> Result<(), String> {
        // 更新状态为连接中
        {
            let mut state = self.state.write().await;
            *state = WsConnectionState::Connecting;
        }

        let url = self.config.url.clone();
        log::info!("Connecting to WebSocket server: {}", url);

        let (ws_stream, _) = connect_async(&url)
            .await
            .map_err(|e| format!("Failed to connect to {}: {}", url, e))?;

        log::info!("WebSocket connection established");

        // 更新状态为已连接
        {
            let mut state = self.state.write().await;
            *state = WsConnectionState::Connected;
        }

        let (mut ws_sender, mut ws_receiver) = ws_stream.split();
        let (message_tx, mut message_rx) = mpsc::channel::<Message>(100);
        let (shutdown_tx, mut shutdown_rx) = mpsc::channel::<()>(1);
        let (received_tx, received_rx) = mpsc::channel::<WsMessage>(100);

        // 保存发送通道
        {
            let mut tx_guard = self.message_tx.lock().await;
            *tx_guard = Some(message_tx);
        }

        // 保存关闭通道
        {
            let mut shutdown_guard = self.shutdown_tx.lock().await;
            *shutdown_guard = Some(shutdown_tx);
        }

        // 保存接收通道
        {
            let mut rx_guard = self.message_rx.lock().await;
            *rx_guard = Some(received_rx);
        }

        let state_clone = self.state.clone();

        // 发送任务：从 channel 接收消息并发送到服务器
        let send_task = tokio::spawn(async move {
            loop {
                tokio::select! {
                    Some(msg) = message_rx.recv() => {
                        if let Err(e) = ws_sender.send(msg).await {
                            log::error!("Failed to send message: {}", e);
                            break;
                        }
                    }
                    _ = shutdown_rx.recv() => {
                        log::info!("Client shutdown signal received");
                        break;
                    }
                }
            }
        });

        let state_clone2 = state_clone.clone();

        // 接收任务：从服务器接收消息
        let receive_task = tokio::spawn(async move {
            while let Some(result) = ws_receiver.next().await {
                match result {
                    Ok(msg) => {
                        match msg {
                            Message::Text(text) => {
                                log::info!("Received text: {}", text);
                                let ws_msg = WsMessage::text(text.to_string());
                                let _ = received_tx.send(ws_msg).await;
                            }
                            Message::Binary(data) => {
                                log::info!("Received binary: {} bytes", data.len());
                                // 将二进制数据编码为 base64
                                use base64::{engine::general_purpose, Engine as _};
                                let encoded = general_purpose::STANDARD.encode(&data);
                                let ws_msg = WsMessage::binary(encoded);
                                let _ = received_tx.send(ws_msg).await;
                            }
                            Message::Close(_) => {
                                log::info!("Server closed connection");
                                break;
                            }
                            _ => {}
                        }
                    }
                    Err(e) => {
                        log::error!("Error receiving message: {}", e);
                        break;
                    }
                }
            }

            // 更新状态为已断开
            {
                let mut state = state_clone2.write().await;
                *state = WsConnectionState::Disconnected;
            }
        });

        // 在后台等待任务完成
        tokio::spawn(async move {
            tokio::select! {
                _ = send_task => {},
                _ = receive_task => {},
            }

            // 更新状态
            {
                let mut state = state_clone.write().await;
                if *state != WsConnectionState::Disconnected {
                    *state = WsConnectionState::Disconnected;
                }
            }
        });

        Ok(())
    }

    /// 断开连接
    pub async fn disconnect(&self) -> Result<(), String> {
        let shutdown_guard = self.shutdown_tx.lock().await;
        if let Some(tx) = shutdown_guard.as_ref() {
            tx.send(())
                .await
                .map_err(|e| format!("Failed to send shutdown signal: {}", e))?;
        }

        // 清空发送通道
        {
            let mut tx_guard = self.message_tx.lock().await;
            *tx_guard = None;
        }

        // 更新状态
        {
            let mut state = self.state.write().await;
            *state = WsConnectionState::Disconnected;
        }

        log::info!("WebSocket client disconnected");
        Ok(())
    }

    /// 发送文本消息
    pub async fn send_text(&self, message: String) -> Result<(), String> {
        let tx_guard = self.message_tx.lock().await;
        if let Some(tx) = tx_guard.as_ref() {
            tx.send(Message::Text(message.into()))
                .await
                .map_err(|e| format!("Failed to send message: {}", e))?;
            Ok(())
        } else {
            Err("Client is not connected".to_string())
        }
    }

    /// 发送二进制消息
    pub async fn send_binary(&self, data: Vec<u8>) -> Result<(), String> {
        let tx_guard = self.message_tx.lock().await;
        if let Some(tx) = tx_guard.as_ref() {
            tx.send(Message::Binary(data.into()))
                .await
                .map_err(|e| format!("Failed to send message: {}", e))?;
            Ok(())
        } else {
            Err("Client is not connected".to_string())
        }
    }

    /// 获取连接状态
    pub async fn get_state(&self) -> WsConnectionState {
        let state = self.state.read().await;
        *state
    }

    /// 是否已连接
    pub async fn is_connected(&self) -> bool {
        let state = self.state.read().await;
        *state == WsConnectionState::Connected
    }

    /// 接收消息（非阻塞，返回 Option）
    pub async fn receive_message(&self) -> Option<WsMessage> {
        let mut rx_guard = self.message_rx.lock().await;
        if let Some(rx) = rx_guard.as_mut() {
            rx.try_recv().ok()
        } else {
            None
        }
    }
}
