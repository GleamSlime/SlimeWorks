//! 手写同步 SMTP 客户端：只做连接与凭据自检（EHLO / STARTTLS / AUTH）。
//!
//! SMTP 是发信协议，不能"收"邮件，所以这里不提供取信能力；
//! 记账场景用它验证"这个邮箱的授权码是不是真的可用"，
//! 以及自签/证书链问题时给出比"发信失败"更明确的定位。

use base64::engine::general_purpose::STANDARD as B64;
use base64::Engine;

use crate::net::Conn;
use crate::types::{ConnectionReport, EmailAccountConfig};

pub struct SmtpSession {
    conn: Conn,
    capabilities: Vec<String>,
    tls: bool,
}

impl SmtpSession {
    pub fn open(cfg: &EmailAccountConfig) -> Result<SmtpSession, String> {
        let mut conn = Conn::connect(cfg)?;
        let (code, greeting) = read_reply(&mut conn)?;
        if code != 220 {
            return Err(format!("服务器问候异常: {}", greeting.join(" / ")));
        }
        let mut session = SmtpSession {
            conn,
            capabilities: Vec::new(),
            tls: cfg.use_ssl,
        };
        session.ehlo()?;
        // 587/25 这类明文端口要先升 TLS，否则 AUTH 一律不发
        if !session.tls && session.has("STARTTLS") {
            session.command("STARTTLS", &[]).map_err(|e| format!("STARTTLS 失败: {}", e))?;
            session.conn.upgrade_tls()?;
            session.tls = true;
            session.ehlo()?;
        }
        Ok(session)
    }

    fn ehlo(&mut self) -> Result<(), String> {
        // EHLO 的参数只是标识，服务器不校验；本机不必伪造域名
        let (code, lines) = self.command("EHLO localhost", &[250])?;
        if code != 250 {
            return Err(format!("EHLO 失败: {}", lines.join(" / ")));
        }
        // 整行留着：`AUTH PLAIN LOGIN` 拆成单词会把机制列表丢掉
        self.capabilities = lines.into_iter().map(|l| l.to_ascii_uppercase()).collect();
        Ok(())
    }

    fn has(&self, keyword: &str) -> bool {
        let want = keyword.to_ascii_uppercase();
        self.capabilities.iter().any(|c| c.split_ascii_whitespace().any(|w| w == want))
    }

    fn auth_methods(&self) -> Vec<String> {
        // EHLO 的 AUTH 行可能已经在 capabilities 里
        self.capabilities
            .iter()
            .filter(|c| c.starts_with("AUTH"))
            .cloned()
            .collect()
    }

    /// 发一条命令并把响应收干净
    fn command(&mut self, line: &str, expect: &[u16]) -> Result<(u16, Vec<String>), String> {
        self.conn.write_line(line)?;
        let (code, lines) = read_reply(&mut self.conn)?;
        if !expect.is_empty() && !expect.contains(&code) {
            return Err(format!("{} -> {} {}", line.split_whitespace().next().unwrap_or(""), code, lines.join(" / ")));
        }
        Ok((code, lines))
    }

    /// AUTH LOGIN：先按 PLAIN 试，再退回 LOGIN 两步式
    fn authenticate(&mut self, user: &str, pass: &str) -> Result<String, String> {
        if self.tls {
            let plain = format!("\0{}\0{}", user, pass);
            let (code, lines) = self.command(&format!("AUTH PLAIN {}", B64.encode(plain.as_bytes())), &[235])?;
            if code == 235 {
                return Ok("AUTH PLAIN 通过".to_string());
            }
            let _ = lines;
            self.command("AUTH LOGIN", &[334, 235])?;
            self.conn.write_line(&B64.encode(user.as_bytes()))?;
            let (code, lines) = read_reply(&mut self.conn)?;
            if code != 334 {
                return Err(format!("提交账号被拒: {} {}", code, lines.join(" / ")));
            }
            self.conn.write_line(&B64.encode(pass.as_bytes()))?;
            let (code, lines) = read_reply(&mut self.conn)?;
            if code == 235 {
                return Ok("AUTH LOGIN 通过".to_string());
            }
            return Err(format!("认证失败: {} {}", code, lines.join(" / ")));
        }
        Err("连接未启用 TLS，拒绝提交授权码".to_string())
    }

    fn quit(&mut self) {
        let _ = self.command("QUIT", &[221]);
    }
}

/// SMTP 是逐行 3 位状态码，`250-` 表示还有后续行
fn read_reply(conn: &mut Conn) -> Result<(u16, Vec<String>), String> {
    let mut lines = Vec::new();
    loop {
        let line = conn.read_line()?;
        let trimmed = line.trim_end_matches(['\r', '\n']);
        let bytes = trimmed.as_bytes();
        if bytes.len() < 4 || !bytes[..3].iter().all(|b| b.is_ascii_digit()) {
            return Err(format!("SMTP 响应格式异常: {}", trimmed));
        }
        let code: u16 = trimmed[..3]
            .parse()
            .map_err(|_| format!("SMTP 响应没有状态码: {}", trimmed))?;
        lines.push(trimmed[4..].to_string());
        // 第 4 个字符是空格说明这是最后一行
        if bytes[3] == b' ' {
            return Ok((code, lines));
        }
    }
}

pub fn probe(cfg: &EmailAccountConfig, _want_folders: bool) -> Result<ConnectionReport, String> {
    let cfg = cfg.normalized();
    let mut session = match SmtpSession::open(&cfg) {
        Ok(s) => s,
        Err(e) => return Ok(ConnectionReport::fail("smtp", &e)),
    };
    let detail = if cfg.username.is_empty() || cfg.password.is_empty() {
        "连接与 EHLO 成功（未填账号，跳过认证检查）".to_string()
    } else {
        match session.authenticate(&cfg.username, &cfg.password) {
            Ok(ok) => ok,
            Err(e) => {
                let report = ConnectionReport {
                    ok: false,
                    protocol: "smtp".to_string(),
                    detail: e,
                    capabilities: session.auth_methods(),
                    folders: Vec::new(),
                };
                session.quit();
                return Ok(report);
            }
        }
    };
    let report = ConnectionReport {
        ok: true,
        protocol: "smtp".to_string(),
        detail: format!(
            "{}；TLS: {}；能力: {}",
            detail,
            if session.tls { "已启用" } else { "未启用" },
            session.capabilities.join(" ")
        ),
        capabilities: session.auth_methods(),
        // SMTP 没有信箱目录概念
        folders: Vec::new(),
    };
    session.quit();
    Ok(report)
}
