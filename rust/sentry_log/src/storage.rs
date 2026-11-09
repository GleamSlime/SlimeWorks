use anyhow::{Context, Result};
use redb::{Database, ReadableTable, TableDefinition};
use std::collections::HashMap;
use std::ops::Bound;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicI64, Ordering};
use std::sync::{Arc, Mutex};

use crate::types::*;

const EVENTS_TABLE: TableDefinition<'static, &'static str, &'static str> =
    TableDefinition::new("sentry_events");
const PROJECTS_TABLE: TableDefinition<'static, &'static str, &'static str> =
    TableDefinition::new("sentry_projects");
const PROJECT_EVENTS_TABLE: TableDefinition<'static, &'static str, &'static str> =
    TableDefinition::new("sentry_project_events");

// ==== 真分页二级索引（性能审计 #2）====
// 全局时间索引：key = `{timestamp}\0{event_id}`，字典序即时间序；
// 查询用 redb range().rev() 从最新往回走，只反序列化命中的那一页。
const TIME_INDEX_TABLE: TableDefinition<'static, &'static str, &'static str> =
    TableDefinition::new("sentry_time_index");
// 项目复合时间索引：key = `{project_id}\0{timestamp}\0{event_id}`，
// 项目过滤 = 前缀 range，同样免全表。
const PROJECT_TIME_INDEX_TABLE: TableDefinition<'static, &'static str, &'static str> =
    TableDefinition::new("sentry_project_time_index");
// 事件元数据小表：event_id → {level, environment, project_id, timestamp}。
// level/env 过滤只读这条几十字节的小值，不碰可能数十 KB 的事件大 JSON；
// 同时让删除路径 O(1) 定位索引行，替代原先对 project_events 的全表扫描。
const EVENT_META_TABLE: TableDefinition<'static, &'static str, &'static str> =
    TableDefinition::new("sentry_event_meta");
// 增量聚合小表：key = "total" / "level:{level}" → 计数字符串。
// store/delete/clear/清理时同步增减，get_stats 不再全表反序列化。
const STATS_TABLE: TableDefinition<'static, &'static str, &'static str> =
    TableDefinition::new("sentry_stats");
// 元信息表：存放索引回填完成的幂等标记。
const META_TABLE: TableDefinition<'static, &'static str, &'static str> =
    TableDefinition::new("sentry_meta");
/// 索引/聚合已就绪的幂等标记（存量库懒回填一次后写入，与回填同事务落盘）
const INDEX_READY_KEY: &str = "index_v1_ready";
/// 复合索引键分隔符：NUL 不会出现在合法 timestamp/project_id/event_id 中，
/// 且小于一切可见字符，保证「前缀 + 分隔符」的字典序与时间序一致。
const KEY_SEP: char = '\0';

/// 保留策略：默认保留 90 天（可配置常量）
const RETENTION_DAYS: i64 = 90;
/// 保留策略：条数上限 5 万条（超出从最旧开始删）
const MAX_EVENTS: u64 = 50_000;
/// 写入路径触发后台清理的最小间隔（秒）：限频，避免日志风暴时每条都起线程
const CLEANUP_INTERVAL_SECS: i64 = 3600;

/// 字符串 KV 表句柄别名（本模块所有表都是 str→str）
type StrTable<'t> = redb::Table<'t, &'static str, &'static str>;

/// 事件索引元数据：只存过滤/删除所需的小字段，绝不存事件正文
#[derive(serde::Serialize, serde::Deserialize)]
struct EventMeta {
    /// 事件级别字符串；None 保持 None（过滤口径与旧版一致），聚合计数按 "info"
    level: Option<String>,
    environment: Option<String>,
    project_id: String,
    /// 入库时的时间戳（缺省空串），删除时用于 O(1) 还原时间索引键
    timestamp: String,
}

/// 全局时间索引键：`{timestamp}\0{event_id}`
fn time_index_key(timestamp: &str, event_id: &str) -> String {
    format!("{timestamp}{KEY_SEP}{event_id}")
}

/// 项目复合时间索引键：`{project_id}\0{timestamp}\0{event_id}`
fn project_time_index_key(project_id: &str, timestamp: &str, event_id: &str) -> String {
    format!("{project_id}{KEY_SEP}{timestamp}{KEY_SEP}{event_id}")
}

/// 聚合小表的级别计数键；级别缺省按 "info" 计（与旧 get_stats 口径一致）
fn level_stats_key(level: Option<&str>) -> String {
    format!("level:{}", level.unwrap_or("info"))
}

/// 聚合小表计数增减（delta 可为负）；饱和运算保证计数永不下溢
fn stats_bump(stats: &mut StrTable<'_>, key: &str, delta: i64) -> Result<()> {
    let cur = stats
        .get(key)?
        .map(|v| v.value().parse::<u64>().unwrap_or(0))
        .unwrap_or(0);
    let next = if delta >= 0 {
        cur.saturating_add(delta as u64)
    } else {
        cur.saturating_sub(delta.unsigned_abs())
    };
    let next_str = next.to_string();
    stats.insert(key, next_str.as_str())?;
    Ok(())
}

/// 从各表清除一个事件的全部行（事件正文 + 两级时间索引 + 项目索引 + 元数据），
/// 并回退聚合计数。返回事件正文是否存在。
/// 元数据缺失 = 回填时 JSON 损坏被跳过的事件（未建索引、未计数），只删正文即可。
#[allow(clippy::too_many_arguments)]
fn purge_event_rows(
    events: &mut StrTable<'_>,
    time_idx: &mut StrTable<'_>,
    proj_idx: &mut StrTable<'_>,
    pe: &mut StrTable<'_>,
    metas: &mut StrTable<'_>,
    stats: &mut StrTable<'_>,
    event_id: &str,
) -> Result<bool> {
    let existed = events.remove(event_id)?.is_some();
    let meta: Option<EventMeta> = metas
        .remove(event_id)?
        .and_then(|v| serde_json::from_str(v.value()).ok());
    if let Some(m) = meta {
        time_idx.remove(time_index_key(&m.timestamp, event_id).as_str())?;
        if !m.project_id.is_empty() {
            proj_idx.remove(
                project_time_index_key(&m.project_id, &m.timestamp, event_id).as_str(),
            )?;
            let pe_key = format!("{}:{}", m.project_id, event_id);
            pe.remove(pe_key.as_str())?;
        }
        stats_bump(stats, "total", -1)?;
        stats_bump(stats, &level_stats_key(m.level.as_deref()), -1)?;
    }
    Ok(existed)
}

/// 关键词匹配：与旧版 query_events 的 retain 逻辑逐字一致
/// （message/culprit/transaction/logger/event_id + 异常 type/value，小写包含）
fn event_matches_query(e: &SentryEvent, q: &str) -> bool {
    let searchable = format!(
        "{} {} {} {} {}",
        e.message.as_deref().unwrap_or(""),
        e.culprit.as_deref().unwrap_or(""),
        e.transaction.as_deref().unwrap_or(""),
        e.logger.as_deref().unwrap_or(""),
        e.event_id
    )
    .to_lowercase();
    searchable.contains(q)
        || e.exception.as_ref().is_some_and(|ex| {
            ex.values.iter().any(|v| {
                let s = format!(
                    "{} {}",
                    v.exc_type.as_deref().unwrap_or(""),
                    v.value.as_deref().unwrap_or("")
                )
                .to_lowercase();
                s.contains(q)
            })
        })
}

/// 保留期清理（独立函数，供同步调用与后台线程共用）：
/// ① 删除时间戳早于 now - retention_days 的事件；② 总数超过 max_events 时
/// 从最旧开始删到上限。两者取并集（都作用于时间索引的最旧前缀），单事务完成，
/// 同步回退聚合小表。返回删除条数。
fn retention_cleanup_tx(db: &Database, retention_days: i64, max_events: u64) -> Result<u64> {
    let cutoff = (chrono::Utc::now() - chrono::Duration::days(retention_days)).to_rfc3339();
    // 第一趟读：算出要删的最旧前缀长度（按年龄的条数 与 超上限的条数 取大者）
    let remove_count = {
        let read_txn = db.begin_read()?;
        let time_idx = read_txn.open_table(TIME_INDEX_TABLE)?;
        let stats = read_txn.open_table(STATS_TABLE)?;
        let total: u64 = stats
            .get("total")?
            .map(|v| v.value().parse().unwrap_or(0))
            .unwrap_or(0);
        let cutoff_key = format!("{cutoff}{KEY_SEP}");
        let mut by_age = 0u64;
        let cutoff_bounds: (Bound<&str>, Bound<&str>) =
            (Bound::Unbounded, Bound::Excluded(cutoff_key.as_str()));
        for item in time_idx.range::<&str>(cutoff_bounds)? {
            let _ = item?;
            by_age += 1;
        }
        by_age.max(total.saturating_sub(max_events))
    };
    if remove_count == 0 {
        return Ok(0);
    }
    // 第二趟读：时间索引升序即最旧优先，取前 remove_count 个 event_id
    let victims: Vec<String> = {
        let read_txn = db.begin_read()?;
        let time_idx = read_txn.open_table(TIME_INDEX_TABLE)?;
        let mut ids = Vec::with_capacity(remove_count as usize);
        for item in time_idx.iter()?.take(remove_count as usize) {
            let (key, _) = item?;
            if let Some(id) = key.value().rsplit(KEY_SEP).next() {
                ids.push(id.to_string());
            }
        }
        ids
    };
    let write_txn = db.begin_write()?;
    {
        let mut events = write_txn.open_table(EVENTS_TABLE)?;
        let mut time_idx = write_txn.open_table(TIME_INDEX_TABLE)?;
        let mut proj_idx = write_txn.open_table(PROJECT_TIME_INDEX_TABLE)?;
        let mut pe = write_txn.open_table(PROJECT_EVENTS_TABLE)?;
        let mut metas = write_txn.open_table(EVENT_META_TABLE)?;
        let mut stats = write_txn.open_table(STATS_TABLE)?;
        for id in &victims {
            purge_event_rows(
                &mut events, &mut time_idx, &mut proj_idx, &mut pe, &mut metas, &mut stats, id,
            )?;
        }
    }
    write_txn.commit()?;
    Ok(victims.len() as u64)
}

pub struct SentryLogStorage {
    // Arc 包装：后台保留期清理线程需要共享同一个 Database 句柄
    // （redb 对同一文件只允许一个打开实例，不能在线程里重新 open）
    db: Arc<Database>,
    db_path: PathBuf,
    /// 二级索引/聚合是否已就绪（进程内快路径，落盘幂等标记在 META_TABLE）
    index_ready: AtomicBool,
    /// 回填互斥：并发首次访问只回填一次
    backfill_lock: Mutex<()>,
    /// 后台清理是否正在运行（防重入；Arc 供线程结束时复位）
    cleanup_running: Arc<AtomicBool>,
    /// 上次触发清理检查的 unix 秒（限频闸门；初始化为建库时刻，避免首条写入就起线程）
    last_cleanup_ts: AtomicI64,
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
            // 索引/聚合/元信息表一并物理建好，后续读路径不会遇到 "does not exist"
            write_txn.open_table(TIME_INDEX_TABLE)?;
            write_txn.open_table(PROJECT_TIME_INDEX_TABLE)?;
            write_txn.open_table(EVENT_META_TABLE)?;
            write_txn.open_table(STATS_TABLE)?;
            write_txn.open_table(META_TABLE)?;
            write_txn.commit()?;
        }

        Ok(Self {
            db: Arc::new(db),
            db_path,
            index_ready: AtomicBool::new(false),
            backfill_lock: Mutex::new(()),
            cleanup_running: Arc::new(AtomicBool::new(false)),
            last_cleanup_ts: AtomicI64::new(chrono::Utc::now().timestamp()),
        })
    }

    /// 确保二级索引/聚合已就绪：进程内原子快路径 → 互斥锁 → 落盘幂等标记。
    /// 存量旧库（只有 events/projects/project_events 三表数据）在首次访问时
    /// 懒回填一次，回填与标记同事务提交，中途崩溃重启会整体重做，不会半份索引。
    fn ensure_index_ready(&self) -> Result<()> {
        if self.index_ready.load(Ordering::Acquire) {
            return Ok(());
        }
        let _guard = self.backfill_lock.lock().unwrap_or_else(|e| e.into_inner());
        if self.index_ready.load(Ordering::Acquire) {
            return Ok(());
        }
        let marker_exists = {
            let read_txn = self.db.begin_read()?;
            let meta = read_txn.open_table(META_TABLE)?;
            meta.get(INDEX_READY_KEY)?.is_some()
        };
        if !marker_exists {
            self.backfill_index()?;
        }
        self.index_ready.store(true, Ordering::Release);
        Ok(())
    }

    /// 存量库一次性回填：遍历事件表重建两级时间索引、元数据小表与聚合计数。
    /// 这是唯一允许全表反序列化的路径（每库只付一次）。
    fn backfill_index(&self) -> Result<()> {
        let write_txn = self.db.begin_write()?;
        let mut count = 0u64;
        {
            let events = write_txn.open_table(EVENTS_TABLE)?;
            let pe = write_txn.open_table(PROJECT_EVENTS_TABLE)?;
            let mut time_idx = write_txn.open_table(TIME_INDEX_TABLE)?;
            let mut proj_idx = write_txn.open_table(PROJECT_TIME_INDEX_TABLE)?;
            let mut metas = write_txn.open_table(EVENT_META_TABLE)?;
            let mut stats = write_txn.open_table(STATS_TABLE)?;
            let mut meta_tbl = write_txn.open_table(META_TABLE)?;

            // pe_key 形如 `{project_id}:{event_id}`，event_id 本身不含 ':'，
            // 故取最后一段即可还原 event_id 用于集合比对。
            let mut project_of: HashMap<String, String> = HashMap::new();
            for item in pe.iter()? {
                let (key, _) = item?;
                if let Some((project, id)) = key.value().rsplit_once(':') {
                    project_of.insert(id.to_string(), project.to_string());
                }
            }

            for item in events.iter()? {
                let (key, value) = item?;
                // 与旧查询口径一致：JSON 损坏的事件跳过（不建索引、不计数）
                let Ok(event) = serde_json::from_str::<SentryEvent>(value.value()) else {
                    continue;
                };
                let id = key.value();
                let ts = event.timestamp.as_deref().unwrap_or("");
                let project = project_of.get(id).cloned().unwrap_or_default();
                time_idx.insert(time_index_key(ts, id).as_str(), ts)?;
                if !project.is_empty() {
                    proj_idx.insert(project_time_index_key(&project, ts, id).as_str(), ts)?;
                }
                let m = EventMeta {
                    level: event.level.as_ref().map(|l| l.as_str().to_string()),
                    environment: event.environment.clone(),
                    project_id: project,
                    timestamp: ts.to_string(),
                };
                let m_json = serde_json::to_string(&m).context("序列化事件元数据失败")?;
                metas.insert(id, m_json.as_str())?;
                stats_bump(&mut stats, "total", 1)?;
                stats_bump(&mut stats, &level_stats_key(m.level.as_deref()), 1)?;
                count += 1;
            }
            // 幂等标记与回填数据同事务：要么都看见，要么都没看见
            meta_tbl.insert(INDEX_READY_KEY, "1")?;
        }
        write_txn.commit()?;
        slime_logger::sw_info!("[sentry_log] 存量库索引回填完成，共 {} 条事件", count);
        Ok(())
    }

    pub fn store_event(&self, project_id: &str, event: &SentryEvent) -> Result<()> {
        // 旧库首次写入前先懒回填，保证增量计数从正确基线出发
        self.ensure_index_ready()?;
        // 事件、项目索引、项目统计合入同一事务：原先拆成两次 commit，
        // 每条日志要付两趟磁盘刷写，日志风暴时写入吞吐直接减半。
        // 二级时间索引/元数据/聚合小表 likewise 并入本事务，只多几条小 KV，不增加 commit 次数。
        let write_txn = self.db.begin_write()?;

        {
            let mut events_table = write_txn.open_table(EVENTS_TABLE)?;
            let mut pe_table = write_txn.open_table(PROJECT_EVENTS_TABLE)?;
            let mut time_idx = write_txn.open_table(TIME_INDEX_TABLE)?;
            let mut proj_idx = write_txn.open_table(PROJECT_TIME_INDEX_TABLE)?;
            let mut metas = write_txn.open_table(EVENT_META_TABLE)?;
            let mut stats = write_txn.open_table(STATS_TABLE)?;

            // 同 event_id 重复上报按「替换」处理：先清旧索引行并回退聚合，
            // 避免 total/level 计数随重传虚增（旧版事件正文本就是覆盖写）
            purge_event_rows(
                &mut events_table,
                &mut time_idx,
                &mut proj_idx,
                &mut pe_table,
                &mut metas,
                &mut stats,
                &event.event_id,
            )?;

            let event_json = serde_json::to_string(event).context("序列化Sentry事件失败")?;
            events_table.insert(event.event_id.as_str(), event_json.as_str())?;

            let pe_key = format!("{}:{}", project_id, event.event_id);
            let timestamp = event.timestamp.as_deref().unwrap_or("");
            pe_table.insert(pe_key.as_str(), timestamp)?;

            // 两级时间索引 + 元数据小表 + 增量聚合
            time_idx.insert(time_index_key(timestamp, &event.event_id).as_str(), timestamp)?;
            proj_idx.insert(
                project_time_index_key(project_id, timestamp, &event.event_id).as_str(),
                timestamp,
            )?;
            let m = EventMeta {
                level: event.level.as_ref().map(|l| l.as_str().to_string()),
                environment: event.environment.clone(),
                project_id: project_id.to_string(),
                timestamp: timestamp.to_string(),
            };
            let m_json = serde_json::to_string(&m).context("序列化事件元数据失败")?;
            metas.insert(event.event_id.as_str(), m_json.as_str())?;
            stats_bump(&mut stats, "total", 1)?;
            stats_bump(&mut stats, &level_stats_key(m.level.as_deref()), 1)?;

            let mut proj_table = write_txn.open_table(PROJECTS_TABLE)?;
            let mut project = match proj_table.get(project_id)? {
                Some(val) => serde_json::from_str(val.value())
                    .unwrap_or_else(|_| self.create_default_project(project_id)),
                None => self.create_default_project(project_id),
            };
            project.event_count += 1;
            project.last_event_at = event.timestamp.clone();
            if event.platform.is_some() && project.platform.is_none() {
                project.platform = event.platform.clone();
            }
            let proj_json = serde_json::to_string(&project).context("序列化项目信息失败")?;
            proj_table.insert(project_id, proj_json.as_str())?;
        }

        write_txn.commit()?;

        // 写入路径限频触发后台保留期清理（不阻塞本条写入）
        self.maybe_spawn_cleanup();

        Ok(())
    }

    /// 限频 + 防重入地把保留期清理丢到后台线程。
    /// 闸门：距上次检查不足 CLEANUP_INTERVAL_SECS 直接返回；
    /// compare_exchange 抢占失败（并发写入/已有清理在跑）也直接返回。
    fn maybe_spawn_cleanup(&self) {
        let now = chrono::Utc::now().timestamp();
        let last = self.last_cleanup_ts.load(Ordering::Relaxed);
        if now.saturating_sub(last) < CLEANUP_INTERVAL_SECS {
            return;
        }
        if self
            .last_cleanup_ts
            .compare_exchange(last, now, Ordering::Relaxed, Ordering::Relaxed)
            .is_err()
        {
            return;
        }
        if self
            .cleanup_running
            .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
            .is_err()
        {
            return;
        }
        let db = Arc::clone(&self.db);
        let running = Arc::clone(&self.cleanup_running);
        let spawned = std::thread::Builder::new()
            .name("sentry-log-retention".to_string())
            .spawn(move || {
                // 走到这里索引必然已就绪（store_event 先 ensure 后 commit）
                match retention_cleanup_tx(&db, RETENTION_DAYS, MAX_EVENTS) {
                    Ok(n) if n > 0 => {
                        slime_logger::sw_info!("[sentry_log] 保留期清理删除 {} 条过期事件", n);
                    }
                    Err(e) => {
                        slime_logger::sw_warn!("[sentry_log] 保留期清理失败: {}", e);
                    }
                    _ => {}
                }
                running.store(false, Ordering::Release);
            });
        if spawned.is_err() {
            // 线程起不来就复位标志，下次写入再试
            self.cleanup_running.store(false, Ordering::Release);
        }
    }

    /// 立即执行一次保留期清理（默认 90 天 / 5 万条），返回删除条数。
    /// 供测试与手动维护调用；日常由写入路径限频后台触发。
    pub fn run_retention_cleanup(&self) -> Result<u64> {
        self.ensure_index_ready()?;
        retention_cleanup_tx(&self.db, RETENTION_DAYS, MAX_EVENTS)
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

    /// 真分页查询：沿时间索引 range().rev() 从最新往回走，
    /// level/env 过滤读元数据小表，只有命中页（或关键词搜索）才反序列化事件大 JSON。
    /// total = 过滤后总条数，与旧版「全表过滤后计数」语义一致。
    /// 注：无时间戳的事件按空串排在最旧端；带 start_time 过滤时视为最旧
    /// （协议入口 store_raw_event 必填 timestamp，实际入库事件不受影响）。
    pub fn query_events(&self, filter: &SentryLogFilter) -> Result<SentryLogQueryResult> {
        self.ensure_index_ready()?;
        let read_txn = self.db.begin_read()?;
        let events_table = read_txn.open_table(EVENTS_TABLE)?;
        let meta_table = read_txn.open_table(EVENT_META_TABLE)?;

        // 项目过滤 = 复合键前缀 range；时间上下界直接编进 range 边界，
        // 字符串比较口径与旧版一致（timestamp 原样字典序比较，边界含等号）
        let base = match &filter.project_id {
            Some(p) => format!("{p}{KEY_SEP}"),
            None => String::new(),
        };
        let lower = match &filter.start_time {
            Some(s) => format!("{base}{s}"),
            None => base.clone(),
        };
        // 上界：end_time 存在时用 `{base}{end}\x01` 作排他上界——
        // ts == end 的键下一字符是 NUL < \x01，全部包含；ts > end 的键全部排除。
        let upper = match &filter.end_time {
            Some(e) => format!("{base}{e}\u{1}"),
            None => format!("{base}\u{10FFFF}"),
        };
        let lower_bound: Bound<&str> = Bound::Included(lower.as_str());
        let upper_bound: Bound<&str> = Bound::Excluded(upper.as_str());

        let use_project = filter.project_id.is_some();
        let need_meta = filter.level.is_some() || filter.environment.is_some();
        let q_lower = filter.query.as_ref().map(|q| q.to_lowercase());
        let page_end = filter.offset.saturating_add(filter.limit);

        let mut total = 0u64;
        let mut events: Vec<SentryEvent> = Vec::new();

        // 两条分支仅索引表不同；闭包统一走遍历逻辑
        let mut walk = |index: &redb::ReadOnlyTable<&'static str, &'static str>| -> Result<()> {
            for item in index.range::<&str>((lower_bound, upper_bound))?.rev() {
                let (key, _) = item?;
                let key_str = key.value();
                // 复合键最后一段即 event_id（全局键两段、项目键三段）
                let event_id = key_str.rsplit(KEY_SEP).next().unwrap_or("");

                if need_meta {
                    let meta: Option<EventMeta> = meta_table
                        .get(event_id)?
                        .and_then(|v| serde_json::from_str(v.value()).ok());
                    if let Some(level) = &filter.level {
                        if meta.as_ref().and_then(|m| m.level.as_deref()) != Some(level.as_str()) {
                            continue;
                        }
                    }
                    if let Some(env) = &filter.environment {
                        if meta.as_ref().and_then(|m| m.environment.as_deref())
                            != Some(env.as_str())
                        {
                            continue;
                        }
                    }
                }

                let in_page = total >= filter.offset && total < page_end;
                if let Some(q) = &q_lower {
                    // 关键词搜索必须看正文：只反序列化通过前置过滤的候选行
                    if let Some(val) = events_table.get(event_id)? {
                        if let Ok(event) = serde_json::from_str::<SentryEvent>(val.value()) {
                            if event_matches_query(&event, q) {
                                if in_page {
                                    events.push(event);
                                }
                                total += 1;
                            }
                        }
                    }
                } else {
                    // 无关键词：total 直接数索引行，不碰事件正文；
                    // 只有落在请求页内的行才反序列化
                    if in_page {
                        if let Some(val) = events_table.get(event_id)? {
                            if let Ok(event) = serde_json::from_str::<SentryEvent>(val.value()) {
                                events.push(event);
                            }
                        }
                    }
                    total += 1;
                }
            }
            Ok(())
        };

        if use_project {
            let index = read_txn.open_table(PROJECT_TIME_INDEX_TABLE)?;
            walk(&index)?;
        } else {
            let index = read_txn.open_table(TIME_INDEX_TABLE)?;
            walk(&index)?;
        }

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
        self.ensure_index_ready()?;
        let write_txn = self.db.begin_write()?;

        // 元数据小表 O(1) 还原全部索引键，不再全表扫 project_events
        let existed = {
            let mut events = write_txn.open_table(EVENTS_TABLE)?;
            let mut time_idx = write_txn.open_table(TIME_INDEX_TABLE)?;
            let mut proj_idx = write_txn.open_table(PROJECT_TIME_INDEX_TABLE)?;
            let mut pe = write_txn.open_table(PROJECT_EVENTS_TABLE)?;
            let mut metas = write_txn.open_table(EVENT_META_TABLE)?;
            let mut stats = write_txn.open_table(STATS_TABLE)?;
            purge_event_rows(
                &mut events, &mut time_idx, &mut proj_idx, &mut pe, &mut metas, &mut stats,
                event_id,
            )?
        };

        write_txn.commit()?;
        Ok(existed)
    }

    /// 批量删除事件：合并到单个事务，并对 project_events 索引只做一趟扫描。
    /// 逐条调用 `delete_event` 会让 M 个事件付 M 次 commit，且每次都全表扫一遍
    /// 索引表，总代价 O(M×P)；合并后为 O(M+P)。
    /// （性能审计 #2 后：元数据小表让每条删除 O(1) 定位全部索引行，
    /// 总代价进一步降为 O(M)，不再需要任何扫描。）
    pub fn delete_events(&self, event_ids: &[String]) -> Result<u64> {
        if event_ids.is_empty() {
            return Ok(0);
        }
        self.ensure_index_ready()?;
        let write_txn = self.db.begin_write()?;
        let mut deleted = 0u64;
        {
            let mut events = write_txn.open_table(EVENTS_TABLE)?;
            let mut time_idx = write_txn.open_table(TIME_INDEX_TABLE)?;
            let mut proj_idx = write_txn.open_table(PROJECT_TIME_INDEX_TABLE)?;
            let mut pe = write_txn.open_table(PROJECT_EVENTS_TABLE)?;
            let mut metas = write_txn.open_table(EVENT_META_TABLE)?;
            let mut stats = write_txn.open_table(STATS_TABLE)?;
            for id in event_ids {
                if purge_event_rows(
                    &mut events, &mut time_idx, &mut proj_idx, &mut pe, &mut metas, &mut stats,
                    id.as_str(),
                )? {
                    deleted += 1;
                }
            }
        }

        write_txn.commit()?;
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

    /// 统计走增量聚合小表（常数行）+ 项目表（项目数量级），不再全表反序列化事件。
    /// 口径与旧版一致：total = 现存事件数；level 缺省按 "info" 计；
    /// projects 沿用项目表的累计 event_count / last_event_at。
    pub fn get_stats(&self) -> Result<SentryLogStats> {
        self.ensure_index_ready()?;
        let read_txn = self.db.begin_read()?;

        let stats_table = read_txn.open_table(STATS_TABLE)?;
        let proj_table = read_txn.open_table(PROJECTS_TABLE)?;

        let mut total_events: u64 = 0;
        let mut level_counts: Vec<LevelCount> = Vec::new();
        for item in stats_table.iter()? {
            let (key, value) = item?;
            let count: u64 = value.value().parse().unwrap_or(0);
            let key_str = key.value();
            if key_str == "total" {
                total_events = count;
            } else if let Some(level) = key_str.strip_prefix("level:") {
                if count > 0 {
                    level_counts.push(LevelCount {
                        level: level.to_string(),
                        count,
                    });
                }
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
        self.ensure_index_ready()?;
        // 项目复合时间索引的前缀 range 直接列出本项目全部 event_id（只读小键，不碰正文）
        let base = format!("{project_id}{KEY_SEP}");
        let upper = format!("{base}\u{10FFFF}");
        let event_ids: Vec<String> = {
            let read_txn = self.db.begin_read()?;
            let proj_idx = read_txn.open_table(PROJECT_TIME_INDEX_TABLE)?;
            let mut ids = Vec::new();
            let bounds: (Bound<&str>, Bound<&str>) =
                (Bound::Included(base.as_str()), Bound::Excluded(upper.as_str()));
            for item in proj_idx.range::<&str>(bounds)? {
                let (key, _) = item?;
                if let Some(id) = key.value().rsplit(KEY_SEP).next() {
                    ids.push(id.to_string());
                }
            }
            ids
        };

        let count = event_ids.len() as u64;

        let write_txn = self.db.begin_write()?;
        {
            let mut events = write_txn.open_table(EVENTS_TABLE)?;
            let mut time_idx = write_txn.open_table(TIME_INDEX_TABLE)?;
            let mut proj_idx = write_txn.open_table(PROJECT_TIME_INDEX_TABLE)?;
            let mut pe = write_txn.open_table(PROJECT_EVENTS_TABLE)?;
            let mut metas = write_txn.open_table(EVENT_META_TABLE)?;
            let mut stats = write_txn.open_table(STATS_TABLE)?;
            for id in &event_ids {
                purge_event_rows(
                    &mut events, &mut time_idx, &mut proj_idx, &mut pe, &mut metas, &mut stats, id,
                )?;
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

    /// 用例临时库守卫：持有存储并连带其专属子目录，用例结束（含 panic）时
    /// 随 Drop 删除本子目录，实现「写入后删除、跑完归零」
    struct TempStorage {
        case_dir: std::path::PathBuf,
        storage: SentryLogStorage,
    }
    impl std::ops::Deref for TempStorage {
        type Target = SentryLogStorage;
        fn deref(&self) -> &SentryLogStorage {
            &self.storage
        }
    }
    impl Drop for TempStorage {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.case_dir);
            // 根目录仅在已空（所有用例都归零）时删除，绝不误伤并发用例
            if let Some(root) = self.case_dir.parent() {
                let _ = std::fs::remove_dir(root);
            }
        }
    }

    fn create_temp_storage() -> TempStorage {
        // 每个用例独占一个 uuid 子目录（并发用例互不干扰），结束即删
        let case_dir = std::env::temp_dir().join(format!(
            "sentry_log_test/{}",
            uuid::Uuid::new_v4().simple()
        ));
        std::fs::create_dir_all(&case_dir).ok();
        let db_path = case_dir.join("test.db");
        TempStorage {
            storage: SentryLogStorage::new(&db_path).unwrap(),
            case_dir,
        }
    }

    fn create_test_event(event_id: &str, level: SentryLevel, message: &str) -> SentryEvent {
        SentryEvent {
            event_id: event_id.to_string(),
            message: Some(message.to_string()),
            level: Some(level),
            timestamp: Some("2024-01-01T00:00:00Z".to_string()),
            platform: Some("javascript".to_string()),
            environment: Some("production".to_string()),
            ..Default::default()
        }
    }

    #[test]
    fn test_store_and_query_event() {
        let storage = create_temp_storage();
        let event = create_test_event("test123", SentryLevel::error, "测试事件");
        storage.store_event("1", &event).unwrap();

        let filter = SentryLogFilter {
            project_id: Some("1".to_string()),
            ..Default::default()
        };
        let result = storage.query_events(&filter).unwrap();
        assert_eq!(result.total, 1);
        assert_eq!(result.events[0].event_id, "test123");
        assert_eq!(result.events[0].message.as_deref(), Some("测试事件"));
    }

    #[test]
    fn test_query_filter_by_level() {
        let storage = create_temp_storage();
        storage
            .store_event(
                "proj1",
                &create_test_event("e1", SentryLevel::error, "错误消息"),
            )
            .unwrap();
        storage
            .store_event(
                "proj1",
                &create_test_event("e2", SentryLevel::warning, "警告消息"),
            )
            .unwrap();
        storage
            .store_event(
                "proj1",
                &create_test_event("e3", SentryLevel::info, "信息消息"),
            )
            .unwrap();

        let filter_error = SentryLogFilter {
            project_id: Some("proj1".to_string()),
            level: Some(SentryLevel::error),
            ..Default::default()
        };
        let result_error = storage.query_events(&filter_error).unwrap();
        assert_eq!(result_error.total, 1);
        assert_eq!(result_error.events[0].event_id, "e1");

        let filter_warning = SentryLogFilter {
            project_id: Some("proj1".to_string()),
            level: Some(SentryLevel::warning),
            ..Default::default()
        };
        let result_warning = storage.query_events(&filter_warning).unwrap();
        assert_eq!(result_warning.total, 1);
        assert_eq!(result_warning.events[0].event_id, "e2");
    }

    #[test]
    fn test_query_filter_by_environment() {
        let storage = create_temp_storage();
        let mut event_prod = create_test_event("e1", SentryLevel::error, "生产环境错误");
        event_prod.environment = Some("production".to_string());
        storage.store_event("proj1", &event_prod).unwrap();

        let mut event_dev = create_test_event("e2", SentryLevel::error, "开发环境错误");
        event_dev.environment = Some("development".to_string());
        storage.store_event("proj1", &event_dev).unwrap();

        let filter_prod = SentryLogFilter {
            project_id: Some("proj1".to_string()),
            environment: Some("production".to_string()),
            ..Default::default()
        };
        let result_prod = storage.query_events(&filter_prod).unwrap();
        assert_eq!(result_prod.total, 1);
        assert_eq!(
            result_prod.events[0].environment.as_deref(),
            Some("production")
        );

        let filter_dev = SentryLogFilter {
            project_id: Some("proj1".to_string()),
            environment: Some("development".to_string()),
            ..Default::default()
        };
        let result_dev = storage.query_events(&filter_dev).unwrap();
        assert_eq!(result_dev.total, 1);
        assert_eq!(
            result_dev.events[0].environment.as_deref(),
            Some("development")
        );
    }

    #[test]
    fn test_query_filter_by_query_string() {
        let storage = create_temp_storage();
        storage
            .store_event(
                "proj1",
                &create_test_event("e1", SentryLevel::error, "数据库连接失败"),
            )
            .unwrap();
        storage
            .store_event(
                "proj1",
                &create_test_event("e2", SentryLevel::error, "用户认证成功"),
            )
            .unwrap();
        storage
            .store_event(
                "proj1",
                &create_test_event("e3", SentryLevel::warning, "网络延迟较高"),
            )
            .unwrap();

        let filter_db = SentryLogFilter {
            project_id: Some("proj1".to_string()),
            query: Some("数据库".to_string()),
            ..Default::default()
        };
        let result_db = storage.query_events(&filter_db).unwrap();
        assert_eq!(result_db.total, 1);
        assert_eq!(result_db.events[0].event_id, "e1");

        let filter_user = SentryLogFilter {
            project_id: Some("proj1".to_string()),
            query: Some("用户".to_string()),
            ..Default::default()
        };
        let result_user = storage.query_events(&filter_user).unwrap();
        assert_eq!(result_user.total, 1);
        assert_eq!(result_user.events[0].event_id, "e2");
    }

    #[test]
    fn test_delete_event() {
        let storage = create_temp_storage();
        storage
            .store_event(
                "proj1",
                &create_test_event("e1", SentryLevel::error, "待删除事件"),
            )
            .unwrap();

        let filter = SentryLogFilter {
            project_id: Some("proj1".to_string()),
            ..Default::default()
        };
        assert_eq!(storage.query_events(&filter).unwrap().total, 1);

        let deleted = storage.delete_event("e1").unwrap();
        assert!(deleted);
        assert_eq!(storage.query_events(&filter).unwrap().total, 0);

        let not_found = storage.delete_event("nonexistent").unwrap();
        assert!(!not_found);
    }

    #[test]
    fn test_batch_delete_events() {
        let storage = create_temp_storage();
        storage
            .store_event(
                "proj1",
                &create_test_event("e1", SentryLevel::error, "事件1"),
            )
            .unwrap();
        storage
            .store_event(
                "proj1",
                &create_test_event("e2", SentryLevel::warning, "事件2"),
            )
            .unwrap();
        storage
            .store_event(
                "proj1",
                &create_test_event("e3", SentryLevel::info, "事件3"),
            )
            .unwrap();

        let count = storage
            .delete_events(&["e1".to_string(), "e3".to_string()])
            .unwrap();
        assert_eq!(count, 2);

        let filter = SentryLogFilter {
            project_id: Some("proj1".to_string()),
            ..Default::default()
        };
        assert_eq!(storage.query_events(&filter).unwrap().total, 1);
        assert_eq!(
            storage.query_events(&filter).unwrap().events[0].event_id,
            "e2"
        );
    }

    #[test]
    fn test_get_projects() {
        let storage = create_temp_storage();
        storage
            .store_event(
                "project-a",
                &create_test_event("e1", SentryLevel::error, "A项目事件"),
            )
            .unwrap();
        storage
            .store_event(
                "project-b",
                &create_test_event("e2", SentryLevel::warning, "B项目事件"),
            )
            .unwrap();

        let projects = storage.get_projects().unwrap();
        assert_eq!(projects.len(), 2);

        let project_ids: Vec<&str> = projects.iter().map(|p| p.id.as_str()).collect();
        assert!(project_ids.contains(&"project-a"));
        assert!(project_ids.contains(&"project-b"));
    }

    #[test]
    fn test_update_project_name() {
        let storage = create_temp_storage();
        storage
            .store_event(
                "proj1",
                &create_test_event("e1", SentryLevel::error, "初始事件"),
            )
            .unwrap();

        let projects_before = storage.get_projects().unwrap();
        let project_before = projects_before.iter().find(|p| p.id == "proj1").unwrap();
        assert_eq!(project_before.name, "项目 proj1");

        storage
            .update_project_name("proj1", "生产环境项目")
            .unwrap();

        let projects_after = storage.get_projects().unwrap();
        let project_after = projects_after.iter().find(|p| p.id == "proj1").unwrap();
        assert_eq!(project_after.name, "生产环境项目");
    }

    #[test]
    fn test_get_stats() {
        let storage = create_temp_storage();
        storage
            .store_event(
                "proj1",
                &create_test_event("e1", SentryLevel::error, "错误1"),
            )
            .unwrap();
        storage
            .store_event(
                "proj1",
                &create_test_event("e2", SentryLevel::error, "错误2"),
            )
            .unwrap();
        storage
            .store_event(
                "proj1",
                &create_test_event("e3", SentryLevel::warning, "警告1"),
            )
            .unwrap();
        storage
            .store_event(
                "proj1",
                &create_test_event("e4", SentryLevel::info, "信息1"),
            )
            .unwrap();

        let stats = storage.get_stats().unwrap();
        assert_eq!(stats.total_events, 4);
        assert_eq!(stats.level_counts.len(), 3);

        let error_count = stats
            .level_counts
            .iter()
            .find(|lc| lc.level == "error")
            .map(|lc| lc.count)
            .unwrap_or(0);
        assert_eq!(error_count, 2);
    }

    #[test]
    fn test_export_events_json() {
        let storage = create_temp_storage();
        storage
            .store_event(
                "proj1",
                &create_test_event("e1", SentryLevel::error, "导出测试事件"),
            )
            .unwrap();

        let filter = SentryLogFilter {
            project_id: Some("proj1".to_string()),
            ..Default::default()
        };
        let json = storage.export_events_json(&filter).unwrap();
        assert!(json.contains("导出测试事件"));
        assert!(json.contains("e1"));

        let parsed: Vec<SentryEvent> = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.len(), 1);
        assert_eq!(parsed[0].event_id, "e1");
    }

    #[test]
    fn test_clear_project_events() {
        let storage = create_temp_storage();
        storage
            .store_event(
                "proj1",
                &create_test_event("e1", SentryLevel::error, "事件1"),
            )
            .unwrap();
        storage
            .store_event(
                "proj1",
                &create_test_event("e2", SentryLevel::warning, "事件2"),
            )
            .unwrap();
        storage
            .store_event(
                "proj2",
                &create_test_event("e3", SentryLevel::info, "其他项目事件"),
            )
            .unwrap();

        let cleared = storage.clear_project_events("proj1").unwrap();
        assert_eq!(cleared, 2);

        let proj1_filter = SentryLogFilter {
            project_id: Some("proj1".to_string()),
            ..Default::default()
        };
        assert_eq!(storage.query_events(&proj1_filter).unwrap().total, 0);

        let proj2_filter = SentryLogFilter {
            project_id: Some("proj2".to_string()),
            ..Default::default()
        };
        assert_eq!(storage.query_events(&proj2_filter).unwrap().total, 1);
    }

    #[test]
    fn test_get_event() {
        let storage = create_temp_storage();
        storage
            .store_event(
                "proj1",
                &create_test_event("found-event", SentryLevel::fatal, "致命错误"),
            )
            .unwrap();

        let found = storage.get_event("found-event").unwrap();
        assert!(found.is_some());
        assert_eq!(found.unwrap().event_id, "found-event");

        let not_found = storage.get_event("nonexistent").unwrap();
        assert!(not_found.is_none());
    }

    #[test]
    fn test_multi_project_isolation() {
        let storage = create_temp_storage();
        storage
            .store_event(
                "proj-a",
                &create_test_event("a1", SentryLevel::error, "A项目错误"),
            )
            .unwrap();
        storage
            .store_event(
                "proj-b",
                &create_test_event("b1", SentryLevel::warning, "B项目警告"),
            )
            .unwrap();

        let filter_a = SentryLogFilter {
            project_id: Some("proj-a".to_string()),
            ..Default::default()
        };
        let filter_b = SentryLogFilter {
            project_id: Some("proj-b".to_string()),
            ..Default::default()
        };

        assert_eq!(storage.query_events(&filter_a).unwrap().total, 1);
        assert_eq!(storage.query_events(&filter_b).unwrap().total, 1);

        let stats = storage.get_stats().unwrap();
        assert_eq!(stats.total_events, 2);
        assert_eq!(stats.projects.len(), 2);
    }

    // ==== 性能审计 #2 新增验收用例 ====

    /// 生成带互异时间戳的事件（id 与时间戳一一对应，便于断言排序）
    fn timed_event(seq: usize) -> SentryEvent {
        SentryEvent {
            event_id: format!("evt{seq:04}"),
            message: Some(format!("事件 {seq}")),
            level: Some(SentryLevel::error),
            timestamp: Some(format!("2024-06-01T00:00:{seq:02}Z")),
            ..Default::default()
        }
    }

    /// 真分页探针：把「不在请求页内」的事件正文直接写坏成非法 JSON。
    /// 旧实现每页都全表反序列化，坏行会被静默跳过导致 total 缩水；
    /// 新实现 total 数索引行、只反序列化页内事件，坏行根本不会被读到。
    #[test]
    fn test_true_pagination_does_not_deserialize_offpage_events() {
        let storage = create_temp_storage();
        // 60 条互异时间戳：evt0059 最新
        for seq in 0..60 {
            storage.store_event("proj1", &timed_event(seq)).unwrap();
        }
        // 直接改底层事件表：把最旧 55 条正文写坏（索引/元数据不动）
        {
            let write_txn = storage.db.begin_write().unwrap();
            {
                let mut events = write_txn.open_table(EVENTS_TABLE).unwrap();
                for seq in 0..55 {
                    events
                        .insert(format!("evt{seq:04}").as_str(), "这不是JSON{{{")
                        .unwrap();
                }
            }
            write_txn.commit().unwrap();
        }

        let result = storage
            .query_events(&SentryLogFilter {
                project_id: Some("proj1".to_string()),
                offset: 0,
                limit: 5,
                ..Default::default()
            })
            .unwrap();
        // total 必须仍是 60（旧实现会只剩 5），且只取到最新 5 条完整事件
        assert_eq!(result.total, 60, "total 应由索引计数，不依赖页外事件正文");
        let ids: Vec<&str> = result.events.iter().map(|e| e.event_id.as_str()).collect();
        assert_eq!(ids, vec!["evt0059", "evt0058", "evt0057", "evt0056", "evt0055"]);
    }

    /// 翻页遍历：offset/limit 语义与旧版一致（时间倒序、total 恒定、无重无漏）
    #[test]
    fn test_pagination_walk_matches_legacy_semantics() {
        let storage = create_temp_storage();
        for seq in 0..60 {
            storage.store_event("proj1", &timed_event(seq)).unwrap();
        }
        // 另一项目混入，验证项目过滤分页不受干扰
        storage
            .store_event("proj2", &timed_event(999))
            .unwrap();

        let mut seen: Vec<String> = Vec::new();
        for offset in [0u64, 25, 50] {
            let result = storage
                .query_events(&SentryLogFilter {
                    project_id: Some("proj1".to_string()),
                    offset,
                    limit: 25,
                    ..Default::default()
                })
                .unwrap();
            assert_eq!(result.total, 60, "每页 total 都应为过滤后总数");
            assert_eq!(result.events.len(), if offset == 50 { 10 } else { 25 });
            seen.extend(result.events.iter().map(|e| e.event_id.clone()));
        }
        assert_eq!(seen.len(), 60);
        // 严格时间倒序且无重复
        let mut expected: Vec<String> = (0..60).rev().map(|s| format!("evt{s:04}")).collect();
        assert_eq!(seen, expected);
        expected.clear();

        // 全局（无项目过滤）分页 total 含另一项目的事件
        let all = storage
            .query_events(&SentryLogFilter {
                offset: 0,
                limit: 10,
                ..Default::default()
            })
            .unwrap();
        assert_eq!(all.total, 61);
        assert_eq!(all.events.len(), 10);
    }

    /// 时间区间过滤：边界含等号，与旧版字符串比较口径一致
    #[test]
    fn test_query_time_range_inclusive() {
        let storage = create_temp_storage();
        for seq in 0..10 {
            storage.store_event("proj1", &timed_event(seq)).unwrap();
        }
        let result = storage
            .query_events(&SentryLogFilter {
                project_id: Some("proj1".to_string()),
                start_time: Some("2024-06-01T00:00:03Z".to_string()),
                end_time: Some("2024-06-01T00:00:06Z".to_string()),
                ..Default::default()
            })
            .unwrap();
        assert_eq!(result.total, 4);
        let ids: Vec<&str> = result.events.iter().map(|e| e.event_id.as_str()).collect();
        assert_eq!(ids, vec!["evt0006", "evt0005", "evt0004", "evt0003"]);
    }

    /// 聚合小表口径：写入/替换/删除/清空后计数与真实存量一致；
    /// 并把全部事件正文写坏后 get_stats 仍正确（证明不再读事件表）。
    #[test]
    fn test_stats_incremental_and_probe() {
        let storage = create_temp_storage();
        storage
            .store_event("p1", &create_test_event("e1", SentryLevel::error, "x"))
            .unwrap();
        storage
            .store_event("p1", &create_test_event("e2", SentryLevel::warning, "x"))
            .unwrap();
        // level 缺省按 info 计（旧 get_stats 口径）
        let mut no_level = create_test_event("e3", SentryLevel::info, "x");
        no_level.level = None;
        storage.store_event("p2", &no_level).unwrap();

        let stats = storage.get_stats().unwrap();
        assert_eq!(stats.total_events, 3);
        let info = stats.level_counts.iter().find(|l| l.level == "info").unwrap();
        assert_eq!(info.count, 1);

        // 同 id 重传（替换）：total 不虚增，级别计数跟随新值
        storage
            .store_event("p1", &create_test_event("e1", SentryLevel::fatal, "x"))
            .unwrap();
        let stats = storage.get_stats().unwrap();
        assert_eq!(stats.total_events, 3);
        assert!(stats.level_counts.iter().all(|l| l.level != "error" || l.count == 0));
        assert_eq!(
            stats.level_counts.iter().find(|l| l.level == "fatal").unwrap().count,
            1
        );

        // 删除 + 清空项目后计数归位
        storage.delete_event("e2").unwrap();
        storage.clear_project_events("p2").unwrap();
        let stats = storage.get_stats().unwrap();
        assert_eq!(stats.total_events, 1);
        assert_eq!(stats.level_counts.iter().map(|l| l.count).sum::<u64>(), 1);

        // 探针：写坏仅存事件的正文，get_stats 必须不受影响
        {
            let write_txn = storage.db.begin_write().unwrap();
            {
                let mut events = write_txn.open_table(EVENTS_TABLE).unwrap();
                events.insert("e1", "坏掉的大JSON").unwrap();
            }
            write_txn.commit().unwrap();
        }
        let stats = storage.get_stats().unwrap();
        assert_eq!(stats.total_events, 1, "get_stats 不得依赖事件正文反序列化");
    }

    /// 保留期清理：超龄事件删除、新事件保留、聚合回退；条数上限裁最旧
    #[test]
    fn test_retention_cleanup_age_and_cap() {
        let storage = create_temp_storage();
        // 两条超龄（2020 年）+ 三条新鲜（当前时间）
        for (id, ts) in [
            ("old1", "2020-01-01T00:00:00Z"),
            ("old2", "2020-06-01T00:00:00Z"),
        ] {
            let mut e = create_test_event(id, SentryLevel::error, "超龄");
            e.timestamp = Some(ts.to_string());
            storage.store_event("p1", &e).unwrap();
        }
        let now = chrono::Utc::now();
        for i in 0..3 {
            let mut e = create_test_event(&format!("new{i}"), SentryLevel::info, "新鲜");
            e.timestamp = Some((now - chrono::Duration::minutes(i)).to_rfc3339());
            storage.store_event("p1", &e).unwrap();
        }

        let removed = storage.run_retention_cleanup().unwrap();
        assert_eq!(removed, 2, "应删两条超龄事件");
        let result = storage.query_events(&SentryLogFilter::default()).unwrap();
        assert_eq!(result.total, 3);
        assert!(result.events.iter().all(|e| e.event_id.starts_with("new")));
        assert_eq!(storage.get_stats().unwrap().total_events, 3);
        // 索引/元数据同步清除：单条读取应为 None
        assert!(storage.get_event("old1").unwrap().is_none());

        // 条数上限：用可配置参数把上限压到 2，应再删最旧 1 条
        let removed = retention_cleanup_tx(&storage.db, RETENTION_DAYS, 2).unwrap();
        assert_eq!(removed, 1);
        let result = storage.query_events(&SentryLogFilter::default()).unwrap();
        assert_eq!(result.total, 2);
        assert_eq!(storage.get_stats().unwrap().total_events, 2);
        // 留下的应是最新的两条（new0 最新、new1 次新）
        let ids: Vec<&str> = result.events.iter().map(|e| e.event_id.as_str()).collect();
        assert_eq!(ids, vec!["new0", "new1"]);
    }

    /// 存量旧库懒回填：只有旧三表数据的库首次访问时回填索引/聚合，
    /// 幂等标记保证重开/并发不重复计数；回填后新写入正常增量。
    #[test]
    fn test_legacy_backfill_idempotent() {
        let case_dir = std::env::temp_dir().join(format!(
            "sentry_log_test/{}",
            uuid::Uuid::new_v4().simple()
        ));
        std::fs::create_dir_all(&case_dir).unwrap();
        let db_path = case_dir.join("legacy.db");

        // 手工构造旧格式库：只写 events / projects / project_events 三表
        {
            let db = Database::create(&db_path).unwrap();
            let write_txn = db.begin_write().unwrap();
            {
                let mut events = write_txn.open_table(EVENTS_TABLE).unwrap();
                let mut pe = write_txn.open_table(PROJECT_EVENTS_TABLE).unwrap();
                let mut projects = write_txn.open_table(PROJECTS_TABLE).unwrap();
                for seq in 0..5 {
                    let e = timed_event(seq);
                    let json = serde_json::to_string(&e).unwrap();
                    events.insert(e.event_id.as_str(), json.as_str()).unwrap();
                    let pe_key = format!("legacy-proj:{}", e.event_id);
                    pe.insert(pe_key.as_str(), e.timestamp.as_deref().unwrap()).unwrap();
                }
                // 一条损坏 JSON：回填口径与旧查询一致，跳过不计数
                events.insert("broken", "不是JSON").unwrap();
                pe.insert("legacy-proj:broken", "2024-06-01T00:00:00Z").unwrap();
                let proj = SentryProject {
                    id: "legacy-proj".to_string(),
                    name: "旧项目".to_string(),
                    slug: None,
                    platform: None,
                    event_count: 5,
                    last_event_at: Some("2024-06-01T00:00:04Z".to_string()),
                    created_at: "2024-01-01T00:00:00Z".to_string(),
                };
                let pj = serde_json::to_string(&proj).unwrap();
                projects.insert("legacy-proj", pj.as_str()).unwrap();
            }
            write_txn.commit().unwrap();
            drop(db);
        }

        // 首次打开 + 查询触发懒回填
        {
            let storage = SentryLogStorage::new(&db_path).unwrap();
            let result = storage
                .query_events(&SentryLogFilter {
                    project_id: Some("legacy-proj".to_string()),
                    ..Default::default()
                })
                .unwrap();
            assert_eq!(result.total, 5, "损坏行不计数，与旧查询口径一致");
            assert_eq!(result.events[0].event_id, "evt0004");
            let stats = storage.get_stats().unwrap();
            assert_eq!(stats.total_events, 5);
            // 幂等标记已落盘（内层作用域：先释放读事务对 storage.db 的借用再 drop）
            {
                let read_txn = storage.db.begin_read().unwrap();
                let meta = read_txn.open_table(META_TABLE).unwrap();
                assert!(meta.get(INDEX_READY_KEY).unwrap().is_some());
            }
            drop(storage);
        }

        // 重开：不得重复回填/重复计数；新写入走增量
        {
            let storage = SentryLogStorage::new(&db_path).unwrap();
            let stats = storage.get_stats().unwrap();
            assert_eq!(stats.total_events, 5, "重开后计数不得翻倍");
            storage
                .store_event("legacy-proj", &timed_event(100))
                .unwrap();
            assert_eq!(storage.get_stats().unwrap().total_events, 6);
            let result = storage
                .query_events(&SentryLogFilter {
                    project_id: Some("legacy-proj".to_string()),
                    ..Default::default()
                })
                .unwrap();
            assert_eq!(result.total, 6);
            assert_eq!(result.events[0].event_id, "evt0100");
            // 删除旧事件也要能 O(1) 命中回填出来的索引行
            assert!(storage.delete_event("evt0000").unwrap());
            assert_eq!(storage.get_stats().unwrap().total_events, 5);
            drop(storage);
        }

        let _ = std::fs::remove_dir_all(&case_dir);
        if let Some(root) = case_dir.parent() {
            let _ = std::fs::remove_dir(root);
        }
    }
}