use std::io::{BufWriter, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU32, AtomicU8, Ordering};

/// sherpa-onnx 发行版本号（升级时需同步修改下载 URL）
pub const SHERPA_VERSION: &str = "v1.13.8";

/// 部署进度（百分比 × 100，即 0~10000），u32::MAX 表示空闲。
/// 运行时与模型的下载共用此进度，因为 UI 上是同一个"一键部署"流程。
static DEPLOY_PROGRESS: AtomicU32 = AtomicU32::new(u32::MAX);
/// 部署阶段：0=空闲 1=下载 2=解压 3=完成 4=失败
static DEPLOY_STAGE: AtomicU8 = AtomicU8::new(0);

/// 读取部署进度（0~100），空闲时返回 -1
pub fn get_deploy_progress() -> f64 {
    let val = DEPLOY_PROGRESS.load(Ordering::Relaxed);
    if val == u32::MAX {
        -1.0
    } else {
        val as f64 / 100.0
    }
}

/// 读取当前部署阶段（0~4）
pub fn get_deploy_stage() -> u8 {
    DEPLOY_STAGE.load(Ordering::Relaxed)
}

/// 部署流程全部完成时调用（标记阶段=完成）
pub fn set_deploy_done() {
    set_deploy_stage(3);
    set_deploy_progress(10000);
}

pub(crate) fn set_deploy_progress(pct: u32) {
    DEPLOY_PROGRESS.store(pct.min(10000), Ordering::Relaxed);
}

pub(crate) fn set_deploy_stage(stage: u8) {
    DEPLOY_STAGE.store(stage, Ordering::Relaxed);
}

pub(crate) fn mark_deploy_idle() {
    DEPLOY_PROGRESS.store(u32::MAX, Ordering::Relaxed);
}

/// ASR 数据根目录（Windows: %APPDATA%/SlimeWorks/asr；macOS: ~/Library/Application Support/SlimeWorks/asr）
pub fn asr_root() -> PathBuf {
    let base: PathBuf = if cfg!(target_os = "windows") {
        std::env::var("APPDATA")
            .map(PathBuf::from)
            .unwrap_or_else(|_| PathBuf::from("."))
    } else if cfg!(target_os = "macos") {
        home_dir()
            .join("Library")
            .join("Application Support")
    } else {
        std::env::var("XDG_DATA_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|_| home_dir().join(".local").join("share"))
    };
    let dir = base.join("SlimeWorks").join("asr");
    let _ = std::fs::create_dir_all(&dir);
    dir
}

fn home_dir() -> PathBuf {
    std::env::var("HOME")
        .or_else(|_| std::env::var("USERPROFILE"))
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("."))
}

/// 平台相关的发行包名（不含扩展名），同时也是 tar 包内的顶层目录名
fn archive_stem() -> String {
    if cfg!(target_os = "windows") {
        format!("sherpa-onnx-{}-win-x64-shared-MD-Release", SHERPA_VERSION)
    } else if cfg!(target_os = "macos") {
        if cfg!(target_arch = "aarch64") {
            format!("sherpa-onnx-{}-osx-arm64-shared", SHERPA_VERSION)
        } else {
            format!("sherpa-onnx-{}-osx-x86_64-shared", SHERPA_VERSION)
        }
    } else {
        format!("sherpa-onnx-{}-linux-x64-shared", SHERPA_VERSION)
    }
}

/// 运行时目录：asr/runtime/<平台包名>
pub fn runtime_dir() -> PathBuf {
    asr_root().join("runtime").join(archive_stem())
}

fn runtime_archive_url() -> String {
    format!(
        "https://github.com/k2-fsa/sherpa-onnx/releases/download/{}/{}.tar.bz2",
        SHERPA_VERSION,
        archive_stem()
    )
}

/// sidecar 可执行文件名
fn sidecar_exe_name() -> &'static str {
    if cfg!(target_os = "windows") {
        "sherpa-onnx-vad-with-offline-asr.exe"
    } else {
        "sherpa-onnx-vad-with-offline-asr"
    }
}

/// 定位已安装的 sidecar 可执行文件（在运行时目录树内递归查找，兼容不同包的内层结构）
pub fn find_sidecar_exec() -> Option<PathBuf> {
    let root = runtime_dir();
    if !root.exists() {
        return None;
    }
    find_file_recursive(&root, sidecar_exe_name())
}

/// 递归查找指定文件名的第一个匹配项
pub(crate) fn find_file_recursive(dir: &Path, name: &str) -> Option<PathBuf> {
    let entries = std::fs::read_dir(dir).ok()?;
    let mut subdirs = Vec::new();
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            subdirs.push(path);
        } else if path.file_name().map(|n| n == name).unwrap_or(false) {
            return Some(path);
        }
    }
    for sub in subdirs {
        if let Some(found) = find_file_recursive(&sub, name) {
            return Some(found);
        }
    }
    None
}

/// 运行时是否已就绪
pub fn is_runtime_ready() -> bool {
    find_sidecar_exec().is_some()
}

/// 运行时占用字节数
pub fn runtime_disk_usage() -> u64 {
    dir_size_bytes(&asr_root().join("runtime"))
}

/// 下载并解压 sidecar 运行时（阻塞，需在后台线程调用）
pub fn download_runtime() -> Result<PathBuf, String> {
    if let Some(existing) = find_sidecar_exec() {
        return Ok(existing);
    }

    set_deploy_stage(1);
    set_deploy_progress(0);

    let url = runtime_archive_url();
    slime_logger::sw_info!("[asr] 开始下载 sherpa-onnx 运行时: {}", url);

    let runtime_root = asr_root().join("runtime");
    std::fs::create_dir_all(&runtime_root).map_err(|e| format!("创建运行时目录失败: {}", e))?;
    let archive_path = runtime_root.join("_runtime.tar.bz2");

    if let Err(e) = download_to_file(&url, &archive_path) {
        set_deploy_stage(4);
        mark_deploy_idle();
        let _ = std::fs::remove_file(&archive_path);
        return Err(e);
    }

    set_deploy_stage(2);
    slime_logger::sw_info!("[asr] 运行时下载完成，开始解压");
    let extract_result = extract_tar_bz2(&archive_path, &runtime_root);
    let _ = std::fs::remove_file(&archive_path);

    match extract_result {
        Ok(()) => {
            #[cfg(unix)]
            if let Some(exe) = find_sidecar_exec() {
                use std::os::unix::fs::PermissionsExt;
                let _ = std::fs::set_permissions(&exe, std::fs::Permissions::from_mode(0o755));
            }
            set_deploy_stage(3);
            set_deploy_progress(10000);
            find_sidecar_exec().ok_or_else(|| "解压后未找到 sidecar 可执行文件".to_string())
        }
        Err(e) => {
            set_deploy_stage(4);
            mark_deploy_idle();
            Err(e)
        }
    }
}

/// 删除运行时目录（卸载/重装前清理）
pub fn remove_runtime() -> Result<(), String> {
    let dir = asr_root().join("runtime");
    if dir.exists() {
        std::fs::remove_dir_all(&dir).map_err(|e| format!("删除运行时目录失败: {}", e))?;
    }
    set_deploy_stage(0);
    mark_deploy_idle();
    Ok(())
}

/// GitHub Release 直连在境内经常连接重置，优先走加速镜像，最后才回退原始地址。
/// 镜像可用性会变化，所以逐个尝试而不是只写一个。
const URL_MIRRORS: [&str; 2] = ["https://gh-proxy.com/", "https://ghfast.top/"];

pub(crate) fn url_candidates(url: &str) -> Vec<String> {
    let mut list: Vec<String> = URL_MIRRORS
        .iter()
        .map(|mirror| format!("{mirror}{url}"))
        .collect();
    list.push(url.to_string());
    list
}

/// 流式下载到文件，按 content-length 更新部署进度；失败时自动换下一个镜像地址
///
/// 半截文件保留给下一个地址续传：模型包上百 MB，境内链路动辄十几分钟，
/// 每换一次镜像就从 0 重来基本等于下不完。
pub(crate) fn download_to_file(url: &str, dest: &Path) -> Result<(), String> {
    let mut last_error = String::from("没有可用的下载地址");
    for candidate in url_candidates(url) {
        match download_single(&candidate, dest) {
            Ok(()) => return Ok(()),
            Err(e) => {
                slime_logger::sw_warn!("[asr] 下载地址失败({})，尝试下一个: {}", candidate, e);
                last_error = e;
            }
        }
    }
    // 全部镜像都失败：清掉残留的半截文件，避免下次部署拿坏文件续传
    let _ = std::fs::remove_file(dest);
    Err(format!("下载失败: {last_error}"))
}

fn download_single(url: &str, dest: &Path) -> Result<(), String> {
    use std::fs::OpenOptions;
    use std::io::Read;

    let resumed = std::fs::metadata(dest).map(|m| m.len()).unwrap_or(0);

    let client = reqwest::blocking::Client::builder()
        .user_agent("SlimeWorks-ASR")
        .connect_timeout(std::time::Duration::from_secs(10))
        // 不设整体 timeout：几百 MB 的模型下载在慢速链路上会被误杀，
        // 链路真断掉时 read 本身就会返回错误，交由上层换下一个镜像重试
        .build()
        .map_err(|e| format!("创建 HTTP 客户端失败: {}", e))?;
    let mut request = client.get(url);
    if resumed > 0 {
        request = request.header("Range", format!("bytes={resumed}-"));
    }
    let mut response = request
        .send()
        .map_err(|e| format!("下载请求失败: {}", e))?;
    let status = response.status();
    if !status.is_success() && status.as_u16() != 206 {
        return Err(format!("下载失败，HTTP 状态: {}", status));
    }
    // 服务端忽略 Range 时返回 200 全量内容，此时必须从头覆盖写
    let append = resumed > 0 && status.as_u16() == 206;
    let body_len = response.content_length().unwrap_or(0);
    let total = if append { resumed + body_len } else { body_len };

    let file = OpenOptions::new()
        .write(true)
        .create(true)
        .append(append)
        .truncate(!append)
        .open(dest)
        .map_err(|e| format!("创建文件失败: {}", e))?;
    let mut writer = BufWriter::new(file);

    let mut buffer = [0u8; 65536];
    let mut downloaded = if append { resumed } else { 0 };
    loop {
        let n = response
            .read(&mut buffer)
            .map_err(|e| format!("读取下载流失败: {}", e))?;
        if n == 0 {
            break;
        }
        writer
            .write_all(&buffer[..n])
            .map_err(|e| format!("写入文件失败: {}", e))?;
        downloaded += n as u64;
        if total > 0 {
            set_deploy_progress((downloaded * 10000 / total) as u32);
        }
    }
    writer
        .flush()
        .map_err(|e| format!("刷新文件失败: {}", e))?;
    drop(writer);

    let written = std::fs::metadata(dest).map(|m| m.len()).unwrap_or(0);
    // 镜像偶尔会把 404 页面写进文件，体积过小说明拿到的不是压缩包
    if written < 1024 {
        return Err(format!("下载内容异常（仅 {} 字节）", written));
    }
    // 长度对不上说明连接中途断了：保留半截文件，换下一个地址续传
    if total > 0 && written < total {
        return Err(format!("下载不完整（{written}/{total} 字节）"));
    }
    Ok(())
}

/// 解压 .tar.bz2 到目标目录
pub(crate) fn extract_tar_bz2(archive: &Path, dest: &Path) -> Result<(), String> {
    std::fs::create_dir_all(dest).map_err(|e| format!("创建解压目录失败: {}", e))?;
    let bz = std::fs::File::open(archive).map_err(|e| format!("打开压缩包失败: {}", e))?;
    let decoder = bzip2::bufread::BzDecoder::new(std::io::BufReader::new(bz));
    tar::Archive::new(decoder)
        .unpack(dest)
        .map_err(|e| format!("解压失败: {}", e))?;
    Ok(())
}

/// 统计目录占用字节数（跳过读取失败项）
pub(crate) fn dir_size_bytes(dir: &Path) -> u64 {
    let mut total = 0u64;
    if let Ok(entries) = std::fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                total += dir_size_bytes(&path);
            } else if let Ok(meta) = std::fs::metadata(&path) {
                total += meta.len();
            }
        }
    }
    total
}
