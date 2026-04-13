/// PicACG API 桥接层
///
/// 将独立 crate picacg_module 的 API 包装并暴露给 Flutter Rust Bridge
use anyhow::Result;
use flutter_rust_bridge::frb;
use std::sync::OnceLock;

// ==================== 初始化 / 配置 ====================

/// 初始化 PicACG 客户端
#[frb(sync)]
pub fn picacg_init() {
    picacg_module::api::picacg_init();
}

/// 设置代理
#[frb(sync)]
pub fn picacg_set_proxy(proxy_url: String) {
    picacg_module::api::picacg_set_proxy(proxy_url);
}

/// 直接写入 Token
#[frb(sync)]
pub fn picacg_set_token(token: String) {
    picacg_module::api::picacg_set_token(token);
}

/// 获取当前 Token
#[frb(sync)]
pub fn picacg_get_token() -> String {
    picacg_module::api::picacg_get_token()
}

/// 登出并清除 Token
#[frb(sync)]
pub fn picacg_logout() {
    picacg_module::api::picacg_logout();
}

/// 设置 API 分流模式
/// - 0: 标准直连
/// - 2: 分流2 (IP: 104.21.91.145)
/// - 3: 分流3 (IP: 188.114.98.153)
/// - 4: CDN分流 (自定义IP，默认 104.18.227.172)
/// - 5: JP反代 (https://bika-api.jpacg.cc)
/// - 6: US反代 (https://bika2-api.jpacg.cc)
#[frb(sync)]
pub fn picacg_set_channel(mode: i32, custom: String) {
    picacg_module::api::picacg_set_channel(mode, custom);
}

/// 设置图片服务器（如 s3.picacomic.com / storage1.picacomic.com）
#[frb(sync)]
pub fn picacg_set_image_server(server: String) {
    picacg_module::api::picacg_set_image_server(server);
}

/// 获取当前图片服务器
#[frb(sync)]
pub fn picacg_get_image_server() -> String {
    picacg_module::api::picacg_get_image_server()
}

/// 测试分流节点连通性，返回延迟(ms)
pub async fn picacg_test_channel(mode: i32, custom: String) -> Result<u64> {
    picacg_module::api::picacg_test_channel(mode, custom).await
}

// ==================== 认证 ====================

/// 登录
pub async fn picacg_login(email: String, password: String) -> Result<String> {
    picacg_module::api::picacg_login(email, password).await
}

/// 获取用户信息
pub async fn picacg_get_user_profile() -> Result<String> {
    picacg_module::api::picacg_get_user_profile().await
}

/// 每日签到
pub async fn picacg_punch_in() -> Result<String> {
    picacg_module::api::picacg_punch_in().await
}

// ==================== 首页 ====================

/// 获取首页精选推荐
pub async fn picacg_get_collections() -> Result<String> {
    picacg_module::api::picacg_get_collections().await
}

/// 获取随机漫画
pub async fn picacg_get_random_comics() -> Result<String> {
    picacg_module::api::picacg_get_random_comics().await
}

// ==================== 分类 ====================

/// 获取所有分类
pub async fn picacg_get_categories() -> Result<String> {
    picacg_module::api::picacg_get_categories().await
}

/// 按分类获取漫画列表
pub async fn picacg_get_comics_by_category(
    category: String,
    page: i32,
    sort: String,
) -> Result<String> {
    picacg_module::api::picacg_get_comics_by_category(category, page, sort).await
}

// ==================== 搜索 ====================

/// 高级搜索
pub async fn picacg_search_comics(
    keyword: String,
    categories: Vec<String>,
    page: i32,
    sort: String,
) -> Result<String> {
    picacg_module::api::picacg_search_comics(keyword, categories, page, sort).await
}

/// 热门搜索关键词
pub async fn picacg_get_keywords() -> Result<String> {
    picacg_module::api::picacg_get_keywords().await
}

// ==================== 排行榜 ====================

/// 排行榜
pub async fn picacg_get_rankings(time_type: String) -> Result<String> {
    picacg_module::api::picacg_get_rankings(time_type).await
}

// ==================== 漫画详情 ====================

/// 漫画详情
pub async fn picacg_get_comic_detail(comic_id: String) -> Result<String> {
    picacg_module::api::picacg_get_comic_detail(comic_id).await
}

/// 漫画相关推荐
pub async fn picacg_get_comic_recommendations(comic_id: String) -> Result<String> {
    picacg_module::api::picacg_get_comic_recommendations(comic_id).await
}

/// 章节列表
pub async fn picacg_get_comic_eps(comic_id: String, page: i32) -> Result<String> {
    picacg_module::api::picacg_get_comic_eps(comic_id, page).await
}

/// 章节图片
pub async fn picacg_get_eps_pages(comic_id: String, eps_order: i32, page: i32) -> Result<String> {
    picacg_module::api::picacg_get_eps_pages(comic_id, eps_order, page).await
}

// ==================== 收藏 ====================

/// 收藏列表
pub async fn picacg_get_favourites(page: i32, sort: String) -> Result<String> {
    picacg_module::api::picacg_get_favourites(page, sort).await
}

/// 切换收藏状态
pub async fn picacg_toggle_favourite(comic_id: String) -> Result<String> {
    picacg_module::api::picacg_toggle_favourite(comic_id).await
}

/// 切换点赞状态
pub async fn picacg_toggle_like(comic_id: String) -> Result<String> {
    picacg_module::api::picacg_toggle_like(comic_id).await
}

// ==================== 评论 ====================

/// 评论列表
pub async fn picacg_get_comments(comic_id: String, page: i32) -> Result<String> {
    picacg_module::api::picacg_get_comments(comic_id, page).await
}

/// 子评论列表
pub async fn picacg_get_comment_children(comment_id: String, page: i32) -> Result<String> {
    picacg_module::api::picacg_get_comment_children(comment_id, page).await
}

/// 发表评论
pub async fn picacg_send_comment(comic_id: String, content: String) -> Result<String> {
    picacg_module::api::picacg_send_comment(comic_id, content).await
}

/// 点赞评论
pub async fn picacg_like_comment(comment_id: String) -> Result<String> {
    picacg_module::api::picacg_like_comment(comment_id).await
}

// ==================== 工具 ====================

/// 构建完整图片 URL
#[frb(sync)]
pub fn picacg_build_image_url(file_server: String, path: String) -> String {
    picacg_module::api::picacg_build_image_url(file_server, path)
}

pub async fn picacg_fetch_image(file_server: String, path: String) -> Result<Vec<u8>> {
    picacg_module::api::picacg_fetch_image(file_server, path).await
}

// ==================== 观看历史（本地数据库存储）====================
// 历史记录存储在 Rust 侧 redb 数据库中，比 SharedPreferences 更可靠高效。
// 数据格式：JSON 数组字符串，由 Dart 层负责序列化/反序列化。

const PICACG_HISTORY_TABLE: &str = "picacg_history";
const PICACG_HISTORY_KEY: &str = "items";

/// 标记历史表是否已注册（防止重复 leak 内存）
static HISTORY_TABLE_INIT: OnceLock<()> = OnceLock::new();

/// 确保历史表已初始化（注册到 db_module 的已打开数据库中）
fn ensure_history_table() {
    HISTORY_TABLE_INIT.get_or_init(|| {
        let _ = db_module::db_register_table(PICACG_HISTORY_TABLE.to_string());
    });
}

/// 初始化漫画历史记录数据库
///
/// 在应用启动时调用一次，传入应用数据目录下的 db 文件路径（由 Dart path_provider 提供）。
/// db_module 是全局单例，若已初始化则幂等返回。
#[frb(sync)]
pub fn picacg_init_history(db_path: String) {
    let _ = db_module::db_init(db_path);
    ensure_history_table();
}

/// 读取所有历史记录，返回 JSON 字符串（未初始化或无数据时返回空字符串）
#[frb(sync)]
pub fn picacg_load_history() -> String {
    ensure_history_table();
    db_module::db_get(PICACG_HISTORY_TABLE.to_string(), PICACG_HISTORY_KEY.to_string())
        .unwrap_or(None)
        .unwrap_or_default()
}

/// 持久化历史记录（完整 JSON 字符串，由 Dart 构造后传入）
#[frb(sync)]
pub fn picacg_save_history_raw(json: String) {
    ensure_history_table();
    let _ = db_module::db_set(PICACG_HISTORY_TABLE.to_string(), PICACG_HISTORY_KEY.to_string(), json);
}

/// 清空全部历史记录
#[frb(sync)]
pub fn picacg_clear_history() {
    ensure_history_table();
    let _ = db_module::db_delete(PICACG_HISTORY_TABLE.to_string(), PICACG_HISTORY_KEY.to_string());
}

