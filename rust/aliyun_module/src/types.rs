use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DdnsConfig {
    pub access_key_id: String,
    pub access_key_secret: String,
    #[serde(default)]
    pub watch_domains: Vec<WatchDomain>,
    #[serde(default = "default_interval_secs")]
    pub interval_secs: u64,
    #[serde(default)]
    pub enabled: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WatchDomain {
    pub domain_name: String,
    pub rr: String,
    #[serde(default = "default_record_type")]
    pub record_type: String,
}

fn default_record_type() -> String {
    "A".to_string()
}

fn default_interval_secs() -> u64 {
    300
}

impl Default for DdnsConfig {
    fn default() -> Self {
        Self {
            access_key_id: String::new(),
            access_key_secret: String::new(),
            watch_domains: Vec::new(),
            interval_secs: default_interval_secs(),
            enabled: false,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DomainInfo {
    #[serde(rename = "DomainName")]
    pub domain_name: String,
    #[serde(rename = "DomainId")]
    pub domain_id: String,
    #[serde(rename = "RecordCount")]
    pub record_count: i64,
    #[serde(default)]
    pub remark: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DomainRecord {
    #[serde(rename = "RecordId")]
    pub record_id: String,
    #[serde(rename = "RR")]
    pub rr: String,
    #[serde(rename = "Type")]
    pub record_type: String,
    #[serde(rename = "Value")]
    pub value: String,
    #[serde(default)]
    pub line: String,
    #[serde(default)]
    pub ttl: i64,
    #[serde(default)]
    pub status: String,
    #[serde(default)]
    pub remark: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DdnsLogEntry {
    pub timestamp: String,
    pub domain: String,
    pub rr: String,
    pub old_ip: String,
    pub new_ip: String,
    pub success: bool,
    #[serde(default)]
    pub message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DdnsStatus {
    pub enabled: bool,
    pub current_ip: String,
    pub interval_secs: u64,
    pub last_update: String,
    pub last_result: String,
    #[serde(default)]
    pub domain_statuses: Vec<DomainStatus>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DomainStatus {
    pub domain_name: String,
    pub rr: String,
    pub record_type: String,
    pub resolved_ip: String,
    pub updated: bool,
}
