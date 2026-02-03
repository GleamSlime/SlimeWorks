use serde::{Deserialize, Serialize};

/// 数据库操作结果
pub type DbResult<T> = Result<T, String>;

/// 数据库记录
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DbRecord {
    pub key: String,
    pub value: String,
}

/// 批量操作请求
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BatchOperation {
    pub operations: Vec<Operation>,
}

/// 单个操作
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum Operation {
    Set { key: String, value: String },
    Delete { key: String },
}
