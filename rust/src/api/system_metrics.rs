use flutter_rust_bridge::frb;
use std::sync::{Mutex, OnceLock};
use std::time::Instant;
use sysinfo::{ProcessesToUpdate, System};

#[derive(Debug, Clone)]
pub struct SystemResourceSnapshot {
    pub cpu_usage_percent: f64,
    pub memory_used_mb: u64,
    pub memory_total_mb: u64,
    pub rx_kbps: f64,
    pub tx_kbps: f64,
}

#[derive(Debug, Clone)]
struct NetSpeedState {
    last_at: Instant,
    last_rx: u64,
    last_tx: u64,
}

static NET_STATE: OnceLock<Mutex<Option<NetSpeedState>>> = OnceLock::new();
static SYSTEM_STATE: OnceLock<Mutex<System>> = OnceLock::new();

fn net_state() -> &'static Mutex<Option<NetSpeedState>> {
    NET_STATE.get_or_init(|| Mutex::new(None))
}

fn metrics_system() -> &'static Mutex<System> {
    SYSTEM_STATE.get_or_init(|| Mutex::new(System::new_all()))
}

#[frb(sync)]
pub fn get_system_resource_snapshot() -> anyhow::Result<SystemResourceSnapshot> {
    let mut system = metrics_system()
        .lock()
        .map_err(|_| anyhow::anyhow!("metrics system lock poisoned"))?;

    system.refresh_cpu_usage();
    system.refresh_memory();

    let (cpu_usage_percent, memory_used_mb, memory_total_mb) = match sysinfo::get_current_pid() {
        Ok(current_pid) => {
            system.refresh_processes(ProcessesToUpdate::Some(&[current_pid]), true);
            if let Some(process) = system.process(current_pid) {
                (
                    process.cpu_usage() as f64,
                    process.memory() / 1024 / 1024,
                    process.virtual_memory() / 1024 / 1024,
                )
            } else {
                // iOS 等环境可能拿不到当前进程，回退为设备级状态。
                (
                    system.global_cpu_usage() as f64,
                    system.used_memory() / 1024 / 1024,
                    system.total_memory() / 1024 / 1024,
                )
            }
        }
        Err(_) => (
            system.global_cpu_usage() as f64,
            system.used_memory() / 1024 / 1024,
            system.total_memory() / 1024 / 1024,
        ),
    };

    // sysinfo 暂不提供跨平台稳定的进程级网络上下行统计，先返回应用级占位值。
    let total_rx: u64 = 0;
    let total_tx: u64 = 0;

    let now = Instant::now();
    let mut rx_kbps = 0.0;
    let mut tx_kbps = 0.0;

    if let Ok(mut guard) = net_state().lock() {
        if let Some(prev) = guard.as_ref() {
            let elapsed = now.duration_since(prev.last_at).as_secs_f64();
            if elapsed > 0.0 {
                let rx_delta = total_rx.saturating_sub(prev.last_rx) as f64;
                let tx_delta = total_tx.saturating_sub(prev.last_tx) as f64;
                rx_kbps = rx_delta / 1024.0 / elapsed;
                tx_kbps = tx_delta / 1024.0 / elapsed;
            }
        }

        *guard = Some(NetSpeedState {
            last_at: now,
            last_rx: total_rx,
            last_tx: total_tx,
        });
    }

    Ok(SystemResourceSnapshot {
        cpu_usage_percent,
        memory_used_mb,
        memory_total_mb,
        rx_kbps,
        tx_kbps,
    })
}
