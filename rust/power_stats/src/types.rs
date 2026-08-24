use serde::{Deserialize, Serialize};

/// 单次电表读数（从HTML解析得到）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MeterReading {
    pub meter_id: String,
    pub meter_name: String,
    pub remaining_kwh: f64,
    pub remaining_yuan: f64,
    pub price: f64,
    pub fetched_at: i64,
}

/// 持久化存储的分钟级采样
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PowerSample {
    pub timestamp: i64,
    pub remaining_kwh: f64,
    pub remaining_yuan: f64,
    pub price: f64,
}

/// 模块配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PowerStatsConfig {
    pub meter_id: String,
    pub enabled: bool,
    pub interval_secs: u64,
    pub persist: bool,
    pub db_path: String,
}

impl Default for PowerStatsConfig {
    fn default() -> Self {
        Self {
            meter_id: String::new(),
            enabled: false,
            interval_secs: 60,
            persist: true,
            db_path: String::new(),
        }
    }
}

/// 运行时状态
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PowerStatsStatus {
    pub enabled: bool,
    pub meter_id: String,
    pub meter_name: String,
    pub current_kwh: f64,
    pub current_yuan: f64,
    pub price: f64,
    pub last_fetch: String,
    pub last_result: String,
    pub sample_count: u64,
    pub is_persisting: bool,
    pub polling: bool,
}

impl Default for PowerStatsStatus {
    fn default() -> Self {
        Self {
            enabled: false,
            meter_id: String::new(),
            meter_name: String::new(),
            current_kwh: 0.0,
            current_yuan: 0.0,
            price: 1.0,
            last_fetch: String::new(),
            last_result: String::new(),
            sample_count: 0,
            is_persisting: false,
            polling: false,
        }
    }
}

/// 图表中的一个统计桶
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StatBucket {
    pub label: String,
    pub timestamp: i64,
    pub consumption_kwh: f64,
    pub cost_yuan: f64,
    pub balance_yuan: f64,
    pub balance_kwh: f64,
}

/// 聚合统计结果（用于图表展示）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AggregatedStats {
    pub range: String,
    pub buckets: Vec<StatBucket>,
    pub total_consumption: f64,
    pub total_cost: f64,
    pub avg_balance: f64,
    pub current_balance: f64,
    pub current_kwh: f64,
    pub sample_count: u64,
}

/// 统计卡片汇总
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StatsSummary {
    pub meter_id: String,
    pub meter_name: String,
    pub current_kwh: f64,
    pub current_yuan: f64,
    pub price: f64,
    pub last_update: String,
    pub hour_consumption: f64,
    pub day_consumption: f64,
    pub week_consumption: f64,
    pub fifteen_day_consumption: f64,
    pub sixteen_day_consumption: f64,
    pub thirty_day_consumption: f64,
    pub hour_cost: f64,
    pub day_cost: f64,
    pub week_cost: f64,
    pub fifteen_day_cost: f64,
    pub thirty_day_cost: f64,
    pub minute_consumption: f64,
    pub sample_count: u64,
}

/// 抓取日志条目
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FetchLogEntry {
    pub timestamp: String,
    pub success: bool,
    pub message: String,
    pub kwh: f64,
    pub yuan: f64,
}
