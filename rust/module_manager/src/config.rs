/// 模块配置管理
use super::types::*;
use std::path::PathBuf;

/// 获取当前平台的标识符
/// 例如：darwin-aarch64, windows-x86_64
pub fn get_platform_key() -> String {
    let os = if cfg!(target_os = "macos") {
        "darwin"
    } else if cfg!(target_os = "windows") {
        "windows"
    } else if cfg!(target_os = "linux") {
        "linux"
    } else {
        std::env::consts::OS
    };

    let arch = if cfg!(target_arch = "x86_64") {
        "x86_64"
    } else if cfg!(target_arch = "aarch64") {
        "aarch64"
    } else if cfg!(target_arch = "x86") {
        "x86"
    } else {
        std::env::consts::ARCH
    };

    format!("{}-{}", os, arch)
}

/// 从 JSON 字符串解析模块配置
pub fn parse_modules_config(json: &str) -> Result<ModulesConfig, String> {
    serde_json::from_str(json).map_err(|e| format!("Failed to parse JSON: {}", e))
}

/// 从 URL 获取模块配置
pub async fn fetch_modules_config(url: &str) -> Result<ModulesConfig, String> {
    let response = reqwest::get(url)
        .await
        .map_err(|e| format!("Failed to fetch config: {}", e))?;

    if !response.status().is_success() {
        return Err(format!("HTTP error: {}", response.status()));
    }

    let text = response
        .text()
        .await
        .map_err(|e| format!("Failed to read response: {}", e))?;

    eprintln!("Fetched module config: {}", text);
    parse_modules_config(&text)
}

/// 获取模块的目标目录
/// - dynamic_library -> install_dir/dll/
/// - executable -> install_dir/bin/{module_name}/
pub fn get_module_directory(
    install_dir: &PathBuf,
    module_name: &str,
    module_type: &ModuleType,
) -> PathBuf {
    match module_type {
        ModuleType::DynamicLibrary | ModuleType::Library => install_dir.join("dll"),
        ModuleType::Executable => install_dir.join("bin").join(module_name),
    }
}

/// 构建完整的文件名（包含扩展名）
pub fn build_filename(version_info: &VersionInfo, module_type: &ModuleType) -> String {
    let add_lib_prefix = matches!(
        module_type,
        ModuleType::DynamicLibrary | ModuleType::Library
    ) && (cfg!(target_os = "macos") || cfg!(target_os = "linux"));

    let base = version_info.to_filename_base(add_lib_prefix);

    match module_type {
        ModuleType::DynamicLibrary | ModuleType::Library => {
            if cfg!(target_os = "windows") {
                format!("{}.dll", base)
            } else if cfg!(target_os = "macos") {
                format!("{}.dylib", base)
            } else if cfg!(target_os = "linux") {
                format!("{}.so", base)
            } else {
                // Fallback: no extension
                base
            }
        }
        ModuleType::Executable => {
            #[cfg(target_os = "windows")]
            {
                format!("{}.exe", base)
            }
            #[cfg(not(target_os = "windows"))]
            {
                base
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_platform_key() {
        let key = get_platform_key();
        println!("Platform key: {}", key);
        assert!(key.contains("-"));
    }

    #[test]
    fn test_build_filename() {
        let version_info =
            VersionInfo::new("capture_proxy".to_string(), "1.2.0+23".to_string(), false);
        let module_type = ModuleType::DynamicLibrary;
        let filename = build_filename(&version_info, &module_type);

        #[cfg(target_os = "windows")]
        assert_eq!(filename, "capture_proxy_1-2-0-23.dll");

        #[cfg(target_os = "macos")]
        assert_eq!(filename, "libcapture_proxy_1-2-0-23.dylib");
    }
}
