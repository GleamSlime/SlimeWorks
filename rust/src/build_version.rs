//! 构建版本号。
//!
//! CI 在编译无头节点时通过 `SLIME_BUILD_VERSION` 注入形如 `1.0.0+20261117.abcdef`
//! 的完整版本（与 Release tag 去 `v` 后一致），自更新靠它判断是否比线上新。
//! 本地开发没有注入，回落到 crate 版本，保证 `--version` 永远有输出。

pub const BUILD_VERSION: &str = match option_env!("SLIME_BUILD_VERSION") {
    Some(v) => v,
    None => env!("CARGO_PKG_VERSION"),
};
