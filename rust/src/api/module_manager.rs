/// Flutter Rust Bridge API - 模块管理系统
///
/// 这个文件只负责将 module_manager crate 的功能暴露给 Flutter
/// 所有业务逻辑都在独立的 module_manager crate 中
use crate::constants::env::Env;
use flutter_rust_bridge::frb;
use std::path::PathBuf;

// 重新导出类型供 FRB 生成的代码使用
pub use libloading::Library;
pub use module_manager::{ModuleLoader, ModuleManager};

// FRB 需要的类型定义（直接定义以支持序列化）
/// 模块类型
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub enum ModuleType {
    /// 动态链接库（Windows .dll）
    DynamicLibrary,
    /// 可执行文件（Windows .exe / Linux-macOS binary）
    Executable,
}

/// 已安装的模块信息
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
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

/// 可用的模块信息
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct AvailableModuleInfo {
    /// 模块名
    pub name: String,
    /// 最新版本
    pub version: String,
    /// 模块类型
    pub module_type: ModuleType,
    /// 描述
    pub description: String,
}

// 内部转换辅助函数
fn convert_module(m: module_manager::InstalledModule) -> InstalledModule {
    InstalledModule {
        module_name: m.module_name,
        version: m.version,
        is_locked: m.is_locked,
        file_path: m.file_path,
        module_type: match m.module_type {
            #[allow(deprecated)]
            module_manager::ModuleType::Library => ModuleType::DynamicLibrary,
            module_manager::ModuleType::DynamicLibrary => ModuleType::DynamicLibrary,
            module_manager::ModuleType::Executable => ModuleType::Executable,
        },
        file_size: m.file_size,
        installed_at: m.installed_at,
    }
}

fn convert_module_info(m: module_manager::ModuleInfo) -> AvailableModuleInfo {
    AvailableModuleInfo {
        name: m.name,
        version: m.version,
        module_type: match m.module_type {
            #[allow(deprecated)]
            module_manager::ModuleType::Library => ModuleType::DynamicLibrary,
            module_manager::ModuleType::DynamicLibrary => ModuleType::DynamicLibrary,
            module_manager::ModuleType::Executable => ModuleType::Executable,
        },
        description: m.description,
    }
}

// ============================================================================
// 模块管理器 API
// ============================================================================

/// 创建模块管理器
///
/// # 参数
/// - install_dir: 安装目录（会创建 dll/ 和 bin/ 子目录）
///
/// 配置 URL 使用 Env::MODULE_CONFIG
#[frb(sync)]
pub fn create_module_manager(install_dir: String) -> ModuleManager {
    ModuleManager::new(PathBuf::from(install_dir), Env::MODULE_CONFIG.to_string())
}

/// 获取可用的模块列表（从配置）
///
/// 返回所有可以安装的模块信息
pub async fn module_get_available(
    manager: &ModuleManager,
) -> Result<Vec<AvailableModuleInfo>, String> {
    manager
        .get_available_modules()
        .await
        .map(|modules| modules.into_iter().map(convert_module_info).collect())
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
    manager
        .install_module(&module_name, version, lock_version, auto_load)
        .await
}

/// 卸载模块
///
/// # 参数
/// - module_name: 模块名
/// - version: 指定版本（None 为卸载所有版本）
///
/// 返回：删除的文件数量
pub fn module_uninstall(
    manager: &ModuleManager,
    module_name: String,
    version: Option<String>,
) -> Result<usize, String> {
    manager.uninstall_module(&module_name, version)
}

/// 重新安装模块
///
/// # 参数
/// - module_name: 模块名
/// - version: 指定版本（None 为最新版）
/// - lock_version: 是否锁定版本
/// - auto_load: 是否自动加载（仅对动态库有效）
pub async fn module_reinstall(
    manager: &ModuleManager,
    module_name: String,
    version: Option<String>,
    lock_version: bool,
    auto_load: bool,
) -> Result<String, String> {
    manager
        .reinstall_module(&module_name, version, lock_version, auto_load)
        .await
}

/// 列出模块的已安装版本
///
/// 返回按版本号降序排列的版本列表
pub fn module_list_versions(
    manager: &ModuleManager,
    module_name: String,
) -> Result<Vec<InstalledModule>, String> {
    manager
        .list_installed_versions(&module_name)
        .map(|modules| modules.into_iter().map(convert_module).collect())
}

/// 列出所有已安装的模块
pub fn module_list_all(manager: &ModuleManager) -> Result<Vec<InstalledModule>, String> {
    manager
        .list_all_modules()
        .map(|modules| modules.into_iter().map(convert_module).collect())
}

// ============================================================================
// 模块加载器 API（仅用于动态库）
// ============================================================================

/// 创建模块加载器
#[frb(sync)]
pub fn create_module_loader(install_dir: String) -> ModuleLoader {
    ModuleLoader::new(PathBuf::from(install_dir))
}

/// 加载动态库模块
///
/// # 参数
/// - module_name: 模块名
/// - version: 指定版本（None 为自动选择最新版本）
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

/// 重新加载模块
pub fn module_reload(
    loader: &ModuleLoader,
    module_name: String,
    version: Option<String>,
) -> Result<(), String> {
    loader.reload_module(&module_name, version)
}

/// 检查模块是否已加载
#[frb(sync)]
pub fn module_is_loaded(loader: &ModuleLoader, module_name: String) -> bool {
    loader.is_loaded(&module_name)
}

/// 列出所有已加载的模块
#[frb(sync)]
pub fn module_list_loaded(loader: &ModuleLoader) -> Vec<String> {
    loader.list_loaded_modules()
}
