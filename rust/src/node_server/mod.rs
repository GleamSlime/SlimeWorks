mod handlers;
mod media_handler;
/// 节点服务器模块
///
/// 提供本地节点 HTTP 服务，支持以下路由：
/// - POST /node/call - 动作分发（调用 media_collection / novel_reader FFI 函数）
/// - GET  /node/media - 媒体文件服务（含图片缩放、Range 请求）
/// - POST /node/upload/archive - 目录归档上传（流式落盘 + 解压，见 upload_handler）
/// - POST /node/upload - 文件上传
/// - GET  /health - 健康检查
///
/// 除 `/health` 与 CORS 预检外，所有路由都要求授权码摘要（见 `AUTH_HEADER`）。
mod router;
mod types;
mod upload_handler;

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
        // worker 数必须与并发连接容量同量级：连接线程各自 `block_on` 提交任务后
        // 就在等这个 runtime 出结果，worker 只有 2 个时第 3 个并发请求开始排队，
        // 而缩略图生成会占住 worker 几百毫秒（内部还要等同步 ffmpeg 子进程）。
        let workers = std::thread::available_parallelism()
            .map(|n| n.get())
            .unwrap_or(4)
            .clamp(4, MAX_CONNECTIONS);
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(workers)
            // 未移入 spawn_blocking 的同步 IO 落在阻塞线程池上，给它足够的额度
            // 兜底，避免饿死 worker。
            .max_blocking_threads(workers * 4)
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
    /// 授权码的 SHA-256 摘要（小写十六进制）。`None` 表示该节点未启用授权校验。
    /// 只存摘要不存明文：明文没有理由留在节点进程内存和日志里。
    pub auth_code_hash: Option<String>,
}

impl Default for NodeServerConfig {
    fn default() -> Self {
        Self {
            host: "0.0.0.0".to_string(),
            port: 17888,
            name: "本机节点".to_string(),
            auth_code_hash: None,
        }
    }
}

/// 客户端约定的授权请求头名。值 = 授权码明文的 SHA-256 十六进制摘要，
/// 明文永不上线，抓包者拿到的摘要也无法反推回授权码。
pub const AUTH_HEADER: &str = "x-sw-auth";

/// 把明文授权码归一成待校验摘要。空串/全空白一律按"未启用"处理，
/// 否则会出现"配置留空 == 只接受空摘要"这种谁都能过的假安全状态。
pub fn auth_code_hash(auth_code: &str) -> Option<String> {
    let trimmed = auth_code.trim();
    if trimmed.is_empty() {
        return None;
    }
    Some(sha256_hex(trimmed))
}

fn sha256_hex(input: &str) -> String {
    use sha2::Digest as _;
    sha2::Sha256::digest(input.as_bytes())
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

/// 媒体流摘要的查询参数名。
///
/// 图片 `<img>`/视频 Range 播放这类 URL 由 Flutter 直接交给解码器，拿不到注入自定义
/// 请求头的机会，因此同一份 sha256 摘要允许以 `?sw_auth=<hex>` 形式提供。
/// API 调用（`/node/call`、`/node/upload`）仍走 `X-SW-Auth` 请求头。
pub const AUTH_QUERY_PARAM: &str = "sw_auth";

fn query_value<'a>(path: &'a str, key: &str) -> Option<&'a str> {
    let (_, query) = path.split_once('?')?;
    query.split('&').find_map(|pair| {
        let mut halves = pair.splitn(2, '=');
        match (halves.next(), halves.next()) {
            (Some(k), Some(v)) if k == key => Some(v),
            _ => None,
        }
    })
}

/// 请求是否通过授权校验。
///
/// 两条刻意放行：`/health`（客户端要靠它区分"节点不在线"和"授权码不对"，
/// 锁死就没法给出可操作的错误提示）、`OPTIONS`（CORS 预检，真正的请求随后仍会被拒）。
fn is_authorized(
    config: &NodeServerConfig,
    header_value: Option<&str>,
    method: &str,
    path: &str,
) -> bool {
    let route = path.split('?').next().unwrap_or(path);
    if route == "/health" || method.eq_ignore_ascii_case("OPTIONS") {
        return true;
    }
    let provided = header_value.or_else(|| query_value(path, AUTH_QUERY_PARAM));
    match (&config.auth_code_hash, provided) {
        // 节点未配置授权码：保持旧行为，不校验
        (None, _) => true,
        (Some(expected), Some(provided)) => provided.trim().eq_ignore_ascii_case(expected),
        (Some(_), None) => false,
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
/// 因并发打满而拒绝连接的次数（只用于日志节流）
static BUSY_REJECTIONS: AtomicUsize = AtomicUsize::new(0);

/// 并发打满时回一个 503，而不是静默断开。
///
/// 静默 RST 在客户端看来和「节点死了」完全一样，会让一次偶发的连接数峰值
/// 直接把节点判成熔断；回 503 则是「我在线，只是忙」，探测据此解除熔断。
fn reject_busy(stream: &mut TcpStream) {
    let count = BUSY_REJECTIONS.fetch_add(1, Ordering::Relaxed) + 1;
    if count == 1 || count % 50 == 0 {
        println!(
            "[node-conn] 并发已满(>={})，第 {} 次回 503",
            MAX_CONNECTIONS, count
        );
    }
    let body = types::NodeResponse::error(format!(
        "node busy: {} concurrent connections",
        MAX_CONNECTIONS
    ))
    .to_json();
    let header = format!(
        "HTTP/1.1 503 Service Unavailable\r\nContent-Type: application/json\r\nContent-Length: {}\r\nRetry-After: 1\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n",
        body.len()
    );
    let _ = stream.write_all(header.as_bytes());
    let _ = stream.write_all(body.as_bytes());
    let _ = stream.flush();
}

// ── 辅助 ─────────────────────────────────────────────────────────────────────

/// 尝试清理占用端口的旧进程。
///
/// unix 用 lsof + kill -9；Windows 用 netstat 定位占用端口的 PID 后 taskkill /F 强杀。
/// 两端都属"激进清理"：残留的旧节点进程若仍占着端口，bind 必然失败（Windows 上是
/// os error 10048「每个套接字地址只允许使用一次」），此时直接把占用者杀掉再重绑。
fn kill_process_on_port(#[cfg_attr(not(any(unix, windows)), allow(unused_variables))] port: u16) {
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

    #[cfg(windows)]
    {
        let self_pid = std::process::id();
        let suffix = format!(":{}", port);
        let mut targets: Vec<u32> = Vec::new();

        // netstat -ano -p tcp：数据行格式为 协议 本地地址 外部地址 状态 PID，
        // 表头会本地化但数据行不变；只取本地地址精确匹配 :port 的行，末列即 PID。
        if let Ok(out) = std::process::Command::new("netstat")
            .args(["-ano", "-p", "tcp"])
            .output()
        {
            for line in String::from_utf8_lossy(&out.stdout).lines() {
                let cols: Vec<&str> = line.split_whitespace().collect();
                if cols.len() < 5 {
                    continue;
                }
                // 本地地址（第 2 列）端口精确匹配，避免误伤连到远端 :port 的出站连接
                if !cols[1].ends_with(&suffix) {
                    continue;
                }
                if let Ok(pid) = cols[4].parse::<u32>() {
                    // 跳过自己与 PID 0（系统保留），其余占用者一律强杀
                    if pid != 0 && pid != self_pid && !targets.contains(&pid) {
                        targets.push(pid);
                    }
                }
            }
        }

        for pid in targets {
            let _ = std::process::Command::new("taskkill")
                .args(["/F", "/PID", &pid.to_string()])
                .output();
        }
        // taskkill 是异步回收端口，稍等再让调用方重绑
        std::thread::sleep(std::time::Duration::from_millis(400));
    }
}

/// 【临时埋点】节点侧单请求耗时，日志格式 `标签(+NN.NNNs)`。
/// 走 log_info 而不是 println：这样在节点那台机器的日志文件里也查得到。
fn trace_elapsed(started: std::time::Instant, label: &str) {
    let secs = started.elapsed().as_secs_f64();
    crate::api::logger::log_info(&format!("[耗时][节点] {label}(+{secs:.3}s)"));
}

/// 处理单个连接：解析请求行 → 调用路由 → 写回响应
///
/// 所有响应都显式带 `Connection: close`：一个连接只服务一个请求就 return
/// （socket 随即关闭），但 HTTP/1.1 默认 keep-alive。不写这个头，dart:io 会把
/// 已经收到 FIN 的 socket 放回空闲池复用，下一个请求发进死连接后收不到任何
/// 响应，只能干等到 Dio 的 receiveTimeout（12s）才失败重试 —— 这正是
/// 「远程节点取数要卡 10 秒以上」的根因。
fn handle_connection(mut stream: TcpStream, config: Arc<NodeServerConfig>) {
    let conn_started = std::time::Instant::now();
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
    let mut auth_header: Option<String> = None;
    let mut accept_gzip = false;
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
        } else if lower.starts_with("x-sw-auth:") {
            auth_header = Some(line[10..].trim().to_string());
        } else if lower.starts_with("accept-encoding:") {
            accept_gzip = accepts_gzip(&line[16..]);
        }
    }

    // ── 授权校验 ─────────────────────────────────────────────────────────────
    // 刻意放在读 body 之前：未授权的请求连 body 都不必进内存，顺带堵掉
    // "用超大 Content-Length 打爆节点内存"这条最省事的打法。
    if !is_authorized(&config, auth_header.as_deref(), &method, &path) {
        let deny = types::NodeResponse::error("未授权：缺少或错误的 X-SW-Auth 请求头".to_string())
            .to_json();
        let _ = stream.write_all(
            format!(
                "HTTP/1.1 401 Unauthorized\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: {}\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n{}",
                deny.len(),
                deny
            )
            .as_bytes(),
        );
        return;
    }

    // ── 归档上传分流 ─────────────────────────────────────────────────────────
    // 必须走独立通道：下面的通用 body 读取是 `vec![0u8; content_length]`，
    // 一个几百 MB 的目录归档会直接把节点内存打爆。
    let route = path.split('?').next().unwrap_or(&path).to_string();
    if method == "POST" && route == "/node/upload/archive" {
        let query = path.splitn(2, '?').nth(1).unwrap_or("").to_string();
        upload_handler::handle_archive_upload(stream, &mut reader, &query, content_length);
        return;
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
                    // ping 就地回答，绝不排进共享 runtime 的队列：客户端拿它判定节点存活，
                    // 一旦排在缩略图生成/目录导入后面，探测超时就等于「节点死了」，
                    // 结果是节点一忙就被错误熔断。
                    if node_req.action == "ping" {
                        let data = serde_json::json!({ "pong": true });
                        (200, types::NodeResponse::success(data).to_json())
                    } else {
                        // 复用全局共享的 tokio runtime，避免每次请求创建/销毁 runtime
                        let action_started = std::time::Instant::now();
                        let result = shared_runtime().block_on(handlers::dispatch_action(
                            &node_req.action,
                            node_req.params,
                            &config,
                        ));
                        // 【临时埋点】节点侧动作执行耗时，>300ms 的都会被看到
                        trace_elapsed(
                            action_started,
                            &format!("节点动作 {}", node_req.action),
                        );
                        match result {
                            Ok(data) => (200, types::NodeResponse::success(data).to_json()),
                            Err(e) => (500, types::NodeResponse::error(e).to_json()),
                        }
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

            // 【临时埋点】媒体流/出图的分段耗时（两条分支各自结束时报一次）
            let media_started = std::time::Instant::now();
            // 非 Range 请求且是图片/封面模式 → 走缩略图生成（原逻辑）
            if range_header.is_none()
                && (is_cover || has_width || media_handler::is_image_path(&file_path))
            {
                let result = shared_runtime().block_on(media_handler::handle_media_query(&query));
                match result {
                    Ok(response_bytes) => {
                        let content_type = media_handler::guess_media_content_type(&file_path);
                        let header = format!(
                            "HTTP/1.1 200 OK\r\nContent-Type: {}\r\nContent-Length: {}\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n",
                            content_type,
                            response_bytes.len()
                        );
                        let _ = stream.write_all(header.as_bytes());
                        let _ = stream.write_all(&response_bytes);
                        trace_elapsed(
                            media_started,
                            &format!("节点出图 {} bytes={}", file_path, response_bytes.len()),
                        );
                        return;
                    }
                    Err(e) => {
                        let err_body = format!("media error: {}", e);
                        let header = format!(
                            "HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\nContent-Length: {}\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n",
                            err_body.len()
                        );
                        let _ = stream.write_all(header.as_bytes());
                        let _ = stream.write_all(err_body.as_bytes());
                        trace_elapsed(media_started, &format!("节点出图失败 {}", file_path));
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
                    header.push_str("Access-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n");
                    let _ = stream.write_all(header.as_bytes());
                    let _ = stream.write_all(&body_bytes);
                    trace_elapsed(
                        media_started,
                        &format!("节点流媒体 {} bytes={}", file_path, body_bytes.len()),
                    );
                    return;
                }
                Err(e) => {
                    // 文件不存在必须是 404（与 hyper 路径 handle_media_request 对齐）：
                    // 客户端靠它区分「这个字幕文件没有」与「节点出错了」，
                    // 统一回 500 会让逐候选探测字幕的逻辑在第一候选就中断。
                    let status_line = if e.starts_with("file not found") {
                        "404 Not Found"
                    } else {
                        "500 Internal Server Error"
                    };
                    let err_body = format!("media error: {}", e);
                    let header = format!(
                        "HTTP/1.1 {}\r\nContent-Type: text/plain\r\nContent-Length: {}\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n",
                        status_line,
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
                        "HTTP/1.1 200 OK\r\nContent-Type: image/jpeg\r\nContent-Length: {}\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n",
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
                        "HTTP/1.1 500 Internal Server Error\r\nContent-Type: application/json\r\nContent-Length: {}\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n",
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
                "HTTP/1.1 204 No Content\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, DELETE, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type, X-Sentry-Auth\r\nAccess-Control-Max-Age: 86400\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            );
            let _ = stream.write_all(header.as_bytes());
            return;
        }

        _ => (
            404,
            types::NodeResponse::error("Not Found".to_string()).to_json(),
        ),
    };

    write_json_response(&mut stream, status, &body_str, accept_gzip).ok();
    // 【临时埋点】从 accept 到写完响应的整段占用时间（含读请求体）
    trace_elapsed(
        conn_started,
        &format!("节点响应 {} {} status={}", method, route, status),
    );

    // suppress unused warning
    let _ = peer;
}

/// JSON 响应压缩阈值：比这更小的包，gzip 的头部（18 字节）和 CPU 比省下的带宽还多。
/// 更要紧的是 `ping`/连通性探测走的也是这条写回路径 —— 探测响应一旦被压缩排队，
/// 节点就会在忙的时候被误判成失联。
const GZIP_MIN_BODY_BYTES: usize = 1024;

/// 请求头的 `Accept-Encoding` 是否表示接受 gzip。
///
/// 按逗号拆 token、容忍 `gzip;q=0.5` 这类带权重的写法，`gzip;q=0` 是明确拒绝不算接受；
/// 不认通配 `*`（客户端用 `*` 通常只是占位，压缩与否则应由它自己声明 gzip 决定）。
fn accepts_gzip(value: &str) -> bool {
    value.split(',').any(|token| {
        let mut parts = token.trim().split(';');
        let name = parts.next().unwrap_or("").trim().to_ascii_lowercase();
        if name != "gzip" {
            return false;
        }
        // 权重解析不出来时按接受处理：宁可多发一次压缩，也别把请求卡死
        parts
            .find_map(|p| {
                p.trim()
                    .strip_prefix("q=")
                    .and_then(|q| q.trim().parse::<f32>().ok())
            })
            .map_or(true, |q| q > 0.0)
    })
}

/// 用 flate2 的纯 Rust 后端压缩响应体。
fn gzip_body(raw: &[u8]) -> std::io::Result<Vec<u8>> {
    use flate2::{write::GzEncoder, Compression};
    let mut encoder = GzEncoder::new(Vec::with_capacity(raw.len() / 3), Compression::new(6));
    encoder.write_all(raw)?;
    encoder.finish()
}

/// 写出 JSON 响应：客户端接受 gzip 且体积过阈值时改发压缩体。
///
/// 压缩失败（内存吃紧等）回退明文，绝不让一个已经算出来的响应凭空变成连接错误。
/// 明文回退必须发生在写任何字节之前，否则 `Content-Length` 已经按压缩长度发出去了。
fn write_json_response(
    stream: &mut TcpStream,
    status: u16,
    body_str: &str,
    accept_gzip: bool,
) -> std::io::Result<()> {
    let mut head = String::with_capacity(256);
    head.push_str(&format!(
        "HTTP/1.1 {}\r\nContent-Type: application/json; charset=utf-8\r\n",
        status_text(status)
    ));

    let mut payload: Vec<u8> = Vec::new();
    let mut gzipped = false;
    if accept_gzip && body_str.len() >= GZIP_MIN_BODY_BYTES {
        if let Ok(compressed) = gzip_body(body_str.as_bytes()) {
            // 压缩反而更大（已经是高熵内容）时不如直接发明文
            if compressed.len() < body_str.len() {
                payload = compressed;
                gzipped = true;
            }
        }
    }
    if !gzipped {
        payload = body_str.as_bytes().to_vec();
    }
    if gzipped {
        // Vary 不能省：中间缓存（将来若走 CDN）按这个头区分两种编码的副本
        head.push_str("Content-Encoding: gzip\r\nVary: Accept-Encoding\r\n");
    }
    head.push_str(&format!(
        "Content-Length: {}\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n",
        payload.len()
    ));

    stream.write_all(head.as_bytes())?;
    stream.write_all(&payload)
}

fn status_text(code: u16) -> &'static str {
    match code {
        200 => "200 OK",
        204 => "204 No Content",
        400 => "400 Bad Request",
        401 => "401 Unauthorized",
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

/// 启动节点服务器。
///
/// `auth_code` 为空串时不启用授权校验（兼容未配置的旧部署）；非空时除 `/health`
/// 与 CORS 预检外的所有路由都要求 `X-SW-Auth` 头等于该授权码的 SHA-256 摘要。
pub fn start_node_server(
    host: String,
    port: u16,
    name: String,
    auth_code: String,
) -> Result<(), String> {
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
    let auth_code_hash = auth_code_hash(&auth_code);
    let config = Arc::new(NodeServerConfig {
        host,
        port,
        name,
        auth_code_hash: auth_code_hash.clone(),
    });
    // 只报"是否启用"，绝不打印摘要本身：日志里的摘要等价于口令
    println!(
        "[node-server] auth check {}",
        if auth_code_hash.is_some() {
            "enabled (sha256 header)"
        } else {
            "disabled (no auth code configured)"
        }
    );

    {
        let running = Arc::clone(&running);
        let config = Arc::clone(&config);
        std::thread::Builder::new()
            .name("node-server-accept".into())
            .spawn(move || {
                while running.load(Ordering::SeqCst) {
                    match listener.accept() {
                        Ok((mut stream, _addr)) => {
                            if !running.load(Ordering::SeqCst) {
                                break;
                            }
                            let cfg = Arc::clone(&config);
                            // 限制最大并发连接数，防止 FD 耗尽
                            if ACTIVE_CONNECTIONS.fetch_add(1, Ordering::Relaxed) >= MAX_CONNECTIONS
                            {
                                ACTIVE_CONNECTIONS.fetch_sub(1, Ordering::Relaxed);
                                reject_busy(&mut stream);
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

#[cfg(test)]
mod tests {
    use super::*;

    fn config_with_code(auth_code: &str) -> NodeServerConfig {
        NodeServerConfig {
            auth_code_hash: auth_code_hash(auth_code),
            ..Default::default()
        }
    }

    #[test]
    fn auth_code_hash_matches_known_sha256_vector() {
        // 与 `printf test | shasum -a 256` 的输出对齐，确保线上摘要可对账
        assert_eq!(
            auth_code_hash("test").as_deref(),
            Some("9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08")
        );
    }

    #[test]
    fn blank_auth_code_disables_check() {
        // 配置留空必须是"不校验"，而不是"只接受空摘要"
        assert_eq!(auth_code_hash(""), None);
        assert_eq!(auth_code_hash("   "), None);
        assert!(is_authorized(
            &NodeServerConfig::default(),
            None,
            "POST",
            "/node/call"
        ));
    }

    #[test]
    fn trimming_and_case_of_header_value_are_tolerated() {
        let config = config_with_code("test");
        let correct = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08";
        assert!(is_authorized(&config, Some(correct), "POST", "/node/call"));
        assert!(is_authorized(&config, Some(&correct.to_uppercase()), "POST", "/node/call"));
        assert!(is_authorized(&config, Some(&format!("  {correct} ")), "POST", "/node/call"));
        // 前后空白参与明文哈希：授权码本身不会带空白
        assert_eq!(config_with_code("  test  ").auth_code_hash, config.auth_code_hash);
    }

    #[test]
    fn missing_or_wrong_header_is_rejected() {
        let config = config_with_code("slime-node");
        assert!(!is_authorized(&config, None, "POST", "/node/call"));
        assert!(!is_authorized(&config, Some(""), "POST", "/node/call"));
        assert!(!is_authorized(
            &config,
            Some("9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"),
            "POST",
            "/node/call"
        ));
        // 带 query 的路径同样受保护（路径比对只看 ? 之前）
        assert!(!is_authorized(
            &config,
            None,
            "GET",
            "/node/media?path=/tmp/a.jpg&width=320"
        ));
    }

    #[test]
    fn health_and_preflight_stay_open() {
        let config = config_with_code("slime-node");
        assert!(is_authorized(&config, None, "GET", "/health"));
        assert!(is_authorized(&config, None, "OPTIONS", "/node/call"));
    }

    #[test]
    fn media_url_may_carry_digest_as_query_param() {
        let config = config_with_code("slime-node");
        let digest = config.auth_code_hash.clone().unwrap();
        // 图片/视频流拿不到请求头，允许 ?sw_auth=<摘要>
        assert!(is_authorized(
            &config,
            None,
            "GET",
            &format!("/node/media?path=/tmp/a.jpg&sw_auth={digest}")
        ));
        assert!(!is_authorized(
            &config,
            None,
            "GET",
            "/node/media?path=/tmp/a.jpg&sw_auth=deadbeef"
        ));
        // 摘要与其他 query 参数的顺序无关
        assert!(query_value(&format!("/x?sw_auth={digest}&p=1"), AUTH_QUERY_PARAM).is_some());
        assert!(query_value("/x?p=1", AUTH_QUERY_PARAM).is_none());
    }

    /// 走真 socket 的握手测试：请求头是手写解析（`line[10..]` 这类切片），
    /// 只用纯函数断言证明不了它切对了。
    #[test]
    fn socket_handshake_accepts_header_and_query_digest() {
        use std::io::{Read, Write};
        use std::net::{TcpListener, TcpStream};

        let config = Arc::new(config_with_code("slime-node"));
        let digest = config.auth_code_hash.clone().unwrap();
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
        let port = listener.local_addr().unwrap().port();
        let server_cfg = Arc::clone(&config);
        // detached：accept 循环不阻塞测试结束，进程退出时随之回收
        let _server = std::thread::spawn(move || {
            for incoming in listener.incoming() {
                match incoming {
                    Ok(stream) => handle_connection(stream, Arc::clone(&server_cfg)),
                    Err(_) => break,
                }
            }
        });

        // 未知路由：授权通过后会是 404，未授权则是 401 —— 用状态码区分两道关卡
        let send = |request: &str| -> String {
            let mut stream = TcpStream::connect(format!("127.0.0.1:{port}")).expect("connect");
            stream.write_all(request.as_bytes()).expect("write");
            let mut response = String::new();
            stream.read_to_string(&mut response).expect("read");
            response
        };

        assert!(send("GET /node/nope HTTP/1.1\r\nHost: x\r\n\r\n").starts_with("HTTP/1.1 401"));
        assert!(send(&format!(
            "GET /node/nope HTTP/1.1\r\nHost: x\r\nX-SW-Auth: {digest}\r\n\r\n"
        ))
        .starts_with("HTTP/1.1 404"));
        // 请求头名大小写不敏感（HTTP 语义）
        assert!(send(&format!(
            "GET /node/nope HTTP/1.1\r\nHost: x\r\nx-sw-auth: {digest}\r\n\r\n"
        ))
        .starts_with("HTTP/1.1 404"));
        assert!(send(&format!("GET /node/nope?sw_auth={digest} HTTP/1.1\r\nHost: x\r\n\r\n"))
            .starts_with("HTTP/1.1 404"));
        assert!(send("GET /node/nope?sw_auth=deadbeef HTTP/1.1\r\nHost: x\r\n\r\n")
            .starts_with("HTTP/1.1 401"));
        // /health 免鉴权：客户端要靠它区分"不在线"和"码不对"
        assert!(send("GET /health HTTP/1.1\r\nHost: x\r\n\r\n").starts_with("HTTP/1.1 200"));
    }

    /// 播放时逐候选探测同级字幕，全靠状态码区分"没有这个字幕文件"与"节点出错了"：
    /// 不存在的媒体必须回 404（早前统一回 500，会让第一个候选就中断，有字幕也挂不上）。
    #[test]
    fn media_missing_file_is_404_and_existing_subtitle_serves_whole_bytes() {
        use std::io::{Read, Write};
        use std::net::{TcpListener, TcpStream};

        let config = Arc::new(config_with_code("slime-node"));
        let digest = config.auth_code_hash.clone().unwrap();
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
        let port = listener.local_addr().unwrap().port();
        let server_cfg = Arc::clone(&config);
        let _server = std::thread::spawn(move || {
            for incoming in listener.incoming() {
                match incoming {
                    Ok(stream) => handle_connection(stream, Arc::clone(&server_cfg)),
                    Err(_) => break,
                }
            }
        });

        let send = |request: &str| -> String {
            let mut stream = TcpStream::connect(format!("127.0.0.1:{port}")).expect("connect");
            stream.write_all(request.as_bytes()).expect("write");
            let mut response = Vec::new();
            stream.read_to_end(&mut response).expect("read");
            String::from_utf8_lossy(&response).into_owned()
        };
        let media_get = |path: &str| {
            let mut ser = url::form_urlencoded::Serializer::new(String::new());
            ser.append_pair("path", path);
            ser.append_pair("sw_auth", &digest);
            send(&format!(
                "GET /node/media?{} HTTP/1.1\r\nHost: x\r\n\r\n",
                ser.finish()
            ))
        };

        let dir = std::env::temp_dir().join(format!("sw_node_sub_{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let srt = dir.join("a.srt");
        let payload = "1\n00:00:01,000 --> 00:00:02,000\n你好\n";
        std::fs::write(&srt, payload).unwrap();

        let ok = media_get(srt.to_str().unwrap());
        assert!(ok.starts_with("HTTP/1.1 20"), "实际: {}", &ok[..ok.len().min(40)]);
        // 字幕不是音视频：整文件一次给完，不受 2MB 切片上限约束
        assert!(ok.ends_with(payload), "字幕正文不完整");
        assert!(
            ok.contains(&format!("Content-Length: {}", payload.len())),
            "实际: {ok}"
        );

        let miss = media_get("/tmp/sw_no_such_subtitle_file.srt");
        assert!(
            miss.starts_with("HTTP/1.1 404"),
            "不存在的字幕必须 404，实际: {}",
            &miss[..miss.len().min(40)]
        );
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// ping 是连通性探测用的，必须在连接线程就地回答（不进共享 runtime 队列），
    /// 并且照样受授权码保护。
    #[test]
    fn ping_is_answered_inline_and_still_requires_auth() {
        use std::io::{Read, Write};
        use std::net::{TcpListener, TcpStream};

        let config = Arc::new(config_with_code("slime-node"));
        let digest = config.auth_code_hash.clone().unwrap();
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
        let port = listener.local_addr().unwrap().port();
        let server_cfg = Arc::clone(&config);
        let _server = std::thread::spawn(move || {
            for incoming in listener.incoming() {
                match incoming {
                    Ok(stream) => handle_connection(stream, Arc::clone(&server_cfg)),
                    Err(_) => break,
                }
            }
        });

        let send = |request: &str| -> String {
            let mut stream = TcpStream::connect(format!("127.0.0.1:{port}")).expect("connect");
            stream.write_all(request.as_bytes()).expect("write");
            let mut response = String::new();
            stream.read_to_string(&mut response).expect("read");
            response
        };

        let body = r#"{"action":"ping","params":{}}"#;
        assert!(send(&format!(
            "POST /node/call HTTP/1.1\r\nHost: x\r\nContent-Length: {}\r\n\r\n{}",
            body.len(),
            body
        ))
        .starts_with("HTTP/1.1 401"));

        let response = send(&format!(
            "POST /node/call HTTP/1.1\r\nHost: x\r\nX-SW-Auth: {}\r\nContent-Length: {}\r\n\r\n{}",
            digest,
            body.len(),
            body
        ));
        assert!(response.starts_with("HTTP/1.1 200"), "响应: {response}");
        assert!(response.contains("\"pong\":true"), "响应: {response}");
    }

    // ── gzip 响应压缩 ────────────────────────────────────────────────────────

    #[test]
    fn accept_encoding_tokens_parsed_correctly() {
        assert!(accepts_gzip("gzip"));
        assert!(accepts_gzip("GZIP"));
        assert!(accepts_gzip("  gzip , deflate"));
        assert!(accepts_gzip("deflate, gzip;q=0.5"));
        assert!(accepts_gzip("gzip;x=1")); // 解析不出的权重按接受处理
        assert!(!accepts_gzip("deflate, br"));
        assert!(!accepts_gzip(""));
        // 明确拒绝，和「客户端没提」不是一回事
        assert!(!accepts_gzip("gzip;q=0"));
        assert!(!accepts_gzip("gzip;q=0.0"));
        // 不认通配：要不要压缩由客户端显式声明 gzip 决定
        assert!(!accepts_gzip("*"));
    }

    /// 走真实的 `write_json_response` 写回，收端按原始字节读（gzip 体过不了 `read_to_string`）
    fn round_trip(body: &str, accept_gzip: bool) -> Vec<u8> {
        use std::io::Read;
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
        let port = listener.local_addr().unwrap().port();
        let body_owned = body.to_string();
        let server = std::thread::spawn(move || {
            let (mut stream, _) = listener.accept().expect("accept");
            write_json_response(&mut stream, 200, &body_owned, accept_gzip).expect("write");
        });

        let mut client = TcpStream::connect(format!("127.0.0.1:{port}")).expect("connect");
        let mut raw = Vec::new();
        client.read_to_end(&mut raw).expect("read");
        server.join().expect("server 线程");
        raw
    }

    /// 拆成 (头部小写文本, body, gzip 解压后的 body)
    fn split_response(raw: &[u8]) -> (String, Vec<u8>, Vec<u8>) {
        let split_at = raw
            .windows(4)
            .position(|w| w == b"\r\n\r\n")
            .expect("响应应含头尾分隔");
        let head = String::from_utf8_lossy(&raw[..split_at]).to_ascii_lowercase();
        let body = raw[split_at + 4..].to_vec();
        use std::io::Read;
        let mut plain = Vec::new();
        flate2::read::GzDecoder::new(&body[..])
            .read_to_end(&mut plain)
            .ok();
        (head, body, plain)
    }

    /// 与真实集合列表同数量级的样本（3226 条 ≈ 1.6MB），刻意做成每条不同的内容，
    /// 免得全同的字符串把压缩比刷成虚高。
    fn sample_json_body() -> String {
        (0..30_000)
            .map(|i| format!("[\"media_collection_{i:016x}\",\"素材整理 {i}\",{}]", 1759000000 + i))
            .collect::<String>()
    }

    #[test]
    fn large_json_response_is_gzipped_when_accepted() {
        let body = sample_json_body();
        let (head, body_bytes, plain) = split_response(&round_trip(&body, true));

        assert!(head.contains("content-encoding: gzip"), "头部: {head}");
        assert!(head.contains("vary: accept-encoding"), "头部: {head}");
        let declared: usize = head
            .lines()
            .find(|l| l.starts_with("content-length:"))
            .unwrap()
            .split(':')
            .nth(1)
            .unwrap()
            .trim()
            .parse()
            .unwrap();
        // 长度必须按压缩后的实际字节声明，声明错了客户端会挂在读上
        assert_eq!(declared, body_bytes.len());
        assert_eq!(plain.len(), body.len(), "解压后应与原文等长");
        assert_eq!(String::from_utf8(plain).unwrap(), body);
        assert!(body_bytes.len() * 2 < body.len(), "压缩没生效，收益不成立");
    }

    #[test]
    fn small_or_non_accepting_client_gets_plain_json() {
        let big_body = sample_json_body();

        // 客户端没声明 gzip（例如 Rust 侧 reqwest 未开 gzip 特性）→ 明文，且能正常解析
        let (head, body_bytes, _) = split_response(&round_trip(&big_body, false));
        assert!(!head.contains("content-encoding"), "头部: {head}");
        assert_eq!(String::from_utf8(body_bytes).unwrap(), big_body);

        // 明文小响应（ping/探测那一路）低于阈值 → 不压缩，快速返回
        let small = r#"{"success":true,"data":{"pong":true}}"#;
        let (head, body_bytes, _) = split_response(&round_trip(small, true));
        assert!(!head.contains("content-encoding"), "头部: {head}");
        assert_eq!(String::from_utf8(body_bytes).unwrap(), small);
    }

    /// 端到端：从真实 socket 发一份带 `Accept-Encoding` 的请求头，走完整的
    /// 头解析 + `/node/call` 路由，确认压缩是加在业务响应上的。
    /// 上面那两条用例直接调 `write_json_response`，绕过了头解析和路由，
    /// 所以「部署后实测没压缩」这一路它们覆盖不到。
    #[test]
    fn node_call_compresses_business_response_end_to_end() {
        use std::io::{Read, Write};
        use std::net::{TcpListener, TcpStream};

        // 用 list_directories 当大块响应来源：不碰数据库，体积靠造目录控制
        let dir = std::env::temp_dir().join("sw_node_gzip_e2e");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        for i in 0..120 {
            std::fs::create_dir_all(dir.join(format!("素材目录_{i:04}_{}", "x".repeat(40))))
                .unwrap();
        }

        let config = Arc::new(config_with_code("slime-node"));
        let digest = config.auth_code_hash.clone().unwrap();
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
        let port = listener.local_addr().unwrap().port();
        let server_cfg = Arc::clone(&config);
        let _server = std::thread::spawn(move || {
            for incoming in listener.incoming() {
                match incoming {
                    Ok(stream) => handle_connection(stream, Arc::clone(&server_cfg)),
                    Err(_) => break,
                }
            }
        });

        let body = format!(
            "{{\"action\":\"list_directories\",\"params\":{{\"path\":\"{}\"}}}}",
            dir.display()
        );
        let send = |accept_encoding: &str| -> Vec<u8> {
            let mut stream = TcpStream::connect(format!("127.0.0.1:{port}")).expect("connect");
            let request = format!(
                "POST /node/call HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\nX-SW-Auth: {digest}\r\n{accept_encoding}Content-Length: {}\r\n\r\n{body}",
                body.len()
            );
            stream.write_all(request.as_bytes()).expect("write");
            let mut raw = Vec::new();
            stream.read_to_end(&mut raw).expect("read");
            raw
        };

        // 先取明文：既是对照基线，也用来确认样本确实过了压缩阈值
        let (plain_head, plain_body, _) = split_response(&send(""));
        assert!(plain_head.starts_with("http/1.1 200"), "头部: {plain_head}");
        assert!(!plain_head.contains("content-encoding"), "头部: {plain_head}");
        assert!(
            plain_body.len() >= GZIP_MIN_BODY_BYTES,
            "样本 {}B 低于阈值，本用例证明不了任何事",
            plain_body.len()
        );

        // dart:io / Dio 实际发的是这种带空格、多 token 的值
        let (gz_head, gz_body, gz_plain) =
            split_response(&send("Accept-Encoding: gzip, deflate, br\r\n"));
        assert!(gz_head.starts_with("http/1.1 200"), "头部: {gz_head}");
        assert!(gz_head.contains("content-encoding: gzip"), "头部: {gz_head}");
        assert!(gz_head.contains("vary: accept-encoding"), "头部: {gz_head}");
        assert_eq!(gz_plain, plain_body, "解压结果应与明文响应逐字节一致");
        assert!(
            gz_body.len() * 2 < plain_body.len(),
            "压缩比不成立: gz={} plain={}",
            gz_body.len(),
            plain_body.len()
        );

        // 明确拒绝压缩的客户端必须拿明文（老节点/其它语言客户端不受影响）
        let (reject_head, reject_body, _) =
            split_response(&send("Accept-Encoding: gzip;q=0\r\n"));
        assert!(!reject_head.contains("content-encoding"), "头部: {reject_head}");
        assert_eq!(reject_body, plain_body);

        let _ = std::fs::remove_dir_all(&dir);
    }
}
