//! 模块下载器
//!
//! 提供通用的模块下载和管理功能
//! 支持 Windows 和 macOS 平台的可执行文件下载
use flutter_rust_bridge::frb;
use std::fs;
use std::path::{Path, PathBuf};

/// 已安装体积门槛：这些模块（ffmpeg / ffprobe / capture_proxy）都是多 MB 的
/// 二进制，小到 64KB 只可能是失败的残缺下载，不能当成「已安装」。
const MIN_INSTALLED_BYTES: u64 = 64 * 1024;

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

    /// 获取模块库文件路径 (DLL/dylib/so)
    pub fn get_library_path(&self, module_name: &str, lib_name: &str) -> PathBuf {
        let mut path = self.get_module_path(module_name).join(lib_name);

        #[cfg(target_os = "windows")]
        {
            if !lib_name.ends_with(".dll") {
                path.set_extension("dll");
            }
        }

        #[cfg(target_os = "macos")]
        {
            if !lib_name.ends_with(".dylib") {
                path.set_extension("dylib");
            }
        }

        #[cfg(target_os = "linux")]
        {
            if !lib_name.ends_with(".so") {
                path.set_extension("so");
            }
        }

        path
    }

    /// 获取可执行文件路径
    pub fn get_executable_path(&self, module_name: &str, executable_name: &str) -> PathBuf {
        let mut path = self.get_module_path(module_name).join(executable_name);

        #[cfg(target_os = "windows")]
        {
            if std::path::Path::new(executable_name).extension().is_none() {
                path.set_extension("exe");
            }
        }

        path
    }

    /// 检查模块是否已安装
    ///
    /// 除了存在性还要过一道体积门槛：历史上是本函数「存在即已安装」
    /// 让半截下载（进程被杀/断网）永久短路，永远不重下。
    /// 现在的写入路径已经是 tmp+rename，这里是历史残留文件的兜底。
    pub fn is_module_installed(&self, module_name: &str, executable_name: &str) -> bool {
        let exec_path = self.get_executable_path(module_name, executable_name);
        match fs::metadata(&exec_path) {
            Ok(meta) => meta.is_file() && meta.len() >= MIN_INSTALLED_BYTES,
            Err(_) => false,
        }
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

        // 先写临时文件再 rename：直接写最终路径的话，进程中途退出/断网会留下
        // 半截可执行文件，而 is_module_installed 只看存在性 → 永久「已安装」。
        let part_path = Self::part_path_of(dest_path);
        if let Err(e) = fs::write(&part_path, &bytes) {
            let _ = fs::remove_file(&part_path);
            return Err(format!("Failed to write file: {}", e));
        }
        if (bytes.len() as u64) < MIN_INSTALLED_BYTES {
            let _ = fs::remove_file(&part_path);
            return Err(format!(
                "Downloaded module is too small ({} bytes), likely a broken response",
                bytes.len()
            ));
        }
        if let Err(e) = fs::rename(&part_path, dest_path) {
            let _ = fs::remove_file(&part_path);
            return Err(format!("Failed to finalize file: {}", e));
        }

        Ok(())
    }

    /// 下载中的临时文件：与最终文件同目录（rename 才能同卷原子落盘），
    /// 隐藏前缀便于用户/清理脚本一眼认出是残留
    fn part_path_of(dest_path: &Path) -> PathBuf {
        let name = dest_path
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_else(|| "module".to_string());
        dest_path.with_file_name(format!(".{}.part", name))
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

    /// 获取模块本地版本（从 version.txt 文件）
    pub fn get_local_module_version(&self, module_name: &str) -> Option<String> {
        let version_file = self.get_module_path(module_name).join("version.txt");
        if version_file.exists() {
            fs::read_to_string(version_file).ok()
        } else {
            None
        }
    }

    /// 保存模块版本信息
    // fn save_module_version(&self, module_name: &str, version: &str) -> Result<(), String> {
    //     let version_file = self.get_module_path(module_name).join("version.txt");
    //     fs::write(version_file, version).map_err(|e| format!("Failed to save version: {}", e))
    // }

    /// 检查模块是否已安装（包含库文件）
    pub fn is_library_installed(&self, module_name: &str, lib_name: &str) -> bool {
        let lib_path = self.get_library_path(module_name, lib_name);
        lib_path.exists()
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

    /// 半截下载（只有 .part、最终文件不存在）不能被当成已安装
    #[test]
    fn interrupted_download_is_not_considered_installed() {
        let dir = std::env::temp_dir().join(format!("sw_mod_dl_{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        let downloader = ModuleDownloader::new(dir.clone());
        let exec = downloader.get_executable_path("ffmpeg", "ffmpeg");
        fs::create_dir_all(exec.parent().unwrap()).unwrap();

        // 模拟写到一半中断：临时文件在，最终文件没有
        let part = ModuleDownloader::part_path_of(&exec);
        fs::write(&part, vec![0u8; 1024]).unwrap();
        assert!(!downloader.is_module_installed("ffmpeg", "ffmpeg"), ".part 不该算已安装");

        // 体积够大但仍是 1KB 的残缺文件：门槛挡住
        fs::write(&exec, vec![0u8; 1024]).unwrap();
        assert!(!downloader.is_module_installed("ffmpeg", "ffmpeg"), "1KB 残缺文件不该算已安装");

        // 正常体积才认
        fs::write(&exec, vec![0u8; MIN_INSTALLED_BYTES as usize]).unwrap();
        assert!(downloader.is_module_installed("ffmpeg", "ffmpeg"));

        let _ = fs::remove_dir_all(&dir);
    }

    /// 临时名必须是最终名的隐藏兄弟文件，绝不与最终名相等
    #[test]
    fn part_path_is_hidden_sibling() {
        let dest = PathBuf::from("/test/install/modules/ffmpeg/ffmpeg");
        assert_ne!(ModuleDownloader::part_path_of(&dest), dest);
        assert_eq!(
            ModuleDownloader::part_path_of(&dest),
            PathBuf::from("/test/install/modules/ffmpeg/.ffmpeg.part")
        );
    }
}
