/// PicACG API 请求签名模块
///
/// 使用 HMAC-SHA256 对请求进行签名，保证请求合法性
use hmac::{Hmac, Mac};
use sha2::Sha256;
use std::sync::OnceLock;
use std::time::{SystemTime, UNIX_EPOCH};
use uuid::{Context, Timestamp, Uuid};

/// API 密钥
pub const API_KEY: &str = "C69BAF41DA5ABD1FFEDC6D2FEA56B";

/// API 版本号
pub const APP_VERSION: &str = "2.2.1.3.3.4";

/// Build 版本
pub const BUILD_VERSION: &str = "45";

/// 平台标识
pub const PLATFORM: &str = "android";

/// Agent
pub const AGENT: &str = "okhttp/3.8.1";

/// App Channel
pub const APP_CHANNEL: &str = "3";

/// 客户端更新版本（旧项目会携带该头）
pub const UPDATE_VERSION: &str = "v1.5.4";

/// Accept Header
pub const ACCEPT: &str = "application/vnd.picacomic.com.v1+json";

/// 签名密钥（由原项目 IDA PRO 逆向获取）
const SIGN_KEY: &str = "~d}$Q7$eIni=V)9\\RK/P.RM4;9[7|@/CA}b~OW!3?EV`:<>M7pddUBL5n|0/*Cn";

static UUID_V1_CONTEXT: OnceLock<Context> = OnceLock::new();
static UUID_V1_NODE_ID: OnceLock<[u8; 6]> = OnceLock::new();

/// 生成请求签名所需的 nonce（旧项目使用 uuid1，去掉连字符）
pub fn generate_nonce() -> String {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    let context = UUID_V1_CONTEXT.get_or_init(|| Context::new(42));
    let node_id = UUID_V1_NODE_ID.get_or_init(|| {
        let random = Uuid::new_v4();
        let bytes = random.as_bytes();
        [bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5]]
    });
    let ts = Timestamp::from_unix(context, now.as_secs(), now.subsec_nanos());
    Uuid::new_v1(ts, node_id).simple().to_string()
}

/// 获取当前时间戳（Unix 秒）
pub fn current_timestamp() -> String {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
        .to_string()
}

/// 计算 HMAC-SHA256 签名并返回十六进制字符串
pub fn hmac_sha256(src: &str, key: &str) -> String {
    type HmacSha256 = Hmac<Sha256>;
    let mut mac = HmacSha256::new_from_slice(key.as_bytes()).expect("HMAC 密钥长度任意");
    mac.update(src.to_lowercase().as_bytes());
    let result = mac.finalize();
    hex::encode(result.into_bytes())
}

/// 构建请求签名
///
/// # 参数
/// - `path`: 请求 URL 中相对 API 根的路径（例如 "auth/sign-in"）
/// - `timestamp`: 当前时间戳字符串
/// - `nonce`: 随机 nonce 字符串
/// - `method`: HTTP 方法（"GET"、"POST" 等）
pub fn build_signature(path: &str, timestamp: &str, nonce: &str, method: &str) -> String {
    // 源字符串拼接顺序：path + timestamp + nonce + method + apiKey
    let src = format!("{}{}{}{}{}", path, timestamp, nonce, method, API_KEY);
    hmac_sha256(&src, SIGN_KEY)
}

/// 构建请求所需的全部公共 Header
pub fn build_headers(path: &str, method: &str, token: Option<&str>) -> Vec<(String, String)> {
    let timestamp = current_timestamp();
    let nonce = generate_nonce();
    let signature = build_signature(path, &timestamp, &nonce, method);

    let mut headers = vec![
        ("api-key".to_string(), API_KEY.to_string()),
        ("accept".to_string(), ACCEPT.to_string()),
        ("app-channel".to_string(), APP_CHANNEL.to_string()),
        ("time".to_string(), timestamp),
        ("app-uuid".to_string(), "defaultUuid".to_string()),
        ("nonce".to_string(), nonce),
        ("signature".to_string(), signature),
        ("app-version".to_string(), APP_VERSION.to_string()),
        ("image-quality".to_string(), "original".to_string()),
        ("app-platform".to_string(), PLATFORM.to_string()),
        ("app-build-version".to_string(), BUILD_VERSION.to_string()),
        ("user-agent".to_string(), AGENT.to_string()),
        ("version".to_string(), UPDATE_VERSION.to_string()),
    ];

    if method.eq_ignore_ascii_case("post") || method.eq_ignore_ascii_case("put") {
        headers.push((
            "Content-Type".to_string(),
            "application/json; charset=UTF-8".to_string(),
        ));
    }

    if let Some(token) = token {
        // 原项目对测速请求设置 authorization="" (空字符串)，需原样传入
        // 登录前也需要空 authorization 头部，否则某些端点会拒绝请求
        headers.push(("authorization".to_string(), token.to_string()));
    }

    headers
}
