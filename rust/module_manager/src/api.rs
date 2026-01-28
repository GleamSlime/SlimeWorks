/// 模块管理系统 API
/// 
/// 对外暴露的所有模块管理功能（纯 Rust，不依赖 FRB）
use super::{ModuleManager, ModuleLoader, InstalledModule};
use std::path::PathBuf;

// ============================================================================
// 模块管理器 API
// ============================================================================

/// 创建模块管理器
/// 
/// # 参数
/// - install_dir: 安装目录（会创建 dll/ 和 bin/ 子目录）
/// - config_url: 模块配置 JSON 的 URL
pub fn create_module_manager(install_dir: String, config_url: String) -> ModuleManager {
    ModuleManager::new(PathBuf::from(install_dir), config_url)
}

/// 检查模块是否有更新
/// 
/// 返回：Some(version) 表示有新版本，None 表示已是最新或锁定版本
pub async fn module_check_update(
    manager: &ModuleManager,
    module_name: String,
) -> Result<Option<String>, String> {
    manager.check_for_update(&module_name).await
}

/// 安装模块
/// 
/// # 参数
/// - manager: 模块管理器
/// - module_name: 模块名（如 "capture_proxy", "ffmpeg"）
/// - version: 指定版本（None 为最新版，如 "1.2.0+23"）
/// - lock_version: 是否锁定版本（文件名会带 _lock 后缀）
/// - auto_load: 是否自动加载（仅对动态库有效）
/// 
/// 返回：安装后的文件路径
pub async fn module_install(
    manager: &ModuleManager,
    module_name: String,
    version: Option<String>,
    lock_version: bool,
    auto_load: bool,
) -> Result<String, String> {
    manager.install_module(&module_name, version, lock_version, auto_load).await
}

/// 列出模块的已安装版本
pub fn module_list_versions(
    manager: &ModuleManager,
    module_name: String,
) -> Result<Vec<InstalledModule>, String> {
    manager.list_installed_versions(&module_name)
}

/// 卸载模块
/// 
/// # 参数
/// - manager: 模块管理器
/// - module_name: 模块名
/// - version: 指定版本（None 表示卸载所有版本）
/// 
/// 返回：卸载的文件数量
pub fn module_uninstall(
    manager: &ModuleManager,
    module_name: String,
    version: Option<String>,
) -> Result<usize, String> {
    manager.uninstall_module(&module_name, version)
}

/// 重新安装模块（先卸载再安装）
pub async fn module_reinstall(
    manager: &ModuleManager,
    module_name: String,
    version: Option<String>,
    lock_version: bool,
    auto_load: bool,
) -> Result<String, String> {
    manager.reinstall_module(&module_name, version, lock_version, auto_load).await
}

/// 列出所有已安装的模块
pub fn module_list_all(manager: &ModuleManager) -> Result<Vec<InstalledModule>, String> {
    manager.list_all_modules()
}

// ============================================================================
// 模块加载器 API（仅用于动态库）
// ============================================================================

/// 创建模块加载器
pub fn create_module_loader(install_dir: String) -> ModuleLoader {
    ModuleLoader::new(PathBuf::from(install_dir))
}

/// 加载动态库模块
/// 
/// # 参数
/// - loader: 模块加载器
/// - module_name: 模块名
/// - version: 指定版本（None 表示自动选择最新或锁定版本）
pub fn module_load(
    loader: &ModuleLoader,
    module_name: String,
    version: Option<String>,
) -> Result<(), String> {
    loader.load_module(&module_name, version)
}

/// 卸载动态库模块
pub fn module_unload(loader: &ModuleLoader, module_name: String) -> Result<(), String> {
    loader.unload_module(&module_name)
}

/// 检查模块是否已加载
pub fn module_is_loaded(loader: &ModuleLoader, module_name: String) -> bool {
    loader.is_loaded(&module_name)
}

/// 列出所有已加载的模块
pub fn module_list_loaded(loader: &ModuleLoader) -> Vec<String> {
    loader.list_loaded_modules()
}

/// 重新加载模块
pub fn module_reload(
    loader: &ModuleLoader,
    module_name: String,
    version: Option<String>,
) -> Result<(), String> {
    loader.reload_module(&module_name, version)
}
