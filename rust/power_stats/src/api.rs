use std::sync::{Arc, RwLock};
use std::time::Duration;

use slime_logger::{sw_error, sw_info, sw_warn};
use tokio::sync::Mutex as TokioMutex;
use tokio::task::JoinHandle;

use crate::aggregator;
use crate::client::fetch_meter_reading;
use crate::storage;
use crate::types::*;

static MANAGER: RwLock<Option<Arc<PowerStatsManager>>> = RwLock::new(None);

/// 电力统计核心管理器：负责抓取、存储、聚合、调度
struct PowerStatsManager {
    config: RwLock<PowerStatsConfig>,
    samples: RwLock<Vec<PowerSample>>,
    logs: RwLock<Vec<FetchLogEntry>>,
    status: RwLock<PowerStatsStatus>,
    scheduler_handle: TokioMutex<Option<JoinHandle<()>>>,
}

fn get_manager() -> Result<Arc<PowerStatsManager>, String> {
    MANAGER
        .read()
        .map_err(|e| format!("读取管理器锁失败: {}", e))?
        .clone()
        .ok_or("电力统计模块未初始化".to_string())
}

/// 将时间戳截断到分钟
fn truncate_to_minute(ts: i64) -> i64 {
    ts - (ts % 60)
}

impl PowerStatsManager {
    fn new(config: PowerStatsConfig) -> Self {
        let persist = config.persist;
        let meter_id = config.meter_id.clone();
        let status = PowerStatsStatus {
            enabled: config.enabled,
            meter_id: meter_id.clone(),
            is_persisting: persist,
            ..Default::default()
        };
        Self {
            config: RwLock::new(config),
            samples: RwLock::new(Vec::new()),
            logs: RwLock::new(Vec::new()),
            status: RwLock::new(status),
            scheduler_handle: TokioMutex::new(None),
        }
    }

    /// 执行一次抓取并存储
    async fn fetch_once_inner(&self) -> Result<MeterReading, String> {
        let meter_id = self.config.read().map_err(|e| format!("{}", e))?.meter_id.clone();
        if meter_id.is_empty() {
            return Err("未配置电表号".to_string());
        }

        let reading = fetch_meter_reading(&meter_id).await?;

        let sample = PowerSample {
            timestamp: truncate_to_minute(reading.fetched_at),
            remaining_kwh: reading.remaining_kwh,
            remaining_yuan: reading.remaining_yuan,
            price: reading.price,
        };

        // 写入内存缓存
        {
            let mut samples = self.samples.write().map_err(|e| format!("{}", e))?;
            // 去重：同分钟覆盖
            if let Some(existing) = samples.iter_mut().find(|s| s.timestamp == sample.timestamp) {
                *existing = sample.clone();
            } else {
                samples.push(sample.clone());
            }
            // 内存中最多保留30天数据
            let cutoff = chrono::Local::now().timestamp() - 30 * 86_400;
            samples.retain(|s| s.timestamp >= cutoff);
        }

        // 持久化写入
        let persist = self.config.read().map_err(|e| format!("{}", e))?.persist;
        if persist && storage::is_ready() {
            if let Err(e) = storage::insert_sample(&meter_id, &sample) {
                sw_warn!("[power_stats] 持久化采样失败: {}", e);
            }
        }

        // 更新状态
        {
            let mut status = self.status.write().map_err(|e| format!("{}", e))?;
            status.meter_id = reading.meter_id.clone();
            status.meter_name = reading.meter_name.clone();
            status.current_kwh = reading.remaining_kwh;
            status.current_yuan = reading.remaining_yuan;
            status.price = reading.price;
            status.last_fetch = chrono::Local::now().format("%Y-%m-%d %H:%M:%S").to_string();
            status.last_result = format!("抓取成功: {}kWh / {}元", reading.remaining_kwh, reading.remaining_yuan);
            status.is_persisting = persist;
            status.sample_count = self.sample_count();
        }

        // 追加日志
        {
            let mut logs = self.logs.write().map_err(|e| format!("{}", e))?;
            logs.push(FetchLogEntry {
                timestamp: chrono::Local::now().format("%Y-%m-%d %H:%M:%S").to_string(),
                success: true,
                message: format!("{}kWh / {}元", reading.remaining_kwh, reading.remaining_yuan),
                kwh: reading.remaining_kwh,
                yuan: reading.remaining_yuan,
            });
            let split = logs.len().saturating_sub(200);
            if split > 0 {
                logs.drain(0..split);
            }
        }

        Ok(reading)
    }

    /// 获取采样数量
    fn sample_count(&self) -> u64 {
        let persist = self.config.read().map(|c| c.persist).unwrap_or(false);
        if persist && storage::is_ready() {
            storage::count_samples(&self.config.read().map(|c| c.meter_id.clone()).unwrap_or_default())
                .unwrap_or(0)
        } else {
            self.samples.read().map(|s| s.len() as u64).unwrap_or(0)
        }
    }

    /// 读取全部采样（优先从数据库）
    fn load_samples(&self) -> Vec<PowerSample> {
        let config = self.config.read().unwrap();
        if config.persist && storage::is_ready() {
            storage::get_all_samples(&config.meter_id, 50_000).unwrap_or_default()
        } else {
            self.samples.read().unwrap().clone()
        }
    }
}

// ── 对外 FFI 接口 ─────────────────────────────────────────────────────────────

/// 初始化模块
pub fn power_stats_init(config_json: String) -> Result<String, String> {
    let config: PowerStatsConfig =
        serde_json::from_str(&config_json).map_err(|e| format!("解析电力统计配置失败: {}", e))?;

    // 持久化模式需要初始化数据库
    if config.persist && !config.db_path.is_empty() {
        storage::init_db(&config.db_path).map_err(|e| format!("初始化电力统计数据库失败: {}", e))?;
    }

    let manager = Arc::new(PowerStatsManager::new(config.clone()));

    {
        let mut instance = MANAGER.write().map_err(|e| format!("{}", e))?;
        *instance = Some(manager);
    }

    sw_info!("[power_stats] 模块初始化完成 (persist={})", config.persist);
    Ok("电力统计模块初始化完成".to_string())
}

/// 更新配置
pub fn power_stats_update_config(config_json: String) -> Result<(), String> {
    let manager = get_manager()?;
    let config: PowerStatsConfig =
        serde_json::from_str(&config_json).map_err(|e| format!("解析配置失败: {}", e))?;

    if config.persist && !config.db_path.is_empty() && !storage::is_ready() {
        storage::init_db(&config.db_path).map_err(|e| format!("初始化数据库失败: {}", e))?;
    }

    {
        let mut cfg = manager.config.write().map_err(|e| format!("{}", e))?;
        *cfg = config;
    }
    {
        let mut status = manager.status.write().map_err(|e| format!("{}", e))?;
        status.enabled = manager.config.read().map_err(|e| format!("{}", e))?.enabled;
        status.is_persisting = manager.config.read().map_err(|e| format!("{}", e))?.persist;
    }
    Ok(())
}

/// 读取配置
pub fn power_stats_get_config() -> Result<String, String> {
    let manager = get_manager()?;
    let config = manager.config.read().map_err(|e| format!("{}", e))?.clone();
    serde_json::to_string(&config).map_err(|e| format!("序列化配置失败: {}", e))
}

/// 设置开关
pub fn power_stats_set_enabled(enabled: bool) -> Result<(), String> {
    let manager = get_manager()?;
    manager.config.write().map_err(|e| format!("{}", e))?.enabled = enabled;
    manager.status.write().map_err(|e| format!("{}", e))?.enabled = enabled;
    sw_info!("[power_stats] 开关: {}", enabled);
    Ok(())
}

/// 手动触发一次抓取
pub async fn power_stats_fetch_once() -> Result<String, String> {
    let manager = get_manager()?;
    match manager.fetch_once_inner().await {
        Ok(reading) => {
            let json = serde_json::to_string(&reading).map_err(|e| format!("序列化读数失败: {}", e))?;
            Ok(json)
        }
        Err(e) => {
            let manager = get_manager()?;
            let mut status = manager.status.write().map_err(|e| format!("{}", e))?;
            status.last_fetch = chrono::Local::now().format("%Y-%m-%d %H:%M:%S").to_string();
            status.last_result = format!("抓取失败: {}", e);
            let mut logs = manager.logs.write().map_err(|e| format!("{}", e))?;
            logs.push(FetchLogEntry {
                timestamp: chrono::Local::now().format("%Y-%m-%d %H:%M:%S").to_string(),
                success: false,
                message: e.clone(),
                kwh: 0.0,
                yuan: 0.0,
            });
            let split = logs.len().saturating_sub(200);
            if split > 0 {
                logs.drain(0..split);
            }
            sw_error!("[power_stats] 抓取失败: {}", e);
            Err(e)
        }
    }
}

/// 启动定时轮询（每分钟抓取一次）
pub async fn power_stats_start_polling() -> Result<(), String> {
    let manager = get_manager()?;
    power_stats_stop_polling().await?;

    let interval_secs = manager.config.read().map_err(|e| format!("{}", e))?.interval_secs;
    let interval = Duration::from_secs(interval_secs.max(30));

    let mgr = manager.clone();
    let handle = tokio::spawn(async move {
        sw_info!("[power_stats] 定时轮询已启动，间隔{}秒", interval_secs);
        // 立即执行一次
        if let Err(e) = mgr.fetch_once_inner().await {
            sw_warn!("[power_stats] 轮询首次抓取失败: {}", e);
        }
        {
            if let Ok(mut s) = mgr.status.write() {
                s.polling = true;
            }
        }
        loop {
            tokio::time::sleep(interval).await;
            if let Ok(cfg) = mgr.config.read() {
                if !cfg.enabled {
                    sw_info!("[power_stats] 配置已关闭，停止轮询");
                    break;
                }
            }
            if let Err(e) = mgr.fetch_once_inner().await {
                sw_warn!("[power_stats] 轮询抓取失败: {}", e);
            }
        }
        if let Ok(mut s) = mgr.status.write() {
            s.polling = false;
        }
    });

    let mut h = manager.scheduler_handle.lock().await;
    *h = Some(handle);
    Ok(())
}

/// 停止定时轮询
pub async fn power_stats_stop_polling() -> Result<(), String> {
    let manager = get_manager()?;
    let mut h = manager.scheduler_handle.lock().await;
    if let Some(handle) = h.take() {
        handle.abort();
        sw_info!("[power_stats] 定时轮询已停止");
    }
    if let Ok(mut s) = manager.status.write() {
        s.polling = false;
    }
    Ok(())
}

/// 获取运行时状态
pub fn power_stats_get_status() -> Result<String, String> {
    let manager = get_manager()?;
    let mut status = manager.status.read().map_err(|e| format!("{}", e))?.clone();
    status.sample_count = manager.sample_count();
    serde_json::to_string(&status).map_err(|e| format!("序列化状态失败: {}", e))
}

/// 获取图表聚合数据
pub fn power_stats_get_aggregated(range: String) -> Result<String, String> {
    let manager = get_manager()?;
    let samples = manager.load_samples();
    let price = samples.last().map(|s| s.price).unwrap_or(1.0);
    let aggregated = aggregator::aggregate(&samples, &range, price);
    serde_json::to_string(&aggregated).map_err(|e| format!("序列化聚合数据失败: {}", e))
}

/// 获取统计卡片汇总
pub fn power_stats_get_summary() -> Result<String, String> {
    let manager = get_manager()?;
    let samples = manager.load_samples();
    let config = manager.config.read().map_err(|e| format!("{}", e))?;
    let status = manager.status.read().map_err(|e| format!("{}", e))?;
    let summary = aggregator::compute_summary(&samples, &config.meter_id, &status.meter_name);
    serde_json::to_string(&summary).map_err(|e| format!("序列化汇总数据失败: {}", e))
}

/// 获取抓取日志
pub fn power_stats_get_logs() -> Result<String, String> {
    let manager = get_manager()?;
    let logs = manager.logs.read().map_err(|e| format!("{}", e))?.clone();
    serde_json::to_string(&logs).map_err(|e| format!("序列化日志失败: {}", e))
}

/// 清空日志
pub fn power_stats_clear_logs() -> Result<(), String> {
    let manager = get_manager()?;
    manager.logs.write().map_err(|e| format!("{}", e))?.clear();
    Ok(())
}
