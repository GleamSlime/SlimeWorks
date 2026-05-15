use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// Sentry事件级别
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum SentryLevel {
    fatal,
    error,
    warning,
    info,
    debug,
}

impl SentryLevel {
    pub fn as_str(&self) -> &'static str {
        match self {
            SentryLevel::fatal => "fatal",
            SentryLevel::error => "error",
            SentryLevel::warning => "warning",
            SentryLevel::info => "info",
            SentryLevel::debug => "debug",
        }
    }

    pub fn from_str(s: &str) -> Self {
        match s {
            "fatal" => SentryLevel::fatal,
            "error" => SentryLevel::error,
            "warning" => SentryLevel::warning,
            "info" => SentryLevel::info,
            "debug" => SentryLevel::debug,
            _ => SentryLevel::info,
        }
    }
}

/// Sentry异常信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SentryException {
    #[serde(rename = "type")]
    pub exc_type: Option<String>,
    pub value: Option<String>,
    pub module: Option<String>,
    pub stacktrace: Option<SentryStacktrace>,
}

/// Sentry堆栈跟踪
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SentryStacktrace {
    pub frames: Vec<SentryFrame>,
}

/// Sentry堆栈帧
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SentryFrame {
    pub filename: Option<String>,
    pub function: Option<String>,
    pub lineno: Option<i64>,
    pub colno: Option<i64>,
    pub abs_path: Option<String>,
    #[serde(default)]
    pub in_app: Option<bool>,
}

/// Sentry面包屑
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SentryBreadcrumb {
    pub timestamp: Option<String>,
    pub category: Option<String>,
    pub message: Option<String>,
    pub level: Option<String>,
    #[serde(rename = "type")]
    pub breadcrumb_type: Option<String>,
    #[serde(default)]
    pub data: Option<serde_json::Value>,
}

/// Sentry用户信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SentryUser {
    pub id: Option<String>,
    pub email: Option<String>,
    pub username: Option<String>,
    pub ip_address: Option<String>,
}

/// Sentry请求信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SentryRequest {
    pub url: Option<String>,
    pub method: Option<String>,
    pub headers: Option<serde_json::Value>,
    pub data: Option<serde_json::Value>,
}

/// Sentry设备信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SentryDevice {
    pub brand: Option<String>,
    pub model: Option<String>,
    pub os: Option<String>,
    pub os_version: Option<String>,
}

/// Sentry SDK信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SentrySdkInfo {
    pub name: Option<String>,
    pub version: Option<String>,
}

/// 完整的Sentry事件（兼容Sentry协议）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SentryEvent {
    pub event_id: String,
    #[serde(default)]
    pub timestamp: Option<String>,
    #[serde(default)]
    pub received_at: Option<String>,
    #[serde(default)]
    pub level: Option<SentryLevel>,
    #[serde(default)]
    pub logger: Option<String>,
    #[serde(default)]
    pub culprit: Option<String>,
    #[serde(default)]
    pub transaction: Option<String>,
    #[serde(default)]
    pub server_name: Option<String>,
    #[serde(default)]
    pub release: Option<String>,
    #[serde(default)]
    pub environment: Option<String>,
    #[serde(default)]
    pub platform: Option<String>,
    #[serde(default)]
    pub message: Option<String>,
    #[serde(default)]
    pub exception: Option<SentryExceptionContainer>,
    #[serde(default)]
    pub breadcrumbs: Option<SentryBreadcrumbsContainer>,
    #[serde(default)]
    pub tags: Option<serde_json::Value>,
    #[serde(default)]
    pub extra: Option<serde_json::Value>,
    #[serde(default)]
    pub contexts: Option<serde_json::Value>,
    #[serde(default)]
    pub user: Option<SentryUser>,
    #[serde(default)]
    pub request: Option<SentryRequest>,
    #[serde(default)]
    pub device: Option<SentryDevice>,
    #[serde(default)]
    pub sdk: Option<SentrySdkInfo>,
    #[serde(default)]
    pub fingerprint: Option<Vec<String>>,
    #[serde(default)]
    pub title: Option<String>,
    #[serde(rename = "type", default)]
    pub event_type: Option<String>,
    #[serde(flatten)]
    pub unknown_fields: serde_json::Value,
}

/// Sentry异常容器
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SentryExceptionContainer {
    pub values: Vec<SentryException>,
}

/// Sentry面包屑容器
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SentryBreadcrumbsContainer {
    pub values: Vec<SentryBreadcrumb>,
}

impl Default for SentryEvent {
    fn default() -> Self {
        Self {
            event_id: uuid::Uuid::new_v4().to_string().replace("-", ""),
            timestamp: Some(Utc::now().to_rfc3339()),
            received_at: Some(Utc::now().to_rfc3339()),
            level: Some(SentryLevel::info),
            logger: None,
            culprit: None,
            transaction: None,
            server_name: None,
            release: None,
            environment: None,
            platform: None,
            message: None,
            exception: None,
            breadcrumbs: None,
            tags: None,
            extra: None,
            contexts: None,
            user: None,
            request: None,
            device: None,
            sdk: None,
            fingerprint: None,
            title: None,
            event_type: None,
            unknown_fields: serde_json::Value::Null,
        }
    }
}

/// 项目信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SentryProject {
    pub id: String,
    pub name: String,
    pub slug: Option<String>,
    pub platform: Option<String>,
    #[serde(default)]
    pub event_count: u64,
    #[serde(default)]
    pub last_event_at: Option<String>,
    #[serde(default)]
    pub created_at: String,
}

/// 日志查询过滤条件
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SentryLogFilter {
    pub project_id: Option<String>,
    pub level: Option<SentryLevel>,
    pub query: Option<String>,
    pub environment: Option<String>,
    pub start_time: Option<String>,
    pub end_time: Option<String>,
    pub offset: u64,
    pub limit: u64,
}

impl Default for SentryLogFilter {
    fn default() -> Self {
        Self {
            project_id: None,
            level: None,
            query: None,
            environment: None,
            start_time: None,
            end_time: None,
            offset: 0,
            limit: 50,
        }
    }
}

/// 日志查询结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SentryLogQueryResult {
    pub events: Vec<SentryEvent>,
    pub total: u64,
    pub offset: u64,
    pub limit: u64,
}

/// 日志统计信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SentryLogStats {
    pub total_events: u64,
    pub projects: Vec<ProjectStats>,
    pub level_counts: Vec<LevelCount>,
}

/// 项目统计
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectStats {
    pub project_id: String,
    pub project_name: String,
    pub event_count: u64,
    pub last_event_at: Option<String>,
}

/// 级别计数
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LevelCount {
    pub level: String,
    pub count: u64,
}

/// Envelope头
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnvelopeHeader {
    #[serde(default)]
    pub event_id: Option<String>,
    #[serde(default)]
    pub sent_at: Option<String>,
    #[serde(default)]
    pub sdk: Option<SentrySdkInfo>,
    #[serde(default)]
    pub dsn: Option<String>,
}

/// Envelope项头
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnvelopeItemHeader {
    #[serde(rename = "type")]
    pub item_type: String,
    #[serde(default)]
    pub length: Option<usize>,
}
