/// 通用数据库模块
///
/// 功能：
/// - 提供基于 redb 的通用 KV 存储
/// - 支持多表管理
/// - 支持数据加密（可选）
/// - 支持批量操作
pub mod api;
pub mod storage;
pub mod types;

pub use api::*;
pub use types::*;
