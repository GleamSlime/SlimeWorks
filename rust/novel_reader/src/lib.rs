/// Novel Reader 模块
///
/// 功能：
/// - 扫描指定目录下的 txt、epub 文件（递归）
/// - 使用 db_module 存储书籍元数据
/// - 解析和渲染 txt、epub 内容
pub mod api;
pub mod http_bridge_register;
pub mod parser;
pub mod scanner;
pub mod search;
pub mod types;

pub use api::*;
pub use types::*;

// 重新导出 SearchMatch 用于 Flutter
pub use api::SearchMatch;
