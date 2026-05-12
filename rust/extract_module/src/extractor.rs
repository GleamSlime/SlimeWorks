use std::io::{BufRead, BufReader, Read};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Instant;

use anyhow::{Context, Result};
use log::{error, info};

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

fn find_7z_binary() -> Result<String> {
    if cfg!(target_os = "windows") {
        let candidates = [
            r"C:\Program Files\7-Zip\7z.exe",
            r"C:\Program Files (x86)\7-Zip\7z.exe",
        ];
        for c in &candidates {
            if Path::new(c).exists() {
                return Ok(c.to_string());
            }
        }
        let output = Command::new("where").arg("7z.exe").output();
        if let Ok(out) = output {
            if out.status.success() {
                let s = String::from_utf8_lossy(&out.stdout);
                let line = s.lines().next().unwrap_or("").trim();
                if !line.is_empty() {
                    return Ok(line.to_string());
                }
            }
        }
        anyhow::bail!("未找到 7z，请安装 7-Zip: https://7-zip.org/");
    } else {
        for cmd in &["7z", "7zz"] {
            let output = Command::new("which").arg(cmd).output();
            if let Ok(out) = output {
                if out.status.success() {
                    let s = String::from_utf8_lossy(&out.stdout);
                    let line = s.lines().next().unwrap_or("").trim();
                    if !line.is_empty() {
                        return Ok(line.to_string());
                    }
                }
            }
        }
        anyhow::bail!("未找到 7z，请安装：brew install sevenzip");
    }
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
    let binary = find_7z_binary()?;
    let output = Path::new(output_dir);
    std::fs::create_dir_all(output)?;

    let mut cmd = Command::new(&binary);
    cmd.arg("x")
        .arg("-y")
        .arg("-bsp1")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());

    if let Some(pw) = password {
        if !pw.is_empty() {
            cmd.arg(format!("-p{}", pw));
        }
    } else {
        cmd.arg("-p");
    }

    cmd.arg(format!("-o{}", output_dir));
    cmd.arg("--").arg(archive_path);

    let mut child = cmd.spawn()?;
    let stdout = child.stdout.take();
    if let Some(stdout) = stdout {
        let reader = BufReader::new(stdout);
        for line in reader.lines() {
            if is_cancelled() {
                let _ = child.kill();
                anyhow::bail!("用户取消");
            }
            if let Ok(line) = line {
                if let Some(pct) = parse_7z_progress(&line) {
                    progress_callback(pct);
                }
            }
        }
    }

    let status = child.wait()?;
    if !status.success() {
        let stderr_output = if let Some(mut stderr) = child.stderr.take() {
            let mut buf = String::new();
            let _ = stderr.read_to_string(&mut buf);
            buf
        } else {
            String::new()
        };
        anyhow::bail!(
            "解压失败: {} | stderr: {}",
            archive_path,
            stderr_output.trim()
        );
    }
    Ok(())
}

fn parse_7z_progress(line: &str) -> Option<f64> {
    let trimmed = line.trim();
    if trimmed.ends_with('%') {
        let pct_str = trimmed.trim_end_matches('%');
        let pct: f64 = pct_str.parse().ok()?;
        if (0.0..=100.0).contains(&pct) {
            return Some(pct / 100.0);
        }
    }
    None
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

    info!(
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
            info!("解压已取消");
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
                info!("解压成功: {}", archive.file_name);
            }
            Err(e) => {
                error!("解压失败: {} - {}", archive.file_name, e);
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
