use anyhow::{Context, Result};
use redb::{Database, ReadableTable, TableDefinition};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

use crate::types::*;

const EVENTS_TABLE: TableDefinition<'static, &'static str, &'static str> =
    TableDefinition::new("sentry_events");
const PROJECTS_TABLE: TableDefinition<'static, &'static str, &'static str> =
    TableDefinition::new("sentry_projects");
const PROJECT_EVENTS_TABLE: TableDefinition<'static, &'static str, &'static str> =
    TableDefinition::new("sentry_project_events");

pub struct SentryLogStorage {
    db: Database,
    db_path: PathBuf,
}

impl SentryLogStorage {
    pub fn new<P: AsRef<Path>>(db_path: P) -> Result<Self> {
        let db_path = db_path.as_ref().to_path_buf();
        if let Some(parent) = db_path.parent() {
            std::fs::create_dir_all(parent).context("创建sentry_log数据库目录失败")?;
        }

        let db = Database::create(&db_path).context("创建sentry_log数据库失败")?;

        {
            let write_txn = db.begin_write()?;
            write_txn.open_table(EVENTS_TABLE)?;
            write_txn.open_table(PROJECTS_TABLE)?;
            write_txn.open_table(PROJECT_EVENTS_TABLE)?;
            write_txn.commit()?;
        }

        Ok(Self { db, db_path })
    }

    pub fn store_event(&self, project_id: &str, event: &SentryEvent) -> Result<()> {
        let write_txn = self.db.begin_write()?;

        {
            let mut events_table = write_txn.open_table(EVENTS_TABLE)?;
            let event_json = serde_json::to_string(event).context("序列化Sentry事件失败")?;
            events_table.insert(event.event_id.as_str(), event_json.as_str())?;

            let mut pe_table = write_txn.open_table(PROJECT_EVENTS_TABLE)?;
            let pe_key = format!("{}:{}", project_id, event.event_id);
            let timestamp = event.timestamp.as_deref().unwrap_or("");
            pe_table.insert(pe_key.as_str(), timestamp)?;
        }

        write_txn.commit()?;

        self.update_project_stats(project_id, event)?;

        Ok(())
    }

    fn update_project_stats(&self, project_id: &str, event: &SentryEvent) -> Result<()> {
        let write_txn = self.db.begin_write()?;

        {
            let mut proj_table = write_txn.open_table(PROJECTS_TABLE)?;
            let project = {
                let existing = proj_table.get(project_id)?;
                match existing {
                    Some(val) => serde_json::from_str(val.value())
                        .unwrap_or_else(|_| self.create_default_project(project_id)),
                    None => self.create_default_project(project_id),
                }
            };

            let mut project = project;
            project.event_count += 1;
            project.last_event_at = event.timestamp.clone();

            if event.platform.is_some() && project.platform.is_none() {
                project.platform = event.platform.clone();
            }

            let proj_json = serde_json::to_string(&project).context("序列化项目信息失败")?;
            proj_table.insert(project_id, proj_json.as_str())?;
        }

        write_txn.commit()?;
        Ok(())
    }

    fn create_default_project(&self, project_id: &str) -> SentryProject {
        SentryProject {
            id: project_id.to_string(),
            name: format!("项目 {}", project_id),
            slug: None,
            platform: None,
            event_count: 0,
            last_event_at: None,
            created_at: chrono::Utc::now().to_rfc3339(),
        }
    }

    pub fn update_project_name(&self, project_id: &str, name: &str) -> Result<()> {
        let write_txn = self.db.begin_write()?;

        {
            let mut proj_table = write_txn.open_table(PROJECTS_TABLE)?;
            let project = {
                let existing = proj_table.get(project_id)?;
                match existing {
                    Some(val) => serde_json::from_str(val.value())
                        .unwrap_or_else(|_| self.create_default_project(project_id)),
                    None => self.create_default_project(project_id),
                }
            };

            let mut project = project;
            project.name = name.to_string();
            let proj_json = serde_json::to_string(&project)?;
            proj_table.insert(project_id, proj_json.as_str())?;
        }

        write_txn.commit()?;
        Ok(())
    }

    pub fn query_events(&self, filter: &SentryLogFilter) -> Result<SentryLogQueryResult> {
        let read_txn = self.db.begin_read()?;

        let events_table = read_txn.open_table(EVENTS_TABLE)?;
        let pe_table = read_txn.open_table(PROJECT_EVENTS_TABLE)?;

        let mut all_events: Vec<SentryEvent> = Vec::new();

        if let Some(ref project_id) = filter.project_id {
            let prefix = format!("{}:", project_id);
            for item in pe_table.iter()? {
                let (key, timestamp) = item?;
                let key_str = key.value();
                if key_str.starts_with(&prefix) {
                    let event_id = &key_str[prefix.len()..];
                    if let Some(event_val) = events_table.get(event_id)? {
                        if let Ok(event) = serde_json::from_str::<SentryEvent>(event_val.value()) {
                            all_events.push(event);
                        }
                    }
                }
            }
        } else {
            for item in events_table.iter()? {
                let (_, value) = item?;
                if let Ok(event) = serde_json::from_str::<SentryEvent>(value.value()) {
                    all_events.push(event);
                }
            }
        }

        if let Some(ref level) = filter.level {
            all_events.retain(|e| e.level.as_ref() == Some(level));
        }

        if let Some(ref env) = filter.environment {
            all_events.retain(|e| e.environment.as_ref() == Some(env));
        }

        if let Some(ref start) = filter.start_time {
            all_events.retain(|e| e.timestamp.as_ref().map_or(true, |t| t >= start));
        }
        if let Some(ref end) = filter.end_time {
            all_events.retain(|e| e.timestamp.as_ref().map_or(true, |t| t <= end));
        }

        if let Some(ref query) = filter.query {
            let q = query.to_lowercase();
            all_events.retain(|e| {
                let searchable = format!(
                    "{} {} {} {} {}",
                    e.message.as_deref().unwrap_or(""),
                    e.culprit.as_deref().unwrap_or(""),
                    e.transaction.as_deref().unwrap_or(""),
                    e.logger.as_deref().unwrap_or(""),
                    e.event_id
                )
                .to_lowercase();
                searchable.contains(&q)
                    || e.exception.as_ref().map_or(false, |ex| {
                        ex.values.iter().any(|v| {
                            let s = format!(
                                "{} {}",
                                v.exc_type.as_deref().unwrap_or(""),
                                v.value.as_deref().unwrap_or("")
                            )
                            .to_lowercase();
                            s.contains(&q)
                        })
                    })
            });
        }

        let total = all_events.len() as u64;

        all_events.sort_by(|a, b| {
            let ta = a.timestamp.as_deref().unwrap_or("");
            let tb = b.timestamp.as_deref().unwrap_or("");
            tb.cmp(ta)
        });

        let offset = filter.offset as usize;
        let limit = filter.limit as usize;
        let events: Vec<SentryEvent> = all_events.into_iter().skip(offset).take(limit).collect();

        Ok(SentryLogQueryResult {
            events,
            total,
            offset: filter.offset,
            limit: filter.limit,
        })
    }

    pub fn get_event(&self, event_id: &str) -> Result<Option<SentryEvent>> {
        let read_txn = self.db.begin_read()?;
        let table = read_txn.open_table(EVENTS_TABLE)?;

        if let Some(value) = table.get(event_id)? {
            let event: SentryEvent =
                serde_json::from_str(value.value()).context("反序列化Sentry事件失败")?;
            Ok(Some(event))
        } else {
            Ok(None)
        }
    }

    pub fn delete_event(&self, event_id: &str) -> Result<bool> {
        let write_txn = self.db.begin_write()?;

        let existed = {
            let mut events_table = write_txn.open_table(EVENTS_TABLE)?;
            let existed = events_table.get(event_id)?.is_some();
            if existed {
                events_table.remove(event_id)?;
            }
            existed
        };

        if existed {
            let mut pe_table = write_txn.open_table(PROJECT_EVENTS_TABLE)?;
            let prefix = ":";
            let keys_to_remove: Vec<String> = pe_table
                .iter()?
                .filter_map(|item| {
                    if let Ok((key, _)) = item {
                        let key_str = key.value().to_string();
                        if key_str.ends_with(&format!("{}{}", prefix, event_id)) {
                            Some(key_str)
                        } else {
                            None
                        }
                    } else {
                        None
                    }
                })
                .collect();

            for key in keys_to_remove {
                pe_table.remove(key.as_str())?;
            }
        }

        write_txn.commit()?;
        Ok(existed)
    }

    pub fn delete_events(&self, event_ids: &[String]) -> Result<u64> {
        let mut deleted = 0u64;
        for id in event_ids {
            if self.delete_event(id)? {
                deleted += 1;
            }
        }
        Ok(deleted)
    }

    pub fn get_projects(&self) -> Result<Vec<SentryProject>> {
        let read_txn = self.db.begin_read()?;
        let table = read_txn.open_table(PROJECTS_TABLE)?;

        let mut projects: Vec<SentryProject> = Vec::new();
        for item in table.iter()? {
            let (_, value) = item?;
            if let Ok(project) = serde_json::from_str::<SentryProject>(value.value()) {
                projects.push(project);
            }
        }

        projects.sort_by(|a, b| b.event_count.cmp(&a.event_count));
        Ok(projects)
    }

    pub fn get_stats(&self) -> Result<SentryLogStats> {
        let read_txn = self.db.begin_read()?;

        let events_table = read_txn.open_table(EVENTS_TABLE)?;
        let proj_table = read_txn.open_table(PROJECTS_TABLE)?;

        let mut total_events: u64 = 0;
        let mut level_map: HashMap<String, u64> = HashMap::new();

        for item in events_table.iter()? {
            let (_, value) = item?;
            if let Ok(event) = serde_json::from_str::<SentryEvent>(value.value()) {
                total_events += 1;
                let level = event
                    .level
                    .as_ref()
                    .map(|l| l.as_str().to_string())
                    .unwrap_or_else(|| "info".to_string());
                *level_map.entry(level).or_insert(0) += 1;
            }
        }

        let mut projects: Vec<ProjectStats> = Vec::new();
        for item in proj_table.iter()? {
            let (_, value) = item?;
            if let Ok(project) = serde_json::from_str::<SentryProject>(value.value()) {
                projects.push(ProjectStats {
                    project_id: project.id.clone(),
                    project_name: project.name.clone(),
                    event_count: project.event_count,
                    last_event_at: project.last_event_at.clone(),
                });
            }
        }

        let level_counts: Vec<LevelCount> = level_map
            .into_iter()
            .map(|(level, count)| LevelCount { level, count })
            .collect();

        Ok(SentryLogStats {
            total_events,
            projects,
            level_counts,
        })
    }

    pub fn export_events_json(&self, filter: &SentryLogFilter) -> Result<String> {
        let result = self.query_events(filter)?;
        serde_json::to_string_pretty(&result.events).context("导出事件JSON失败")
    }

    pub fn clear_project_events(&self, project_id: &str) -> Result<u64> {
        let event_ids: Vec<String> = {
            let read_txn = self.db.begin_read()?;
            let pe_table = read_txn.open_table(PROJECT_EVENTS_TABLE)?;
            let prefix = format!("{}:", project_id);
            pe_table
                .iter()?
                .filter_map(|item| {
                    if let Ok((key, _)) = item {
                        let key_str = key.value().to_string();
                        if key_str.starts_with(&prefix) {
                            Some(key_str[prefix.len()..].to_string())
                        } else {
                            None
                        }
                    } else {
                        None
                    }
                })
                .collect()
        };

        let count = event_ids.len() as u64;

        let write_txn = self.db.begin_write()?;
        {
            let mut events_table = write_txn.open_table(EVENTS_TABLE)?;
            let mut pe_table = write_txn.open_table(PROJECT_EVENTS_TABLE)?;
            for id in &event_ids {
                events_table.remove(id.as_str())?;
            }
            let prefix = format!("{}:", project_id);
            for id in &event_ids {
                let pe_key = format!("{}{}", prefix, id);
                pe_table.remove(pe_key.as_str())?;
            }
        }
        write_txn.commit()?;

        Ok(count)
    }

    pub fn db_path(&self) -> &Path {
        &self.db_path
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_store_and_query_event() {
        let temp_dir = std::env::temp_dir().join("sentry_log_test");
        let db_path = temp_dir.join("test.db");

        let storage = SentryLogStorage::new(&db_path).unwrap();

        let event = SentryEvent {
            event_id: "test123".to_string(),
            message: Some("测试事件".to_string()),
            level: Some(SentryLevel::error),
            timestamp: Some("2024-01-01T00:00:00Z".to_string()),
            ..Default::default()
        };

        storage.store_event("1", &event).unwrap();

        let filter = SentryLogFilter {
            project_id: Some("1".to_string()),
            ..Default::default()
        };
        let result = storage.query_events(&filter).unwrap();
        assert_eq!(result.total, 1);
        assert_eq!(result.events[0].event_id, "test123");

        std::fs::remove_dir_all(temp_dir).ok();
    }
}
