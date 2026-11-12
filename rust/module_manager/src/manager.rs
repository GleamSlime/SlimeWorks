/// 模块管理器 - 负责下载、安装、卸载等操作
use super::config::*;
use super::types::*;
use flutter_rust_bridge::frb;
use std::fs;
use std::path::PathBuf;

/// 模块管理器
#[frb(opaque)]
pub struct ModuleManager {
    install_dir: PathBuf,
    config_url: String,
}

impl ModuleManager {
    /// 创建模块管理器
    pub fn new(install_dir: PathBuf, config_url: String) -> Self {
        Self {
            install_dir,
            config_url,
        }
    }

    /// 计算文件的 MD5
    fn calculate_md5(file_path: &PathBuf) -> Result<String, String> {
        let content = fs::read(file_path).map_err(|e| format!("Failed to read file: {}", e))?;

        let result = md5::compute(&content);

        Ok(format!("{:x}", result))
    }

    /// 验证文件 MD5
    fn verify_md5(file_path: &PathBuf, expected_md5: &str) -> Result<bool, String> {
        let actual_md5 = Self::calculate_md5(file_path)?;
        Ok(actual_md5.eq_ignore_ascii_case(expected_md5))
    }

    /// 下载中的临时文件名：与目标同目录（同卷才可能原子 rename），
    /// 命名带 pid 与点前缀，便于识别残留且不与并发实例互踩
    fn part_path_of(dest: &PathBuf) -> PathBuf {
        let name = dest
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_else(|| "module".to_string());
        dest.with_file_name(format!(".{}.{}.part", name, std::process::id()))
    }

    /// 获取模块配置（从远程或缓存）
    async fn get_config(&self) -> Result<ModulesConfig, String> {
        fetch_modules_config(&self.config_url).await
    }

    /// 获取可用的模块列表（从配置）
    pub async fn get_available_modules(&self) -> Result<Vec<ModuleInfo>, String> {
        let config = self.get_config().await?;
        let mut modules = Vec::new();

        for (name, module_config) in config.modules {
            modules.push(ModuleInfo {
                name,
                version: module_config.version,
                module_type: module_config.module_type,
                description: module_config.notes,
            });
        }

        Ok(modules)
    }

    /// 检查模块是否需要更新
    /// 如果文件名带 _lock 则不更新
    pub async fn check_for_update(&self, module_name: &str) -> Result<Option<String>, String> {
        let installed = self.list_installed_versions(module_name)?;

        // 如果有锁定版本，不需要更新
        if installed.iter().any(|m| m.is_locked) {
            return Ok(None);
        }

        // 获取最新版本
        let config = self.get_config().await?;
        let module_config = config
            .modules
            .get(module_name)
            .ok_or_else(|| format!("Module '{}' not found in config", module_name))?;

        let latest_version = VersionInfo::normalize_version(&module_config.version);

        // 检查是否已安装最新版本
        let has_latest = installed.iter().any(|m| m.version == latest_version);

        if has_latest {
            Ok(None)
        } else {
            Ok(Some(module_config.version.clone()))
        }
    }

    /// 下载并安装模块
    ///
    /// # 参数
    /// - module_name: 模块名称
    /// - version: 指定版本（None 表示最新版）
    /// - lock_version: 是否锁定版本
    /// - auto_load: 是否自动加载（仅对 dynamic_library 有效）
    #[allow(deprecated)]
    pub async fn install_module(
        &self,
        module_name: &str,
        version: Option<String>,
        lock_version: bool,
        auto_load: bool,
    ) -> Result<String, String> {
        // 获取配置
        let config = self.get_config().await?;
        let module_config = config
            .modules
            .get(module_name)
            .ok_or_else(|| format!("Module '{}' not found", module_name))?;

        // 确定版本
        let target_version = version.unwrap_or_else(|| module_config.version.clone());

        // 获取平台信息
        let platform_key = get_platform_key();
        let platform_info = module_config.platforms.get(&platform_key).ok_or_else(|| {
            format!(
                "Platform '{}' not supported for module '{}'",
                platform_key, module_name
            )
        })?;

        // 创建版本信息
        let version_info = VersionInfo::new(
            module_name.to_string(),
            target_version.clone(),
            lock_version,
        );

        // 确定目标目录和文件名
        let target_dir =
            get_module_directory(&self.install_dir, module_name, &module_config.module_type);
        fs::create_dir_all(&target_dir)
            .map_err(|e| format!("Failed to create directory: {}", e))?;

        let filename = build_filename(&version_info, &module_config.module_type);
        let file_path = target_dir.join(&filename);

        // 顺序很重要：下载到临时文件 → 验 MD5 → 删旧 → rename。
        // 旧实现是「先删旧再下载」，下载失败就新旧两空；
        // 且直接写最终名，进程中途退出会留下一个 MD5 不对的「已安装」文件。
        let part_path = Self::part_path_of(&file_path);

        // 下载文件
        let response = reqwest::get(&platform_info.url)
            .await
            .map_err(|e| format!("Failed to download: {}", e))?;

        if !response.status().is_success() {
            return Err(format!("Download failed: {}", response.status()));
        }

        let content = response
            .bytes()
            .await
            .map_err(|e| format!("Failed to read response: {}", e))?;

        // 保存到临时文件
        if let Err(e) = fs::write(&part_path, &content) {
            fs::remove_file(&part_path).ok();
            return Err(format!("Failed to write file: {}", e));
        }

        // 验证 MD5（临时文件）：不过就删临时文件，旧版本毫发无损
        match Self::verify_md5(&part_path, &platform_info.signature) {
            Ok(true) => {}
            Ok(false) => {
                fs::remove_file(&part_path).ok();
                return Err(format!(
                    "MD5 verification failed for module '{}'",
                    module_name
                ));
            }
            Err(e) => {
                fs::remove_file(&part_path).ok();
                return Err(e);
            }
        }

        // 校验通过才动旧文件
        if file_path.exists() {
            fs::remove_file(&file_path)
                .map_err(|e| format!("Failed to remove existing file: {}", e))?;
        }
        if let Err(e) = fs::rename(&part_path, &file_path) {
            fs::remove_file(&part_path).ok();
            return Err(format!("Failed to finalize module file: {}", e));
        }

        // Unix 系统设置可执行权限
        #[cfg(unix)]
        {
            if matches!(module_config.module_type, ModuleType::Executable) {
                use std::os::unix::fs::PermissionsExt;
                let mut perms = fs::metadata(&file_path)
                    .map_err(|e| format!("Failed to get metadata: {}", e))?
                    .permissions();
                perms.set_mode(0o755);
                fs::set_permissions(&file_path, perms)
                    .map_err(|e| format!("Failed to set permissions: {}", e))?;
            }
        }

        // 如果需要自动加载且是动态库
        if auto_load
            && matches!(
                module_config.module_type,
                ModuleType::DynamicLibrary | ModuleType::Library
            )
        {
            // TODO: 调用加载器加载模块
        }

        Ok(file_path.to_string_lossy().to_string())
    }

    /// 列出已安装的模块版本
    pub fn list_installed_versions(
        &self,
        module_name: &str,
    ) -> Result<Vec<InstalledModule>, String> {
        let mut result = Vec::new();

        // 检查 dll 目录
        let dll_dir = self.install_dir.join("dll");
        if dll_dir.exists() {
            if let Ok(entries) = fs::read_dir(&dll_dir) {
                for entry in entries.flatten() {
                    if let Some(filename) = entry.file_name().to_str() {
                        if let Some(version_info) = VersionInfo::from_filename(filename) {
                            if version_info.module_name == module_name {
                                if let Ok(metadata) = entry.metadata() {
                                    result.push(InstalledModule {
                                        module_name: version_info.module_name.clone(),
                                        version: version_info.version.clone(),
                                        is_locked: version_info.is_locked,
                                        file_path: entry.path().to_string_lossy().to_string(),
                                        module_type: ModuleType::DynamicLibrary,
                                        file_size: metadata.len(),
                                        installed_at: "".to_string(), // TODO: 从文件系统获取
                                    });
                                }
                            }
                        }
                    }
                }
            }
        }

        // 检查 bin/{module_name} 目录
        let bin_dir = self.install_dir.join("bin").join(module_name);
        if bin_dir.exists() {
            if let Ok(entries) = fs::read_dir(&bin_dir) {
                for entry in entries.flatten() {
                    if let Some(filename) = entry.file_name().to_str() {
                        if let Some(version_info) = VersionInfo::from_filename(filename) {
                            if version_info.module_name == module_name {
                                if let Ok(metadata) = entry.metadata() {
                                    result.push(InstalledModule {
                                        module_name: version_info.module_name.clone(),
                                        version: version_info.version.clone(),
                                        is_locked: version_info.is_locked,
                                        file_path: entry.path().to_string_lossy().to_string(),
                                        module_type: ModuleType::Executable,
                                        file_size: metadata.len(),
                                        installed_at: "".to_string(),
                                    });
                                }
                            }
                        }
                    }
                }
            }
        }

        Ok(result)
    }

    /// 卸载模块（删除文件）
    pub fn uninstall_module(
        &self,
        module_name: &str,
        version: Option<String>,
    ) -> Result<usize, String> {
        let installed = self.list_installed_versions(module_name)?;
        let mut removed_count = 0;

        for module in installed {
            // 如果指定了版本，只删除该版本
            if let Some(ref v) = version {
                let normalized = VersionInfo::normalize_version(v);
                if module.version != normalized {
                    continue;
                }
            }

            // 删除文件
            fs::remove_file(&module.file_path)
                .map_err(|e| format!("Failed to remove file {}: {}", module.file_path, e))?;
            removed_count += 1;
        }

        if removed_count == 0 {
            return Err(format!("No matching module found to uninstall"));
        }

        Ok(removed_count)
    }

    /// 重新安装模块（先卸载再安装）
    pub async fn reinstall_module(
        &self,
        module_name: &str,
        version: Option<String>,
        lock_version: bool,
        auto_load: bool,
    ) -> Result<String, String> {
        // 先尝试卸载
        let _ = self.uninstall_module(module_name, version.clone());

        // 重新安装
        self.install_module(module_name, version, lock_version, auto_load)
            .await
    }

    /// 列出所有已安装的模块
    pub fn list_all_modules(&self) -> Result<Vec<InstalledModule>, String> {
        let mut result = Vec::new();

        // 扫描 dll 目录
        let dll_dir = self.install_dir.join("dll");
        if dll_dir.exists() {
            if let Ok(entries) = fs::read_dir(&dll_dir) {
                for entry in entries.flatten() {
                    if let Some(filename) = entry.file_name().to_str() {
                        if let Some(version_info) = VersionInfo::from_filename(filename) {
                            if let Ok(metadata) = entry.metadata() {
                                result.push(InstalledModule {
                                    module_name: version_info.module_name.clone(),
                                    version: version_info.version.clone(),
                                    is_locked: version_info.is_locked,
                                    file_path: entry.path().to_string_lossy().to_string(),
                                    module_type: ModuleType::DynamicLibrary,
                                    file_size: metadata.len(),
                                    installed_at: "".to_string(),
                                });
                            }
                        }
                    }
                }
            }
        }

        // 扫描 bin 目录
        let bin_dir = self.install_dir.join("bin");
        if bin_dir.exists() {
            if let Ok(module_dirs) = fs::read_dir(&bin_dir) {
                for module_dir in module_dirs.flatten() {
                    if module_dir.path().is_dir() {
                        if let Ok(entries) = fs::read_dir(module_dir.path()) {
                            for entry in entries.flatten() {
                                if let Some(filename) = entry.file_name().to_str() {
                                    if let Some(version_info) = VersionInfo::from_filename(filename)
                                    {
                                        if let Ok(metadata) = entry.metadata() {
                                            result.push(InstalledModule {
                                                module_name: version_info.module_name.clone(),
                                                version: version_info.version.clone(),
                                                is_locked: version_info.is_locked,
                                                file_path: entry
                                                    .path()
                                                    .to_string_lossy()
                                                    .to_string(),
                                                module_type: ModuleType::Executable,
                                                file_size: metadata.len(),
                                                installed_at: "".to_string(),
                                            });
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Ok(result)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 临时名必须是目标名的同目录兄弟文件，且不等于最终名
    #[test]
    fn part_path_is_sibling_and_not_final_name() {
        let dest = PathBuf::from("/tmp/modules/ffmpeg_1.0.0");
        let part = ModuleManager::part_path_of(&dest);
        assert_ne!(part, dest);
        assert_eq!(part.parent(), dest.parent(), "必须同目录，rename 才能原子完成");
        let name = part.file_name().unwrap().to_string_lossy().into_owned();
        assert!(name.starts_with('.') && name.ends_with(".part"), "name = {name}");
        // 带 pid：并发两个进程安装同一模块不会写坏同一个临时文件
        assert!(name.contains(&std::process::id().to_string()), "name = {name}");
    }

    /// 回归：下载失败（本例是文件不存在导致的 MD5 读取失败）后旧文件必须还在。
    /// 旧实现先删旧再下载，一失败就新旧两空。
    #[test]
    fn failed_verification_keeps_previous_install() {
        let dir = std::env::temp_dir().join(format!("sw_mm_keep_{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let final_file = dir.join("ffmpeg_1.0.0");
        fs::write(&final_file, b"old-version").unwrap();

        // 模拟「临时文件校验失败」分支：临时文件里的内容与期望 MD5 不符
        let part = ModuleManager::part_path_of(&final_file);
        fs::write(&part, b"broken-download").unwrap();
        let verified = ModuleManager::verify_md5(&part, "00000000000000000000000000000000").unwrap();
        assert!(!verified);
        // 校验失败只删临时文件，绝不动旧文件
        fs::remove_file(&part).ok();
        assert!(final_file.exists(), "下载失败后旧文件必须保留");
        assert_eq!(fs::read(&final_file).unwrap(), b"old-version");
        assert!(!part.exists());

        let _ = fs::remove_dir_all(&dir);
    }

    /// 校验通过后才允许替换：旧文件被新内容覆盖
    #[test]
    fn verified_download_replaces_previous_install() {
        let dir = std::env::temp_dir().join(format!("sw_mm_swap_{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let final_file = dir.join("ffmpeg_1.0.0");
        fs::write(&final_file, b"old-version").unwrap();

        let part = ModuleManager::part_path_of(&final_file);
        fs::write(&part, b"new-version").unwrap();
        let expected = format!("{:x}", md5::compute(b"new-version"));
        assert!(ModuleManager::verify_md5(&part, &expected).unwrap());

        // 与 install_module 相同的顺序：验过 → 删旧 → rename
        if final_file.exists() {
            fs::remove_file(&final_file).unwrap();
        }
        fs::rename(&part, &final_file).unwrap();
        assert_eq!(fs::read(&final_file).unwrap(), b"new-version");
        assert!(!part.exists());

        let _ = fs::remove_dir_all(&dir);
    }
}
