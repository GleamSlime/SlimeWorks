use slime_logger::{sw_info, sw_warn, sw_error, sw_debug};
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
        assert_eq!(result, "/source/sub");
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
        assert_eq!(result, "/output/archive");
    }

    #[test]
    fn calculate_output_dir_preserve_structure() {
        let result = calculate_output_dir(
            "/source/sub/deep/archive.zip",
            "/output",
            "/source",
            &ExtractOutputMode::PreserveStructure,
        );
        assert_eq!(result, "/output/sub/deep");
    }

    #[test]
    fn calculate_output_dir_preserve_structure_top_level() {
        let result = calculate_output_dir(
            "/source/archive.zip",
            "/output",
            "/source",
            &ExtractOutputMode::PreserveStructure,
        );
        assert_eq!(result, "/output/");
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
