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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn db_record_serde_round_trip() {
        let record = DbRecord {
            key: "user:001".to_string(),
            value: r#"{"name":"test"}"#.to_string(),
        };
        let json = serde_json::to_string(&record).expect("serialize");
        let restored: DbRecord = serde_json::from_str(&json).expect("deserialize");
        assert_eq!(restored.key, record.key);
        assert_eq!(restored.value, record.value);
    }

    #[test]
    fn operation_set_serde_round_trip() {
        let op = Operation::Set {
            key: "k1".to_string(),
            value: "v1".to_string(),
        };
        let json = serde_json::to_string(&op).expect("serialize");
        let restored: Operation = serde_json::from_str(&json).expect("deserialize");
        if let Operation::Set { key, value } = restored {
            assert_eq!(key, "k1");
            assert_eq!(value, "v1");
        } else {
            panic!("Expected Operation::Set");
        }
    }

    #[test]
    fn operation_delete_serde_round_trip() {
        let op = Operation::Delete {
            key: "k2".to_string(),
        };
        let json = serde_json::to_string(&op).expect("serialize");
        let restored: Operation = serde_json::from_str(&json).expect("deserialize");
        if let Operation::Delete { key } = restored {
            assert_eq!(key, "k2");
        } else {
            panic!("Expected Operation::Delete");
        }
    }

    #[test]
    fn batch_operation_serde_round_trip() {
        let batch = BatchOperation {
            operations: vec![
                Operation::Set {
                    key: "a".to_string(),
                    value: "1".to_string(),
                },
                Operation::Delete {
                    key: "b".to_string(),
                },
            ],
        };
        let json = serde_json::to_string(&batch).expect("serialize");
        let restored: BatchOperation = serde_json::from_str(&json).expect("deserialize");
        assert_eq!(restored.operations.len(), 2);
    }
}
