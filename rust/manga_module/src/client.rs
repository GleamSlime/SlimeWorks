use slime_logger::{sw_info, sw_warn, sw_debug};
/// Manga HTTP 客户端
///
/// 基于 reqwest 封装，支持代理配置、分流（Channel Routing）和 Token 管理。
///
/// ## 分流原理
/// Manga API 域名 `picaapi.picacomic.com` 在大陆常受 DNS 污染。
/// 分流通过以下方式绕过：
/// - 分流2/3：使用 Cloudflare 或其他节点的固定 IP 地址直连，
///   在 reqwest 构建时通过 `.resolve()` 覆盖该域名的 DNS 解析。
/// - US反代：将 BASE_URL 替换为境外反向代理节点域名（如 `https://bika-api.jpacg.cc`），
///   由代理节点转发请求。
use crate::error::{MangaError, MangaResult};
use crate::signature;
use bytes::Bytes;
use http_body_util::{BodyExt, Full};
use hyper::{Method, Request, Uri};
use hyper_rustls::{FixedServerNameResolver, HttpsConnectorBuilder};
use hyper_util::{
    client::legacy::{connect::dns::Name, connect::HttpConnector, Client as HyperClient},
    rt::TokioExecutor,
};
use parking_lot::RwLock;
use reqwest::{Client, Url};
use rustls::{
    client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier},
    pki_types::{CertificateDer, ServerName, UnixTime},
    ClientConfig, DigitallySignedStruct, Error as RustlsError, SignatureScheme,
};
use serde_json::Value;
use std::error::Error as StdError;
use std::future::{ready, Ready};
use std::io;
use std::net::SocketAddr;
use std::sync::Arc;
use std::task::{Context, Poll};
use std::time::Duration;
use tower_service::Service;

/// 标准 API 域名
pub const API_DOMAIN: &str = "picaapi.picacomic.com";

/// 分流2/3官方 IPv4/IPv6 节点（与原项目一致）
pub const CHANNEL2_IPV4: &str = "104.21.91.145";
pub const CHANNEL2_IPV6: &str = "2606:4700:d:28:dbf4:26f3:c265:73bc";
pub const CHANNEL3_IPV4: &str = "188.114.98.153";
pub const CHANNEL3_IPV6: &str = "2a06:98c1:3120:ca71:be2c:c721:d2b5:5dbf";

/// 备用 API 域名（旧项目也做了同样映射）
pub const API_DOMAIN_ALT: &str = "post-api.wikawika.xyz";

/// 旧项目对 API 分流使用的 SNI 伪装域名
pub const API_SNI_HOST: &str = "picacomic.com";
pub const API_SNI_HOST_ALT: &str = "wikawika.xyz";

/// 标准 API 基础 URL
pub const BASE_URL: &str = "https://picaapi.picacomic.com";

/// 默认图片 CDN 地址
#[allow(dead_code)]
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

/// CDN 分流默认 IP（与 api.rs 的 DEFAULT_CDN_IP 保持一致）
pub const DEFAULT_CDN_IP: &str = "104.18.227.172";

/// API 请求失败时切换分流的最大重试次数
const MAX_API_RETRY: usize = 3;
/// 图片请求失败时切换分流的最大重试次数
const MAX_IMAGE_RETRY: usize = 2;

/// 分流配置
///
/// 选择 API 请求的路由方式：
/// - `Direct` — 标准直连（默认 DNS 解析）
/// - `ChannelIp(ip)` — 分流2/3：将 `picaapi.picacomic.com` 解析到指定 IP（绕过 DNS 污染）
/// - `ReverseProxy(base_url)` — US反代：使用该 URL 作为 API 根路径（如 `https://bika-api.jpacg.cc`）
#[derive(Debug, Clone, Default, PartialEq)]
pub enum ChannelMode {
    #[default]
    Direct,
    ChannelIp(String),
    ReverseProxy(String),
    /// PC 中转：通过局域网 PC 节点服务器中转所有请求
    /// 值格式："192.168.x.x:PORT"（PC 端节点服务器地址）
    LanRelay(String),
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

/// Manga 客户端，线程安全（内部使用 `Arc<RwLock<>>` 保护状态）
pub struct MangaClient {
    state: Arc<RwLock<ClientState>>,
}

impl Default for MangaClient {
    fn default() -> Self {
        MangaClient {
            state: Arc::new(RwLock::new(ClientState::default())),
        }
    }
}

impl MangaClient {
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
            ChannelMode::LanRelay(addr) => format!("relay:{}", addr),
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

    fn compose_image_url_for_channel(url: &str, channel: &ChannelMode) -> MangaResult<String> {
        match channel {
            ChannelMode::ReverseProxy(base) => {
                let proxy_base = match base.trim_end_matches('/') {
                    "https://bika-api.jpacg.cc" => IMAGE_PROXY_BASE_JP,
                    "https://bika2-api.jpacg.cc" => IMAGE_PROXY_BASE_US,
                    _ => return Ok(url.to_string()),
                };
                let parsed = Url::parse(url)
                    .map_err(|e| MangaError::Network(format!("图片URL无效 '{}': {}", url, e)))?;
                let host = parsed
                    .host_str()
                    .ok_or_else(|| MangaError::Network(format!("图片URL缺少host: {}", url)))?;
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

    fn format_error_chain(err: &dyn StdError) -> String {
        let mut chain = format!("{}", err);
        let mut src = err.source();
        while let Some(cause) = src {
            chain.push_str(&format!(" caused by: {}", cause));
            if let Some(io_err) = cause.downcast_ref::<io::Error>() {
                chain.push_str(&format!(
                    " [os={:?} raw={}]",
                    io_err.kind(),
                    io_err.raw_os_error().unwrap_or(-1)
                ));
            }
            src = cause.source();
        }
        chain
    }

    /// 给分流2/3提供 IPv4+IPv6 双栈候选，减少在特定网络下单栈不可达的概率。
    fn channel_ip_candidates(ip: &str) -> Vec<String> {
        match ip {
            CHANNEL2_IPV4 | CHANNEL2_IPV6 => {
                vec![CHANNEL2_IPV6.to_string(), CHANNEL2_IPV4.to_string()]
            }
            CHANNEL3_IPV4 | CHANNEL3_IPV6 => {
                vec![CHANNEL3_IPV6.to_string(), CHANNEL3_IPV4.to_string()]
            }
            _ => vec![ip.to_string()],
        }
    }

    /// 判断两个 ChannelMode 是否等价（用于排除候选列表中的当前分流）
    fn channels_equal(a: &ChannelMode, b: &ChannelMode) -> bool {
        match (a, b) {
            (ChannelMode::Direct, ChannelMode::Direct) => true,
            (ChannelMode::ChannelIp(ip_a), ChannelMode::ChannelIp(ip_b)) => ip_a == ip_b,
            (ChannelMode::ReverseProxy(u_a), ChannelMode::ReverseProxy(u_b)) => u_a == u_b,
            (ChannelMode::LanRelay(a), ChannelMode::LanRelay(b)) => a == b,
            _ => false,
        }
    }

    /// 获取除当前分流外的候选分流列表（用于失败重试时临时切换）
    ///
    /// 排除 LanRelay（PC 中转地址不固定，无法假设可用），
    /// 按 Direct → 分流2 → 分流3 → CDN → JP反代 → US反代 的优先级排序。
    fn channel_fallback_list(current: &ChannelMode) -> Vec<ChannelMode> {
        let all = vec![
            ChannelMode::Direct,
            ChannelMode::ChannelIp(CHANNEL2_IPV4.to_string()),
            ChannelMode::ChannelIp(CHANNEL3_IPV4.to_string()),
            ChannelMode::ChannelIp(DEFAULT_CDN_IP.to_string()),
            ChannelMode::ReverseProxy("https://bika-api.jpacg.cc".to_string()),
            ChannelMode::ReverseProxy("https://bika2-api.jpacg.cc".to_string()),
        ];
        all.into_iter()
            .filter(|c| !Self::channels_equal(c, current))
            .collect()
    }

    /// 判断错误是否可重试（切换分流重试）
    ///
    /// 可重试：网络错误、API 业务码错误（排除 401 未登录和 400 参数错误）
    /// 不可重试：未登录、JSON 解析错误、其他错误
    fn is_retryable_error(err: &MangaError) -> bool {
        match err {
            MangaError::Network(_) => true,
            MangaError::Api(code, _) => !matches!(*code, 401 | 400),
            _ => false,
        }
    }

    /// 分流模式描述（用于日志）
    fn channel_brief(channel: &ChannelMode) -> &'static str {
        match channel {
            ChannelMode::Direct => "直连",
            ChannelMode::ChannelIp(ip) if *ip == CHANNEL2_IPV4 => "分流2",
            ChannelMode::ChannelIp(ip) if *ip == CHANNEL3_IPV4 => "分流3",
            ChannelMode::ChannelIp(ip) if *ip == DEFAULT_CDN_IP => "CDN",
            ChannelMode::ChannelIp(_) => "CDN自定义",
            ChannelMode::ReverseProxy(u) if *u == "https://bika-api.jpacg.cc" => "JP反代",
            ChannelMode::ReverseProxy(u) if *u == "https://bika2-api.jpacg.cc" => "US反代",
            ChannelMode::ReverseProxy(_) => "自定义反代",
            ChannelMode::LanRelay(_) => "PC中转",
        }
    }

    /// 测试指定分流模式的连通性，返回延迟（毫秒）
    ///
    /// **测试行为与原项目一致**：
    /// - 打 `categories` 端点（原 SpeedTestPingReq）
    /// - authorization 设为空字符串（原项目 `header["authorization"] = ""`）
    /// - 无论 HTTP 状态码，只要收到响应即认为可达
    /// - 该方法不改变当前客户端状态
    pub async fn test_connectivity(&self, mode: ChannelMode) -> MangaResult<u64> {
        use std::time::Instant;

        let channel_desc = match &mode {
            ChannelMode::Direct => "直连".to_string(),
            ChannelMode::ChannelIp(ip) => format!("分流IP:{}", ip),
            ChannelMode::ReverseProxy(url) => format!("反代:{}", url),
            ChannelMode::LanRelay(addr) => format!("PC中转:{}", addr),
        };
        sw_info!("[Manga测速] 开始测试节点: {}", channel_desc);

        // PC 中转模式：对 /manga/ping 探头测速
        if let ChannelMode::LanRelay(relay_addr) = &mode {
            let t0 = Instant::now();
            let url = format!("http://{}/manga/ping", relay_addr);
            let client = reqwest::Client::builder()
                .timeout(Duration::from_secs(5))
                .build()
                .map_err(|e| MangaError::Network(e.to_string()))?;
            client.get(&url).send().await.map_err(|e| {
                let msg = format!("中转服务器 {} 不可达: {}", relay_addr, e);
                sw_warn!("[Manga测速] {}", msg);
                MangaError::Network(msg)
            })?;
            let elapsed = t0.elapsed().as_millis() as u64;
            sw_info!("[Manga测速] PC中转[{}] 延迟={}ms", relay_addr, elapsed);
            return Ok(elapsed);
        }

        let client = self.build_client_with_channel(Some(&mode))?;

        // 与原项目一致：使用 categories 端点，authorization 为空字符串
        let path = "categories";
        let url = Self::compose_url_for_channel(path, &mode);

        // build_headers 传 Some("") 使签名中包含空 authorization header（原项目行为）
        let mut headers = signature::build_headers(path, "GET", Some(""));
        Self::rewrite_headers_for_channel(&mut headers, &mode);
        sw_debug!("[Manga测速] 目标URL: {}", url);

        let t0 = Instant::now();
        let mut req = client.get(&url);
        for (k, v) in &headers {
            req = req.header(k.as_str(), v.as_str());
        }
        let status = req
            .send()
            .await
            .map(|resp| resp.status().as_u16())
            .map_err(|e| {
                let detail = Self::format_error_chain(&e);
                let msg = format!("节点[{}]连接失败: {}", channel_desc, detail);
                sw_warn!("[Manga测速] {}", msg);
                MangaError::Network(msg)
            })?;

        let elapsed = t0.elapsed().as_millis() as u64;
        sw_info!(
            "[Manga测速] 节点[{}] 延迟={}ms HTTP={}",
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
    ) -> MangaResult<(u16, Value)> {
        let _ = rustls::crypto::ring::default_provider().install_default();

        let addr: SocketAddr = format!("{}:443", ip_str)
            .parse()
            .map_err(|e| MangaError::Network(format!("分流 IP 无效 '{}': {}", ip_str, e)))?;
        let uri: Uri = url
            .parse()
            .map_err(|e| MangaError::Network(format!("无效请求URL '{}': {}", url, e)))?;
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
                    .map_err(|e| MangaError::Network(format!("无效SNI域名: {}", e)))?,
            ))
            .enable_all_versions()
            .wrap_connector(http);

        let client: HyperClient<_, Full<Bytes>> =
            HyperClient::builder(TokioExecutor::new()).build(https);

        let request_body = match body {
            Some(value) => serde_json::to_vec(value)
                .map(Bytes::from)
                .map_err(|e| MangaError::Parse(format!("请求体序列化失败: {}", e)))?,
            None => Bytes::new(),
        };

        let mut builder = Request::builder().method(method).uri(uri);
        for (k, v) in headers {
            builder = builder.header(k.as_str(), v.as_str());
        }

        let request = builder
            .body(Full::new(request_body))
            .map_err(|e| MangaError::Network(format!("构造请求失败: {}", e)))?;

        let response: hyper::Response<hyper::body::Incoming> = client
            .request(request)
            .await
            .map_err(|e| {
                // 遍历错误链以暴露底层 OS 错误码（ENETUNREACH / ECONNREFUSED 等）
                let mut chain = format!("{}", e);
                let mut src: Option<&dyn StdError> = e.source();
                while let Some(cause) = src {
                    chain.push_str(&format!(" caused by: {}", cause));
                    if let Some(io_err) = cause.downcast_ref::<io::Error>() {
                        chain.push_str(&format!(
                            " [os={:?} raw={}]",
                            io_err.kind(),
                            io_err.raw_os_error().unwrap_or(-1)
                        ));
                    }
                    src = cause.source();
                }
                sw_warn!("[Manga] send_via_fixed_ip 连接失败 ip={} url={} err={}", ip_str, url, chain);
                MangaError::Network(format!("网络错误: {}", chain))
            })?;
        let status = response.status().as_u16();
        let body_bytes = response
            .into_body()
            .collect()
            .await
            .map_err(|e| MangaError::Network(format!("读取响应失败: {}", e)))?
            .to_bytes();
        let value: Value = serde_json::from_slice(&body_bytes).map_err(|e| {
            MangaError::Parse(format!(
                "响应解析失败: {} body={} ",
                e,
                String::from_utf8_lossy(&body_bytes)
            ))
        })?;
        Ok((status, value))
    }

    async fn download_bytes_via_fixed_ip(&self, url: &str, ip_str: &str) -> MangaResult<Vec<u8>> {
        let _ = rustls::crypto::ring::default_provider().install_default();

        let addr: SocketAddr = format!("{}:443", ip_str)
            .parse()
            .map_err(|e| MangaError::Network(format!("图片分流 IP 无效 '{}': {}", ip_str, e)))?;
        let mut current_url = Url::parse(url)
            .map_err(|e| MangaError::Network(format!("无效图片URL '{}': {}", url, e)))?;

        for _ in 0..5 {
            let uri: Uri = current_url.as_str().parse().map_err(|e| {
                MangaError::Network(format!("无效图片URL '{}': {}", current_url, e))
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
                        .map_err(|e| MangaError::Network(format!("无效图片SNI域名: {}", e)))?,
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
                .map_err(|e| MangaError::Network(format!("构造图片请求失败: {}", e)))?;
            let response: hyper::Response<hyper::body::Incoming> = client
                .request(request)
                .await
                .map_err(|e| MangaError::Network(format!("图片网络错误: {}", e)))?;
            let status = response.status();

            if status.is_redirection() {
                let location = response
                    .headers()
                    .get(hyper::header::LOCATION)
                    .and_then(|value| value.to_str().ok())
                    .ok_or_else(|| {
                        MangaError::Network(format!("图片重定向缺少 Location: {}", current_url))
                    })?;
                current_url = if let Ok(next_url) = Url::parse(location) {
                    next_url
                } else {
                    current_url.join(location).map_err(|e| {
                        MangaError::Network(format!("图片重定向地址无效 '{}': {}", location, e))
                    })?
                };
                sw_debug!("[Manga IMG] 跟随图片重定向 -> {}", current_url);
                continue;
            }

            let body = response
                .into_body()
                .collect()
                .await
                .map_err(|e| MangaError::Network(format!("读取图片响应失败: {}", e)))?
                .to_bytes();
            if status.as_u16() >= 400 {
                return Err(MangaError::Network(format!(
                    "图片请求失败 HTTP={} url={}",
                    status.as_u16(),
                    current_url
                )));
            }
            if !Self::looks_like_image_bytes(&body) {
                return Err(MangaError::Network(format!(
                    "图片数据无效 url={}",
                    current_url
                )));
            }
            return Ok(body.to_vec());
        }

        Err(MangaError::Network(format!("图片重定向次数过多: {}", url)))
    }

    pub async fn fetch_image_bytes(&self, file_server: &str, path: &str) -> MangaResult<Vec<u8>> {
        let (channel, image_server) = {
            let state = self.state.read();
            (state.channel.clone(), state.image_server.clone())
        };
        self.fetch_image_bytes_with_channel(file_server, path, &channel, &image_server)
            .await
    }

    /// 图片下载（使用指定分流，不修改全局状态，用于重试场景）
    async fn fetch_image_bytes_with_channel(
        &self,
        file_server: &str,
        path: &str,
        channel: &ChannelMode,
        image_server: &str,
    ) -> MangaResult<Vec<u8>> {
        // PC 中转模式：图片也经由局域网节点获取
        if let ChannelMode::LanRelay(relay_addr) = channel {
            return self
                .fetch_image_via_relay(file_server, path, relay_addr)
                .await;
        }

        let candidate_urls = Self::build_image_candidate_urls(file_server, path, image_server);
        let client = self.build_client()?;
        let mut last_error: Option<MangaError> = None;

        for raw_url in candidate_urls {
            let request_url = Self::compose_image_url_for_channel(&raw_url, channel)?;
            sw_debug!(
                "[Manga IMG] 下载图片 url={} channel={:?}",
                request_url, channel
            );

            let result = match channel {
                ChannelMode::ChannelIp(ip) => {
                    let mut last_ip_err: Option<MangaError> = None;
                    for candidate_ip in Self::channel_ip_candidates(ip) {
                        match self
                            .download_bytes_via_fixed_ip(&request_url, &candidate_ip)
                            .await
                        {
                            Ok(bytes) => return Ok(bytes),
                            Err(err) => {
                                sw_warn!(
                                    "[Manga IMG] 分流IP下载失败 ip={} url={} err={}",
                                    candidate_ip, request_url, err
                                );
                                last_ip_err = Some(err);
                            }
                        }
                    }
                    Err(last_ip_err.unwrap_or_else(|| {
                        MangaError::Network(format!("图片请求失败（分流IP候选均不可达）: {}", request_url))
                    }))
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
                        .map_err(|e| MangaError::Network(format!("图片网络错误: {}", e)));

                    match response {
                        Ok(response) => {
                            let status = response.status().as_u16();
                            match response.bytes().await {
                                Ok(bytes)
                                    if status < 400 && Self::looks_like_image_bytes(&bytes) =>
                                {
                                    Ok(bytes.to_vec())
                                }
                                Ok(bytes) if status >= 400 => Err(MangaError::Network(format!(
                                    "图片请求失败 HTTP={} url={}",
                                    status, request_url
                                ))),
                                Ok(_) => Err(MangaError::Network(format!(
                                    "图片数据无效 url={}",
                                    request_url
                                ))),
                                Err(e) => Err(MangaError::Network(format!("读取图片失败: {}", e))),
                            }
                        }
                        Err(err) => Err(err),
                    }
                }
            };

            match result {
                Ok(bytes) => return Ok(bytes),
                Err(err) => {
                    sw_warn!(
                        "[Manga IMG] 图片候选地址失败 url={} err={}",
                        request_url, err
                    );
                    last_error = Some(err);
                }
            }
        }

        Err(last_error
            .unwrap_or_else(|| MangaError::Network("图片请求失败：没有可用候选地址".to_string())))
    }

    /// 图片下载（带自动重试：失败时切换分流重试，最多 MAX_IMAGE_RETRY 次）
    ///
    /// 临时切换不修改全局分流配置，重试完毕后用户原选分流不变。
    pub async fn fetch_image_bytes_with_retry(
        &self,
        file_server: &str,
        path: &str,
    ) -> MangaResult<Vec<u8>> {
        let (original, image_server) = {
            let state = self.state.read();
            (state.channel.clone(), state.image_server.clone())
        };
        match self
            .fetch_image_bytes_with_channel(file_server, path, &original, &image_server)
            .await
        {
            Ok(v) => Ok(v),
            Err(e) if Self::is_retryable_error(&e) => {
                let mut last_err = e;
                let fallbacks = Self::channel_fallback_list(&original);
                for fallback in fallbacks.iter().take(MAX_IMAGE_RETRY) {
                    sw_warn!(
                        "[Manga重试] IMG file_server={} path={} 从[{}]切换到[{}]",
                        file_server,
                        path,
                        Self::channel_brief(&original),
                        Self::channel_brief(fallback)
                    );
                    match self
                        .fetch_image_bytes_with_channel(file_server, path, fallback, &image_server)
                        .await
                    {
                        Ok(v) => {
                            sw_info!(
                                "[Manga重试] IMG 成功 path={} via [{}]",
                                path,
                                Self::channel_brief(fallback)
                            );
                            return Ok(v);
                        }
                        Err(e2) if Self::is_retryable_error(&e2) => {
                            last_err = e2;
                            continue;
                        }
                        Err(e2) => return Err(e2),
                    }
                }
                Err(last_err)
            }
            Err(e) => Err(e),
        }
    }

    /// 获取当前生效的 API 根 URL
    #[allow(dead_code)]
    fn effective_base_url(&self) -> String {
        match &self.state.read().channel {
            ChannelMode::ReverseProxy(base) => base.trim_end_matches('/').to_string(),
            _ => BASE_URL.to_string(),
        }
    }

    fn build_client(&self) -> MangaResult<Client> {
        self.build_client_with_channel(None)
    }

    /// 根据可选的临时 channel 模式构建客户端（None 表示使用当前状态）
    pub fn build_client_with_channel(
        &self,
        override_channel: Option<&ChannelMode>,
    ) -> MangaResult<Client> {
        let state = self.state.read();
        let proxy_url = state.proxy_url.clone();
        let channel = override_channel.unwrap_or(&state.channel).clone();
        drop(state); // 尽早释放读锁

        // PC 中转模式不需要特殊客户端配置
        if matches!(channel, ChannelMode::LanRelay(_)) {
            return Client::builder()
                .timeout(Duration::from_secs(30))
                .build()
                .map_err(|e| MangaError::Network(e.to_string()));
        }

        let mut builder = Client::builder()
            .gzip(true)
            .connect_timeout(Duration::from_secs(5))
            .timeout(Duration::from_secs(12));

        // 分流2/3：用指定 IP 覆盖域名 DNS 解析（SNI 保持原域名）
        // 同时关闭证书校验——原项目 httpx.Client(verify=False) 亦如此处理，
        // 因为 Cloudflare 共享 IP 上 SNI 映射不保证与目标域名证书完全匹配。
        if let ChannelMode::ChannelIp(ip_str) = &channel {
            let addrs: Vec<SocketAddr> = Self::channel_ip_candidates(ip_str)
                .into_iter()
                .map(|ip| {
                    let host = if ip.contains(':') {
                        format!("[{}]:443", ip)
                    } else {
                        format!("{}:443", ip)
                    };
                    host.parse().map_err(|e| {
                        MangaError::Network(format!("分流 IP 无效 '{}': {}", ip, e))
                    })
                })
                .collect::<Result<Vec<_>, MangaError>>()?;
            builder = builder
                .resolve_to_addrs(API_DOMAIN, &addrs)
                // 旧项目同时映射 post-api.wikawika.xyz，避免部分接口或重定向走污染 DNS
                .resolve_to_addrs(API_DOMAIN_ALT, &addrs)
                .danger_accept_invalid_certs(true);
        }

        // 代理（分流时通常不需要代理，但保留兼容性）
        if !proxy_url.is_empty() {
            let proxy = reqwest::Proxy::all(&proxy_url)
                .map_err(|e| MangaError::Network(format!("代理配置无效: {}", e)))?;
            builder = builder.proxy(proxy);
        }

        builder
            .build()
            .map_err(|e| MangaError::Network(e.to_string()))
    }

    /// GET 请求（使用当前全局分流）
    pub async fn get(&self, path: &str) -> MangaResult<Value> {
        let channel = self.state.read().channel.clone();
        self.get_with_channel(path, &channel).await
    }

    /// GET 请求（使用指定分流，不修改全局状态，用于重试场景）
    async fn get_with_channel(&self, path: &str, channel: &ChannelMode) -> MangaResult<Value> {
        let token = {
            let s = self.state.read();
            if s.token.is_empty() {
                None
            } else {
                Some(s.token.clone())
            }
        };

        let url = Self::compose_url_for_channel(path, channel);
        sw_debug!("[Manga GET] {}", url);

        // PC 中转模式：转发到局域网节点服务器
        if let ChannelMode::LanRelay(relay_addr) = channel {
            return self.call_relay_api(path, "GET", None, relay_addr).await;
        }

        let auth_token = if path.starts_with("auth/") {
            None
        } else {
            token.as_deref()
        };
        let mut headers = signature::build_headers(path, "GET", auth_token);
        Self::rewrite_headers_for_channel(&mut headers, channel);

        // 分流2/3：通过 Hyper FixedConnector 绕过系统 DNS，直连目标 IP
        if let ChannelMode::ChannelIp(ip_str) = channel {
            let mut last_err: Option<MangaError> = None;
            for candidate_ip in Self::channel_ip_candidates(ip_str) {
                match self
                    .send_via_fixed_ip(Method::GET, &url, &headers, None, &candidate_ip)
                    .await
                {
                    Ok((status, body)) => {
                        if status != 200 {
                            sw_warn!(
                                "[Manga GET] 非200响应 path={} status={} body={}",
                                path, status, body
                            );
                        }
                        return check_api_response(status, body);
                    }
                    Err(e) => {
                        sw_warn!(
                            "[Manga GET] 分流IP失败 ip={} path={} err={}",
                            candidate_ip, path, e
                        );
                        last_err = Some(e);
                    }
                }
            }
            return Err(last_err.unwrap_or_else(|| {
                MangaError::Network(format!("分流连接失败（所有候选IP不可达）: {}", path))
            }));
        }

        let client = self.build_client()?;

        let mut req = client.get(&url);
        for (k, v) in &headers {
            req = req.header(k.as_str(), v.as_str());
        }

        let resp = req.send().await.map_err(|e| {
            let detail = Self::format_error_chain(&e);
            sw_warn!("[Manga GET] 请求失败 path={} err={}", path, detail);
            MangaError::Network(format!("网络错误: {}", detail))
        })?;
        let status = resp.status().as_u16();
        let body: Value = resp
            .json()
            .await
            .map_err(|e| MangaError::Parse(e.to_string()))?;
        sw_debug!("[Manga GET] 响应 path={} status={}", path, status);
        if status != 200 {
            sw_warn!(
                "[Manga GET] 非200响应 path={} status={} body={}",
                path, status, body
            );
        }
        check_api_response(status, body)
    }

    /// GET 请求（带自动重试：失败时切换分流重试，最多 MAX_API_RETRY 次）
    ///
    /// 临时切换不修改全局分流配置，重试完毕后用户原选分流不变。
    pub async fn get_with_retry(&self, path: &str) -> MangaResult<Value> {
        let original = self.state.read().channel.clone();
        match self.get_with_channel(path, &original).await {
            Ok(v) => Ok(v),
            Err(e) if Self::is_retryable_error(&e) => {
                let mut last_err = e;
                let fallbacks = Self::channel_fallback_list(&original);
                for fallback in fallbacks.iter().take(MAX_API_RETRY) {
                    sw_warn!(
                        "[Manga重试] GET path={} 从[{}]切换到[{}]",
                        path,
                        Self::channel_brief(&original),
                        Self::channel_brief(fallback)
                    );
                    match self.get_with_channel(path, fallback).await {
                        Ok(v) => {
                            sw_info!(
                                "[Manga重试] GET 成功 path={} via [{}]",
                                path,
                                Self::channel_brief(fallback)
                            );
                            return Ok(v);
                        }
                        Err(e2) if Self::is_retryable_error(&e2) => {
                            last_err = e2;
                            continue;
                        }
                        Err(e2) => return Err(e2),
                    }
                }
                Err(last_err)
            }
            Err(e) => Err(e),
        }
    }

    /// POST 请求（使用当前全局分流）
    pub async fn post(&self, path: &str, body: Value) -> MangaResult<Value> {
        let channel = self.state.read().channel.clone();
        self.post_with_channel(path, body, &channel).await
    }

    /// POST 请求（使用指定分流，不修改全局状态，用于重试场景）
    async fn post_with_channel(
        &self,
        path: &str,
        body: Value,
        channel: &ChannelMode,
    ) -> MangaResult<Value> {
        let token = {
            let s = self.state.read();
            if s.token.is_empty() {
                None
            } else {
                Some(s.token.clone())
            }
        };
        let channel_desc = match channel {
            ChannelMode::Direct => "直连".to_string(),
            ChannelMode::ChannelIp(ip) => format!("IP:{}", ip),
            ChannelMode::ReverseProxy(u) => format!("反代:{}", u),
            ChannelMode::LanRelay(addr) => format!("中转:{}", addr),
        };

        let url = Self::compose_url_for_channel(path, channel);
        sw_debug!("[Manga POST] {} [{}]", url, channel_desc);

        // PC 中转模式：转发到局域网节点服务器
        if let ChannelMode::LanRelay(relay_addr) = channel {
            return self.call_relay_api(path, "POST", Some(&body), relay_addr).await;
        }

        let auth_token = if path.starts_with("auth/") {
            None
        } else {
            token.as_deref()
        };
        let mut headers = signature::build_headers(path, "POST", auth_token);
        Self::rewrite_headers_for_channel(&mut headers, channel);

        // 分流2/3：通过 Hyper FixedConnector 绕过系统 DNS，直连目标 IP
        if let ChannelMode::ChannelIp(ip_str) = channel {
            let mut last_err: Option<MangaError> = None;
            for candidate_ip in Self::channel_ip_candidates(ip_str) {
                match self
                    .send_via_fixed_ip(
                        Method::POST,
                        &url,
                        &headers,
                        Some(&body),
                        &candidate_ip,
                    )
                    .await
                {
                    Ok((status, resp_body)) => {
                        if status != 200 {
                            sw_warn!(
                                "[Manga POST] 非200响应 path={} status={} body={}",
                                path, status, resp_body
                            );
                        }
                        return check_api_response(status, resp_body);
                    }
                    Err(e) => {
                        sw_warn!(
                            "[Manga POST] 分流IP失败 ip={} path={} err={}",
                            candidate_ip, path, e
                        );
                        last_err = Some(e);
                    }
                }
            }
            return Err(last_err.unwrap_or_else(|| {
                MangaError::Network(format!("分流连接失败（所有候选IP不可达）: {}", path))
            }));
        }

        let client = self.build_client()?;

        let mut req = client.post(&url).json(&body);
        for (k, v) in &headers {
            req = req.header(k.as_str(), v.as_str());
        }

        let resp = req.send().await.map_err(|e| {
            let detail = Self::format_error_chain(&e);
            sw_warn!("[Manga POST] 请求失败 path={} err={}", path, detail);
            MangaError::Network(format!("网络错误: {}", detail))
        })?;
        let status = resp.status().as_u16();
        let resp_body: Value = resp
            .json()
            .await
            .map_err(|e| MangaError::Parse(e.to_string()))?;
        sw_debug!("[Manga POST] 响应 path={} status={}", path, status);
        if status != 200 {
            sw_warn!(
                "[Manga POST] 非200响应 path={} status={} body={}",
                path, status, resp_body
            );
        }
        check_api_response(status, resp_body)
    }

    /// POST 请求（带自动重试：失败时切换分流重试，最多 MAX_API_RETRY 次）
    ///
    /// 临时切换不修改全局分流配置，重试完毕后用户原选分流不变。
    pub async fn post_with_retry(&self, path: &str, body: Value) -> MangaResult<Value> {
        let original = self.state.read().channel.clone();
        match self.post_with_channel(path, body.clone(), &original).await {
            Ok(v) => Ok(v),
            Err(e) if Self::is_retryable_error(&e) => {
                let mut last_err = e;
                let fallbacks = Self::channel_fallback_list(&original);
                for fallback in fallbacks.iter().take(MAX_API_RETRY) {
                    sw_warn!(
                        "[Manga重试] POST path={} 从[{}]切换到[{}]",
                        path,
                        Self::channel_brief(&original),
                        Self::channel_brief(fallback)
                    );
                    match self.post_with_channel(path, body.clone(), fallback).await {
                        Ok(v) => {
                            sw_info!(
                                "[Manga重试] POST 成功 path={} via [{}]",
                                path,
                                Self::channel_brief(fallback)
                            );
                            return Ok(v);
                        }
                        Err(e2) if Self::is_retryable_error(&e2) => {
                            last_err = e2;
                            continue;
                        }
                        Err(e2) => return Err(e2),
                    }
                }
                Err(last_err)
            }
            Err(e) => Err(e),
        }
    }

    /// PUT 请求（使用当前全局分流）
    pub async fn put(&self, path: &str) -> MangaResult<Value> {
        let channel = self.state.read().channel.clone();
        self.put_with_channel(path, &channel).await
    }

    /// PUT 请求（使用指定分流，不修改全局状态，用于重试场景）
    async fn put_with_channel(&self, path: &str, channel: &ChannelMode) -> MangaResult<Value> {
        let token = {
            let s = self.state.read();
            if s.token.is_empty() {
                None
            } else {
                Some(s.token.clone())
            }
        };
        let channel_desc = match channel {
            ChannelMode::Direct => "直连".to_string(),
            ChannelMode::ChannelIp(ip) => format!("IP:{}", ip),
            ChannelMode::ReverseProxy(u) => format!("反代:{}", u),
            ChannelMode::LanRelay(addr) => format!("中转:{}", addr),
        };

        let url = Self::compose_url_for_channel(path, channel);
        sw_debug!("[Manga PUT] {} [{}]", url, channel_desc);

        // PC 中转模式：转发到局域网节点服务器
        if let ChannelMode::LanRelay(relay_addr) = channel {
            return self.call_relay_api(path, "PUT", None, relay_addr).await;
        }

        let auth_token = if path.starts_with("auth/") {
            None
        } else {
            token.as_deref()
        };
        let mut headers = signature::build_headers(path, "PUT", auth_token);
        Self::rewrite_headers_for_channel(&mut headers, channel);

        // 分流2/3：通过 Hyper FixedConnector 绕过系统 DNS，直连目标 IP
        if let ChannelMode::ChannelIp(ip_str) = channel {
            let mut last_err: Option<MangaError> = None;
            for candidate_ip in Self::channel_ip_candidates(ip_str) {
                match self
                    .send_via_fixed_ip(Method::PUT, &url, &headers, None, &candidate_ip)
                    .await
                {
                    Ok((status, resp_body)) => {
                        if status != 200 {
                            sw_warn!(
                                "[Manga PUT] 非200响应 path={} status={} body={}",
                                path, status, resp_body
                            );
                        }
                        return check_api_response(status, resp_body);
                    }
                    Err(e) => {
                        sw_warn!(
                            "[Manga PUT] 分流IP失败 ip={} path={} err={}",
                            candidate_ip, path, e
                        );
                        last_err = Some(e);
                    }
                }
            }
            return Err(last_err.unwrap_or_else(|| {
                MangaError::Network(format!("分流连接失败（所有候选IP不可达）: {}", path))
            }));
        }

        let client = self.build_client()?;

        let mut req = client.put(&url);
        for (k, v) in &headers {
            req = req.header(k.as_str(), v.as_str());
        }

        let resp = req.send().await.map_err(|e| {
            let detail = Self::format_error_chain(&e);
            sw_warn!("[Manga PUT] 请求失败 path={} err={}", path, detail);
            MangaError::Network(format!("网络错误: {}", detail))
        })?;
        let status = resp.status().as_u16();
        let resp_body: Value = resp
            .json()
            .await
            .map_err(|e| MangaError::Parse(e.to_string()))?;
        sw_debug!("[Manga PUT] 响应 path={} status={}", path, status);
        if status != 200 {
            sw_warn!(
                "[Manga PUT] 非200响应 path={} status={} body={}",
                path, status, resp_body
            );
        }
        check_api_response(status, resp_body)
    }

    /// PUT 请求（带自动重试：失败时切换分流重试，最多 MAX_API_RETRY 次）
    ///
    /// 临时切换不修改全局分流配置，重试完毕后用户原选分流不变。
    pub async fn put_with_retry(&self, path: &str) -> MangaResult<Value> {
        let original = self.state.read().channel.clone();
        match self.put_with_channel(path, &original).await {
            Ok(v) => Ok(v),
            Err(e) if Self::is_retryable_error(&e) => {
                let mut last_err = e;
                let fallbacks = Self::channel_fallback_list(&original);
                for fallback in fallbacks.iter().take(MAX_API_RETRY) {
                    sw_warn!(
                        "[Manga重试] PUT path={} 从[{}]切换到[{}]",
                        path,
                        Self::channel_brief(&original),
                        Self::channel_brief(fallback)
                    );
                    match self.put_with_channel(path, fallback).await {
                        Ok(v) => {
                            sw_info!(
                                "[Manga重试] PUT 成功 path={} via [{}]",
                                path,
                                Self::channel_brief(fallback)
                            );
                            return Ok(v);
                        }
                        Err(e2) if Self::is_retryable_error(&e2) => {
                            last_err = e2;
                            continue;
                        }
                        Err(e2) => return Err(e2),
                    }
                }
                Err(last_err)
            }
            Err(e) => Err(e),
        }
    }

    // ==================== PC 中转辅助方法 ====================

    /// 通过 PC 节点服务器中转 API 请求
    async fn call_relay_api(
        &self,
        path: &str,
        method: &str,
        body: Option<&Value>,
        relay_addr: &str,
    ) -> MangaResult<Value> {
        let relay_url = format!("http://{}/manga/api", relay_addr);
        let req_body = serde_json::json!({
            "path": path,
            "method": method,
            "body": body,
        });
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(20))
            .build()
            .map_err(|e| MangaError::Network(e.to_string()))?;
        let resp = client
            .post(&relay_url)
            .json(&req_body)
            .send()
            .await
            .map_err(|e| {
                MangaError::Network(format!("PC中转服务器 {} 请求失败: {}", relay_addr, e))
            })?;
        let resp_val: Value = resp
            .json()
            .await
            .map_err(|e| MangaError::Parse(format!("PC中转响应解析失败: {}", e)))?;
        let success = resp_val
            .get("success")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        if success {
            resp_val
                .get("data")
                .cloned()
                .ok_or_else(|| MangaError::Parse("PC中转响应缺少data字段".to_string()))
        } else {
            let err_msg = resp_val
                .get("error")
                .and_then(|v| v.as_str())
                .unwrap_or("PC中转请求失败")
                .to_string();
            Err(MangaError::Network(format!("PC中转错误: {}", err_msg)))
        }
    }

    /// 通过 PC 节点服务器中转图片下载
    async fn fetch_image_via_relay(
        &self,
        file_server: &str,
        path: &str,
        relay_addr: &str,
    ) -> MangaResult<Vec<u8>> {
        use percent_encoding::{utf8_percent_encode, NON_ALPHANUMERIC};
        let fs_enc = utf8_percent_encode(file_server, NON_ALPHANUMERIC).to_string();
        let path_enc = utf8_percent_encode(path, NON_ALPHANUMERIC).to_string();
        let relay_url = format!(
            "http://{}/manga/img?file_server={}&path={}",
            relay_addr, fs_enc, path_enc
        );
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(30))
            .build()
            .map_err(|e| MangaError::Network(e.to_string()))?;
        let resp = client.get(&relay_url).send().await.map_err(|e| {
            MangaError::Network(format!("PC中转图片请求失败 addr={}: {}", relay_addr, e))
        })?;
        if !resp.status().is_success() {
            return Err(MangaError::Network(format!(
                "PC中转图片HTTP错误: {} url={}",
                resp.status(),
                relay_url
            )));
        }
        let bytes = resp
            .bytes()
            .await
            .map_err(|e| MangaError::Network(format!("读取PC中转图片数据失败: {}", e)))?;
        Ok(bytes.to_vec())
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

fn check_api_response(http_status: u16, body: Value) -> MangaResult<Value> {
    let code = body
        .get("code")
        .and_then(|v| v.as_u64())
        .unwrap_or(http_status as u64) as u32;

    if code == 200 {
        Ok(body)
    } else if code == 401 || http_status == 401 {
        Err(MangaError::Unauthorized)
    } else {
        let msg = body
            .get("message")
            .and_then(|v| v.as_str())
            .unwrap_or("未知错误")
            .to_string();
        sw_warn!(
            "[Manga API] 业务错误 http_status={} code={} message={}",
            http_status, code, msg
        );
        Err(MangaError::Api(code, msg))
    }
}

#[cfg(test)]
mod tests {
    //! 漫画模块重试机制的单元测试
    //!
    //! 覆盖范围：
    //! - `channels_equal` / `channel_fallback_list`：候选分流列表生成
    //! - `is_retryable_error`：重试触发判定
    //! - `channel_brief`：日志分流描述
    //! - `check_api_response`：HTTP 响应→错误类型映射（重试判定的依据）
    //! - 重试决策序列模拟：验证 fallback list 与 is_retryable_error 协同的行为

    use super::*;

    /// 构造已知分流 IP，简化测试代码
    fn ch2() -> ChannelMode {
        ChannelMode::ChannelIp(CHANNEL2_IPV4.to_string())
    }
    fn ch3() -> ChannelMode {
        ChannelMode::ChannelIp(CHANNEL3_IPV4.to_string())
    }
    fn ch_cdn() -> ChannelMode {
        ChannelMode::ChannelIp(DEFAULT_CDN_IP.to_string())
    }
    fn ch_jp() -> ChannelMode {
        ChannelMode::ReverseProxy("https://bika-api.jpacg.cc".to_string())
    }
    fn ch_us() -> ChannelMode {
        ChannelMode::ReverseProxy("https://bika2-api.jpacg.cc".to_string())
    }
    fn ch_relay() -> ChannelMode {
        ChannelMode::LanRelay("192.168.1.100:8888".to_string())
    }
    fn ch_custom_ip(ip: &str) -> ChannelMode {
        ChannelMode::ChannelIp(ip.to_string())
    }
    fn ch_custom_proxy(u: &str) -> ChannelMode {
        ChannelMode::ReverseProxy(u.to_string())
    }

    // ==================== channels_equal ====================

    #[test]
    fn channels_equal_same_variants() {
        assert!(MangaClient::channels_equal(
            &ChannelMode::Direct,
            &ChannelMode::Direct
        ));
        assert!(MangaClient::channels_equal(&ch2(), &ch2()));
        assert!(MangaClient::channels_equal(&ch3(), &ch3()));
        assert!(MangaClient::channels_equal(&ch_cdn(), &ch_cdn()));
        assert!(MangaClient::channels_equal(&ch_jp(), &ch_jp()));
        assert!(MangaClient::channels_equal(&ch_us(), &ch_us()));
        assert!(MangaClient::channels_equal(&ch_relay(), &ch_relay()));
    }

    #[test]
    fn channels_equal_different_ip() {
        assert!(!MangaClient::channels_equal(
            &ch2(),
            &ch3()
        ));
        assert!(!MangaClient::channels_equal(
            &ch2(),
            &ch_custom_ip("9.9.9.9")
        ));
        assert!(!MangaClient::channels_equal(
            &ch_cdn(),
            &ch_custom_ip("9.9.9.9")
        ));
    }

    #[test]
    fn channels_equal_different_proxy_url() {
        assert!(!MangaClient::channels_equal(&ch_jp(), &ch_us()));
        assert!(!MangaClient::channels_equal(
            &ch_jp(),
            &ch_custom_proxy("https://example.com")
        ));
    }

    #[test]
    fn channels_equal_different_relay_addr() {
        let a = ChannelMode::LanRelay("192.168.1.1:8888".to_string());
        let b = ChannelMode::LanRelay("10.0.0.1:9999".to_string());
        assert!(!MangaClient::channels_equal(&a, &b));
    }

    #[test]
    fn channels_equal_cross_variant() {
        // 不同变体之间一律视为不等
        assert!(!MangaClient::channels_equal(
            &ChannelMode::Direct,
            &ch2()
        ));
        assert!(!MangaClient::channels_equal(&ch2(), &ch_jp()));
        assert!(!MangaClient::channels_equal(&ch_jp(), &ch_relay()));
        assert!(!MangaClient::channels_equal(
            &ch_relay(),
            &ChannelMode::Direct
        ));
    }

    // ==================== channel_fallback_list ====================

    #[test]
    fn fallback_list_for_direct_has_five_entries() {
        let list = MangaClient::channel_fallback_list(&ChannelMode::Direct);
        assert_eq!(list.len(), 5);
        assert_eq!(list[0], ch2());
        assert_eq!(list[1], ch3());
        assert_eq!(list[2], ch_cdn());
        assert_eq!(list[3], ch_jp());
        assert_eq!(list[4], ch_us());
    }

    #[test]
    fn fallback_list_for_channel2_excludes_self() {
        let list = MangaClient::channel_fallback_list(&ch2());
        assert_eq!(list.len(), 5);
        // 当前分流2 不应出现在候选中
        assert!(list.iter().all(|c| !MangaClient::channels_equal(c, &ch2())));
        assert_eq!(list[0], ChannelMode::Direct);
        assert_eq!(list[1], ch3());
        assert_eq!(list[2], ch_cdn());
        assert_eq!(list[3], ch_jp());
        assert_eq!(list[4], ch_us());
    }

    #[test]
    fn fallback_list_for_cdn_excludes_self() {
        let list = MangaClient::channel_fallback_list(&ch_cdn());
        assert_eq!(list.len(), 5);
        assert!(list
            .iter()
            .all(|c| !MangaClient::channels_equal(c, &ch_cdn())));
    }

    #[test]
    fn fallback_list_for_jp_proxy_excludes_self() {
        let list = MangaClient::channel_fallback_list(&ch_jp());
        assert_eq!(list.len(), 5);
        assert!(list.iter().all(|c| !MangaClient::channels_equal(c, &ch_jp())));
        assert_eq!(list[0], ChannelMode::Direct);
        assert_eq!(list[4], ch_us());
    }

    #[test]
    fn fallback_list_for_lanrelay_excludes_self_but_includes_all_others() {
        // LanRelay 不在标准候选池中，但当前是 LanRelay 时应给出全部 6 个标准候选
        let list = MangaClient::channel_fallback_list(&ch_relay());
        assert_eq!(list.len(), 6);
        assert!(list
            .iter()
            .all(|c| !MangaClient::channels_equal(c, &ch_relay())));
        assert_eq!(list[0], ChannelMode::Direct);
        assert_eq!(list[5], ch_us());
    }

    #[test]
    fn fallback_list_for_custom_ip_keeps_all_standard_channels() {
        // 自定义 IP 不在标准列表中，候选列表保留全部 6 个标准分流
        let list = MangaClient::channel_fallback_list(&ch_custom_ip("9.9.9.9"));
        assert_eq!(list.len(), 6);
        assert_eq!(list[0], ChannelMode::Direct);
        assert_eq!(list[1], ch2());
        assert_eq!(list[2], ch3());
        assert_eq!(list[3], ch_cdn());
        assert_eq!(list[4], ch_jp());
        assert_eq!(list[5], ch_us());
    }

    #[test]
    fn fallback_list_always_excludes_lanrelay() {
        // 标准候选池中不含 LanRelay（地址不固定，无法假设可用）
        for current in [
            ChannelMode::Direct,
            ch2(),
            ch3(),
            ch_cdn(),
            ch_jp(),
            ch_us(),
            ch_custom_ip("9.9.9.9"),
            ch_custom_proxy("https://x"),
        ] {
            let list = MangaClient::channel_fallback_list(&current);
            assert!(
                list.iter()
                    .all(|c| !matches!(c, ChannelMode::LanRelay(_))),
                "当前为 {:?} 时候选列表不应包含 LanRelay",
                current
            );
        }
    }

    #[test]
    fn fallback_list_order_is_stable() {
        // 排序始终为 Direct → 分流2 → 分流3 → CDN → JP → US
        let expected_order = vec![
            ChannelMode::Direct,
            ch2(),
            ch3(),
            ch_cdn(),
            ch_jp(),
            ch_us(),
        ];
        // 取一个会让候选列表包含全部 6 项的当前分流
        let list = MangaClient::channel_fallback_list(&ch_relay());
        assert_eq!(list, expected_order);
    }

    // ==================== is_retryable_error ====================

    #[test]
    fn network_error_is_retryable() {
        assert!(MangaClient::is_retryable_error(&MangaError::Network(
            "连接超时".to_string()
        )));
        assert!(MangaClient::is_retryable_error(&MangaError::Network(
            "DNS 解析失败".to_string()
        )));
        assert!(MangaClient::is_retryable_error(&MangaError::Network(
            "图片请求失败 HTTP=500 url=xxx".to_string()
        )));
    }

    #[test]
    fn api_error_401_not_retryable() {
        // 未登录错误切换分流无意义
        assert!(!MangaClient::is_retryable_error(&MangaError::Api(
            401,
            "未登录".to_string()
        )));
    }

    #[test]
    fn api_error_400_not_retryable() {
        // 参数错误通常是客户端问题，切换分流无意义
        assert!(!MangaClient::is_retryable_error(&MangaError::Api(
            400,
            "参数错误".to_string()
        )));
    }

    #[test]
    fn api_error_5xx_is_retryable() {
        assert!(MangaClient::is_retryable_error(&MangaError::Api(
            500,
            "服务器内部错误".to_string()
        )));
        assert!(MangaClient::is_retryable_error(&MangaError::Api(
            502,
            "Bad Gateway".to_string()
        )));
        assert!(MangaClient::is_retryable_error(&MangaError::Api(
            503,
            "Service Unavailable".to_string()
        )));
    }

    #[test]
    fn api_error_4xx_other_than_400_401_is_retryable() {
        // 403/404/429 等切换分流可能有效
        assert!(MangaClient::is_retryable_error(&MangaError::Api(
            403,
            "禁止访问".to_string()
        )));
        assert!(MangaClient::is_retryable_error(&MangaError::Api(
            404,
            "不存在".to_string()
        )));
        assert!(MangaClient::is_retryable_error(&MangaError::Api(
            429,
            "Too Many Requests".to_string()
        )));
    }

    #[test]
    fn unauthorized_not_retryable() {
        assert!(!MangaClient::is_retryable_error(&MangaError::Unauthorized));
    }

    #[test]
    fn parse_error_not_retryable() {
        // JSON 解析失败通常是响应内容问题，切换分流不会解决
        assert!(!MangaClient::is_retryable_error(&MangaError::Parse(
            "invalid JSON".to_string()
        )));
    }

    #[test]
    fn other_error_not_retryable() {
        assert!(!MangaClient::is_retryable_error(&MangaError::Other(
            "未知错误".to_string()
        )));
    }

    // ==================== channel_brief ====================

    #[test]
    fn channel_brief_known_modes() {
        assert_eq!(MangaClient::channel_brief(&ChannelMode::Direct), "直连");
        assert_eq!(MangaClient::channel_brief(&ch2()), "分流2");
        assert_eq!(MangaClient::channel_brief(&ch3()), "分流3");
        assert_eq!(MangaClient::channel_brief(&ch_cdn()), "CDN");
        assert_eq!(MangaClient::channel_brief(&ch_jp()), "JP反代");
        assert_eq!(MangaClient::channel_brief(&ch_us()), "US反代");
        assert_eq!(MangaClient::channel_brief(&ch_relay()), "PC中转");
    }

    #[test]
    fn channel_brief_custom_ip_and_proxy() {
        assert_eq!(
            MangaClient::channel_brief(&ch_custom_ip("9.9.9.9")),
            "CDN自定义"
        );
        assert_eq!(
            MangaClient::channel_brief(&ch_custom_proxy("https://example.com")),
            "自定义反代"
        );
    }

    // ==================== check_api_response ====================

    #[test]
    fn check_api_response_code_200_ok() {
        let body = serde_json::json!({ "code": 200, "data": "ok" });
        let result = check_api_response(200, body).expect("应解析为 Ok");
        assert_eq!(result.get("data").and_then(|v| v.as_str()), Some("ok"));
    }

    #[test]
    fn check_api_response_body_code_401_returns_unauthorized() {
        let body = serde_json::json!({ "code": 401, "message": "未登录" });
        let err = check_api_response(200, body).unwrap_err();
        assert!(matches!(err, MangaError::Unauthorized));
    }

    #[test]
    fn check_api_response_http_401_returns_unauthorized() {
        // 即使 body 没有 code 字段，HTTP 401 也判定为未登录
        let body = serde_json::json!({ "message": "禁止" });
        let err = check_api_response(401, body).unwrap_err();
        assert!(matches!(err, MangaError::Unauthorized));
    }

    #[test]
    fn check_api_response_500_returns_api_error() {
        let body = serde_json::json!({ "code": 500, "message": "服务器错误" });
        let err = check_api_response(500, body).unwrap_err();
        match err {
            MangaError::Api(code, msg) => {
                assert_eq!(code, 500);
                assert_eq!(msg, "服务器错误");
            }
            other => panic!("期望 Api(500, _), 实际 {:?}", other),
        }
    }

    #[test]
    fn check_api_response_no_code_field_falls_back_to_http_status() {
        // body 没有 code 字段时，用 HTTP 状态码作为 code
        let body = serde_json::json!({ "data": "ok" });
        let result = check_api_response(200, body);
        assert!(result.is_ok());

        let err = check_api_response(500, serde_json::json!({})).unwrap_err();
        match err {
            MangaError::Api(code, _) => assert_eq!(code, 500),
            other => panic!("期望 Api(500, _), 实际 {:?}", other),
        }
    }

    #[test]
    fn check_api_response_missing_message_uses_default() {
        let body = serde_json::json!({ "code": 500 }); // 无 message 字段
        let err = check_api_response(500, body).unwrap_err();
        match err {
            MangaError::Api(_, msg) => assert_eq!(msg, "未知错误"),
            other => panic!("期望 Api(_, _), 实际 {:?}", other),
        }
    }

    // ==================== 重试决策序列模拟 ====================
    //
    // 以下测试不发起真实网络请求，而是模拟 *_with_retry 内部的决策路径：
    // 给定一系列错误响应，验证 fallback list + is_retryable_error 的协同行为
    // 是否符合预期（是否触发切换、是否提前终止、是否最终失败）。

    /// 模拟重试循环的决策结果
    #[derive(Debug)]
    enum RetryOutcome {
        /// 首次成功，无需重试
        ImmediateOk,
        /// 经过若干次切换后成功（包含尝试过的分流数）
        OkAfter(Vec<ChannelMode>),
        /// 重试耗尽后失败（最后一次错误）
        Exhausted(MangaError),
        /// 遇到不可重试错误，立即中止
        Aborted(MangaError),
    }

    /// 模拟 *_with_retry 的核心决策循环
    ///
    /// `errors_per_attempt`：按候选顺序（含初始 current）依次返回错误。
    ///   - None 表示该次成功
    ///   - Some(err) 表示该次返回指定错误
    /// 长度应足够覆盖所有候选，否则视为成功（剩余默认成功）。
    fn simulate_retry_decision(
        current: &ChannelMode,
        max_retries: usize,
        errors_per_attempt: &[Option<MangaError>],
    ) -> RetryOutcome {
        // 第 0 次：用当前分流
        match errors_per_attempt.first() {
            None => return RetryOutcome::ImmediateOk,
            Some(None) => return RetryOutcome::ImmediateOk,
            Some(Some(e)) if !MangaClient::is_retryable_error(e) => {
                return RetryOutcome::Aborted(e.clone())
            }
            Some(Some(_)) => {}
        }

        let fallbacks = MangaClient::channel_fallback_list(current);
        let mut tried: Vec<ChannelMode> = Vec::new();

        for (idx, fallback) in fallbacks.iter().take(max_retries).enumerate() {
            tried.push(fallback.clone());
            // errors_per_attempt[0] 是首次（current）的结果
            // errors_per_attempt[idx + 1] 是第 idx+1 个 fallback 的结果
            let outcome = errors_per_attempt.get(idx + 1);
            match outcome {
                None | Some(None) => return RetryOutcome::OkAfter(tried),
                Some(Some(e)) if !MangaClient::is_retryable_error(e) => {
                    return RetryOutcome::Aborted(e.clone())
                }
                Some(Some(_)) => continue,
            }
        }

        // 耗尽候选后，取实际最后一次尝试的错误
        // 最后一次 fallback 索引为 min(max_retries, fallbacks.len()) - 1，
        // 对应 errors_per_attempt[min(max_retries, fallbacks.len())]
        let last_attempt_idx = max_retries.min(fallbacks.len());
        let last_err = match errors_per_attempt.get(last_attempt_idx) {
            Some(Some(e)) => e.clone(),
            _ => MangaError::Network("所有候选均不可达".to_string()),
        };
        RetryOutcome::Exhausted(last_err)
    }

    #[test]
    fn retry_sequence_first_attempt_ok() {
        // 首次成功，不进入重试
        let outcome = simulate_retry_decision(&ChannelMode::Direct, 3, &[None]);
        assert!(matches!(outcome, RetryOutcome::ImmediateOk));
    }

    #[test]
    fn retry_sequence_network_error_then_success() {
        // 第1次 Direct 网络错误 → 切到分流2 → 成功
        let errors = vec![
            Some(MangaError::Network("连接失败".to_string())),
            None, // 分流2 成功
        ];
        let outcome = simulate_retry_decision(&ChannelMode::Direct, 3, &errors);
        match outcome {
            RetryOutcome::OkAfter(tried) => {
                assert_eq!(tried.len(), 1);
                assert_eq!(tried[0], ch2());
            }
            other => panic!("期望 OkAfter, 实际 {:?}", other),
        }
    }

    #[test]
    fn retry_sequence_multiple_failures_then_success() {
        // Direct 失败 → 分流2 失败 → 分流3 成功
        let errors = vec![
            Some(MangaError::Network("超时".to_string())),
            Some(MangaError::Api(500, "服务器错误".to_string())),
            None, // 分流3 成功
        ];
        let outcome = simulate_retry_decision(&ChannelMode::Direct, 3, &errors);
        match outcome {
            RetryOutcome::OkAfter(tried) => {
                assert_eq!(tried.len(), 2);
                assert_eq!(tried[0], ch2());
                assert_eq!(tried[1], ch3());
            }
            other => panic!("期望 OkAfter, 实际 {:?}", other),
        }
    }

    #[test]
    fn retry_sequence_exhausted_all_attempts() {
        // 所有候选都失败（包括 5xx 错误，可重试），最终耗尽
        let errors = vec![
            Some(MangaError::Network("超时".to_string())),
            Some(MangaError::Api(500, "x".to_string())),
            Some(MangaError::Api(503, "x".to_string())),
            Some(MangaError::Api(502, "x".to_string())),
        ];
        // max_retries=3，会尝试 3 个 fallback（不包含首次）
        let outcome = simulate_retry_decision(&ChannelMode::Direct, 3, &errors);
        match outcome {
            RetryOutcome::Exhausted(err) => {
                assert!(matches!(err, MangaError::Api(502, _)));
            }
            other => panic!("期望 Exhausted, 实际 {:?}", other),
        }
    }

    #[test]
    fn retry_sequence_aborts_on_unauthorized() {
        // 首次返回 401 → 不重试，立即中止
        let errors = vec![Some(MangaError::Api(401, "未登录".to_string()))];
        let outcome = simulate_retry_decision(&ChannelMode::Direct, 3, &errors);
        match outcome {
            RetryOutcome::Aborted(err) => {
                assert!(matches!(err, MangaError::Api(401, _)));
            }
            other => panic!("期望 Aborted, 实际 {:?}", other),
        }
    }

    #[test]
    fn retry_sequence_aborts_on_400_after_network_error() {
        // Direct 网络错误（可重试）→ 切到分流2 → 返回 400（不可重试，中止）
        let errors = vec![
            Some(MangaError::Network("超时".to_string())),
            Some(MangaError::Api(400, "参数错误".to_string())),
        ];
        let outcome = simulate_retry_decision(&ChannelMode::Direct, 3, &errors);
        match outcome {
            RetryOutcome::Aborted(err) => {
                assert!(matches!(err, MangaError::Api(400, _)));
            }
            other => panic!("期望 Aborted, 实际 {:?}", other),
        }
    }

    #[test]
    fn retry_sequence_respects_max_retries() {
        // 即使有更多候选，也只尝试 max_retries 次
        // Direct 失败 + 5 次失败（但 max_retries=2 只会尝试 2 个 fallback）
        let errors = vec![
            Some(MangaError::Network("e1".to_string())),
            Some(MangaError::Network("e2".to_string())),
            Some(MangaError::Network("e3".to_string())),
            Some(MangaError::Network("e4".to_string())),
            Some(MangaError::Network("e5".to_string())),
            Some(MangaError::Network("e6".to_string())),
        ];
        let outcome = simulate_retry_decision(&ChannelMode::Direct, 2, &errors);
        match outcome {
            RetryOutcome::Exhausted(err) => {
                // 第 3 次尝试（首次 + 2 个 fallback）的错误是 e3
                assert!(matches!(err, MangaError::Network(ref m) if m == "e3"));
            }
            other => panic!("期望 Exhausted, 实际 {:?}", other),
        }
    }

    #[test]
    fn retry_sequence_for_lanrelay_uses_all_six_standard_channels() {
        // 当前是 LanRelay，候选有 6 个标准分流；首次失败后从 Direct 开始尝试
        let errors = vec![
            Some(MangaError::Network("PC 中转服务器宕机".to_string())),
            None, // Direct 成功
        ];
        let outcome = simulate_retry_decision(&ch_relay(), 3, &errors);
        match outcome {
            RetryOutcome::OkAfter(tried) => {
                assert_eq!(tried.len(), 1);
                assert_eq!(tried[0], ChannelMode::Direct);
            }
            other => panic!("期望 OkAfter, 实际 {:?}", other),
        }
    }

    #[test]
    fn retry_sequence_api_5xx_triggers_retry() {
        // 5xx 业务码错误应该触发重试
        let errors = vec![
            Some(MangaError::Api(503, "Service Unavailable".to_string())),
            None,
        ];
        let outcome = simulate_retry_decision(&ch_jp(), 3, &errors);
        match outcome {
            RetryOutcome::OkAfter(tried) => {
                assert_eq!(tried[0], ChannelMode::Direct);
            }
            other => panic!("期望 OkAfter, 实际 {:?}", other),
        }
    }

    // ==================== 常量一致性 ====================

    #[test]
    fn default_cdn_ip_constant_matches_api_rs() {
        // 与 api.rs 中的 DEFAULT_CDN_IP 保持一致
        assert_eq!(DEFAULT_CDN_IP, "104.18.227.172");
    }

    #[test]
    fn max_retry_constants_are_sensible() {
        // 重试次数应在合理范围（1~5）
        assert!(MAX_API_RETRY >= 1 && MAX_API_RETRY <= 5);
        assert!(MAX_IMAGE_RETRY >= 1 && MAX_IMAGE_RETRY <= 5);
        // API 重试次数应大于等于图片（API 无其他回退机制）
        assert!(MAX_API_RETRY >= MAX_IMAGE_RETRY);
    }
}
