//! 模板引擎的公共底料：HTML 转文本、实体解码、金额/日期/摘要识别。
//!
//! 刻意不用 DOM 解析器：账单邮件是"表格套表格"的畸形 HTML，
//! DOM 路径一旦银行改版就全断；把 HTML 拉平成文本行再按语义抓，
//! 抗改版能力远强于按节点寻址。

use lazy_static::lazy_static;
use regex::{Regex, RegexBuilder};

use crate::types::{DIRECTION_EXPENSE, DIRECTION_INCOME};

lazy_static! {
    /// 金额：可带负号、千分位，必须带小数。
    /// 强制小数是为了不把积分(282)、卡号段这类裸整数当钱 —— 银行账单金额永远是两位小数。
    static ref AMOUNT: Regex =
        Regex::new(r"(-)?\s*(\d{1,3}(?:,\d{3})*|\d+)\.(\d{1,2})").unwrap();
    /// 币种前缀
    static ref CURRENCY: Regex = Regex::new(r"(?i)\b(CNY|USD|EUR|GBP|JPY|HKD|TWD|AUD|CAD)\b").unwrap();
    static ref SYMBOL: Regex = Regex::new(r"[￥¥$€£]").unwrap();
    /// 记账日期：`2026-08-29` / `2026/08/29` / `2026年8月29日`
    static ref DATE_ISO: Regex = Regex::new(r"(\d{4})[-/年]\s*(\d{1,2})[-/月]\s*(\d{1,2})日?").unwrap();
    /// 时分秒或时分
    static ref TIME_HMS: Regex = Regex::new(r"(\d{1,2}):(\d{2})(?::(\d{2}))?").unwrap();
    /// 尾号：`尾号0001` / `尾号 ****1234`
    static ref CARD_TAIL: Regex = Regex::new(r"尾\s*号\s*[:：]?\s*(\d{3,4}|\*{3,4}\d{3,4})").unwrap();
    /// 表头噪声行
    static ref HEADER_NOISE: Regex =
        Regex::new(r"(交易时间|记账日期|交易日期|金额|币种|摘要|说明|类型|商户|序号)").unwrap();
    static ref WS: Regex = Regex::new(r"[ \t\r\n\u{000b}\u{000c}]+").unwrap();
}

/// 文本里读到的一个金额
#[derive(Debug, Clone)]
pub struct AmountToken {
    pub currency: String,
    pub value: f64,
    pub negative: bool,
    pub raw: String,
}

/// HTML 实体解码：只处理邮件里真实出现的那些，外加数字实体。
pub fn decode_entities(input: &str) -> String {
    const TABLE: &[(&str, &str)] = &[
        ("nbsp", "\u{00A0}"),
        ("thinsp", " "),
        ("ensp", " "),
        ("emsp", " "),
        ("amp", "&"),
        ("lt", "<"),
        ("gt", ">"),
        ("quot", "\""),
        ("apos", "'"),
        ("middot", "·"),
        ("mdash", "—"),
        ("ndash", "–"),
        ("hellip", "…"),
        ("deg", "°"),
        ("times", "×"),
    ];
    let bytes = input.as_bytes();
    let mut out = String::with_capacity(input.len());
    let mut i = 0usize;
    while i < bytes.len() {
        if bytes[i] != b'&' {
            let start = i;
            while i < bytes.len() && bytes[i] != b'&' {
                i += 1;
            }
            // '&' 是 ASCII，绝不会出现在多字节序列中间，所以这里切片必在字符边界上
            out.push_str(&input[start..i]);
            continue;
        }
        let rest = &input[i..];
        let semi = match rest.find(';') {
            Some(pos) if pos <= 10 => pos,
            _ => {
                out.push('&');
                i += 1;
                continue;
            }
        };
        let name = &rest[1..semi];
        if let Some((_, decoded)) = TABLE.iter().find(|(k, _)| *k == name) {
            out.push_str(decoded);
            i += semi + 1;
            continue;
        }
        let hex = name
            .strip_prefix("#x")
            .or_else(|| name.strip_prefix("#X"))
            .and_then(|h| u32::from_str_radix(h, 16).ok())
            .or_else(|| name.strip_prefix('#').and_then(|d| d.parse::<u32>().ok()));
        match hex.and_then(char::from_u32) {
            Some(c) => {
                out.push(c);
                i += semi + 1;
            }
            // 认不出的实体原样留着，不做二次猜测
            None => {
                out.push('&');
                i += 1;
            }
        }
    }
    out
}

/// 去掉 style/script/注释块：这些块里的文字不是给人看的明细
fn drop_invisible(html: &str) -> String {
    // 必须用 to_ascii_lowercase：to_lowercase 会改变某些字符的字节长度，
    // 之后按下标切片就会错位切进多字节字符里。
    let lower = html.to_ascii_lowercase();
    let mut out = String::with_capacity(html.len());
    let mut i = 0usize;
    while i < lower.len() {
        if lower[i..].starts_with("<!--") {
            i = match lower[i..].find("-->") {
                Some(rel) => i + rel + 3,
                None => lower.len(),
            };
            continue;
        }
        match find_block_start(&lower, i) {
            Some((start, end)) => {
                out.push_str(&html[i..start]);
                i = end;
            }
            None => {
                out.push_str(&html[i..]);
                break;
            }
        }
    }
    out
}

/// 找到紧随其后的 style/script 块，返回 (块起点, 块终点)
fn find_block_start(lower: &str, from: usize) -> Option<(usize, usize)> {
    let mut best: Option<(usize, usize)> = None;
    for tag in ["<style", "<script"] {
        if let Some(rel) = lower[from..].find(tag) {
            let start = from + rel;
            if best.map(|b| start < b.0).unwrap_or(true) {
                let close = format!("{}>", tag.replacen('<', "</", 1));
                let end = match lower[start..].find(&close) {
                    Some(rel2) => start + rel2 + close.len(),
                    None => lower.len(),
                };
                best = Some((start, end));
            }
        }
    }
    best
}

/// HTML 片段 → 纯文本：块级标签换行，其余标签丢弃，实体解码。
/// 换行是关键：招行把金额和摘要放在同一个 span 的两个 `<div>` 里，
/// 不插换行就会粘成 `CNY 17.10尾号0001 消费 …`。
pub fn html_to_text(html: &str) -> String {
    let cleaned = drop_invisible(html);
    let mut text = String::with_capacity(cleaned.len());
    let mut rest = cleaned.as_str();
    while let Some(pos) = rest.find('<') {
        text.push_str(&rest[..pos]);
        match rest[pos..].find('>') {
            Some(rel) => {
                if is_block_tag(&rest[pos + 1..pos + rel]) {
                    text.push('\n');
                }
                rest = &rest[pos + rel + 1..];
            }
            // 未闭合的 '<'：后面整段当文本，不再找 '>'
            None => rest = "",
        }
    }
    text.push_str(rest);
    decode_entities(&collapse_newlines(&text))
}

/// 块级标签成对出现会连出一串空行，压成一个；开头的换行直接丢，
/// 否则 `lines()` 会多出一个空行让上层误判。
fn collapse_newlines(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut prev_nl = true;
    for c in s.chars() {
        if c == '\n' {
            if !prev_nl {
                out.push('\n');
            }
            prev_nl = true;
        } else {
            out.push(c);
            prev_nl = false;
        }
    }
    out
}

fn is_block_tag(tag: &str) -> bool {
    let head = tag.trim_start_matches('/').split_whitespace().next().unwrap_or("");
    matches!(
        head,
        "br" | "div" | "p" | "tr" | "td" | "th" | "li" | "ul" | "ol" | "table" | "h1" | "h2" | "h3"
            | "h4" | "section" | "blockquote"
    )
}

/// 拉平空白：全角空格、`&nbsp;`(U+00A0) 都折成普通空格，方便正则
pub fn normalize_spaces(s: &str) -> String {
    let replaced = s.replace('\u{00A0}', " ").replace('\u{3000}', " ");
    WS.replace_all(&replaced, " ").trim().to_string()
}

/// 把日期/时间片段整段摘掉：它们各自是一列，留在摘要里就会被当成"交易类型"，
/// 方向判定跟着一起歪。
pub fn strip_datetime(text: &str) -> String {
    let no_date = DATE_ISO.replace_all(text, " ");
    let no_time = TIME_HMS.replace_all(&no_date, " ");
    normalize_spaces(&no_time)
}

/// 按 `<span id="前缀` 切片，返回 (首段, 每段正文)。
/// 尾缀是银行每次渲染随机的串，所以只认前缀；每段以该 marker 开头。
pub fn split_by_marker(html: &str, marker: &str) -> (String, Vec<String>) {
    let pat = format!("<span id=\"{}", marker);
    let positions = find_all(html, pat.as_bytes());
    let head = positions
        .first()
        .map(|p| html[..*p].to_string())
        .unwrap_or_else(|| html.to_string());
    let mut chunks = Vec::with_capacity(positions.len());
    for idx in 0..positions.len() {
        let start = positions[idx];
        let end = positions.get(idx + 1).copied().unwrap_or(html.len());
        chunks.push(html[start..end].to_string());
    }
    (head, chunks)
}

/// 逐字节查找所有出现位置（pattern 为 ASCII，边界安全）
fn find_all(hay: &str, needle: &[u8]) -> Vec<usize> {
    let bytes = hay.as_bytes();
    let mut out = Vec::new();
    if needle.is_empty() || bytes.len() < needle.len() {
        return out;
    }
    let mut i = 0usize;
    while i + needle.len() <= bytes.len() {
        if &bytes[i..i + needle.len()] == needle {
            out.push(i);
            i += needle.len();
        } else {
            i += 1;
        }
    }
    out
}

/// 把片段按 `<span id="…">` 拆成单元格：返回 (id 前缀, 纯文本)。
///
/// id 形如 `fixBand5_A9wP_5`，中段是每次渲染随机的串，所以只取第一个 `_` 之前的
/// `fixBand5` 作前缀；单元格正文按"到下一个 id 标记为止"切，天然把行尾之后的
/// 页脚内容排除掉。
pub fn cells_by_id_prefix(fragment: &str) -> Vec<(String, String)> {
    let open = b"<span id=\"";
    let positions = find_all(fragment, open);
    let mut out = Vec::with_capacity(positions.len());
    for (idx, pos) in positions.iter().enumerate() {
        let id_start = pos + open.len();
        let id_end = match fragment[id_start..].find('"') {
            Some(rel) => id_start + rel,
            None => continue,
        };
        let key = fragment[id_start..id_end]
            .split('_')
            .next()
            .unwrap_or("")
            .to_ascii_lowercase();
        if key.is_empty() {
            continue;
        }
        let body_start = match fragment[id_end..].find('>') {
            Some(rel) => id_end + rel + 1,
            None => continue,
        };
        let body_end = positions.get(idx + 1).copied().unwrap_or(fragment.len());
        if body_start >= body_end {
            continue;
        }
        out.push((key, html_to_text(&fragment[body_start..body_end])));
    }
    out
}

/// 从一段文本里抓金额；返回 None 表示这段里没有任何"像钱"的数。
/// 逐个候选试，跳过被更长数字包住的匹配 —— `2026.08.29` 这类点分日期
/// 会被 `\d+\.\d{1,2}` 咬走，不挡就把年份当金额入账。
pub fn extract_amount(text: &str) -> Option<AmountToken> {
    for m in AMOUNT.find_iter(text) {
        let matched = m.as_str();
        let before = &text[..m.start()];
        let after = &text[m.end()..];
        if before.chars().last().map(|c| c.is_ascii_digit() || c == '.').unwrap_or(false) {
            continue;
        }
        if after.starts_with('.') || after.starts_with(|c: char| c.is_ascii_digit()) {
            continue;
        }
        // 负号在匹配串的最前面，split_once 会把空串当"前段"，判负只能看首字符
        let negative = matched.starts_with('-');
        let body = matched.trim_start_matches('-').trim_start();
        let (grouped, decimals) = split_once_decimal(body)?;
        let plain: String = grouped.chars().filter(|c| *c != ',').collect();
        let value: f64 = format!("{}.{}", plain, decimals).parse().ok()?;
        if value <= 0.0 {
            continue;
        }
        let currency = CURRENCY
            .captures(before)
            .and_then(|c| c.get(1))
            .map(|c| c.as_str().to_uppercase())
            .or_else(|| SYMBOL.find(before).map(|_| "CNY".to_string()))
            .unwrap_or_else(|| "CNY".to_string());
        return Some(AmountToken {
            currency,
            value,
            negative,
            raw: normalize_spaces(matched),
        });
    }
    None
}

/// `50,000.00` → ("50,000", "00")
fn split_once_decimal(body: &str) -> Option<(&str, &str)> {
    let dot = body.rfind('.')?;
    let decimals = body.len() - dot - 1;
    if !(1..=2).contains(&decimals) {
        return None;
    }
    Some((&body[..dot], &body[dot + 1..]))
}

/// 抓日期，输出 `YYYY-MM-DD`
pub fn extract_date(text: &str) -> Option<String> {
    let caps = DATE_ISO.captures(text)?;
    let year: i32 = caps.get(1)?.as_str().parse().ok()?;
    let month: u32 = caps.get(2)?.as_str().parse().ok()?;
    let day: u32 = caps.get(3)?.as_str().parse().ok()?;
    if !(1980..=2200).contains(&year) || !(1..=12).contains(&month) || !(1..=31).contains(&day) {
        return None;
    }
    Some(format!("{:04}-{:02}-{:02}", year, month, day))
}

/// 抓时间，输出 `HH:MM:SS`
pub fn extract_time(text: &str) -> Option<String> {
    let caps = TIME_HMS.captures(text)?;
    let h: u32 = caps.get(1)?.as_str().parse().ok()?;
    let min: u32 = caps.get(2)?.as_str().parse().ok()?;
    let sec: u32 = caps.get(3).and_then(|c| c.as_str().parse().ok()).unwrap_or(0);
    if h > 23 || min > 59 || sec > 59 {
        return None;
    }
    Some(format!("{:02}:{:02}:{:02}", h, min, sec))
}

/// 抓卡号尾号
pub fn extract_card_tail(text: &str) -> String {
    CARD_TAIL
        .captures(text)
        .and_then(|c| c.get(1))
        .map(|c| c.as_str().chars().filter(|ch| ch.is_ascii_digit()).collect())
        .unwrap_or_default()
}

/// 收入类交易类型关键字：命中即按收入记
pub const INCOME_TYPES: &[&str] = &["退款", "退货", "冲正", "撤销", "溢缴款", "存入", "利息收入", "贷记"];

/// 已知的支出类交易类型：不在表内也照支出记，但要吼一声
pub const KNOWN_EXPENSE_TYPES: &[&str] = &[
    "消费", "取现", "提现", "分期", "利息", "费用", "年费", "违约金", "逾期", "手续费", "购物", "还款", "转账", "扣费",
    "支付",
];

/// 交易类型 → 方向；返回 (方向, 警告)
pub fn classify_direction(entry_type: &str, negative: bool) -> (String, Option<String>) {
    let hit_income = INCOME_TYPES.iter().any(|k| !entry_type.is_empty() && entry_type.contains(k));
    if hit_income || negative {
        return (DIRECTION_INCOME.to_string(), None);
    }
    let known = KNOWN_EXPENSE_TYPES.iter().any(|k| !entry_type.is_empty() && entry_type.contains(k));
    let warn = if entry_type.is_empty() {
        Some("未识别出交易类型，按支出入账，请人工核对".to_string())
    } else if !known {
        Some(format!("未识别的交易类型「{}」，已按支出入账，请人工核对", entry_type))
    } else {
        None
    };
    (DIRECTION_EXPENSE.to_string(), warn)
}

/// `尾号0001 消费 示例支付-…` → (尾号, 类型, 商户)
/// 三段式是招行（及多数国内银行）账单的稳定写法。
pub fn split_description(desc: &str) -> (String, String, String) {
    let tail = extract_card_tail(desc);
    // 先把"尾号XXXX"整段摘掉，再按空白切类型/商户
    let without_tail = CARD_TAIL.replace_all(desc, " ").to_string();
    let mut parts = without_tail.split_whitespace().map(str::trim).filter(|p| !p.is_empty());
    let entry_type = parts.next().unwrap_or("").to_string();
    let merchant = parts.collect::<Vec<_>>().join(" ");
    (tail, entry_type, merchant)
}

/// 商户名清洗：银行按定宽截断，末尾常留一个没闭合的括号
pub fn tidy_merchant(merchant: &str) -> String {
    let mut m = normalize_spaces(merchant);
    for (open, close) in [("（", "）"), ("(", ")"), ("【", "】"), ("[", "]")] {
        if m.matches(open).count() > m.matches(close).count() {
            if let Some(pos) = m.rfind(open) {
                m = m[..pos].trim_end().to_string();
            }
        }
    }
    m
}

/// 是否表头/说明噪声行
pub fn looks_like_header(line: &str) -> bool {
    let norm = normalize_spaces(line);
    if norm.is_empty() {
        return true;
    }
    HEADER_NOISE.is_match(&norm) && extract_amount(&norm).is_none()
}

/// 大小写不敏感 + 多行的正则构造（自定义模板用）
pub fn build_regex(pattern: &str) -> Option<Regex> {
    RegexBuilder::new(pattern)
        .case_insensitive(true)
        .multi_line(true)
        .build()
        .ok()
}

/// 组装 `YYYY-MM-DD HH:MM:SS`；缺日期时只给时间，由入账编排补默认日期
pub fn assemble_datetime(date: &str, time: &str) -> String {
    if date.is_empty() {
        return time.to_string();
    }
    if time.is_empty() {
        return format!("{} 00:00:00", date);
    }
    format!("{} {}", date, time)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decode_entities_common_forms() {
        assert_eq!(decode_entities("A&nbsp;B"), "A\u{00A0}B");
        assert_eq!(decode_entities("1 &lt; 2 &amp;&amp; 3"), "1 < 2 && 3");
        assert_eq!(decode_entities("&#20013;文&#x6587;"), "中文文");
        assert_eq!(decode_entities("A & B"), "A & B");
        assert_eq!(decode_entities("&notanentity;"), "&notanentity;");
    }

    #[test]
    fn block_tags_become_newlines() {
        let text = html_to_text("<div>CNY&nbsp;17.10</div><div>尾号0001&nbsp;消费&nbsp;示例商户</div>");
        let lines: Vec<String> = text.lines().map(normalize_spaces).collect();
        assert_eq!(lines, vec!["CNY 17.10", "尾号0001 消费 示例商户"]);
    }

    #[test]
    fn amount_requires_decimals() {
        let a = extract_amount("CNY&nbsp;17.10").unwrap();
        assert_eq!((a.currency.as_str(), a.value, a.negative), ("CNY", 17.10, false));
        let b = extract_amount("CNY -33.00").unwrap();
        assert_eq!((b.value, b.negative), (33.00, true));
        let c = extract_amount("可用额度 ￥50,000.00").unwrap();
        assert_eq!((c.currency.as_str(), c.value), ("CNY", 50000.00));
        // 裸整数不是钱：积分、卡号段都不该被抓走
        assert!(extract_amount("积分余额 282").is_none());
        assert!(extract_amount("00:09:22").is_none());
    }

    #[test]
    fn description_three_parts() {
        // 生产链路里摘要已经过 html_to_text + normalize_spaces，这里保持一致
        let raw = "<div>尾号0001&nbsp;消费&nbsp;示例支付-外卖平台示例烧烤店（示例分舵</div>";
        let line = normalize_spaces(&html_to_text(raw));
        let (tail, kind, merchant) = split_description(&line);
        assert_eq!(tail, "0001");
        assert_eq!(kind, "消费");
        assert_eq!(tidy_merchant(&merchant), "示例支付-外卖平台示例烧烤店");
    }

    #[test]
    fn date_and_time_reading() {
        assert_eq!(extract_date("2026/08/29 您的消费明细如下：").as_deref(), Some("2026-08-29"));
        assert_eq!(extract_date("2026年8月2日").as_deref(), Some("2026-08-02"));
        assert_eq!(extract_time("00:09:22").as_deref(), Some("00:09:22"));
        assert_eq!(extract_time("8:15").as_deref(), Some("08:15:00"));
        assert_eq!(assemble_datetime("2026-08-29", "08:15:34"), "2026-08-29 08:15:34");
        assert_eq!(assemble_datetime("", "08:15:34"), "08:15:34");
        assert_eq!(assemble_datetime("2026-08-29", ""), "2026-08-29 00:00:00");
    }

    #[test]
    fn direction_and_unknown_warning() {
        assert_eq!(classify_direction("退货", false).0, DIRECTION_INCOME);
        assert_eq!(classify_direction("消费", true).0, DIRECTION_INCOME);
        assert!(classify_direction("神秘类型", false).1.is_some());
        assert!(classify_direction("消费", false).1.is_none());
    }

    #[test]
    fn marker_split_keeps_every_chunk() {
        let html = "head<span id=\"fixBand4_x_4\">A</span>mid<span id=\"fixBand4_y_4\">B</span>";
        let (head, chunks) = split_by_marker(html, "fixBand4");
        assert_eq!(head, "head");
        assert_eq!(chunks.len(), 2);
        assert!(chunks[0].contains(">A</span>"));
        assert!(chunks[1].contains(">B</span>"));
    }
}
