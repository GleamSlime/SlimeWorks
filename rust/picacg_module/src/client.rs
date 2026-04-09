/// PicACG HTTP 客户端
///
/// 基于 reqwest 封装，支持代理配置、分流（Channel Routing）和 Token 管理。
///
/// ## 分流原理
/// PicACG API 域名 `picaapi.picacomic.com` 在大陆常受 DNS 污染。
/// 分流通过以下方式绕过：
/// - 分流2/3：使用 Cloudflare 或其他节点的固定 IP 地址直连，
///   在 reqwest 构建时通过 `.resolve()` 覆盖该域名的 DNS 解析。
/// - US反代：将 BASE_URL 替换为境外反向代理节点域名（如 `https://bika-api.jpacg.cc`），
///   由代理节点转发请求。
use crate::error::{PicacgError, PicacgResult};
use crate::signature;
use bytes::Bytes;
use http_body_util::{BodyExt, Full};
use hyper::{Method, Request, Uri};
use hyper_rustls::{FixedServerNameResolver, HttpsConnectorBuilder};
use hyper_util::{
    client::legacy::{connect::dns::Name, connect::HttpConnector, Client as HyperClient},
    rt::TokioExecutor,
};
use log::{debug, info, warn};
use parking_lot::RwLock;
use reqwest::{Client, Url};
use rustls::{
    client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier},
    pki_types::{CertificateDer, ServerName, UnixTime},
    ClientConfig, DigitallySignedStruct, Error as RustlsError, SignatureScheme,
};
use serde_json::Value;
use std::future::{ready, Ready};
use std::io;
use std::net::SocketAddr;
use std::sync::Arc;
use std::task::{Context, Poll};
use std::time::Duration;
use tower_service::Service;

/// 标准 API 域名
pub const API_DOMAIN: &str = "picaapi.picacomic.com";

/// 备用 API 域名（旧项目也做了同样映射）
pub const API_DOMAIN_ALT: &str = "post-api.wikawika.xyz";

/// 旧项目对 API 分流使用的 SNI 伪装域名
pub const API_SNI_HOST: &str = "picacomic.com";
pub const API_SNI_HOST_ALT: &str = "wikawika.xyz";

/// 标准 API 基础 URL
pub const BASE_URL: &str = "https://picaapi.picacomic.com";

/// 默认图片 CDN 地址
pub const IMAGE_BASE_URL: &str = "https://storage1.picacomic.com/static/";
pub const IMAGE_PROXY_BASE_JP: &str = "https://bika-img.jpacg.cc";
pub const IMAGE_PROXY_BASE_US: &str = "https://bika21-img.jpacg.cc";
pub const IMAGE_SERVER_LIST: &[&str] = &[
    "s3.picacomic.com",
    "storage.diwodiwo.xyz",
    "s2.picacomic.com",
    "storage1.picacomic.com",
    "storage-b.picacomic.com",
];
pub const IMAGE_JUMP_LIST: &[&str] = &[
    "img.picacomic.com",
    "img.diwodiwo.xyz",
    "img.safedataplj.com",
];

/// 分流配置
///
/// 选择 API 请求的路由方式：
/// - `Direct` — 标准直连（默认 DNS 解析）
/// - `ChannelIp(ip)` — 分流2/3：将 `picaapi.picacomic.com` 解析到指定 IP（绕过 DNS 污染）
/// - `ReverseProxy(base_url)` — US反代：使用该 URL 作为 API 根路径（如 `https://bika-api.jpacg.cc`）
#[derive(Debug, Clone, Default)]
pub enum ChannelMode {
    #[default]
    Direct,
    ChannelIp(String),
    ReverseProxy(String),
}

struct ClientState {
    token: String,
    proxy_url: String,
    channel: ChannelMode,
    image_server: String,
}

impl Default for ClientState {
    fn default() -> Self {
        ClientState {
            token: String::new(),
            proxy_url: String::new(),
            channel: ChannelMode::Direct,
            image_server: "storage1.picacomic.com".to_string(),
        }
    }
}

/// PicACG 客户端，线程安全（内部使用 `Arc<RwLock<>>` 保护状态）
pub struct PicacgClient {
    state: Arc<RwLock<ClientState>>,
}

impl Default for PicacgClient {
    fn default() -> Self {
        PicacgClient {
            state: Arc::new(RwLock::new(ClientState::default())),
        }
    }
}

impl PicacgClient {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn set_token(&self, token: &str) {
        self.state.write().token = token.to_string();
    }

    pub fn get_token(&self) -> String {
        self.state.read().token.clone()
    }

    pub fn set_proxy(&self, proxy_url: &str) {
        self.state.write().proxy_url = proxy_url.to_string();
    }

    pub fn clear_token(&self) {
        self.state.write().token.clear();
    }

    /// 设置分流模式
    pub fn set_channel(&self, mode: ChannelMode) {
        self.state.write().channel = mode;
    }

    /// 获取当前分流模式的描述（用于日志）
    pub fn channel_desc(&self) -> String {
        match &self.state.read().channel {
            ChannelMode::Direct => "direct".to_string(),
            ChannelMode::ChannelIp(ip) => format!("ip:{}", ip),
            ChannelMode::ReverseProxy(url) => format!("proxy:{}", url),
        }
    }

    /// 设置图片服务器域名（如 `s3.picacomic.com`）
    pub fn set_image_server(&self, server: &str) {
        self.state.write().image_server = server.to_string();
    }

    /// 获取当前图片服务器域名
    pub fn get_image_server(&self) -> String {
        self.state.read().image_server.clone()
    }

    /// 生成当前 channel 下的实际请求 URL
    ///
    /// 旧项目在反代模式会把 URL 从:
    /// `https://picaapi.picacomic.com/{path}`
    /// 改写为:
    /// `https://bika-api.jpacg.cc/picaapi.picacomic.com/{path}`
    fn compose_url_for_channel(path: &str, channel: &ChannelMode) -> String {
        let clean_path = path.trim_start_matches('/');
        match channel {
            ChannelMode::ReverseProxy(base) => {
                let base = base.trim_end_matches('/');
                format!("{}/{}/{}", base, API_DOMAIN, clean_path)
            }
            _ => format!("{}/{}", BASE_URL, clean_path),
        }
    }

    /// 旧项目在反代模式会移除 user-agent
    fn should_strip_user_agent(channel: &ChannelMode) -> bool {
        matches!(channel, ChannelMode::ReverseProxy(_))
    }

    fn sni_hostname_for_url(url: &str) -> &'static str {
        if url.contains(API_DOMAIN_ALT)
            || url.contains(API_SNI_HOST_ALT)
            || url.contains("wikawika.xyz")
        {
            API_SNI_HOST_ALT
        } else if url.contains("diwodiwo.xyz") {
            "diwodiwo.xyz"
        } else if url.contains("tipatipa.xyz") {
            "tipatipa.xyz"
        } else {
            API_SNI_HOST
        }
    }

    fn extract_host(raw: &str) -> Option<String> {
        let trimmed = raw.trim().trim_end_matches('/');
        if trimmed.is_empty() {
            return None;
        }

        if trimmed.starts_with("http://") || trimmed.starts_with("https://") {
            return Url::parse(trimmed)
                .ok()
                .and_then(|url| url.host_str().map(|host| host.to_string()));
        }

        Some(
            trimmed
                .split('/')
                .next()
                .unwrap_or(trimmed)
                .trim_end_matches(':')
                .to_string(),
        )
    }

    fn is_ip_like(host: &str) -> bool {
        let candidate = host.trim().trim_start_matches('[').trim_end_matches(']');
        candidate.parse::<std::net::IpAddr>().is_ok()
    }

    fn is_known_image_host(host: &str) -> bool {
        IMAGE_SERVER_LIST
            .iter()
            .any(|item| item.eq_ignore_ascii_case(host))
            || IMAGE_JUMP_LIST
                .iter()
                .any(|item| item.eq_ignore_ascii_case(host))
    }

    fn ensure_https_host(host: &str) -> String {
        if host.starts_with("http://") || host.starts_with("https://") {
            host.trim_end_matches('/').to_string()
        } else {
            format!("https://{}", host.trim_matches('/'))
        }
    }

    fn normalize_image_server(file_server: &str, current_image_server: &str) -> String {
        let raw = file_server
            .trim()
            .trim_end_matches('/')
            .trim_end_matches("/static")
            .trim_end_matches('/');
        let original_host =
            Self::extract_host(raw).unwrap_or_else(|| "storage1.picacomic.com".to_string());
        let current_host = Self::extract_host(current_image_server).unwrap_or_default();

        let effective_host = if !current_host.is_empty()
            && !Self::is_ip_like(&current_host)
            && Self::is_known_image_host(&original_host)
        {
            current_host
        } else if raw.is_empty() || original_host.eq_ignore_ascii_case("wikawika.xyz") {
            if current_host.is_empty() {
                "storage1.picacomic.com".to_string()
            } else {
                current_host
            }
        } else {
            original_host
        };

        Self::ensure_https_host(&effective_host)
    }

    pub fn build_image_url(file_server: &str, path: &str, current_image_server: &str) -> String {
        let server = Self::normalize_image_server(file_server, current_image_server);
        format!(
            "{}/static/{}",
            server.trim_end_matches('/'),
            path.trim_start_matches('/')
        )
    }

    fn build_image_candidate_urls(
        file_server: &str,
        path: &str,
        current_image_server: &str,
    ) -> Vec<String> {
        let primary_server = Self::normalize_image_server(file_server, current_image_server);
        let primary_host = Self::extract_host(&primary_server).unwrap_or_default();
        let mut servers = vec![primary_server];

        if Self::is_known_image_host(&primary_host) {
            for host in IMAGE_SERVER_LIST {
                if !host.eq_ignore_ascii_case(&primary_host) {
                    servers.push(Self::ensure_https_host(host));
                }
            }
        }

        servers
            .into_iter()
            .map(|server| {
                format!(
                    "{}/static/{}",
                    server.trim_end_matches('/'),
                    path.trim_start_matches('/')
                )
            })
            .collect()
    }

    fn looks_like_image_bytes(bytes: &[u8]) -> bool {
        if bytes.len() < 4 {
            return false;
        }

        bytes.starts_with(&[0xFF, 0xD8, 0xFF])
            || bytes.starts_with(&[0x89, b'P', b'N', b'G'])
            || bytes.starts_with(b"GIF87a")
            || bytes.starts_with(b"GIF89a")
            || (bytes.len() >= 12 && &bytes[0..4] == b"RIFF" && &bytes[8..12] == b"WEBP")
            || bytes.starts_with(b"BM")
    }

    fn compose_image_url_for_channel(url: &str, channel: &ChannelMode) -> PicacgResult<String> {
        match channel {
            ChannelMode::ReverseProxy(base) => {
                let proxy_base = match base.trim_end_matches('/') {
                    "https://bika-api.jpacg.cc" => IMAGE_PROXY_BASE_JP,
                    "https://bika2-api.jpacg.cc" => IMAGE_PROXY_BASE_US,
                    _ => return Ok(url.to_string()),
                };
                let parsed = Url::parse(url)
                    .map_err(|e| PicacgError::Network(format!("图片URL无效 '{}': {}", url, e)))?;
                let host = parsed
                    .host_str()
                    .ok_or_else(|| PicacgError::Network(format!("图片URL缺少host: {}", url)))?;
                let path = parsed.path().trim_start_matches('/');
                let mut proxied = format!("{}/{}/{}", proxy_base, host, path);
                if let Some(query) = parsed.query() {
                    proxied.push('?');
                    proxied.push_str(query);
                }
                Ok(proxied)
            }
            _ => Ok(url.to_string()),
        }
    }

    /// 根据当前 channel 调整请求头。
    fn rewrite_headers_for_channel(headers: &mut Vec<(String, String)>, channel: &ChannelMode) {
        if Self::should_strip_user_agent(channel) {
            headers.retain(|(k, _)| !k.eq_ignore_ascii_case("user-agent"));
        }
    }

    /// 测试指定分流模式的连通性，返回延迟（毫秒）
    ///
    /// **测试行为与原项目一致**：
    /// - 打 `categories` 端点（原 SpeedTestPingReq）
    /// - authorization 设为空字符串（原项目 `header["authorization"] = ""`）
    /// - 无论 HTTP 状态码，只要收到响应即认为可达
    /// - 该方法不改变当前客户端状态
    pub async fn test_connectivity(&self, mode: ChannelMode) -> PicacgResult<u64> {
        use std::time::Instant;

        let channel_desc = match &mode {
            ChannelMode::Direct => "直连".to_string(),
            ChannelMode::ChannelIp(ip) => format!("分流IP:{}", ip),
            ChannelMode::ReverseProxy(url) => format!("反代:{}", url),
        };
        info!("[PicACG测速] 开始测试节点: {}", channel_desc);

        let client = self.build_client_with_channel(Some(&mode))?;

        // 与原项目一致：使用 categories 端点，authorization 为空字符串
        let path = "categories";
        let url = Self::compose_url_for_channel(path, &mode);

        // build_headers 传 Some("") 使签名中包含空 authorization header（原项目行为）
        let mut headers = signature::build_headers(path, "GET", Some(""));
        Self::rewrite_headers_for_channel(&mut headers, &mode);
        debug!("[PicACG测速] 目标URL: {}", url);

        let t0 = Instant::now();
        let status = match &mode {
            ChannelMode::ChannelIp(ip) => self
                .send_via_fixed_ip(Method::GET, &url, &headers, None, ip)
                .await
                .map(|(status, _)| status),
            _ => {
                let mut req = client.get(&url);
                for (k, v) in &headers {
                    req = req.header(k.as_str(), v.as_str());
                }
                req.send()
                    .await
                    .map(|resp| resp.status().as_u16())
                    .map_err(|e| {
                        let msg = format!("节点[{}]连接失败: {}", channel_desc, e);
                        warn!("[PicACG测速] {}", msg);
                        PicacgError::Network(msg)
                    })
            }
        }?;

        let elapsed = t0.elapsed().as_millis() as u64;
        info!(
            "[PicACG测速] 节点[{}] 延迟={}ms HTTP={}",
            channel_desc, elapsed, status
        );
        Ok(elapsed)
    }

    async fn send_via_fixed_ip(
        &self,
        method: Method,
        url: &str,
        headers: &[(String, String)],
        body: Option<&Value>,
        ip_str: &str,
    ) -> PicacgResult<(u16, Value)> {
        let _ = rustls::crypto::ring::default_provider().install_default();

        let addr: SocketAddr = format!("{}:443", ip_str)
            .parse()
            .map_err(|e| PicacgError::Network(format!("分流 IP 无效 '{}': {}", ip_str, e)))?;
        let uri: Uri = url
            .parse()
            .map_err(|e| PicacgError::Network(format!("无效请求URL '{}': {}", url, e)))?;
        let sni_hostname = Self::sni_hostname_for_url(url).to_string();

        let tls = ClientConfig::builder()
            .dangerous()
            .with_custom_certificate_verifier(Arc::new(NoCertificateVerification))
            .with_no_client_auth();

        let mut http = HttpConnector::new_with_resolver(FixedResolver { addr });
        http.enforce_http(false);
        http.set_connect_timeout(Some(Duration::from_secs(5)));

        let https = HttpsConnectorBuilder::new()
            .with_tls_config(tls)
            .https_only()
            .with_server_name_resolver(FixedServerNameResolver::new(
                ServerName::try_from(sni_hostname)
                    .map_err(|e| PicacgError::Network(format!("无效SNI域名: {}", e)))?,
            ))
            .enable_all_versions()
            .wrap_connector(http);

        let client: HyperClient<_, Full<Bytes>> =
            HyperClient::builder(TokioExecutor::new()).build(https);

        let request_body = match body {
            Some(value) => serde_json::to_vec(value)
                .map(Bytes::from)
                .map_err(|e| PicacgError::Parse(format!("请求体序列化失败: {}", e)))?,
            None => Bytes::new(),
        };

        let mut builder = Request::builder().method(method).uri(uri);
        for (k, v) in headers {
            builder = builder.header(k.as_str(), v.as_str());
        }

        let request = builder
            .body(Full::new(request_body))
            .map_err(|e| PicacgError::Network(format!("构造请求失败: {}", e)))?;

        let response: hyper::Response<hyper::body::Incoming> = client
            .request(request)
            .await
            .map_err(|e| PicacgError::Network(format!("网络错误: {}", e)))?;
        let status = response.status().as_u16();
        let body_bytes = response
            .into_body()
            .collect()
            .await
            .map_err(|e| PicacgError::Network(format!("读取响应失败: {}", e)))?
            .to_bytes();
        let value: Value = serde_json::from_slice(&body_bytes).map_err(|e| {
            PicacgError::Parse(format!(
                "响应解析失败: {} body={} ",
                e,
                String::from_utf8_lossy(&body_bytes)
            ))
        })?;
        Ok((status, value))
    }

    async fn download_bytes_via_fixed_ip(&self, url: &str, ip_str: &str) -> PicacgResult<Vec<u8>> {
        let _ = rustls::crypto::ring::default_provider().install_default();

        let addr: SocketAddr = format!("{}:443", ip_str)
            .parse()
            .map_err(|e| PicacgError::Network(format!("图片分流 IP 无效 '{}': {}", ip_str, e)))?;
        let mut current_url = Url::parse(url)
            .map_err(|e| PicacgError::Network(format!("无效图片URL '{}': {}", url, e)))?;

        for _ in 0..5 {
            let uri: Uri = current_url.as_str().parse().map_err(|e| {
                PicacgError::Network(format!("无效图片URL '{}': {}", current_url, e))
            })?;
            let sni_hostname = Self::sni_hostname_for_url(current_url.as_str()).to_string();

            let tls = ClientConfig::builder()
                .dangerous()
                .with_custom_certificate_verifier(Arc::new(NoCertificateVerification))
                .with_no_client_auth();

            let mut http = HttpConnector::new_with_resolver(FixedResolver { addr });
            http.enforce_http(false);
            http.set_connect_timeout(Some(Duration::from_secs(8)));

            let https = HttpsConnectorBuilder::new()
                .with_tls_config(tls)
                .https_only()
                .with_server_name_resolver(FixedServerNameResolver::new(
                    ServerName::try_from(sni_hostname)
                        .map_err(|e| PicacgError::Network(format!("无效图片SNI域名: {}", e)))?,
                ))
                .enable_all_versions()
                .wrap_connector(http);

            let client: HyperClient<_, Full<Bytes>> =
                HyperClient::builder(TokioExecutor::new()).build(https);
            let request = Request::builder()
                .method(Method::GET)
                .uri(uri)
                .header(
                    "accept",
                    "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
                )
                .body(Full::new(Bytes::new()))
                .map_err(|e| PicacgError::Network(format!("构造图片请求失败: {}", e)))?;
            let response: hyper::Response<hyper::body::Incoming> = client
                .request(request)
                .await
                .map_err(|e| PicacgError::Network(format!("图片网络错误: {}", e)))?;
            let status = response.status();

            if status.is_redirection() {
                let location = response
                    .headers()
                    .get(hyper::header::LOCATION)
                    .and_then(|value| value.to_str().ok())
                    .ok_or_else(|| {
                        PicacgError::Network(format!("图片重定向缺少 Location: {}", current_url))
                    })?;
                current_url = if let Ok(next_url) = Url::parse(location) {
                    next_url
                } else {
                    current_url.join(location).map_err(|e| {
                        PicacgError::Network(format!("图片重定向地址无效 '{}': {}", location, e))
                    })?
                };
                debug!("[PicACG IMG] 跟随图片重定向 -> {}", current_url);
                continue;
            }

            let body = response
                .into_body()
                .collect()
                .await
                .map_err(|e| PicacgError::Network(format!("读取图片响应失败: {}", e)))?
                .to_bytes();
            if status.as_u16() >= 400 {
                return Err(PicacgError::Network(format!(
                    "图片请求失败 HTTP={} url={}",
                    status.as_u16(),
                    current_url
                )));
            }
            if !Self::looks_like_image_bytes(&body) {
                return Err(PicacgError::Network(format!(
                    "图片数据无效 url={}",
                    current_url
                )));
            }
            return Ok(body.to_vec());
        }

        Err(PicacgError::Network(format!("图片重定向次数过多: {}", url)))
    }

    pub async fn fetch_image_bytes(&self, file_server: &str, path: &str) -> PicacgResult<Vec<u8>> {
        let (channel, image_server) = {
            let state = self.state.read();
            (state.channel.clone(), state.image_server.clone())
        };

        let candidate_urls = Self::build_image_candidate_urls(file_server, path, &image_server);
        let client = self.build_client()?;
        let mut last_error: Option<PicacgError> = None;

        for raw_url in candidate_urls {
            let request_url = Self::compose_image_url_for_channel(&raw_url, &channel)?;
            debug!(
                "[PicACG IMG] 下载图片 url={} channel={:?}",
                request_url, channel
            );

            let result = match &channel {
                ChannelMode::ChannelIp(ip) => {
                    self.download_bytes_via_fixed_ip(&request_url, ip).await
                }
                _ => {
                    let response = client
                        .get(&request_url)
                        .header(
                            "accept",
                            "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
                        )
                        .send()
                        .await
                        .map_err(|e| PicacgError::Network(format!("图片网络错误: {}", e)));

                    match response {
                        Ok(response) => {
                            let status = response.status().as_u16();
                            match response.bytes().await {
                                Ok(bytes)
                                    if status < 400 && Self::looks_like_image_bytes(&bytes) =>
                                {
                                    Ok(bytes.to_vec())
                                }
                                Ok(bytes) if status >= 400 => Err(PicacgError::Network(format!(
                                    "图片请求失败 HTTP={} url={}",
                                    status, request_url
                                ))),
                                Ok(_) => Err(PicacgError::Network(format!(
                                    "图片数据无效 url={}",
                                    request_url
                                ))),
                                Err(e) => Err(PicacgError::Network(format!("读取图片失败: {}", e))),
                            }
                        }
                        Err(err) => Err(err),
                    }
                }
            };

            match result {
                Ok(bytes) => return Ok(bytes),
                Err(err) => {
                    warn!(
                        "[PicACG IMG] 图片候选地址失败 url={} err={}",
                        request_url, err
                    );
                    last_error = Some(err);
                }
            }
        }

        Err(last_error
            .unwrap_or_else(|| PicacgError::Network("图片请求失败：没有可用候选地址".to_string())))
    }

    /// 获取当前生效的 API 根 URL
    fn effective_base_url(&self) -> String {
        match &self.state.read().channel {
            ChannelMode::ReverseProxy(base) => base.trim_end_matches('/').to_string(),
            _ => BASE_URL.to_string(),
        }
    }

    fn build_client(&self) -> PicacgResult<Client> {
        self.build_client_with_channel(None)
    }

    /// 根据可选的临时 channel 模式构建客户端（None 表示使用当前状态）
    pub fn build_client_with_channel(
        &self,
        override_channel: Option<&ChannelMode>,
    ) -> PicacgResult<Client> {
        let state = self.state.read();
        let proxy_url = state.proxy_url.clone();
        let channel = override_channel.unwrap_or(&state.channel).clone();
        drop(state); // 尽早释放读锁

        let mut builder = Client::builder()
            .gzip(true)
            .no_proxy()
            .connect_timeout(Duration::from_secs(5))
            .timeout(Duration::from_secs(12));

        // 分流2/3：用指定 IP 覆盖域名 DNS 解析（SNI 保持原域名）
        // 同时关闭证书校验——原项目 httpx.Client(verify=False) 亦如此处理，
        // 因为 Cloudflare 共享 IP 上 SNI 映射不保证与目标域名证书完全匹配。
        if let ChannelMode::ChannelIp(ip_str) = &channel {
            let addr: SocketAddr = format!("{}:443", ip_str)
                .parse()
                .map_err(|e| PicacgError::Network(format!("分流 IP 无效 '{}': {}", ip_str, e)))?;
            builder = builder
                .resolve(API_DOMAIN, addr)
                // 旧项目同时映射 post-api.wikawika.xyz，避免部分接口或重定向走污染 DNS
                .resolve(API_DOMAIN_ALT, addr)
                .danger_accept_invalid_certs(true);
        }

        // 代理（分流时通常不需要代理，但保留兼容性）
        if !proxy_url.is_empty() {
            let proxy = reqwest::Proxy::all(&proxy_url)
                .map_err(|e| PicacgError::Network(format!("代理配置无效: {}", e)))?;
            builder = builder.proxy(proxy);
        }

        builder
            .build()
            .map_err(|e| PicacgError::Network(e.to_string()))
    }

    /// GET 请求
    pub async fn get(&self, path: &str) -> PicacgResult<Value> {
        let (token, channel, channel_desc) = {
            let s = self.state.read();
            let token = if s.token.is_empty() {
                None
            } else {
                Some(s.token.clone())
            };
            let channel = s.channel.clone();
            let desc = match &s.channel {
                ChannelMode::Direct => "直连".to_string(),
                ChannelMode::ChannelIp(ip) => format!("IP:{}", ip),
                ChannelMode::ReverseProxy(u) => format!("反代:{}", u),
            };
            (token, channel, desc)
        };

        let url = Self::compose_url_for_channel(path, &channel);
        debug!("[PicACG GET] {} [{}]", url, channel_desc);

        let auth_token = if path.starts_with("auth/") {
            None
        } else {
            token.as_deref()
        };
        let mut headers = signature::build_headers(path, "GET", auth_token);
        Self::rewrite_headers_for_channel(&mut headers, &channel);
        let (status, body) = match &channel {
            ChannelMode::ChannelIp(ip) => {
                self.send_via_fixed_ip(Method::GET, &url, &headers, None, ip)
                    .await
            }
            _ => {
                let client = self.build_client()?;

                let mut req = client.get(&url);
                for (k, v) in &headers {
                    req = req.header(k.as_str(), v.as_str());
                }

                let resp = req.send().await.map_err(|e| {
                    warn!("[PicACG GET] 请求失败 path={} err={}", path, e);
                    PicacgError::Network(format!("网络错误: {}", e))
                })?;
                let status = resp.status().as_u16();
                let body: Value = resp
                    .json()
                    .await
                    .map_err(|e| PicacgError::Parse(e.to_string()))?;
                Ok((status, body))
            }
        }?;
        debug!("[PicACG GET] 响应 path={} status={}", path, status);
        if status != 200 {
            warn!(
                "[PicACG GET] 非200响应 path={} status={} body={}",
                path, status, body
            );
        }
        check_api_response(status, body)
    }

    /// POST 请求
    pub async fn post(&self, path: &str, body: Value) -> PicacgResult<Value> {
        let (token, channel, channel_desc) = {
            let s = self.state.read();
            let token = if s.token.is_empty() {
                None
            } else {
                Some(s.token.clone())
            };
            let channel = s.channel.clone();
            let desc = match &s.channel {
                ChannelMode::Direct => "直连".to_string(),
                ChannelMode::ChannelIp(ip) => format!("IP:{}", ip),
                ChannelMode::ReverseProxy(u) => format!("反代:{}", u),
            };
            (token, channel, desc)
        };

        let url = Self::compose_url_for_channel(path, &channel);
        debug!("[PicACG POST] {} [{}]", url, channel_desc);

        let auth_token = if path.starts_with("auth/") {
            None
        } else {
            token.as_deref()
        };
        let mut headers = signature::build_headers(path, "POST", auth_token);
        Self::rewrite_headers_for_channel(&mut headers, &channel);
        let (status, resp_body) = match &channel {
            ChannelMode::ChannelIp(ip) => {
                self.send_via_fixed_ip(Method::POST, &url, &headers, Some(&body), ip)
                    .await
            }
            _ => {
                let client = self.build_client()?;

                let mut req = client.post(&url).json(&body);
                for (k, v) in &headers {
                    req = req.header(k.as_str(), v.as_str());
                }

                let resp = req.send().await.map_err(|e| {
                    warn!("[PicACG POST] 请求失败 path={} err={}", path, e);
                    PicacgError::Network(format!("网络错误: {}", e))
                })?;
                let status = resp.status().as_u16();
                let resp_body: Value = resp
                    .json()
                    .await
                    .map_err(|e| PicacgError::Parse(e.to_string()))?;
                Ok((status, resp_body))
            }
        }?;
        debug!("[PicACG POST] 响应 path={} status={}", path, status);
        if status != 200 {
            warn!(
                "[PicACG POST] 非200响应 path={} status={} body={}",
                path, status, resp_body
            );
        }
        check_api_response(status, resp_body)
    }

    /// PUT 请求
    pub async fn put(&self, path: &str) -> PicacgResult<Value> {
        let (token, channel, channel_desc) = {
            let s = self.state.read();
            let token = if s.token.is_empty() {
                None
            } else {
                Some(s.token.clone())
            };
            let channel = s.channel.clone();
            let desc = match &s.channel {
                ChannelMode::Direct => "直连".to_string(),
                ChannelMode::ChannelIp(ip) => format!("IP:{}", ip),
                ChannelMode::ReverseProxy(u) => format!("反代:{}", u),
            };
            (token, channel, desc)
        };

        let url = Self::compose_url_for_channel(path, &channel);
        debug!("[PicACG PUT] {} [{}]", url, channel_desc);

        let auth_token = if path.starts_with("auth/") {
            None
        } else {
            token.as_deref()
        };
        let mut headers = signature::build_headers(path, "PUT", auth_token);
        Self::rewrite_headers_for_channel(&mut headers, &channel);
        let (status, resp_body) = match &channel {
            ChannelMode::ChannelIp(ip) => {
                self.send_via_fixed_ip(Method::PUT, &url, &headers, None, ip)
                    .await
            }
            _ => {
                let client = self.build_client()?;

                let mut req = client.put(&url);
                for (k, v) in &headers {
                    req = req.header(k.as_str(), v.as_str());
                }

                let resp = req.send().await.map_err(|e| {
                    warn!("[PicACG PUT] 请求失败 path={} err={}", path, e);
                    PicacgError::Network(format!("网络错误: {}", e))
                })?;
                let status = resp.status().as_u16();
                let resp_body: Value = resp
                    .json()
                    .await
                    .map_err(|e| PicacgError::Parse(e.to_string()))?;
                Ok((status, resp_body))
            }
        }?;
        debug!("[PicACG PUT] 响应 path={} status={}", path, status);
        if status != 200 {
            warn!(
                "[PicACG PUT] 非200响应 path={} status={} body={}",
                path, status, resp_body
            );
        }
        check_api_response(status, resp_body)
    }
}

#[derive(Clone)]
struct FixedResolver {
    addr: SocketAddr,
}

impl Service<Name> for FixedResolver {
    type Response = std::iter::Once<SocketAddr>;
    type Error = io::Error;
    type Future = Ready<Result<Self::Response, Self::Error>>;

    fn poll_ready(&mut self, _cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
        Poll::Ready(Ok(()))
    }

    fn call(&mut self, _name: Name) -> Self::Future {
        ready(Ok(std::iter::once(self.addr)))
    }
}

#[derive(Debug)]
struct NoCertificateVerification;

impl ServerCertVerifier for NoCertificateVerification {
    fn verify_server_cert(
        &self,
        _end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &ServerName<'_>,
        _ocsp_response: &[u8],
        _now: UnixTime,
    ) -> Result<ServerCertVerified, RustlsError> {
        Ok(ServerCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        _message: &[u8],
        _cert: &CertificateDer<'_>,
        _dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, RustlsError> {
        Ok(HandshakeSignatureValid::assertion())
    }

    fn verify_tls13_signature(
        &self,
        _message: &[u8],
        _cert: &CertificateDer<'_>,
        _dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, RustlsError> {
        Ok(HandshakeSignatureValid::assertion())
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        rustls::crypto::ring::default_provider()
            .signature_verification_algorithms
            .supported_schemes()
    }
}

fn check_api_response(http_status: u16, body: Value) -> PicacgResult<Value> {
    let code = body
        .get("code")
        .and_then(|v| v.as_u64())
        .unwrap_or(http_status as u64) as u32;

    if code == 200 {
        Ok(body)
    } else if code == 401 || http_status == 401 {
        Err(PicacgError::Unauthorized)
    } else {
        let msg = body
            .get("message")
            .and_then(|v| v.as_str())
            .unwrap_or("未知错误")
            .to_string();
        warn!(
            "[PicACG API] 业务错误 http_status={} code={} message={}",
            http_status, code, msg
        );
        Err(PicacgError::Api(code, msg))
    }
}
