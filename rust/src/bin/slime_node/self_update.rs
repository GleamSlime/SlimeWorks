//! 无头节点自更新。
//!
//! 数据源与客户端更新一致：GitHub Release。流程是
//! 查最新 tag → 比对构建版本 → 下载对应平台的无头包 → 校验 sha256
//! → 解包暂存 → 新二进制自检（`--version`）→ 替换可执行文件 → 原地重启。
//!
//! 替换采用 `rename` 覆盖：Unix 上正在运行的旧 inode 不受影响，
//! 替换后 `exec` 新文件即可完成重启，不依赖 systemd / launchd 的 Restart 策略。
//! 任一步失败都保留旧文件继续服务，最坏情况只是这轮没更新。
//!
//! Windows 不允许覆盖运行中的 exe，这里只下载到暂存位置并提示手动替换，
//! 不做「先退出再让外部脚本拉起」那套：节点无人值守，一旦脚本失败就彻底失联。

use std::fs;
use std::io::Write;
use std::path::Path;
use std::process::ExitCode;
use std::time::{Duration, Instant};

use sha2::{Digest, Sha256};

const REPO: &str = "GleamSlime/SlimeWorks";

/// 自更新参数。
#[derive(Debug, Clone)]
pub struct UpdateOptions {
    /// GitHub API 根地址，可换成镜像/代理
    pub api_base: String,
    /// 定时检查间隔
    pub interval: Duration,
}

/// 一次查询得到的线上版本信息。
#[derive(Debug, Clone)]
pub struct ReleaseInfo {
    pub version: String,
    pub asset_name: String,
    pub download_url: String,
    /// GitHub 资产 digest（`sha256:...`），部分旧版本没有
    pub digest: Option<String>,
}

/// 当前运行的构建版本。
pub fn current_version() -> &'static str {
    rust_lib_slime_works::build_version::BUILD_VERSION
}

/// 当前平台该取哪个无头包（与 CI 的产物命名对应）。
fn asset_suffix() -> &'static str {
    if cfg!(target_os = "macos") {
        "-macos-arm64.tar.gz"
    } else if cfg!(target_os = "windows") {
        "-windows-x86_64.zip"
    } else {
        "-linux-x86_64.tar.gz"
    }
}

/// 把 `v1.0.0+20261117.abcdef` 拆成（语义版本各段，构建号）。
fn split_version(raw: &str) -> (Vec<u64>, Option<String>) {
    let s = raw.trim().trim_start_matches('v');
    let (semver, build) = match s.split_once('+') {
        Some((a, b)) => (a, Some(b.to_string())),
        None => (s, None),
    };
    let parts = semver
        .split('.')
        .map(|p| p.parse::<u64>().unwrap_or(0))
        .collect();
    (parts, build)
}

/// [latest] 是否比 [current] 新。
///
/// 先比语义版本，再比构建号。构建号形如 `20261117.abcdef`（日期.短 hash），
/// 同日内按 hash 字典序，跨日按日期——两者合起来的字典序就是时间序。
pub fn is_newer(latest: &str, current: &str) -> bool {
    let (latest_semver, latest_build) = split_version(latest);
    let (current_semver, current_build) = split_version(current);
    for i in 0..latest_semver.len().max(current_semver.len()) {
        let a = *latest_semver.get(i).unwrap_or(&0);
        let b = *current_semver.get(i).unwrap_or(&0);
        if a != b {
            return a > b;
        }
    }
    match (latest_build, current_build) {
        (Some(a), Some(b)) => a > b,
        // 带构建号的一定比裸版本（本地开发构建）新
        (Some(_), None) => true,
        _ => false,
    }
}

/// 查询线上最新版本与对应平台的资产。
pub fn fetch_latest(opts: &UpdateOptions) -> Result<ReleaseInfo, String> {
    let url = format!(
        "{}/repos/{}/releases/latest",
        opts.api_base.trim_end_matches('/'),
        REPO
    );
    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(30))
        .user_agent("SlimeWorks-Node-Updater")
        .build()
        .map_err(|e| format!("创建 HTTP 客户端失败: {e}"))?;
    let resp = client
        .get(&url)
        .send()
        .map_err(|e| format!("请求 {url} 失败: {e}"))?;
    if !resp.status().is_success() {
        return Err(format!("查询最新版本失败: HTTP {}", resp.status()));
    }
    let text = resp.text().map_err(|e| format!("读取响应失败: {e}"))?;
    let json: serde_json::Value =
        serde_json::from_str(&text).map_err(|e| format!("解析响应失败: {e}"))?;

    let version = json["tag_name"]
        .as_str()
        .unwrap_or_default()
        .trim_start_matches('v')
        .to_string();
    if version.is_empty() {
        return Err("响应里没有 tag_name".to_string());
    }

    let suffix = asset_suffix();
    let assets = json["assets"]
        .as_array()
        .ok_or_else(|| "响应里没有 assets".to_string())?;
    let asset = assets
        .iter()
        .find(|a| {
            a["name"]
                .as_str()
                .map(|n| n.starts_with("slime_node") && n.ends_with(suffix))
                .unwrap_or(false)
        })
        .ok_or_else(|| format!("{version} 没有适配当前平台的无头包（{suffix}）"))?;

    Ok(ReleaseInfo {
        version,
        asset_name: asset["name"].as_str().unwrap_or_default().to_string(),
        download_url: asset["browser_download_url"]
            .as_str()
            .unwrap_or_default()
            .to_string(),
        digest: asset["digest"].as_str().map(|s| s.to_string()),
    })
}

/// 下载并校验，返回落盘路径。
fn download(info: &ReleaseInfo, dest: &Path) -> Result<(), String> {
    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(600))
        .user_agent("SlimeWorks-Node-Updater")
        .build()
        .map_err(|e| format!("创建 HTTP 客户端失败: {e}"))?;
    let mut resp = client
        .get(&info.download_url)
        .send()
        .map_err(|e| format!("下载 {} 失败: {e}", info.asset_name))?;
    if !resp.status().is_success() {
        return Err(format!("下载失败: HTTP {}", resp.status()));
    }

    let mut file = fs::File::create(dest).map_err(|e| format!("创建 {} 失败: {e}", dest.display()))?;
    let mut hasher = Sha256::new();
    let mut buf = [0u8; 64 * 1024];
    loop {
        let n = std::io::Read::read(&mut resp, &mut buf)
            .map_err(|e| format!("读取下载流失败: {e}"))?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
        file.write_all(&buf[..n])
            .map_err(|e| format!("写入 {} 失败: {e}", dest.display()))?;
    }
    file.flush().map_err(|e| format!("落盘失败: {e}"))?;
    let actual = format!("{:x}", hasher.finalize());

    if let Some(expected) = info.digest.as_deref() {
        let expected = expected.trim().trim_start_matches("sha256:");
        if !expected.is_empty() && !expected.eq_ignore_ascii_case(&actual) {
            let _ = fs::remove_file(dest);
            return Err(format!("sha256 校验失败（期望 {expected}，实际 {actual}）"));
        }
    } else {
        println!("[自更新] 资产未提供 digest，已计算 sha256={actual}");
    }
    Ok(())
}

/// 从无头包里取出可执行文件写到 [dest]。
#[cfg(any(target_os = "linux", target_os = "macos"))]
fn extract(archive: &Path, dest: &Path) -> Result<(), String> {
    let file = fs::File::open(archive).map_err(|e| format!("打开压缩包失败: {e}"))?;
    let decoder = flate2::read::GzDecoder::new(file);
    let mut tar = tar::Archive::new(decoder);
    let entries = tar.entries().map_err(|e| format!("读取压缩包失败: {e}"))?;
    for entry in entries {
        let mut entry = entry.map_err(|e| format!("读取压缩包条目失败: {e}"))?;
        let path = entry
            .path()
            .map_err(|e| format!("解析压缩包条目路径失败: {e}"))?
            .to_path_buf();
        let name = path
            .file_name()
            .and_then(|s| s.to_str())
            .unwrap_or_default();
        if !name.starts_with("slime_node") {
            continue;
        }
        let mut out =
            fs::File::create(dest).map_err(|e| format!("创建 {} 失败: {e}", dest.display()))?;
        std::io::copy(&mut entry, &mut out).map_err(|e| format!("解包失败: {e}"))?;
        return Ok(());
    }
    Err("压缩包里没有 slime_node".to_string())
}

#[cfg(not(any(target_os = "linux", target_os = "macos")))]
fn extract(_archive: &Path, _dest: &Path) -> Result<(), String> {
    Err("当前平台不支持自动替换".to_string())
}

#[cfg(unix)]
fn set_executable(path: &Path) -> Result<(), String> {
    use std::os::unix::fs::PermissionsExt;
    let mut perms = fs::metadata(path)
        .map_err(|e| format!("读取 {} 权限失败: {e}", path.display()))?
        .permissions();
    perms.set_mode(0o755);
    fs::set_permissions(path, perms).map_err(|e| format!("设置可执行权限失败: {e}"))
}

#[cfg(not(unix))]
fn set_executable(_path: &Path) -> Result<(), String> {
    Ok(())
}

/// 用暂存的新文件替换可执行文件并重启进程。
///
/// 这里只有在 Unix 上才会真正替换；Windows 见模块注释。
#[cfg(unix)]
fn swap_and_restart(exe: &Path, staged: &Path) -> Result<(), String> {
    use std::os::unix::process::CommandExt;

    let file_name = exe
        .file_name()
        .and_then(|s| s.to_str())
        .ok_or_else(|| "无法解析可执行文件名".to_string())?;
    let backup = exe.with_file_name(format!("{file_name}.bak"));

    // 旧版本留一份备份：exec 失败时可以原地回滚
    if backup.exists() {
        let _ = fs::remove_file(&backup);
    }
    fs::rename(exe, &backup).map_err(|e| {
        format!(
            "备份旧版本失败（目录需要写权限）: {e}；请确认 {} 所在目录可写",
            exe.display()
        )
    })?;
    if let Err(e) = fs::rename(staged, exe) {
        let _ = fs::rename(&backup, exe);
        return Err(format!("替换可执行文件失败: {e}"));
    }

    println!("[自更新] 已替换可执行文件，正在重启进程");
    let _ = std::io::stdout().flush();
    let args: Vec<std::ffi::OsString> = std::env::args_os().skip(1).collect();
    // exec 成功则不返回；fd 默认带 CLOEXEC，端口会随旧进程一起释放
    let err = std::process::Command::new(exe).args(&args).exec();

    // 走到这里说明 exec 失败：把备份换回去，继续用旧版本服务
    let _ = fs::rename(&backup, exe);
    Err(format!("重启失败: {err}（已回滚到旧版本）"))
}

#[cfg(not(unix))]
fn swap_and_restart(exe: &Path, staged: &Path) -> Result<(), String> {
    let _ = fs::remove_file(staged);
    Err(format!(
        "Windows 不允许覆盖运行中的程序（{}），请手动下载 release 里的无头包替换后重启",
        exe.display()
    ))
}

/// 下载、校验、替换、重启。成功时进程已被新版本接管，不会返回。
pub fn apply(info: &ReleaseInfo) -> Result<(), String> {
    let exe = std::env::current_exe().map_err(|e| format!("定位可执行文件失败: {e}"))?;
    let dir = exe
        .parent()
        .ok_or_else(|| "可执行文件没有上级目录".to_string())?;
    let pid = std::process::id();
    let archive = dir.join(format!(".slime_node.update-{pid}.download"));
    let staged = dir.join(format!(".slime_node.update-{pid}.new"));

    println!(
        "[自更新] 下载 {} → {}",
        info.asset_name,
        info.version
    );
    download(info, &archive)?;
    let extracted = extract(&archive, &staged);
    let _ = fs::remove_file(&archive);
    extracted?;
    set_executable(&staged)?;

    // 自检：新文件至少得能报出版本号，避免把坏包换上去
    let probe = std::process::Command::new(&staged)
        .arg("--version")
        .output()
        .map_err(|e| format!("新版本自检失败: {e}"))?;
    let probe_text = String::from_utf8_lossy(&probe.stdout);
    if !probe.status.success() || !probe_text.contains(&info.version) {
        let _ = fs::remove_file(&staged);
        return Err(format!(
            "新版本自检未通过（输出: {}），已放弃本次更新",
            probe_text.trim()
        ));
    }

    swap_and_restart(&exe, &staged)
}

/// 检查一次：有新版本就打印出来，返回是否可更新。
pub fn check_once(opts: &UpdateOptions) -> Result<Option<ReleaseInfo>, String> {
    let latest = fetch_latest(opts)?;
    if is_newer(&latest.version, current_version()) {
        Ok(Some(latest))
    } else {
        println!(
            "[自更新] 已是最新版本 {}（线上 {}）",
            current_version(),
            latest.version
        );
        Ok(None)
    }
}

/// `--check-update`：只查不装。
pub fn run_check(opts: &UpdateOptions) -> ExitCode {
    match check_once(opts) {
        Ok(Some(latest)) => {
            println!(
                "[自更新] 发现新版本 {}（当前 {}），资产 {}",
                latest.version,
                current_version(),
                latest.asset_name
            );
            ExitCode::SUCCESS
        }
        Ok(None) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("[自更新] 检查失败: {err}");
            ExitCode::FAILURE
        }
    }
}

/// `--self-update`：查一次，有就装。
pub fn run_once(opts: &UpdateOptions) -> ExitCode {
    match check_once(opts) {
        Ok(Some(latest)) => match apply(&latest) {
            Ok(()) => ExitCode::SUCCESS,
            Err(err) => {
                eprintln!("[自更新] 更新失败: {err}");
                ExitCode::FAILURE
            }
        },
        Ok(None) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("[自更新] 检查失败: {err}");
            ExitCode::FAILURE
        }
    }
}

/// 启动后台定时检查。首轮延后 30 秒，避开节点启动时的初始化高峰。
pub fn start_auto_update(opts: UpdateOptions) {
    println!(
        "[自更新] 已开启：每 {} 小时检查一次，当前版本 {}",
        opts.interval.as_secs() / 3600,
        current_version()
    );
    std::thread::spawn(move || {
        std::thread::sleep(Duration::from_secs(30));
        loop {
            let started = Instant::now();
            println!("[自更新] 开始检查新版本");
            match check_once(&opts) {
                Ok(Some(latest)) => {
                    if let Err(err) = apply(&latest) {
                        // 更新失败不影响节点继续服务，下一轮再试
                        eprintln!("[自更新] 更新到 {} 失败: {err}", latest.version);
                    }
                }
                Ok(None) => {}
                Err(err) => eprintln!("[自更新] 检查失败: {err}"),
            }
            let elapsed = started.elapsed();
            let wait = opts.interval.saturating_sub(elapsed);
            std::thread::sleep(wait);
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 构建号更新的版本算新() {
        assert!(is_newer("1.0.0+20261117.abcdef", "1.0.0+20261116.abcdef"));
        assert!(is_newer("1.0.0+20261117.abcdef", "1.0.0+20261117.abcdee"));
    }

    #[test]
    fn 版本相同或更旧都不该更新() {
        assert!(!is_newer("1.0.0+20261117.abcdef", "1.0.0+20261117.abcdef"));
        assert!(!is_newer("1.0.0+20261116.abcdef", "1.0.0+20261117.abcdef"));
        assert!(!is_newer("0.9.0+20261117.abcdef", "1.0.0+20261116.abcdef"));
    }

    #[test]
    fn tag_的_v_前缀不影响比较() {
        assert!(is_newer("v1.0.0+20261117.abcdef", "1.0.0+20261116.abcdef"));
    }

    #[test]
    fn 构建号版本比裸版本新() {
        // 本地开发的 0.1.0 与线上同语义版本时，带构建号的一方才算更新
        assert!(is_newer("0.1.0+20261117.abcdef", "0.1.0"));
        assert!(!is_newer("0.1.0", "0.1.0+20261117.abcdef"));
    }

    #[test]
    fn 资产后缀与平台匹配() {
        let suffix = asset_suffix();
        assert!(suffix.starts_with("-"));
        assert!(suffix.ends_with(".tar.gz") || suffix.ends_with(".zip"));
        assert!(
            suffix.contains("macos") || suffix.contains("linux") || suffix.contains("windows"),
            "后缀应带平台标识: {suffix}"
        );
    }
}
