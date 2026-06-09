pub mod aliyun_ddns; // 阿里云DDNS模块
pub mod capture;
pub mod extract;
pub mod ffmpeg;
pub mod game_library;
pub mod http_bridge;
pub mod lan_transfer;
pub mod logger;
// pub mod module_api;         // 已删除 - 依赖旧module_manager结构
pub mod manga; // Manga 漫画平台模块
pub mod media_collection; // 媒体集合模块
pub mod module_downloader;
pub mod module_loader; // 旧 API（CaptureProxy相关）
pub mod module_manager; // 新的统一模块管理系统（使用独立 crate）
pub mod music_player; // 音乐播放器模块
pub mod novel_reader; // 书籍阅读器模块
pub mod sentry_log; // Sentry日志收集模块
pub mod simple;
pub mod system_metrics;
pub mod websocket; // WebSocket 模块
pub mod whisper; // Whisper 语音识别模块

// 数据库模块
pub use db_module::*;
