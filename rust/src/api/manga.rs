/// Manga API 桥接层
///
/// 将独立 crate manga_module 的 API 包装并暴露给 Flutter Rust Bridge
use anyhow::Result;
use flutter_rust_bridge::frb;
use std::sync::OnceLock;

// ==================== 初始化 / 配置 ====================

/// 初始化 Manga 客户端
#[frb(sync)]
pub fn manga_init() {
    manga_module::api::manga_init();
}

/// 设置代理
#[frb(sync)]
pub fn manga_set_proxy(proxy_url: String) {
    manga_module::api::manga_set_proxy(proxy_url);
}

/// 直接写入 Token
#[frb(sync)]
pub fn manga_set_token(token: String) {
    manga_module::api::manga_set_token(token);
}

/// 获取当前 Token
#[frb(sync)]
pub fn manga_get_token() -> String {
    manga_module::api::manga_get_token()
}

/// 登出并清除 Token
#[frb(sync)]
pub fn manga_logout() {
    manga_module::api::manga_logout();
}

/// 设置 API 分流模式
/// - 0: 标准直连
/// - 2: 分流2 (IP: 104.21.91.145)
/// - 3: 分流3 (IP: 188.114.98.153)
/// - 4: CDN分流 (自定义IP，默认 104.18.227.172)
/// - 5: JP反代 (https://bika-api.jpacg.cc)
/// - 6: US反代 (https://bika2-api.jpacg.cc)
#[frb(sync)]
pub fn manga_set_channel(mode: i32, custom: String) {
    manga_module::api::manga_set_channel(mode, custom);
}

/// 设置图片服务器（如 s3.picacomic.com / storage1.picacomic.com）
#[frb(sync)]
pub fn manga_set_image_server(server: String) {
    manga_module::api::manga_set_image_server(server);
}

/// 获取当前图片服务器
#[frb(sync)]
pub fn manga_get_image_server() -> String {
    manga_module::api::manga_get_image_server()
}

/// 测试分流节点连通性，返回延迟(ms)
pub async fn manga_test_channel(mode: i32, custom: String) -> Result<u64> {
    manga_module::api::manga_test_channel(mode, custom).await
}

// ==================== 认证 ====================

/// 登录
pub async fn manga_login(email: String, password: String) -> Result<String> {
    manga_module::api::manga_login(email, password).await
}

/// 获取用户信息
pub async fn manga_get_user_profile() -> Result<String> {
    manga_module::api::manga_get_user_profile().await
}

/// 每日签到
pub async fn manga_punch_in() -> Result<String> {
    manga_module::api::manga_punch_in().await
}

// ==================== 首页 ====================

/// 获取首页精选推荐
pub async fn manga_get_collections() -> Result<String> {
    manga_module::api::manga_get_collections().await
}

/// 获取随机漫画
pub async fn manga_get_random_comics() -> Result<String> {
    manga_module::api::manga_get_random_comics().await
}

// ==================== 分类 ====================

/// 获取所有分类
pub async fn manga_get_categories() -> Result<String> {
    manga_module::api::manga_get_categories().await
}

/// 按分类获取漫画列表
pub async fn manga_get_comics_by_category(
    category: String,
    page: i32,
    sort: String,
) -> Result<String> {
    manga_module::api::manga_get_comics_by_category(category, page, sort).await
}

// ==================== 搜索 ====================

/// 高级搜索
pub async fn manga_search_comics(
    keyword: String,
    categories: Vec<String>,
    page: i32,
    sort: String,
) -> Result<String> {
    manga_module::api::manga_search_comics(keyword, categories, page, sort).await
}

/// 热门搜索关键词
pub async fn manga_get_keywords() -> Result<String> {
    manga_module::api::manga_get_keywords().await
}

// ==================== 排行榜 ====================

/// 排行榜
pub async fn manga_get_rankings(time_type: String) -> Result<String> {
    manga_module::api::manga_get_rankings(time_type).await
}

// ==================== 漫画详情 ====================

/// 漫画详情
pub async fn manga_get_comic_detail(comic_id: String) -> Result<String> {
    manga_module::api::manga_get_comic_detail(comic_id).await
}

/// 漫画相关推荐
pub async fn manga_get_comic_recommendations(comic_id: String) -> Result<String> {
    manga_module::api::manga_get_comic_recommendations(comic_id).await
}

/// 章节列表
pub async fn manga_get_comic_eps(comic_id: String, page: i32) -> Result<String> {
    manga_module::api::manga_get_comic_eps(comic_id, page).await
}

/// 章节图片
pub async fn manga_get_eps_pages(comic_id: String, eps_order: i32, page: i32) -> Result<String> {
    manga_module::api::manga_get_eps_pages(comic_id, eps_order, page).await
}

// ==================== 收藏 ====================

/// 收藏列表
pub async fn manga_get_favourites(page: i32, sort: String) -> Result<String> {
    manga_module::api::manga_get_favourites(page, sort).await
}

/// 切换收藏状态
pub async fn manga_toggle_favourite(comic_id: String) -> Result<String> {
    manga_module::api::manga_toggle_favourite(comic_id).await
}

/// 切换点赞状态
pub async fn manga_toggle_like(comic_id: String) -> Result<String> {
    manga_module::api::manga_toggle_like(comic_id).await
}

// ==================== 评论 ====================

/// 评论列表
pub async fn manga_get_comments(comic_id: String, page: i32) -> Result<String> {
    manga_module::api::manga_get_comments(comic_id, page).await
}

/// 子评论列表
pub async fn manga_get_comment_children(comment_id: String, page: i32) -> Result<String> {
    manga_module::api::manga_get_comment_children(comment_id, page).await
}

/// 发表评论
pub async fn manga_send_comment(comic_id: String, content: String) -> Result<String> {
    manga_module::api::manga_send_comment(comic_id, content).await
}

/// 点赞评论
pub async fn manga_like_comment(comment_id: String) -> Result<String> {
    manga_module::api::manga_like_comment(comment_id).await
}

// ==================== 工具 ====================

/// 构建完整图片 URL
#[frb(sync)]
pub fn manga_build_image_url(file_server: String, path: String) -> String {
    manga_module::api::manga_build_image_url(file_server, path)
}

pub async fn manga_fetch_image(file_server: String, path: String) -> Result<Vec<u8>> {
    manga_module::api::manga_fetch_image(file_server, path).await
}

// ==================== 观看历史（本地数据库存储）====================
// 历史记录存储在 Rust 侧 redb 数据库中，比 SharedPreferences 更可靠高效。
// 数据格式：JSON 数组字符串，由 Dart 层负责序列化/反序列化。

const MANGA_HISTORY_TABLE: &str = "manga_history";
const MANGA_HISTORY_KEY: &str = "items";

/// 标记历史表是否已注册（防止重复迁移）
static HISTORY_TABLE_INIT: OnceLock<()> = OnceLock::new();

/// 确保历史表已初始化（依赖 manga_init_history 完成绑定）
fn ensure_history_table() {
    HISTORY_TABLE_INIT.get_or_init(|| {
        let _ = db_module::db_register_table(MANGA_HISTORY_TABLE.to_string());
    });
}

/// 初始化漫画历史记录数据库
///
/// 在应用启动时调用一次，传入应用数据目录下的 db 文件路径（由 Dart path_provider 提供）。
/// 表绑定到该专属文件，不受其他模块初始化顺序影响。
#[frb(sync)]
pub fn manga_init_history(db_path: String) {
    let _ = db_module::db_init(db_path.clone());
    // 绑定到专属文件，避免历史上全局单例被其他模块抢先导致历史写错文件
    if db_module::db_bind_table(MANGA_HISTORY_TABLE.to_string(), db_path.clone()).is_ok() {
        // 一次性迁移：历史上历史数据可能被写入 media.db / music_player.db
        migrate_scattered_manga_history(&db_path);
    }
    ensure_history_table();
}

/// 一次性迁移：把散落在其他数据库文件中的漫画历史合并回专属文件（幂等）。
fn migrate_scattered_manga_history(db_path: &str) {
    // 幂等标记存于独立的 manga_meta 表
    let _ = db_module::db_bind_table("manga_meta".to_string(), db_path.to_string());
    if let Ok(Some(flag)) =
        db_module::db_get("manga_meta".to_string(), "scatter_merged_v1".to_string())
    {
        if flag == "1" {
            return;
        }
    }
    let mut candidates = Vec::new();
    #[cfg(windows)]
    if let Ok(appdata) = std::env::var("APPDATA") {
        let base = std::path::Path::new(&appdata).join("SlimeWorks");
        candidates.push(base.join("media.db"));
        candidates.push(base.join("music_player.db"));
    }
    for candidate in &candidates {
        let src = candidate.to_string_lossy().into_owned();
        if src == db_path || !candidate.exists() {
            continue;
        }
        let _ = db_module::db_merge_tables(
            src,
            db_path.to_string(),
            vec![MANGA_HISTORY_TABLE.to_string()],
            false,
        );
    }
    let _ = db_module::db_set(
        "manga_meta".to_string(),
        "scatter_merged_v1".to_string(),
        "1".to_string(),
    );
}

/// 读取所有历史记录，返回 JSON 字符串（未初始化或无数据时返回空字符串）
#[frb(sync)]
pub fn manga_load_history() -> String {
    ensure_history_table();
    db_module::db_get(MANGA_HISTORY_TABLE.to_string(), MANGA_HISTORY_KEY.to_string())
        .unwrap_or(None)
        .unwrap_or_default()
}

/// 持久化历史记录（完整 JSON 字符串，由 Dart 构造后传入）
#[frb(sync)]
pub fn manga_save_history_raw(json: String) {
    ensure_history_table();
    let _ = db_module::db_set(MANGA_HISTORY_TABLE.to_string(), MANGA_HISTORY_KEY.to_string(), json);
}

/// 清空全部历史记录
#[frb(sync)]
pub fn manga_clear_history() {
    ensure_history_table();
    let _ = db_module::db_delete(MANGA_HISTORY_TABLE.to_string(), MANGA_HISTORY_KEY.to_string());
}
