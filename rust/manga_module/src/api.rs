use slime_logger::{sw_info, sw_warn, sw_error, sw_debug};
/// Manga FFI API
///
/// 通过 flutter_rust_bridge 暴露给 Dart 层
use crate::client::{ChannelMode, MangaClient};
use anyhow::{anyhow, Result};
use flutter_rust_bridge::frb;
use lazy_static::lazy_static;
use serde_json::json;

lazy_static! {
    static ref CLIENT: MangaClient = MangaClient::new();
}

const DEFAULT_CDN_IP: &str = "104.18.227.172";

// ==================== 初始化 / 配置 ====================

#[frb(sync)]
pub fn manga_init() {}

#[frb(sync)]
pub fn manga_set_proxy(proxy_url: String) {
    sw_info!(
        "[Manga] 设置代理: {}",
        if proxy_url.is_empty() {
            "无"
        } else {
            &proxy_url
        }
    );
    CLIENT.set_proxy(&proxy_url);
}

#[frb(sync)]
pub fn manga_set_token(token: String) {
    sw_info!("[Manga] 设置 token (len={})", token.len());
    CLIENT.set_token(&token);
}

#[frb(sync)]
pub fn manga_get_token() -> String {
    CLIENT.get_token()
}

#[frb(sync)]
pub fn manga_logout() {
    sw_info!("[Manga] 退出登录，清除 token");
    CLIENT.clear_token();
}

/// 设置 API 分流模式
///
/// - `mode`: 0=直连(分流1), 2=分流2, 3=分流3, 4=CDN分流(自定义IP), 5=JP反代, 6=US反代, 7=PC中转
/// - `custom`: mode=4 时填写自定义 IP，mode=7 时填写中转地址 (IP:PORT)
#[frb(sync)]
pub fn manga_set_channel(mode: i32, custom: String) {
    let cdn_ip = if custom.trim().is_empty() {
        DEFAULT_CDN_IP.to_string()
    } else {
        custom.trim().to_string()
    };

    let channel = match mode {
        2 => ChannelMode::ChannelIp("104.21.91.145".to_string()),
        3 => ChannelMode::ChannelIp("188.114.98.153".to_string()),
        4 => ChannelMode::ChannelIp(cdn_ip.clone()),
        5 => ChannelMode::ReverseProxy("https://bika-api.jpacg.cc".to_string()),
        6 => ChannelMode::ReverseProxy("https://bika2-api.jpacg.cc".to_string()),
        7 => ChannelMode::LanRelay(custom.trim().to_string()),
        _ => ChannelMode::Direct,
    };
    sw_info!(
        "[Manga] 分流模式已切换: mode={} custom={:?} effective_custom={:?} -> {:?}",
        mode, custom, cdn_ip, channel
    );
    CLIENT.set_channel(channel);
}

/// 设置图片服务器域名
///
/// 常用值：`s3.picacomic.com`、`storage1.picacomic.com`、`storage-b.picacomic.com`
/// 传空字符串重置为默认值
#[frb(sync)]
pub fn manga_set_image_server(server: String) {
    let s = if server.is_empty() {
        "storage1.picacomic.com".to_string()
    } else {
        server
    };
    CLIENT.set_image_server(&s);
}

/// 获取当前图片服务器域名
#[frb(sync)]
pub fn manga_get_image_server() -> String {
    CLIENT.get_image_server()
}

/// 测试指定分流节点的连通性
///
/// - `mode` / `custom` 含义同 `manga_set_channel`
/// - 返回延迟毫秒数（成功），或抛出错误（失败）
pub async fn manga_test_channel(mode: i32, custom: String) -> Result<u64> {
    let cdn_ip = if custom.trim().is_empty() {
        DEFAULT_CDN_IP.to_string()
    } else {
        custom.trim().to_string()
    };

    let channel = match mode {
        2 => crate::client::ChannelMode::ChannelIp("104.21.91.145".to_string()),
        3 => crate::client::ChannelMode::ChannelIp("188.114.98.153".to_string()),
        4 => crate::client::ChannelMode::ChannelIp(cdn_ip.clone()),
        5 => crate::client::ChannelMode::ReverseProxy("https://bika-api.jpacg.cc".to_string()),
        6 => crate::client::ChannelMode::ReverseProxy("https://bika2-api.jpacg.cc".to_string()),
        7 => crate::client::ChannelMode::LanRelay(custom.trim().to_string()),
        _ => crate::client::ChannelMode::Direct,
    };
    sw_info!(
        "[Manga测速] 节点测试参数 mode={} custom={:?} effective_custom={:?}",
        mode, custom, cdn_ip
    );
    CLIENT
        .test_connectivity(channel)
        .await
        .map_err(|e| anyhow!("{}", e))
}

// ==================== 认证 ====================

pub async fn manga_login(email: String, password: String) -> Result<String> {
    sw_info!("[Manga] 开始登录: email={}", email);
    let body = json!({ "email": email, "password": password });
    let resp = CLIENT.post("auth/sign-in", body).await.map_err(|e| {
        sw_warn!("[Manga] 登录失败: {}", e);
        anyhow!("{}", e)
    })?;
    let token = resp
        .get("data")
        .and_then(|d| d.get("token"))
        .and_then(|t| t.as_str())
        .ok_or_else(|| anyhow!("登录响应中未找到 token"))?
        .to_string();
    sw_info!("[Manga] 登录成功, token len={}", token.len());
    CLIENT.set_token(&token);
    Ok(serde_json::to_string(&json!({ "token": token }))?)
}

pub async fn manga_get_user_profile() -> Result<String> {
    let resp = CLIENT
        .get("users/profile")
        .await
        .map_err(|e| anyhow!("{}", e))?;
    let user = resp
        .get("data")
        .and_then(|d| d.get("user"))
        .cloned()
        .unwrap_or(resp);
    Ok(serde_json::to_string(&user)?)
}

pub async fn manga_punch_in() -> Result<String> {
    let resp = CLIENT
        .post("users/punch-in", json!({}))
        .await
        .map_err(|e| anyhow!("{}", e))?;
    Ok(serde_json::to_string(&resp)?)
}

// ==================== 首页 ====================

pub async fn manga_get_collections() -> Result<String> {
    let resp = CLIENT
        .get("collections")
        .await
        .map_err(|e| anyhow!("{}", e))?;
    let collections = resp
        .get("data")
        .and_then(|d| d.get("collections"))
        .cloned()
        .unwrap_or(json!([]));
    Ok(serde_json::to_string(
        &json!({ "collections": collections }),
    )?)
}

pub async fn manga_get_random_comics() -> Result<String> {
    let resp = CLIENT
        .get("comics/random")
        .await
        .map_err(|e| anyhow!("{}", e))?;
    let comics = resp
        .get("data")
        .and_then(|d| d.get("comics"))
        .cloned()
        .unwrap_or(json!([]));
    Ok(serde_json::to_string(&comics)?)
}

// ==================== 分类 ====================

pub async fn manga_get_categories() -> Result<String> {
    let resp = CLIENT
        .get("categories")
        .await
        .map_err(|e| anyhow!("{}", e))?;
    let categories = resp
        .get("data")
        .and_then(|d| d.get("categories"))
        .cloned()
        .unwrap_or(json!([]));
    Ok(serde_json::to_string(&json!({ "categories": categories }))?)
}

pub async fn manga_get_comics_by_category(
    category: String,
    page: i32,
    sort: String,
) -> Result<String> {
    let path = format!(
        "comics?page={}&c={}&s={}",
        page,
        urlencoding_encode(&category),
        sort
    );
    let resp = CLIENT.get(&path).await.map_err(|e| anyhow!("{}", e))?;
    let data = resp.get("data").cloned().unwrap_or(resp.clone());
    Ok(serde_json::to_string(&data)?)
}

// ==================== 搜索 ====================

pub async fn manga_search_comics(
    keyword: String,
    categories: Vec<String>,
    page: i32,
    sort: String,
) -> Result<String> {
    let body = json!({ "keyword": keyword, "categories": categories, "sort": sort });
    let path = format!("comics/advanced-search?page={}", page);
    let resp = CLIENT
        .post(&path, body)
        .await
        .map_err(|e| anyhow!("{}", e))?;
    let data = resp.get("data").cloned().unwrap_or(resp.clone());
    Ok(serde_json::to_string(&data)?)
}

pub async fn manga_get_keywords() -> Result<String> {
    let resp = CLIENT.get("keywords").await.map_err(|e| anyhow!("{}", e))?;
    let keywords = resp
        .get("data")
        .and_then(|d| d.get("keywords"))
        .cloned()
        .unwrap_or(json!([]));
    Ok(serde_json::to_string(&json!({ "keywords": keywords }))?)
}

// ==================== 排行榜 ====================

pub async fn manga_get_rankings(time_type: String) -> Result<String> {
    let path = format!("comics/leaderboard?tt={}&ct=VC", time_type);
    let resp = CLIENT.get(&path).await.map_err(|e| anyhow!("{}", e))?;
    let comics = resp
        .get("data")
        .and_then(|d| d.get("comics"))
        .cloned()
        .unwrap_or(json!([]));
    Ok(serde_json::to_string(&json!({ "comics": comics }))?)
}

// ==================== 漫画详情 ====================

pub async fn manga_get_comic_detail(comic_id: String) -> Result<String> {
    let path = format!("comics/{}", comic_id);
    let resp = CLIENT.get(&path).await.map_err(|e| anyhow!("{}", e))?;
    let comic = resp
        .get("data")
        .and_then(|d| d.get("comic"))
        .cloned()
        .unwrap_or(resp.clone());
    Ok(serde_json::to_string(&json!({ "comic": comic }))?)
}

pub async fn manga_get_comic_recommendations(comic_id: String) -> Result<String> {
    let path = format!("comics/{}/recommendation", comic_id);
    let resp = CLIENT.get(&path).await.map_err(|e| anyhow!("{}", e))?;
    let comics = resp
        .get("data")
        .and_then(|d| d.get("comics"))
        .cloned()
        .unwrap_or(json!([]));
    Ok(serde_json::to_string(&json!({ "comics": comics }))?)
}

pub async fn manga_get_comic_eps(comic_id: String, page: i32) -> Result<String> {
    let path = format!("comics/{}/eps?page={}", comic_id, page);
    let resp = CLIENT.get(&path).await.map_err(|e| anyhow!("{}", e))?;
    let data = resp.get("data").cloned().unwrap_or(resp.clone());
    Ok(serde_json::to_string(&data)?)
}

pub async fn manga_get_eps_pages(comic_id: String, eps_order: i32, page: i32) -> Result<String> {
    let path = format!(
        "comics/{}/order/{}/pages?page={}",
        comic_id, eps_order, page
    );
    let resp = CLIENT.get(&path).await.map_err(|e| anyhow!("{}", e))?;
    let data = resp.get("data").cloned().unwrap_or(resp.clone());
    Ok(serde_json::to_string(&data)?)
}

// ==================== 收藏 ====================

pub async fn manga_get_favourites(page: i32, sort: String) -> Result<String> {
    let path = format!("users/favourite?page={}&s={}", page, sort);
    let resp = CLIENT.get(&path).await.map_err(|e| anyhow!("{}", e))?;
    let data = resp.get("data").cloned().unwrap_or(resp.clone());
    Ok(serde_json::to_string(&data)?)
}

pub async fn manga_toggle_favourite(comic_id: String) -> Result<String> {
    let path = format!("comics/{}/favourite", comic_id);
    let resp = CLIENT
        .post(&path, json!({}))
        .await
        .map_err(|e| anyhow!("{}", e))?;
    let action = resp
        .get("data")
        .and_then(|d| d.get("action"))
        .cloned()
        .unwrap_or(json!("favourite"));
    Ok(serde_json::to_string(&json!({ "action": action }))?)
}

pub async fn manga_toggle_like(comic_id: String) -> Result<String> {
    let path = format!("comics/{}/like", comic_id);
    let resp = CLIENT
        .post(&path, json!({}))
        .await
        .map_err(|e| anyhow!("{}", e))?;
    let action = resp
        .get("data")
        .and_then(|d| d.get("action"))
        .cloned()
        .unwrap_or(json!("like"));
    Ok(serde_json::to_string(&json!({ "action": action }))?)
}

// ==================== 评论 ====================

pub async fn manga_get_comments(comic_id: String, page: i32) -> Result<String> {
    let path = format!("comics/{}/comments?page={}", comic_id, page);
    let resp = CLIENT.get(&path).await.map_err(|e| anyhow!("{}", e))?;
    let data = resp.get("data").cloned().unwrap_or(resp.clone());
    Ok(serde_json::to_string(&data)?)
}

pub async fn manga_get_comment_children(comment_id: String, page: i32) -> Result<String> {
    let path = format!("comments/{}/childrens?page={}", comment_id, page);
    let resp = CLIENT.get(&path).await.map_err(|e| anyhow!("{}", e))?;
    let data = resp.get("data").cloned().unwrap_or(resp.clone());
    Ok(serde_json::to_string(&data)?)
}

pub async fn manga_send_comment(comic_id: String, content: String) -> Result<String> {
    let path = format!("comics/{}/comments", comic_id);
    let resp = CLIENT
        .post(&path, json!({ "content": content }))
        .await
        .map_err(|e| anyhow!("{}", e))?;
    Ok(serde_json::to_string(&resp)?)
}

pub async fn manga_like_comment(comment_id: String) -> Result<String> {
    let path = format!("comments/{}/like", comment_id);
    let resp = CLIENT
        .post(&path, json!({}))
        .await
        .map_err(|e| anyhow!("{}", e))?;
    Ok(serde_json::to_string(&resp)?)
}

// ==================== 工具 ====================

#[frb(sync)]
pub fn manga_build_image_url(file_server: String, path: String) -> String {
    MangaClient::build_image_url(&file_server, &path, &CLIENT.get_image_server())
}

pub async fn manga_fetch_image(file_server: String, path: String) -> Result<Vec<u8>> {
    CLIENT
        .fetch_image_bytes(&file_server, &path)
        .await
        .map_err(|e| anyhow!("{}", e))
}

fn urlencoding_encode(s: &str) -> String {
    percent_encoding::utf8_percent_encode(s, percent_encoding::NON_ALPHANUMERIC).to_string()
}

// ==================== PC 中转服务端函数 ====================
// 以下函数不直接暴露给 Flutter，而是供模块内部的节点服务器调用，
// 实现"PC中转"功能（移动端请求 -> PC 节点服务器 -> Manga）。

/// 中转 API 请求（供 PC 节点服务器用）
///
/// 使用 PC 自身的 CLIENT（包含 PC 的分流配置与 Token）转发 API 请求。
pub async fn manga_relay_api(
    path: String,
    method: String,
    body: Option<serde_json::Value>,
) -> anyhow::Result<serde_json::Value> {
    let result = match method.to_uppercase().as_str() {
        "POST" => CLIENT.post(&path, body.unwrap_or_else(|| json!({}))).await,
        "PUT" => CLIENT.put(&path).await,
        _ => CLIENT.get(&path).await,
    };
    result.map_err(|e| anyhow::anyhow!("{}", e))
}

/// 中转图片下载（供 PC 节点服务器用）
pub async fn manga_relay_image(
    file_server: String,
    path: String,
) -> anyhow::Result<Vec<u8>> {
    CLIENT
        .fetch_image_bytes(&file_server, &path)
        .await
        .map_err(|e| anyhow::anyhow!("{}", e))
}

/// 获取 PC 当前 Token（供 PC 节点服务器用）
pub fn manga_relay_get_token() -> String {
    CLIENT.get_token()
}
