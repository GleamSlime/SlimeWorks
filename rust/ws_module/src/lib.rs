pub mod api;
/// WebSocket 模块
///
/// 功能：
/// - PC 端：WebSocket 服务器（仅 PC 编译）
/// - 移动端：WebSocket 客户端
///
/// 使用条件编译区分 PC 和移动平台
mod types;

// PC 端服务器
#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
#[cfg(not(any(target_os = "ios", target_os = "android")))]
mod server;

// 移动端客户端
mod client;

pub use api::*;
pub use client::*;

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
#[cfg(not(any(target_os = "ios", target_os = "android")))]
pub use server::WsServerHandle;
