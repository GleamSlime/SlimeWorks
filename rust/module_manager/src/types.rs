/// 模块管理系统的类型定义
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// 模块类型
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ModuleType {
    /// 动态库模块（.dll / .dylib / .so）- 放在 dll/ 目录
    #[serde(rename = "dynamic_library")]
    DynamicLibrary,
    /// 可执行程序模块（.exe / 无扩展名）- 放在 bin/{module_name}/ 目录
    #[serde(rename = "executable")]
    Executable,
    /// 兼容旧代码：Library 别名指向 DynamicLibrary
    #[deprecated(note = "Use DynamicLibrary instead")]
    Library,
}

/// 平台信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlatformInfo {
    /// MD5 签名
    pub signature: String,
    /// 下载地址
    pub url: String,
}

/// 模块配置（从 JSON 解析）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModuleConfig {
    /// 版本号（如 "1.2.0+23"）
    pub version: String,
    /// 更新说明
    pub notes: String,
    /// 更新时间
    pub time: String,
    /// 模块类型
    #[serde(rename = "type")]
    pub module_type: ModuleType,
    /// 各平台信息
    pub platforms: HashMap<String, PlatformInfo>,
    /// 历史版本
    #[serde(default)]
    pub history: Vec<String>,
}

/// 模块信息列表（JSON 根对象）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModulesConfig {
    #[serde(flatten)]
    pub modules: HashMap<String, ModuleConfig>,
}

/// 版本信息（从文件名解析）
#[derive(Debug, Clone, PartialEq)]
pub struct VersionInfo {
    /// 模块名
    pub module_name: String,
    /// 版本号（如 "1-2-0-23"）
    pub version: String,
    /// 是否锁定版本
    pub is_locked: bool,
}

impl VersionInfo {
    /// 从文件名解析版本信息
    /// 例如：capture_proxy_1-2-0-23.dll -> VersionInfo { module_name: "capture_proxy", version: "1-2-0-23", is_locked: false }
    /// 例如：libcapture_proxy_1-2-0-23_lock.dylib -> VersionInfo { module_name: "capture_proxy", version: "1-2-0-23", is_locked: true }
    pub fn from_filename(filename: &str) -> Option<Self> {
        // 移除扩展名
        let name = filename
            .strip_suffix(".dll")
            .or_else(|| filename.strip_suffix(".dylib"))
            .or_else(|| filename.strip_suffix(".so"))
            .or_else(|| filename.strip_suffix(".exe"))
            .unwrap_or(filename);

        // 移除 lib 前缀（如果有）
        let name = name.strip_prefix("lib").unwrap_or(name);

        // 检查是否锁定版本
        let (name, is_locked) = if let Some(base) = name.strip_suffix("_lock") {
            (base, true)
        } else {
            (name, false)
        };

        // 分割模块名和版本号
        // 例如：capture_proxy_1-2-0-23 -> ["capture_proxy", "1-2-0-23"]
        let parts: Vec<&str> = name.rsplitn(2, '_').collect();
        if parts.len() != 2 {
            return None;
        }

        let version = parts[0];
        let module_name = parts[1];

        // 验证版本号格式（应该包含 - 分隔符）
        if !version.contains('-') {
            return None;
        }

        Some(VersionInfo {
            module_name: module_name.to_string(),
            version: version.to_string(),
            is_locked,
        })
    }

    /// 转换为带版本号的文件名（不含扩展名）
    /// 例如：capture_proxy_1-2-0-23 或 capture_proxy_1-2-0-23_lock
    pub fn to_filename_base(&self, add_lib_prefix: bool) -> String {
        let prefix = if add_lib_prefix { "lib" } else { "" };
        let lock_suffix = if self.is_locked { "_lock" } else { "" };
        format!(
            "{}{}_{}{}",
            prefix, self.module_name, self.version, lock_suffix
        )
    }

    /// 将版本号从 "1.2.0+23" 格式转换为 "1-2-0-23" 格式
    pub fn normalize_version(version: &str) -> String {
        version.replace('.', "-").replace('+', "-")
    }

    /// 从标准版本号创建
    pub fn new(module_name: String, version: String, is_locked: bool) -> Self {
        Self {
            module_name,
            version: Self::normalize_version(&version),
            is_locked,
        }
    }
}

/// 已安装的模块信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InstalledModule {
    /// 模块名
    pub module_name: String,
    /// 版本号
    pub version: String,
    /// 是否锁定版本
    pub is_locked: bool,
    /// 文件路径
    pub file_path: String,
    /// 模块类型
    pub module_type: ModuleType,
    /// 文件大小
    pub file_size: u64,
    /// 安装时间
    pub installed_at: String,
}

/// 可用的模块信息（从配置获取）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModuleInfo {
    /// 模块名
    pub name: String,
    /// 最新版本
    pub version: String,
    /// 模块类型
    pub module_type: ModuleType,
    /// 描述
    pub description: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_version_info_parsing() {
        // 测试动态库（Windows）
        let info = VersionInfo::from_filename("capture_proxy_1-2-0-23.dll").unwrap();
        assert_eq!(info.module_name, "capture_proxy");
        assert_eq!(info.version, "1-2-0-23");
        assert_eq!(info.is_locked, false);

        // 测试锁定版本（macOS）
        let info = VersionInfo::from_filename("libcapture_proxy_1-2-0-23_lock.dylib").unwrap();
        assert_eq!(info.module_name, "capture_proxy");
        assert_eq!(info.version, "1-2-0-23");
        assert_eq!(info.is_locked, true);

        // 测试可执行文件
        let info = VersionInfo::from_filename("ffmpeg_6-0-1-5.exe").unwrap();
        assert_eq!(info.module_name, "ffmpeg");
        assert_eq!(info.version, "6-0-1-5");
        assert_eq!(info.is_locked, false);
    }

    #[test]
    fn test_version_normalize() {
        assert_eq!(VersionInfo::normalize_version("1.2.0+23"), "1-2-0-23");
        assert_eq!(VersionInfo::normalize_version("6.0.1+5"), "6-0-1-5");
    }
}
