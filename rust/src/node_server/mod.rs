/// 节点服务器模块
/// 
/// 提供本地节点 HTTP 服务，支持以下路由：
/// - POST /node/call - 动作分发（调用 media_collection / novel_reader FFI 函数）
/// - GET  /node/media - 媒体文件服务（含图片缩放、Range 请求）
/// - POST /node/upload - 文件上传
/// - GET  /health - 健康检查

mod router;
mod handlers;
mod media_handler;
mod types;

pub use router::*;
pub use handlers::dispatch_action;
pub use media_handler::*;
pub use types::*;

use std::io::{BufRead, BufReader, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc, Mutex,
};

// ── 公开配置 ─────────────────────────────────────────────────────────────────

/// 节点服务器配置
#[derive(Debug, Clone)]
pub struct NodeServerConfig {
    pub host: String,
    pub port: u16,
    pub name: String,
}

impl Default for NodeServerConfig {
    fn default() -> Self {
        Self {
            host: "0.0.0.0".to_string(),
            port: 17888,
            name: "本机节点".to_string(),
        }
    }
}

// ── 全局单例 ─────────────────────────────────────────────────────────────────

struct NodeServerHandle {
    running: Arc<AtomicBool>,
    /// 用一个连自己的 dummy 连接来"唤醒" accept 循环
    port: u16,
}

lazy_static::lazy_static! {
    static ref NODE_SERVER: Mutex<Option<NodeServerHandle>> = Mutex::new(None);
}

// ── 辅助 ─────────────────────────────────────────────────────────────────────

fn kill_process_on_port(port: u16) {
    #[cfg(unix)]
    {
        let _ = std::process::Command::new("sh")
            .arg("-c")
            .arg(format!(
                "lsof -ti :{} 2>/dev/null | xargs kill -9 2>/dev/null || true",
                port
            ))
            .output();
        std::thread::sleep(std::time::Duration::from_millis(400));
    }
}

/// 处理单个连接：解析请求行 → 调用路由 → 写回响应
fn handle_connection(mut stream: TcpStream, config: Arc<NodeServerConfig>) {
    stream
        .set_read_timeout(Some(std::time::Duration::from_secs(10)))
        .ok();

    let peer = stream.peer_addr().ok();
    let mut reader = BufReader::new(stream.try_clone().expect("clone stream"));

    // 读请求行
    let mut request_line = String::new();
    if reader.read_line(&mut request_line).is_err() {
        return;
    }
    let request_line = request_line.trim().to_string();
    // e.g. "GET /health HTTP/1.1"
    let parts: Vec<&str> = request_line.splitn(3, ' ').collect();
    if parts.len() < 2 {
        return;
    }
    let method = parts[0].to_uppercase();
    let path = parts[1].to_string();

    // 读 headers
    let mut content_length: usize = 0;
    loop {
        let mut line = String::new();
        if reader.read_line(&mut line).is_err() {
            break;
        }
        let line = line.trim();
        if line.is_empty() {
            break;
        }
        let lower = line.to_lowercase();
        if lower.starts_with("content-length:") {
            content_length = line[15..].trim().parse().unwrap_or(0);
        }
    }

    // 读 body
    let mut body = vec![0u8; content_length];
    if content_length > 0 {
        use std::io::Read;
        let _ = reader.read_exact(&mut body);
    }

    // ── 路由分发 ─────────────────────────────────────────────────────────────
    let (status, body_str) = match (method.as_str(), path.split('?').next().unwrap_or(&path)) {
        ("GET", "/health") => {
            let data = serde_json::json!({
                "success": true,
                "data": { "name": config.name, "port": config.port }
            });
            (200, data.to_string())
        }

        ("POST", "/node/call") => {
            let req_str = String::from_utf8_lossy(&body).to_string();
            match serde_json::from_str::<types::NodeRequest>(&req_str) {
                Ok(node_req) => {
                    // 用 tokio runtime 调用异步 handler
                    let result = tokio::runtime::Builder::new_current_thread()
                        .enable_all()
                        .build()
                        .map_err(|e| e.to_string())
                        .and_then(|rt| {
                            rt.block_on(handlers::dispatch_action(
                                &node_req.action,
                                node_req.params,
                                &config,
                            ))
                        });
                    match result {
                        Ok(data) => (200, types::NodeResponse::success(data).to_json()),
                        Err(e) => (500, types::NodeResponse::error(e).to_json()),
                    }
                }
                Err(e) => (400, types::NodeResponse::error(format!("解析请求失败: {}", e)).to_json()),
            }
        }

        ("GET", "/node/media") => {
            // 提取 query string（不依赖 hyper）
            let query = path.splitn(2, '?').nth(1).unwrap_or("").to_string();
            let result = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .map_err(|e| e.to_string())
                .and_then(|rt| {
                    rt.block_on(media_handler::handle_media_query(&query))
                });
            match result {
                Ok(response_bytes) => {
                    let content_type = media_handler::guess_media_content_type(
                        query.split('&').find_map(|p| p.strip_prefix("path=")).unwrap_or("")
                    );
                    let header = format!(
                        "HTTP/1.1 200 OK\r\nContent-Type: {}\r\nContent-Length: {}\r\nAccess-Control-Allow-Origin: *\r\n\r\n",
                        content_type,
                        response_bytes.len()
                    );
                    let _ = stream.write_all(header.as_bytes());
                    let _ = stream.write_all(&response_bytes);
                    return;
                }
                Err(e) => (500, types::NodeResponse::error(e).to_json()),
            }
        }

        _ => (404, types::NodeResponse::error("Not Found".to_string()).to_json()),
    };

    let response = format!(
        "HTTP/1.1 {}\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: {}\r\nAccess-Control-Allow-Origin: *\r\n\r\n{}",
        status_text(status),
        body_str.len(),
        body_str
    );
    let _ = stream.write_all(response.as_bytes());

    // suppress unused warning
    let _ = peer;
}

fn status_text(code: u16) -> &'static str {
    match code {
        200 => "200 OK",
        400 => "400 Bad Request",
        404 => "404 Not Found",
        500 => "500 Internal Server Error",
        _ => "200 OK",
    }
}

// ── 公开 API ─────────────────────────────────────────────────────────────────

pub fn start_node_server(host: String, port: u16, name: String) -> Result<(), String> {

    let mut guard = NODE_SERVER.lock().map_err(|e| format!("获取锁失败: {}", e))?;

    // 停旧服务
    if let Some(old) = guard.take() {
        old.running.store(false, Ordering::SeqCst);
        // 发一个 dummy 连接唤醒 accept 循环
        let _ = std::net::TcpStream::connect(format!("127.0.0.1:{}", old.port));
        std::thread::sleep(std::time::Duration::from_millis(200));
    }

    kill_process_on_port(port);

    // 绑定 socket（同步，在调用方线程完成，立即可见）
    let listener = TcpListener::bind(format!("{}:{}", host, port))
        .map_err(|e| format!("绑定端口 {} 失败: {}", port, e))?;

    let running = Arc::new(AtomicBool::new(true));
    let config = Arc::new(NodeServerConfig { host, port, name });

    {
        let running = Arc::clone(&running);
        let config = Arc::clone(&config);
        std::thread::Builder::new()
            .name("node-server-accept".into())
            .spawn(move || {
                while running.load(Ordering::SeqCst) {
                    match listener.accept() {
                        Ok((stream, _addr)) => {
                            if !running.load(Ordering::SeqCst) {
                                break;
                            }
                            let cfg = Arc::clone(&config);
                            std::thread::Builder::new()
                                .name("node-conn".into())
                                .spawn(move || handle_connection(stream, cfg))
                                .ok();
                        }
                        Err(_) => {
                            if running.load(Ordering::SeqCst) {
                                break;
                            }
                        }
                    }
                }
            })
            .map_err(|e| format!("启动线程失败: {}", e))?;
    }

    *guard = Some(NodeServerHandle { running, port });
    Ok(())
}

pub fn stop_node_server() -> Result<(), String> {
    let mut guard = NODE_SERVER.lock().map_err(|e| format!("获取锁失败: {}", e))?;
    if let Some(old) = guard.take() {
        old.running.store(false, Ordering::SeqCst);
        let _ = std::net::TcpStream::connect(format!("127.0.0.1:{}", old.port));
    }
    Ok(())
}

pub fn is_node_server_running() -> bool {
    NODE_SERVER
        .lock()
        .map(|g| g.as_ref().map_or(false, |h| h.running.load(Ordering::SeqCst)))
        .unwrap_or(false)
}
