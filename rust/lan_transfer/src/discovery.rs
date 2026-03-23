use crate::types::{
    DeviceInfo, EventType, HeartbeatPayload, MessageType, TransferEvent, TransferMessage,
};
use anyhow::{anyhow, Result};
use async_channel::{Receiver, Sender};
use chrono::Utc;
use if_addrs::get_if_addrs;
use lazy_static::lazy_static;
use log::{debug, error, info};
use mdns_sd::{ServiceDaemon, ServiceEvent, ServiceInfo};
use std::collections::HashMap;
use std::net::{IpAddr, Ipv4Addr};
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::sync::RwLock;
use tokio::task::JoinSet;
use tokio::time::{timeout, Duration, Instant};
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
    last_fallback_scan: Arc<RwLock<Option<Instant>>>,
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
            last_fallback_scan: Arc::new(RwLock::new(None)),
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

    /// 获取本机首选局域网 IP（优先 IPv4）
    pub fn get_preferred_local_ip() -> String {
        match collect_local_ips() {
            Ok(ips) => ips
                .first()
                .map(std::string::ToString::to_string)
                .unwrap_or_else(|| "127.0.0.1".to_string()),
            Err(_) => "127.0.0.1".to_string(),
        }
    }

    /// 开始广播服务
    pub fn start_broadcast(&self) -> Result<()> {
        let service_name = format!("{}{}", SERVICE_NAME_PREFIX, DEVICE_ID.clone());
        // Host name 使用 ASCII，避免设备名中的空格或非 ASCII 导致 Bonjour 兼容问题。
        let host_name = format!("slimeworks-{}.local.", DEVICE_ID.replace('-', ""));
        let local_ips = collect_local_ips()?;
        info!(
            "mDNS broadcast register: service_name={}, host_name={}, port={}, ips={:?}",
            service_name, host_name, self.service_port, local_ips
        );

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
            local_ips.as_slice(),
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

                        let ip_address = select_preferred_ip_address(&info)
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
                                "New device discovered: {} ({}) ip={} port={}",
                                device.device_name, device.device_id, device.ip_address, device.port
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

    /// mDNS 发现为空时，主动扫描同网段设备（不依赖 multicast entitlement）
    pub async fn refresh_devices_fallback_scan(&self) -> Result<()> {
        {
            let mut last_scan = self.last_fallback_scan.write().await;
            let now = Instant::now();
            if let Some(previous) = *last_scan {
                if now.duration_since(previous) < Duration::from_secs(15) {
                    return Ok(());
                }
            }
            *last_scan = Some(now);
        }

        let local_ipv4 = collect_primary_ipv4()?;
        let octets = local_ipv4.octets();
        let prefix = format!("{}.{}.{}.", octets[0], octets[1], octets[2]);

        let probe = HeartbeatPayload {
            device_id: DEVICE_ID.to_string(),
            device_name: DEVICE_NAME.to_string(),
            device_type: DEVICE_TYPE.to_string(),
            port: self.service_port,
        };

        let mut join_set = JoinSet::new();
        for host in 1..=254u8 {
            let target_ip = format!("{}{}", prefix, host);
            if target_ip == local_ipv4.to_string() {
                continue;
            }

            if join_set.len() >= 48 {
                if let Some(joined) = join_set.join_next().await {
                    if let Ok(Some(device)) = joined {
                        self.save_discovered_device(device).await;
                    }
                }
            }

            let payload = probe.clone();
            let port = self.service_port;
            join_set.spawn(async move { probe_device_by_heartbeat(target_ip, port, payload).await });
        }

        let mut found = 0usize;
        while let Some(joined) = join_set.join_next().await {
            if let Ok(Some(device)) = joined {
                found += 1;
                self.save_discovered_device(device).await;
            }
        }

        info!(
            "Fallback subnet scan done: local_ip={}, found={} (port={})",
            local_ipv4, found, self.service_port
        );
        Ok(())
    }

    async fn save_discovered_device(&self, device: DeviceInfo) {
        if device.device_id == *DEVICE_ID {
            return;
        }

        let mut devices = self.discovered_devices.write().await;
        let is_new = !devices.contains_key(&device.device_id);
        devices.insert(device.device_id.clone(), device.clone());
        drop(devices);

        if is_new {
            info!(
                "Fallback discovered device: {} ({}) ip={} port={}",
                device.device_name, device.device_id, device.ip_address, device.port
            );
        }
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

fn collect_local_ips() -> Result<Vec<IpAddr>> {
    let mut ipv4 = Vec::new();
    let mut ipv6 = Vec::new();

    for iface in get_if_addrs().map_err(|e| anyhow!("Failed to query interfaces: {}", e))? {
        let ip = iface.ip();
        if ip.is_loopback() || ip.is_unspecified() {
            continue;
        }

        match ip {
            IpAddr::V4(_) => ipv4.push(ip),
            IpAddr::V6(v6) if !v6.is_unicast_link_local() => ipv6.push(ip),
            _ => {}
        }
    }

    if ipv4.is_empty() && ipv6.is_empty() {
        error!("No active local network interface found for mDNS broadcast");
        return Err(anyhow!("No active local network interface found"));
    }

    ipv4.extend(ipv6);
    Ok(ipv4)
}

fn collect_primary_ipv4() -> Result<Ipv4Addr> {
    for iface in get_if_addrs().map_err(|e| anyhow!("Failed to query interfaces: {}", e))? {
        if let IpAddr::V4(v4) = iface.ip() {
            if !v4.is_loopback() && !v4.is_unspecified() {
                return Ok(v4);
            }
        }
    }

    Err(anyhow!("No active IPv4 interface found"))
}

async fn probe_device_by_heartbeat(
    target_ip: String,
    target_port: u16,
    payload: HeartbeatPayload,
) -> Option<DeviceInfo> {
    let addr = format!("{}:{}", target_ip, target_port);
    let mut stream = match timeout(Duration::from_millis(180), TcpStream::connect(&addr)).await {
        Ok(Ok(stream)) => stream,
        _ => return None,
    };

    let message = TransferMessage {
        message_type: MessageType::Heartbeat,
        payload: serde_json::to_string(&payload).ok()?,
        timestamp: Utc::now().to_rfc3339(),
    };
    let bytes = serde_json::to_vec(&message).ok()?;
    let len = bytes.len() as u32;

    if timeout(Duration::from_millis(120), stream.write_all(&len.to_be_bytes()))
        .await
        .is_err()
    {
        return None;
    }
    if timeout(Duration::from_millis(120), stream.write_all(&bytes))
        .await
        .is_err()
    {
        return None;
    }

    let mut len_buf = [0u8; 4];
    if timeout(Duration::from_millis(180), stream.read_exact(&mut len_buf))
        .await
        .is_err()
    {
        return None;
    }
    let msg_len = u32::from_be_bytes(len_buf) as usize;
    if msg_len == 0 || msg_len > 64 * 1024 {
        return None;
    }

    let mut msg_buf = vec![0u8; msg_len];
    if timeout(Duration::from_millis(180), stream.read_exact(&mut msg_buf))
        .await
        .is_err()
    {
        return None;
    }

    let response: TransferMessage = serde_json::from_slice(&msg_buf).ok()?;
    if !matches!(response.message_type, MessageType::Heartbeat) {
        return None;
    }

    let mut device: DeviceInfo = serde_json::from_str(&response.payload).ok()?;
    if device.ip_address.is_empty() {
        device.ip_address = target_ip;
    }
    Some(device)
}

fn select_preferred_ip_address(info: &ServiceInfo) -> Option<IpAddr> {
    let mut ipv4_candidate: Option<IpAddr> = None;
    let mut ipv6_candidate: Option<IpAddr> = None;

    for addr in info.get_addresses() {
        if addr.is_loopback() || addr.is_unspecified() {
            continue;
        }

        match addr {
            IpAddr::V4(_) if ipv4_candidate.is_none() => ipv4_candidate = Some(*addr),
            IpAddr::V6(v6) if !v6.is_unicast_link_local() && ipv6_candidate.is_none() => {
                ipv6_candidate = Some(*addr)
            }
            _ => {}
        }
    }

    ipv4_candidate.or(ipv6_candidate)
}
