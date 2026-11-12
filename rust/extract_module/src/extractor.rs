use slime_logger::{sw_info, sw_error};
use std::fs::{self, File};
use std::io::BufReader;
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Instant;

use anyhow::{Context, Result};

use crate::types::*;

static CANCEL_FLAG: AtomicBool = AtomicBool::new(false);

pub fn request_cancel() {
    CANCEL_FLAG.store(true, Ordering::SeqCst);
}

pub fn reset_cancel() {
    CANCEL_FLAG.store(false, Ordering::SeqCst);
}

pub fn is_cancelled() -> bool {
    CANCEL_FLAG.load(Ordering::SeqCst)
}

#[derive(Debug, Clone, Copy, PartialEq)]
enum ArchiveFormat {
    SevenZ,
    Zip,
    Tar,
    TarGz,
    TarBz2,
    TarXz,
    Gz,
    Bz2,
    Xz,
    Rar,
}

fn detect_format(path: &str) -> Option<ArchiveFormat> {
    let p = Path::new(path);
    let lower = p.to_string_lossy().to_lowercase();
    if lower.ends_with(".7z") {
        Some(ArchiveFormat::SevenZ)
    } else if lower.ends_with(".zip") {
        Some(ArchiveFormat::Zip)
    } else if lower.ends_with(".tar.gz") || lower.ends_with(".tgz") {
        Some(ArchiveFormat::TarGz)
    } else if lower.ends_with(".tar.bz2") || lower.ends_with(".tbz2") {
        Some(ArchiveFormat::TarBz2)
    } else if lower.ends_with(".tar.xz") || lower.ends_with(".txz") {
        Some(ArchiveFormat::TarXz)
    } else if lower.ends_with(".tar") {
        Some(ArchiveFormat::Tar)
    } else if lower.ends_with(".rar") {
        Some(ArchiveFormat::Rar)
    } else if lower.ends_with(".gz") {
        Some(ArchiveFormat::Gz)
    } else if lower.ends_with(".bz2") {
        Some(ArchiveFormat::Bz2)
    } else if lower.ends_with(".xz") {
        Some(ArchiveFormat::Xz)
    } else {
        None
    }
}

fn extract_7z(archive_path: &str, output_dir: &str, password: Option<&str>) -> Result<()> {
    let output = Path::new(output_dir);
    fs::create_dir_all(output)?;

    if let Some(pw) = password {
        if !pw.is_empty() {
            sevenz_rust2::decompress_file_with_password(archive_path, output_dir, pw.into())
                .with_context(|| format!("7z 解压失败: {}", archive_path))?;
            return Ok(());
        }
    }
    sevenz_rust2::decompress_file(archive_path, output_dir)
        .with_context(|| format!("7z 解压失败: {}", archive_path))?;
    Ok(())
}

/// 解压后累计写出体积上限。
///
/// 上传与解压两处都只看压缩体大小（8 GiB），而 zip bomb 一笔 1 MB 的包能解出 TB 级：
/// 没有这个上限，一个压缩包就能写满节点磁盘。
const MAX_EXTRACTED_BYTES: u64 = 64 * 1024 * 1024 * 1024; // 64 GiB

/// 把 zip crate 的错误翻译成中文，并且把「密码错/缺密码」与「文件损坏」区分开。
///
/// AES 条目的密码校验分两处：打开条目时校验 2 字节验证值（→ InvalidPassword），
/// 以及读完数据时校验 HMAC（→ Io(InvalidData)）。只映射前者会让密码错误的 AES 包
/// 被报成「文件损坏」，用户会误以为压缩包本身坏了而反复重下。
fn describe_zip_error(err: &zip::result::ZipError, password_given: bool) -> String {
    match err {
        zip::result::ZipError::InvalidPassword => "密码错误或未提供".to_string(),
        zip::result::ZipError::UnsupportedArchive(msg)
            if *msg == zip::result::ZipError::PASSWORD_REQUIRED =>
        {
            "该压缩包已加密，需要提供密码".to_string()
        }
        zip::result::ZipError::Io(io_err)
            if password_given && io_err.kind() == std::io::ErrorKind::InvalidData =>
        {
            // HMAC 校验失败：密码错或数据被篡改，两者都按密码问题提示
            "密码错误或未提供".to_string()
        }
        other => format!("压缩包读取失败: {}", other),
    }
}

fn extract_zip(archive_path: &str, output_dir: &str, password: Option<&str>) -> Result<()> {
    let output = Path::new(output_dir);
    fs::create_dir_all(output)?;

    let file =
        File::open(archive_path).with_context(|| format!("无法打开 zip 文件: {}", archive_path))?;
    let mut archive = zip::ZipArchive::new(BufReader::new(file))
        .with_context(|| format!("无法读取 zip 文件: {}", archive_path))?;

    // 空串按「未提供密码」处理：UI 上密码框留空与不填语义相同
    let password = password.filter(|p| !p.is_empty());
    let password_given = password.is_some();

    let mut written_total: u64 = 0;
    for i in 0..archive.len() {
        if is_cancelled() {
            anyhow::bail!("用户取消");
        }
        // 加密条目必须走 decrypt 分支：by_index 对加密条目会返回 PASSWORD_REQUIRED
        let opened = match password {
            Some(pwd) => archive.by_index_decrypt(i, pwd.as_bytes()),
            None => archive.by_index(i),
        };
        let mut entry = match opened {
            Ok(entry) => entry,
            Err(e) => return Err(anyhow::anyhow!(describe_zip_error(&e, password_given))),
        };
        let outpath = match entry.enclosed_name() {
            Some(path) => output.join(path),
            None => continue,
        };

        if entry.is_dir() {
            fs::create_dir_all(&outpath)?;
        } else {
            if let Some(parent) = outpath.parent() {
                fs::create_dir_all(parent)?;
            }
            let mut outfile = File::create(&outpath)
                .with_context(|| format!("无法创建文件: {}", outpath.display()))?;
            // 防 zip bomb：累计写出量超限立即中止（已解出的部分由调用方清理）
            match copy_with_limit(&mut entry, &mut outfile, &mut written_total) {
                Ok(_) => {}
                // 读取期错误（AES HMAC、坏块）同样要区分密码问题与损坏
                Err(e) => return Err(anyhow::anyhow!(describe_zip_error_anyhow(&e, password_given))),
            }
        }
    }
    Ok(())
}

/// copy_with_limit 返回的是 anyhow 错误，这里只在能判定「密码相关」时才改写文案。
fn describe_zip_error_anyhow(err: &anyhow::Error, password_given: bool) -> String {
    for cause in err.chain() {
        if let Some(zip_err) = cause.downcast_ref::<zip::result::ZipError>() {
            return describe_zip_error(zip_err, password_given);
        }
    }
    format!("{}", err)
}


/// 边读边写并累计体积，超过 [MAX_EXTRACTED_BYTES] 立即中止。
/// 单文件解压（gz/bz2/xz）与 zip 条目共用这一个卡口。
fn copy_with_limit<R: std::io::Read, W: std::io::Write>(
    reader: &mut R,
    writer: &mut W,
    total: &mut u64,
) -> Result<u64> {
    use std::io::{Read, Write};
    let mut buf = vec![0u8; 64 * 1024];
    let mut copied = 0u64;
    loop {
        let n = reader.read(&mut buf)?;
        if n == 0 {
            break;
        }
        writer.write_all(&buf[..n])?;
        copied += n as u64;
        *total = total.saturating_add(n as u64);
        if *total > MAX_EXTRACTED_BYTES {
            anyhow::bail!(
                "解压后体积超过上限 {} GiB，疑似压缩炸弹，已中止",
                MAX_EXTRACTED_BYTES / 1024 / 1024 / 1024
            );
        }
    }
    Ok(copied)
}

/// tar 系列统一走这里：`Archive::unpack` 无法卡体积，
/// 改为逐条目读取并累计写出量，超限中止（软链/设备文件照常由 unpack_in 处理）。
fn unpack_tar_limited<R: std::io::Read>(archive: &mut tar::Archive<R>, output: &Path) -> Result<()> {
    let mut total: u64 = 0;
    for entry in archive.entries()? {
        if is_cancelled() {
            anyhow::bail!("用户取消");
        }
        let mut entry = entry?;
        // header 声明的大小即可判定炸弹：真实写出量不会超过它
        total = total.saturating_add(entry.size());
        if total > MAX_EXTRACTED_BYTES {
            anyhow::bail!(
                "解压后体积超过上限 {} GiB，疑似压缩炸弹，已中止",
                MAX_EXTRACTED_BYTES / 1024 / 1024 / 1024
            );
        }
        entry.unpack_in(output)?;
    }
    Ok(())
}

fn extract_tar(archive_path: &str, output_dir: &str) -> Result<()> {
    let output = Path::new(output_dir);
    fs::create_dir_all(output)?;

    let file =
        File::open(archive_path).with_context(|| format!("无法打开 tar 文件: {}", archive_path))?;
    let mut archive = tar::Archive::new(file);
    unpack_tar_limited(&mut archive, output)
        .with_context(|| format!("tar 解压失败: {}", archive_path))?;
    Ok(())
}

fn extract_tar_gz(archive_path: &str, output_dir: &str) -> Result<()> {
    let output = Path::new(output_dir);
    fs::create_dir_all(output)?;

    let file = File::open(archive_path)
        .with_context(|| format!("无法打开 tar.gz 文件: {}", archive_path))?;
    let gz = flate2::read::GzDecoder::new(file);
    let mut archive = tar::Archive::new(gz);
    unpack_tar_limited(&mut archive, output)
        .with_context(|| format!("tar.gz 解压失败: {}", archive_path))?;
    Ok(())
}

fn extract_tar_bz2(archive_path: &str, output_dir: &str) -> Result<()> {
    let output = Path::new(output_dir);
    fs::create_dir_all(output)?;

    let file = File::open(archive_path)
        .with_context(|| format!("无法打开 tar.bz2 文件: {}", archive_path))?;
    let bz2 = bzip2::read::BzDecoder::new(file);
    let mut archive = tar::Archive::new(bz2);
    unpack_tar_limited(&mut archive, output)
        .with_context(|| format!("tar.bz2 解压失败: {}", archive_path))?;
    Ok(())
}

fn extract_tar_xz(archive_path: &str, output_dir: &str) -> Result<()> {
    let output = Path::new(output_dir);
    fs::create_dir_all(output)?;

    let file = File::open(archive_path)
        .with_context(|| format!("无法打开 tar.xz 文件: {}", archive_path))?;
    let xz = liblzma::read::XzDecoder::new(file);
    let mut archive = tar::Archive::new(xz);
    unpack_tar_limited(&mut archive, output)
        .with_context(|| format!("tar.xz 解压失败: {}", archive_path))?;
    Ok(())
}

fn extract_gz(archive_path: &str, output_dir: &str) -> Result<()> {
    let output = Path::new(output_dir);
    fs::create_dir_all(output)?;

    let file =
        File::open(archive_path).with_context(|| format!("无法打开 gz 文件: {}", archive_path))?;
    let mut gz = flate2::read::GzDecoder::new(file);

    let p = Path::new(archive_path);
    let stem = p
        .file_stem()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();
    let outpath = output.join(&stem);
    let mut outfile =
        File::create(&outpath).with_context(|| format!("无法创建文件: {}", outpath.display()))?;
    let mut total = 0u64;
    copy_with_limit(&mut gz, &mut outfile, &mut total)?;
    Ok(())
}

fn extract_bz2(archive_path: &str, output_dir: &str) -> Result<()> {
    let output = Path::new(output_dir);
    fs::create_dir_all(output)?;

    let file =
        File::open(archive_path).with_context(|| format!("无法打开 bz2 文件: {}", archive_path))?;
    let mut bz2 = bzip2::read::BzDecoder::new(file);

    let p = Path::new(archive_path);
    let stem = p
        .file_stem()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();
    let outpath = output.join(&stem);
    let mut outfile =
        File::create(&outpath).with_context(|| format!("无法创建文件: {}", outpath.display()))?;
    let mut total = 0u64;
    copy_with_limit(&mut bz2, &mut outfile, &mut total)?;
    Ok(())
}

fn extract_xz(archive_path: &str, output_dir: &str) -> Result<()> {
    let output = Path::new(output_dir);
    fs::create_dir_all(output)?;

    let file =
        File::open(archive_path).with_context(|| format!("无法打开 xz 文件: {}", archive_path))?;
    let mut xz = liblzma::read::XzDecoder::new(file);

    let p = Path::new(archive_path);
    let stem = p
        .file_stem()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();
    let outpath = output.join(&stem);
    let mut outfile =
        File::create(&outpath).with_context(|| format!("无法创建文件: {}", outpath.display()))?;
    let mut total = 0u64;
    copy_with_limit(&mut xz, &mut outfile, &mut total)?;
    Ok(())
}

pub fn scan_archives(dir: &str) -> Result<Vec<ArchiveInfo>> {
    let path = Path::new(dir);
    if !path.exists() {
        anyhow::bail!("目录不存在: {}", dir);
    }
    let extensions = [
        "zip", "7z", "rar", "tar", "gz", "bz2", "xz", "tar.gz", "tgz",
    ];
    let mut archives = Vec::new();
    scan_archives_recursive(path, path, &extensions, &mut archives)?;
    archives.sort_by(|a, b| a.path.cmp(&b.path));
    Ok(archives)
}

fn scan_archives_recursive(
    base: &Path,
    current: &Path,
    extensions: &[&str],
    results: &mut Vec<ArchiveInfo>,
) -> Result<()> {
    scan_archives_inner(base, current, extensions, results, 0)
}

/// 与 zip_tree 同口径的防御：限深 + 跳过软链。
/// path.is_dir() 会跟随软链，用户目录里一个指向祖先的软链就会无限递归栈溢出。
fn scan_archives_inner(
    base: &Path,
    current: &Path,
    extensions: &[&str],
    results: &mut Vec<ArchiveInfo>,
    depth: usize,
) -> Result<()> {
    const MAX_DEPTH: usize = 32;
    if depth >= MAX_DEPTH || !current.exists() {
        return Ok(());
    }
    for entry in std::fs::read_dir(current)? {
        let entry = entry?;
        let path = entry.path();
        // file_type() 不跟随软链；拿不到类型的条目（并发删除/权限变化）直接跳过
        let Ok(file_type) = entry.file_type() else {
            continue;
        };
        if file_type.is_symlink() {
            continue;
        }
        if file_type.is_dir() {
            scan_archives_inner(base, &path, extensions, results, depth + 1)?;
            continue;
        }
        let file_name = path
            .file_name()
            .unwrap_or_default()
            .to_string_lossy()
            .to_string();
        let lower = file_name.to_lowercase();
        let is_archive = extensions.iter().any(|ext| {
            if ext.contains('.') {
                lower.ends_with(ext)
            } else {
                let parts: Vec<&str> = lower.rsplitn(2, '.').collect();
                parts.first().map(|p| *p == *ext).unwrap_or(false)
            }
        });
        if is_archive {
            // 扫描期间文件被并发删除/权限变化时跳过该条目，不能 panic 炸掉整个扫描
            let Ok(metadata) = std::fs::metadata(&path)
                .or_else(|_| std::fs::symlink_metadata(&path))
            else {
                continue;
            };
            results.push(ArchiveInfo {
                path: path.to_string_lossy().to_string(),
                file_name,
                file_size: metadata.len(),
                is_password_protected: false,
            });
        }
    }
    Ok(())
}

pub fn extract_archive(
    archive_path: &str,
    output_dir: &str,
    password: Option<&str>,
    progress_callback: &dyn Fn(f64),
) -> Result<()> {
    let format = detect_format(archive_path)
        .with_context(|| format!("无法识别压缩格式: {}", archive_path))?;

    match format {
        ArchiveFormat::SevenZ => extract_7z(archive_path, output_dir, password)?,
        ArchiveFormat::Zip => extract_zip(archive_path, output_dir, password)?,
        ArchiveFormat::Tar => extract_tar(archive_path, output_dir)?,
        ArchiveFormat::TarGz => extract_tar_gz(archive_path, output_dir)?,
        ArchiveFormat::TarBz2 => extract_tar_bz2(archive_path, output_dir)?,
        ArchiveFormat::TarXz => extract_tar_xz(archive_path, output_dir)?,
        ArchiveFormat::Gz => extract_gz(archive_path, output_dir)?,
        ArchiveFormat::Bz2 => extract_bz2(archive_path, output_dir)?,
        ArchiveFormat::Xz => extract_xz(archive_path, output_dir)?,
        ArchiveFormat::Rar => {
            anyhow::bail!("RAR 格式暂不支持纯 Rust 解压，请使用 7z 或 zip 格式");
        }
    }

    progress_callback(1.0);
    Ok(())
}

pub fn calculate_output_dir(
    archive_path: &str,
    base_output: &str,
    source_dir: &str,
    mode: &ExtractOutputMode,
) -> String {
    let archive = Path::new(archive_path);
    match mode {
        ExtractOutputMode::SameDirectory => archive
            .parent()
            .unwrap_or(Path::new("."))
            .to_string_lossy()
            .to_string(),
        ExtractOutputMode::FlatToOutput => base_output.to_string(),
        ExtractOutputMode::ByArchiveName => {
            let stem = archive.file_stem().unwrap_or_default().to_string_lossy();
            let out = Path::new(base_output).join(stem.as_ref());
            out.to_string_lossy().to_string()
        }
        ExtractOutputMode::PreserveStructure => {
            let rel = Path::new(archive_path)
                .strip_prefix(source_dir)
                .unwrap_or(Path::new(archive_path));
            let parent = rel.parent().unwrap_or(Path::new("."));
            let out = Path::new(base_output).join(parent);
            out.to_string_lossy().to_string()
        }
    }
}

pub fn run_extract(
    config: &ExtractConfig,
    progress_callback: &dyn Fn(ExtractProgress),
) -> ExtractResult {
    reset_cancel();
    let start = Instant::now();

    let archives = match scan_archives(&config.source_dir) {
        Ok(a) => a,
        Err(e) => {
            return ExtractResult {
                success: false,
                total_archives: 0,
                total_file_size: 0,
                extracted_size: 0,
                elapsed_seconds: 0.0,
                failed_archives: vec![],
                error_message: Some(format!("扫描压缩包失败: {}", e)),
            };
        }
    };

    if archives.is_empty() {
        return ExtractResult {
            success: true,
            total_archives: 0,
            total_file_size: 0,
            extracted_size: 0,
            elapsed_seconds: start.elapsed().as_secs_f64(),
            failed_archives: vec![],
            error_message: Some("未找到压缩包".to_string()),
        };
    }

    let total_count = archives.len() as u32;
    let total_size: u64 = archives.iter().map(|a| a.file_size).sum();
    let mut extracted_size: u64 = 0;
    let mut failed_archives: Vec<String> = Vec::new();
    // 首个失败原因：加密包密码错时，调用方需要看到「密码错误或未提供」而不是只有文件名
    let mut first_failure_reason: Option<String> = None;
    let mut completed_count: u32 = 0;

    sw_info!(
        "开始解压: 共 {} 个压缩包, 总大小 {} 字节",
        total_count, total_size
    );

    progress_callback(ExtractProgress {
        total_archives: total_count,
        current_archive_index: 0,
        current_archive_name: String::new(),
        current_archive_progress: 0.0,
        total_progress: 0.0,
        total_file_size: total_size,
        extracted_file_size: 0,
        elapsed_seconds: 0.0,
        estimated_remaining_seconds: 0.0,
        status: ExtractStatus::Extracting,
    });

    for (idx, archive) in archives.iter().enumerate() {
        if is_cancelled() {
            sw_info!("解压已取消");
            return ExtractResult {
                success: false,
                total_archives: total_count,
                total_file_size: total_size,
                extracted_size,
                elapsed_seconds: start.elapsed().as_secs_f64(),
                failed_archives,
                error_message: Some("用户取消".to_string()),
            };
        }

        let output_dir = calculate_output_dir(
            &archive.path,
            &config.output_dir,
            &config.source_dir,
            &config.output_mode,
        );

        progress_callback(ExtractProgress {
            total_archives: total_count,
            current_archive_index: idx as u32,
            current_archive_name: archive.file_name.clone(),
            current_archive_progress: 0.0,
            total_progress: completed_count as f64 / total_count as f64,
            total_file_size: total_size,
            extracted_file_size: extracted_size,
            elapsed_seconds: start.elapsed().as_secs_f64(),
            estimated_remaining_seconds: 0.0,
            status: ExtractStatus::Extracting,
        });

        match extract_archive(
            &archive.path,
            &output_dir,
            config.password.as_deref(),
            &|pct| {
                let elapsed = start.elapsed().as_secs_f64();
                let base_progress = completed_count as f64 / total_count as f64;
                let archive_weight = 1.0 / total_count as f64;
                let total_progress = base_progress + pct * archive_weight;
                let estimated_remaining = if total_progress > 0.0 && elapsed > 0.0 {
                    elapsed / total_progress - elapsed
                } else {
                    0.0
                };
                progress_callback(ExtractProgress {
                    total_archives: total_count,
                    current_archive_index: idx as u32,
                    current_archive_name: archive.file_name.clone(),
                    current_archive_progress: pct,
                    total_progress,
                    total_file_size: total_size,
                    extracted_file_size: extracted_size,
                    elapsed_seconds: elapsed,
                    estimated_remaining_seconds: estimated_remaining,
                    status: ExtractStatus::Extracting,
                });
            },
        ) {
            Ok(()) => {
                extracted_size += archive.file_size;
                sw_info!("解压成功: {}", archive.file_name);
            }
            Err(e) => {
                sw_error!("解压失败: {} - {}", archive.file_name, e);
                failed_archives.push(archive.file_name.clone());
                // 只留第一条原因：UI 只展示一句汇总，逐条堆叠反而看不清
                if first_failure_reason.is_none() {
                    first_failure_reason = Some(e.to_string());
                }
            }
        }

        completed_count += 1;
        let elapsed = start.elapsed().as_secs_f64();
        let progress = completed_count as f64 / total_count as f64;
        let estimated_remaining = if progress > 0.0 && elapsed > 0.0 {
            elapsed / progress - elapsed
        } else {
            0.0
        };

        progress_callback(ExtractProgress {
            total_archives: total_count,
            current_archive_index: idx as u32,
            current_archive_name: archive.file_name.clone(),
            current_archive_progress: 1.0,
            total_progress: progress,
            total_file_size: total_size,
            extracted_file_size: extracted_size,
            elapsed_seconds: elapsed,
            estimated_remaining_seconds: estimated_remaining,
            status: ExtractStatus::Extracting,
        });
    }

    let elapsed = start.elapsed().as_secs_f64();
    let success = failed_archives.is_empty();

    progress_callback(ExtractProgress {
        total_archives: total_count,
        current_archive_index: total_count,
        current_archive_name: String::new(),
        current_archive_progress: 1.0,
        total_progress: 1.0,
        total_file_size: total_size,
        extracted_file_size: extracted_size,
        elapsed_seconds: elapsed,
        estimated_remaining_seconds: 0.0,
        status: if success {
            ExtractStatus::Completed
        } else {
            ExtractStatus::Failed
        },
    });

    let has_failures = !failed_archives.is_empty();
    let failed_count = failed_archives.len();
    ExtractResult {
        success,
        total_archives: total_count,
        total_file_size: total_size,
        extracted_size,
        elapsed_seconds: elapsed,
        failed_archives,
        error_message: if has_failures {
            match first_failure_reason {
                Some(reason) => Some(format!("{} 个压缩包解压失败：{}", failed_count, reason)),
                None => Some(format!("{} 个压缩包解压失败", failed_count)),
            }
        } else {
            None
        },
    }
}

/// 校验打包用的顶层目录名，返回去掉首尾空白的可写入版本。
///
/// 允许嵌套根（漫画推送恒传 `漫画名/话名` 两级），但必须**逐段**校验：
/// 旧实现一律拒掉含 `/` 的值，导致每一章推送都在打包阶段失败。
/// 逐段规则与 zip-slip 防护同口径——某一段是空串、`.`、`..`、带盘符冒号或反斜杠时，
/// 拼出的条目名就可能落到目标目录之外，或根本不是合法 zip 条目名。
fn validate_entry_root(entry_root: &str) -> Result<&str> {
    // 末尾斜杠只是目录层级收尾，对条目名无影响，先剥掉；
    // 前导斜杠代表绝对路径，必须原样保留下来被下面的空段规则拒掉。
    let trimmed = entry_root.trim().trim_end_matches('/');
    anyhow::ensure!(!trimmed.is_empty(), "压缩包顶层目录名不合法: {}", entry_root);
    for seg in trimmed.split('/') {
        anyhow::ensure!(
            !seg.is_empty(),
            "压缩包顶层目录名含空路径段: {}",
            entry_root
        );
        anyhow::ensure!(
            seg != "." && seg != "..",
            "压缩包顶层目录名不得包含 . 或 ..: {}",
            entry_root
        );
        // 反斜杠在 zip 条目名里不是分隔符，出现即说明调用方传了 Windows 路径
        anyhow::ensure!(
            !seg.contains('\\'),
            "压缩包顶层目录名不得包含反斜杠: {}",
            entry_root
        );
        // 盘符（C:）与 NTFS 备用流都带冒号，嵌套根里不应出现
        anyhow::ensure!(
            !seg.contains(':'),
            "压缩包顶层目录名不得包含盘符或冒号: {}",
            entry_root
        );
        anyhow::ensure!(
            !seg.chars().any(|c| c.is_control()),
            "压缩包顶层目录名不得包含控制字符: {}",
            entry_root
        );
    }
    Ok(trimmed)
}

/// 把 `src_dir` 整棵目录树打包成 zip 写入系统临时目录，返回 zip 的绝对路径。
///
/// 压缩包内所有条目都以 `entry_root` 为顶层目录名，节点端把包解压到目标目录下即可
/// 原样还原层级。刻意跳过 `.SlimeWorks`（本应用生成的邻近缩略图缓存）与 `.DS_Store`：
/// 把派生缓存搬给对方节点既白占带宽，又可能让对端把缓存文件当资源导入。
pub fn zip_directory_to_tmp(src_dir: &str, entry_root: &str) -> Result<String> {
    let root = Path::new(src_dir);
    anyhow::ensure!(root.is_dir(), "源目录不存在或不是目录: {}", src_dir);
    let entry_root = validate_entry_root(entry_root)?;

    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or(0);
    let zip_path = std::env::temp_dir().join(format!("sw_upload_{stamp}.zip"));
    let file =
        File::create(&zip_path).with_context(|| format!("创建压缩包失败: {}", zip_path.display()))?;

    let mut writer = zip::ZipWriter::new(std::io::BufWriter::new(file));
    let options = zip::write::FileOptions::default()
        .compression_method(zip::CompressionMethod::Deflated);
    // 顶层目录本身也要写进去：节点端解压后才有清晰的单根目录，
    // 不会把散落文件直接摊进目标目录
    writer.add_directory(entry_root.to_string(), options)?;
    zip_tree(&mut writer, root, entry_root, options, 0)?;
    // finish() 会消费 writer 并交还缓冲层；显式 into_inner() 才能拿到 flush 的 IO 错误，
    // 否则缓冲写失败会被 Drop 静默吞掉，留下一个损坏的 zip 继续往上传
    let buffered = writer.finish().context("写入压缩包索引失败")?;
    buffered
        .into_inner()
        .map_err(|e| anyhow::anyhow!("刷新压缩包缓冲失败: {}", e))?;

    Ok(zip_path.to_string_lossy().into_owned())
}

/// 递归把 `dir` 下的内容写入压缩包，条目名前缀为 `prefix`。
/// 限深只为防御异常深的目录树（以及被误配成的自引用软链结构）。
fn zip_tree<'a, W: std::io::Write + std::io::Seek>(
    writer: &mut zip::ZipWriter<W>,
    dir: &Path,
    prefix: &str,
    options: zip::write::FileOptions<'a, ()>,
    depth: usize,
) -> Result<()> {
    const MAX_DEPTH: usize = 32;
    if depth >= MAX_DEPTH {
        sw_info!("[zip_directory] 目录层级超过 {} 层，后续内容跳过: {}", MAX_DEPTH, dir.display());
        return Ok(());
    }
    let mut sub_dirs = Vec::new();
    for entry in fs::read_dir(dir).with_context(|| format!("读取目录失败: {}", dir.display()))? {
        let entry = entry?;
        let name = entry.file_name().to_string_lossy().to_string();
        if name == ".SlimeWorks" || name == ".DS_Store" {
            continue;
        }
        let path = entry.path();
        // file_type() 不跟随软链，软链一律跳过：目录环会在递归里失控，
        // 而且对端拿到的也只是个指向它自己机器上不存在路径的链接
        if entry.file_type()?.is_symlink() {
            continue;
        }
        let item_prefix = format!("{prefix}/{name}");
        // 用 file_type 判定（不跟随软链）；上面已排除软链，这里语义等价但更明确
        if entry.file_type()?.is_dir() {
            writer.add_directory(&item_prefix, options)?;
            sub_dirs.push((path, item_prefix));
        } else if let Ok(mut content) = fs::File::open(&path) {
            writer.start_file(&item_prefix, options)?;
            std::io::copy(&mut content, writer)
                .with_context(|| format!("写入压缩包失败: {}", path.display()))?;
        }
    }
    for (sub_dir, sub_prefix) in sub_dirs {
        zip_tree(writer, &sub_dir, &sub_prefix, options, depth + 1)?;
    }
    Ok(())
}

pub fn get_dir_size(path: &str) -> Result<u64> {
    let p = Path::new(path);
    if !p.exists() {
        return Ok(0);
    }
    let mut total: u64 = 0;
    // 与 zip_tree/扫描同口径：限深 + 跳软链，防目录环栈溢出
    fn walk(dir: &Path, total: &mut u64, depth: usize) -> Result<()> {
        const MAX_DEPTH: usize = 32;
        if depth >= MAX_DEPTH {
            return Ok(());
        }
        for entry in std::fs::read_dir(dir)? {
            let entry = entry?;
            let Ok(file_type) = entry.file_type() else {
                continue;
            };
            if file_type.is_symlink() {
                continue;
            }
            let path = entry.path();
            if file_type.is_dir() {
                walk(&path, total, depth + 1)?;
            } else if let Ok(meta) = entry.metadata() {
                *total += meta.len();
            }
        }
        Ok(())
    }
    walk(p, &mut total, 0)?;
    Ok(total)
}

#[cfg(test)]
mod tests {
    use super::*;

    // ── detect_format ──────────────────────────────────────────────────────

    #[test]
    fn detect_format_7z() {
        assert_eq!(detect_format("archive.7z"), Some(ArchiveFormat::SevenZ));
    }

    #[test]
    fn detect_format_zip() {
        assert_eq!(detect_format("archive.zip"), Some(ArchiveFormat::Zip));
    }

    #[test]
    fn detect_format_tar() {
        assert_eq!(detect_format("archive.tar"), Some(ArchiveFormat::Tar));
    }

    #[test]
    fn detect_format_tar_gz() {
        assert_eq!(detect_format("archive.tar.gz"), Some(ArchiveFormat::TarGz));
        assert_eq!(detect_format("archive.tgz"), Some(ArchiveFormat::TarGz));
    }

    #[test]
    fn detect_format_tar_bz2() {
        assert_eq!(
            detect_format("archive.tar.bz2"),
            Some(ArchiveFormat::TarBz2)
        );
        assert_eq!(detect_format("archive.tbz2"), Some(ArchiveFormat::TarBz2));
    }

    #[test]
    fn detect_format_tar_xz() {
        assert_eq!(detect_format("archive.tar.xz"), Some(ArchiveFormat::TarXz));
        assert_eq!(detect_format("archive.txz"), Some(ArchiveFormat::TarXz));
    }

    #[test]
    fn detect_format_gz() {
        assert_eq!(detect_format("file.gz"), Some(ArchiveFormat::Gz));
    }

    #[test]
    fn detect_format_bz2() {
        assert_eq!(detect_format("file.bz2"), Some(ArchiveFormat::Bz2));
    }

    #[test]
    fn detect_format_xz() {
        assert_eq!(detect_format("file.xz"), Some(ArchiveFormat::Xz));
    }

    #[test]
    fn detect_format_rar() {
        assert_eq!(detect_format("archive.rar"), Some(ArchiveFormat::Rar));
    }

    #[test]
    fn detect_format_unknown() {
        assert_eq!(detect_format("file.txt"), None);
        assert_eq!(detect_format("file.pdf"), None);
        assert_eq!(detect_format("archive.abc"), None);
    }

    #[test]
    fn detect_format_case_insensitive() {
        assert_eq!(detect_format("archive.ZIP"), Some(ArchiveFormat::Zip));
        assert_eq!(detect_format("archive.7Z"), Some(ArchiveFormat::SevenZ));
        assert_eq!(detect_format("archive.Rar"), Some(ArchiveFormat::Rar));
    }

    #[test]
    fn detect_format_path_with_dirs() {
        assert_eq!(
            detect_format("/some/path/to/archive.zip"),
            Some(ArchiveFormat::Zip)
        );
        assert_eq!(
            detect_format("C:\\Users\\test\\file.7z"),
            Some(ArchiveFormat::SevenZ)
        );
    }

    // ── calculate_output_dir ───────────────────────────────────────────────

    #[test]
    fn calculate_output_dir_same_directory() {
        let result = calculate_output_dir(
            "/source/sub/archive.zip",
            "/output",
            "/source",
            &ExtractOutputMode::SameDirectory,
        );
        // 期望值用 Path 构造，避免硬编码分隔符导致跨平台（Windows）失败
        let expected = Path::new("/source/sub").to_string_lossy().to_string();
        assert_eq!(result, expected);
    }

    #[test]
    fn calculate_output_dir_flat_to_output() {
        let result = calculate_output_dir(
            "/source/sub/archive.zip",
            "/output",
            "/source",
            &ExtractOutputMode::FlatToOutput,
        );
        assert_eq!(result, "/output");
    }

    #[test]
    fn calculate_output_dir_by_archive_name() {
        let result = calculate_output_dir(
            "/source/archive.zip",
            "/output",
            "/source",
            &ExtractOutputMode::ByArchiveName,
        );
        let expected = Path::new("/output")
            .join("archive")
            .to_string_lossy()
            .to_string();
        assert_eq!(result, expected);
    }

    #[test]
    fn calculate_output_dir_preserve_structure() {
        let result = calculate_output_dir(
            "/source/sub/deep/archive.zip",
            "/output",
            "/source",
            &ExtractOutputMode::PreserveStructure,
        );
        let expected = Path::new("/output")
            .join("sub/deep")
            .to_string_lossy()
            .to_string();
        assert_eq!(result, expected);
    }

    #[test]
    fn calculate_output_dir_preserve_structure_top_level() {
        let result = calculate_output_dir(
            "/source/archive.zip",
            "/output",
            "/source",
            &ExtractOutputMode::PreserveStructure,
        );
        // 顶层压缩包相对父目录为空，输出即 base_output 本身（经 Path 规整）
        let expected = Path::new("/output")
            .join("")
            .to_string_lossy()
            .to_string();
        assert_eq!(result, expected);
    }

    // ── cancel flag ────────────────────────────────────────────────────────

    #[test]
    fn cancel_flag_reset_and_check() {
        reset_cancel();
        assert!(!is_cancelled());
        request_cancel();
        assert!(is_cancelled());
        reset_cancel();
        assert!(!is_cancelled());
    }
}

#[cfg(test)]
mod zip_tests {
    use super::*;
    use std::io::Write;

    /// zip_directory_to_tmp 的落盘名只带毫秒时间戳，同毫秒并发执行的两个打包
    /// 测试会互相覆盖同一个 /tmp/sw_upload_*.zip，因此所有调用点必须串行。
    static ZIP_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

    fn lock_zip_tmp() -> std::sync::MutexGuard<'static, ()> {
        ZIP_LOCK.lock().unwrap_or_else(|e| e.into_inner())
    }

    fn write_file(path: &Path, content: &str) {
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, content).unwrap();
    }

    fn zip_entry_names(zip_path: &str) -> Vec<String> {
        let file = File::open(zip_path).unwrap();
        let mut archive = zip::ZipArchive::new(file).unwrap();
        (0..archive.len())
            .map(|i| archive.by_index(i).unwrap().name().to_string())
            .collect()
    }

    #[test]
    fn zip_directory_skips_cache_and_preserves_structure() {
        let base = tmp_base("sw_zip_rt");
        let src = base.join("src/vol01");
        write_file(&src.join("001.jpg"), "one");
        write_file(&src.join("pages/002.jpg"), "two");
        // 本应用生成的邻近缩略图缓存，绝不能被搬去对端节点
        write_file(&src.join(".SlimeWorks/tmp/001.jpg_w320.jpg"), "cache");
        write_file(&src.join("pages/.SlimeWorks/tmp/002.jpg_w320.jpg"), "cache");
        write_file(&src.join(".DS_Store"), "junk");
        fs::create_dir_all(src.join("empty_dir")).unwrap();

        // 与其他打包测试串行，避免毫秒级时间戳重名互相覆盖
        let _guard = lock_zip_tmp();
        let zip_path = zip_directory_to_tmp(src.to_str().unwrap(), "vol01").unwrap();
        let names = zip_entry_names(&zip_path);
        assert!(names.contains(&"vol01/001.jpg".to_string()), "got: {names:?}");
        assert!(
            names.contains(&"vol01/pages/002.jpg".to_string()),
            "子目录层级必须保留, got: {names:?}"
        );
        assert!(
            names.iter().any(|n| n == "vol01/empty_dir/"),
            "空目录也要进包, got: {names:?}"
        );
        assert!(
            names.iter().all(|n| !n.contains(".SlimeWorks")),
            ".SlimeWorks 不得进包, got: {names:?}"
        );
        assert!(
            names.iter().all(|n| !n.ends_with(".DS_Store")),
            ".DS_Store 不得进包, got: {names:?}"
        );

        // 节点端拿到包后就是走这条路解压，回读一致才说明可以直接导入
        let out = base.join("out");
        extract_archive(&zip_path, out.to_str().unwrap(), None, &|_| {}).unwrap();
        assert_eq!(fs::read_to_string(out.join("vol01/001.jpg")).unwrap(), "one");
        assert_eq!(
            fs::read_to_string(out.join("vol01/pages/002.jpg")).unwrap(),
            "two"
        );
        assert!(out.join("vol01/empty_dir").is_dir());
        assert!(!out.join("vol01/.SlimeWorks").exists());

        let _ = fs::remove_file(&zip_path);
        let _ = fs::remove_dir_all(&base);
    }

    #[test]
    fn zip_directory_rejects_unsafe_arguments() {
        // `..` 段、空段、盘符会分别把条目写到目标目录之外或写出不合法条目名
        assert!(zip_directory_to_tmp("/tmp", "../escape").is_err());
        assert!(zip_directory_to_tmp("/tmp", "a/../b").is_err());
        assert!(zip_directory_to_tmp("/tmp", "a//b").is_err());
        assert!(zip_directory_to_tmp("/tmp", "  ").is_err());
        assert!(zip_directory_to_tmp("/nonexistent_sw_dir_xyz", "ok").is_err());
    }

    // ── entry_root 逐段校验（P1-1）────────────────────────────────────────

    #[test]
    fn entry_root_accepts_nested_root() {
        // 漫画推送恒传「漫画名/话名」两级路径，旧实现一律拒掉 → 每章必失败
        assert_eq!(validate_entry_root("漫画/第1话").unwrap(), "漫画/第1话");
        // 单段仍照常可用（其他调用方兼容）
        assert_eq!(validate_entry_root("vol01").unwrap(), "vol01");
        // 末尾斜杠只是目录收尾，剥掉后仍合法
        assert_eq!(validate_entry_root("漫画/第1话/").unwrap(), "漫画/第1话");
        assert_eq!(validate_entry_root("  漫画/第1话  ").unwrap(), "漫画/第1话");
    }

    #[test]
    fn entry_root_rejects_path_traversal_and_absolute() {
        assert!(validate_entry_root("../evil").is_err());
        assert!(validate_entry_root("漫画/../../evil").is_err());
        assert!(validate_entry_root("漫画/./第1话").is_err());
        // 前导斜杠 = 绝对路径，拆分出的首段为空，必须拒
        assert!(validate_entry_root("/abs").is_err());
        assert!(validate_entry_root("a//b").is_err());
        assert_eq!(validate_entry_root("a/").unwrap(), "a", "末尾斜杠剥掉后合法");
        // Windows 路径形态：反斜杠与盘符都不得出现在嵌套根系里
        assert!(validate_entry_root("C:\\x").is_err());
        assert!(validate_entry_root("a\\b").is_err());
        assert!(validate_entry_root("C:/x").is_err());
        assert!(validate_entry_root("").is_err());
        assert!(validate_entry_root("   ").is_err());
    }

    // ── 加密 zip（P1-2）───────────────────────────────────────────────────

    /// 造一个 AES-256 加密的 zip：extract_module 已启用 aes-crypto，
    /// 与用户实际拿到的压缩包走同一条解密路径。
    fn write_aes_zip(path: &Path, password: &str, entries: &[(&str, &str)]) {
        let file = File::create(path).unwrap();
        let mut writer = zip::ZipWriter::new(file);
        for (name, content) in entries {
            let options: zip::write::FileOptions<'_, ()> = zip::write::FileOptions::default()
                .compression_method(zip::CompressionMethod::Deflated)
                .with_aes_encryption(zip::AesMode::Aes256, password);
            writer.start_file(*name, options).unwrap();
            writer.write_all(content.as_bytes()).unwrap();
        }
        writer.finish().unwrap();
    }

    fn write_plain_zip(path: &Path, entries: &[(&str, &str)]) {
        let file = File::create(path).unwrap();
        let mut writer = zip::ZipWriter::new(file);
        for (name, content) in entries {
            let options: zip::write::FileOptions<'_, ()> =
                zip::write::FileOptions::default()
                    .compression_method(zip::CompressionMethod::Deflated);
            writer.start_file(*name, options).unwrap();
            writer.write_all(content.as_bytes()).unwrap();
        }
        writer.finish().unwrap();
    }

    /// 密码错误经 run_extract 汇总后，UI 拿到的 error_message 必须包含「密码」，
    /// 否则用户只会看到「1 个压缩包解压失败」而不知道要补/改密码。
    #[test]
    fn run_extract_surfaces_password_error_in_message() {
        let base = tmp_base("sw_run_pw");
        let src = base.join("src");
        fs::create_dir_all(&src).unwrap();
        let archive = src.join("secret.zip");
        write_aes_zip(&archive, "正确密码", &[("a.txt", "x")]);

        let config = ExtractConfig {
            source_dir: src.to_string_lossy().into_owned(),
            output_dir: base.join("out").to_string_lossy().into_owned(),
            output_mode: ExtractOutputMode::FlatToOutput,
            password: Some("错误密码".to_string()),
            parallel_count: 1,
            delete_after_extract: false,
        };
        let result = run_extract(&config, &|_| {});
        assert!(!result.success, "密码错必须整体失败");
        assert_eq!(result.failed_archives, vec!["secret.zip".to_string()]);
        let msg = result.error_message.unwrap_or_default();
        assert!(msg.contains("密码"), "汇总信息应带出密码问题, got: {msg}");
    }

    #[test]
    fn encrypted_zip_extracts_with_correct_password() {
        let base = tmp_base("sw_zip_pw_ok");
        let archive = base.join("secret.zip");
        write_aes_zip(&archive, "正确密码", &[("a.txt", "机密内容"), ("sub/b.txt", "第二层")]);

        let out = base.join("out");
        extract_archive(
            archive.to_str().unwrap(),
            out.to_str().unwrap(),
            Some("正确密码"),
            &|_| {},
        )
        .expect("正确密码应能解开加密 zip");

        assert_eq!(
            fs::read_to_string(out.join("a.txt")).unwrap(),
            "机密内容"
        );
        assert_eq!(
            fs::read_to_string(out.join("sub/b.txt")).unwrap(),
            "第二层"
        );
    }

    #[test]
    fn encrypted_zip_reports_password_error_for_wrong_password() {
        let base = tmp_base("sw_zip_pw_bad");
        let archive = base.join("secret.zip");
        write_aes_zip(&archive, "正确密码", &[("a.txt", "机密内容")]);

        let out = base.join("out_bad");
        let err = extract_archive(
            archive.to_str().unwrap(),
            out.to_str().unwrap(),
            Some("错误密码"),
            &|_| {},
        )
        .unwrap_err()
        .to_string();
        // 必须明确指向密码问题，不能报成「文件损坏」让用户反复重下
        assert!(err.contains("密码"), "错误密码应报密码问题, got: {err}");
        assert!(!err.contains("损坏"), "密码错不得报成损坏, got: {err}");
    }

    #[test]
    fn encrypted_zip_without_password_reports_need_password() {
        let base = tmp_base("sw_zip_pw_none");
        let archive = base.join("secret.zip");
        write_aes_zip(&archive, "正确密码", &[("a.txt", "机密内容")]);

        let out = base.join("out_none");
        let err = extract_archive(
            archive.to_str().unwrap(),
            out.to_str().unwrap(),
            None,
            &|_| {},
        )
        .unwrap_err()
        .to_string();
        assert!(err.contains("密码"), "缺密码应提示需要密码, got: {err}");
    }

    #[test]
    fn plain_zip_still_extracts_with_password_supplied() {
        // 用户给密码库留了密码、但压缩包其实没加密：不能因此失败
        let base = tmp_base("sw_zip_pw_unneeded");
        let archive = base.join("plain.zip");
        write_plain_zip(&archive, &[("c.txt", "明文")]);

        let out = base.join("out_plain");
        extract_archive(
            archive.to_str().unwrap(),
            out.to_str().unwrap(),
            Some("多余密码"),
            &|_| {},
        )
        .expect("未加密包不应因多给密码而失败");
        assert_eq!(fs::read_to_string(out.join("c.txt")).unwrap(), "明文");
    }

    /// P1-1 端到端：漫画章节推送恒传「漫画名/话名」两级根，
    /// 打包 → 节点端解压后必须还原成 目标目录/漫画名/话名/页图。
    #[test]
    fn zip_directory_accepts_nested_entry_root_end_to_end() {
        let base = tmp_base("sw_zip_nested");
        let src = base.join("src");
        write_file(&src.join("001.jpg"), "page-one");
        write_file(&src.join("002.jpg"), "page-two");

        let _guard = lock_zip_tmp();
        let zip_path =
            zip_directory_to_tmp(src.to_str().unwrap(), "漫画/第1话").expect("两级根必须允许");
        let names = zip_entry_names(&zip_path);
        assert!(
            names.contains(&"漫画/第1话/001.jpg".to_string()),
            "条目应带完整两级前缀, got: {names:?}"
        );

        // 节点端走同一条解压路径
        let out = base.join("out");
        extract_archive(&zip_path, out.to_str().unwrap(), None, &|_| {}).expect("解压失败");
        assert_eq!(
            fs::read_to_string(out.join("漫画/第1话/002.jpg")).unwrap(),
            "page-two"
        );

        let _ = fs::remove_file(&zip_path);
    }

    /// 端到端字节级往返：多文件目录 → 打包 → 解压 → 逐文件内容比对。
    /// 文本 + 二进制 + 深层嵌套目录都要覆盖，证明上传链路不丢任何字节。
    #[test]
    fn zip_extract_roundtrip_preserves_every_byte() {
        let base = tmp_base("sw_zip_rt2");
        let src = base.join("src");

        write_file(&src.join("note.txt"), "你好，SlimeWorks");
        // 二进制载荷：0x00~0xFF 全字节点，压缩/解压任何一处丢字节都会暴露
        let binary: Vec<u8> = (0u16..256).map(|i| i as u8).collect();
        fs::create_dir_all(src.join("sub/deep")).unwrap();
        fs::write(src.join("sub/data.bin"), &binary).unwrap();
        write_file(&src.join("sub/deep/deeper.txt"), "deep-content");

        // 与其他打包测试串行，避免毫秒级时间戳重名互相覆盖
        let _guard = lock_zip_tmp();
        let zip_path = zip_directory_to_tmp(src.to_str().unwrap(), "pkg").unwrap();
        // 走节点端同一条解压路径
        let out = base.join("out");
        extract_archive(&zip_path, out.to_str().unwrap(), None, &|_| {}).unwrap();

        assert_eq!(
            fs::read(out.join("pkg/note.txt")).unwrap(),
            "你好，SlimeWorks".as_bytes()
        );
        assert_eq!(fs::read(out.join("pkg/sub/data.bin")).unwrap(), binary);
        assert_eq!(
            fs::read(out.join("pkg/sub/deep/deeper.txt")).unwrap(),
            b"deep-content"
        );

        let _ = fs::remove_file(&zip_path);
        let _ = fs::remove_dir_all(&base);
    }
}

#[cfg(test)]
mod scan_size_tests {
    use super::*;

    fn touch(path: &Path, bytes: &[u8]) {
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, bytes).unwrap();
    }

    // ── scan_archives ──────────────────────────────────────────────────────

    #[test]
    fn scan_archives_finds_nested_archives_and_ignores_others() {
        let base = tmp_base("sw_scan");

        touch(&base.join("a.zip"), b"zip-bytes");
        // 深层嵌套目录里的压缩包必须被递归发现
        touch(&base.join("sub/b.tar.gz"), b"targz");
        touch(&base.join("sub/deep/c.7z"), b"7z7z");
        // 非压缩包文件一律忽略
        touch(&base.join("notes.txt"), b"txt");
        touch(&base.join("sub/photo.jpg"), b"jpg");
        touch(&base.join("archive-backup.rar"), b"rar");

        let found = scan_archives(base.to_str().unwrap()).unwrap();
        let names: Vec<&str> = found.iter().map(|a| a.file_name.as_str()).collect();
        // rar 虽在扫描名单内（后续解压不支持），这里只验证"发现"行为
        assert_eq!(names.len(), 4, "应发现 4 个压缩包（含嵌套目录）, got: {names:?}");
        assert!(names.contains(&"a.zip"), "got: {names:?}");
        assert!(names.contains(&"b.tar.gz"), "got: {names:?}");
        assert!(names.contains(&"c.7z"), "got: {names:?}");
        assert!(names.contains(&"archive-backup.rar"), "got: {names:?}");
        assert!(!names.contains(&"notes.txt"), "非压缩包不得混入: {names:?}");
        assert!(!names.contains(&"photo.jpg"), "非压缩包不得混入: {names:?}");

        // 嵌套目录的完整路径 + 文件大小必须如实上报
        let b = found.iter().find(|a| a.file_name == "b.tar.gz").unwrap();
        assert!(b.path.ends_with("sub/b.tar.gz"), "got: {}", b.path);
        assert_eq!(b.file_size, 5);

        // 结果按路径排序，保证 UI 展示稳定
        let mut sorted = found.iter().map(|a| a.path.clone()).collect::<Vec<_>>();
        sorted.sort();
        assert_eq!(found.iter().map(|a| a.path.clone()).collect::<Vec<_>>(), sorted);

        // 空目录返回空集合而不是报错
        let empty = base.join("empty_dir");
        fs::create_dir_all(&empty).unwrap();
        assert!(scan_archives(empty.to_str().unwrap()).unwrap().is_empty());

        // 目录不存在必须报错
        assert!(scan_archives("/nonexistent_sw_dir_xyz").is_err());

        let _ = fs::remove_dir_all(&base);
    }

    // ── get_dir_size ───────────────────────────────────────────────────────

    #[test]
    fn get_dir_size_sums_all_nested_files() {
        let base = tmp_base("sw_dsize");

        touch(&base.join("x.txt"), b"12345"); // 5 字节
        touch(&base.join("sub/y.bin"), &[0u8; 7]); // 7 字节
        touch(&base.join("sub/deep/z.dat"), b"0123456789"); // 10 字节

        assert_eq!(get_dir_size(base.to_str().unwrap()).unwrap(), 22);
    }

    /// 软链目录环：scan_archives / get_dir_size 曾用 path.is_dir() 无限递归 → 栈溢出。
    /// 这里造一个指回父目录的软链，两个函数都必须正常返回且不重复计入。
    #[cfg(unix)]
    #[test]
    fn recursive_scans_skip_symlink_loops() {
        let base = tmp_base("sw_symlink_loop");
        touch(&base.join("sub/a.zip"), b"zipdata");
        // sub/loop -> base：跟随软链就是无限环
        std::os::unix::fs::symlink(&base, base.join("sub/loop")).unwrap();

        let found = scan_archives(base.to_str().unwrap()).unwrap();
        assert_eq!(found.len(), 1, "软链环不得让扫描重复计数: {found:?}");
        // get_dir_size 同样只算真实文件
        assert_eq!(get_dir_size(base.to_str().unwrap()).unwrap(), 7);
        let _ = fs::remove_dir_all(&base);
    }

    /// copy_with_limit 的累计上限：超过 MAX_EXTRACTED_BYTES 必须报错而不是把磁盘写满。
    /// 用已过阈值的计数器模拟「前面已经写了很多」，验证这一笔就被拦下。
    #[test]
    fn copy_with_limit_stops_on_zip_bomb() {
        let mut src: &[u8] = b"0123456789";
        let mut out: Vec<u8> = Vec::new();
        // 计数已经贴着上限：任何一笔写入都应立刻中止
        let mut total = MAX_EXTRACTED_BYTES;
        let err = copy_with_limit(&mut src, &mut out, &mut total).unwrap_err();
        assert!(err.to_string().contains("压缩炸弹"), "err={err}");
        // 未超限时正常写完并累计
        let mut src2: &[u8] = b"0123456789";
        let mut out2: Vec<u8> = Vec::new();
        let mut total2 = 0u64;
        copy_with_limit(&mut src2, &mut out2, &mut total2).unwrap();
        assert_eq!(out2.len(), 10);
        assert_eq!(total2, 10);
    }

    #[test]
    fn get_dir_size_empty_dir_and_missing_path() {
        let base = tmp_base("sw_dsize_empty");
        // 空目录大小为 0
        assert_eq!(get_dir_size(base.to_str().unwrap()).unwrap(), 0);
        // 不存在的路径按 0 处理（调用方用它做展示，不应因缺目录而失败）
        assert_eq!(get_dir_size("/nonexistent_sw_dir_xyz").unwrap(), 0);
        let _ = fs::remove_dir_all(&base);
    }

    // ── extract_archive 补充路径 ───────────────────────────────────────────

    #[test]
    fn extract_archive_rejects_unknown_format_and_rar() {
        // 无法识别的扩展名必须报错，而不是静默产出空目录
        let result = extract_archive("/tmp/whatever.txt", "/tmp", None, &|_| {});
        assert!(result.is_err());
        // RAR 走的是明确的不支持分支
        let rar = extract_archive("/tmp/archive.rar", "/tmp", None, &|_| {});
        assert!(rar.is_err());
        assert!(rar.unwrap_err().to_string().contains("RAR"));
    }

    #[test]
    fn extract_archive_tar_gz_roundtrip() {
        // tar.gz 走 extract_tar_gz 分支：手工构造压缩包再解压比对
        let base = tmp_base("sw_targz");
        let src = base.join("src");
        touch(&src.join("hello.txt"), b"tar-gz-payload");
        touch(&src.join("sub/nested.txt"), b"nested-bytes");

        let archive = base.join("pack.tar.gz");
        {
            let file = File::create(&archive).unwrap();
            let gz = flate2::write::GzEncoder::new(
                file,
                flate2::Compression::default(),
            );
            let mut builder = tar::Builder::new(gz);
            builder.append_dir_all("", &src).unwrap();
            let gz = builder.into_inner().unwrap();
            gz.finish().unwrap();
        }

        let out = base.join("out");
        extract_archive(archive.to_str().unwrap(), out.to_str().unwrap(), None, &|pct| {
            // 成功路径必须以 1.0 收尾
            assert_eq!(pct, 1.0);
        })
        .unwrap();
        assert_eq!(fs::read(out.join("hello.txt")).unwrap(), b"tar-gz-payload");
        assert_eq!(fs::read(out.join("sub/nested.txt")).unwrap(), b"nested-bytes");

        let _ = fs::remove_dir_all(&base);
    }
}

/// 测试公共：TMPDIR 下固定名用例目录守卫。
/// 创建前清旧、用例结束（含 panic unwind）随 Drop 整树删除，实现「写入后删除、跑完归零」
#[cfg(test)]
mod tmp_guard {
    use std::path::PathBuf;

    pub struct TmpBase(pub PathBuf);

    impl std::ops::Deref for TmpBase {
        type Target = PathBuf;
        fn deref(&self) -> &PathBuf {
            &self.0
        }
    }
    impl AsRef<std::path::Path> for TmpBase {
        fn as_ref(&self) -> &std::path::Path {
            &self.0
        }
    }
    impl Drop for TmpBase {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

}

/// 便捷入口：在系统临时目录创建（先清旧）固定名用例目录，结束自动删除
#[cfg(test)]
pub(crate) fn tmp_base(name: &str) -> tmp_guard::TmpBase {
    assert!(
        !name.contains(std::path::MAIN_SEPARATOR),
        "用例目录名必须是不含路径分隔符的单段名"
    );
    let dir = std::env::temp_dir().join(name);
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("创建用例临时目录失败");
    tmp_guard::TmpBase(dir)
}
