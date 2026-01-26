/// 动态模块加载器
///
/// 负责加载和管理动态链接库（.dll / .dylib / .so）
use libloading::{Library, Symbol};
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};
use std::path::PathBuf;
use std::sync::Mutex;

use super::module_downloader::ModuleDownloader;

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
            return Ok(());
        }

        unsafe {
            let lib = Library::new(lib_path)
                .map_err(|e| format!("Failed to load library {}: {}", lib_path, e))?;

            // 调用模块初始化函数
            let init_fn: Symbol<extern "C" fn() -> *const CModuleInfo> = lib
                .get(b"module_init")
                .map_err(|e| format!("Failed to find module_init: {}", e))?;

            let module_info_ptr = init_fn();
            if module_info_ptr.is_null() {
                return Err("module_init returned null".to_string());
            }

            let module_info = &*module_info_ptr;
            let name_str = CStr::from_ptr(module_info.name).to_string_lossy();
            let version_str = CStr::from_ptr(module_info.version).to_string_lossy();

            println!(
                "Loaded module: {} v{} (API: {})",
                name_str, version_str, module_info.api_version
            );

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

/// Capture Proxy 模块包装器
pub struct CaptureProxyModule;

impl CaptureProxyModule {
    /// 确保模块已加载
    fn ensure_loaded(install_dir: &str) -> Result<(), String> {
        let mut manager = MODULE_MANAGER.lock().unwrap();

        // 如果已加载，直接返回
        if manager.loaded_modules.contains_key("capture_proxy") {
            return Ok(());
        }

        // 获取模块路径
        let downloader = ModuleDownloader::new(PathBuf::from(install_dir));
        let module_path = downloader.get_executable_path("capture_proxy", "capture_proxy");

        #[cfg(target_os = "windows")]
        let lib_path = module_path.with_extension("dll");
        #[cfg(target_os = "macos")]
        let lib_path = module_path.with_extension("dylib");
        #[cfg(target_os = "linux")]
        let lib_path = module_path.with_extension("so");

        if !lib_path.exists() {
            return Err(format!(
                "Capture proxy module not found at: {}",
                lib_path.display()
            ));
        }

        manager.load_module("capture_proxy", lib_path.to_str().unwrap())?;
        Ok(())
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
