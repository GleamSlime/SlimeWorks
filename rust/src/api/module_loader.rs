/// 动态模块加载器
///
/// 负责加载和管理动态链接库（.dll / .dylib / .so）
use libloading::{Library, Symbol};
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};
use std::path::PathBuf;
use std::sync::Mutex;
use log::{info, warn, error, debug};

use super::module_downloader::ModuleDownloader;
use super::logger::log_info;

lazy_static::lazy_static! {
    static ref MODULE_MANAGER: Mutex<ModuleManager> = Mutex::new(ModuleManager::new());
}

/// 模块信息
#[derive(Debug, Clone)]
pub struct ModuleInfo {
    pub name: String,
    pub version: String,
    pub api_version: u32,
}

/// C ABI 模块信息结构
#[repr(C)]
struct CModuleInfo {
    name: *const c_char,
    version: *const c_char,
    api_version: u32,
}

/// 模块管理器
struct ModuleManager {
    loaded_modules: std::collections::HashMap<String, Library>,
}

impl ModuleManager {
    fn new() -> Self {
        Self {
            loaded_modules: std::collections::HashMap::new(),
        }
    }

    /// 加载模块
    fn load_module(&mut self, name: &str, lib_path: &str) -> Result<(), String> {
        if self.loaded_modules.contains_key(name) {
            log_info(&format!("Module {} already loaded", name));
            return Ok(());
        }

        log_info(&format!("Loading module from: {}", lib_path));

        // 检查文件是否存在
        if !std::path::Path::new(lib_path).exists() {
            let err = format!("Module library file not found: {}", lib_path);
            error!("{}", err);
            log_info(&err);
            return Err(err);
        }

        unsafe {
            let lib = Library::new(lib_path)
                .map_err(|e| {
                    let err = format!("Failed to load library {}: {}", lib_path, e);
                    error!("{}", err);
                    log_info(&err);
                    err
                })?;

            // 调用模块初始化函数
            let init_fn: Symbol<extern "C" fn() -> *const CModuleInfo> = lib
                .get(b"module_init")
                .map_err(|e| {
                    let err = format!("Failed to find module_init: {}", e);
                    error!("{}", err);
                    log_info(&err);
                    err
                })?;

            let module_info_ptr = init_fn();
            if module_info_ptr.is_null() {
                let err = "module_init returned null".to_string();
                error!("{}", err);
                log_info(&err);
                return Err(err);
            }

            let module_info = &*module_info_ptr;
            let name_str = CStr::from_ptr(module_info.name).to_string_lossy();
            let version_str = CStr::from_ptr(module_info.version).to_string_lossy();

            let success_msg = format!(
                "Loaded module: {} v{} (API: {})",
                name_str, version_str, module_info.api_version
            );
            info!("{}", success_msg);
            log_info(&success_msg);
            println!("{}", success_msg);

            self.loaded_modules.insert(name.to_string(), lib);
            Ok(())
        }
    }

    /// 卸载模块
    fn unload_module(&mut self, name: &str) -> Result<(), String> {
        self.loaded_modules
            .remove(name)
            .ok_or_else(|| format!("Module {} not loaded", name))?;
        Ok(())
    }

    /// 获取模块
    fn get_module(&self, name: &str) -> Result<&Library, String> {
        self.loaded_modules
            .get(name)
            .ok_or_else(|| format!("Module {} not loaded", name))
    }
}

/// Capture Proxy 模块包装器（不对外暴露给 Dart）
pub struct CaptureProxyModule {}

impl CaptureProxyModule {
    /// 确保模块已加载（自动下载如果不存在）
    async fn ensure_loaded_async(install_dir: &str) -> Result<(), String> {
        let mut manager = MODULE_MANAGER.lock().unwrap();

        // 如果已加载，直接返回
        if manager.loaded_modules.contains_key("capture_proxy") {
            return Ok(());
        }

        drop(manager); // 释放锁，允许下载操作

        // 获取模块路径
        let downloader = ModuleDownloader::new(PathBuf::from(install_dir));
        let lib_path = downloader.get_library_path("capture_proxy", "capture_proxy");

        // 如果不存在，尝试下载
        if !lib_path.exists() {
            println!("Capture proxy module not found, attempting to download...");
            
            // 从环境变量或配置获取下载 URL
            let windows_url = std::env::var("CAPTURE_PROXY_WINDOWS_URL")
                .unwrap_or_default();
            let macos_url = std::env::var("CAPTURE_PROXY_MACOS_URL")
                .unwrap_or_default();

            if windows_url.is_empty() && macos_url.is_empty() {
                return Err(format!(
                    "Capture proxy module not found at: {} and no download URL configured",
                    lib_path.display()
                ));
            }

            #[cfg(target_os = "windows")]
            let ext = "dll";
            #[cfg(target_os = "macos")]
            let ext = "dylib";
            #[cfg(target_os = "linux")]
            let ext = "so";

            let lib_name = format!("capture_proxy.{}", ext);
            let module_config = super::module_downloader::ModuleConfig {
                name: "capture_proxy".to_string(),
                windows_url,
                macos_url,
                executable_name: lib_name,
            };

            downloader.download_module(&module_config).await?;
        }

        // 重新获取锁并加载模块
        let mut manager = MODULE_MANAGER.lock().unwrap();
        manager.load_module("capture_proxy", lib_path.to_str().unwrap())?;
        Ok(())
    }

    /// 确保模块已加载（同步版本，不自动下载）
    fn ensure_loaded(install_dir: &str) -> Result<(), String> {
        let mut manager = MODULE_MANAGER.lock().unwrap();

        // 如果已加载，直接返回
        if manager.loaded_modules.contains_key("capture_proxy") {
            debug!("Capture proxy module already loaded");
            return Ok(());
        }

        // 获取模块路径
        let downloader = ModuleDownloader::new(PathBuf::from(install_dir));
        let lib_path = downloader.get_library_path("capture_proxy", "capture_proxy");

        log_info(&format!("Checking for module at: {}", lib_path.display()));
        log_info(&format!("Install dir: {}", install_dir));

        // 检查多个可能的位置
        let mut checked_paths = vec![];
        let mut found_path: Option<PathBuf> = None;

        // 1. 标准位置（AppData）
        checked_paths.push(lib_path.clone());
        if lib_path.exists() {
            found_path = Some(lib_path.clone());
        }

        // 2. 开发环境位置（项目构建目录）
        if found_path.is_none() {
            let dev_path = PathBuf::from("build/windows/x64/runner/Release/modules/capture_proxy/capture_proxy.dll");
            checked_paths.push(dev_path.clone());
            if dev_path.exists() {
                log_info(&format!("Found module in dev location: {}", dev_path.display()));
                found_path = Some(dev_path);
            }
        }

        // 3. Rust target 目录
        if found_path.is_none() {
            let rust_path = PathBuf::from("rust/target/release/capture_proxy.dll");
            checked_paths.push(rust_path.clone());
            if rust_path.exists() {
                log_info(&format!("Found module in rust target: {}", rust_path.display()));
                found_path = Some(rust_path);
            }
        }

        match found_path {
            Some(path) => {
                let path_str = path.to_str().unwrap();
                log_info(&format!("Loading module from: {}", path_str));
                manager.load_module("capture_proxy", path_str)?;
                Ok(())
            }
            None => {
                let err_msg = format!(
                    "Capture proxy module not found. Checked locations:\n{}",
                    checked_paths
                        .iter()
                        .map(|p| format!("  - {}", p.display()))
                        .collect::<Vec<_>>()
                        .join("\n")
                );
                error!("{}", err_msg);
                log_info(&err_msg);
                Err(format!(
                    "{}\nPlease download it first using download_capture_proxy_module().",
                    err_msg
                ))
            }
        }
    }

    /// 启动代理
    pub fn start(port: u16, install_dir: &str) -> Result<String, String> {
        Self::ensure_loaded(install_dir)?;

        let manager = MODULE_MANAGER.lock().unwrap();
        let lib = manager.get_module("capture_proxy")?;

        unsafe {
            let start_fn: Symbol<extern "C" fn(u16) -> c_int> =
                lib.get(b"proxy_start").map_err(|e| e.to_string())?;

            let result = start_fn(port);
            match result {
                0 => Ok(format!("Proxy started on port {}", port)),
                -1 => Err("Proxy already running".to_string()),
                _ => Err("Failed to start proxy".to_string()),
            }
        }
    }

    /// 停止代理
    pub fn stop(install_dir: &str) -> Result<String, String> {
        Self::ensure_loaded(install_dir)?;

        let manager = MODULE_MANAGER.lock().unwrap();
        let lib = manager.get_module("capture_proxy")?;

        unsafe {
            let stop_fn: Symbol<extern "C" fn() -> c_int> =
                lib.get(b"proxy_stop").map_err(|e| e.to_string())?;

            let result = stop_fn();
            match result {
                0 => Ok("Proxy stopped".to_string()),
                -1 => Err("Proxy not running".to_string()),
                _ => Err("Failed to stop proxy".to_string()),
            }
        }
    }

    /// 检查代理是否运行
    pub fn is_running(install_dir: &str) -> Result<bool, String> {
        Self::ensure_loaded(install_dir)?;

        let manager = MODULE_MANAGER.lock().unwrap();
        let lib = manager.get_module("capture_proxy")?;

        unsafe {
            let is_running_fn: Symbol<extern "C" fn() -> c_int> =
                lib.get(b"proxy_is_running").map_err(|e| e.to_string())?;

            Ok(is_running_fn() != 0)
        }
    }

    /// 获取捕获的视频列表
    pub fn get_videos(install_dir: &str) -> Result<Vec<String>, String> {
        Self::ensure_loaded(install_dir)?;

        let manager = MODULE_MANAGER.lock().unwrap();
        let lib = manager.get_module("capture_proxy")?;

        unsafe {
            let get_videos_fn: Symbol<extern "C" fn() -> *mut c_char> = lib
                .get(b"proxy_get_videos_json")
                .map_err(|e| e.to_string())?;

            let free_fn: Symbol<extern "C" fn(*mut c_char)> =
                lib.get(b"proxy_free_string").map_err(|e| e.to_string())?;

            let json_ptr = get_videos_fn();
            if json_ptr.is_null() {
                return Ok(Vec::new());
            }

            let json_str = CStr::from_ptr(json_ptr).to_string_lossy().to_string();
            free_fn(json_ptr);

            serde_json::from_str(&json_str).map_err(|e| e.to_string())
        }
    }

    /// 清除捕获的数据
    pub fn clear_data(install_dir: &str) -> Result<(), String> {
        Self::ensure_loaded(install_dir)?;

        let manager = MODULE_MANAGER.lock().unwrap();
        let lib = manager.get_module("capture_proxy")?;

        unsafe {
            let clear_fn: Symbol<extern "C" fn()> =
                lib.get(b"proxy_clear_items").map_err(|e| e.to_string())?;

            clear_fn();
            Ok(())
        }
    }

    /// 安装 CA 证书
    pub fn install_certificate(password: &str, install_dir: &str) -> Result<(), String> {
        Self::ensure_loaded(install_dir)?;

        let manager = MODULE_MANAGER.lock().unwrap();
        let lib = manager.get_module("capture_proxy")?;

        unsafe {
            let install_fn: Symbol<extern "C" fn(*const c_char) -> c_int> = lib
                .get(b"proxy_install_certificate")
                .map_err(|e| e.to_string())?;

            let c_password = CString::new(password).unwrap();
            let result = install_fn(c_password.as_ptr());

            match result {
                0 => Ok(()),
                _ => Err("Failed to install certificate".to_string()),
            }
        }
    }

    /// 检查证书是否已安装
    pub fn is_certificate_installed(install_dir: &str) -> Result<bool, String> {
        Self::ensure_loaded(install_dir)?;

        let manager = MODULE_MANAGER.lock().unwrap();
        let lib = manager.get_module("capture_proxy")?;

        unsafe {
            let is_installed_fn: Symbol<extern "C" fn() -> c_int> = lib
                .get(b"proxy_is_certificate_installed")
                .map_err(|e| e.to_string())?;

            Ok(is_installed_fn() != 0)
        }
    }
}

// Flutter Rust Bridge 导出函数

/// 下载并加载 capture_proxy 模块
pub async fn download_capture_proxy_module(
    windows_url: String,
    macos_url: String,
    install_dir: String,
) -> Result<String, String> {
    let downloader = ModuleDownloader::new(PathBuf::from(&install_dir));

    let module_config = super::module_downloader::ModuleConfig {
        name: "capture_proxy".to_string(),
        windows_url,
        macos_url,
        executable_name: "capture_proxy".to_string(),
    };

    #[cfg(target_os = "windows")]
    let ext = "dll";
    #[cfg(target_os = "macos")]
    let ext = "dylib";
    #[cfg(target_os = "linux")]
    let ext = "so";

    // 修改 executable_name 为动态库名称
    let lib_name = format!("capture_proxy.{}", ext);
    let mut lib_config = module_config.clone();
    lib_config.executable_name = lib_name;

    let module_path = downloader.download_module(&lib_config).await?;

    Ok(format!("Module downloaded to: {}", module_path.display()))
}

/// 检查 capture_proxy 模块是否已下载
pub fn is_capture_proxy_downloaded(install_dir: String) -> bool {
    let downloader = ModuleDownloader::new(PathBuf::from(&install_dir));

    #[cfg(target_os = "windows")]
    let ext = "dll";
    #[cfg(target_os = "macos")]
    let ext = "dylib";
    #[cfg(target_os = "linux")]
    let ext = "so";

    let lib_name = format!("capture_proxy.{}", ext);
    downloader.is_module_installed("capture_proxy", &lib_name)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_module_manager() {
        let mut manager = ModuleManager::new();
        assert_eq!(manager.loaded_modules.len(), 0);
    }
}
