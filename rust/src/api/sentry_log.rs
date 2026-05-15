use flutter_rust_bridge::frb;

/// 初始化Sentry日志存储
#[frb(sync)]
pub fn sentry_log_init(db_path: String) -> Result<String, String> {
    sentry_log::api::sentry_log_init(db_path)
}

/// 查询Sentry日志事件
pub fn sentry_log_query(
    project_id: Option<String>,
    level: Option<String>,
    query: Option<String>,
    environment: Option<String>,
    start_time: Option<String>,
    end_time: Option<String>,
    offset: u64,
    limit: u64,
) -> Result<String, String> {
    let filter = sentry_log::types::SentryLogFilter {
        project_id,
        level: level.map(|l| sentry_log::types::SentryLevel::from_str(&l)),
        query,
        environment,
        start_time,
        end_time,
        offset,
        limit,
    };

    let result = sentry_log::api::sentry_log_query(filter)?;
    serde_json::to_string(&result).map_err(|e| format!("序列化查询结果失败: {}", e))
}

/// 获取单个Sentry事件
pub fn sentry_log_get_event(event_id: String) -> Result<String, String> {
    let result = sentry_log::api::sentry_log_get_event(event_id)?;
    match result {
        Some(event) => serde_json::to_string(&event).map_err(|e| format!("序列化事件失败: {}", e)),
        None => Err("事件不存在".to_string()),
    }
}

/// 删除Sentry事件
pub fn sentry_log_delete_event(event_id: String) -> Result<bool, String> {
    sentry_log::api::sentry_log_delete_event(event_id)
}

/// 批量删除Sentry事件
pub fn sentry_log_delete_events(event_ids: Vec<String>) -> Result<u64, String> {
    sentry_log::api::sentry_log_delete_events(event_ids)
}

/// 获取Sentry项目列表
pub fn sentry_log_get_projects() -> Result<String, String> {
    let projects = sentry_log::api::sentry_log_get_projects()?;
    serde_json::to_string(&projects).map_err(|e| format!("序列化项目列表失败: {}", e))
}

/// 更新Sentry项目名称
pub fn sentry_log_update_project_name(project_id: String, name: String) -> Result<(), String> {
    sentry_log::api::sentry_log_update_project_name(project_id, name)
}

/// 获取Sentry日志统计
pub fn sentry_log_get_stats() -> Result<String, String> {
    let stats = sentry_log::api::sentry_log_get_stats()?;
    serde_json::to_string(&stats).map_err(|e| format!("序列化统计信息失败: {}", e))
}

/// 导出Sentry日志为JSON
pub fn sentry_log_export_json(
    project_id: Option<String>,
    level: Option<String>,
    query: Option<String>,
    environment: Option<String>,
    start_time: Option<String>,
    end_time: Option<String>,
) -> Result<String, String> {
    let filter = sentry_log::types::SentryLogFilter {
        project_id,
        level: level.map(|l| sentry_log::types::SentryLevel::from_str(&l)),
        query,
        environment,
        start_time,
        end_time,
        offset: 0,
        limit: 10000,
    };

    sentry_log::api::sentry_log_export_json(filter)
}

/// 清空项目事件
pub fn sentry_log_clear_project_events(project_id: String) -> Result<u64, String> {
    sentry_log::api::sentry_log_clear_project_events(project_id)
}
