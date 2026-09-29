//! 邮箱配置层的离线测试：TLS 策略、默认端口回填、serde 默认值。
//!
//! 这一层是"口令会不会明文出网"的唯一闸门，且全是纯函数，
//! 所以必须逐条钉住；真的连服务器的部分（imap/pop3/smtp 客户端）不在这里测。

use email_module::types::{default_port, EmailAccountConfig};

/// 造一份最小可用配置：只有 protocol 是必填字段，其余走 serde 默认
fn cfg(protocol: &str, host: &str, use_ssl: bool) -> EmailAccountConfig {
    EmailAccountConfig {
        protocol: protocol.to_string(),
        host: host.to_string(),
        port: 0,
        use_ssl,
        username: "user@example.test".to_string(),
        password: "hunter2".to_string(),
        mailbox: String::new(),
        accept_invalid_certs: false,
        timeout_secs: 0,
    }
}

#[test]
fn plaintext_to_public_host_is_refused() {
    // 明文 + 公网域名 = 口令裸奔，策略必须拒绝
    for host in ["imap.example.com", "mail.qq.com", "10.0.0.8", "192.168.1.20"] {
        let c = cfg("imap", host, false);
        assert!(!c.is_tls_required_by_policy(), "{} 不该被当作本机回环", host);
    }
}

#[test]
fn loopback_plaintext_is_allowed() {
    // 本机测试例外：127.0.0.1 / localhost / ::1 允许明文
    for host in ["127.0.0.1", "127.0.0.53", "localhost", "::1"] {
        let c = cfg("imap", host, false);
        assert!(c.is_tls_required_by_policy(), "{} 应被认作回环", host);
    }
}

#[test]
fn ssl_always_satisfies_policy() {
    let c = cfg("pop3", "imap.example.com", true);
    assert!(c.is_tls_required_by_policy());
    // 空 host + SSL 也算合规（由后续连接阶段报"地址为空"）
    assert!(cfg("smtp", "", true).is_tls_required_by_policy());
    // 空 host 且明文：不是回环 → 拒绝
    assert!(!cfg("smtp", "", false).is_tls_required_by_policy());
}

#[test]
fn prefix_looking_host_is_not_loopback() {
    // 按现状锁定："127." 前缀是字符串匹配而非 IP 判定，
    // 于是 127.example.com 这种"看起来像回环"的公网域名会被放行（见报告的可疑项）
    let c = cfg("imap", "127.example.com", false);
    assert!(c.is_tls_required_by_policy());
    // 带方括号的 IPv6 字面量（URL 写法）不在白名单里
    assert!(!cfg("imap", "[::1]", false).is_tls_required_by_policy());
    // host 不做小写化，大写 LOCALHOST 命中不了白名单
    assert!(!cfg("imap", "LOCALHOST", false).is_tls_required_by_policy());
}

#[test]
fn default_port_matrix() {
    // 三种协议 × SSL 真假
    assert_eq!(default_port("imap", true), 993);
    assert_eq!(default_port("imap", false), 143);
    assert_eq!(default_port("pop3", true), 995);
    assert_eq!(default_port("pop3", false), 110);
    assert_eq!(default_port("smtp", true), 465);
    assert_eq!(default_port("smtp", false), 587);
    // 未知协议一律兜到 993，且与 use_ssl 无关
    assert_eq!(default_port("exchange_eas", true), 993);
    assert_eq!(default_port("exchange_eas", false), 993);
    assert_eq!(default_port("", false), 993);
    // 大小写敏感：IMAP 会掉进兜底分支（normalized() 先小写化，所以链路里不出问题）
    assert_eq!(default_port("IMAP", true), 993);
    assert_eq!(default_port("IMAP", false), 993);
}

#[test]
fn normalized_backfills_port_and_defaults() {
    // port=0 时按协议 + use_ssl 回填
    let c = cfg(" POP3 ", "mail.example.com", false).normalized();
    assert_eq!((c.protocol.as_str(), c.port), ("pop3", 110));
    assert_eq!(cfg("imap", "x.test", true).normalized().port, 993);
    assert_eq!(cfg("smtp", "x.test", false).normalized().port, 587);
    // 显式端口不被覆盖
    let mut explicit = cfg("imap", "x.test", true);
    explicit.port = 2143;
    assert_eq!(explicit.normalized().port, 2143);
    // 未知协议 + 明文：回填到 993（IMAPS 端口），按现状锁定
    assert_eq!(cfg("carddav", "x.test", false).normalized().port, 993);
}

#[test]
fn normalized_trims_host_and_mailbox() {
    let mut c = cfg("imap", "  mail.example.com  ", true);
    c.mailbox = "   ".to_string();
    let c = c.normalized();
    assert_eq!(c.host, "mail.example.com");
    // 空白 mailbox 回落 INBOX
    assert_eq!(c.mailbox, "INBOX");
    // timeout_secs=0 视为未设置，回落到 25 秒
    assert_eq!(c.timeout_secs, 25);
    // 非空 mailbox 只 trim，不改大小写
    let mut c2 = cfg("imap", "x.test", true);
    c2.mailbox = "  INBOX/账单  ".to_string();
    c2.timeout_secs = 3;
    assert_eq!(c2.normalized().mailbox, "INBOX/账单");
    // 显式超时原样保留
    assert_eq!(c2.normalized().timeout_secs, 3);
    // normalized() 不修改原对象（纯函数）
    assert_eq!(c2.port, 0);
}

#[test]
fn serde_defaults_are_secure_by_default() {
    // 只给 protocol：use_ssl 默认 true，accept_invalid_certs 默认 false
    let raw = r#"{"protocol":"imap"}"#;
    let c: EmailAccountConfig = serde_json::from_str(raw).expect("最小配置应可解析");
    assert!(c.use_ssl, "use_ssl 缺省必须是 true");
    assert!(!c.accept_invalid_certs, "accept_invalid_certs 缺省必须是 false");
    assert_eq!(c.mailbox, "INBOX");
    assert_eq!(c.timeout_secs, 25);
    assert_eq!(c.port, 0);
    assert_eq!(c.host, "");
    assert!(c.is_tls_required_by_policy());
}

#[test]
fn serde_rejects_missing_protocol() {
    // protocol 没有 serde(default)：漏字段要在解析阶段就炸，而不是静默走兜底端口
    let e = serde_json::from_str::<EmailAccountConfig>(r#"{"host":"x.test"}"#);
    assert!(e.is_err());
    // 归一化后 JSON 往返保持一致
    let c = cfg("imap", "x.test", true).normalized();
    let text = serde_json::to_string(&c).unwrap();
    let back: EmailAccountConfig = serde_json::from_str(&text).unwrap();
    assert_eq!((back.protocol.as_str(), back.port, back.use_ssl), ("imap", 993, true));
    assert_eq!(back.password, "hunter2");
}
