pub mod capture;
pub mod ffmpeg;
pub mod http_bridge;
pub mod logger;
// pub mod module_api;         // 已删除 - 依赖旧module_manager结构
pub mod module_downloader;
pub mod module_loader; // 旧 API（CaptureProxy相关）
pub mod module_manager; // 新的统一模块管理系统（使用独立 crate）
pub mod novel_reader; // 小说阅读器模块
pub mod simple;
pub mod websocket; // WebSocket 模块

// 数据库模块
pub use db_module::*;
