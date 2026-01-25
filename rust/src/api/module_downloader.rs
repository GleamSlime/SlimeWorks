/// 模块下载器
///
/// 提供通用的模块下载和管理功能
/// 支持 Windows 和 macOS 平台的可执行文件下载
use flutter_rust_bridge::frb;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

/// 模块下载配置
#[frb(ignore)]
#[derive(Debug, Clone)]
pub struct ModuleConfig {
    pub name: String,
    pub windows_url: String,
    pub macos_url: String,
    pub executable_name: String,
}

/// 模块下载器
#[frb(ignore)]
pub struct ModuleDownloader {
    install_dir: PathBuf,
}

impl ModuleDownloader {
    /// 创建模块下载器
    pub fn new(install_dir: PathBuf) -> Self {
        Self { install_dir }
    }

    /// 获取模块安装路径
    pub fn get_module_path(&self, module_name: &str) -> PathBuf {
        self.install_dir.join("modules").join(module_name)
    }

    /// 获取可执行文件路径
    pub fn get_executable_path(&self, module_name: &str, executable_name: &str) -> PathBuf {
        let mut path = self.get_module_path(module_name).join(executable_name);

        #[cfg(target_os = "windows")]
        {
            if !executable_name.ends_with(".exe") {
                path.set_extension("exe");
            }
        }

        path
    }

    /// 检查模块是否已安装
    pub fn is_module_installed(&self, module_name: &str, executable_name: &str) -> bool {
        let exec_path = self.get_executable_path(module_name, executable_name);
        exec_path.exists()
    }

    /// 下载并安装模块
    pub async fn download_module(&self, config: &ModuleConfig) -> Result<PathBuf, String> {
        // 检查是否已安装
        if self.is_module_installed(&config.name, &config.executable_name) {
            return Ok(self.get_executable_path(&config.name, &config.executable_name));
        }

        // 确定下载 URL
        let download_url = if cfg!(target_os = "windows") {
            &config.windows_url
        } else if cfg!(target_os = "macos") {
            &config.macos_url
        } else {
            return Err("Unsupported platform".to_string());
        };

        if download_url.is_empty() {
            return Err(format!("No download URL configured for {}", config.name));
        }

        // 创建模块目录
        let module_dir = self.get_module_path(&config.name);
        fs::create_dir_all(&module_dir)
            .map_err(|e| format!("Failed to create module directory: {}", e))?;

        // 下载文件
        let exec_path = self.get_executable_path(&config.name, &config.executable_name);
        self.download_file(download_url, &exec_path).await?;

        // 设置执行权限 (Unix)
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut perms = fs::metadata(&exec_path)
                .map_err(|e| format!("Failed to get file metadata: {}", e))?
                .permissions();
            perms.set_mode(0o755);
            fs::set_permissions(&exec_path, perms)
                .map_err(|e| format!("Failed to set executable permissions: {}", e))?;
        }

        Ok(exec_path)
    }

    /// 下载文件
    async fn download_file(&self, url: &str, dest_path: &Path) -> Result<(), String> {
        // 创建 HTTP 客户端
        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(300)) // 5分钟超时
            .build()
            .map_err(|e| format!("Failed to create HTTP client: {}", e))?;

        // 下载文件
        let response = client
            .get(url)
            .send()
            .await
            .map_err(|e| format!("Failed to download from {}: {}", url, e))?;

        if !response.status().is_success() {
            return Err(format!(
                "Download failed with status: {}",
                response.status()
            ));
        }

        // 获取文件内容
        let bytes = response
            .bytes()
            .await
            .map_err(|e| format!("Failed to read response body: {}", e))?;

        // 写入文件
        let mut file =
            fs::File::create(dest_path).map_err(|e| format!("Failed to create file: {}", e))?;

        file.write_all(&bytes)
            .map_err(|e| format!("Failed to write file: {}", e))?;

        Ok(())
    }

    /// 删除模块
    pub fn remove_module(&self, module_name: &str) -> Result<(), String> {
        let module_dir = self.get_module_path(module_name);
        if module_dir.exists() {
            fs::remove_dir_all(&module_dir)
                .map_err(|e| format!("Failed to remove module: {}", e))?;
        }
        Ok(())
    }

    /// 获取模块版本（通过执行 --version 命令）
    pub fn get_module_version(
        &self,
        module_name: &str,
        executable_name: &str,
    ) -> Result<String, String> {
        let exec_path = self.get_executable_path(module_name, executable_name);

        if !exec_path.exists() {
            return Err("Module not installed".to_string());
        }

        let output = std::process::Command::new(&exec_path)
            .arg("-version")
            .output()
            .map_err(|e| format!("Failed to execute command: {}", e))?;

        let version_output = String::from_utf8_lossy(&output.stdout);
        Ok(version_output
            .lines()
            .next()
            .unwrap_or("Unknown")
            .to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_module_paths() {
        let downloader = ModuleDownloader::new(PathBuf::from("/test/install"));

        let module_path = downloader.get_module_path("ffmpeg");
        assert_eq!(module_path, PathBuf::from("/test/install/modules/ffmpeg"));

        let exec_path = downloader.get_executable_path("ffmpeg", "ffmpeg");
        #[cfg(target_os = "windows")]
        assert_eq!(
            exec_path,
            PathBuf::from("/test/install/modules/ffmpeg/ffmpeg.exe")
        );
        #[cfg(not(target_os = "windows"))]
        assert_eq!(
            exec_path,
            PathBuf::from("/test/install/modules/ffmpeg/ffmpeg")
        );
    }
}
