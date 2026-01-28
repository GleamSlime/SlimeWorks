/// 模块加载器 - 负责动态库的加载和卸载
use super::config::*;
use super::types::*;
use flutter_rust_bridge::frb;
use libloading::Library;
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::sync::Mutex;

lazy_static::lazy_static! {
    static ref LOADED_MODULES: Mutex<HashMap<String, Library>> = Mutex::new(HashMap::new());
}

/// 模块加载器
#[frb(opaque)]
pub struct ModuleLoader {
    install_dir: PathBuf,
}

impl ModuleLoader {
    /// 创建模块加载器
    pub fn new(install_dir: PathBuf) -> Self {
        Self { install_dir }
    }

    /// 查找模块文件
    /// 支持：
    /// 1. 开发环境：rust/target/release/libmodule.dylib
    /// 2. 生产环境：dll/module_1-2-0-23.dll
    /// 3. 锁定版本：dll/module_1-2-0-23_lock.dll
    fn find_module_file(
        &self,
        module_name: &str,
        version: Option<&str>,
    ) -> Result<PathBuf, String> {
        let dll_dir = self.install_dir.join("dll");

        // 如果指定了版本，精确查找
        if let Some(v) = version {
            let normalized_version = VersionInfo::normalize_version(v);
            let version_info = VersionInfo {
                module_name: module_name.to_string(),
                version: normalized_version,
                is_locked: false,
            };

            let filename = build_filename(&version_info, &ModuleType::DynamicLibrary);
            let file_path = dll_dir.join(&filename);

            if file_path.exists() {
                return Ok(file_path);
            }

            // 尝试锁定版本
            let version_info_locked = VersionInfo {
                is_locked: true,
                ..version_info
            };
            let filename_locked = build_filename(&version_info_locked, &ModuleType::DynamicLibrary);
            let file_path_locked = dll_dir.join(&filename_locked);

            if file_path_locked.exists() {
                return Ok(file_path_locked);
            }
        }

        // 模糊查找：找到最新的版本
        if dll_dir.exists() {
            let mut candidates: Vec<(PathBuf, VersionInfo)> = Vec::new();

            if let Ok(entries) = fs::read_dir(&dll_dir) {
                for entry in entries.flatten() {
                    if let Some(filename) = entry.file_name().to_str() {
                        if let Some(version_info) = VersionInfo::from_filename(filename) {
                            if version_info.module_name == module_name {
                                candidates.push((entry.path(), version_info));
                            }
                        }
                    }
                }
            }

            // 优先选择锁定版本，否则选择版本号最大的
            candidates.sort_by(|a, b| {
                if a.1.is_locked && !b.1.is_locked {
                    std::cmp::Ordering::Less
                } else if !a.1.is_locked && b.1.is_locked {
                    std::cmp::Ordering::Greater
                } else {
                    b.1.version.cmp(&a.1.version)
                }
            });

            if let Some((path, _)) = candidates.first() {
                return Ok(path.clone());
            }
        }

        // 开发环境查找
        let dev_paths = vec![
            PathBuf::from("rust/target/release"),
            PathBuf::from("../rust/target/release"),
            PathBuf::from("../../rust/target/release"),
        ];

        for dev_path in dev_paths {
            #[cfg(target_os = "windows")]
            let dev_file = dev_path.join(format!("{}.dll", module_name));

            #[cfg(target_os = "macos")]
            let dev_file = dev_path.join(format!("lib{}.dylib", module_name));

            #[cfg(target_os = "linux")]
            let dev_file = dev_path.join(format!("lib{}.so", module_name));

            if dev_file.exists() {
                return Ok(dev_file);
            }
        }

        Err(format!("Module '{}' not found", module_name))
    }

    /// 加载模块
    ///
    /// # 参数
    /// - module_name: 模块名称
    /// - version: 指定版本（None 表示自动选择）
    pub fn load_module(&self, module_name: &str, version: Option<String>) -> Result<(), String> {
        // 查找文件
        let file_path = self.find_module_file(module_name, version.as_deref())?;

        // 加载库
        unsafe {
            let lib =
                Library::new(&file_path).map_err(|e| format!("Failed to load library: {}", e))?;

            // 保存到全局 map
            let mut loaded = LOADED_MODULES.lock().unwrap();
            loaded.insert(module_name.to_string(), lib);
        }

        Ok(())
    }

    /// 卸载模块
    pub fn unload_module(&self, module_name: &str) -> Result<(), String> {
        let mut loaded = LOADED_MODULES.lock().unwrap();

        if loaded.remove(module_name).is_none() {
            return Err(format!("Module '{}' is not loaded", module_name));
        }

        Ok(())
    }

    /// 检查模块是否已加载
    pub fn is_loaded(&self, module_name: &str) -> bool {
        let loaded = LOADED_MODULES.lock().unwrap();
        loaded.contains_key(module_name)
    }

    /// 列出所有已加载的模块
    pub fn list_loaded_modules(&self) -> Vec<String> {
        let loaded = LOADED_MODULES.lock().unwrap();
        loaded.keys().cloned().collect()
    }

    /// 重新加载模块
    pub fn reload_module(&self, module_name: &str, version: Option<String>) -> Result<(), String> {
        // 先卸载
        let _ = self.unload_module(module_name);

        // 重新加载
        self.load_module(module_name, version)
    }
}
