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
