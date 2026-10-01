//! 账单模板引擎：把邮件正文解析成 ParseResult。
//!
//! 三条铁律：
//! 1. 抓不到就报错或写 warnings，绝不允许"解析成功但 0 笔"这种静默漏记；
//! 2. 只认稳定特征（band 前缀、"尾号XXXX 类型 商户"三段式），不认整段 DOM 路径；
//! 3. 方向判定靠交易类型 + 金额正负，未知类型必须留警告。

use serde::Deserialize;

use crate::parse_glue::{ParsedTx, ParseResult};
use crate::parser_types as pt;

// 行容器在 HTML 里是 `fixBand4`（大小写不敏感匹配），单元格 id 归一化后是
// `fixband5`（时间）、`fixband12`（金额 + 摘要）；随机中段不参与匹配。
const CMB_TIME_BAND: &str = "fixband5";
const CMB_DETAIL_BAND: &str = "fixband12";

/// 统一的模板入口清单
pub fn template_ids() -> Vec<String> {
    vec![
        "cmb_daily_bill".to_string(),
        "generic_keyword".to_string(),
        "custom_regex".to_string(),
    ]
}

// ── 招商银行信用卡每日账单 ───────────────────────────────────────────────────

pub fn parse_cmb_daily_bill(html: &str) -> Result<ParseResult, String> {
    let (head, rows) = pt::split_by_marker(html, "fixBand4");
    // fixBand4 在两种版式里都存在（月度账单里它只是页脚的一个容器，不是明细行），
    // 光看容器在不在选不对分支：先按每日版式试，谁能真解析出笔数就听谁的。
    let daily_err = if rows.is_empty() {
        "没有 fixBand4 明细行容器".to_string()
    } else {
        match parse_cmb_daily_rows(&head, &rows) {
            Ok(result) => return Ok(result),
            Err(e) => e,
        }
    };
    parse_cmb_statement(html).map_err(|e| format!("{}（每日版式：{}）", e, daily_err))
}

/// 每日账单（fixBand4 行容器 + 带 id 的单元格）
fn parse_cmb_daily_rows(head: &str, rows: &[String]) -> Result<ParseResult, String> {
    let head_text = pt::html_to_text(head);
    let bill_date = pt::extract_date(&head_text).unwrap_or_default();
    let available_credit = extract_after_keyword(&head_text, "可用额度").and_then(|s| pt::extract_amount(&s).map(|a| a.value));
    let points_balance = extract_after_keyword(&head_text, "积分余额")
        .and_then(|s| s.chars().skip_while(|c| !c.is_ascii_digit()).take_while(|c| c.is_ascii_digit()).collect::<String>().parse::<i64>().ok());

    let mut result = ParseResult {
        template_id: "cmb_daily_bill".to_string(),
        bill_date: bill_date.clone(),
        available_credit,
        points_balance,
        ..Default::default()
    };
    if bill_date.is_empty() {
        result.warnings.push("账单头部没读到账单日期，流水日期将退回邮件接收日期".to_string());
    }

    for (idx, row) in rows.iter().enumerate() {
        let cells = pt::cells_by_id_prefix(row);
        let time = cells
            .iter()
            .find(|(k, _)| k == CMB_TIME_BAND)
            .and_then(|(_, text)| first_line_with(text, |line| pt::extract_time(line)))
            .unwrap_or_default();
        let detail = cells
            .iter()
            .find(|(k, _)| k == CMB_DETAIL_BAND)
            .map(|(_, text)| text.clone())
            .unwrap_or_default();

        let amount = first_line_with(&detail, |line| pt::extract_amount(line));
        let Some(amount) = amount else {
            // 明细单元里没有金额：要么这行不是交易（表头/说明），要么银行改了写法。
            // 两种情况都要留痕，不能装作这行不存在。
            let snippet = pt::normalize_spaces(&detail).chars().take(60).collect::<String>();
            if !snippet.is_empty() {
                result.warnings.push(format!("第 {} 行未识别到金额，已跳过：{}", idx + 1, snippet));
            }
            continue;
        };

        let description = detail
            .lines()
            .map(pt::normalize_spaces)
            .find(|line| line.contains("尾号") || line.contains("尾 号"))
            .unwrap_or_default();
        let (card_tail, entry_type, merchant_raw) = pt::split_description(&description);
        let merchant = pt::tidy_merchant(&merchant_raw);
        let (direction, warn) = pt::classify_direction(&entry_type, amount.negative);
        if let Some(warn) = warn {
            result.warnings.push(warn);
        }
        if merchant.is_empty() {
            result.warnings.push(format!("第 {} 行有金额但没抓到商户，摘要原文：{}", idx + 1, description));
        }

        result.transactions.push(ParsedTx {
            time: time.clone(),
            datetime: pt::assemble_datetime(&bill_date, &time),
            currency: amount.currency,
            amount: amount.value,
            raw_amount: amount.raw,
            description,
            card_tail,
            entry_type,
            merchant,
            direction,
        });
    }

    if result.transactions.is_empty() {
        return Err(format!("命中了招行账单模板但一笔都没解析出来（共 {} 行），请先用预览核对模板", rows.len()));
    }
    Ok(result)
}

/// 2026 版月度电子账单：明细行一个单元格 id 都没有、表头整排是图片，
/// 能靠的只有列的相对顺序 `交易日 | 入账日 | 摘要 | 交易金额 | 卡号末四位 | 币种 | 人民币金额`。
///
/// 列位从行尾倒推而不是写死下标：招行习惯在明细前后留空白格，
/// 多一列就会让写死的下标整体错位、把金额读成卡号。
/// 入账取人民币金额列（外币行银行已折算），币种列不参与记账；
/// 日期只有 MMDD，年份靠账单期间补。
struct StmtCols {
    trade: usize,
    post: usize,
    desc: usize,
    txn: usize,
    card: usize,
    cny: usize,
}

/// 校验这一行是不是明细行；不是就 None（表头、说明、小计都走这条路被挡掉）。
/// 顺带把人民币金额解出来，省得调用方再解析一遍。
fn stmt_columns(cells: &[String]) -> Option<(StmtCols, pt::AmountToken)> {
    // 人民币金额是行里最后一个金额列，它右边不该再有"像钱"的格
    let cny = cells.iter().rposition(|c| pt::extract_amount(c).is_some())?;
    if cny < 6 {
        return None;
    }
    let cols = StmtCols {
        trade: cny - 6,
        post: cny - 5,
        desc: cny - 4,
        txn: cny - 3,
        card: cny - 2,
        cny,
    };
    // 交易金额列必须也是钱：七列表格不止明细有，缺这一眼就说明不是交易行
    if pt::extract_amount(&cells[cols.txn]).is_none() {
        return None;
    }
    if cells[cols.desc].is_empty() {
        return None;
    }
    // 日期列要么空（还款行），要么是 MMDD；两个都空说明读错了列
    if pick_date_cell(&cells[cols.trade], &cells[cols.post]).is_none() {
        return None;
    }
    let amount = pt::extract_amount(&cells[cols.cny])?;
    Some((cols, amount))
}

fn parse_cmb_statement(html: &str) -> Result<ParseResult, String> {
    let text = pt::html_to_text(html);
    let period = pt::extract_period(&text);
    let bill_date = period.as_ref().map(|(_, end)| end.clone()).unwrap_or_default();
    let mut result = ParseResult {
        template_id: "cmb_daily_bill".to_string(),
        bill_date,
        ..Default::default()
    };
    if period.is_none() {
        result.warnings.push("没读到账单期间，明细行的 MMDD 无法补年份，流水日期将退回邮件接收日期".to_string());
    }

    let (period_start, period_end) = period.unwrap_or_default();
    let mut unknown_type = 0usize;
    let mut near_miss = 0usize;
    for cells in pt::table_rows(html) {
        let Some((cols, amount)) = stmt_columns(&cells) else {
            // 格数够多却对不上列形的行要留数：改版往往就是这个形状
            // （额度、最低还款那些汇总行只有几列，不该跟着一起喊）
            if cells.len() >= 7 {
                near_miss += 1;
            }
            continue;
        };
        let desc = cells[cols.desc].clone();
        let date = match pick_date_cell(&cells[cols.trade], &cells[cols.post]) {
            Some(mmdd) => pt::expand_mmdd(&mmdd, &period_start, &period_end).unwrap_or_default(),
            None => String::new(),
        };
        let entry_type = stmt_entry_type(&desc);
        if entry_type.is_empty() {
            unknown_type += 1;
        }
        let (direction, _) = pt::classify_direction(&entry_type, amount.negative);

        result.transactions.push(ParsedTx {
            time: String::new(),
            datetime: pt::assemble_datetime(&date, ""),
            currency: "CNY".to_string(),
            amount: amount.value,
            raw_amount: amount.raw,
            description: desc.clone(),
            card_tail: digits_of(&cells[cols.card]),
            entry_type,
            merchant: pt::tidy_merchant(&desc),
            direction,
        });
    }

    if unknown_type > 0 {
        result.warnings.push(format!("{} 行的摘要里没有已知交易类型，已按金额正负判定方向，请抽查", unknown_type));
    }
    if near_miss > 0 {
        result.warnings.push(format!("{} 行像明细行但列形对不上，已跳过；若确实漏了流水，请用预览核对列序", near_miss));
    }
    if result.transactions.is_empty() {
        return Err(format!(
            "没找到招行账单明细行：既没有 fixBand4 行容器，也没有列形对得上的明细表格（候选行 {} 行），招行的邮件模板可能已改版",
            near_miss
        ));
    }
    Ok(result)
}

/// 还款、费用这类行没有交易日，只有入账日
fn pick_date_cell(trade: &str, post: &str) -> Option<String> {
    [trade, post]
        .into_iter()
        .map(pt::normalize_spaces)
        .find(|c| c.len() == 4 && c.chars().all(|ch| ch.is_ascii_digit()))
}

fn digits_of(cell: &str) -> String {
    let digits: String = cell.chars().filter(|c| c.is_ascii_digit()).collect();
    // 只认 3~4 位的末四位：招行这一列就是 4 位，长了说明读错了列
    if (3..=4).contains(&digits.len()) { digits } else { String::new() }
}

/// 摘要里能认出的第一个交易类型词；认不出留空，由方向判定兜底
fn stmt_entry_type(desc: &str) -> String {
    for k in pt::INCOME_TYPES.iter().chain(pt::KNOWN_EXPENSE_TYPES.iter()) {
        if desc.contains(*k) {
            return (*k).to_string();
        }
    }
    String::new()
}

/// 在正文里定位关键字，返回关键字之后的内容（用于"可用额度 ￥50,000.00"这类标签-数值对）
fn extract_after_keyword(text: &str, keyword: &str) -> Option<String> {
    let pos = text.find(keyword)?;
    Some(text[pos + keyword.len()..].chars().take(40).collect())
}

/// 逐行试解析，取第一个成功的结果
fn first_line_with<T>(text: &str, f: impl Fn(&str) -> Option<T>) -> Option<T> {
    text.lines().map(str::trim).filter(|l| !l.is_empty()).find_map(f)
}

// ── 通用关键字模板 ───────────────────────────────────────────────────────────

/// 关键字模板配置：全部字段可省略，省略即走默认识别
#[derive(Debug, Clone, Default, Deserialize)]
pub struct GenericConfig {
    /// 行内出现任一关键词才视为交易行
    #[serde(default)]
    pub include_keywords: Vec<String>,
    /// 命中即丢弃该行（表头、说明、免责声明）
    #[serde(default)]
    pub exclude_keywords: Vec<String>,
    /// 覆盖默认金额正则（必须含 1~2 位小数）
    #[serde(default)]
    pub amount_pattern: String,
    /// 覆盖默认日期正则
    #[serde(default)]
    pub date_pattern: String,
    /// 视为收入关键词（叠加在内置收入词表之上）
    #[serde(default)]
    pub income_keywords: Vec<String>,
    /// 跳过表头样式行
    #[serde(default = "default_true")]
    pub skip_header_lines: bool,
}

fn default_true() -> bool {
    true
}

pub fn parse_generic_keyword(body: &str, config_json: &str) -> Result<ParseResult, String> {
    let cfg: GenericConfig = parse_config(config_json)?;
    let text = if body.contains('<') { pt::html_to_text(body) } else { body.to_string() };
    let amount_re = if cfg.amount_pattern.trim().is_empty() {
        None
    } else {
        Some(pt::build_regex(cfg.amount_pattern.trim()).ok_or_else(|| format!("金额正则无法编译：{}", cfg.amount_pattern))?)
    };
    let date_re = if cfg.date_pattern.trim().is_empty() {
        None
    } else {
        Some(pt::build_regex(cfg.date_pattern.trim()).ok_or_else(|| format!("日期正则无法编译：{}", cfg.date_pattern))?)
    };

    let mut result = ParseResult {
        template_id: "generic_keyword".to_string(),
        ..Default::default()
    };
    result.bill_date = pt::extract_date(&text).unwrap_or_default();

    for raw_line in text.lines() {
        let line = pt::normalize_spaces(raw_line);
        if line.is_empty() {
            continue;
        }
        if cfg.skip_header_lines && pt::looks_like_header(&line) {
            continue;
        }
        if cfg.exclude_keywords.iter().any(|k| !k.trim().is_empty() && line.contains(k.trim())) {
            continue;
        }
        if !cfg.include_keywords.is_empty()
            && !cfg.include_keywords.iter().any(|k| !k.trim().is_empty() && line.contains(k.trim()))
        {
            continue;
        }
        let Some(amount) = pick_amount(&line, amount_re.as_ref()) else {
            if !cfg.include_keywords.is_empty() {
                result.warnings.push(format!("命中关键词但没有金额，已跳过：{}", line.chars().take(60).collect::<String>()));
            }
            continue;
        };
        let date = pick_date(&line, date_re.as_ref()).unwrap_or_else(|| result.bill_date.clone());
        let time = pt::extract_time(&line).unwrap_or_default();
        let (card_tail, entry_type, merchant) = describe_line(&line, &amount);
        let income_hit = cfg.income_keywords.iter().any(|k| !k.trim().is_empty() && line.contains(k.trim()));
        let (mut direction, warn) = pt::classify_direction(&entry_type, amount.negative);
        if income_hit {
            direction = crate::types::DIRECTION_INCOME.to_string();
        }
        if let Some(warn) = warn {
            result.warnings.push(format!("{}（行：{}）", warn, line.chars().take(60).collect::<String>()));
        }
        result.transactions.push(ParsedTx {
            time: time.clone(),
            datetime: pt::assemble_datetime(&date, &time),
            currency: amount.currency,
            amount: amount.value,
            raw_amount: amount.raw,
            description: line.clone(),
            card_tail,
            entry_type,
            merchant,
            direction,
        });
    }

    if result.transactions.is_empty() {
        return Err("通用关键字模板没有解析到任何带金额的明细行：请调整关键词，或改用自定义正则模板".to_string());
    }
    Ok(result)
}

fn pick_amount(line: &str, re: Option<&regex::Regex>) -> Option<pt::AmountToken> {
    match re {
        Some(re) => re
            .find_iter(line)
            .find_map(|m| pt::extract_amount(m.as_str()).or_else(|| {
                let v: f64 = m.as_str().replace(',', "").parse().ok()?;
                if v <= 0.0 {
                    return None;
                }
                Some(pt::AmountToken {
                    currency: "CNY".to_string(),
                    value: v,
                    negative: v < 0.0,
                    raw: m.as_str().to_string(),
                })
            })),
        None => pt::extract_amount(line),
    }
}

fn pick_date(line: &str, re: Option<&regex::Regex>) -> Option<String> {
    match re {
        Some(re) => re.find(line).and_then(|m| pt::extract_date(m.as_str())),
        None => pt::extract_date(line),
    }
}

/// 去掉金额片段后按空白切列，尽量还原"类型 + 商户"
fn describe_line(line: &str, amount: &pt::AmountToken) -> (String, String, String) {
    let cleaned = pt::strip_datetime(&strip_amount_tokens(line, amount));
    let (tail, entry_type, merchant) = pt::split_description(&cleaned);
    (tail, entry_type, pt::tidy_merchant(&merchant))
}

/// 把金额与其币种标记从行里摘掉，剩下的才是摘要主体
fn strip_amount_tokens(line: &str, amount: &pt::AmountToken) -> String {
    let mut rest = line.replace(&amount.raw, " ");
    for form in [amount.currency.to_uppercase(), amount.currency.to_lowercase()] {
        if rest.contains(&form) {
            rest = rest.replace(&form, " ");
        }
    }
    for sym in ["￥", "¥", "$", "€", "£"] {
        rest = rest.replace(sym, " ");
    }
    rest
}

// ── 自定义正则模板 ───────────────────────────────────────────────────────────

/// 一条带命名组的正则吃一行：`date`/`time`/`amount`/`type`/`merchant`/`card` 可选，
/// 其中只有 `amount` 是必需的。
#[derive(Debug, Clone, Deserialize)]
pub struct RegexConfig {
    pub pattern: String,
    #[serde(default)]
    pub currency: String,
    /// 命中的金额是否已经是负数形式（如 -33.00 表示收入）
    #[serde(default = "default_true")]
    pub treat_negative_as_income: bool,
}

pub fn parse_custom_regex(body: &str, config_json: &str) -> Result<ParseResult, String> {
    let cfg: RegexConfig = serde_json::from_str(config_json.trim())
        .map_err(|e| format!("自定义正则配置解析失败：{}", e))?;
    if cfg.pattern.trim().is_empty() {
        return Err("自定义正则模板缺少 pattern".to_string());
    }
    let re = pt::build_regex(cfg.pattern.trim()).ok_or_else(|| format!("正则无法编译：{}", cfg.pattern))?;
    // 用户没写 type 组时，"类型未知"的警告不该每行都喊一遍
    let has_type_group = cfg.pattern.contains("<type>");
    let text = if body.contains('<') { pt::html_to_text(body) } else { body.to_string() };

    let mut result = ParseResult {
        template_id: "custom_regex".to_string(),
        ..Default::default()
    };
    let doc_date = pt::extract_date(&text).unwrap_or_default();
    result.bill_date = doc_date.clone();

    for caps in re.captures_iter(&text) {
        let grab = |name: &str| -> String {
            caps.name(name).map(|m| pt::normalize_spaces(m.as_str())).unwrap_or_default()
        };
        let amount_text = grab("amount");
        let Some(amount) = pt::extract_amount(&amount_text).or_else(|| {
            let v: f64 = amount_text.replace(',', "").parse().ok()?;
            if v == 0.0 {
                return None;
            }
            Some(pt::AmountToken {
                currency: if cfg.currency.is_empty() { "CNY".to_string() } else { cfg.currency.clone() },
                value: v.abs(),
                negative: v < 0.0,
                raw: amount_text.clone(),
            })
        }) else {
            result.warnings.push(format!("正则命中但没有可用金额（amount 组内容：\"{}\"）", amount_text));
            continue;
        };
        let raw_date = grab("date");
        let date = if raw_date.is_empty() {
            pt::extract_date(caps.get(0).map(|m| m.as_str()).unwrap_or("")).unwrap_or_default()
        } else {
            match pt::extract_date(&raw_date) {
                Some(d) => d,
                // MM-DD 这类缺年份的写法不能当日期用：留空，让入账层按邮件日期兜底
                None => {
                    result.warnings.push(format!("date 组不是完整日期：\"{}\"，已改用邮件日期", raw_date));
                    String::new()
                }
            }
        };
        let time = grab("time");
        let time = if time.is_empty() { String::new() } else { pt::extract_time(&time).unwrap_or_default() };
        let entry_type = grab("type");
        let mut merchant = grab("merchant");
        if merchant.is_empty() {
            merchant = grab("desc");
        }
        let card_tail = {
            let raw = grab("card");
            if raw.is_empty() {
                pt::extract_card_tail(&caps.get(0).map(|m| m.as_str()).unwrap_or(""))
            } else {
                raw.chars().filter(|c| c.is_ascii_digit()).collect()
            }
        };
        let negative_income = cfg.treat_negative_as_income && amount.negative;
        let (direction, warn) = if negative_income {
            (crate::types::DIRECTION_INCOME.to_string(), None)
        } else {
            pt::classify_direction(&entry_type, false)
        };
        if let Some(warn) = warn {
            if has_type_group || !entry_type.is_empty() {
                result.warnings.push(warn);
            }
        }
        let whole = pt::normalize_spaces(caps.get(0).map(|m| m.as_str()).unwrap_or(""));
        result.transactions.push(ParsedTx {
            time: time.clone(),
            datetime: pt::assemble_datetime(&date, &time),
            currency: amount.currency,
            amount: amount.value,
            raw_amount: amount.raw,
            description: whole,
            card_tail,
            entry_type,
            merchant: pt::tidy_merchant(&merchant),
            direction,
        });
    }

    if result.transactions.is_empty() {
        return Err(format!("自定义正则没有命中任何行：{}", cfg.pattern));
    }
    Ok(result)
}

/// 配置留空即用默认
fn parse_config<T>(config_json: &str) -> Result<T, String>
where
    T: serde::de::DeserializeOwned + Default,
{
    let trimmed = config_json.trim();
    if trimmed.is_empty() {
        return Ok(T::default());
    }
    serde_json::from_str(trimmed).map_err(|e| format!("模板配置解析失败：{}（原值：{}）", e, trimmed.chars().take(80).collect::<String>()))
}
