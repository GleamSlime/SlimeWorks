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

fn extract_zip(archive_path: &str, output_dir: &str, _password: Option<&str>) -> Result<()> {
    let output = Path::new(output_dir);
    fs::create_dir_all(output)?;

    let file =
        File::open(archive_path).with_context(|| format!("无法打开 zip 文件: {}", archive_path))?;
    let mut archive = zip::ZipArchive::new(BufReader::new(file))
        .with_context(|| format!("无法读取 zip 文件: {}", archive_path))?;

    for i in 0..archive.len() {
        if is_cancelled() {
            anyhow::bail!("用户取消");
        }
        let mut entry = archive
            .by_index(i)
            .with_context(|| format!("无法读取 zip 条目 #{}", i))?;
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
            std::io::copy(&mut entry, &mut outfile)?;
        }
    }
    Ok(())
}

fn extract_tar(archive_path: &str, output_dir: &str) -> Result<()> {
    let output = Path::new(output_dir);
    fs::create_dir_all(output)?;

    let file =
        File::open(archive_path).with_context(|| format!("无法打开 tar 文件: {}", archive_path))?;
    let mut archive = tar::Archive::new(file);
    archive
        .unpack(output)
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
    archive
        .unpack(output)
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
    archive
        .unpack(output)
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
    archive
        .unpack(output)
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
    std::io::copy(&mut gz, &mut outfile)?;
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
    std::io::copy(&mut bz2, &mut outfile)?;
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
    std::io::copy(&mut xz, &mut outfile)?;
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
    if !current.exists() {
        return Ok(());
    }
    for entry in std::fs::read_dir(current)? {
        let entry = entry?;
        let path = entry.path();
        if path.is_dir() {
            scan_archives_recursive(base, &path, extensions, results)?;
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
            let metadata = std::fs::metadata(&path).unwrap_or_else(|_| {
                std::fs::symlink_metadata(&path)
                    .unwrap_or_else(|_| panic!("无法获取文件元数据: {}", path.display()))
            });
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
            Some(format!("{} 个压缩包解压失败", failed_count))
        } else {
            None
        },
    }
}

/// 把 `src_dir` 整棵目录树打包成 zip 写入系统临时目录，返回 zip 的绝对路径。
///
/// 压缩包内所有条目都以 `entry_root` 为顶层目录名，节点端把包解压到目标目录下即可
/// 原样还原层级。刻意跳过 `.SlimeWorks`（本应用生成的邻近缩略图缓存）与 `.DS_Store`：
/// 把派生缓存搬给对方节点既白占带宽，又可能让对端把缓存文件当资源导入。
pub fn zip_directory_to_tmp(src_dir: &str, entry_root: &str) -> Result<String> {
    let root = Path::new(src_dir);
    anyhow::ensure!(root.is_dir(), "源目录不存在或不是目录: {}", src_dir);
    let entry_root = entry_root.trim().trim_matches('/');
    anyhow::ensure!(
        !entry_root.is_empty() && !entry_root.contains('/') && entry_root != "..",
        "压缩包顶层目录名不合法: {}",
        entry_root
    );

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
        if path.is_dir() {
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
    fn walk(dir: &Path, total: &mut u64) -> Result<()> {
        for entry in std::fs::read_dir(dir)? {
            let entry = entry?;
            let path = entry.path();
            if path.is_dir() {
                walk(&path, total)?;
            } else {
                let meta = entry.metadata()?;
                *total += meta.len();
            }
        }
        Ok(())
    }
    walk(p, &mut total)?;
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
        // 顶层名带斜杠或 .. 会把条目写到目标目录之外，必须在打包前就拒掉
        assert!(zip_directory_to_tmp("/tmp", "../escape").is_err());
        assert!(zip_directory_to_tmp("/tmp", "a/b").is_err());
        assert!(zip_directory_to_tmp("/tmp", "  ").is_err());
        assert!(zip_directory_to_tmp("/nonexistent_sw_dir_xyz", "ok").is_err());
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
