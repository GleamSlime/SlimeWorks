use anyhow::Result;
use std::sync::{Arc, OnceLock};

use crate::storage::SentryLogStorage;
use crate::types::*;

static SENTRY_LOG_INSTANCE: OnceLock<Arc<SentryLogStorage>> = OnceLock::new();

fn get_instance() -> Result<&'static Arc<SentryLogStorage>, String> {
    SENTRY_LOG_INSTANCE
        .get()
        .ok_or("Sentry日志存储未初始化".to_string())
}

pub fn sentry_log_init(db_path: String) -> Result<String, String> {
    let storage =
        SentryLogStorage::new(&db_path).map_err(|e| format!("初始化Sentry日志存储失败: {}", e))?;

    let _ = SENTRY_LOG_INSTANCE.set(Arc::new(storage));

    println!("[sentry_log] 日志存储初始化完成: {}", db_path);

    Ok(format!("Sentry日志存储初始化完成: {}", db_path))
}

pub fn sentry_log_store_event(project_id: String, event: SentryEvent) -> Result<(), String> {
    let storage = get_instance()?;
    storage
        .store_event(&project_id, &event)
        .map_err(|e| format!("存储Sentry事件失败: {}", e))
}

pub fn sentry_log_store_raw_event(project_id: String, event_json: String) -> Result<(), String> {
    let mut event: SentryEvent =
        serde_json::from_str(&event_json).map_err(|e| format!("解析Sentry事件JSON失败: {}", e))?;

    if event.event_id.is_empty() {
        event.event_id = uuid::Uuid::new_v4().to_string().replace("-", "");
    }
    if event.timestamp.is_none() {
        event.timestamp = Some(chrono::Utc::now().to_rfc3339());
    }
    if event.received_at.is_none() {
        event.received_at = Some(chrono::Utc::now().to_rfc3339());
    }
    if event.level.is_none() {
        event.level = Some(SentryLevel::error);
    }

    sentry_log_store_event(project_id, event)
}

pub fn sentry_log_store_envelope(project_id: String, envelope_body: String) -> Result<(), String> {
    let lines: Vec<&str> = envelope_body.split('\n').collect();
    if lines.is_empty() {
        return Err("Envelope格式无效：内容为空".to_string());
    }

    let _header: EnvelopeHeader =
        serde_json::from_str(lines[0]).map_err(|e| format!("解析Envelope头失败: {}", e))?;

    let mut i = 1;
    while i + 1 < lines.len() {
        let item_header_line = lines[i].trim();

        if item_header_line.is_empty() {
            i += 1;
            continue;
        }

        let item_header: EnvelopeItemHeader = match serde_json::from_str(item_header_line) {
            Ok(h) => h,
            Err(_) => {
                i += 2;
                continue;
            }
        };

        let payload_length = item_header.length.unwrap_or(0);

        let payload = if payload_length > 0 {
            let mut payload_lines = Vec::new();
            let mut consumed = 0;
            let mut j = i + 1;
            while j < lines.len() {
                let line_bytes = lines[j].len();
                if consumed > 0 {
                    payload_lines.push("\n");
                }
                payload_lines.push(lines[j]);
                consumed += line_bytes + if consumed > 0 { 1 } else { 0 };
                if consumed >= payload_length {
                    break;
                }
                j += 1;
            }
            payload_lines.join("").trim().to_string()
        } else if i + 1 < lines.len() {
            lines[i + 1].trim().to_string()
        } else {
            String::new()
        };

        match item_header.item_type.as_str() {
            "event" | "transaction" => {
                if !payload.is_empty() {
                    let _ = sentry_log_store_raw_event(project_id.clone(), payload);
                }
            }
            _ => {}
        }

        if payload_length > 0 {
            let mut j = i + 1;
            let mut consumed = 0;
            while j < lines.len() {
                let line_bytes = lines[j].len();
                consumed += line_bytes + if consumed > 0 { 1 } else { 0 };
                j += 1;
                if consumed >= payload_length {
                    break;
                }
            }
            i = j;
        } else {
            i += 2;
        }
    }

    Ok(())
}

pub fn sentry_log_query(filter: SentryLogFilter) -> Result<SentryLogQueryResult, String> {
    let storage = get_instance()?;
    storage
        .query_events(&filter)
        .map_err(|e| format!("查询Sentry日志失败: {}", e))
}

pub fn sentry_log_get_event(event_id: String) -> Result<Option<SentryEvent>, String> {
    let storage = get_instance()?;
    storage
        .get_event(&event_id)
        .map_err(|e| format!("获取Sentry事件失败: {}", e))
}

pub fn sentry_log_delete_event(event_id: String) -> Result<bool, String> {
    let storage = get_instance()?;
    storage
        .delete_event(&event_id)
        .map_err(|e| format!("删除Sentry事件失败: {}", e))
}

pub fn sentry_log_delete_events(event_ids: Vec<String>) -> Result<u64, String> {
    let storage = get_instance()?;
    storage
        .delete_events(&event_ids)
        .map_err(|e| format!("批量删除Sentry事件失败: {}", e))
}

pub fn sentry_log_get_projects() -> Result<Vec<SentryProject>, String> {
    let storage = get_instance()?;
    storage
        .get_projects()
        .map_err(|e| format!("获取Sentry项目列表失败: {}", e))
}

pub fn sentry_log_update_project_name(project_id: String, name: String) -> Result<(), String> {
    let storage = get_instance()?;
    storage
        .update_project_name(&project_id, &name)
        .map_err(|e| format!("更新项目名称失败: {}", e))
}

pub fn sentry_log_get_stats() -> Result<SentryLogStats, String> {
    let storage = get_instance()?;
    storage
        .get_stats()
        .map_err(|e| format!("获取Sentry日志统计失败: {}", e))
}

pub fn sentry_log_export_json(filter: SentryLogFilter) -> Result<String, String> {
    let storage = get_instance()?;
    storage
        .export_events_json(&filter)
        .map_err(|e| format!("导出Sentry日志失败: {}", e))
}

pub fn sentry_log_clear_project_events(project_id: String) -> Result<u64, String> {
    let storage = get_instance()?;
    storage
        .clear_project_events(&project_id)
        .map_err(|e| format!("清空项目事件失败: {}", e))
}

/// 协议入口（store_raw_event / store_envelope）测试：
/// api 层持有全局 OnceLock 单例，整个测试进程只能初始化一次，
/// 因此各用例通过独立项目 ID 隔离数据，统一读取回 storage.rs 的查询接口。
#[cfg(test)]
mod api_tests {
    use super::*;
    use std::sync::Once;

    static INIT: Once = Once::new();

    /// 用临时 redb 文件初始化全局存储（只执行一次）
    fn ensure_storage() {
        INIT.call_once(|| {
            let db_path = std::env::temp_dir().join(format!(
                "sentry_log_api_test_{}.db",
                std::process::id()
            ));
            // 清掉上次运行残留，避免旧数据污染断言
            let _ = std::fs::remove_file(&db_path);
            let _ = std::fs::remove_file(format!("{}-wal", db_path.display()));
            sentry_log_init(db_path.to_string_lossy().into_owned())
                .expect("初始化测试用 Sentry 存储失败");
        });
    }

    fn unique_id(prefix: &str) -> String {
        format!("{prefix}{}", uuid::Uuid::new_v4().simple())
    }

    fn query_project(project_id: &str) -> SentryLogQueryResult {
        sentry_log_query(SentryLogFilter {
            project_id: Some(project_id.to_string()),
            ..Default::default()
        })
        .expect("查询失败")
    }

    #[test]
    fn store_raw_event_roundtrip() {
        ensure_storage();
        let project = unique_id("api-rt-");
        let event_id = unique_id("evt");
        let json = format!(
            r#"{{"event_id":"{event_id}","message":"协议入口事件","level":"warning","timestamp":"2024-05-01T00:00:00Z"}}"#
        );
        sentry_log_store_raw_event(project.clone(), json).unwrap();

        // 经 storage.rs 的查询接口读回
        let result = query_project(&project);
        assert_eq!(result.total, 1);
        assert_eq!(result.events[0].event_id, event_id);
        assert_eq!(result.events[0].message.as_deref(), Some("协议入口事件"));
        assert_eq!(result.events[0].level, Some(SentryLevel::warning));

        // 单条读取也必须命中
        let found = sentry_log_get_event(event_id.clone()).unwrap();
        assert!(found.is_some());
        assert_eq!(found.unwrap().event_id, event_id);
    }

    #[test]
    fn store_raw_event_fills_defaults() {
        ensure_storage();
        let project = unique_id("api-def-");
        // 只有 event_id 空串与 message：id/时间戳/级别都应由入口自动补齐
        let json = r#"{"event_id":"","message":"缺省填充"}"#;
        sentry_log_store_raw_event(project.clone(), json.to_string()).unwrap();

        let result = query_project(&project);
        assert_eq!(result.total, 1);
        let event = &result.events[0];
        assert!(!event.event_id.is_empty(), "空 event_id 必须补 uuid");
        assert!(event.timestamp.is_some(), "缺 timestamp 必须补当前时间");
        assert_eq!(event.level, Some(SentryLevel::error), "缺 level 默认 error");
    }

    #[test]
    fn store_raw_event_rejects_bad_json() {
        ensure_storage();
        let project = unique_id("api-bad-");
        let err = sentry_log_store_raw_event(project, "这不是JSON{{{".to_string())
            .expect_err("坏 JSON 必须报错");
        assert!(err.contains("解析Sentry事件JSON失败"), "got: {err}");
    }

    #[test]
    fn store_envelope_multi_item_roundtrip() {
        ensure_storage();
        let project = unique_id("api-env-");
        let e1 = format!(
            r#"{{"event_id":"{}","message":"Envelope事件一","level":"info"}}"#,
            unique_id("evt")
        );
        let e2 = format!(
            r#"{{"event_id":"{}","message":"Envelope事件二","level":"fatal"}}"#,
            unique_id("evt")
        );
        // 标准 Sentry envelope：header 行 + (item头 + payload) × N，
        // transaction 与 event 都必须入库
        let envelope = format!(
            "{{\"event_id\":\"env-h\"}}\n{{\"type\":\"event\",\"length\":{}}}\n{e1}\n{{\"type\":\"transaction\",\"length\":{}}}\n{e2}\n",
            e1.len(),
            e2.len()
        );
        sentry_log_store_envelope(project.clone(), envelope).unwrap();

        let result = query_project(&project);
        assert_eq!(result.total, 2, "两个 item 都应入库");
        let messages: Vec<&str> = result
            .events
            .iter()
            .map(|e| e.message.as_deref().unwrap_or(""))
            .collect();
        assert!(messages.contains(&"Envelope事件一"), "got: {messages:?}");
        assert!(messages.contains(&"Envelope事件二"), "got: {messages:?}");
    }

    #[test]
    fn store_envelope_rejects_bad_header() {
        ensure_storage();
        // 头行不是合法 JSON：必须整体报错（对应 Sentry 端点回 400）
        let err = sentry_log_store_envelope(
            unique_id("api-env-bad-"),
            "坏头!!!\n{}\npayload\n".to_string(),
        )
        .expect_err("坏 header 必须报错");
        assert!(err.contains("解析Envelope头失败"), "got: {err}");
    }

    #[test]
    fn store_envelope_empty_body_handled() {
        ensure_storage();
        // 空 body：header 行解析失败，同样走报错分支而不是 panic
        assert!(sentry_log_store_envelope(unique_id("api-env-empty-"), String::new()).is_err());
        // 只有 header、没有 item：协议上合法，应 Ok 且不入库任何事件
        let project = unique_id("api-env-hdronly-");
        sentry_log_store_envelope(project.clone(), "{\"event_id\":\"x\"}".to_string()).unwrap();
        assert_eq!(query_project(&project).total, 0);
    }

    #[test]
    fn store_envelope_skips_unparseable_item() {
        ensure_storage();
        let project = unique_id("api-env-itembad-");
        let bad_payload = "完全不是事件JSON";
        // item 头合法但 payload 是坏数据：入口吞掉单条错误（与线上行为一致），
        // 不允许把整个 envelope 请求打崩，也不允许写入半条事件
        let envelope = format!(
            "{{\"sent_at\":\"2024-01-01T00:00:00Z\"}}\n{{\"type\":\"event\",\"length\":{}}}\n{bad_payload}\n",
            bad_payload.len()
        );
        sentry_log_store_envelope(project.clone(), envelope).unwrap();
        assert_eq!(query_project(&project).total, 0);
    }
}
