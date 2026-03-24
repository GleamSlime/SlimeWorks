pub mod api;
/// 模块管理系统
///
/// 功能：
/// - 版本管理和锁版本
/// - 从 JSON 配置获取模块信息
/// - MD5 校验
/// - 自动更新检测
/// - 模糊匹配加载
mod config;
mod loader;
mod manager;
mod types;

pub use api::*;
pub use config::*;
pub use loader::*;
pub use manager::*;
pub use types::*;
