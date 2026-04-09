/// PicACG API 桥接层
///
/// 将独立 crate picacg_module 的 API 包装并暴露给 Flutter Rust Bridge
use anyhow::Result;
use flutter_rust_bridge::frb;

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
