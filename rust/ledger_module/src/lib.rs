//! 流水账模块：账户/类别/流水的本地存储，以及"邮件自动记账"的规则、收取与入账编排。
//!
//! 分层：
//! - storage：SQLite 读写（账本唯一事实源）
//! - parser / parser_types：账单模板引擎（HTML 拉平成文本后按语义抓行）
//! - parse_glue：把 email_module 的模板识别 + 本地模板引擎拼成一次解析
//! - scheduler：到点自动检查规则的后台线程
//! - api：FFI 侧的 JSON 字符串接口

pub mod api;
pub mod parse_glue;
pub mod parser;
pub mod parser_types;
pub mod scheduler;
pub mod storage;
pub mod types;
