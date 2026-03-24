use crate::discovery::DiscoveryService;
use crate::transfer::TransferService;
use crate::types::*;
use anyhow::Result;
use async_channel::Receiver;
use std::sync::Arc;
use tokio::sync::RwLock;

/// 局域网传输管理器
pub struct LanTransferManager {
    discovery: Arc<RwLock<DiscoveryService>>,
    transfer: Arc<RwLock<TransferService>>,
    is_running: Arc<RwLock<bool>>,
}

impl LanTransferManager {
    /// 创建新的传输管理器
    pub async fn new(port: u16) -> Result<Self> {
        let device_id = DiscoveryService::get_device_id();
        let device_name = DiscoveryService::get_device_name();

        let discovery = DiscoveryService::new(port)?;
        let transfer = TransferService::new(port, device_id, device_name).await?;

        Ok(Self {
            discovery: Arc::new(RwLock::new(discovery)),
            transfer: Arc::new(RwLock::new(transfer)),
            is_running: Arc::new(RwLock::new(false)),
        })
    }

    /// 启动服务
    pub async fn start(&self) -> Result<()> {
        let mut is_running = self.is_running.write().await;
        if *is_running {
            return Ok(());
        }

        // 启动发现服务
        {
            let discovery = self.discovery.read().await;
            discovery.start_broadcast()?;
            discovery.start_browse()?;
        }

        // 启动传输服务
        {
            let mut transfer = self.transfer.write().await;
            transfer.start_listening().await?;
        }

        *is_running = true;
        Ok(())
    }

    /// 停止服务
    pub async fn stop(&self) -> Result<()> {
        let mut is_running = self.is_running.write().await;
        if !*is_running {
            return Ok(());
        }

        // 停止传输监听并释放端口
        {
            let mut transfer = self.transfer.write().await;
            transfer.stop_listening().await?;
        }

        // 停止发现服务
        {
            let discovery = self.discovery.read().await;
            discovery.shutdown()?;
        }

        *is_running = false;
        Ok(())
    }

    /// 获取本机设备信息
    pub fn get_local_device_info(&self, port: u16) -> DeviceInfo {
        DeviceInfo {
            device_id: DiscoveryService::get_device_id(),
            device_name: DiscoveryService::get_device_name(),
            device_type: DiscoveryService::get_device_type(),
            ip_address: DiscoveryService::get_preferred_local_ip(),
            port,
            discovered_at: chrono::Utc::now().to_rfc3339(),
            is_online: true,
        }
    }

    /// 获取已发现的设备列表
    pub async fn get_discovered_devices(&self) -> Vec<DeviceInfo> {
        self.discovery.read().await.get_discovered_devices().await
    }

    /// 当 mDNS 为空时触发主动扫描兜底
    pub async fn refresh_devices_fallback_scan(&self) -> Result<()> {
        self.discovery
            .read()
            .await
            .refresh_devices_fallback_scan()
            .await
    }

    /// 发送文本消息
    pub async fn send_text(
        &self,
        target_ip: String,
        target_port: u16,
        target_device_id: String,
        text: String,
    ) -> Result<String> {
        self.transfer
            .read()
            .await
            .send_text(target_ip, target_port, target_device_id, text)
            .await
    }

    /// 发送文件
    pub async fn send_file(
        &self,
        target_ip: String,
        target_port: u16,
        target_device_id: String,
        file_path: String,
    ) -> Result<String> {
        self.transfer
            .read()
            .await
            .send_file(target_ip, target_port, target_device_id, file_path)
            .await
    }

    /// 接受传输
    pub async fn accept_transfer(&self, transfer_id: String) -> Result<()> {
        self.transfer
            .read()
            .await
            .accept_transfer(transfer_id)
            .await
    }

    /// 拒绝传输
    pub async fn reject_transfer(&self, transfer_id: String) -> Result<()> {
        self.transfer
            .read()
            .await
            .reject_transfer(transfer_id)
            .await
    }

    /// 取消传输
    pub async fn cancel_transfer(&self, transfer_id: String) -> Result<()> {
        self.transfer
            .read()
            .await
            .cancel_transfer(transfer_id)
            .await
    }

    /// 获取所有传输记录
    pub async fn get_transfers(&self) -> Vec<TransferItem> {
        self.transfer.read().await.get_transfers().await
    }

    /// 添加信任设备
    pub async fn add_trusted_device(&self, device_id: String, device_name: String) -> Result<()> {
        self.transfer
            .read()
            .await
            .add_trusted_device(device_id, device_name)
            .await
    }

    /// 移除信任设备
    pub async fn remove_trusted_device(&self, device_id: String) -> Result<()> {
        self.transfer
            .read()
            .await
            .remove_trusted_device(device_id)
            .await
    }

    /// 检查是否为信任设备
    pub async fn is_trusted_device(&self, device_id: String) -> bool {
        self.transfer
            .read()
            .await
            .is_trusted_device(&device_id)
            .await
    }

    /// 获取信任设备列表
    pub async fn get_trusted_devices(&self) -> Vec<TrustedDevice> {
        self.transfer.read().await.get_trusted_devices().await
    }

    /// 获取事件接收器（发现事件）
    pub fn get_discovery_event_receiver(&self) -> Receiver<TransferEvent> {
        // 注意：这里需要在创建时存储receiver
        // 暂时返回一个新的channel
        let (_, rx) = async_channel::unbounded();
        rx
    }

    /// 获取事件接收器（传输事件）
    pub fn get_transfer_event_receiver(&self) -> Receiver<TransferEvent> {
        // 注意：这里需要在创建时存储receiver
        // 暂时返回一个新的channel
        let (_, rx) = async_channel::unbounded();
        rx
    }
}
