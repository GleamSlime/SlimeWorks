use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Mutex, RwLock};
use std::thread::JoinHandle;
use std::time::Duration;

use chrono::{DateTime, Local, NaiveDateTime, NaiveTime, TimeZone};
use lazy_static::lazy_static;
use slime_logger::{sw_error, sw_info};

use crate::api::check_by_rule;
use crate::storage;
use crate::types::*;

// 后台检查线程：只做"到点触发"，抓取与落库的编排都在 api::check_by_rule 里。
// 用 std::thread + 分片 sleep 而不是 tokio 定时器，是为了和同步的收信层保持一致，
// 移动端也能跑（不依赖 FRB 的 runtime 是否可用）。
lazy_static! {
    static ref WORKER: Mutex<Option<JoinHandle<()>>> = Mutex::new(None);
    static ref SECRETS: RwLock<HashMap<i64, String>> = RwLock::new(HashMap::new());
    static ref STATUS: RwLock<SchedulerStatus> = RwLock::new(SchedulerStatus::default());
}

static STOP_REQUESTED: AtomicBool = AtomicBool::new(false);

/// 检查节拍：规则真正的"每日 HH:MM / 间隔 N 分钟"判断在 rule_due 里做，
/// 这里只决定轮询粒度，太密会白耗唤醒，太疏会错过到点。
const TICK_SECS: u64 = 60;

pub fn set_secret(rule_id: i64, password: &str) {
    if let Ok(mut map) = SECRETS.write() {
        if password.is_empty() {
            map.remove(&rule_id);
        } else {
            map.insert(rule_id, password.to_string());
        }
    }
}

pub fn secret_of(rule_id: i64) -> String {
    SECRETS
        .read()
        .map(|m| m.get(&rule_id).cloned().unwrap_or_default())
        .unwrap_or_default()
}

pub fn status() -> SchedulerStatus {
    STATUS.read().map(|s| s.clone()).unwrap_or_default()
}

fn update_status(f: impl FnOnce(&mut SchedulerStatus)) {
    if let Ok(mut s) = STATUS.write() {
        f(&mut s);
    }
}

pub fn is_running() -> bool {
    WORKER
        .lock()
        .map(|g| g.as_ref().map(|h| !h.is_finished()).unwrap_or(false))
        .unwrap_or(false)
}

/// 启动后台检查；已运行则幂等返回
pub fn start() -> Result<(), String> {
    {
        let guard = WORKER.lock().map_err(|e| e.to_string())?;
        if let Some(h) = guard.as_ref() {
            if !h.is_finished() {
                return Ok(());
            }
        }
    }
    STOP_REQUESTED.store(false, Ordering::SeqCst);
    let handle = std::thread::spawn(|| loop {
        if STOP_REQUESTED.load(Ordering::SeqCst) {
            sw_info!("[ledger] 自动记账线程已退出");
            break;
        }
        run_due_rules();
        // 分片睡眠，停止请求最坏 1 秒内生效
        for _ in 0..TICK_SECS {
            if STOP_REQUESTED.load(Ordering::SeqCst) {
                break;
            }
            std::thread::sleep(Duration::from_secs(1));
        }
    });
    *WORKER.lock().map_err(|e| e.to_string())? = Some(handle);
    update_status(|s| {
        s.running = true;
        s.check_interval_secs = TICK_SECS;
    });
    sw_info!("[ledger] 自动记账线程已启动（每 {} 秒检查一次到点规则）", TICK_SECS);
    Ok(())
}

pub fn stop() -> Result<(), String> {
    STOP_REQUESTED.store(true, Ordering::SeqCst);
    let handle = WORKER.lock().map_err(|e| e.to_string())?.take();
    if let Some(h) = handle {
        // 线程最长 1 秒后自行退出；这里不 join，避免卡住 FFI 调用线程
        if h.is_finished() {
            let _ = h.join();
        }
    }
    update_status(|s| s.running = false);
    Ok(())
}

pub fn set_enabled(enabled: bool) {
    update_status(|s| s.enabled = enabled);
}

/// 跑一遍所有到点的规则
fn run_due_rules() {
    update_status(|s| {
        s.last_check_at = now_text();
        s.next_check_at = next_tick_text();
    });
    let rules = match storage::list_email_rules() {
        Ok(r) => r,
        Err(e) => {
            // 未初始化时（比如移动端只连节点）不该刷屏，降级成一条摘要
            update_status(|s| s.last_summary = format!("读取规则失败: {}", e));
            return;
        }
    };
    let now = Local::now();
    let due: Vec<EmailRule> = rules
        .into_iter()
        .filter(|r| r.enabled && rule_due(r, now))
        .collect();
    update_status(|s| s.active_rules = due.len());
    if due.is_empty() {
        return;
    }
    let mut summary = Vec::new();
    for rule in due {
        let password = secret_of(rule.id);
        if password.is_empty() {
            summary.push(format!("{}:缺少密码", rule.name));
            continue;
        }
        match check_by_rule(rule.id, &password) {
            Ok(text) => summary.push(format!("{}:{}", rule.name, text)),
            Err(e) => {
                sw_error!("[ledger] 规则 {} 检查失败: {}", rule.name, e);
                summary.push(format!("{}:{}", rule.name, e));
            }
        }
    }
    update_status(|s| s.last_summary = summary.join("；"));
}

/// 到点判定：间隔模式看上次运行时间，每日模式看今天是否已过该时刻且今天还没跑过
fn rule_due(rule: &EmailRule, now: DateTime<Local>) -> bool {
    let last = parse_rule_time(&rule.last_run_at);
    if rule.interval_minutes > 0 {
        return match last {
            None => true,
            Some(t) => (now - t).num_minutes() >= rule.interval_minutes as i64,
        };
    }
    if !rule.daily_time.is_empty() {
        let wanted = match parse_hm(&rule.daily_time) {
            Some(t) => t,
            None => return false,
        };
        let reached = now.time() >= wanted;
        let ran_today = last
            .map(|t| t.format("%Y-%m-%d").to_string() == now.format("%Y-%m-%d").to_string())
            .unwrap_or(false);
        return reached && !ran_today;
    }
    false
}

/// 存储里 last_run_at 是本地时间文本，按同一口径解析回来
fn parse_rule_time(text: &str) -> Option<DateTime<Local>> {
    if text.len() < 19 {
        return None;
    }
    NaiveDateTime::parse_from_str(&text.chars().take(19).collect::<String>(), "%Y-%m-%d %H:%M:%S")
        .ok()
        .and_then(|nd| Local.from_local_datetime(&nd).single())
}

/// 供前端展示"哪些规则今天会跑/该跑了"
pub fn due_rule_ids() -> Vec<i64> {
    let rules = storage::list_email_rules().unwrap_or_default();
    let now = Local::now();
    rules
        .into_iter()
        .filter(|r| r.enabled && rule_due(r, now))
        .map(|r| r.id)
        .collect()
}

fn parse_hm(text: &str) -> Option<NaiveTime> {
    let parts: Vec<&str> = text.trim().split(':').collect();
    if parts.len() < 2 {
        return None;
    }
    NaiveTime::from_hms_opt(
        parts[0].parse().ok()?,
        parts[1].parse().ok()?,
        parts.get(2).and_then(|s| s.parse().ok()).unwrap_or(0),
    )
}

fn now_text() -> String {
    Local::now().format("%Y-%m-%d %H:%M:%S").to_string()
}

fn next_tick_text() -> String {
    (Local::now() + chrono::Duration::seconds(TICK_SECS as i64))
        .format("%Y-%m-%d %H:%M:%S")
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 本地时区造一个"墙上时间"，与 last_run_at 的存储口径一致
    fn at(year: i32, month: u32, day: u32, hh: u32, mm: u32, ss: u32) -> DateTime<Local> {
        Local.with_ymd_and_hms(year, month, day, hh, mm, ss).unwrap()
    }

    fn rule(interval_minutes: u64, daily_time: &str, last_run_at: &str) -> EmailRule {
        EmailRule {
            id: 1,
            name: "示例招行账单规则".to_string(),
            enabled: true,
            interval_minutes,
            daily_time: daily_time.to_string(),
            last_run_at: last_run_at.to_string(),
            ..Default::default()
        }
    }

    // ── 间隔模式 ──────────────────────────────────────────────

    #[test]
    fn interval_rule_never_run_is_due() {
        let r = rule(30, "", "");
        assert!(rule_due(&r, at(2026, 9, 1, 10, 30, 0)));
        // 非法/空的时间文本一律按"从没跑过"处理，立即到点
        let r = rule(30, "", "不是时间");
        assert!(rule_due(&r, at(2026, 9, 1, 10, 30, 0)));
    }

    #[test]
    fn interval_boundary_is_inclusive_to_the_minute() {
        let now = at(2026, 9, 1, 10, 30, 0);
        // 正好 30 分钟 → 到点（判定用 >=）
        let r = rule(30, "", "2026-09-01 10:00:00");
        assert!(rule_due(&r, now));
        // 差一秒钟不足 30 分钟：num_minutes 向下取整成 29 → 不到点
        let r = rule(30, "", "2026-09-01 10:00:01");
        assert!(!rule_due(&r, now));
        // 间隔 1 分钟：59 秒不算，60 秒算
        assert!(!rule_due(&rule(1, "", "2026-09-01 10:29:01"), now));
        assert!(rule_due(&rule(1, "", "2026-09-01 10:29:00"), now));
        // 超过间隔当然到点
        assert!(rule_due(&rule(30, "", "2026-08-31 09:00:00"), now));
    }

    #[test]
    fn interval_rule_with_future_last_run_is_not_due() {
        // last_run_at 在未来（改过系统时间/时区漂移）→ 负数间隔，视为未到点
        let r = rule(30, "", "2026-09-01 11:00:00");
        assert!(!rule_due(&r, at(2026, 9, 1, 10, 30, 0)));
    }

    // ── 间隔优先于每日时刻 ────────────────────────────────────

    #[test]
    fn interval_minutes_takes_precedence_over_daily_time() {
        // 两个都设了：只看间隔，daily_time 完全不参与判定
        // 若 daily_time 生效，"已过 00:00 且今天没跑过"→ 该到点；实际按间隔判 → 不到点
        let r = rule(60, "00:00", "2026-09-01 10:25:00");
        assert!(!rule_due(&r, at(2026, 9, 1, 10, 30, 0)));
        // 同一规则跨过间隔后立刻到点，与 daily_time 无关
        let r = rule(60, "00:00", "2026-09-01 09:30:00");
        assert!(rule_due(&r, at(2026, 9, 1, 10, 30, 0)));
    }

    // ── 每日时刻模式 ──────────────────────────────────────────

    #[test]
    fn daily_time_fires_at_or_after_the_time() {
        let r = rule(0, "09:00", "");
        assert!(!rule_due(&r, at(2026, 9, 1, 8, 59, 59)));
        // 时刻本身算"已到"
        assert!(rule_due(&r, at(2026, 9, 1, 9, 0, 0)));
        assert!(rule_due(&r, at(2026, 9, 1, 23, 59, 59)));
        // 带秒的写法：09:00:30 之前不到点
        let r = rule(0, "09:00:30", "");
        assert!(!rule_due(&r, at(2026, 9, 1, 9, 0, 29)));
        assert!(rule_due(&r, at(2026, 9, 1, 9, 0, 30)));
    }

    #[test]
    fn daily_time_fires_only_once_per_day() {
        let now = at(2026, 9, 1, 12, 0, 0);
        // 今天 09:05 跑过 → 当天不再跑
        let r = rule(0, "09:00", "2026-09-01 09:05:00");
        assert!(!rule_due(&r, now));
        // 昨天深夜跑过 → 今天到点即跑
        let r = rule(0, "09:00", "2026-08-31 23:59:00");
        assert!(rule_due(&r, now));
        // 今天跑在 daily_time 之前也算"今天已跑"，不会再触发一次
        let r = rule(0, "09:00", "2026-09-01 06:00:00");
        assert!(!rule_due(&r, now));
    }

    #[test]
    fn daily_time_uses_local_wall_clock_of_now() {
        // 跨天边界：00:00 的规则在当天零点整到点，且昨天 23:59 跑的不算今天
        let r = rule(0, "00:00", "2026-08-31 23:59:00");
        assert!(rule_due(&r, at(2026, 9, 1, 0, 0, 0)));
        let r = rule(0, "00:00", "2026-09-01 00:00:30");
        assert!(!rule_due(&r, at(2026, 9, 1, 12, 0, 0)));
    }

    #[test]
    fn unparsable_daily_time_means_never_due() {
        let now = at(2026, 9, 1, 12, 0, 0);
        for bad in ["9am", "09", "25:00", "09:60", "", "   "] {
            let r = rule(0, bad, "");
            assert!(!rule_due(&r, now), "非法 daily_time {:?} 不该触发", bad);
        }
        // 注意：非法时刻 + 无间隔 = 永久不跑，且没有任何提示（见报告可疑项）
    }

    #[test]
    fn rule_without_any_schedule_is_never_due() {
        // 间隔 0 + 时刻空：只能手动触发
        let r = rule(0, "", "");
        assert!(!rule_due(&r, at(2026, 9, 1, 12, 0, 0)));
    }

    #[test]
    fn garbage_last_run_in_daily_mode_refires_every_tick() {
        // 按现状锁定：last_run_at 解析不出来 → ran_today=false → 当天每个节拍都判"到点"
        let now = at(2026, 9, 1, 12, 0, 0);
        for bad in ["不是时间", "2026-09-01", "2026-09-01T12:00:00", "0000-00-00 00:00:00"] {
            let r = rule(0, "09:00", bad);
            assert!(rule_due(&r, now), "坏值 {:?} 当前被判为到点", bad);
        }
    }

    // ── 时间解析辅助 ──────────────────────────────────────────

    #[test]
    fn parse_rule_time_only_accepts_local_text_format() {
        let ok = parse_rule_time("2026-09-01 09:05:00").unwrap();
        assert_eq!(ok.format("%Y-%m-%d %H:%M:%S").to_string(), "2026-09-01 09:05:00");
        // 只取前 19 个字符，后面的小数秒/时区被丢弃
        assert!(parse_rule_time("2026-09-01 09:05:00.123+08:00").is_some());
        // 短于 19 字符直接 None（含空串与纯日期）
        assert!(parse_rule_time("").is_none());
        assert!(parse_rule_time("2026-09-01").is_none());
        // ISO 的 T 分隔写法不支持
        assert!(parse_rule_time("2026-09-01T09:05:00").is_none());
    }

    #[test]
    fn parse_hm_accepts_hm_and_hms() {
        assert_eq!(parse_hm("09:00"), NaiveTime::from_hms_opt(9, 0, 0));
        // 整体 trim 后按 ':' 切，单数字段可用
        assert_eq!(parse_hm(" 9:5 "), NaiveTime::from_hms_opt(9, 5, 0));
        assert_eq!(parse_hm("09:00:30"), NaiveTime::from_hms_opt(9, 0, 30));
        // 缺秒字段解析失败则回落 0，但整段不可解析时给 None
        assert_eq!(parse_hm("09:00:xx"), NaiveTime::from_hms_opt(9, 0, 0));
        assert_eq!(parse_hm("09:00:30:50"), NaiveTime::from_hms_opt(9, 0, 30));
        assert!(parse_hm("09").is_none());
        assert!(parse_hm("").is_none());
        assert!(parse_hm("09:60").is_none());
        assert!(parse_hm("-1:00").is_none());
    }

    #[test]
    fn status_text_helpers_emit_storage_format() {
        // 现在时间/下次检查时间都得能被 parse_rule_time 读回，否则前端展示会瞎
        assert!(parse_rule_time(&now_text()).is_some());
        assert!(parse_rule_time(&next_tick_text()).is_some());
        assert_eq!(status().check_interval_secs, 60);
    }

    // ── 口令暂存表 ────────────────────────────────────────────

    #[test]
    fn secret_store_roundtrip_and_removal() {
        // 用不复用的 id，避免和别的用例抢同一张全局表
        let id = 900_017;
        assert_eq!(secret_of(id), "");
        set_secret(id, "hunter2");
        assert_eq!(secret_of(id), "hunter2");
        set_secret(id, "again");
        assert_eq!(secret_of(id), "again");
        // 空串按"删除"处理：调度器据此报"缺少密码"而不是拿空口令去登录
        set_secret(id, "");
        assert_eq!(secret_of(id), "");
    }
}
