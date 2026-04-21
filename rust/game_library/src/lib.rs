/// 游戏库模块
///
/// 功能：
/// - 本地视觉小说/游戏库管理（来自 LunaBox 迁移）
/// - 游戏 CRUD、分类管理、游玩时长追踪、统计
/// - 全平台支持（桌面端支持启动游戏，移动端只读查看）
pub mod api;
mod db;
mod types;

pub use api::*;
pub use types::*;
