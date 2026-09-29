//! MIME / RFC822 解析：头部、编码词、multipart、传输编码、字符集。
//!
//! 只做邮件客户端需要的那一档：不追求 MIME 全规范，但对国内银行常踩的坑
//! （GBK/GB18030 主题、QP 折行、multipart 里嵌 message/rfc822）必须正确处理，
//! 否则主题匹配会莫名失败。

use base64::engine::general_purpose::STANDARD as B64;
use base64::Engine;
use lazy_static::lazy_static;
use regex::Regex;

use crate::types::EmailMessage;

lazy_static! {
    static ref ENCODED_WORD: Regex = Regex::new(r"=\?([^?]+)\?([BbQq])\?([^?]*)\?=").unwrap();
    static ref WORD_GAP: Regex = Regex::new(r"\?=\s+=\?").unwrap();
    static ref QP_SOFT: Regex = Regex::new(r"=\r?\n").unwrap();
    static ref ADDR: Regex = Regex::new(r"<\s*([^>]+?)\s*>").unwrap();
}

#[derive(Debug, Clone, Default)]
pub struct Mail {
    pub headers: Vec<(String, String)>,
    pub html: String,
    pub text: String,
}

impl Mail {
    pub fn header(&self, name: &str) -> String {
        header_of(&self.headers, name)
    }
}

pub fn header_of(headers: &[(String, String)], name: &str) -> String {
    let want = name.to_ascii_lowercase();
    headers
        .iter()
        .find(|(k, _)| k.to_ascii_lowercase() == want)
        .map(|(_, v)| v.clone())
        .unwrap_or_default()
}

/// 解析整封邮件原文
pub fn parse(raw: &[u8]) -> Mail {
    let (head, body) = split_head_body(raw);
    let headers = parse_headers(&head);
    let mut mail = Mail {
        headers,
        ..Default::default()
    };
    let mut html_parts: Vec<String> = Vec::new();
    let mut text_parts: Vec<String> = Vec::new();
    let ct = mail.header("content-type");
    let cte = mail.header("content-transfer-encoding");
    walk(&ct, &cte, &mut html_parts, &mut text_parts, body);
    // 同一封邮件里可能有多个 text 片段（inline 附件说明等），取最长的那个当正文：
    // 最短的往往只是"请在支持 HTML 的客户端查看"的提示行。
    mail.html = html_parts.into_iter().max_by_key(|s| s.len()).unwrap_or_default();
    mail.text = text_parts.into_iter().max_by_key(|s| s.len()).unwrap_or_default();
    mail
}

fn split_head_body(raw: &[u8]) -> (&[u8], &[u8]) {
    for pattern in [&b"\r\n\r\n"[..], &b"\n\n"[..]] {
        if let Some(pos) = find_sub(raw, pattern) {
            return (&raw[..pos], &raw[pos + pattern.len()..]);
        }
    }
    (raw, &[])
}

fn find_sub(hay: &[u8], needle: &[u8]) -> Option<usize> {
    if needle.is_empty() || hay.len() < needle.len() {
        return None;
    }
    hay.windows(needle.len()).position(|w| w == needle)
}

/// 头部：折行（continuation）合并、实体与 RFC2047 解码、键值切分
pub fn parse_headers(head: &[u8]) -> Vec<(String, String)> {
    let text = lossy_utf8(head);
    let mut out: Vec<(String, String)> = Vec::new();
    for line in text.split('\n') {
        let line = line.trim_end_matches('\r');
        if line.is_empty() {
            continue;
        }
        // 以空白开头的行属于上一个头的折行
        if line.starts_with(' ') || line.starts_with('\t') {
            if let Some(last) = out.last_mut() {
                last.1.push(' ');
                last.1.push_str(line.trim());
            }
            continue;
        }
        match line.split_once(':') {
            Some((k, v)) => out.push((k.trim().to_string(), decode_rfc2047(v.trim()))),
            None => out.push((line.to_string(), String::new())),
        }
    }
    out
}

/// 头部值可能带参数（`multipart/alternative; boundary=...`），取主值
fn header_value(raw: &str) -> String {
    raw.split(';').next().unwrap_or("").trim().to_string()
}

pub fn decode_rfc2047(input: &str) -> String {
    if !input.contains("=?") {
        return input.to_string();
    }
    // 先并掉相邻编码词之间的空格，规范规定那只是折行留下的
    let pre = WORD_GAP.replace_all(input, "?==?");
    ENCODED_WORD
        .replace_all(&pre, |caps: &regex::Captures| {
            let charset = caps.get(1).map(|m| m.as_str()).unwrap_or("utf-8");
            let kind = caps
                .get(2)
                .map(|m| m.as_str().to_ascii_uppercase())
                .unwrap_or_else(|| "B".to_string());
            let payload = caps.get(3).map(|m| m.as_str()).unwrap_or("");
            let bytes = if kind == "B" {
                base64_bytes(payload)
            } else {
                quoted_printable_bytes(&payload.replace('_', " "))
            };
            decode_charset(&bytes, Some(charset))
        })
        .to_string()
}

pub fn base64_bytes(text: &str) -> Vec<u8> {
    let cleaned: String = text.chars().filter(|c| !c.is_whitespace() && *c != '=').collect();
    let padded = match cleaned.len() % 4 {
        0 => cleaned,
        n => format!("{}{}", cleaned, "=".repeat(4 - n)),
    };
    // 邮件里的 base64 常被折行截断，解不出来就返回空，让调用方按"无正文"处理
    B64.decode(&padded).unwrap_or_default()
}

/// quoted-printable：软换行、=XX 转义；正文里的裸 '=' 后不跟两位十六进制时原样保留
pub fn quoted_printable_bytes(text: &str) -> Vec<u8> {
    let unfolded = QP_SOFT.replace_all(text, "");
    let bytes = unfolded.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0usize;
    while i < bytes.len() {
        if bytes[i] == b'=' && i + 2 < bytes.len() {
            let hex = &unfolded[i + 1..i + 3];
            if let Ok(v) = u8::from_str_radix(hex, 16) {
                out.push(v);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    out
}

/// 按声明的字符集解码；声明缺失或不可用时探测，最后兜底 lossy UTF-8
pub fn decode_charset(bytes: &[u8], charset: Option<&str>) -> String {
    if let Some(label) = charset.map(|c| c.trim().trim_matches('"').trim_matches('\'')) {
        if !label.is_empty() {
            if let Some(enc) = encoding_rs::Encoding::for_label(label.as_bytes()) {
                let (decoded, _, _) = enc.decode(bytes);
                return decoded.into_owned();
            }
        }
    }
    if let Ok(s) = std::str::from_utf8(bytes) {
        return s.to_string();
    }
    let mut detector = chardetng::EncodingDetector::new();
    detector.feed(bytes, true);
    let enc = detector.guess(None, true);
    let (decoded, _, _) = enc.decode(bytes);
    decoded.into_owned()
}

fn lossy_utf8(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes).into_owned()
}

/// 递归走 MIME 结构，收集 html / text 正文。
///
/// 只处理真实邮件里会出现的四类：multipart/*、message/rfc822、text/html、text/plain。
/// 其它类型（图片附件等）直接跳过 —— 记账只关心正文。
fn walk(content_type: &str, cte: &str, html: &mut Vec<String>, text: &mut Vec<String>, body: &[u8]) {
    let main = header_value(content_type).to_ascii_lowercase();
    let charset = param(content_type, "charset");

    if main.starts_with("multipart/") {
        let boundary = match param(content_type, "boundary") {
            Some(b) if !b.is_empty() => b,
            _ => return,
        };
        for part in split_multipart(body, &boundary) {
            let (head, sub_body) = split_head_body(part);
            let headers = parse_headers(head);
            let sub_ct = header_of(&headers, "content-type");
            let sub_cte = header_of(&headers, "content-transfer-encoding");
            // 嵌套的 multipart 用自己的 Content-Type 再走一层
            walk(
                if sub_ct.is_empty() { "text/plain" } else { &sub_ct },
                &sub_cte,
                html,
                text,
                sub_body,
            );
        }
        return;
    }

    if main.starts_with("message/rfc822") {
        let nested = parse(body);
        if !nested.html.is_empty() {
            html.push(nested.html);
        }
        if !nested.text.is_empty() {
            text.push(nested.text);
        }
        return;
    }

    if !main.starts_with("text/") && !main.is_empty() {
        return;
    }
    let decoded = match cte.trim().to_ascii_lowercase().as_str() {
        "base64" => decode_charset(&base64_bytes(&lossy_utf8(body)), charset.as_deref()),
        "quoted-printable" => decode_charset(&quoted_printable_bytes(&lossy_utf8(body)), charset.as_deref()),
        _ => decode_charset(body, charset.as_deref()),
    };
    if decoded.trim().is_empty() {
        return;
    }
    if main.contains("html") {
        html.push(decoded);
    } else {
        text.push(decoded);
    }
}

/// 从 Content-Type 里取参数（boundary / charset），带不带引号都认
fn param(content_type: &str, key: &str) -> Option<String> {
    let lowered = content_type.to_ascii_lowercase();
    let at = lowered.find(&format!("{}=", key))?;
    let rest = &content_type[at + key.len() + 1..];
    let value = if let Some(stripped) = rest.strip_prefix('"') {
        stripped.split('"').next().unwrap_or("")
    } else if let Some(stripped) = rest.strip_prefix('\'') {
        stripped.split('\'').next().unwrap_or("")
    } else {
        rest.split([';', ' ', '\t', '\r', '\n']).next().unwrap_or("")
    };
    Some(value.trim().to_string())
}

/// 按 `--boundary` 切分 multipart：丢掉前言/后语与结束标记
fn split_multipart<'a>(body: &'a [u8], boundary: &str) -> Vec<&'a [u8]> {
    let marker = format!("--{}", boundary);
    let mut parts: Vec<&[u8]> = Vec::new();
    let mut cursor = 0usize;
    let mut first = true;
    let mut terminated = false;
    while let Some(rel) = find_sub(&body[cursor..], marker.as_bytes()) {
        let at = cursor + rel;
        if !first {
            let end = trim_part_end(&body[cursor..at]);
            parts.push(&body[cursor..cursor + end]);
        }
        first = false;
        // `--boundary--` 是结束标记，后面没有部件了
        let after = at + marker.len();
        if body.len() > after + 1 && &body[after..after + 2] == b"--" {
            terminated = true;
            break;
        }
        cursor = skip_line_break(body, after);
    }
    if !first && !terminated {
        let end = trim_part_end(&body[cursor..]);
        parts.push(&body[cursor..cursor + end]);
    }
    parts
}

/// 分隔线之后可能带扩展（`--b--` 之外的 `--b x`），统一跳到行尾换行之后
fn skip_line_break(body: &[u8], from: usize) -> usize {
    if body.len() >= from + 2 && &body[from..from + 2] == b"\r\n" {
        return from + 2;
    }
    if body.len() > from && body[from] == b'\n' {
        return from + 1;
    }
    let mut i = from;
    while i < body.len() && body[i] != b'\n' {
        i += 1;
    }
    (i + 1).min(body.len())
}

/// 去掉部件末尾的 CRLF（分隔线前的那个换行属于分隔线本身）
fn trim_part_end(part: &[u8]) -> usize {
    let mut len = part.len();
    while len > 0 && (part[len - 1] == b'\n' || part[len - 1] == b'\r') {
        len -= 1;
    }
    len
}

/// `张三 <a@b.com>` → (地址, 显示名)
pub fn split_addr(value: &str) -> (String, String) {
    let decoded = decode_rfc2047(value);
    if let Some(caps) = ADDR.captures(&decoded) {
        let addr = caps.get(1).map(|m| m.as_str().trim().to_string()).unwrap_or_default();
        let name = decoded.replace(caps.get(0).map(|m| m.as_str()).unwrap_or(""), "");
        let name = name.trim().trim_matches('"').trim().to_string();
        return (addr, name);
    }
    (decoded.trim().to_string(), String::new())
}

/// 邮件日期归一化成 `YYYY-MM-DD HH:MM:SS`；解析失败就原样带回，不做二次猜测
pub fn normalize_date(raw: &str) -> String {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return String::new();
    }
    if let Ok(dt) = chrono::DateTime::parse_from_rfc2822(trimmed) {
        return dt.with_timezone(&chrono::Local).format("%Y-%m-%d %H:%M:%S").to_string();
    }
    // 星期名写错时 rfc2822 会整体拒绝（少数服务器真会这样），去掉星期再试一次，
    // 否则原样带回的 "Fri, 29 A…" 会把入账日期切坏
    if let Some(rel) = trimmed.find(',') {
        let rest = trimmed[rel + 1..].trim();
        if let Ok(dt) = chrono::DateTime::parse_from_rfc2822(rest) {
            return dt.with_timezone(&chrono::Local).format("%Y-%m-%d %H:%M:%S").to_string();
        }
    }
    // 少数服务器给出 ISO 形式的日期头
    for fmt in ["%Y-%m-%d %H:%M:%S %z", "%Y-%m-%dT%H:%M:%S%:z", "%Y-%m-%dT%H:%M:%S"] {
        if let Ok(dt) = chrono::DateTime::parse_from_str(trimmed, fmt) {
            return dt.with_timezone(&chrono::Local).format("%Y-%m-%d %H:%M:%S").to_string();
        }
    }
    trimmed.to_string()
}

/// 头部 → 对外邮件结构
pub fn to_message(uid: &str, raw: &[u8]) -> EmailMessage {
    let mail = parse(raw);
    let (from, from_name) = split_addr(&mail.header("from"));
    let (to, _) = split_addr(&mail.header("to"));
    EmailMessage {
        uid: uid.to_string(),
        message_id: mail.header("message-id").trim().to_string(),
        from,
        from_name,
        to,
        subject: mail.header("subject"),
        date: normalize_date(&mail.header("date")),
        body_html: mail.html,
        body_text: mail.text,
        size_bytes: raw.len() as u64,
    }
}
