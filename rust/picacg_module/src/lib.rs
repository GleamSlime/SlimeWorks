/// PicACG 模块
///
/// 功能：
/// - PicACG 漫画平台 API 客户端（全平台，移动端 + 桌面端均支持）
/// - 用户认证（登录、注册、签到）
/// - 漫画浏览（分类、搜索、排行榜、首页推荐）
/// - 漫画详情、章节、图片
/// - 收藏、历史记录
/// - 代理配置（HTTP/SOCKS5 代理、CDN 分流）
pub mod api;
mod client;
mod error;
mod signature;
mod types;

pub use api::*;
pub use client::PicacgClient;
pub use types::*;
