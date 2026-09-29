//! MIME 层离线测试：RFC2047/charset/multipart 都是手写的，必须有用例兜住。
//! 协议本身（IMAP/POP3/SMTP）要连真服务器，这里只测"拿到原文之后"的部分。

use chrono::{Local, TimeZone};
use email_module::mime::{
    base64_bytes, decode_rfc2047, normalize_date, parse, quoted_printable_bytes, split_addr,
    to_message,
};

/// GBK 的"招商银行信用卡每日账单"，base64 后就是 RFC2047 编码词
const GBK_SUBJECT: &str = "=?GBK?B?1dDJzNL40NDQxdPDv6jDv8jV1cu1pQ==?=";

#[test]
fn rfc2047_subject_in_gbk() {
    assert_eq!(decode_rfc2047(GBK_SUBJECT), "招商银行信用卡每日账单");
    // 普通标题不该被动过
    assert_eq!(decode_rfc2047("您的账单已出"), "您的账单已出");
}

#[test]
fn base64_and_quoted_printable_roundtrip() {
    assert_eq!(base64_bytes("YWJjZA=="), b"abcd".to_vec());
    // 分块折行与缺 padding 都要能吃下
    assert_eq!(base64_bytes("YWJj\nZA"), b"abcd".to_vec());
    let qp = |s: &str| String::from_utf8(quoted_printable_bytes(s)).unwrap();
    assert_eq!(qp("CNY=20=31=37=2E=31=30"), "CNY 17.10");
    // `=` 结尾是软换行，不该留下换行本身
    assert_eq!(qp("ab=\r\ncd"), "abcd");
}

#[test]
fn multipart_picks_real_bodies() {
    let raw = "From: bill@cmbchina.com\r\n\
Content-Type: multipart/alternative; boundary=\"BBB\"\r\n\
\r\n\
--BBB\r\n\
Content-Type: text/plain; charset=utf-8\r\n\
\r\n\
请查看HTML\r\n\
--BBB\r\n\
Content-Type: text/html; charset=utf-8\r\n\
\r\n\
<div>CNY 17.10</div>\r\n\
--BBB--\r\n";
    let mail = parse(raw.as_bytes());
    assert_eq!(mail.html, "<div>CNY 17.10</div>");
    assert_eq!(mail.text, "请查看HTML");
}

#[test]
fn nested_multipart_is_walked() {
    // 真实账单常见 multipart/mixed 里套 alternative，外面还挂附件说明
    let raw = "Content-Type: multipart/mixed; boundary=\"OUT\"\r\n\
\r\n\
--OUT\r\n\
Content-Type: multipart/alternative; boundary=\"IN\"\r\n\
\r\n\
--IN\r\n\
Content-Type: text/html; charset=utf-8\r\n\
\r\n\
<html>可用额度 20000.00</html>\r\n\
--IN--\r\n\
--OUT\r\n\
Content-Type: text/plain; charset=utf-8\r\n\
Content-Disposition: attachment; filename=\"note.txt\"\r\n\
\r\n\
附件说明\r\n\
--OUT--\r\n";
    let mail = parse(raw.as_bytes());
    assert!(mail.html.contains("可用额度 20000.00"), "html={}", mail.html);
}

#[test]
fn base64_body_declared_gbk() {
    // GBK 字节不是合法 UTF-8，字符集没处理就会乱码
    let raw = "Subject: =?GBK?B?1dDJzNL40NDQxdPDv6jDv8jV1cu1pQ==?=\r\n\
Content-Type: text/html; charset=\"GBK\"\r\n\
Content-Transfer-Encoding: base64\r\n\
\r\n\
1cu1pdLRyfqzyaOsv8nTw7butsggMjAwMDAuMDA=\r\n";
    let mail = parse(raw.as_bytes());
    assert_eq!(mail.header("subject"), "招商银行信用卡每日账单");
    assert_eq!(mail.html, "账单已生成，可用额度 20000.00");
}

#[test]
fn header_folding_is_joined() {
    let raw = "Subject: 每日\r\n 账单\r\nDate: Thu, 1 Jan 2026 00:00:00 +0800\r\n\r\nbody\r\n";
    let mail = parse(raw.as_bytes());
    assert_eq!(mail.header("subject"), "每日 账单");
    // 头部名不区分大小写
    assert_eq!(mail.header("DATE"), "Thu, 1 Jan 2026 00:00:00 +0800");
}

#[test]
fn date_normalized_to_local_wall_clock() {
    // 只比"同一时刻"，不锁死本机时区
    let check = |input: &str, expect: &str| {
        let out = normalize_date(input);
        let naive = chrono::NaiveDateTime::parse_from_str(&out, "%Y-%m-%d %H:%M:%S")
            .unwrap_or_else(|_| panic!("{} 没有归一化成 YYYY-MM-DD HH:MM:SS，实际 [{}]", input, out));
        let got = Local.from_local_datetime(&naive).single().unwrap();
        let want = chrono::DateTime::parse_from_rfc2822(expect).unwrap();
        assert_eq!(got, want.with_timezone(&Local));
    };
    check("Sat, 29 Aug 2026 08:15:34 +0800", "Sat, 29 Aug 2026 08:15:34 +0800");
    // 29 号其实是周六；星期名写错也不能把原始头部带回去，否则入账日期会被切成 "Fri, 29 A"
    check("Fri, 29 Aug 2026 08:15:34 +0800", "Sat, 29 Aug 2026 08:15:34 +0800");
    assert_eq!(normalize_date("昨天下午"), "昨天下午");
    assert_eq!(normalize_date(""), "");
}

#[test]
fn from_header_splits_name_and_addr() {
    let (addr, name) = split_addr("\"招商银行\" <bill@cmbchina.com>");
    assert_eq!(addr, "bill@cmbchina.com");
    assert_eq!(name, "招商银行");

    let (addr, name) = split_addr(GBK_SUBJECT);
    assert_eq!(addr, "招商银行信用卡每日账单");
    assert_eq!(name, "");
}

#[test]
fn to_message_carries_uid_and_size() {
    let raw = "From: =?GBK?B?1dDJzNL40NDQxdPDv6jDv8jV1cu1pQ==?= <bill@cmbchina.com>\r\n\
To: me@example.com\r\n\
Message-Id: <abc@cmb>\r\n\
Date: Sat, 29 Aug 2026 08:15:34 +0800\r\n\
Subject: =?GBK?B?1dDJzNL40NDQxdPDv6jDv8jV1cu1pQ==?=\r\n\
Content-Type: text/html; charset=utf-8\r\n\
\r\n\
<div>CNY 17.10</div>\r\n";
    let msg = to_message("42", raw.as_bytes());
    assert_eq!(msg.uid, "42");
    assert_eq!(msg.from, "bill@cmbchina.com");
    assert_eq!(msg.from_name, "招商银行信用卡每日账单");
    assert_eq!(msg.message_id, "<abc@cmb>");
    assert_eq!(msg.subject, "招商银行信用卡每日账单");
    // 本机时区不固定（CI 是 UTC），只比"同一时刻"：把归一化后的墙上时间按本地时区还原再对
    let naive = chrono::NaiveDateTime::parse_from_str(&msg.date, "%Y-%m-%d %H:%M:%S")
        .unwrap_or_else(|_| panic!("date 没有归一化成 YYYY-MM-DD HH:MM:SS，实际 [{}]", msg.date));
    let got = Local.from_local_datetime(&naive).single().unwrap();
    assert_eq!(
        got,
        chrono::DateTime::parse_from_rfc2822("Sat, 29 Aug 2026 08:15:34 +0800")
            .unwrap()
            .with_timezone(&Local)
    );
    assert!(msg.body_html.contains("17.10"));
    assert_eq!(msg.size_bytes, raw.len() as u64);
    assert_eq!(msg.body_text, "");
}
