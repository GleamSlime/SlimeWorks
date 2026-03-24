/// 局域网文件传输模块
///
/// 功能：
/// - 局域网设备发现（mDNS）
/// - 文件传输（TCP）
/// - 文本消息传输
/// - 设备信任管理
/// - 传输历史记录
///
/// 支持平台：Windows, MacOS, iOS, Android
pub mod api;
mod discovery;
mod manager;
mod transfer;
mod types;

pub use api::*;
pub use manager::LanTransferManager;
pub use types::*;
