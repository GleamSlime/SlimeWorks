use crate::types::{DeviceInfo, EventType, TransferEvent};
use anyhow::{anyhow, Result};
use async_channel::{Receiver, Sender};
use chrono::Utc;
use lazy_static::lazy_static;
use log::{debug, error, info};
use mdns_sd::{ServiceDaemon, ServiceEvent, ServiceInfo};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use uuid::Uuid;

const SERVICE_TYPE: &str = "_slimeworks-lan._tcp.local.";
const SERVICE_NAME_PREFIX: &str = "SlimeWorks-";

lazy_static! {
    static ref DEVICE_ID: String = Uuid::new_v4().to_string();
    static ref DEVICE_NAME: String = get_device_name();
    static ref DEVICE_TYPE: String = get_device_type();
}

/// 获取设备名称
fn get_device_name() -> String {
    hostname::get()
        .ok()
        .and_then(|h| h.into_string().ok())
        .unwrap_or_else(|| "Unknown Device".to_string())
}

/// 获取设备类型
fn get_device_type() -> String {
    #[cfg(target_os = "windows")]
    return "Windows".to_string();

    #[cfg(target_os = "macos")]
    return "MacOS".to_string();

    #[cfg(target_os = "ios")]
    return "iOS".to_string();

    #[cfg(target_os = "android")]
    return "Android".to_string();

    #[cfg(not(any(
        target_os = "windows",
        target_os = "macos",
        target_os = "ios",
        target_os = "android"
    )))]
    return "Unknown".to_string();
}

/// 设备发现服务
pub struct DiscoveryService {
    mdns: Arc<ServiceDaemon>,
    discovered_devices: Arc<RwLock<HashMap<String, DeviceInfo>>>,
    event_sender: Sender<TransferEvent>,
    event_receiver: Receiver<TransferEvent>,
    service_port: u16,
}

impl DiscoveryService {
    /// 创建新的发现服务
    pub fn new(port: u16) -> Result<Self> {
        let mdns =
            ServiceDaemon::new().map_err(|e| anyhow!("Failed to create mDNS daemon: {}", e))?;
        let (event_sender, event_receiver) = async_channel::unbounded();

        Ok(Self {
            mdns: Arc::new(mdns),
            discovered_devices: Arc::new(RwLock::new(HashMap::new())),
            event_sender,
            event_receiver,
            service_port: port,
        })
    }

    /// 获取本机设备ID
    pub fn get_device_id() -> String {
        DEVICE_ID.clone()
    }

    /// 获取本机设备名称
    pub fn get_device_name() -> String {
        DEVICE_NAME.clone()
    }

    /// 获取本机设备类型
    pub fn get_device_type() -> String {
        DEVICE_TYPE.clone()
    }

    /// 开始广播服务
    pub fn start_broadcast(&self) -> Result<()> {
        let service_name = format!("{}{}", SERVICE_NAME_PREFIX, DEVICE_ID.clone());
        let host_name = format!("{}.local.", DEVICE_NAME.clone());

        let properties: Option<std::collections::HashMap<String, String>> = Some(
            vec![
                ("device_id".to_string(), DEVICE_ID.to_string()),
                ("device_name".to_string(), DEVICE_NAME.to_string()),
                ("device_type".to_string(), DEVICE_TYPE.to_string()),
            ]
            .into_iter()
            .collect(),
        );

        let my_service = ServiceInfo::new(
            SERVICE_TYPE,
            &service_name,
            &host_name,
            "",
            self.service_port,
            properties,
        )
        .map_err(|e| anyhow!("Failed to create service info: {}", e))?;

        self.mdns
            .register(my_service)
            .map_err(|e| anyhow!("Failed to register service: {}", e))?;

        info!("Started broadcasting service: {}", service_name);
        Ok(())
    }

    /// 开始浏览服务
    pub fn start_browse(&self) -> Result<()> {
        let mdns = self.mdns.clone();
        let discovered_devices = self.discovered_devices.clone();
        let event_sender = self.event_sender.clone();

        // 浏览服务
        let receiver = mdns
            .browse(SERVICE_TYPE)
            .map_err(|e| anyhow!("Failed to browse services: {}", e))?;

        tokio::spawn(async move {
            while let Ok(event) = receiver.recv_async().await {
                match event {
                    ServiceEvent::ServiceResolved(info) => {
                        debug!("Service resolved: {:?}", info);

                        // 提取设备信息
                        let device_id = info
                            .get_property_val_str("device_id")
                            .unwrap_or_default()
                            .to_string();

                        // 忽略自己
                        if device_id == *DEVICE_ID {
                            continue;
                        }

                        let device_name = info
                            .get_property_val_str("device_name")
                            .unwrap_or_default()
                            .to_string();
                        let device_type = info
                            .get_property_val_str("device_type")
                            .unwrap_or_default()
                            .to_string();

                        let ip_address = info
                            .get_addresses()
                            .iter()
                            .next()
                            .map(|addr| addr.to_string())
                            .unwrap_or_default();

                        let device = DeviceInfo {
                            device_id: device_id.clone(),
                            device_name,
                            device_type,
                            ip_address,
                            port: info.get_port(),
                            discovered_at: Utc::now().to_rfc3339(),
                            is_online: true,
                        };

                        // 添加到已发现设备列表
                        let mut devices = discovered_devices.write().await;
                        let is_new = !devices.contains_key(&device_id);
                        devices.insert(device_id.clone(), device.clone());
                        drop(devices);

                        if is_new {
                            info!(
                                "New device discovered: {} ({})",
                                device.device_name, device.device_id
                            );

                            // 发送事件
                            let _ = event_sender
                                .send(TransferEvent {
                                    event_type: EventType::DeviceDiscovered,
                                    device_info: Some(device),
                                    transfer_item: None,
                                    message: None,
                                    timestamp: Utc::now().to_rfc3339(),
                                })
                                .await;
                        }
                    }
                    ServiceEvent::ServiceRemoved(_type_name, fullname) => {
                        debug!("Service removed: {}", fullname);

                        // 从设备列表中移除
                        let mut devices = discovered_devices.write().await;
                        if let Some((device_id, device)) = devices
                            .iter()
                            .find(|(_, d)| fullname.contains(&d.device_id))
                            .map(|(id, d)| (id.clone(), d.clone()))
                        {
                            devices.remove(&device_id);
                            drop(devices);

                            info!("Device lost: {} ({})", device.device_name, device.device_id);

                            // 发送事件
                            let _ = event_sender
                                .send(TransferEvent {
                                    event_type: EventType::DeviceLost,
                                    device_info: Some(device),
                                    transfer_item: None,
                                    message: None,
                                    timestamp: Utc::now().to_rfc3339(),
                                })
                                .await;
                        }
                    }
                    _ => {}
                }
            }
        });

        info!("Started browsing for services");
        Ok(())
    }

    /// 获取已发现的设备列表
    pub async fn get_discovered_devices(&self) -> Vec<DeviceInfo> {
        let devices = self.discovered_devices.read().await;
        devices.values().cloned().collect()
    }

    /// 接收事件
    pub fn get_event_receiver(&self) -> Receiver<TransferEvent> {
        self.event_receiver.clone()
    }

    /// 停止服务
    pub fn shutdown(&self) -> Result<()> {
        self.mdns
            .shutdown()
            .map_err(|e| anyhow!("Failed to shutdown mDNS: {}", e))?;
        info!("Discovery service shutdown");
        Ok(())
    }
}
