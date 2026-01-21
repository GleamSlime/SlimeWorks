use hyper::body::to_bytes;
use hyper::client::Client;
use hyper::header::{HeaderName, CONTENT_TYPE, HOST};
use hyper::{Body, Method, Request, Response, Server, StatusCode, Uri};
use regex::Regex;
use serde_json::Value;
use std::convert::Infallible;
use std::env;
use std::net::SocketAddr;
mod system_proxy2;
use crate::system_proxy2::{close_proxy, set_proxy};
use rcgen::{
    BasicConstraints, Certificate as RcgenCert, CertificateParams, DistinguishedName, DnType, IsCa,
    KeyUsagePurpose,
};
use rustls::{
    server::ClientHello, server::ResolvesServerCert, sign::CertifiedKey, Certificate as RustlsCert,
    PrivateKey,
};
use rustls_native_certs;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use std::sync::Mutex;
use std::sync::RwLock;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio_rustls::TlsAcceptor;
use tokio_rustls::TlsConnector;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let port: u16 = env::var("PORT")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(8433);

    let addr = SocketAddr::from(([0, 0, 0, 0], port));

    // 动态生成CA证书，不依赖现有文件
    println!("正在生成CA证书...");

    // prepare TLS MITM acceptor/connector
    let mut tls_acceptor_opt: Option<Arc<TlsAcceptor>> = None;
    let mut tls_connector_opt: Option<Arc<TlsConnector>> = None;

    match CertResolver::new() {
        Ok(resolver) => {
            println!("CA证书生成成功，MITM已启用");
            let server_config = rustls::ServerConfig::builder()
                .with_safe_defaults()
                .with_no_client_auth()
                .with_cert_resolver(Arc::new(resolver));
            let acceptor = TlsAcceptor::from(Arc::new(server_config));
            tls_acceptor_opt = Some(Arc::new(acceptor));

            // client connector
            let mut root_store = rustls::RootCertStore::empty();
            if let Ok(store) = rustls_native_certs::load_native_certs() {
                for cert in store {
                    root_store.add(&RustlsCert(cert.0)).ok();
                }
            }
            let client_config = rustls::ClientConfig::builder()
                .with_safe_defaults()
                .with_root_certificates(root_store)
                .with_no_client_auth();
            let connector = TlsConnector::from(Arc::new(client_config));
            tls_connector_opt = Some(Arc::new(connector));
        }
        Err(e) => {
            eprintln!("CA证书生成失败: {}，将使用原始隧道模式", e);
        }
    }

    let make_service = {
        let tls_acceptor_opt = tls_acceptor_opt.clone();
        let tls_connector_opt = tls_connector_opt.clone();
        hyper::service::make_service_fn(move |_conn| {
            let tls_acceptor_opt = tls_acceptor_opt.clone();
            let tls_connector_opt = tls_connector_opt.clone();
            async move {
                Ok::<_, Infallible>(hyper::service::service_fn(move |req| {
                    proxy_handler(req, tls_acceptor_opt.clone(), tls_connector_opt.clone())
                }))
            }
        })
    };

    println!("代理服务运行在端口 {}...", port);
    // try to set system proxy on startup (best-effort)
    let _ = tokio::spawn(async move {
        if let Err(e) = set_proxy("127.0.0.1", port, None).await {
            eprintln!("设置系统代理错误: {}", e);
        } else {
            println!("系统代理已设置为 127.0.0.1:{}", port);
        }
    });

    // run server with graceful shutdown handling (Ctrl-C) to clear system proxy
    let server = Server::bind(&addr).serve(make_service);
    let graceful = server.with_graceful_shutdown(async {
        tokio::signal::ctrl_c().await.ok();
        // best-effort clear proxy
        if let Err(e) = close_proxy().await {
            eprintln!("关闭系统代理错误: {}", e);
        } else {
            println!("系统代理已清除");
        }
    });

    graceful.await?;
    Ok(())
}

async fn proxy_handler(
    req: Request<Body>,
    tls_acceptor_opt: Option<Arc<TlsAcceptor>>,
    tls_connector_opt: Option<Arc<TlsConnector>>,
) -> Result<Response<Body>, Infallible> {
    println!("[代理] 收到请求 {} {}", req.method(), req.uri());
    if req.method() == Method::CONNECT {
        // handle CONNECT: perform MITM if TLS acceptor/connector available
        if tls_acceptor_opt.is_none() || tls_connector_opt.is_none() {
            // No CA available — perform plain TCP tunnel (no MITM) so clients can still browse.
            println!("[代理] 无CA证书，执行原始CONNECT隧道");
            if let Some(authority) = req.uri().authority() {
                let authority = authority.as_str().to_string();
                tokio::spawn(async move {
                    match hyper::upgrade::on(req).await {
                        Ok(mut upgraded) => {
                            println!("[代理] 原始隧道已升级: {}", authority);
                            let mut parts = authority.split(':');
                            let host = parts.next().unwrap_or("");
                            let port = parts
                                .next()
                                .and_then(|p| p.parse::<u16>().ok())
                                .unwrap_or(443);
                            match TcpStream::connect((host, port)).await {
                                Ok(mut server) => {
                                    let _ =
                                        tokio::io::copy_bidirectional(&mut upgraded, &mut server)
                                            .await;
                                    println!("[代理] 原始隧道已关闭: {}", authority);
                                }
                                Err(e) => eprintln!("[代理] 原始隧道连接错误 {}: {}", authority, e),
                            }
                        }
                        Err(e) => eprintln!("升级错误: {}", e),
                    }
                });

                return Ok(Response::builder()
                    .status(StatusCode::OK)
                    .body(Body::empty())
                    .unwrap());
            }
            return Ok(Response::builder()
                .status(StatusCode::BAD_REQUEST)
                .body(Body::from("无效的CONNECT authority"))
                .unwrap());
        }

        let acceptor = tls_acceptor_opt.unwrap();
        let connector = tls_connector_opt.unwrap();

        if let Some(authority) = req.uri().authority() {
            println!("[代理] CONNECT目标地址 {}", authority.as_str());
            let authority = authority.as_str().to_string();
            // spawn background task to handle upgraded connection
            tokio::spawn(async move {
                match hyper::upgrade::on(req).await {
                    Ok(upgraded) => {
                        println!("[代理] 升级成功: {}", authority);
                        if let Err(e) =
                            handle_connect_mitm(upgraded, authority.clone(), acceptor, connector)
                                .await
                        {
                            eprintln!("[代理] CONNECT MITM错误: {}", e);
                        } else {
                            println!("[代理] CONNECT MITM完成: {}", authority);
                        }
                    }
                    Err(e) => eprintln!("upgrade error: {}", e),
                }
            });

            return Ok(Response::builder()
                .status(StatusCode::OK)
                .body(Body::empty())
                .unwrap());
        }
    }

    // Build target URI: if client sent absolute URI, use it; otherwise use Host header and http scheme
    let uri = build_target_uri(&req).unwrap_or_else(|| req.uri().clone());

    // If hostname is skill.capture.com and content-type application/json, handle directly
    if let Some(host) = uri.authority().map(|a| a.as_str().to_string()) {
        if host.contains("skill.capture.com") {
            // read body as bytes and try parse json
            let whole = to_bytes(req.into_body()).await.unwrap_or_default();
            if let Ok(v) = serde_json::from_slice::<Value>(&whole) {
                if let Some(media_arr) = v.get("media") {
                    if media_arr.is_array() && media_arr.as_array().unwrap().len() > 0 {
                        if let Some(media) = media_arr.as_array().unwrap().get(0) {
                            let url_sign = media.get("url").and_then(|s| s.as_str()).unwrap_or("");
                            let url = format!(
                                "{}{}",
                                media.get("url").and_then(|s| s.as_str()).unwrap_or(""),
                                media.get("urlToken").and_then(|s| s.as_str()).unwrap_or("")
                            );
                            let cover_url =
                                media.get("coverUrl").and_then(|s| s.as_str()).unwrap_or("");
                            let file_format = media
                                .get("spec")
                                .and_then(|s| s.as_array())
                                .map(|arr| {
                                    arr.iter()
                                        .filter_map(|it| {
                                            it.get("fileFormat").and_then(|f| f.as_str())
                                        })
                                        .collect::<Vec<&str>>()
                                        .join("#")
                                })
                                .unwrap_or_default();
                            let size = media.get("fileSize").and_then(|s| s.as_u64()).unwrap_or(0);
                            let decode_key = media
                                .get("decodeKey")
                                .and_then(|s| s.as_str())
                                .unwrap_or("");
                            let description = v.get("description").cloned().unwrap_or(Value::Null);

                            let mut out = serde_json::map::Map::new();
                            out.insert("type".to_string(), Value::String("videoInfo".to_string()));
                            out.insert("url_sign".to_string(), Value::String(url_sign.to_string()));
                            out.insert("url".to_string(), Value::String(url));
                            out.insert(
                                "cover_url".to_string(),
                                Value::String(cover_url.to_string()),
                            );
                            out.insert("referer".to_string(), Value::String("".to_string()));
                            out.insert("file_format".to_string(), Value::String(file_format));
                            out.insert("platform".to_string(), Value::String("".to_string()));
                            out.insert(
                                "size".to_string(),
                                Value::Number(serde_json::Number::from(size)),
                            );
                            out.insert(
                                "type_content".to_string(),
                                Value::String("video/mp4".to_string()),
                            );
                            out.insert("type_str".to_string(), Value::String("video".to_string()));
                            out.insert(
                                "decode_key".to_string(),
                                Value::String(decode_key.to_string()),
                            );
                            out.insert("description".to_string(), description);

                            print_json(Value::Object(out));
                        }
                    }
                }
            }

            println!("[代理] 已拦截skill.capture.com的JSON并输出视频信息");
            // respond directly with ok as in TS implementation
            return Ok(Response::builder()
                .status(StatusCode::OK)
                .header("content-type", "text/plain")
                .body(Body::from("ok"))
                .unwrap());
        }
    }

    // Forward request to upstream
    let client = Client::new();

    // build new request
    let mut builder = Request::builder().method(req.method()).uri(uri.clone());

    // copy headers except hop-by-hop
    for (name, value) in req.headers().iter() {
        if is_hop_by_hop(name) {
            continue;
        }
        builder = builder.header(name, value);
    }

    let body_bytes = to_bytes(req.into_body()).await.unwrap_or_default();
    let outbound = builder.body(Body::from(body_bytes.clone())).unwrap();

    println!(
        "[代理] 转发请求到上游 {} {}",
        outbound.method(),
        outbound.uri()
    );
    match client.request(outbound).await {
        Ok(resp) => {
            let (parts, body) = resp.into_parts();
            let status = parts.status;
            let headers = parts.headers;

            let ctype = headers
                .get(CONTENT_TYPE)
                .and_then(|v| v.to_str().ok())
                .unwrap_or("");
            let body_bytes = to_bytes(body).await.unwrap_or_default();

            if ctype.starts_with("video/") && status != StatusCode::PARTIAL_CONTENT {
                let mut map = serde_json::map::Map::new();
                map.insert("type".to_string(), Value::String("video".to_string()));
                map.insert("url".to_string(), Value::String(uri.to_string()));
                println!("[代理] 检测到视频响应 {} {}", uri, ctype);
                print_json(Value::Object(map));
            }

            if let Some(authority) = uri.authority() {
                if authority.as_str().contains("res.wx.qq.com") {
                    if let Ok(mut s) = String::from_utf8(body_bytes.to_vec()) {
                        if s.contains("virtual_svg-icons-register.publish") {
                            let re = Regex::new(r"get\s*media\s*\(\)\s*\{").unwrap();
                            s = re.replace(&s, "get media(){\n    if(this.objectDesc){\n        fetch(\"https://skill.capture.com\", { method: \"POST\", mode: \"no-cors\", body: JSON.stringify(this.objectDesc) });\n    };\n").to_string();
                        }
                        return Ok(Response::builder()
                            .status(status)
                            .body(Body::from(s))
                            .unwrap());
                    }
                }
            }

            let mut builder = Response::builder().status(status);
            for (name, value) in headers.iter() {
                builder = builder.header(name, value);
            }
            let resp2 = builder.body(Body::from(body_bytes)).unwrap();
            Ok(resp2)
        }
        Err(e) => Ok(Response::builder()
            .status(StatusCode::BAD_GATEWAY)
            .body(Body::from(format!("上游请求错误: {}", e)))
            .unwrap()),
    }
}

fn is_hop_by_hop(name: &HeaderName) -> bool {
    // minimal set
    matches!(
        name.as_str().to_lowercase().as_str(),
        "connection"
            | "keep-alive"
            | "proxy-authenticate"
            | "proxy-authorization"
            | "te"
            | "trailers"
            | "transfer-encoding"
            | "upgrade"
    )
}

fn build_target_uri(req: &Request<Body>) -> Option<Uri> {
    let uri = req.uri();
    if uri.scheme().is_some() && uri.authority().is_some() {
        return Some(uri.clone());
    }
    // try host header
    if let Some(host) = req.headers().get(HOST) {
        if let Ok(host_str) = host.to_str() {
            let scheme = "http";
            let path_and_query = uri.path_and_query().map(|pq| pq.as_str()).unwrap_or("/");
            let s = format!("{}://{}{}", scheme, host_str, path_and_query);
            if let Ok(u) = s.parse::<Uri>() {
                return Some(u);
            }
        }
    }
    None
}

fn print_json(v: Value) {
    match serde_json::to_string(&v) {
        Ok(s) => println!("捕获到视频: {}", s),
        Err(_) => (),
    }
}

fn pem_to_der(pem: &str) -> Result<Vec<u8>, Box<dyn std::error::Error + Send + Sync>> {
    let begin = pem
        .find("-----BEGIN CERTIFICATE-----")
        .ok_or("找不到证书开头")?;
    let end = pem
        .find("-----END CERTIFICATE-----")
        .ok_or("找不到证书结尾")?;
    let b64 = &pem[begin + "-----BEGIN CERTIFICATE-----".len()..end];
    let b64 = b64.replace("\r", "").replace("\n", "").trim().to_string();
    let der = base64::decode(b64)?;
    Ok(der)
}

struct CertResolver {
    ca_rcgen: RcgenCert,
    cache: RwLock<HashMap<String, Arc<CertifiedKey>>>,
}

impl CertResolver {
    fn new() -> Result<Self, Box<dyn std::error::Error + Send + Sync>> {
        // 生成新的CA证书，按照 openssl.cnf 配置
        println!("[证书] 生成新的CA证书...");

        let mut params = CertificateParams::new(vec!["Skill Capture Client Root CA".to_string()]);

        // 设置 Distinguished Name（参考 openssl.cnf）
        let mut dn = DistinguishedName::new();
        dn.push(DnType::CountryName, "CN");
        dn.push(DnType::StateOrProvinceName, "Zhejiang");
        dn.push(DnType::LocalityName, "Hangzhou");
        dn.push(DnType::OrganizationName, "www.everyselect.com");
        dn.push(DnType::OrganizationalUnitName, "Skill Client");
        dn.push(DnType::CommonName, "Skill Capture Client Root CA");
        params.distinguished_name = dn;

        // CA 基本约束：pathlen:0
        params.is_ca = IsCa::Ca(BasicConstraints::Constrained(0));

        // 密钥用途（参考 openssl.cnf）
        params.key_usages = vec![
            KeyUsagePurpose::DigitalSignature,
            KeyUsagePurpose::KeyEncipherment,
            KeyUsagePurpose::KeyCertSign,
            KeyUsagePurpose::CrlSign,
        ];

        // 扩展密钥用途
        params.extended_key_usages = vec![
            rcgen::ExtendedKeyUsagePurpose::ServerAuth,
            rcgen::ExtendedKeyUsagePurpose::ClientAuth,
        ];

        // 生成证书
        let ca_rcgen = RcgenCert::from_params(params)?;
        println!("[证书] CA证书生成成功");

        // 保存CA证书到 key 目录
        let key_dir = PathBuf::from("key");
        std::fs::create_dir_all(&key_dir).ok();

        let ca_cert_path = key_dir.join("generated_ca.crt");
        let ca_cert_pem = ca_rcgen.serialize_pem()?;

        if let Err(e) = std::fs::write(&ca_cert_path, &ca_cert_pem) {
            eprintln!("[警告] 无法保存CA证书: {}", e);
        } else {
            println!("[证书] CA证书已保存到: {}", ca_cert_path.display());

            // 尝试自动安装CA证书
            match install_ca_certificate(&ca_cert_path) {
                Ok(msg) => println!("[证书] {}", msg),
                Err(e) => eprintln!("[证书] 自动安装失败: {}，请手动安装", e),
            }
        }

        Ok(Self {
            ca_rcgen,
            cache: RwLock::new(HashMap::new()),
        })
    }

    fn generate_cert(&self, name: &str) -> Option<Arc<CertifiedKey>> {
        println!("[证书] 为{}生成证书", name);
        let mut params = CertificateParams::new(vec![name.to_string()]);
        let leaf = RcgenCert::from_params(params).ok()?;
        let leaf_der = leaf.serialize_der_with_signer(&self.ca_rcgen).ok()?;
        let leaf_priv = leaf.serialize_private_key_der();
        let signing_key = rustls::sign::any_supported_type(&PrivateKey(leaf_priv)).ok()?;
        let signing_key = Arc::from(signing_key);

        // 证书链：叶子证书 + CA证书(使用rcgen生成的CA证书)
        let ca_cert_der = self.ca_rcgen.serialize_der().ok()?;
        let mut chain = vec![RustlsCert(leaf_der)];
        chain.push(RustlsCert(ca_cert_der));

        let ck = CertifiedKey::new(chain, signing_key);
        Some(Arc::new(ck))
    }
}

impl ResolvesServerCert for CertResolver {
    fn resolve(&self, client_hello: ClientHello<'_>) -> Option<Arc<CertifiedKey>> {
        let sni = client_hello.server_name()?;
        let name = sni.to_string();
        if let Some(c) = self.cache.read().unwrap().get(&name) {
            return Some(c.clone());
        }
        if let Some(ck) = self.generate_cert(&name) {
            self.cache.write().unwrap().insert(name.clone(), ck.clone());
            return Some(ck);
        }
        None
    }
}

async fn handle_connect_mitm(
    mut upgraded: hyper::upgrade::Upgraded,
    authority: String,
    acceptor: Arc<TlsAcceptor>,
    connector: Arc<TlsConnector>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    println!("[中间人] 处理CONNECT MITM: {}", authority);
    // perform TLS server handshake with client
    let client_tls = match acceptor.accept(upgraded).await {
        Ok(s) => {
            println!("[中间人] TLS服务端握手成功");
            s
        }
        Err(e) => {
            eprintln!("[中间人] TLS服务端握手失败: {}", e);
            return Err(Box::new(e));
        }
    };

    // parse authority host:port
    let mut parts = authority.split(':');
    let host = parts.next().ok_or("无效的authority")?.to_string();
    let port = parts
        .next()
        .and_then(|p| p.parse::<u16>().ok())
        .unwrap_or(443);

    println!("[中间人] 连接上游 {}:{}", host, port);
    let upstream_tcp = match TcpStream::connect((host.as_str(), port)).await {
        Ok(s) => {
            println!("[中间人] 上游TCP已连接");
            s
        }
        Err(e) => {
            eprintln!("[中间人] 上游TCP连接失败: {}", e);
            return Err(Box::new(e));
        }
    };
    let dnsname = rustls::ServerName::try_from(host.as_str()).map_err(|_| "无效的DNS名称")?;
    let upstream_tls = match connector.connect(dnsname, upstream_tcp).await {
        Ok(s) => {
            println!("[中间人] 上游TLS握手成功");
            s
        }
        Err(e) => {
            eprintln!("[中间人] 上游TLS握手失败: {}", e);
            return Err(Box::new(e));
        }
    };

    // split into read/write halves to allow Send across tasks
    let (mut client_r, mut client_w) = tokio::io::split(client_tls);
    let (mut up_r, mut up_w) = tokio::io::split(upstream_tls);

    let last_req = Arc::new(Mutex::new(None::<String>));

    // client -> upstream
    let lr1 = last_req.clone();
    let authority1 = authority.clone();
    let client_to_up = tokio::spawn(async move {
        let mut buf = Vec::new();
        let mut tmp = [0u8; 4096];
        loop {
            match client_r.read(&mut tmp).await {
                Ok(0) => break,
                Ok(n) => {
                    buf.extend_from_slice(&tmp[..n]);
                    if buf.windows(4).any(|w| w == b"\r\n\r\n") {
                        break;
                    }
                }
                Err(_) => break,
            }
        }
        if let Ok(s) = String::from_utf8(buf.clone()) {
            if let Some(first_line) = s.lines().next() {
                let parts: Vec<&str> = first_line.split_whitespace().collect();
                if parts.len() >= 2 {
                    let path = parts[1];
                    let host_line = s.lines().find(|l| l.to_lowercase().starts_with("host:"));
                    let full = if let Some(hline) = host_line {
                        let h = hline.splitn(2, ':').nth(1).unwrap_or("").trim();
                        format!("https://{}{}", h, path)
                    } else {
                        format!("https://{}{}", authority1, path)
                    };
                    *lr1.lock().unwrap() = Some(full);
                }
            }
        }
        if !buf.is_empty() {
            let _ = up_w.write_all(&buf).await;
        }
        let _ = tokio::io::copy(&mut client_r, &mut up_w).await;
    });

    // upstream -> client
    let lr2 = last_req.clone();
    let authority2 = authority.clone();
    let up_to_client = tokio::spawn(async move {
        let mut buf = Vec::new();
        let mut tmp = [0u8; 4096];
        loop {
            match up_r.read(&mut tmp).await {
                Ok(0) => break,
                Ok(n) => {
                    buf.extend_from_slice(&tmp[..n]);
                    if buf.windows(4).any(|w| w == b"\r\n\r\n") {
                        break;
                    }
                }
                Err(_) => break,
            }
        }

        let url = lr2
            .lock()
            .unwrap()
            .clone()
            .unwrap_or_else(|| authority2.clone());

        println!("[中间人] 处理响应: {} (已读取{}字节)", url, buf.len());

        // 找到headers和body的分界点
        let header_end = buf
            .windows(4)
            .position(|w| w == b"\r\n\r\n")
            .unwrap_or(buf.len());
        let headers_only = &buf[..header_end];

        if let Ok(s) = String::from_utf8(headers_only.to_vec()) {
            println!(
                "[中间人] 响应头前100字符: {}",
                &s.chars().take(100).collect::<String>()
            );

            if let Some(status_line) = s.lines().next() {
                let status_parts: Vec<&str> = status_line.split_whitespace().collect();
                let status_code = status_parts
                    .get(1)
                    .and_then(|c| c.parse::<u16>().ok())
                    .unwrap_or(0);

                println!("[中间人] 状态码: {}", status_code);

                // 检查是否是 skill.capture.com 的 JSON 响应
                if url.contains("skill.capture.com") {
                    println!("[中间人] 检测到 skill.capture.com 请求: {}", url);
                    // 需要读取响应体
                    let content_length_line = s
                        .lines()
                        .find(|l| l.to_lowercase().starts_with("content-length:"));
                    if let Some(cl_line) = content_length_line {
                        if let Some(len_str) = cl_line.splitn(2, ':').nth(1) {
                            if let Ok(len) = len_str.trim().parse::<usize>() {
                                println!("[中间人] Content-Length: {}", len);
                                if len > 0 && len < 1024 * 1024 {
                                    // 读取响应体
                                    let mut body = Vec::new();
                                    loop {
                                        match up_r.read(&mut tmp).await {
                                            Ok(0) => break,
                                            Ok(n) => {
                                                body.extend_from_slice(&tmp[..n]);
                                                if body.len() >= len {
                                                    break;
                                                }
                                            }
                                            Err(_) => break,
                                        }
                                    }
                                    if let Ok(body_str) = String::from_utf8(body.clone()) {
                                        println!(
                                            "[中间人] skill.capture.com 响应体长度: {}",
                                            body_str.len()
                                        );
                                        if let Ok(json) = serde_json::from_str::<Value>(&body_str) {
                                            println!("[中间人] skill.capture.com JSON: {}", json);
                                            if let Some(obj) = json.as_object() {
                                                if let Some(video_info) = obj.get("videoInfo") {
                                                    print_json(video_info.clone());
                                                }
                                            }
                                        }
                                    }
                                    // 将响应体也转发给客户端
                                    buf.extend_from_slice(&body);
                                }
                            }
                        }
                    }
                }

                // 检测视频 Content-Type
                let ctype_line = s
                    .lines()
                    .find(|l| l.to_lowercase().starts_with("content-type:"));
                if let Some(ctype) = ctype_line {
                    println!("[中间人] Content-Type: {}", ctype);
                    if ctype.to_lowercase().contains("video/") {
                        println!("[中间人] 检测到视频响应: {} (status={})", url, status_code);
                        // 允许 200 和 206 状态码（206是分段传输）
                        if status_code == 200 || status_code == 206 {
                            let mut map = serde_json::map::Map::new();
                            map.insert("type".to_string(), Value::String("video".to_string()));
                            map.insert("url".to_string(), Value::String(url));
                            print_json(Value::Object(map));
                        }
                    }
                }
            }
        }
        if !buf.is_empty() {
            let _ = client_w.write_all(&buf).await;
        }
        let _ = tokio::io::copy(&mut up_r, &mut client_w).await;
    });

    let _ = client_to_up.await;
    let _ = up_to_client.await;

    Ok(())
}

/// 安装CA证书到系统信任根
fn install_ca_certificate(cert_path: &PathBuf) -> Result<String, String> {
    let cert_path_str = cert_path.to_string_lossy().to_string();

    #[cfg(target_os = "windows")]
    {
        // Windows: 使用 certutil 命令（需要管理员权限）
        use std::process::Command;

        println!("[证书] 尝试安装CA证书到Windows系统（需要管理员权限）...");
        let output = Command::new("certutil")
            .args(&["-enterprise", "-f", "-AddStore", "Root", &cert_path_str])
            .output()
            .map_err(|e| format!("执行certutil失败: {}", e))?;

        if output.status.success() {
            let stdout = String::from_utf8_lossy(&output.stdout);
            Ok(format!("CA证书安装成功\n{}", stdout))
        } else {
            let stderr = String::from_utf8_lossy(&output.stderr);
            // 检查是否是权限问题
            if stderr.contains("需要管理员权限")
                || stderr.contains("拒绝访问")
                || stderr.contains("ERROR_ACCESS_DENIED")
            {
                Err(format!(
                    "需要管理员权限。请以管理员身份运行以下命令安装CA证书:\ncertutil -enterprise -f -AddStore Root \"{}\"\n\n或者手动双击证书文件安装到\"受信任的根证书颁发机构\"",
                    cert_path_str
                ))
            } else {
                Err(format!("certutil执行失败: {}", stderr))
            }
        }
    }

    #[cfg(target_os = "macos")]
    {
        // macOS: 使用 security 命令
        use std::process::Command;

        println!("[证书] 正在安装CA证书到macOS钥匙串...");
        println!("[证书] 提示：可能需要输入管理员密码");

        let output = Command::new("security")
            .args(&[
                "add-trusted-cert",
                "-d",
                "-r",
                "trustRoot",
                "-k",
                "/Library/Keychains/System.keychain",
                &cert_path_str,
            ])
            .output()
            .map_err(|e| format!("执行security命令失败: {}", e))?;

        if output.status.success() {
            Ok("CA证书安装成功".to_string())
        } else {
            let stderr = String::from_utf8_lossy(&output.stderr);
            Err(format!("security命令执行失败: {}\n\n请手动运行:\nsudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain \"{}\"", stderr, cert_path_str))
        }
    }

    #[cfg(not(any(target_os = "windows", target_os = "macos")))]
    {
        Err(format!(
            "当前平台不支持自动安装，请手动安装证书: {}",
            cert_path_str
        ))
    }
}
