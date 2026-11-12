/// 通用数据库模块
///
/// 功能：
/// - 提供基于 redb 的通用 KV 存储
/// - 支持多表管理
/// - 支持数据加密（可选）
/// - 支持批量操作
pub mod api;
/// 外部 ffmpeg/ffprobe 路径的进程级注册表（各业务模块共用的基础设施）
pub mod ffmpeg;
/// 应用数据根目录的平台分支（各业务模块共用的基础函数）
pub mod paths;
pub mod storage;
pub mod types;

pub use api::*;
pub use types::*;
