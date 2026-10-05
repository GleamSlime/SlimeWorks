use chrono::{Local, TimeZone};

use crate::types::{AggregatedStats, PowerSample, StatBucket, StatsSummary};

/// 时间范围定义：返回 (范围秒数, 桶秒数, 标签格式)
/// pub(crate)：api 层按同一个表决定 SQL 取数窗口，避免两处各写一份秒数
pub(crate) fn range_config(range: &str) -> (i64, i64, &'static str) {
    match range {
        "hour" => (3600, 60, "%H:%M"),
        "1day" => (86_400, 3600, "%H:%M"),
        "7days" => (7 * 86_400, 86_400, "%m-%d"),
        "15days" => (15 * 86_400, 86_400, "%m-%d"),
        "30days" => (30 * 86_400, 86_400, "%m-%d"),
        _ => (3600, 60, "%H:%M"),
    }
}

/// 将时间戳格式化为本地时间标签
fn format_label(ts: i64, fmt: &str) -> String {
    Local
        .timestamp_opt(ts, 0)
        .single()
        .map(|dt| dt.format(fmt).to_string())
        .unwrap_or_default()
}

/// 计算相邻采样点之间的耗电量总和（只累加下降部分，忽略充值导致的上升）
/// 传入的 samples 必须按时间升序排列
fn compute_consumption(samples: &[&PowerSample], initial_kwh: f64) -> f64 {
    let mut total = 0.0;
    let mut prev_kwh = initial_kwh;
    // 如果有初始值，用初始值作为前一个点；否则用第一个采样点
    let start_idx = if initial_kwh > 0.0 || !samples.is_empty() {
        if initial_kwh > 0.0 {
            0
        } else {
            // 没有初始值时，从第一个点开始，prev_kwh 设为第一个点的值
            prev_kwh = samples.first().map(|s| s.remaining_kwh).unwrap_or(0.0);
            1
        }
    } else {
        return 0.0;
    };

    for i in start_idx..samples.len() {
        let curr_kwh = samples[i].remaining_kwh;
        let diff = prev_kwh - curr_kwh;
        // 只累加下降部分（耗电），忽略上升（充值）
        if diff > 0.0 {
            total += diff;
        }
        prev_kwh = curr_kwh;
    }
    total
}

/// 按桶聚合采样数据，生成图表所需的结构
///
/// 关键改进：
/// 1. 时间范围基于最后一个采样点（而非当前时间），避免非实时数据被过滤
/// 2. 耗电量累加相邻采样点差值（只算下降部分），而非仅首末差值
/// 3. 空桶余额从最近采样点继承（含范围外数据）
pub fn aggregate(samples: &[PowerSample], range: &str, price: f64) -> AggregatedStats {
    if samples.is_empty() {
        return AggregatedStats {
            range: range.to_string(),
            buckets: vec![],
            total_consumption: 0.0,
            total_cost: 0.0,
            avg_balance: 0.0,
            current_balance: 0.0,
            current_kwh: 0.0,
            sample_count: 0,
        };
    }

    let (range_secs, bucket_secs, label_fmt) = range_config(range);

    // 基于最后一个采样点的时间往前推 range_secs 作为起始
    let last_ts = samples.last().unwrap().timestamp;
    let start_ts = last_ts - range_secs;

    // 过滤范围内的采样点
    let in_range: Vec<&PowerSample> = samples.iter().filter(|s| s.timestamp >= start_ts).collect();

    // 查找范围前最后一个采样点（用于初始余额）
    let before_range_kwh = samples
        .iter()
        .filter(|s| s.timestamp < start_ts)
        .last()
        .map(|s| s.remaining_kwh)
        .unwrap_or(0.0);
    let before_range_yuan = samples
        .iter()
        .filter(|s| s.timestamp < start_ts)
        .last()
        .map(|s| s.remaining_yuan)
        .unwrap_or(0.0);

    // 桶起始对齐
    let mut cursor = start_ts - (start_ts % bucket_secs);

    // 当前余额（从最近采样点继承）
    let mut cur_balance_yuan = before_range_yuan;
    let mut cur_balance_kwh = before_range_kwh;

    let mut buckets: Vec<StatBucket> = Vec::new();

    let mut sample_idx = 0;

    while cursor <= last_ts {
        let bucket_end = cursor + bucket_secs;
        let label = format_label(cursor, label_fmt);

        // 收集当前桶内的采样点
        let mut bucket_samples: Vec<&PowerSample> = Vec::new();
        while sample_idx < in_range.len() && in_range[sample_idx].timestamp < bucket_end {
            if in_range[sample_idx].timestamp >= cursor {
                bucket_samples.push(in_range[sample_idx]);
            }
            sample_idx += 1;
        }

        if bucket_samples.is_empty() {
            // 空桶：余额沿用，耗电留待后续分摊
            buckets.push(StatBucket {
                label,
                timestamp: cursor,
                consumption_kwh: 0.0,
                cost_yuan: 0.0,
                balance_yuan: cur_balance_yuan,
                balance_kwh: cur_balance_kwh,
            });
        } else {
            // 计算桶内耗电量（累加相邻差值，只算下降部分）
            let consumption = compute_consumption(&bucket_samples, cur_balance_kwh);

            // 更新当前余额为桶内最后一个采样点
            cur_balance_yuan = bucket_samples.last().unwrap().remaining_yuan;
            cur_balance_kwh = bucket_samples.last().unwrap().remaining_kwh;

            buckets.push(StatBucket {
                label,
                timestamp: cursor,
                consumption_kwh: consumption,
                cost_yuan: consumption * price,
                balance_yuan: cur_balance_yuan,
                balance_kwh: cur_balance_kwh,
            });
        }

        cursor = bucket_end;
    }

    // 耗电量分摊：若两个采样点跨多个空桶，按时间比例把下降差值分摊到中间各桶
    // 避免"前桶有值、中间空、后桶突变"的失真
    backfill_consumption(&mut buckets, &in_range, bucket_secs, price);

    let total_consumption: f64 = buckets.iter().map(|b| b.consumption_kwh).sum();
    let current_balance = cur_balance_yuan;
    let current_kwh = cur_balance_kwh;
    let avg_balance = if !buckets.is_empty() {
        buckets.iter().map(|b| b.balance_yuan).sum::<f64>() / buckets.len() as f64
    } else {
        0.0
    };

    AggregatedStats {
        range: range.to_string(),
        buckets,
        total_consumption,
        total_cost: total_consumption * price,
        avg_balance,
        current_balance,
        current_kwh,
        sample_count: in_range.len() as u64,
    }
}

/// 一次算出多个时间窗口的耗电量（各窗口都基于最后一个采样点往前回溯 secs）
///
/// 相邻采样点之间的"下降量"在链上是可加的，所以先做一次前缀和，再对每个窗口
/// 二分定位起点相减即可。原先每个窗口都要重扫全表并临时拼一个 chain Vec，
/// compute_summary 一次调 7 个窗口 = 21 遍遍历 + 7 次分配。
///
/// 与单窗口版本语义完全一致：窗口起点之前那条采样点必须作为基准计入，
/// 否则首段下降会凭空丢掉。
fn consumption_in_ranges(samples: &[PowerSample], windows_secs: &[i64]) -> Vec<f64> {
    let n = samples.len();
    if n < 2 {
        return vec![0.0; windows_secs.len()];
    }
    let last_ts = samples[n - 1].timestamp;
    // decum[i] = samples[0] 累加到 samples[i] 的下降电量（decum[0] 恒为 0）
    let mut decum: Vec<f64> = Vec::with_capacity(n);
    let mut acc = 0.0;
    decum.push(acc);
    for i in 1..n {
        let diff = samples[i - 1].remaining_kwh - samples[i].remaining_kwh;
        if diff > 0.0 {
            acc += diff;
        }
        decum.push(acc);
    }
    windows_secs
        .iter()
        .map(|&secs| {
            let start = last_ts - secs;
            // 升序序列上第一个落在窗口内的下标
            let first = samples.partition_point(|s| s.timestamp < start);
            if first >= n {
                return 0.0; // 全部数据都在窗口之前
            }
            // 基准行就是窗口内首条的前一条；没有基准行时从首条开始
            let begin = first.saturating_sub(1);
            decum[n - 1] - decum[begin]
        })
        .collect()
}

/// 耗电量分摊：两个采样点跨多个空桶时，按时间比例把下降差值分摊到中间各桶
/// 避免出现"前桶有值、中间空、后桶突变"的失真
fn backfill_consumption(
    buckets: &mut [StatBucket],
    in_range: &[&PowerSample],
    bucket_secs: i64,
    price: f64,
) {
    if buckets.is_empty() || in_range.len() < 2 {
        return;
    }
    // 桶是 contiguous 的（首桶起点对齐、每步 bucket_secs），所以按下标直接算，
    // 不用像原先那样对每对相邻点都 buckets.iter().position() 线性找——
    // "30 天"视图下那是 4 万对 × 2 次 × 平均扫半个桶数组的量级
    let base_ts = buckets[0].timestamp;
    let bucket_count = buckets.len();
    let bucket_idx = |ts: i64| -> Option<usize> {
        if ts < base_ts {
            return None;
        }
        let idx = ((ts - base_ts) / bucket_secs) as usize;
        if idx < bucket_count {
            Some(idx)
        } else {
            None
        }
    };
    // 遍历相邻采样点对，找到它们之间的空桶并分摊
    for i in 1..in_range.len() {
        let prev = in_range[i - 1];
        let curr = in_range[i];
        let diff = prev.remaining_kwh - curr.remaining_kwh;
        if diff <= 0.0 {
            continue; // 上升（充值）或不变，不分摊
        }
        let (Some(pi), Some(ci)) = (bucket_idx(prev.timestamp), bucket_idx(curr.timestamp)) else {
            continue;
        };
        if ci <= pi {
            continue;
        }
        let gap = (ci - pi) as f64;
        // curr 桶里已经装着整段 diff（桶内 compute_consumption 按相邻差值累加过它），
        // 分摊是"把这一段拆开铺到中间各桶"，不是"再加一遍"。所以先扣回再铺：
        // 60 秒采样配 60 秒桶时每对相邻点恰好跨一个桶（gap=1），漏掉这一步
        // 整条"每小时"曲线连同电费都会翻成真实值的两倍。
        buckets[ci].consumption_kwh -= diff;
        // 按比例分摊到中间各桶（含 curr 桶，不含 prev 桶）
        let share = diff / gap;
        for j in (pi + 1)..=ci {
            buckets[j].consumption_kwh += share;
            buckets[j].cost_yuan = buckets[j].consumption_kwh * price;
        }
    }
}

/// 生成统计卡片汇总数据
pub fn compute_summary(samples: &[PowerSample], meter_id: &str, meter_name: &str) -> StatsSummary {
    let price = samples.last().map(|s| s.price).unwrap_or(1.0);
    let latest = samples.last();

    // 一次前缀和算完 7 个窗口，顺序与下面的解构一一对应
    let windows: [i64; 7] = [60, 3600, 86_400, 7 * 86_400, 15 * 86_400, 16 * 86_400, 30 * 86_400];
    let cons = consumption_in_ranges(samples, &windows);
    let minute_cons = cons[0];
    let hour_cons = cons[1];
    let day_cons = cons[2];
    let week_cons = cons[3];
    let fifteen_cons = cons[4];
    let sixteen_cons = cons[5];
    let thirty_cons = cons[6];

    let last_update = latest
        .map(|s| {
            Local
                .timestamp_opt(s.timestamp, 0)
                .single()
                .map(|dt| dt.format("%Y-%m-%d %H:%M:%S").to_string())
                .unwrap_or_default()
        })
        .unwrap_or_default();

    StatsSummary {
        meter_id: meter_id.to_string(),
        meter_name: meter_name.to_string(),
        current_kwh: latest.map(|s| s.remaining_kwh).unwrap_or(0.0),
        current_yuan: latest.map(|s| s.remaining_yuan).unwrap_or(0.0),
        price,
        last_update,
        hour_consumption: hour_cons,
        day_consumption: day_cons,
        week_consumption: week_cons,
        fifteen_day_consumption: fifteen_cons,
        sixteen_day_consumption: sixteen_cons,
        thirty_day_consumption: thirty_cons,
        hour_cost: hour_cons * price,
        day_cost: day_cons * price,
        week_cost: week_cons * price,
        fifteen_day_cost: fifteen_cons * price,
        thirty_day_cost: thirty_cons * price,
        minute_consumption: minute_cons,
        sample_count: samples.len() as u64,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 基准时间戳：20000 * 86400，同时对 86400 / 3600 / 60 对齐，
    /// 便于精确断言桶边界（不受本地时区偏移影响的对齐性只看秒数）
    const BASE: i64 = 1_728_000_000;

    /// 构造一个采样点（yuan 默认与 kwh 相同，price 默认 1.0）
    fn s(ts: i64, kwh: f64) -> PowerSample {
        PowerSample {
            timestamp: ts,
            remaining_kwh: kwh,
            remaining_yuan: kwh,
            price: 1.0,
        }
    }

    /// 构造带独立 yuan / price 的采样点
    fn sy(ts: i64, kwh: f64, yuan: f64, price: f64) -> PowerSample {
        PowerSample {
            timestamp: ts,
            remaining_kwh: kwh,
            remaining_yuan: yuan,
            price,
        }
    }

    fn approx(a: f64, b: f64) -> bool {
        (a - b).abs() < 1e-9
    }

    // ── aggregate ──────────────────────────────────────────────────────────

    /// 空样本：全部字段应为零值且不 panic
    #[test]
    fn aggregate_empty_samples_returns_zeroed_stats() {
        let got = aggregate(&[], "1day", 1.0);
        assert_eq!(got.range, "1day");
        assert!(got.buckets.is_empty());
        assert!(approx(got.total_consumption, 0.0));
        assert!(approx(got.total_cost, 0.0));
        assert!(approx(got.avg_balance, 0.0));
        assert!(approx(got.current_balance, 0.0));
        assert!(approx(got.current_kwh, 0.0));
        assert_eq!(got.sample_count, 0);
    }

    /// 单样本：hour 范围应生成 61 个桶（含末点所在桶），唯一有余额的是最后一个桶
    #[test]
    fn aggregate_single_sample_makes_all_buckets_and_zero_consumption() {
        let samples = vec![sy(BASE, 10.0, 8.5, 2.0)];
        let got = aggregate(&samples, "hour", 2.0);
        // start = BASE-3600，桶宽 60，cursor <= last_ts ⇒ 60 + 1 个桶
        assert_eq!(got.buckets.len(), 61);
        assert_eq!(got.sample_count, 1);
        // 只有一个点时没有相邻差值可累加 ⇒ 无耗电
        assert!(approx(got.total_consumption, 0.0));
        assert!(approx(got.total_cost, 0.0));
        // 前 60 个空桶继承范围前余额（无样本 ⇒ 0.0）
        for b in &got.buckets[..60] {
            assert!(approx(b.balance_yuan, 0.0));
            assert!(approx(b.balance_kwh, 0.0));
            assert!(approx(b.consumption_kwh, 0.0));
        }
        let last = got.buckets.last().unwrap();
        assert_eq!(last.timestamp, BASE);
        assert!(approx(last.balance_kwh, 10.0));
        assert!(approx(last.balance_yuan, 8.5));
        assert!(approx(got.current_kwh, 10.0));
        assert!(approx(got.current_balance, 8.5));
        // avg_balance = 8.5 / 61
        assert!(approx(got.avg_balance, 8.5 / 61.0));
    }

    /// 区间边界：恰好在 start_ts 的样本算范围内，start_ts 前 1 秒的样本只作为基准余额
    /// 注：范围以最后一个采样点为锚（start_ts = last_ts - range_secs）
    #[test]
    fn aggregate_range_boundary_is_inclusive_at_start_and_uses_prev_baseline() {
        // last_ts = BASE ⇒ start_ts = BASE-3600
        let samples = vec![
            s(BASE - 3601, 20.0), // 范围外（start_ts 前 1 秒）：仅作为初始余额基准
            s(BASE - 3600, 18.0), // 恰好落在边界 ⇒ 范围内，第 0 桶
            s(BASE, 18.0),        // 末点：余额不变 ⇒ 与上一点差值为 0，不触发跨桶分摊
        ];
        let got = aggregate(&samples, "hour", 1.0);
        assert_eq!(got.sample_count, 2, "边界样本应计入范围内");
        // 第 0 桶：基准 20 → 18 只累加下降部分 ⇒ 2
        let b0 = &got.buckets[0];
        assert_eq!(b0.timestamp, BASE - 3600);
        assert!(approx(b0.consumption_kwh, 2.0));
        assert!(approx(b0.balance_kwh, 18.0));
        // 其余桶无消耗
        assert!(got.buckets[1..].iter().all(|b| approx(b.consumption_kwh, 0.0)));
        assert!(approx(got.total_consumption, 2.0));
        assert!(approx(got.current_kwh, 18.0));
    }

    /// 电价计算：每桶 cost_yuan 与总 total_cost 都等于消耗 × 单价
    #[test]
    fn aggregate_applies_price_to_bucket_and_total_cost() {
        let price = 0.85;
        let samples = vec![
            s(BASE - 3601, 20.0),
            s(BASE - 3600, 18.0),
            s(BASE, 18.0),
        ];
        let got = aggregate(&samples, "hour", price);
        assert!(approx(got.buckets[0].cost_yuan, 2.0 * price));
        assert!(approx(got.total_cost, 2.0 * price));
        // 所有桶的成本之和应与总成本一致（无跨桶分摊时）
        let sum: f64 = got.buckets.iter().map(|b| b.cost_yuan).sum();
        assert!((sum - got.total_cost).abs() < 1e-9);
        // 每个桶都满足 cost = consumption * price
        for b in &got.buckets {
            assert!(approx(b.cost_yuan, b.consumption_kwh * price));
        }
    }

    /// 跨空桶分摊：两点相隔 30 个桶时，diff 整段被拆开铺到 pi+1..=ci，
    /// 每桶 diff/30，各桶之和恰好等于真实下降量（不叠加、不翻倍）
    #[test]
    fn aggregate_backfills_consumption_across_empty_buckets() {
        // last_ts = BASE-1800 ⇒ start_ts = BASE-5400，共 61 个桶；
        // s1 落第 30 桶，s2 落第 60 桶
        let samples = vec![s(BASE - 3600, 30.0), s(BASE - 1800, 24.0)];
        let got = aggregate(&samples, "hour", 1.0);
        assert_eq!(got.buckets.len(), 61);
        assert!(approx(got.buckets[30].consumption_kwh, 0.0), "首点所在桶无相邻差值");
        let share = 6.0 / 30.0;
        for idx in 31..=60 {
            assert!(
                approx(got.buckets[idx].consumption_kwh, share),
                "桶 {idx} 应分摊 {share}，实际 {}",
                got.buckets[idx].consumption_kwh
            );
        }
        // 分摊范围之外的空桶保持为 0
        assert!(approx(got.buckets[10].consumption_kwh, 0.0));
        // 总消耗恰好等于下降量 6（曾经会是 6+6=12）
        assert!(approx(got.total_consumption, 6.0));
        // 分摊后每桶仍满足 cost = consumption * price（price=1）
        for b in &got.buckets {
            assert!(approx(b.cost_yuan, b.consumption_kwh));
        }
    }

    /// 充值上升不计入耗电：同桶内 10→15→12 只累加下降的 3
    #[test]
    fn aggregate_ignores_recharge_increases() {
        // 三点同落最后一个 60 秒桶内（避免触发跨桶分摊）
        let samples = vec![
            s(BASE - 3, 10.0),
            s(BASE - 2, 15.0), // 充值：上升，忽略
            s(BASE - 1, 12.0), // 下降 3
        ];
        let got = aggregate(&samples, "hour", 1.0);
        let last_bucket = got.buckets.last().unwrap();
        assert!(approx(last_bucket.consumption_kwh, 3.0));
        assert!(approx(got.total_consumption, 3.0));
        // 余额取最后一点
        assert!(approx(got.current_kwh, 12.0));
    }

    /// 未知 range 回退到 hour 配置（60 秒桶 / 3600 秒范围）
    #[test]
    fn aggregate_unknown_range_falls_back_to_hour_config() {
        let samples = vec![s(BASE - 3600, 5.0), s(BASE, 4.0)];
        let got = aggregate(&samples, "nonsense", 1.0);
        assert_eq!(got.range, "nonsense");
        assert_eq!(got.buckets.len(), 61, "未知 range 应回退成 hour 的 61 个 60 秒桶");
    }

    /// 7days 范围：桶宽 86400 ⇒ 8 个桶；跨天下降被摊成每天 1.0
    #[test]
    fn aggregate_day_range_bucket_count() {
        let samples = vec![s(BASE - 7 * 86_400, 50.0), s(BASE, 43.0)];
        let got = aggregate(&samples, "7days", 1.0);
        assert_eq!(got.buckets.len(), 8);
        assert_eq!(got.buckets[1].timestamp - got.buckets[0].timestamp, 86_400);
        // 差值 7 摊到桶 1..=7（每桶 1.0），末桶不再叠加自己那份
        for idx in 1..=7 {
            assert!(approx(got.buckets[idx].consumption_kwh, 1.0));
        }
        assert!(approx(got.total_consumption, 7.0));
        assert_eq!(got.sample_count, 2);
    }

    /// 回归：60 秒采样 + "每小时"视图（桶宽同为 60 秒）时，每对相邻点都恰好
    /// 跨一个桶，分摊曾把差值在 curr 桶再叠一遍，导致电费是真实值的两倍。
    #[test]
    fn aggregate_minute_sampling_hour_view_does_not_double_count() {
        // 61 个点、每分钟一个，一小时内共用掉 15.0 kWh（每点 0.25，二进制精确）
        let samples: Vec<PowerSample> = (0..=60)
            .map(|i| {
                let v = 30.0 - i as f64 * 0.25;
                sy(BASE - (60 - i) * 60, v, v, 1.0)
            })
            .collect();
        let got = aggregate(&samples, "hour", 1.0);
        assert!(
            approx(got.total_consumption, 15.0),
            "总耗电应为 15.0，实际 {}",
            got.total_consumption
        );
        assert!(
            approx(got.total_cost, 15.0),
            "电费应与余额下降一致，实际 {}",
            got.total_cost
        );
        // 逐桶也不能翻倍：每个有值的桶恰好 0.25
        for b in got.buckets.iter().filter(|b| b.consumption_kwh > 0.0) {
            assert!(approx(b.consumption_kwh, 0.25), "桶 {} = {}", b.label, b.consumption_kwh);
        }
    }

    // ── compute_summary ────────────────────────────────────────────────────

    /// 空样本：price 回退 1.0，各项统计为 0，last_update 为空串
    #[test]
    fn compute_summary_empty_samples() {
        let got = compute_summary(&[], "m1", "表一");
        assert_eq!(got.meter_id, "m1");
        assert_eq!(got.meter_name, "表一");
        assert!(approx(got.price, 1.0), "无样本时单价应回退为 1.0");
        assert!(approx(got.current_kwh, 0.0));
        assert!(approx(got.current_yuan, 0.0));
        assert!(approx(got.hour_consumption, 0.0));
        assert!(approx(got.thirty_day_consumption, 0.0));
        assert!(approx(got.hour_cost, 0.0));
        assert_eq!(got.sample_count, 0);
        assert!(got.last_update.is_empty());
    }

    /// 单样本：不足两点无相邻差值，余额与时间取该样本
    #[test]
    fn compute_summary_single_sample_has_no_consumption() {
        let samples = vec![sy(BASE, 7.5, 6.2, 1.2)];
        let got = compute_summary(&samples, "m2", "表二");
        assert!(approx(got.current_kwh, 7.5));
        assert!(approx(got.current_yuan, 6.2));
        assert!(approx(got.price, 1.2));
        assert_eq!(got.sample_count, 1);
        for cons in [
            got.minute_consumption,
            got.hour_consumption,
            got.day_consumption,
            got.week_consumption,
            got.fifteen_day_consumption,
            got.sixteen_day_consumption,
            got.thirty_day_consumption,
        ] {
            assert!(approx(cons, 0.0));
        }
        // last_update 形如 YYYY-MM-DD HH:MM:SS（本地时区，只校验长度与分隔符）
        assert_eq!(got.last_update.len(), 19, "last_update = {}", got.last_update);
        assert_eq!(&got.last_update[4..5], "-");
        assert_eq!(&got.last_update[10..11], " ");
    }

    /// 时间窗口边界：minute / hour / day 三档分别取对应基准点
    #[test]
    fn compute_summary_window_boundaries() {
        let price = 1.5;
        let samples = vec![
            sy(BASE - 7200, 100.0, 100.0, price),
            sy(BASE - 3601, 90.0, 90.0, price), // hour 窗口外的最后一个基准
            sy(BASE - 3600, 80.0, 80.0, price), // 恰好在 hour 窗口边界内
            sy(BASE, 70.0, 70.0, price),
        ];
        let got = compute_summary(&samples, "m3", "表三");
        // minute 窗口：基准 = BASE-3600 的 80 ⇒ 80-70 = 10
        assert!(approx(got.minute_consumption, 10.0));
        // hour 窗口：基准 = BASE-3601 的 90 ⇒ (90-80) + (80-70) = 20
        assert!(approx(got.hour_consumption, 20.0));
        // day 窗口：无更早样本 ⇒ (100-90)+(90-80)+(80-70) = 30
        assert!(approx(got.day_consumption, 30.0));
        assert!(approx(got.week_consumption, 30.0));
        assert!(approx(got.fifteen_day_consumption, 30.0));
        assert!(approx(got.sixteen_day_consumption, 30.0));
        assert!(approx(got.thirty_day_consumption, 30.0));
        // 费用 = 消耗 × 最后一个样本的单价
        assert!(approx(got.price, price));
        assert!(approx(got.hour_cost, 20.0 * price));
        assert!(approx(got.day_cost, 30.0 * price));
        assert!(approx(got.week_cost, 30.0 * price));
        assert!(approx(got.fifteen_day_cost, 30.0 * price));
        assert!(approx(got.thirty_day_cost, 30.0 * price));
        assert_eq!(got.sample_count, 4);
    }

    /// 充值上升在汇总里同样被忽略
    #[test]
    fn compute_summary_ignores_recharge() {
        let samples = vec![
            sy(BASE - 120, 5.0, 5.0, 1.0),
            sy(BASE - 60, 8.0, 8.0, 1.0), // 充值 +3
            sy(BASE, 6.0, 6.0, 1.0),      // 耗电 -2
        ];
        let got = compute_summary(&samples, "m4", "表四");
        assert!(approx(got.hour_consumption, 2.0));
        assert!(approx(got.hour_cost, 2.0));
        assert!(approx(got.current_kwh, 6.0));
    }

    /// 样本不足两点时 consumption_in_ranges 直接返回 0（通过 summary 间接覆盖）
    #[test]
    fn compute_summary_two_samples_only_counts_single_diff() {
        let samples = vec![sy(BASE - 100, 12.0, 12.0, 1.0), sy(BASE, 9.0, 9.0, 1.0)];
        let got = compute_summary(&samples, "m5", "表五");
        assert!(approx(got.minute_consumption, 3.0));
        assert!(approx(got.hour_consumption, 3.0));
        // 超出窗口范围（day 窗口起点 = BASE-86400 之前无点，两点均在窗口内）⇒ 仍是 3
        assert!(approx(got.day_consumption, 3.0));
    }

    /// 取数窗口化的等价性护栏：api 层不再把整张表交给聚合器，只喂
    /// 「窗口内采样 + 窗口前最后一条基准」。这个用例锁死少喂更早的历史
    /// **不改变输出**，否则第 4 项优化就是偷偷改了计算结果。
    ///
    /// 两种消费者的窗口不一样，必须分开验证：
    /// - 图表 aggregate：跟着用户选的 range 走（hour 就只喂 1 小时）
    /// - 卡片 compute_summary：最长要 30 天，api 层固定按 30 天取数，
    ///   所以只有按 30 天切出来的窗口才能和全量等价
    #[test]
    fn aggregate_and_summary_are_identical_on_windowed_input() {
        // 45 天、每 5 分钟一条 = 12961 条，保证 30 天窗口是全集的真子集；
        // 最后一条时间戳正好是 BASE，与 aggregate 的"锚定最新采样"一致
        let step = 300i64;
        let n = 12_961usize;
        let all: Vec<PowerSample> = (0..n)
            .map(|i| {
                // 稳定下降（耗电）+ 第 9000 条处整体抬高 40（充值），
                // 同时覆盖"只累加下降部分"和跨空桶分摊两条路径；
                // 5 分钟采样配 60 秒桶还能顺带铺出大量空桶
                let bump = if i >= 9000 { 40.0 } else { 0.0 };
                let kwh = 300.0 - i as f64 * 0.01 + bump;
                sy(BASE - (n as i64 - 1 - i as i64) * step, kwh, kwh * 0.9, 0.9)
            })
            .collect();
        let last_ts = all[n - 1].timestamp;
        let price = 0.9;

        // 按窗口秒数切出「基准行 + 窗口内」
        let cut_at = |secs: i64| -> &[PowerSample] {
            let first = all.partition_point(|s| s.timestamp < last_ts - secs);
            &all[first.saturating_sub(1)..]
        };

        for range in ["hour", "1day", "7days", "15days", "30days"] {
            let (secs, _, _) = range_config(range);
            let windowed = cut_at(secs);
            assert!(
                windowed.len() < all.len(),
                "{}：窗口化必须真的少喂数据",
                range
            );

            let full = aggregate(&all, range, price);
            let cut = aggregate(windowed, range, price);
            assert_eq!(full.buckets.len(), cut.buckets.len(), "{}：桶数变了", range);
            assert_eq!(full.sample_count, cut.sample_count, "{}：样本数变了", range);
            for (i, (a, b)) in full.buckets.iter().zip(cut.buckets.iter()).enumerate() {
                assert_eq!(a.label, b.label, "{}：第{}桶标签", range, i);
                assert_eq!(a.timestamp, b.timestamp, "{}：第{}桶时间", range, i);
                assert!(
                    approx(a.consumption_kwh, b.consumption_kwh),
                    "{}：第{}桶耗电",
                    range,
                    i
                );
                assert!(approx(a.cost_yuan, b.cost_yuan), "{}：第{}桶电费", range, i);
                assert!(
                    approx(a.balance_yuan, b.balance_yuan),
                    "{}：第{}桶余额",
                    range,
                    i
                );
                assert!(
                    approx(a.balance_kwh, b.balance_kwh),
                    "{}：第{}桶电量",
                    range,
                    i
                );
            }
            assert!(
                approx(full.total_consumption, cut.total_consumption),
                "{}：总耗电",
                range
            );
            assert!(approx(full.total_cost, cut.total_cost), "{}：总电费", range);
            assert!(
                approx(full.avg_balance, cut.avg_balance),
                "{}：平均余额",
                range
            );
            assert!(
                approx(full.current_balance, cut.current_balance),
                "{}：当前余额",
                range
            );
        }

        // 卡片：按 30 天窗口取数后，7 个统计窗口的结果必须与全量一致
        let summary_cut = cut_at(30 * 86_400);
        let s_full = compute_summary(&all, "m", "表");
        let s_cut = compute_summary(summary_cut, "m", "表");
        for (name, a, b) in [
            (
                "minute",
                s_full.minute_consumption,
                s_cut.minute_consumption,
            ),
            ("hour", s_full.hour_consumption, s_cut.hour_consumption),
            ("day", s_full.day_consumption, s_cut.day_consumption),
            ("week", s_full.week_consumption, s_cut.week_consumption),
            (
                "15d",
                s_full.fifteen_day_consumption,
                s_cut.fifteen_day_consumption,
            ),
            (
                "16d",
                s_full.sixteen_day_consumption,
                s_cut.sixteen_day_consumption,
            ),
            (
                "30d",
                s_full.thirty_day_consumption,
                s_cut.thirty_day_consumption,
            ),
        ] {
            assert!(approx(a, b), "{} 窗口耗电 {} != {}", name, a, b);
        }
        assert!(approx(s_full.current_kwh, s_cut.current_kwh));
        assert!(approx(s_full.current_yuan, s_cut.current_yuan));
        assert!(approx(s_full.price, s_cut.price));
        assert_eq!(s_full.last_update, s_cut.last_update);
    }
}
