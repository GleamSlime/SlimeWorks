//! 假 IMAP 服务器（loopback 明文端口）上的端到端协议验证。
//!
//! 单元级的 `parse_list_entry` 只保证字符串切得对；目录列表和"取最近 N 封"这两条
//! 是隔着 socket 才见真章的地方——`/` 目录那个 bug 就是响应行进了 `run()` 之后
//! 才被切错的。TLS 策略只放行本机回环走明文，所以这个服务器不需要证书。

use std::io::{BufRead, BufReader, Write};
use std::net::{TcpListener, TcpStream};
use std::thread;

use email_module::imap;
use email_module::types::EmailAccountConfig;

/// 服务器上"真实存在"的邮箱：一个中文目录、一个只能当目录用的父节点
fn list_response() -> String {
    let mut out = String::new();
    out.push_str("* LIST (\\HasNoChildren) \"/\" \"INBOX\"\r\n");
    out.push_str("* LIST (\\HasNoChildren) \"/\" \"Drafts\"\r\n");
    out.push_str("* LIST (\\Noselect \\HasChildren) \"/\" \"Archives\"\r\n");
    out.push_str("* LIST (\\HasNoChildren) \"/\" \"Archives/2026\"\r\n");
    out.push_str(&format!(
        "* LIST (\\HasNoChildren) \"/\" \"{}\"\r\n",
        imap::encode_mutf7("已发送")
    ));
    out
}

/// 一封最小可解析的账单邮件
fn body_of(uid: &str) -> String {
    format!(
        "From: ccsvc@message.cmbchina.com\r\nSubject: bill-{uid}\r\n\
         Date: Mon, 1 Oct 2026 09:0{uid}:00 +0800\r\n\r\n账单第 {uid} 号\r\n"
    )
}

/// 起一台只会讲这几句话（LIST / SELECT / UID SEARCH / UID FETCH）的假服务器，
/// 返回它监听的端口。收件箱里固定 5 封，UID 1..=5。
///
/// accept 循环一直挂着：一个测试里连着自检和取信会开好几条连接，只 accept 一次
/// 的话第二条连接会被系统直接拒掉。
fn spawn_fake_imap() -> u16 {
    let listener = TcpListener::bind("127.0.0.1:0").expect("假 IMAP 服务器绑定端口失败");
    let port = listener.local_addr().expect("拿不到监听端口").port();
    thread::spawn(move || {
        for stream in listener.incoming() {
            match stream {
                Ok(s) => serve(s),
                Err(_) => break,
            }
        }
    });
    port
}

fn serve(stream: TcpStream) {
    let mut reader = BufReader::new(stream.try_clone().expect("克隆连接失败"));
    let mut writer = stream;
    let say = |w: &mut TcpStream, text: &str| {
        let _ = w.write_all(text.as_bytes());
        let _ = w.flush();
    };

    say(&mut writer, "* OK fake IMAP server ready\r\n");

    let mut line = String::new();
    loop {
        line.clear();
        match reader.read_line(&mut line) {
            Ok(0) | Err(_) => break,
            Ok(_) => {}
        }
        let mut parts = line.splitn(2, ' ');
        let tag = parts.next().unwrap_or("").trim().to_string();
        let rest = parts.next().unwrap_or("").trim().to_string();
        let cmd = rest.split_whitespace().next().unwrap_or("").to_ascii_uppercase();
        let upper = rest.to_ascii_uppercase();
        let arg = rest.splitn(2, ' ').nth(1).unwrap_or("").trim().to_string();
        let (mut status, mut note) = ("OK", "done");

        if cmd == "CAPABILITY" {
            // 故意不声明 AUTH=PLAIN：让登录走 LOGIN 这条老命令，
            // 假服务器就不必实现 base64 挑战那一跳
            say(&mut writer, "* CAPABILITY IMAP4rev1 IDLE UIDPLUS\r\n");
        } else if cmd == "LOGOUT" {
            say(&mut writer, "* BYE fake server closing\r\n");
            say(&mut writer, &format!("{tag} OK LOGOUT completed\r\n"));
            break;
        } else if cmd == "LIST" {
            say(&mut writer, &list_response());
        } else if cmd == "SELECT" {
            let name = arg.trim_matches('"');
            if ["INBOX", "Drafts", "Archives/2026"].contains(&name) {
                say(&mut writer, "* 5 EXISTS\r\n");
                say(&mut writer, "* OK [UIDVALIDITY 777] UIDs valid\r\n");
            } else {
                status = "NO";
                note = "Folder not exist";
            }
        } else if cmd == "UID" && upper.contains("SEARCH") {
            say(&mut writer, "* SEARCH 1 2 3 4 5\r\n");
        } else if cmd == "UID" && upper.contains("FETCH") {
            let uid = upper.split_whitespace().nth(2).unwrap_or("1").to_ascii_lowercase();
            let body = body_of(&uid);
            say(
                &mut writer,
                &format!("* {uid} FETCH (UID {uid} BODY[] {{{}}}\r\n", body.len()),
            );
            say(&mut writer, &body);
            say(&mut writer, "\r\n)\r\n");
        }
        say(&mut writer, &format!("{tag} {status} {note}\r\n"));
    }
}

fn cfg(port: u16, mailbox: &str) -> EmailAccountConfig {
    EmailAccountConfig {
        protocol: "imap".to_string(),
        host: "127.0.0.1".to_string(),
        port,
        // 明文只在本机回环上被策略放行
        use_ssl: false,
        username: "tester".to_string(),
        password: "secret".to_string(),
        mailbox: mailbox.to_string(),
        accept_invalid_certs: false,
        timeout_secs: 10,
    }
}

/// 目录列表要给出真目录：曾经这里返回唯一一条 `/`（把分隔符当成了名字），
/// 界面上点一下就等于把邮箱填成 `/`，SELECT 必然 Folder not exist。
#[test]
fn list_returns_real_mailbox_names_over_the_wire() {
    let port = spawn_fake_imap();
    let report = imap::probe(&cfg(port, "INBOX"), true).expect("自检应当成功");
    assert!(report.ok, "detail = {}", report.detail);
    assert!(
        !report.folders.contains(&"/".to_string()),
        "目录里不该出现分隔符本身：{:?}",
        report.folders
    );
    assert_eq!(
        report.folders,
        vec![
            "Archives/2026".to_string(),
            "Drafts".to_string(),
            "INBOX".to_string(),
            "已发送".to_string(),
        ],
        "只该留下能 SELECT 进去的目录，且按名字排好"
    );
}

/// `limit` 决定抓最近几封：回补历史就是把这一个数字从 10 放大到几百封
#[test]
fn fetch_latest_takes_the_newest_uids_within_the_limit() {
    let port = spawn_fake_imap();

    let two = imap::fetch(&cfg(port, "INBOX"), 2).expect("取最近 2 封应当成功");
    let mut uids: Vec<String> = two.messages.iter().map(|m| m.uid.clone()).collect();
    uids.sort();
    assert_eq!(uids, vec!["4".to_string(), "5".to_string()], "SEARCH 给 1..5，取最近两封应是 4、5");
    assert_eq!(two.total_seen, 5, "EXISTS 要如实带回来");
    assert_eq!(two.folder, "INBOX");
    assert_eq!(two.uid_validity, "777");

    let all = imap::fetch(&cfg(port, "INBOX"), 200).expect("回补级别的数量应当照样取到");
    assert_eq!(all.messages.len(), 5, "箱里只有 5 封，limit 再大也不会凭空多出邮件");
}

/// 邮箱名不存在时要把服务器的 NO 原样报出来，不能悄悄换回 INBOX
#[test]
fn select_reports_missing_mailbox_instead_of_falling_back() {
    let port = spawn_fake_imap();
    let err = imap::fetch(&cfg(port, "/"), 10).unwrap_err();
    assert!(err.contains("打开邮箱 /"), "err = {err}");
}
