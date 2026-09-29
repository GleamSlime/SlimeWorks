//! 手写同步 IMAP4rev1 客户端：登录 → 选信箱 → UID SEARCH → UID FETCH 全文。
//!
//! 只取全文而不做 header-only 预筛：银行邮件每天就一封，多下一次全文的代价
//! 远小于"先筛再取"带来的状态复杂度；真正的去重交给上层的 UID + 去重键。

use base64::engine::general_purpose::STANDARD as B64;
use base64::Engine;
use lazy_static::lazy_static;
use regex::Regex;

use crate::mime;
use crate::net::Conn;
use crate::types::{ConnectionReport, EmailAccountConfig, EmailMessage, FetchOutcome};

lazy_static! {
    /// FETCH 响应里的字面量声明：`... BODY[] {79725}`
    static ref LITERAL: Regex = Regex::new(r"\{(\d+)\}\s*$").unwrap();
    static ref EXISTS: Regex = Regex::new(r"(\d+)\s+EXISTS").unwrap();
    static ref UID_VALIDITY: Regex = Regex::new(r"(?i)UIDVALIDITY\s+(\d+)").unwrap();
}

pub struct ImapSession {
    conn: Conn,
    tag: u32,
    capabilities: Vec<String>,
    mailbox: String,
    exists: u64,
    uid_validity: String,
}

impl ImapSession {
    /// 连接 + 问候 + CAPABILITY + 登录
    pub fn open(cfg: &EmailAccountConfig) -> Result<ImapSession, String> {
        if !cfg.is_tls_required_by_policy() {
            return Err("IMAP 未启用 SSL/TLS：口令会明文出网，请勾选 SSL 或改用本机回环地址".to_string());
        }
        let mut conn = Conn::connect(cfg)?;
        let greeting = read_greeting(&mut conn)?;
        if !greeting.to_ascii_uppercase().contains("OK") {
            return Err(format!("服务器拒绝连接: {}", greeting.trim()));
        }
        let mut session = ImapSession {
            conn,
            tag: 0,
            capabilities: Vec::new(),
            mailbox: String::new(),
            exists: 0,
            uid_validity: String::new(),
        };
        // 服务器不支持 CAPABILITY 时按空能力继续走 LOGIN
        session.capabilities = session.run("CAPABILITY").unwrap_or_default();
        session.login(cfg)?;
        Ok(session)
    }

    fn capability_has(&self, keyword: &str) -> bool {
        let want = keyword.to_ascii_uppercase();
        self.capabilities
            .iter()
            .flat_map(|l| l.split_whitespace())
            .any(|w| w.to_ascii_uppercase() == want)
    }

    fn login(&mut self, cfg: &EmailAccountConfig) -> Result<(), String> {
        if cfg.username.is_empty() {
            return Err("收件账号为空".to_string());
        }
        if self.capability_has("AUTH=PLAIN") {
            if self.authenticate_plain(&cfg.username, &cfg.password).is_ok() {
                return Ok(());
            }
        }
        self.run(&format!(
            "LOGIN {} {}",
            quoted(&cfg.username),
            quoted(&cfg.password)
        ))
        .map_err(|e| format!("登录失败: {}", e))?;
        Ok(())
    }

    fn authenticate_plain(&mut self, user: &str, pass: &str) -> Result<(), String> {
        let token = format!("\0{}\0{}", user, pass);
        let encoded = B64.encode(token.as_bytes());
        let tag = self.next_tag();
        self.conn.write_line(&format!("{} AUTHENTICATE PLAIN", tag))?;
        let mut challenged = false;
        for _ in 0..32 {
            let line = self.conn.read_line()?;
            if line.starts_with('+') {
                challenged = true;
                break;
            }
            if starts_with_tag(&line, &tag) {
                return Err(format!("服务器不接受 AUTHENTICATE: {}", line.trim()));
            }
        }
        if !challenged {
            return Err("AUTHENTICATE 没等到挑战".to_string());
        }
        self.conn.write_line(&encoded)?;
        self.until_tag(&tag).map_err(|e| format!("PLAIN 认证失败: {}", e))
    }

    fn next_tag(&mut self) -> String {
        self.tag += 1;
        format!("A{:05}", self.tag)
    }

    /// 发送命令并收集未打标响应；服务器回 NO/BAD 时返回 Err
    fn run(&mut self, cmd: &str) -> Result<Vec<String>, String> {
        let tag = self.next_tag();
        self.conn.write_line(&format!("{} {}", tag, cmd))?;
        let mut untagged = Vec::new();
        loop {
            let line = self.conn.read_line()?;
            if starts_with_tag(&line, &tag) {
                let status = line[tag.len()..].trim();
                if is_failure(status) {
                    return Err(format!("{}: {}", cmd.split_whitespace().next().unwrap_or(""), status));
                }
                return Ok(untagged);
            }
            if let Some(rest) = line.strip_prefix('*') {
                untagged.push(rest.trim().to_string());
            }
        }
    }

    fn until_tag(&mut self, tag: &str) -> Result<(), String> {
        loop {
            let line = self.conn.read_line()?;
            if starts_with_tag(&line, tag) {
                let status = line[tag.len()..].trim();
                if is_failure(status) {
                    return Err(status.to_string());
                }
                return Ok(());
            }
        }
    }

    pub fn list(&mut self) -> Result<Vec<String>, String> {
        let lines = self.run("LIST \"\" \"*\"")?;
        let mut folders: Vec<String> = lines.iter().filter_map(|l| parse_list_name(l)).collect();
        folders.sort();
        folders.dedup();
        Ok(folders)
    }

    pub fn select(&mut self, mailbox: &str) -> Result<(), String> {
        let encoded = mailbox_name(mailbox);
        let lines = self
            .run(&format!("SELECT {}", quoted(&encoded)))
            .map_err(|e| format!("打开邮箱 {} 失败: {}", mailbox, e))?;
        self.mailbox = mailbox.to_string();
        self.exists = 0;
        self.uid_validity = String::new();
        for line in &lines {
            if let Some(caps) = EXISTS.captures(line) {
                self.exists = caps.get(1).and_then(|m| m.as_str().parse().ok()).unwrap_or(0);
            }
            if let Some(caps) = UID_VALIDITY.captures(line) {
                self.uid_validity = caps.get(1).map(|m| m.as_str().to_string()).unwrap_or_default();
            }
        }
        Ok(())
    }

    /// 取最近 limit 封的全文：`(UID, 原文)`
    pub fn fetch_latest(&mut self, limit: u64) -> Result<Vec<(String, Vec<u8>)>, String> {
        let lines = self.run("UID SEARCH ALL")?;
        let mut uids: Vec<String> = Vec::new();
        for line in &lines {
            if let Some(rest) = line.strip_prefix("SEARCH") {
                uids.extend(rest.split_whitespace().map(|s| s.to_string()));
            }
        }
        let take = (limit as usize).min(uids.len());
        if take == 0 {
            return Ok(Vec::new());
        }
        let picked = uids[uids.len() - take..].to_vec();
        let mut out = Vec::with_capacity(picked.len());
        for uid in picked {
            match self.fetch_one(&uid) {
                Ok(raw) => out.push((uid, raw)),
                // 单封取不到（消息刚被删、服务器抽风）不该让整个规则失败
                Err(e) => slime_logger::sw_warn!("[email] IMAP 取 UID {} 失败: {}", uid, e),
            }
        }
        Ok(out)
    }

    fn fetch_one(&mut self, uid: &str) -> Result<Vec<u8>, String> {
        let tag = self.next_tag();
        self.conn
            .write_line(&format!("{} UID FETCH {} BODY.PEEK[]", tag, uid))?;
        let mut literal: Option<Vec<u8>> = None;
        loop {
            let line = self.conn.read_line()?;
            if starts_with_tag(&line, &tag) {
                let status = line[tag.len()..].trim();
                if is_failure(status) {
                    return Err(status.to_string());
                }
                return literal.ok_or_else(|| format!("UID {} 没有返回正文", uid));
            }
            if let Some(caps) = LITERAL.captures(&line) {
                let n = caps.get(1).and_then(|m| m.as_str().parse().ok()).unwrap_or(0);
                literal = Some(self.conn.read_exact_bytes(n)?);
            }
        }
    }

    pub fn exists(&self) -> u64 {
        self.exists
    }

    pub fn uid_validity(&self) -> String {
        if self.uid_validity.is_empty() {
            "unknown".to_string()
        } else {
            self.uid_validity.clone()
        }
    }

    pub fn close(&mut self) {
        let tag = self.next_tag();
        let _ = self.conn.write_line(&format!("{} LOGOUT", tag));
        let _ = self.conn.read_line();
    }
}

fn is_failure(status: &str) -> bool {
    let upper = status.to_ascii_uppercase();
    upper.starts_with("NO") || upper.starts_with("BAD")
}

fn starts_with_tag(line: &str, tag: &str) -> bool {
    line.len() > tag.len() && line.starts_with(tag) && line.as_bytes()[tag.len()] == b' '
}

/// 问候行一定是 `* OK ...`，中间可能夹着预认证响应
fn read_greeting(conn: &mut Conn) -> Result<String, String> {
    for _ in 0..16 {
        let line = conn.read_line()?;
        if line.starts_with('*') {
            return Ok(line);
        }
    }
    Err("没等到 IMAP 问候行".to_string())
}

/// IMAP 的 quoted string：反斜杠和双引号要转义
fn quoted(value: &str) -> String {
    let mut out = String::with_capacity(value.len() + 2);
    out.push('"');
    for c in value.chars() {
        if c == '"' || c == '\\' {
            out.push('\\');
        }
        out.push(c);
    }
    out.push('"');
    out
}

/// 邮箱名：ASCII 直接用，中文走 modified UTF-7
fn mailbox_name(mailbox: &str) -> String {
    if mailbox.is_ascii() {
        mailbox.to_string()
    } else {
        encode_mutf7(mailbox)
    }
}

/// `LIST (\HasNoChildren) "/" "INBOX"` → INBOX
fn parse_list_name(line: &str) -> Option<String> {
    let rest = line.strip_prefix("LIST")?.trim_start();
    let after_flags = if let Some((_, tail)) = rest.split_once(')') {
        tail.trim_start()
    } else {
        rest.strip_prefix("NIL")?.trim_start()
    };
    let after_sep = if let Some((_, tail)) = after_flags.split_once('"') {
        tail.trim_start()
    } else {
        after_flags.strip_prefix("NIL")?.trim_start()
    };
    let (name, _) = after_sep.split_once('"')?;
    if name.is_empty() {
        return None;
    }
    // LIST 回来的名字是 modified UTF-7，展示前要还原
    Some(decode_mutf7(name))
}

// ── modified UTF-7（IMAP 邮箱名的非 ASCII 编码）──────────────────────────────

fn flush_base64(chunk: &mut Vec<u16>, out: &mut String) {
    if chunk.is_empty() {
        return;
    }
    let bytes: Vec<u8> = chunk.iter().flat_map(|u| u.to_be_bytes()).collect();
    let encoded = B64.encode(&bytes).replace('/', ",").trim_end_matches('=').to_string();
    out.push('&');
    out.push_str(&encoded);
    out.push('-');
    chunk.clear();
}

pub fn encode_mutf7(input: &str) -> String {
    let mut out = String::with_capacity(input.len() + 2);
    let mut chunk: Vec<u16> = Vec::new();
    for ch in input.chars() {
        let code = ch as u32;
        let printable = (0x20..=0x7E).contains(&code);
        if printable && ch != '&' {
            flush_base64(&mut chunk, &mut out);
            out.push(ch);
        } else if ch == '&' {
            // '&' 的转义是 '&-'，且不进 base64 段
            flush_base64(&mut chunk, &mut out);
            out.push_str("&-");
        } else {
            chunk.push(code as u16);
        }
    }
    flush_base64(&mut chunk, &mut out);
    out
}

pub fn decode_mutf7(input: &str) -> String {
    if !input.contains('&') {
        return input.to_string();
    }
    let mut out = String::with_capacity(input.len());
    let mut chars = input.chars().peekable();
    while let Some(ch) = chars.next() {
        if ch != '&' {
            out.push(ch);
            continue;
        }
        if chars.peek() == Some(&'-') {
            chars.next();
            out.push('&');
            continue;
        }
        let mut b64 = String::new();
        while let Some(&c) = chars.peek() {
            chars.next();
            if c == '-' {
                break;
            }
            b64.push(if c == ',' { '/' } else { c });
        }
        if b64.len() % 4 != 0 {
            b64.push_str(&"=".repeat(4 - b64.len() % 4));
        }
        if let Ok(bytes) = B64.decode(&b64) {
            let units: Vec<u16> = bytes
                .chunks(2)
                .filter(|c| c.len() == 2)
                .map(|c| u16::from_be_bytes([c[0], c[1]]))
                .collect();
            out.extend(units.iter().filter_map(|u| char::from_u32(*u as u32)));
        }
    }
    out
}

// ── 对外入口 ──────────────────────────────────────────────────────────────────

pub fn fetch(cfg: &EmailAccountConfig, limit: u64) -> Result<FetchOutcome, String> {
    let cfg = cfg.normalized();
    let mut session = ImapSession::open(&cfg)?;
    session.select(&cfg.mailbox)?;
    let fetched = session.fetch_latest(limit)?;
    let mut messages: Vec<EmailMessage> = fetched
        .iter()
        .map(|(uid, raw)| mime::to_message(uid, raw))
        .collect();
    // 最近的放前面，预览列表不用再翻
    messages.sort_by(|a, b| b.date.cmp(&a.date));
    let outcome = FetchOutcome {
        protocol: "imap".to_string(),
        folder: cfg.mailbox.clone(),
        uid_validity: session.uid_validity(),
        total_seen: session.exists(),
        messages,
    };
    session.close();
    Ok(outcome)
}

pub fn probe(cfg: &EmailAccountConfig, want_folders: bool) -> Result<ConnectionReport, String> {
    let cfg = cfg.normalized();
    let mut session = match ImapSession::open(&cfg) {
        Ok(s) => s,
        Err(e) => return Ok(ConnectionReport::fail("imap", &e)),
    };
    let folders = if want_folders { session.list().unwrap_or_default() } else { Vec::new() };
    let mailbox_state = match session.select(&cfg.mailbox) {
        Ok(()) => format!("邮箱 {} 共 {} 封", cfg.mailbox, session.exists()),
        Err(e) => e,
    };
    let ok = !mailbox_state.contains("失败");
    let report = ConnectionReport {
        ok,
        protocol: "imap".to_string(),
        detail: format!("登录成功；{}；能力: {}", mailbox_state, session.capabilities.join(" ")),
        capabilities: session.capabilities.clone(),
        folders,
    };
    session.close();
    Ok(report)
}
