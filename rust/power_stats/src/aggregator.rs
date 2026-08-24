use chrono::{Local, TimeZone};

use crate::types::{AggregatedStats, PowerSample, StatBucket, StatsSummary};

/// 时间范围定义：返回 (范围秒数, 桶秒数, 标签格式)
fn range_config(range: &str) -> (i64, i64, &'static str) {
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

/// 计算指定时间范围内的耗电量（基于最后一个采样点）
/// 包含 start 之前的最后一个采样点作为基准，避免丢失首个差值
fn consumption_in_range(samples: &[PowerSample], secs: i64) -> f64 {
    if samples.len() < 2 {
        return 0.0;
    }
    let last_ts = samples.last().unwrap().timestamp;
    let start = last_ts - secs;
    // 找到 start 之前的最后一个采样点作为基准
    let mut chain: Vec<&PowerSample> = samples
        .iter()
        .filter(|s| s.timestamp < start)
        .last()
        .map(|s| vec![s])
        .unwrap_or_default();
    chain.extend(samples.iter().filter(|s| s.timestamp >= start));
    if chain.len() < 2 {
        return 0.0;
    }
    // 累加相邻差值（只算下降部分）
    let mut total = 0.0;
    for i in 1..chain.len() {
        let diff = chain[i - 1].remaining_kwh - chain[i].remaining_kwh;
        if diff > 0.0 {
            total += diff;
        }
    }
    total
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
    // 遍历相邻采样点对，找到它们之间的空桶并分摊
    for i in 1..in_range.len() {
        let prev = in_range[i - 1];
        let curr = in_range[i];
        let diff = prev.remaining_kwh - curr.remaining_kwh;
        if diff <= 0.0 {
            continue; // 上升（充值）或不变，不分摊
        }
        let prev_bucket_idx = buckets
            .iter()
            .position(|b| b.timestamp <= prev.timestamp && prev.timestamp < b.timestamp + bucket_secs);
        let curr_bucket_idx = buckets
            .iter()
            .position(|b| b.timestamp <= curr.timestamp && curr.timestamp < b.timestamp + bucket_secs);
        let (Some(pi), Some(ci)) = (prev_bucket_idx, curr_bucket_idx) else {
            continue;
        };
        if ci <= pi {
            continue;
        }
        let gap = (ci - pi) as f64;
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

    let hour_cons = consumption_in_range(samples, 3600);
    let day_cons = consumption_in_range(samples, 86_400);
    let week_cons = consumption_in_range(samples, 7 * 86_400);
    let fifteen_cons = consumption_in_range(samples, 15 * 86_400);
    let sixteen_cons = consumption_in_range(samples, 16 * 86_400);
    let thirty_cons = consumption_in_range(samples, 30 * 86_400);
    let minute_cons = consumption_in_range(samples, 60);

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
