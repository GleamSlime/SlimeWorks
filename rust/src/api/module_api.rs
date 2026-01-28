/// 统一模块 API
///
/// 提供给 Flutter 的模块管理接口

use flutter_rust_bridge::frb;
use std::path::PathBuf;

use super::module_manager::{ModuleConfig, ModuleConfigs, ModuleManager, ModuleType};
use super::logger::log_info;

/// 检查模块是否已安装
#[frb(sync)]
pub fn is_module_installed(
    install_dir: String,
    module_name: String,
    module_type: ModuleType,
    file_name: String,
) -> bool {
    let manager = ModuleManager::new(PathBuf::from(install_dir));
    let config = ModuleConfig {
        name: module_name,
        module_type,
        version: String::new(), // 版本不影响安装检查
        windows_url: String::new(),
        macos_url: String::new(),
        file_name,
    };
    manager.is_module_installed(&config)
}

/// 获取已安装模块的版本
#[frb(sync)]
pub fn get_installed_module_version(
    install_dir: String,
    module_name: String,
) -> Option<String> {
    let manager = ModuleManager::new(PathBuf::from(install_dir));
    manager.get_installed_version(&module_name)
}

/// 检查模块是否需要更新
#[frb(sync)]
pub fn check_module_needs_update(
    install_dir: String,
    module_name: String,
    module_type: ModuleType,
    current_version: String,
    windows_url: String,
    macos_url: String,
    file_name: String,
) -> bool {
    let manager = ModuleManager::new(PathBuf::from(install_dir));
    let config = ModuleConfig {
        name: module_name,
        module_type,
        version: current_version,
        windows_url,
        macos_url,
        file_name,
    };
    manager.needs_update(&config)
}

/// 下载模块
pub async fn download_module(
    install_dir: String,
    module_name: String,
    module_type: ModuleType,
    version: String,
    windows_url: String,
    macos_url: String,
    file_name: String,
) -> Result<String, String> {
    log_info(&format!("Starting download for module: {}", module_name));
    
    let manager = ModuleManager::new(PathBuf::from(install_dir));
    let config = ModuleConfig {
        name: module_name.clone(),
        module_type,
        version: version.clone(),
        windows_url,
        macos_url,
        file_name,
    };

    manager.download_module(&config).await?;

    let file_path = manager.get_module_file_path(&config);
    Ok(format!(
        "Module {} version {} downloaded to: {}",
        module_name,
        version,
        file_path.display()
    ))
}

/// 下载 Capture Proxy 模块（便捷方法）
pub async fn download_capture_proxy_module(
    install_dir: String,
    version: String,
    windows_url: String,
    macos_url: String,
) -> Result<String, String> {
    download_module(
        install_dir,
        "capture_proxy".to_string(),
        ModuleType::Library,
        version,
        windows_url,
        macos_url,
        "capture_proxy".to_string(),
    )
    .await
}

/// 下载 FFmpeg 模块（便捷方法）
pub async fn download_ffmpeg_module(
    install_dir: String,
    version: String,
    windows_url: String,
    macos_url: String,
) -> Result<String, String> {
    download_module(
        install_dir,
        "ffmpeg".to_string(),
        ModuleType::Executable,
        version,
        windows_url,
        macos_url,
        "ffmpeg".to_string(),
    )
    .await
}

/// 获取模块文件路径
#[frb(sync)]
pub fn get_module_file_path(
    install_dir: String,
    module_name: String,
    module_type: ModuleType,
    file_name: String,
) -> String {
    let manager = ModuleManager::new(PathBuf::from(install_dir));
    let config = ModuleConfig {
        name: module_name,
        module_type,
        version: String::new(),
        windows_url: String::new(),
        macos_url: String::new(),
        file_name,
    };
    manager
        .get_module_file_path(&config)
        .to_string_lossy()
        .to_string()
}

/// 批量检查模块状态
#[derive(Debug, Clone)]
pub struct ModuleStatus {
    pub name: String,
    pub installed: bool,
    pub current_version: Option<String>,
    pub needs_update: bool,
}

/// 检查所有模块状态
pub async fn check_all_modules_status(
    install_dir: String,
    capture_proxy_version: String,
    capture_proxy_windows_url: String,
    capture_proxy_macos_url: String,
    ffmpeg_version: String,
    ffmpeg_windows_url: String,
    ffmpeg_macos_url: String,
) -> Vec<ModuleStatus> {
    let manager = ModuleManager::new(PathBuf::from(install_dir));

    let configs = vec![
        ModuleConfigs::capture_proxy(
            &capture_proxy_version,
            &capture_proxy_windows_url,
            &capture_proxy_macos_url,
        ),
        ModuleConfigs::ffmpeg(&ffmpeg_version, &ffmpeg_windows_url, &ffmpeg_macos_url),
    ];

    let mut statuses = Vec::new();

    for config in configs {
        let installed = manager.is_module_installed(&config);
        let current_version = manager.get_installed_version(&config.name);
        let needs_update = manager.needs_update(&config);

        statuses.push(ModuleStatus {
            name: config.name,
            installed,
            current_version,
            needs_update,
        });
    }

    statuses
}
