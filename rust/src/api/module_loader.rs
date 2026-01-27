/// 动态模块加载器
///
/// 负责加载和管理动态链接库（.dll / .dylib / .so）
use libloading::{Library, Symbol};
use log::{debug, error, info, warn};
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};
use std::path::PathBuf;
use std::sync::Mutex;

use super::logger::log_info;
use super::module_downloader::ModuleDownloader;
use std::path::Path;

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
        info!(
            "[module_loader] load_module: checking existence for {}",
            lib_path
        );

        // 检查文件是否存在
        if !std::path::Path::new(lib_path).exists() {
            let err = format!("Module library file not found: {}", lib_path);
            error!("[module_loader] {}", err);
            log_info(&err);
            return Err(err);
        }

        unsafe {
            info!("[module_loader] attempting Library::new({})", lib_path);
            let lib = Library::new(lib_path).map_err(|e| {
                let err = format!("Failed to load library {}: {}", lib_path, e);
                error!("[module_loader] {}", err);
                log_info(&err);
                err
            })?;

            info!("[module_loader] library loaded, searching for module_init");
            // 调用模块初始化函数
            let init_fn: Symbol<extern "C" fn() -> *const CModuleInfo> =
                lib.get(b"module_init").map_err(|e| {
                    let err = format!("Failed to find module_init: {}", e);
                    error!("[module_loader] {}", err);
                    log_info(&err);
                    err
                })?;

            info!("[module_loader] calling module_init()");
            let module_info_ptr = init_fn();
            if module_info_ptr.is_null() {
                let err = "module_init returned null".to_string();
                error!("[module_loader] {}", err);
                log_info(&err);
                return Err(err);
            }

            info!("[module_loader] module_init returned non-null pointer");
            let module_info = &*module_info_ptr;
            let name_str = unsafe { CStr::from_ptr(module_info.name) }.to_string_lossy();
            let version_str = unsafe { CStr::from_ptr(module_info.version) }.to_string_lossy();

            let success_msg = format!(
                "Loaded module: {} v{} (API: {})",
                name_str, version_str, module_info.api_version
            );
            info!("[module_loader] {}", success_msg);
            log_info(&success_msg);
            println!("{}", success_msg);

            self.loaded_modules.insert(name.to_string(), lib);
            info!("[module_loader] inserted library into loaded_modules");
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
/// 注意: 移动端(iOS/Android)不支持动态加载,需要静态编译
pub struct CaptureProxyModule {}

impl CaptureProxyModule {
    /// 尝试从若干候选 `.env` 文件加载到进程环境中（使用 `dotenvy`，更可靠）
    fn try_load_env_files(install_dir: &str) {
        // 候选路径：install_dir/.env、当前可执行文件目录的上溯路径、当前工作目录的上溯路径
        let mut candidates = vec![Path::new(install_dir).join(".env")];

        // 可执行文件目录
        if let Ok(exe) = std::env::current_exe() {
            if let Some(dir) = exe.parent() {
                // 向上查找几个层级
                let mut p = dir.to_path_buf();
                for _ in 0..4 {
                    candidates.push(p.join(".env"));
                    if !p.pop() {
                        break;
                    }
                }
            }
        }

        // 当前工作目录向上查找
        if let Ok(mut cwd) = std::env::current_dir() {
            for _ in 0..6 {
                candidates.push(cwd.join(".env"));
                if !cwd.pop() {
                    break;
                }
            }
        }

        // 去重并尝试加载第一个存在的 .env
        use std::collections::HashSet;
        let mut seen = HashSet::new();
        for cand in candidates {
            let path = cand;
            if let Some(s) = path.to_str() {
                if seen.contains(s) {
                    continue;
                }
                seen.insert(s.to_string());
            }
            if path.exists() {
                match dotenvy::from_path_iter(&path) {
                    Ok(iter) => {
                        for item in iter {
                            if let Ok((k, v)) = item {
                                if std::env::var(&k).is_err() {
                                    std::env::set_var(&k, v);
                                }
                            }
                        }
                        log_info(&format!("Loaded environment from {}", path.display()));
                        return;
                    }
                    Err(e) => {
                        log_info(&format!("Failed to parse .env {}: {}", path.display(), e));
                    }
                }
            }
        }
    }
    /// 确保模块已加载（自动下载如果不存在）
    async fn ensure_loaded_async(install_dir: &str) -> Result<(), String> {
        let manager = MODULE_MANAGER.lock().unwrap();

        // 如果已加载，直接返回
        if manager.loaded_modules.contains_key("capture_proxy") {
            drop(manager); // 释放锁
            return Ok(());
        }

        drop(manager); // 释放锁，允许下载操作

        // 获取模块路径
        let downloader = ModuleDownloader::new(PathBuf::from(install_dir));

        #[cfg(target_os = "windows")]
        let (lib_ext, lib_prefix) = ("dll", "");
        #[cfg(any(target_os = "macos", target_os = "ios"))]
        let (lib_ext, lib_prefix) = ("dylib", "lib");
        #[cfg(target_os = "linux")]
        let (lib_ext, lib_prefix) = ("so", "lib");

        // 优先使用带前缀的库名（macOS/Linux 使用 lib 前缀）
        let lib_filename_with_prefix = format!("{}capture_proxy.{}", lib_prefix, lib_ext);
        let lib_path = downloader.get_library_path("capture_proxy", &lib_filename_with_prefix);

        // 如果不存在，尝试下载
        if !lib_path.exists() {
            println!("Capture proxy module not found, attempting to download...");

            Self::try_load_env_files(install_dir);

            // 从环境变量或配置获取下载 URL
            let mut windows_url = std::env::var("CAPTURE_PROXY_WINDOWS_URL").unwrap_or_default();
            let mut macos_url = std::env::var("CAPTURE_PROXY_MACOS_URL").unwrap_or_default();

            println!("[module_loader] after try_load_env_files: CAPTURE_PROXY_WINDOWS_URL='{}' CAPTURE_PROXY_MACOS_URL='{}'", windows_url, macos_url);
            log_info(&format!("after try_load_env_files: CAPTURE_PROXY_WINDOWS_URL='{}' CAPTURE_PROXY_MACOS_URL='{}'", windows_url, macos_url));

            // 如果环境变量未配置，尝试从 install_dir/.env 或 当前工作目录的 .env 中读取
            if windows_url.is_empty() && macos_url.is_empty() {
                let candidates = vec![
                    PathBuf::from(install_dir).join(".env"),
                    PathBuf::from(".env"),
                ];
                for cand in candidates {
                    if cand.exists() {
                        if let Ok(content) = std::fs::read_to_string(&cand) {
                            for line in content.lines() {
                                let line = line.trim();
                                if line.is_empty() || line.starts_with('#') {
                                    continue;
                                }
                                if let Some((k, v)) = line.split_once('=') {
                                    let key = k.trim();
                                    let mut val = v.trim().to_string();
                                    if val.starts_with('"') && val.ends_with('"') && val.len() >= 2
                                    {
                                        val = val[1..val.len() - 1].to_string();
                                    }
                                    if key == "CAPTURE_PROXY_MACOS_URL" && macos_url.is_empty() {
                                        macos_url = val.clone();
                                    }
                                    if key == "CAPTURE_PROXY_WINDOWS_URL" && windows_url.is_empty()
                                    {
                                        windows_url = val.clone();
                                    }
                                }
                            }
                        }
                        // stop if we found any
                        if !windows_url.is_empty() || !macos_url.is_empty() {
                            break;
                        }
                    }
                }
            }

            if windows_url.is_empty() && macos_url.is_empty() {
                return Err(format!(
                    "Capture proxy module not found at: {} and no download URL configured({})",
                    lib_path.display(),
                    macos_url
                ));
            }

            #[cfg(target_os = "windows")]
            let ext = "dll";
            #[cfg(target_os = "macos")]
            let ext = "dylib";
            #[cfg(target_os = "linux")]
            let ext = "so";

            // 下载时使用带前缀的库名（macOS/Linux 使用 lib 前缀）
            let lib_name = lib_filename_with_prefix.clone();
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
        drop(manager); // 立即释放锁
        Ok(())
    }

    /// 确保模块已加载（同步版本，不自动下载）
    fn ensure_loaded(install_dir: &str) -> Result<(), String> {
        let mut manager = MODULE_MANAGER.lock().unwrap();

        // 如果已加载，直接返回
        if manager.loaded_modules.contains_key("capture_proxy") {
            debug!("Capture proxy module already loaded");
            drop(manager); // 释放锁
            return Ok(());
        }

        // 获取模块路径
        let downloader = ModuleDownloader::new(PathBuf::from(install_dir));

        log_info(&format!("Install dir: {}", install_dir));

        // 根据平台确定文件扩展名和路径
        #[cfg(target_os = "windows")]
        let (lib_ext, platform_path, lib_prefix) = ("dll", "build/windows/x64/runner/Release", "");
        #[cfg(any(target_os = "macos", target_os = "ios"))]
        let (lib_ext, platform_path, lib_prefix) =
            ("dylib", "build/macos/Build/Products/Release", "lib");
        #[cfg(target_os = "linux")]
        let (lib_ext, platform_path, lib_prefix) = ("so", "build/linux/x64/release/bundle", "lib");

        // macOS/Linux 通常有 lib 前缀，但也要检查无前缀的版本
        let lib_filename_with_prefix = format!("{}capture_proxy.{}", lib_prefix, lib_ext);
        let lib_filename_no_prefix = format!("capture_proxy.{}", lib_ext);

        // 优先使用带前缀的路径作为初始检查路径
        let lib_path = downloader.get_library_path("capture_proxy", &lib_filename_with_prefix);

        log_info(&format!("Checking for module at: {}", lib_path.display()));

        // 检查多个可能的位置
        let mut checked_paths = vec![];
        let mut found_path: Option<PathBuf> = None;

        // 1. 标准位置（AppData）
        checked_paths.push(lib_path.clone());
        if lib_path.exists() {
            found_path = Some(lib_path.clone());
        }

        // 2. 开发环境位置（项目构建目录）- 检查有前缀和无前缀的版本
        if found_path.is_none() {
            for filename in &[&lib_filename_with_prefix, &lib_filename_no_prefix] {
                let dev_path = PathBuf::from(platform_path)
                    .join("modules")
                    .join("capture_proxy")
                    .join(filename);
                checked_paths.push(dev_path.clone());
                if dev_path.exists() {
                    log_info(&format!(
                        "Found module in dev location: {}",
                        dev_path.display()
                    ));
                    found_path = Some(dev_path);
                    break;
                }
            }
        }

        // 3. Rust target 目录 - 检查有前缀和无前缀的版本
        if found_path.is_none() {
            for filename in &[&lib_filename_with_prefix, &lib_filename_no_prefix] {
                let rust_path = PathBuf::from("rust/target/release").join(filename);
                checked_paths.push(rust_path.clone());
                if rust_path.exists() {
                    log_info(&format!(
                        "Found module in rust target: {}",
                        rust_path.display()
                    ));
                    found_path = Some(rust_path);
                    break;
                }
            }
        }

        match found_path {
            Some(path) => {
                let path_str = path.to_str().unwrap();
                log_info(&format!("Loading module from: {}", path_str));
                manager.load_module("capture_proxy", path_str)?;
                // 成功加载后立即释放锁
                drop(manager);
                Ok(())
            }
            None => {
                // 在返回错误前释放锁，避免应用卡住
                drop(manager);

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
        #[cfg(any(target_os = "ios", target_os = "android"))]
        {
            return Err("Dynamic module loading is not supported on mobile platforms. Please use static compilation.".to_string());
        }

        info!("[module_loader] start(): ensure_loaded start");
        println!("[module_loader] start(): ensure_loaded start");

        // 尝试同步确保已加载；如果失败（例如模块不存在），则在临时 Tokio 运行时中尝试异步下载并加载
        if let Err(e) = Self::ensure_loaded(install_dir) {
            info!(
                "[module_loader] start(): ensure_loaded failed: {}. attempting async download/load",
                e
            );
            println!(
                "[module_loader] start(): ensure_loaded failed: {}. attempting async download/load",
                e
            );
            // 创建临时运行时以执行异步下载/加载
            match tokio::runtime::Runtime::new() {
                Ok(rt) => {
                    let res = rt.block_on(Self::ensure_loaded_async(install_dir));
                    if let Err(e2) = res {
                        let err = format!("Failed to ensure module loaded asynchronously: {}", e2);
                        error!("[module_loader] {}", err);
                        return Err(err);
                    }
                }
                Err(e_rt) => {
                    let err = format!("Failed to create runtime for async download: {}", e_rt);
                    error!("[module_loader] {}", err);
                    return Err(err);
                }
            }
        }

        info!("[module_loader] start(): ensure_loaded done");
        println!("[module_loader] start(): ensure_loaded done");

        // 获取函数指针后立即释放锁，避免在 FFI 调用期间持有锁
        info!("[module_loader] start(): acquiring lock to get symbol");
        println!("[module_loader] start(): acquiring lock to get symbol");
        let start_fn: extern "C" fn(u16) -> c_int = {
            let manager = MODULE_MANAGER.lock().unwrap();
            let lib = manager.get_module("capture_proxy")?;
            info!("[module_loader] start(): got module reference, locating symbol proxy_start");
            println!("[module_loader] start(): got module reference, locating symbol proxy_start");
            unsafe {
                let symbol = lib
                    .get::<extern "C" fn(u16) -> c_int>(b"proxy_start")
                    .map_err(|e| e.to_string())?;
                let func = *symbol;
                info!("[module_loader] start(): symbol proxy_start located");
                println!("[module_loader] start(): symbol proxy_start located");
                func
            }
        }; // manager 在这里被释放
        info!(
            "[module_loader] start(): calling proxy_start with port {}",
            port
        );
        println!(
            "[module_loader] start(): calling proxy_start with port {}",
            port
        );
        let result = start_fn(port);
        info!("[module_loader] start(): proxy_start returned {}", result);
        println!("[module_loader] start(): proxy_start returned {}", result);
        match result {
            0 => Ok(format!("Proxy started on port {}", port)),
            -1 => Err("Proxy already running".to_string()),
            _ => Err("Failed to start proxy".to_string()),
        }
    }

    /// 停止代理
    pub fn stop(install_dir: &str) -> Result<String, String> {
        #[cfg(any(target_os = "ios", target_os = "android"))]
        {
            return Err("Dynamic module loading is not supported on mobile platforms.".to_string());
        }

        info!("[module_loader] stop(): ensure_loaded start");
        Self::ensure_loaded(install_dir)?;
        info!("[module_loader] stop(): ensure_loaded done");

        info!("[module_loader] stop(): acquiring lock to get symbol");
        let stop_fn: extern "C" fn() -> c_int = {
            let manager = MODULE_MANAGER.lock().unwrap();
            let lib = manager.get_module("capture_proxy")?;

            info!("[module_loader] stop(): locating symbol proxy_stop");
            unsafe {
                let symbol = lib
                    .get::<extern "C" fn() -> c_int>(b"proxy_stop")
                    .map_err(|e| e.to_string())?;
                info!("[module_loader] stop(): symbol proxy_stop located");
                *symbol
            }
        };

        info!("[module_loader] stop(): calling proxy_stop");
        let result = stop_fn();
        info!("[module_loader] stop(): proxy_stop returned {}", result);
        match result {
            0 => Ok("Proxy stopped".to_string()),
            -1 => Err("Proxy not running".to_string()),
            _ => Err("Failed to stop proxy".to_string()),
        }
    }

    /// 检查代理是否运行
    pub fn is_running(install_dir: &str) -> Result<bool, String> {
        #[cfg(any(target_os = "ios", target_os = "android"))]
        {
            return Err("Dynamic module loading is not supported on mobile platforms.".to_string());
        }

        info!("[module_loader] is_running(): ensure_loaded start");
        Self::ensure_loaded(install_dir)?;
        info!("[module_loader] is_running(): ensure_loaded done");

        info!("[module_loader] is_running(): acquiring lock to get symbol");
        let is_running_fn: extern "C" fn() -> c_int = {
            let manager = MODULE_MANAGER.lock().unwrap();
            let lib = manager.get_module("capture_proxy")?;

            info!("[module_loader] is_running(): locating symbol proxy_is_running");
            unsafe {
                let symbol = lib
                    .get::<extern "C" fn() -> c_int>(b"proxy_is_running")
                    .map_err(|e| e.to_string())?;
                info!("[module_loader] is_running(): symbol located");
                *symbol
            }
        };

        info!("[module_loader] is_running(): calling proxy_is_running");
        let res = is_running_fn();
        info!(
            "[module_loader] is_running(): proxy_is_running returned {}",
            res
        );
        Ok(res != 0)
    }

    /// 获取捕获的视频列表
    pub fn get_videos(install_dir: &str) -> Result<Vec<String>, String> {
        println!("[module_loader] get_videos(): ensure_loaded start");
        Self::ensure_loaded(install_dir)?;
        println!("[module_loader] get_videos(): ensure_loaded done");

        let (get_videos_fn, free_fn): (extern "C" fn() -> *mut c_char, extern "C" fn(*mut c_char)) = {
            let manager = MODULE_MANAGER.lock().unwrap();
            let lib = manager.get_module("capture_proxy")?;

            unsafe {
                let get_sym = lib
                    .get::<extern "C" fn() -> *mut c_char>(b"proxy_get_videos_json")
                    .map_err(|e| e.to_string())?;
                let free_sym = lib
                    .get::<extern "C" fn(*mut c_char)>(b"proxy_free_string")
                    .map_err(|e| e.to_string())?;
                (*get_sym, *free_sym)
            }
        };
        let json_ptr = get_videos_fn();
        println!(
            "[module_loader] get_videos(): got json_ptr -> {:p}",
            json_ptr
        );
        if json_ptr.is_null() {
            println!("[module_loader] get_videos(): json_ptr is null -> returning empty");
            return Ok(Vec::new());
        }

        let result = unsafe {
            let json_str = CStr::from_ptr(json_ptr).to_string_lossy().to_string();
            println!("[module_loader] get_videos(): json_str='{}'", json_str);
            // free the C string
            free_fn(json_ptr);
            let parsed: Result<Vec<String>, _> = serde_json::from_str(&json_str);
            match &parsed {
                Ok(v) => println!("[module_loader] get_videos(): parsed {} items", v.len()),
                Err(e) => println!("[module_loader] get_videos(): parse error: {}", e),
            }
            parsed.map_err(|e| e.to_string())
        };

        result
    }

    /// 清除捕获的数据
    pub fn clear_data(install_dir: &str) -> Result<(), String> {
        info!("[module_loader] clear_data(): ensure_loaded start");
        Self::ensure_loaded(install_dir)?;
        info!("[module_loader] clear_data(): ensure_loaded done");

        info!("[module_loader] clear_data(): acquiring lock to get symbol");
        let clear_fn: extern "C" fn() = {
            let manager = MODULE_MANAGER.lock().unwrap();
            let lib = manager.get_module("capture_proxy")?;

            info!("[module_loader] clear_data(): locating symbol proxy_clear_items");
            unsafe {
                let sym = lib
                    .get::<extern "C" fn()>(b"proxy_clear_items")
                    .map_err(|e| e.to_string())?;
                info!("[module_loader] clear_data(): symbol located");
                *sym
            }
        };

        info!("[module_loader] clear_data(): calling proxy_clear_items");
        clear_fn();
        info!("[module_loader] clear_data(): proxy_clear_items returned");
        Ok(())
    }

    /// 安装 CA 证书
    pub fn install_certificate(password: &str, install_dir: &str) -> Result<(), String> {
        info!("[module_loader] install_certificate(): ensure_loaded start");
        Self::ensure_loaded(install_dir)?;
        info!("[module_loader] install_certificate(): ensure_loaded done");

        info!("[module_loader] install_certificate(): acquiring lock to get symbol");
        let install_fn: extern "C" fn(*const c_char) -> c_int = {
            let manager = MODULE_MANAGER.lock().unwrap();
            let lib = manager.get_module("capture_proxy")?;

            info!(
                "[module_loader] install_certificate(): locating symbol proxy_install_certificate"
            );
            unsafe {
                let sym = lib
                    .get::<extern "C" fn(*const c_char) -> c_int>(b"proxy_install_certificate")
                    .map_err(|e| e.to_string())?;
                info!("[module_loader] install_certificate(): symbol located");
                *sym
            }
        };

        info!("[module_loader] install_certificate(): calling proxy_install_certificate");
        let c_password = CString::new(password).unwrap();
        let result = install_fn(c_password.as_ptr());
        info!(
            "[module_loader] install_certificate(): proxy_install_certificate returned {}",
            result
        );

        match result {
            0 => Ok(()),
            _ => Err("Failed to install certificate".to_string()),
        }
    }

    /// 检查证书是否已安装
    pub fn is_certificate_installed(install_dir: &str) -> Result<bool, String> {
        info!("[module_loader] is_certificate_installed(): ensure_loaded start");
        Self::ensure_loaded(install_dir)?;
        info!("[module_loader] is_certificate_installed(): ensure_loaded done");

        info!("[module_loader] is_certificate_installed(): acquiring lock to get symbol");
        let is_installed_fn: extern "C" fn() -> c_int = {
            let manager = MODULE_MANAGER.lock().unwrap();
            let lib = manager.get_module("capture_proxy")?;

            info!("[module_loader] is_certificate_installed(): locating symbol proxy_is_certificate_installed");
            unsafe {
                let sym = lib
                    .get::<extern "C" fn() -> c_int>(b"proxy_is_certificate_installed")
                    .map_err(|e| e.to_string())?;
                info!("[module_loader] is_certificate_installed(): symbol located");
                *sym
            }
        };

        info!("[module_loader] is_certificate_installed(): calling proxy_is_certificate_installed");
        let res = is_installed_fn();
        info!(
            "[module_loader] is_certificate_installed(): returned {}",
            res
        );
        Ok(res != 0)
    }
}

// Flutter Rust Bridge 导出函数

/// 下载并加载 capture_proxy 模块
pub async fn download_capture_proxy_module(
    windows_url: String,
    macos_url: String,
    install_dir: String,
) -> Result<String, String> {
    #[cfg(any(target_os = "ios", target_os = "android"))]
    {
        return Err(
            "Module download is not needed on mobile platforms. Use static compilation."
                .to_string(),
        );
    }

    let downloader = ModuleDownloader::new(PathBuf::from(&install_dir));

    let module_config = super::module_downloader::ModuleConfig {
        name: "capture_proxy".to_string(),
        windows_url,
        macos_url,
        executable_name: "capture_proxy".to_string(),
    };

    #[cfg(target_os = "windows")]
    let (ext, prefix) = ("dll", "");
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    let (ext, prefix) = ("dylib", "lib");
    #[cfg(target_os = "linux")]
    let (ext, prefix) = ("so", "lib");

    // 修改 executable_name 为动态库名称（macOS/Linux 有 lib 前缀）
    let lib_name = format!("{}capture_proxy.{}", prefix, ext);
    let mut lib_config = module_config.clone();
    lib_config.executable_name = lib_name;

    let module_path = downloader.download_module(&lib_config).await?;

    Ok(format!("Module downloaded to: {}", module_path.display()))
}

/// 检查 capture_proxy 模块是否已下载
pub fn is_capture_proxy_downloaded(install_dir: String) -> bool {
    #[cfg(any(target_os = "ios", target_os = "android"))]
    {
        // 移动端使用静态编译,始终返回 true
        return true;
    }

    let downloader = ModuleDownloader::new(PathBuf::from(&install_dir));

    #[cfg(target_os = "windows")]
    let (ext, prefix) = ("dll", "");
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    let (ext, prefix) = ("dylib", "lib");
    #[cfg(target_os = "linux")]
    let (ext, prefix) = ("so", "lib");

    let lib_name = format!("{}capture_proxy.{}", prefix, ext);
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
