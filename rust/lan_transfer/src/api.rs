/// 局域网传输模块 API
///
/// 为 Flutter Rust Bridge 提供局域网传输功能
use crate::manager::LanTransferManager;
use anyhow::Result;
use flutter_rust_bridge::frb;
use lazy_static::lazy_static;
use slime_logger::{sw_info, sw_warn};
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
    Ok(())
}

/// 创建并启动传输管理器
///
/// [pre_trusted_json] 为可选的已持久化信任设备 JSON 列表（每项为 `{"device_id":…,"device_name":…}` 的 JSON 字符串），
/// 在 TCP 监听开始前注入，彻底消除"服务启动 → Dart 注入"窗口期内信任设备无法识别的竞态问题。
pub async fn lan_transfer_start(
    port: u16,
    save_dir: String,
    pre_trusted_json: Vec<String>,
) -> Result<()> {
    let mut manager_guard = MANAGER.write().await;

    if manager_guard.is_some() {
        sw_warn!("lan_transfer_start ignored because manager already started");
        return Ok(());
    }

    sw_info!(
        "lan_transfer_start begin, port={}, save_dir={}, pre_trusted={}",
        port,
        save_dir,
        pre_trusted_json.len()
    );

    // 加载或创建持久化设备 ID，确保换网络/重启 App 后设备 ID 不变
    let device_id = load_or_create_device_id(&save_dir).await;
    crate::discovery::DiscoveryService::set_persistent_device_id(device_id).await;

    let manager = LanTransferManager::new(port).await?;
    manager.set_save_dir(save_dir).await;

    // 在 TCP 监听启动前注入预加载的信任设备，确保第一个连接就能被正确识别
    for json_str in &pre_trusted_json {
        if let Ok(val) = serde_json::from_str::<serde_json::Value>(json_str) {
            let id = val
                .get("device_id")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string();
            let name = val
                .get("device_name")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string();
            if !id.is_empty() {
                if let Err(e) = manager.add_trusted_device(id.clone(), name).await {
                    sw_warn!("预注入信任设备失败 {}: {}", id, e);
                } else {
                    sw_info!("预注入信任设备: {}", id);
                }
            }
        }
    }

    manager.start().await?;

    *manager_guard = Some(manager);

    Ok(())
}

/// 从 <save_dir>/device_id.txt 加载设备 ID；文件不存在则生成新 UUID 并持久化。
async fn load_or_create_device_id(save_dir: &str) -> String {
    use std::path::Path;
    use tokio::fs;
    use uuid::Uuid;

    let dir = Path::new(save_dir);
    let id_file = dir.join("device_id.txt");

    // 尝试读取已有 ID
    if let Ok(content) = fs::read_to_string(&id_file).await {
        let id = content.trim().to_string();
        if !id.is_empty() {
            sw_info!("已加载持久化设备 ID: {}", id);
            return id;
        }
    }

    // 首次：生成新 UUID 并写入文件
    let new_id = Uuid::new_v4().to_string();
    if let Err(e) = fs::create_dir_all(dir).await {
        sw_warn!("创建互传目录失败: {}", e);
    }
    if let Err(e) = fs::write(&id_file, &new_id).await {
        sw_warn!("写入设备 ID 文件失败: {}", e);
    } else {
        sw_info!("已生成并保存新设备 ID: {}", new_id);
    }
    new_id
}

/// 停止传输管理器
pub async fn lan_transfer_stop() -> Result<()> {
    let mut manager_guard = MANAGER.write().await;
    sw_info!("lan_transfer_stop begin");

    if let Some(manager) = manager_guard.as_ref() {
        manager.stop().await?;
    }

    *manager_guard = None;
    sw_info!("lan_transfer_stop done");

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
/// 若设备列表为空，在后台触发 fallback 子网扫描（非阻塞，避免卡住 Dart UI）
pub async fn lan_transfer_get_devices() -> Result<Vec<String>> {
    use crate::discovery::DiscoveryService;
    let local_device_id = DiscoveryService::get_device_id();

    // 先取当前设备列表并序列化，释放读锁后再决定是否触发后台扫描
    let (result, need_fallback) = {
        let manager_guard = MANAGER.read().await;
        if let Some(manager) = manager_guard.as_ref() {
            let devices = manager.get_discovered_devices().await;
            // 过滤本机（Mac 上 mDNS 可能会把自己也加进来）
            let devices: Vec<_> = devices
                .into_iter()
                .filter(|d| d.device_id != local_device_id)
                .collect();
            let is_empty = devices.is_empty();
            sw_info!("lan_transfer_get_devices count={}", devices.len());
            let serialized: Result<Vec<String>> = devices
                .iter()
                .map(|d| serde_json::to_string(d).map_err(|e| anyhow::anyhow!(e)))
                .collect();
            (serialized, is_empty)
        } else {
            return Err(anyhow::anyhow!("Manager not started"));
        }
    }; // manager_guard 在此释放

    // 若无设备，在后台触发 fallback 扫描，不阻塞本次调用
    if need_fallback {
        tokio::spawn(async {
            let guard = MANAGER.read().await;
            if let Some(mgr) = guard.as_ref() {
                let _ = mgr.refresh_devices_fallback_scan().await;
            }
        });
    }

    result
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

#[cfg(test)]
mod tests {
    use super::*;

    /// MANAGER 为进程级全局状态，涉及它的用例必须串行执行
    static API_TEST_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

    fn lock_serial() -> std::sync::MutexGuard<'static, ()> {
        API_TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// lan_transfer_init 是空实现，同步调用应始终成功
    #[test]
    fn lan_transfer_init_sync_is_noop_ok() {
        crate::api::lan_transfer_init().expect("lan_transfer_init 应返回 Ok");
    }

    /// 未 start 先调用各业务 API：统一返回 "Manager not started"
    /// stop 例外：未启动时调用也应安全幂等
    #[tokio::test]
    async fn api_calls_before_start_return_not_started_error() {
        let _guard = lock_serial();
        // 确保干净状态（stop 在未启动时也应返回 Ok，顺带覆盖该幂等分支）
        crate::api::lan_transfer_stop().await.expect("未启动时 stop 应幂等成功");

        let cases: Vec<(&str, Result<String>)> = vec![
            (
                "get_local_device",
                crate::api::lan_transfer_get_local_device(0).await.map(|s| s),
            ),
            ("get_devices", crate::api::lan_transfer_get_devices().await.map(|v| v.join(","))),
            (
                "send_text",
                crate::api::lan_transfer_send_text(
                    "127.0.0.1".into(),
                    0,
                    "dev".into(),
                    "hi".into(),
                )
                .await
                .map(|s| s),
            ),
            (
                "send_file",
                crate::api::lan_transfer_send_file("127.0.0.1".into(), 0, "dev".into(), "/x".into())
                    .await
                    .map(|s| s),
            ),
            ("get_transfers", crate::api::lan_transfer_get_transfers().await.map(|v| v.join(","))),
            (
                "get_trusted_devices",
                crate::api::lan_transfer_get_trusted_devices().await.map(|v| v.join(",")),
            ),
        ];
        for (name, res) in cases {
            let err = res.unwrap_err();
            assert!(err.to_string().contains("Manager not started"), "{name}: {err}");
        }
        // 返回类型非 String 的接口逐个断言
        assert!(crate::api::lan_transfer_accept("t1".into())
            .await
            .unwrap_err()
            .to_string()
            .contains("Manager not started"));
        assert!(crate::api::lan_transfer_reject("t1".into())
            .await
            .unwrap_err()
            .to_string()
            .contains("Manager not started"));
        assert!(crate::api::lan_transfer_cancel("t1".into())
            .await
            .unwrap_err()
            .to_string()
            .contains("Manager not started"));
        assert!(crate::api::lan_transfer_add_trusted("id".into(), "name".into())
            .await
            .unwrap_err()
            .to_string()
            .contains("Manager not started"));
        assert!(crate::api::lan_transfer_remove_trusted("id".into())
            .await
            .unwrap_err()
            .to_string()
            .contains("Manager not started"));
        assert!(crate::api::lan_transfer_is_trusted("id".into())
            .await
            .unwrap_err()
            .to_string()
            .contains("Manager not started"));
    }

    /// 双 init：MANAGER 已存在时 lan_transfer_start 走幂等早退分支，
    /// 不重复创建设备 ID 文件、不重新绑定端口（save_dir 保持空白即证明未深入执行）
    #[tokio::test]
    async fn double_start_returns_ok_without_reinitializing() {
        let _guard = lock_serial();
        crate::api::lan_transfer_stop().await.unwrap();

        // 注入一个「已创建但未 start」的 manager（port=0 ⇒ 临时端口，不占用真实端口，
        // 也不调用 manager.start()，因此不触发 mDNS 广播/浏览）
        let manager = LanTransferManager::new(0).await.expect("测试注入 manager 应成功");
        *MANAGER.write().await = Some(manager);

        // save_dir 指向不存在的空目录：若走了完整初始化流程，
        // load_or_create_device_id 会在其中写入 device_id.txt
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let save_dir = std::env::temp_dir()
            .join(format!("lan_transfer_api_test_{}_{}", std::process::id(), nanos));
        let save_dir_str = save_dir.to_str().unwrap().to_string();

        let res = crate::api::lan_transfer_start(0, save_dir_str.clone(), vec![]).await;
        assert!(res.is_ok(), "双 init 应幂等返回 Ok: {:?}", res);
        assert!(
            !save_dir.join("device_id.txt").exists(),
            "早退分支不得执行设备 ID 持久化"
        );
        assert!(!save_dir.exists() || std::fs::read_dir(&save_dir).unwrap().count() == 0);

        // 清理：stop 时 manager 从未 start（is_running=false），应安全幂等
        crate::api::lan_transfer_stop().await.unwrap();
        assert!(MANAGER.read().await.is_none());
        let _ = std::fs::remove_dir_all(&save_dir);
    }
}
