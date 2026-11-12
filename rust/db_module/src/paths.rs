//! 应用数据根目录的平台分支。
//!
//! 抽到基础层是因为各业务模块历史上各抄了一份：抄漏平台分支（只读 APPDATA）
//! 在 macOS 上会退化成相对路径 "."，正式版由 Finder 启动时 CWD=/ 不可写，
//! 模型/数据库目录创建静默失败，功能表现为"下载永远失败"。
//! 这里保持与 music_player 完全一致的分支口径，便于之后统一迁移。

use std::path::{Path, PathBuf};

/// 平台分支：测试要能注入，所以不直接用 cfg! 一步算完
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AppDataPlatform {
    Windows,
    MacOs,
    Other,
}

/// 当前编译目标对应的平台
pub fn current_platform() -> AppDataPlatform {
    #[cfg(windows)]
    {
        AppDataPlatform::Windows
    }
    #[cfg(target_os = "macos")]
    {
        AppDataPlatform::MacOs
    }
    #[cfg(not(any(windows, target_os = "macos")))]
    {
        AppDataPlatform::Other
    }
}

/// 按平台规则算数据根目录。
///
/// 环境变量缺失时回落 "."：宁可写到当前目录，也不要让调用方拿到空路径
/// （空路径 join 出来是相对路径，行为更难排查）。
pub fn resolve_app_data_base(platform: AppDataPlatform, get_env: impl Fn(&str) -> Option<String>) -> String {
    let env_or = |key: &str| get_env(key).unwrap_or_default();
    match platform {
        AppDataPlatform::Windows => {
            let appdata = env_or("APPDATA");
            if appdata.is_empty() {
                ".".to_string()
            } else {
                appdata
            }
        }
        AppDataPlatform::MacOs => {
            let home = env_or("HOME");
            if home.is_empty() {
                ".".to_string()
            } else {
                format!("{}/Library/Application Support", home)
            }
        }
        AppDataPlatform::Other => {
            let xdg = env_or("XDG_DATA_HOME");
            if !xdg.is_empty() {
                return xdg;
            }
            let home = env_or("HOME");
            if home.is_empty() {
                ".".to_string()
            } else {
                format!("{}/.local/share", home)
            }
        }
    }
}

/// 当前进程的数据根目录（APPDATA / ~/Library/Application Support / XDG）
pub fn app_data_base() -> String {
    resolve_app_data_base(current_platform(), |key| std::env::var(key).ok())
}

/// 某应用专属的数据目录，顺带确保目录存在。
///
/// 建目录失败不在这里报错：调用方通常紧接着就要写文件，
/// 那里会有更贴近业务的中文错误信息，此处多一层只会把错误淹掉。
pub fn app_data_dir(app_name: &str) -> PathBuf {
    let dir = Path::new(&app_data_base()).join(app_name);
    let _ = std::fs::create_dir_all(&dir);
    dir
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    /// 用闭包注入环境变量，避免改动真实进程环境（并行测试里改 env 会互相踩）
    fn env_of(pairs: &[(&str, &str)]) -> impl Fn(&str) -> Option<String> {
        let map: HashMap<String, String> = pairs
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect();
        move |key: &str| map.get(key).cloned()
    }

    #[test]
    fn windows_uses_appdata() {
        let base = resolve_app_data_base(
            AppDataPlatform::Windows,
            env_of(&[("APPDATA", r"C:\Users\me\AppData\Roaming")]),
        );
        assert_eq!(base, r"C:\Users\me\AppData\Roaming");
        // 有 HOME 但没 APPDATA 时不能去用 HOME：Windows 下 APPDATA 才是漫游目录
        let base = resolve_app_data_base(
            AppDataPlatform::Windows,
            env_of(&[("HOME", r"C:\Users\me")]),
        );
        assert_eq!(base, ".");
    }

    #[test]
    fn macos_uses_application_support() {
        let base = resolve_app_data_base(
            AppDataPlatform::MacOs,
            env_of(&[("HOME", "/Users/me")]),
        );
        assert_eq!(base, "/Users/me/Library/Application Support");
        // 关键回归：macOS 上 APPDATA 不存在，早期实现因此退化成相对路径 "."
        let base = resolve_app_data_base(
            AppDataPlatform::MacOs,
            env_of(&[("HOME", "/Users/me"), ("APPDATA", "/nope")]),
        );
        assert_eq!(base, "/Users/me/Library/Application Support");
        assert_eq!(resolve_app_data_base(AppDataPlatform::MacOs, env_of(&[])), ".");
    }

    #[test]
    fn other_platforms_prefer_xdg_then_home() {
        let base = resolve_app_data_base(
            AppDataPlatform::Other,
            env_of(&[("XDG_DATA_HOME", "/xdg"), ("HOME", "/home/me")]),
        );
        assert_eq!(base, "/xdg");
        let base = resolve_app_data_base(
            AppDataPlatform::Other,
            env_of(&[("HOME", "/home/me")]),
        );
        assert_eq!(base, "/home/me/.local/share");
        // 空串的 XDG 视为未设置
        let base = resolve_app_data_base(
            AppDataPlatform::Other,
            env_of(&[("XDG_DATA_HOME", ""), ("HOME", "/home/me")]),
        );
        assert_eq!(base, "/home/me/.local/share");
        assert_eq!(resolve_app_data_base(AppDataPlatform::Other, env_of(&[])), ".");
    }

    #[test]
    fn app_data_dir_keeps_the_platform_suffix() {
        // 真实环境只做形态断言：非空、以应用名结尾
        let dir = app_data_dir("SlimeWorks");
        assert_eq!(dir.file_name().and_then(|n| n.to_str()), Some("SlimeWorks"));
        if current_platform() == AppDataPlatform::MacOs {
            assert!(
                dir.to_string_lossy().contains("/Library/Application Support/"),
                "macOS 数据目录应在 Application Support 下，实际 {:?}",
                dir
            );
        }
    }
}
