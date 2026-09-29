//! 手写同步 POP3 客户端（RFC1939）：STAT / UIDL / RETR。
//!
//! POP3 没有"已读"概念，每天重新拉一遍是常态；幂等靠 UIDL —— 只要服务器
//! 的 UIDL 稳定，上层用 UID 去重就够用。POP3 必须 TLS：口令是明文 USER/PASS。

use crate::mime;
use crate::net::Conn;
use crate::types::{ConnectionReport, EmailAccountConfig, EmailMessage, FetchOutcome};

pub struct Pop3Session {
    conn: Conn,
    total: u64,
    greeting: String,
}

impl Pop3Session {
    pub fn open(cfg: &EmailAccountConfig) -> Result<Pop3Session, String> {
        if !cfg.is_tls_required_by_policy() {
            return Err("POP3 未启用 SSL/TLS：USER/PASS 会明文出网，请勾选 SSL 或改用本机回环地址".to_string());
        }
        let mut conn = Conn::connect(cfg)?;
        let greeting = expect_ok(&mut conn, "问候")?;
        let mut session = Pop3Session {
            conn,
            total: 0,
            greeting,
        };
        if cfg.username.is_empty() {
            return Err("收件账号为空".to_string());
        }
        session.command(&format!("USER {}", cfg.username), "登录账号")?;
        session.command(&format!("PASS {}", cfg.password), "登录口令")?;
        let stat = session.command("STAT", "读取邮件数")?;
        session.total = stat
            .split_whitespace()
            .nth(1)
            .and_then(|n| n.parse().ok())
            .unwrap_or(0);
        Ok(session)
    }

    fn command(&mut self, line: &str, what: &str) -> Result<String, String> {
        self.conn.write_line(line)?;
        expect_ok(&mut self.conn, what)
    }

    /// 多行响应：读到单独一行为止，并还原点填充（`..` → `.`）
    fn multiline(&mut self) -> Result<Vec<String>, String> {
        let mut out = Vec::new();
        loop {
            let raw = self.conn.read_line()?;
            let trimmed = raw.trim_end_matches(['\r', '\n']);
            if trimmed == "." {
                return Ok(out);
            }
            let unstuffed = trimmed.strip_prefix('.').unwrap_or(trimmed);
            out.push(unstuffed.to_string());
        }
    }

    /// `(UIDL, 序号)`：序号用于 RETR
    pub fn uidl_latest(&mut self, limit: u64) -> Result<Vec<(String, usize)>, String> {
        if self.total == 0 {
            return Ok(Vec::new());
        }
        self.command("UIDL", "读取 UIDL")?;
        let lines = self.multiline()?;
        let mut pairs: Vec<(String, usize)> = Vec::new();
        for line in lines {
            let mut cols = line.split_whitespace();
            if let (Some(idx), Some(uid)) = (cols.next(), cols.next()) {
                if let Ok(n) = idx.parse::<usize>() {
                    pairs.push((uid.to_string(), n));
                }
            }
        }
        let take = (limit as usize).min(pairs.len());
        if take == 0 {
            return Ok(pairs);
        }
        Ok(pairs[pairs.len() - take..].to_vec())
    }

    /// 取一封原文；空行/点填充都按 RFC1939 还原
    pub fn retr(&mut self, seq: usize) -> Result<Vec<u8>, String> {
        self.command(&format!("RETR {}", seq), "读取正文")?;
        let mut out: Vec<u8> = Vec::new();
        loop {
            let line = self.conn.read_line_bytes()?;
            // 终止行是 CRLF.CRLF，去掉换行后正好等于 "."
            let stripped: Vec<u8> = line
                .iter()
                .copied()
                .filter(|b| *b != b'\r' && *b != b'\n')
                .collect();
            if stripped == b"." {
                return Ok(out);
            }
            if stripped.first() == Some(&b'.') {
                out.extend_from_slice(&line[1..]);
            } else {
                out.extend_from_slice(&line);
            }
        }
    }

    pub fn total(&self) -> u64 {
        self.total
    }

    pub fn close(&mut self) {
        let _ = self.conn.write_line("QUIT");
        let _ = self.conn.read_line();
    }
}

fn expect_ok(conn: &mut Conn, what: &str) -> Result<String, String> {
    let line = conn.read_line()?;
    let trimmed = line.trim_end_matches(['\r', '\n']).to_string();
    if trimmed.starts_with("+OK") || trimmed.starts_with("+ok") {
        return Ok(trimmed);
    }
    Err(format!("{} 被服务器拒绝: {}", what, trimmed))
}

pub fn fetch(cfg: &EmailAccountConfig, limit: u64) -> Result<FetchOutcome, String> {
    let cfg = cfg.normalized();
    let mut session = Pop3Session::open(&cfg)?;
    let targets = session.uidl_latest(limit)?;
    let mut messages: Vec<EmailMessage> = Vec::new();
    for (uid, seq) in targets {
        match session.retr(seq) {
            Ok(raw) => messages.push(mime::to_message(&uid, &raw)),
            Err(e) => slime_logger::sw_warn!("[email] POP3 取第 {} 封失败: {}", seq, e),
        }
    }
    messages.sort_by(|a, b| b.date.cmp(&a.date));
    let outcome = FetchOutcome {
        protocol: "pop3".to_string(),
        folder: "INBOX".to_string(),
        // POP3 没有 UIDVALIDITY，用固定前缀标明 UID 的可比范围
        uid_validity: "pop3-uidl".to_string(),
        total_seen: session.total(),
        messages,
    };
    session.close();
    Ok(outcome)
}

pub fn probe(cfg: &EmailAccountConfig, want_folders: bool) -> Result<ConnectionReport, String> {
    let cfg = cfg.normalized();
    let mut session = match Pop3Session::open(&cfg) {
        Ok(s) => s,
        Err(e) => return Ok(ConnectionReport::fail("pop3", &e)),
    };
    let uidl_state = match session.uidl_latest(1) {
        Ok(v) => format!("UIDL 可用（{} 条）", v.len()),
        Err(e) => format!("UIDL 失败: {}", e),
    };
    let ok = !uidl_state.contains("失败");
    let folders = if want_folders {
        vec!["INBOX".to_string()]
    } else {
        Vec::new()
    };
    let report = ConnectionReport {
        ok,
        protocol: "pop3".to_string(),
        detail: format!(
            "登录成功；邮箱共 {} 封；{}；问候: {}",
            session.total(),
            uidl_state,
            session.greeting.trim()
        ),
        capabilities: vec!["UIDL".to_string(), "RETR".to_string(), "STAT".to_string()],
        folders,
    };
    session.close();
    Ok(report)
}
