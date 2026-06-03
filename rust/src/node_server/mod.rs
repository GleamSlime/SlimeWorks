mod handlers;
mod media_handler;
/// 节点服务器模块
///
/// 提供本地节点 HTTP 服务，支持以下路由：
/// - POST /node/call - 动作分发（调用 media_collection / novel_reader FFI 函数）
/// - GET  /node/media - 媒体文件服务（含图片缩放、Range 请求）
/// - POST /node/upload - 文件上传
/// - GET  /health - 健康检查
mod router;
mod types;

pub use handlers::dispatch_action;
pub use media_handler::*;
pub use router::*;
pub use types::*;

use std::io::{BufRead, BufReader, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::{
    atomic::{AtomicBool, AtomicUsize, Ordering},
    Arc, Mutex,
};

// 全局共享的多线程 tokio runtime，避免每次请求都创建/销毁 runtime 导致内存碎片
// 使用 multi-thread runtime 保证多个连接线程可并发调用 block_on
use std::sync::OnceLock;
static SHARED_RT: OnceLock<tokio::runtime::Runtime> = OnceLock::new();

fn shared_runtime() -> &'static tokio::runtime::Runtime {
    SHARED_RT.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()
            .expect("build node-server tokio runtime")
    })
}

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

/// 最大并发连接数，防止 FD 耗尽
const MAX_CONNECTIONS: usize = 30;
static ACTIVE_CONNECTIONS: AtomicUsize = AtomicUsize::new(0);

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
    // try_clone 失败通常意味着 FD 已耗尽，安全返回即可
    let cloned = match stream.try_clone() {
        Ok(s) => s,
        Err(e) => {
            println!("[node-conn] stream clone failed (fd exhausted?): {}", e);
            return;
        }
    };
    let mut reader = BufReader::new(cloned);

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
    let mut range_header: Option<String> = None;
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
        } else if lower.starts_with("range:") {
            range_header = Some(line[6..].trim().to_string());
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
                    // 复用全局共享的 tokio runtime，避免每次请求创建/销毁 runtime
                    let result = shared_runtime().block_on(handlers::dispatch_action(
                        &node_req.action,
                        node_req.params,
                        &config,
                    ));
                    match result {
                        Ok(data) => (200, types::NodeResponse::success(data).to_json()),
                        Err(e) => (500, types::NodeResponse::error(e).to_json()),
                    }
                }
                Err(e) => (
                    400,
                    types::NodeResponse::error(format!("解析请求失败: {}", e)).to_json(),
                ),
            }
        }

        ("GET", "/node/media") => {
            // 提取 query string（不依赖 hyper）
            let query = path.splitn(2, '?').nth(1).unwrap_or("").to_string();
            let file_path = query
                .split('&')
                .find_map(|p| p.strip_prefix("path="))
                .map(|p| {
                    url::form_urlencoded::parse(format!("path={}", p).as_bytes())
                        .find(|(k, _)| k == "path")
                        .map(|(_, v)| v.into_owned())
                        .unwrap_or_else(|| p.to_string())
                })
                .unwrap_or_default();
            let is_cover = query.split('&').any(|p| p == "mode=cover");
            let has_width = query
                .split('&')
                .any(|p| p.starts_with("width=") && p.len() > 6);

            // 非 Range 请求且是图片/封面模式 → 走缩略图生成（原逻辑）
            if range_header.is_none()
                && (is_cover || has_width || media_handler::is_image_path(&file_path))
            {
                let result = shared_runtime().block_on(media_handler::handle_media_query(&query));
                match result {
                    Ok(response_bytes) => {
                        let content_type = media_handler::guess_media_content_type(&file_path);
                        let header = format!(
                            "HTTP/1.1 200 OK\r\nContent-Type: {}\r\nContent-Length: {}\r\nAccess-Control-Allow-Origin: *\r\n\r\n",
                            content_type,
                            response_bytes.len()
                        );
                        let _ = stream.write_all(header.as_bytes());
                        let _ = stream.write_all(&response_bytes);
                        return;
                    }
                    Err(e) => {
                        let err_body = format!("media error: {}", e);
                        let header = format!(
                            "HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\nContent-Length: {}\r\nAccess-Control-Allow-Origin: *\r\n\r\n",
                            err_body.len()
                        );
                        let _ = stream.write_all(header.as_bytes());
                        let _ = stream.write_all(err_body.as_bytes());
                        return;
                    }
                }
            }

            // 视频/音频文件：支持 Range 请求的流式分发
            match media_handler::serve_media_file_with_range(&file_path, range_header.as_deref()) {
                Ok((status, headers, body_bytes)) => {
                    let mut header = format!("HTTP/1.1 {}\r\n", status);
                    for (k, v) in &headers {
                        header.push_str(&format!("{}: {}\r\n", k, v));
                    }
                    header.push_str("Access-Control-Allow-Origin: *\r\n\r\n");
                    let _ = stream.write_all(header.as_bytes());
                    let _ = stream.write_all(&body_bytes);
                    return;
                }
                Err(e) => {
                    let err_body = format!("media error: {}", e);
                    let header = format!(
                        "HTTP/1.1 500 Internal Server Error\r\nContent-Type: text/plain\r\nContent-Length: {}\r\nAccess-Control-Allow-Origin: *\r\n\r\n",
                        err_body.len()
                    );
                    let _ = stream.write_all(header.as_bytes());
                    let _ = stream.write_all(err_body.as_bytes());
                    return;
                }
            }
        }

        // ── Manga 中转路由 ────────────────────────────────────────────────────
        // 移动端在选择 "PC中转" 分流模式后，所有 Manga 请求都会发到这里。
        // PC 使用其自身的分流配置（channel + token）代为请求 Manga 并返回数据。
        ("GET", "/manga/ping") => (
            200,
            serde_json::json!({"success": true, "data": "pong"}).to_string(),
        ),

        ("GET", "/manga/token") => {
            let token = manga_module::api::manga_relay_get_token();
            (
                200,
                serde_json::json!({"success": true, "data": token}).to_string(),
            )
        }

        ("POST", "/manga/api") => {
            #[derive(serde::Deserialize)]
            struct RelayReq {
                path: String,
                method: String,
                body: Option<serde_json::Value>,
            }
            let req_str = String::from_utf8_lossy(&body).to_string();
            match serde_json::from_str::<RelayReq>(&req_str) {
                Ok(relay_req) => {
                    let result = shared_runtime().block_on(manga_module::api::manga_relay_api(
                        relay_req.path,
                        relay_req.method,
                        relay_req.body,
                    ));
                    match result {
                        Ok(data) => (
                            200,
                            serde_json::json!({"success": true, "data": data}).to_string(),
                        ),
                        Err(e) => (
                            500,
                            serde_json::json!({"success": false, "error": format!("{}", e)})
                                .to_string(),
                        ),
                    }
                }
                Err(e) => (
                    400,
                    serde_json::json!({"success": false, "error": format!("请求解析失败: {}", e)})
                        .to_string(),
                ),
            }
        }

        ("GET", "/manga/img") => {
            // 二进制图片响应：直接写流并返回，不走统一的 JSON 响应路径
            let query = path.splitn(2, '?').nth(1).unwrap_or("");
            let params: Vec<(String, String)> = url::form_urlencoded::parse(query.as_bytes())
                .into_owned()
                .collect();
            let file_server = params
                .iter()
                .find(|(k, _)| k == "file_server")
                .map(|(_, v)| v.clone())
                .unwrap_or_default();
            let img_path = params
                .iter()
                .find(|(k, _)| k == "path")
                .map(|(_, v)| v.clone())
                .unwrap_or_default();

            let result = shared_runtime().block_on(manga_module::api::manga_relay_image(
                file_server,
                img_path,
            ));
            match result {
                Ok(bytes) => {
                    let header = format!(
                        "HTTP/1.1 200 OK\r\nContent-Type: image/jpeg\r\nContent-Length: {}\r\nAccess-Control-Allow-Origin: *\r\n\r\n",
                        bytes.len()
                    );
                    let _ = stream.write_all(header.as_bytes());
                    let _ = stream.write_all(&bytes);
                    return;
                }
                Err(e) => {
                    let err_body = serde_json::json!({"success": false, "error": format!("{}", e)})
                        .to_string();
                    let header = format!(
                        "HTTP/1.1 500 Internal Server Error\r\nContent-Type: application/json\r\nContent-Length: {}\r\nAccess-Control-Allow-Origin: *\r\n\r\n",
                        err_body.len()
                    );
                    let _ = stream.write_all(header.as_bytes());
                    let _ = stream.write_all(err_body.as_bytes());
                    return;
                }
            }
        }

        // ── Sentry 兼容路由 ──────────────────────────────────────────────────
        // 兼容 Sentry SDK 的 store 和 envelope 端点
        // POST /api/{project_id}/store/ - 旧版 JSON 事件提交
        // POST /api/{project_id}/envelope/ - 新版 Envelope 格式提交
        // GET  /sentry/logs - 内部查询接口
        // GET  /sentry/stats - 统计接口
        // GET  /sentry/projects - 项目列表
        // DELETE /sentry/events/{event_id} - 删除事件
        ("POST", p) if p.starts_with("/api/") && p.contains("/store") => {
            let project_id = extract_sentry_project_id(&path);
            let body_str = String::from_utf8_lossy(&body).to_string();
            match sentry_log::api::sentry_log_store_raw_event(project_id, body_str) {
                Ok(()) => {
                    let resp = serde_json::json!({"id": "ok"});
                    (200, resp.to_string())
                }
                Err(e) => {
                    println!("[sentry] 存储事件失败: {}", e);
                    (400, serde_json::json!({"error": e}).to_string())
                }
            }
        }

        ("POST", p) if p.starts_with("/api/") && p.contains("/envelope") => {
            let project_id = extract_sentry_project_id(&path);
            let body_str = String::from_utf8_lossy(&body).to_string();
            match sentry_log::api::sentry_log_store_envelope(project_id, body_str) {
                Ok(()) => {
                    let resp = serde_json::json!({"id": "ok"});
                    (200, resp.to_string())
                }
                Err(e) => {
                    println!("[sentry] 存储envelope失败: {}", e);
                    (400, serde_json::json!({"error": e}).to_string())
                }
            }
        }

        ("GET", "/sentry/logs") => {
            let query = path.splitn(2, '?').nth(1).unwrap_or("");
            let filter = parse_sentry_log_filter(query);
            match sentry_log::api::sentry_log_query(filter) {
                Ok(result) => (
                    200,
                    serde_json::to_string(&result).unwrap_or_else(|_| "{}".to_string()),
                ),
                Err(e) => (500, serde_json::json!({"error": e}).to_string()),
            }
        }

        ("GET", "/sentry/stats") => match sentry_log::api::sentry_log_get_stats() {
            Ok(stats) => (
                200,
                serde_json::to_string(&stats).unwrap_or_else(|_| "{}".to_string()),
            ),
            Err(e) => (500, serde_json::json!({"error": e}).to_string()),
        },

        ("GET", "/sentry/projects") => match sentry_log::api::sentry_log_get_projects() {
            Ok(projects) => (
                200,
                serde_json::to_string(&projects).unwrap_or_else(|_| "[]".to_string()),
            ),
            Err(e) => (500, serde_json::json!({"error": e}).to_string()),
        },

        ("GET", p) if p.starts_with("/sentry/events/") => {
            let event_id = path
                .trim_start_matches("/sentry/events/")
                .trim_end_matches('/')
                .to_string();
            match sentry_log::api::sentry_log_get_event(event_id) {
                Ok(Some(event)) => (
                    200,
                    serde_json::to_string(&event).unwrap_or_else(|_| "{}".to_string()),
                ),
                Ok(None) => (404, serde_json::json!({"error": "事件不存在"}).to_string()),
                Err(e) => (500, serde_json::json!({"error": e}).to_string()),
            }
        }

        ("DELETE", p) if p.starts_with("/sentry/events/") => {
            let event_id = path
                .trim_start_matches("/sentry/events/")
                .trim_end_matches('/')
                .to_string();
            match sentry_log::api::sentry_log_delete_event(event_id) {
                Ok(true) => (200, serde_json::json!({"success": true}).to_string()),
                Ok(false) => (404, serde_json::json!({"error": "事件不存在"}).to_string()),
                Err(e) => (500, serde_json::json!({"error": e}).to_string()),
            }
        }

        ("POST", "/sentry/events/delete_batch") => {
            let req_str = String::from_utf8_lossy(&body).to_string();
            #[derive(serde::Deserialize)]
            struct BatchDeleteReq {
                event_ids: Vec<String>,
            }
            match serde_json::from_str::<BatchDeleteReq>(&req_str) {
                Ok(req) => match sentry_log::api::sentry_log_delete_events(req.event_ids) {
                    Ok(count) => (200, serde_json::json!({"deleted": count}).to_string()),
                    Err(e) => (500, serde_json::json!({"error": e}).to_string()),
                },
                Err(e) => (
                    400,
                    serde_json::json!({"error": format!("解析请求失败: {}", e)}).to_string(),
                ),
            }
        }

        ("POST", "/sentry/projects/rename") => {
            let req_str = String::from_utf8_lossy(&body).to_string();
            #[derive(serde::Deserialize)]
            struct RenameReq {
                project_id: String,
                name: String,
            }
            match serde_json::from_str::<RenameReq>(&req_str) {
                Ok(req) => {
                    match sentry_log::api::sentry_log_update_project_name(req.project_id, req.name)
                    {
                        Ok(()) => (200, serde_json::json!({"success": true}).to_string()),
                        Err(e) => (500, serde_json::json!({"error": e}).to_string()),
                    }
                }
                Err(e) => (
                    400,
                    serde_json::json!({"error": format!("解析请求失败: {}", e)}).to_string(),
                ),
            }
        }

        ("POST", "/sentry/export") => {
            let req_str = String::from_utf8_lossy(&body).to_string();
            match serde_json::from_str::<sentry_log::types::SentryLogFilter>(&req_str) {
                Ok(filter) => match sentry_log::api::sentry_log_export_json(filter) {
                    Ok(json) => (200, json),
                    Err(e) => (500, serde_json::json!({"error": e}).to_string()),
                },
                Err(e) => (
                    400,
                    serde_json::json!({"error": format!("解析过滤条件失败: {}", e)}).to_string(),
                ),
            }
        }

        ("DELETE", p) if p.starts_with("/sentry/projects/") && p.contains("/events") => {
            let project_id = path
                .trim_start_matches("/sentry/projects/")
                .trim_end_matches("/events")
                .trim_end_matches('/')
                .to_string();
            match sentry_log::api::sentry_log_clear_project_events(project_id) {
                Ok(count) => (200, serde_json::json!({"deleted": count}).to_string()),
                Err(e) => (500, serde_json::json!({"error": e}).to_string()),
            }
        }

        // ── 阿里云 DDNS 路由 ──────────────────────────────────────────────────
        ("GET", "/aliyun/status") => {
            match aliyun_module::api::aliyun_ddns_get_status() {
                Ok(status) => (
                    200,
                    serde_json::json!({"success": true, "data": serde_json::from_str::<serde_json::Value>(&status).unwrap_or(serde_json::json!({}))}).to_string(),
                ),
                Err(e) => (500, serde_json::json!({"success": false, "error": e}).to_string()),
            }
        }

        ("GET", "/aliyun/logs") => {
            match aliyun_module::api::aliyun_ddns_get_logs() {
                Ok(logs) => (
                    200,
                    serde_json::json!({"success": true, "data": serde_json::from_str::<serde_json::Value>(&logs).unwrap_or(serde_json::json!([]))}).to_string(),
                ),
                Err(e) => (500, serde_json::json!({"success": false, "error": e}).to_string()),
            }
        }

        ("GET", "/aliyun/watch_domains") => {
            match aliyun_module::api::aliyun_ddns_get_config() {
                Ok(config) => {
                    let config_val: serde_json::Value = serde_json::from_str(&config).unwrap_or(serde_json::json!({}));
                    let domains = config_val.get("watch_domains").cloned().unwrap_or(serde_json::json!([]));
                    (200, serde_json::json!({"success": true, "data": domains}).to_string())
                },
                Err(e) => (500, serde_json::json!({"success": false, "error": e}).to_string()),
            }
        }

        ("POST", "/aliyun/check_and_update") => {
            match shared_runtime().block_on(aliyun_module::api::aliyun_ddns_check_and_update()) {
                Ok(result) => (200, serde_json::json!({"success": true, "data": {"result": result}}).to_string()),
                Err(e) => (500, serde_json::json!({"success": false, "error": e}).to_string()),
            }
        }

        // OPTIONS 预检请求（CORS）
        ("OPTIONS", _) => {
            // 直接返回并提前退出
            let header = format!(
                "HTTP/1.1 204 No Content\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, DELETE, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type, X-Sentry-Auth\r\nAccess-Control-Max-Age: 86400\r\nContent-Length: 0\r\n\r\n"
            );
            let _ = stream.write_all(header.as_bytes());
            return;
        }

        _ => (
            404,
            types::NodeResponse::error("Not Found".to_string()).to_json(),
        ),
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
        204 => "204 No Content",
        400 => "400 Bad Request",
        404 => "404 Not Found",
        500 => "500 Internal Server Error",
        _ => "200 OK",
    }
}

/// 从Sentry路径中提取project_id
/// 例如: /api/1/store/ -> "1"
///       /api/2/envelope/ -> "2"
fn extract_sentry_project_id(path: &str) -> String {
    let path = path.trim_end_matches('/');
    let parts: Vec<&str> = path.split('/').collect();
    // /api/{project_id}/store 或 /api/{project_id}/envelope
    if parts.len() >= 3 && parts[1] == "api" {
        parts[2].to_string()
    } else {
        "1".to_string()
    }
}

/// 从查询字符串解析Sentry日志过滤条件
fn parse_sentry_log_filter(query: &str) -> sentry_log::types::SentryLogFilter {
    let params: Vec<(String, String)> = url::form_urlencoded::parse(query.as_bytes())
        .into_owned()
        .collect();

    let get_param = |key: &str| -> Option<String> {
        params
            .iter()
            .find(|(k, _)| k == key)
            .map(|(_, v)| v.clone())
    };

    sentry_log::types::SentryLogFilter {
        project_id: get_param("project_id"),
        level: get_param("level").map(|l| sentry_log::types::SentryLevel::parse(&l)),
        query: get_param("query"),
        environment: get_param("environment"),
        start_time: get_param("start_time"),
        end_time: get_param("end_time"),
        offset: get_param("offset")
            .and_then(|v| v.parse().ok())
            .unwrap_or(0),
        limit: get_param("limit")
            .and_then(|v| v.parse().ok())
            .unwrap_or(50),
    }
}

// ── 公开 API ─────────────────────────────────────────────────────────────────

pub fn start_node_server(host: String, port: u16, name: String) -> Result<(), String> {
    let mut guard = NODE_SERVER
        .lock()
        .map_err(|e| format!("获取锁失败: {}", e))?;

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
                            // 限制最大并发连接数，防止 FD 耗尽
                            if ACTIVE_CONNECTIONS.fetch_add(1, Ordering::Relaxed) >= MAX_CONNECTIONS
                            {
                                ACTIVE_CONNECTIONS.fetch_sub(1, Ordering::Relaxed);
                                drop(stream);
                                continue;
                            }
                            let spawn_result = std::thread::Builder::new()
                                .name("node-conn".into())
                                .spawn(move || {
                                    handle_connection(stream, cfg);
                                    ACTIVE_CONNECTIONS.fetch_sub(1, Ordering::Relaxed);
                                });
                            if spawn_result.is_err() {
                                ACTIVE_CONNECTIONS.fetch_sub(1, Ordering::Relaxed);
                            }
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

    // 空闲内存清理线程：每分钟检测一次，若媒体条目缓存超过 5 分钟未访问则自动释放
    {
        let running = Arc::clone(&running);
        std::thread::Builder::new()
            .name("node-idle-cleanup".into())
            .spawn(move || {
                const IDLE_THRESHOLD_SECS: u64 = 5 * 60; // 5 分钟无访问则释放
                const CHECK_INTERVAL_SECS: u64 = 60; // 每分钟检测一次
                while running.load(Ordering::Relaxed) {
                    std::thread::sleep(std::time::Duration::from_secs(CHECK_INTERVAL_SECS));
                    if !running.load(Ordering::Relaxed) {
                        break;
                    }
                    if media_collection::api::check_and_release_if_idle(IDLE_THRESHOLD_SECS) {
                        println!(
                            "[node-server] 媒体条目缓存空闲超过 {}s，已自动释放",
                            IDLE_THRESHOLD_SECS
                        );
                    }
                }
            })
            .ok(); // 线程创建失败不影响主逻辑
    }

    *guard = Some(NodeServerHandle { running, port });
    Ok(())
}

pub fn stop_node_server() -> Result<(), String> {
    let mut guard = NODE_SERVER
        .lock()
        .map_err(|e| format!("获取锁失败: {}", e))?;
    if let Some(old) = guard.take() {
        old.running.store(false, Ordering::SeqCst);
        let _ = std::net::TcpStream::connect(format!("127.0.0.1:{}", old.port));
    }
    // 节点停止后立即释放媒体条目内存缓存，避免闲置时占用大量内存
    media_collection::api::release_items_from_memory();
    Ok(())
}

pub fn is_node_server_running() -> bool {
    NODE_SERVER
        .lock()
        .map(|g| {
            g.as_ref()
                .map_or(false, |h| h.running.load(Ordering::SeqCst))
        })
        .unwrap_or(false)
}
