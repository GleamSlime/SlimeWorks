/// 统一模块管理系统
///
/// 支持两种模块类型：
/// 1. 动态库模块（DLL/dylib/so）- 如 capture_proxy
/// 2. 可执行程序模块（exe）- 如 ffmpeg
///
/// 功能：
/// - 统一的版本管理
/// - 跨平台支持（Windows/macOS）
/// - 自动下载和更新
/// - 本地缓存和验证

use flutter_rust_bridge::frb;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use serde::{Deserialize, Serialize};

use super::logger::log_info;

/// 模块类型
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum ModuleType {
    /// 动态库模块（.dll / .dylib / .so）
    Library,
    /// 可执行程序模块（.exe / 无扩展名）
    Executable,
}

/// 模块配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModuleConfig {
    /// 模块名称（如 "capture_proxy", "ffmpeg"）
    pub name: String,
    /// 模块类型
    pub module_type: ModuleType,
    /// 当前版本
    pub version: String,
    /// Windows 下载地址
    pub windows_url: String,
    /// macOS 下载地址
    pub macos_url: String,
    /// 文件名（不含扩展名，扩展名根据平台自动添加）
    pub file_name: String,
}

/// 模块元数据（本地存储）
#[derive(Debug, Clone, Serialize, Deserialize)]
struct ModuleMetadata {
    version: String,
    installed_at: String,
    file_size: u64,
}

/// 模块管理器
#[frb(opaque)]
pub struct ModuleManager {
    install_dir: PathBuf,
}

#[frb(ignore)]
impl ModuleManager {
    /// 创建模块管理器
    pub fn new(install_dir: PathBuf) -> Self {
        Self { install_dir }
    }

    /// 获取模块根目录
    pub fn get_modules_dir(&self) -> PathBuf {
        self.install_dir.join("modules")
    }

    /// 获取模块目录
    pub fn get_module_dir(&self, module_name: &str) -> PathBuf {
        self.get_modules_dir().join(module_name)
    }

    /// 获取模块文件路径（根据类型和平台自动添加扩展名）
    pub fn get_module_file_path(&self, config: &ModuleConfig) -> PathBuf {
        let module_dir = self.get_module_dir(&config.name);
        let mut path = module_dir.join(&config.file_name);

        match config.module_type {
            ModuleType::Library => {
                #[cfg(target_os = "windows")]
                {
                    if !config.file_name.ends_with(".dll") {
                        path.set_extension("dll");
                    }
                }

                #[cfg(target_os = "macos")]
                {
                    if !config.file_name.ends_with(".dylib") {
                        path.set_extension("dylib");
                    }
                }

                #[cfg(target_os = "linux")]
                {
                    if !config.file_name.ends_with(".so") {
                        path.set_extension("so");
                    }
                }
            }
            ModuleType::Executable => {
                #[cfg(target_os = "windows")]
                {
                    if !config.file_name.ends_with(".exe") {
                        path.set_extension("exe");
                    }
                }
                // macOS/Linux 可执行文件通常无扩展名
            }
        }

        path
    }

    /// 获取模块元数据文件路径
    fn get_metadata_path(&self, module_name: &str) -> PathBuf {
        self.get_module_dir(module_name).join("metadata.json")
    }

    /// 读取模块元数据
    pub fn get_module_metadata(&self, module_name: &str) -> Option<ModuleMetadata> {
        let metadata_path = self.get_metadata_path(module_name);
        if !metadata_path.exists() {
            return None;
        }

        let content = fs::read_to_string(&metadata_path).ok()?;
        serde_json::from_str(&content).ok()
    }

    /// 保存模块元数据
    fn save_module_metadata(
        &self,
        module_name: &str,
        version: &str,
        file_size: u64,
    ) -> Result<(), String> {
        let metadata = ModuleMetadata {
            version: version.to_string(),
            installed_at: chrono::Local::now().to_rfc3339(),
            file_size,
        };

        let metadata_path = self.get_metadata_path(module_name);
        let content = serde_json::to_string_pretty(&metadata)
            .map_err(|e| format!("Failed to serialize metadata: {}", e))?;

        fs::write(&metadata_path, content)
            .map_err(|e| format!("Failed to write metadata: {}", e))?;

        Ok(())
    }

    /// 检查模块是否已安装
    pub fn is_module_installed(&self, config: &ModuleConfig) -> bool {
        let file_path = self.get_module_file_path(config);
        file_path.exists()
    }

    /// 检查模块是否需要更新
    pub fn needs_update(&self, config: &ModuleConfig) -> bool {
        if !self.is_module_installed(config) {
            return true;
        }

        match self.get_module_metadata(&config.name) {
            Some(metadata) => metadata.version != config.version,
            None => true, // 没有元数据，需要更新
        }
    }

    /// 获取模块下载 URL（根据当前平台）
    pub fn get_download_url(&self, config: &ModuleConfig) -> Result<String, String> {
        #[cfg(target_os = "windows")]
        {
            if config.windows_url.is_empty() {
                return Err(format!("Windows URL not configured for module: {}", config.name));
            }
            Ok(config.windows_url.clone())
        }

        #[cfg(target_os = "macos")]
        {
            if config.macos_url.is_empty() {
                return Err(format!("macOS URL not configured for module: {}", config.name));
            }
            Ok(config.macos_url.clone())
        }

        #[cfg(not(any(target_os = "windows", target_os = "macos")))]
        {
            Err("Unsupported platform".to_string())
        }
    }

    /// 下载模块
    pub async fn download_module(&self, config: &ModuleConfig) -> Result<(), String> {
        let url = self.get_download_url(config)?;
        
        log_info(&format!("Downloading module {} from {}", config.name, url));

        // 创建模块目录
        let module_dir = self.get_module_dir(&config.name);
        fs::create_dir_all(&module_dir)
            .map_err(|e| format!("Failed to create module directory: {}", e))?;

        // 下载文件
        let response = reqwest::get(&url)
            .await
            .map_err(|e| format!("Failed to download: {}", e))?;

        if !response.status().is_success() {
            return Err(format!("Download failed with status: {}", response.status()));
        }

        let content = response
            .bytes()
            .await
            .map_err(|e| format!("Failed to read response: {}", e))?;

        // 保存文件
        let file_path = self.get_module_file_path(config);
        fs::write(&file_path, &content)
            .map_err(|e| format!("Failed to write file: {}", e))?;

        // 保存元数据
        self.save_module_metadata(&config.name, &config.version, content.len() as u64)?;

        log_info(&format!(
            "Module {} downloaded successfully: {} bytes",
            config.name,
            content.len()
        ));

        // 在 Unix 系统上设置可执行权限
        #[cfg(unix)]
        {
            if config.module_type == ModuleType::Executable {
                use std::os::unix::fs::PermissionsExt;
                let mut perms = fs::metadata(&file_path)
                    .map_err(|e| format!("Failed to get file metadata: {}", e))?
                    .permissions();
                perms.set_mode(0o755);
                fs::set_permissions(&file_path, perms)
                    .map_err(|e| format!("Failed to set executable permission: {}", e))?;
            }
        }

        Ok(())
    }

    /// 获取已安装的模块版本
    pub fn get_installed_version(&self, module_name: &str) -> Option<String> {
        self.get_module_metadata(module_name)
            .map(|m| m.version)
    }
}

/// 预定义的模块配置
#[frb(ignore)]
pub struct ModuleConfigs;

#[frb(ignore)]
impl ModuleConfigs {
    /// Capture Proxy 模块配置
    pub fn capture_proxy(version: &str, windows_url: &str, macos_url: &str) -> ModuleConfig {
        ModuleConfig {
            name: "capture_proxy".to_string(),
            module_type: ModuleType::Library,
            version: version.to_string(),
            windows_url: windows_url.to_string(),
            macos_url: macos_url.to_string(),
            file_name: "capture_proxy".to_string(),
        }
    }

    /// FFmpeg 模块配置
    pub fn ffmpeg(version: &str, windows_url: &str, macos_url: &str) -> ModuleConfig {
        ModuleConfig {
            name: "ffmpeg".to_string(),
            module_type: ModuleType::Executable,
            version: version.to_string(),
            windows_url: windows_url.to_string(),
            macos_url: macos_url.to_string(),
            file_name: "ffmpeg".to_string(),
        }
    }
}
