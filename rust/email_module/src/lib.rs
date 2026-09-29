//! 邮件收取模块：同步实现的 IMAP / POP3 / SMTP 客户端 + MIME 解析。
//!
//! 为什么全部手写而不用现成 crate：本项目要能离线构建（crates.io 不可达），
//! imap / pop3 / mailparse / lettre 这一串都不在本地缓存里，而
//! native-tls / encoding_rs / chardetng / base64 在。协议本身是文本行协议，
//! 手写换来的是零额外依赖和完全可控的超时。
//!
//! 分层：
//! - net：TCP + TLS 的最小连接体（带读超时、行读、定长读）
//! - mime：RFC822 头、RFC2047 编码词、multipart、base64/QP、字符集
//! - imap / pop3 / smtp：三个协议客户端，只做取信与自检
//! - eas / carddav：本期只占位，调用即返回"尚未实现"
//! - dispatch：按协议分流
//! - api：FFI 侧的 JSON 字符串接口

pub mod api;
pub mod carddav;
pub mod dispatch;
pub mod eas;
pub mod imap;
pub mod mime;
pub mod net;
pub mod pop3;
pub mod smtp;
pub mod types;
