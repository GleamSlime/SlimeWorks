/// 局域网传输模块 API
///
/// 为 Flutter Rust Bridge 提供局域网传输功能
use crate::manager::LanTransferManager;
use crate::types::*;
use anyhow::Result;
use flutter_rust_bridge::frb;
use lazy_static::lazy_static;
use log::{info, warn};
use std::sync::Arc;
use tokio::sync::RwLock;

lazy_static! {
    static ref MANAGER: Arc<RwLock<Option<LanTransferManager>>> = Arc::new(RwLock::new(None));
}

// 重新导出类型（FRB 需要）
pub use crate::types::{
    DeviceInfo, EventType, TransferEvent, TransferItem, TransferStatus, TransferType, TrustedDevice,
};

/// 初始化局域网传输服务
#[frb(sync)]
pub fn lan_transfer_init() -> Result<()> {
    env_logger::try_init().ok();
    Ok(())
}

/// 创建并启动传输管理器
pub async fn lan_transfer_start(port: u16) -> Result<()> {
    let mut manager_guard = MANAGER.write().await;

    if manager_guard.is_some() {
        warn!("lan_transfer_start ignored because manager already started");
        return Ok(());
    }

    info!("lan_transfer_start begin, port={}", port);

    let manager = LanTransferManager::new(port).await?;
    manager.start().await?;

    *manager_guard = Some(manager);

    Ok(())
}

/// 停止传输管理器
pub async fn lan_transfer_stop() -> Result<()> {
    let mut manager_guard = MANAGER.write().await;
    info!("lan_transfer_stop begin");

    if let Some(manager) = manager_guard.as_ref() {
        manager.stop().await?;
    }

    *manager_guard = None;
    info!("lan_transfer_stop done");

    Ok(())
}

/// 获取本机设备信息
pub async fn lan_transfer_get_local_device(port: u16) -> Result<String> {
    let manager_guard = MANAGER.read().await;

    if let Some(manager) = manager_guard.as_ref() {
        let device = manager.get_local_device_info(port);
        Ok(serde_json::to_string(&device)?)
    } else {
        Err(anyhow::anyhow!("Manager not started"))
    }
}

/// 获取已发现的设备列表
pub async fn lan_transfer_get_devices() -> Result<Vec<String>> {
    let manager_guard = MANAGER.read().await;

    if let Some(manager) = manager_guard.as_ref() {
        let mut devices = manager.get_discovered_devices().await;
        if devices.is_empty() {
            let _ = manager.refresh_devices_fallback_scan().await;
            devices = manager.get_discovered_devices().await;
        }
        info!("lan_transfer_get_devices count={}", devices.len());
        devices
            .iter()
            .map(|d| serde_json::to_string(d).map_err(|e| anyhow::anyhow!(e)))
            .collect()
    } else {
        Err(anyhow::anyhow!("Manager not started"))
    }
}

/// 发送文本消息
pub async fn lan_transfer_send_text(
    target_ip: String,
    target_port: u16,
    target_device_id: String,
    text: String,
) -> Result<String> {
    let manager_guard = MANAGER.read().await;

    if let Some(manager) = manager_guard.as_ref() {
        manager
            .send_text(target_ip, target_port, target_device_id, text)
            .await
    } else {
        Err(anyhow::anyhow!("Manager not started"))
    }
}

/// 发送文件
pub async fn lan_transfer_send_file(
    target_ip: String,
    target_port: u16,
    target_device_id: String,
    file_path: String,
) -> Result<String> {
    let manager_guard = MANAGER.read().await;

    if let Some(manager) = manager_guard.as_ref() {
        manager
            .send_file(target_ip, target_port, target_device_id, file_path)
            .await
    } else {
        Err(anyhow::anyhow!("Manager not started"))
    }
}

/// 接受传输
pub async fn lan_transfer_accept(transfer_id: String) -> Result<()> {
    let manager_guard = MANAGER.read().await;

    if let Some(manager) = manager_guard.as_ref() {
        manager.accept_transfer(transfer_id).await
    } else {
        Err(anyhow::anyhow!("Manager not started"))
    }
}

/// 拒绝传输
pub async fn lan_transfer_reject(transfer_id: String) -> Result<()> {
    let manager_guard = MANAGER.read().await;

    if let Some(manager) = manager_guard.as_ref() {
        manager.reject_transfer(transfer_id).await
    } else {
        Err(anyhow::anyhow!("Manager not started"))
    }
}

/// 取消传输
pub async fn lan_transfer_cancel(transfer_id: String) -> Result<()> {
    let manager_guard = MANAGER.read().await;

    if let Some(manager) = manager_guard.as_ref() {
        manager.cancel_transfer(transfer_id).await
    } else {
        Err(anyhow::anyhow!("Manager not started"))
    }
}

/// 获取所有传输记录
pub async fn lan_transfer_get_transfers() -> Result<Vec<String>> {
    let manager_guard = MANAGER.read().await;

    if let Some(manager) = manager_guard.as_ref() {
        let transfers = manager.get_transfers().await;
        transfers
            .iter()
            .map(|t| serde_json::to_string(t).map_err(|e| anyhow::anyhow!(e)))
            .collect()
    } else {
        Err(anyhow::anyhow!("Manager not started"))
    }
}

/// 添加信任设备
pub async fn lan_transfer_add_trusted(device_id: String, device_name: String) -> Result<()> {
    let manager_guard = MANAGER.read().await;

    if let Some(manager) = manager_guard.as_ref() {
        manager.add_trusted_device(device_id, device_name).await
    } else {
        Err(anyhow::anyhow!("Manager not started"))
    }
}

/// 移除信任设备
pub async fn lan_transfer_remove_trusted(device_id: String) -> Result<()> {
    let manager_guard = MANAGER.read().await;

    if let Some(manager) = manager_guard.as_ref() {
        manager.remove_trusted_device(device_id).await
    } else {
        Err(anyhow::anyhow!("Manager not started"))
    }
}

/// 检查是否为信任设备
pub async fn lan_transfer_is_trusted(device_id: String) -> Result<bool> {
    let manager_guard = MANAGER.read().await;

    if let Some(manager) = manager_guard.as_ref() {
        Ok(manager.is_trusted_device(device_id).await)
    } else {
        Err(anyhow::anyhow!("Manager not started"))
    }
}

/// 获取信任设备列表
pub async fn lan_transfer_get_trusted_devices() -> Result<Vec<String>> {
    let manager_guard = MANAGER.read().await;

    if let Some(manager) = manager_guard.as_ref() {
        let devices = manager.get_trusted_devices().await;
        devices
            .iter()
            .map(|d| serde_json::to_string(d).map_err(|e| anyhow::anyhow!(e)))
            .collect()
    } else {
        Err(anyhow::anyhow!("Manager not started"))
    }
}
