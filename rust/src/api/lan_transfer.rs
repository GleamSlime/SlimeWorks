/// 局域网传输模块 API
///
/// 为 Flutter Rust Bridge 提供局域网传输功能
use anyhow::Result;
use flutter_rust_bridge::frb;

// 重新导出类型（FRB 需要）
pub use lan_transfer::{
    DeviceInfo, EventType, TransferEvent, TransferItem, TransferStatus, TransferType, TrustedDevice,
};

/// 初始化局域网传输服务
#[frb(sync)]
pub fn lan_transfer_init() -> Result<()> {
    lan_transfer::lan_transfer_init()
}

/// 创建并启动传输管理器
pub async fn lan_transfer_start(port: u16) -> Result<()> {
    lan_transfer::lan_transfer_start(port).await
}

/// 停止传输管理器
pub async fn lan_transfer_stop() -> Result<()> {
    lan_transfer::lan_transfer_stop().await
}

/// 获取本机设备信息
pub async fn lan_transfer_get_local_device(port: u16) -> Result<String> {
    lan_transfer::lan_transfer_get_local_device(port).await
}

/// 获取已发现的设备列表
pub async fn lan_transfer_get_devices() -> Result<Vec<String>> {
    lan_transfer::lan_transfer_get_devices().await
}

/// 发送文本消息
pub async fn lan_transfer_send_text(
    target_ip: String,
    target_port: u16,
    target_device_id: String,
    text: String,
) -> Result<String> {
    lan_transfer::lan_transfer_send_text(target_ip, target_port, target_device_id, text).await
}

/// 发送文件
pub async fn lan_transfer_send_file(
    target_ip: String,
    target_port: u16,
    target_device_id: String,
    file_path: String,
) -> Result<String> {
    lan_transfer::lan_transfer_send_file(target_ip, target_port, target_device_id, file_path).await
}

/// 接受传输
pub async fn lan_transfer_accept(transfer_id: String) -> Result<()> {
    lan_transfer::lan_transfer_accept(transfer_id).await
}

/// 拒绝传输
pub async fn lan_transfer_reject(transfer_id: String) -> Result<()> {
    lan_transfer::lan_transfer_reject(transfer_id).await
}

/// 取消传输
pub async fn lan_transfer_cancel(transfer_id: String) -> Result<()> {
    lan_transfer::lan_transfer_cancel(transfer_id).await
}

/// 获取所有传输记录
pub async fn lan_transfer_get_transfers() -> Result<Vec<String>> {
    lan_transfer::lan_transfer_get_transfers().await
}

/// 添加信任设备
pub async fn lan_transfer_add_trusted(device_id: String, device_name: String) -> Result<()> {
    lan_transfer::lan_transfer_add_trusted(device_id, device_name).await
}

/// 移除信任设备
pub async fn lan_transfer_remove_trusted(device_id: String) -> Result<()> {
    lan_transfer::lan_transfer_remove_trusted(device_id).await
}

/// 检查是否为信任设备
pub async fn lan_transfer_is_trusted(device_id: String) -> Result<bool> {
    lan_transfer::lan_transfer_is_trusted(device_id).await
}

/// 获取信任设备列表
pub async fn lan_transfer_get_trusted_devices() -> Result<Vec<String>> {
    lan_transfer::lan_transfer_get_trusted_devices().await
}
