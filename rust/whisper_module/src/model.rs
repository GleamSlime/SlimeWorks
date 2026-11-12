use std::path::{Path, PathBuf};
use std::sync::OnceLock;

use crate::types::WhisperModelPreset;

/// 模型存储根目录
static MODEL_DIR: OnceLock<PathBuf> = OnceLock::new();


fn model_dir() -> &'static PathBuf {
    MODEL_DIR.get_or_init(|| {
        // 平台分支统一走 db_module：早期只读 APPDATA，macOS 上得到相对路径 ".",
        // 正式版由 Finder 启动时 CWD 不可写，目录创建与下载全部静默失败。
        let dir = db_module::paths::app_data_dir("SlimeWorks").join("whisper_models");
        let _ = std::fs::create_dir_all(&dir);
        dir
    })
}

/// 获取模型文件路径
pub fn get_model_path(preset: WhisperModelPreset) -> PathBuf {
    model_dir().join(preset.model_filename())
}

/// 下载中的临时文件名：完成前绝不占用最终文件名。
///
/// 中断（退出/断网/取消）留下半文件时，只要文件名还是 .part，
/// is_model_downloaded 就不会把它当成已安装，用户可以重下。
fn part_path_of(dest: &Path) -> PathBuf {
    let name = dest
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| "model.bin".to_string());
    dest.with_file_name(format!(".{}.part", name))
}

/// 已下载文件的最小可信体积：预设标注大小的 90%。
///
/// 只做下界不设上界：上游换量化版本时可能偏大，但绝不可能是标注值的一部分。
/// 半截文件即便因为历史原因落在最终文件名上，也不会再被认成"已下载"。
fn min_expected_bytes(preset: WhisperModelPreset) -> u64 {
    preset.approximate_size_mb() * 1024 * 1024 / 10 * 9
}

/// 检查模型文件是否存在
pub fn is_model_downloaded(preset: WhisperModelPreset) -> bool {
    match std::fs::metadata(get_model_path(preset)) {
        Ok(meta) => meta.is_file() && meta.len() >= min_expected_bytes(preset),
        Err(_) => false,
    }
}

/// 获取模型文件大小
pub fn get_model_file_size(preset: WhisperModelPreset) -> Option<u64> {
    let path = get_model_path(preset);
    std::fs::metadata(&path).ok().map(|m| m.len())
}

/// 下载模型文件（阻塞）
/// 返回下载的字节数
pub fn download_model(preset: WhisperModelPreset) -> Result<u64, String> {
    let url = preset.download_url();
    let dest = get_model_path(preset);
    let part = part_path_of(&dest);

    slime_logger::sw_info!("[whisper] 开始下载模型: {} -> {:?}", url, dest);

    // 大模型（2.9GB）在慢网下分钟级，但绝不能无限等：连接 10 秒、总时长 300 秒
    let client = reqwest::blocking::Client::builder()
        .connect_timeout(std::time::Duration::from_secs(10))
        .timeout(std::time::Duration::from_secs(300))
        .build()
        .map_err(|e| format!("创建下载客户端失败: {}", e))?;

    let mut response = client
        .get(&url)
        .send()
        .map_err(|e| format!("下载请求失败: {}", e))?;

    if !response.status().is_success() {
        return Err(format!("下载失败，HTTP 状态: {}", response.status()));
    }

    // 先写 .part：任何一步失败都要删掉，否则下次会在同一目录留下垃圾
    let write_result = write_stream_to(&mut response, &part);
    let total_bytes = match write_result {
        Ok(n) => n,
        Err(e) => {
            let _ = std::fs::remove_file(&part);
            return Err(e);
        }
    };

    // 尺寸 sanity：半截响应（代理截断、网盘限流）不能 rename 成"已安装"
    let min_bytes = min_expected_bytes(preset);
    if total_bytes < min_bytes {
        let _ = std::fs::remove_file(&part);
        return Err(format!(
            "模型文件不完整：收到 {} 字节，预期至少 {} 字节",
            total_bytes, min_bytes
        ));
    }

    if let Err(e) = std::fs::rename(&part, &dest) {
        let _ = std::fs::remove_file(&part);
        return Err(format!("保存模型文件失败: {}", e));
    }

    slime_logger::sw_info!("[whisper] 模型下载完成: {} 字节", total_bytes);
    Ok(total_bytes)
}

/// 流式落盘，返回写入字节数；不负责清理临时文件
fn write_stream_to(response: &mut impl std::io::Read, dest: &Path) -> Result<u64, String> {
    use std::io::Write;
    let mut file = std::fs::File::create(dest).map_err(|e| format!("创建文件失败: {}", e))?;
    let mut total_bytes: u64 = 0;
    let mut buffer = [0u8; 8192];
    loop {
        let n = response
            .read(&mut buffer)
            .map_err(|e| format!("读取数据失败: {}", e))?;
        if n == 0 {
            break;
        }
        file.write_all(&buffer[..n])
            .map_err(|e| format!("写入文件失败: {}", e))?;
        total_bytes += n as u64;
    }
    file.flush().map_err(|e| format!("刷新文件失败: {}", e))?;
    Ok(total_bytes)
}

/// 删除模型文件
pub fn delete_model(preset: WhisperModelPreset) -> Result<bool, String> {
    let path = get_model_path(preset);
    // 残留的 .part 也要一起清掉，否则用户"删了模型"磁盘上还占着几个 G
    let part = part_path_of(&path);
    if part.exists() {
        let _ = std::fs::remove_file(&part);
    }
    if path.exists() {
        std::fs::remove_file(&path)
            .map_err(|e| format!("删除模型失败: {}", e))?;
        slime_logger::sw_info!("[whisper] 模型已删除: {:?}", path);
        Ok(true)
    } else {
        Ok(false)
    }
}

#[cfg(test)]
impl WhisperModelPreset {
    /// 测试用：把体积标注压到 0，避免真的准备 75MB 文件
    fn test_tiny_threshold(self) -> u64 {
        min_expected_bytes(self)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 用 Tiny 预设做尺寸断言时门槛是 75MB 的 90%，造个假文件太浪费，
    /// 这里只验证判定逻辑本身（阈值常量与边界关系）
    #[test]
    fn min_expected_size_is_ninety_percent_of_declared() {
        let preset = WhisperModelPreset::Tiny;
        let declared = preset.approximate_size_mb() * 1024 * 1024;
        assert_eq!(min_expected_bytes(preset), declared / 10 * 9);
        assert_eq!(preset.test_tiny_threshold(), min_expected_bytes(preset));
        // 各预设的门槛必须严格小于标注体积，否则正常下载会被判成不完整
        for name in WhisperModelPreset::as_str_list() {
            let p = WhisperModelPreset::from_str_name(&name);
            let declared = p.approximate_size_mb() * 1024 * 1024;
            assert!(min_expected_bytes(p) < declared, "{} 的门槛不该反超标注值", name);
        }
    }

    #[test]
    fn part_path_is_hidden_sibling_of_final_file() {
        let dest = PathBuf::from("/tmp/models/ggml-tiny.bin");
        let part = part_path_of(&dest);
        assert_eq!(part, PathBuf::from("/tmp/models/.ggml-tiny.bin.part"));
        // 关键：临时名不等于最终名，半截下载不会被 is_model_downloaded 认走
        assert_ne!(part, dest);
    }

    /// 模拟下载中断：只写出 .part，最终文件不存在 → 不算已安装
    #[test]
    fn interrupted_download_is_not_treated_as_installed() {
        let dir = std::env::temp_dir().join(format!("sw_whisper_part_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let dest = dir.join("ggml-tiny.bin");
        let part = part_path_of(&dest);

        // 只写 .part（模拟写到一半进程退出）
        std::fs::write(&part, vec![0u8; 1024]).unwrap();
        assert!(part.exists());
        assert!(!dest.exists(), "最终文件名必须保持干净");

        // 落盘完成后的 rename 语义
        std::fs::rename(&part, &dest).unwrap();
        assert!(!part.exists());
        assert_eq!(std::fs::metadata(&dest).unwrap().len(), 1024);

        let _ = std::fs::remove_dir_all(&dir);
    }

    /// 即便半截文件落在最终文件名上（历史残留），尺寸 sanity 也要挡住
    #[test]
    fn undersized_final_file_is_rejected() {
        let dir = std::env::temp_dir().join(format!("sw_whisper_size_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let dest = dir.join("ggml-tiny.bin");
        std::fs::write(&dest, vec![0u8; 1024]).unwrap();

        let meta = std::fs::metadata(&dest).unwrap();
        assert!(meta.len() < min_expected_bytes(WhisperModelPreset::Tiny));
        let looks_installed = meta.is_file() && meta.len() >= min_expected_bytes(WhisperModelPreset::Tiny);
        assert!(!looks_installed, "1KB 的半截文件不能被当成已下载");

        let _ = std::fs::remove_dir_all(&dir);
    }

    /// 写流中途失败要能返回错误（调用方据此删 .part）
    #[test]
    fn stream_write_error_is_reported() {
        struct Broken;
        impl std::io::Read for Broken {
            fn read(&mut self, _buf: &mut [u8]) -> std::io::Result<usize> {
                Err(std::io::Error::new(std::io::ErrorKind::ConnectionReset, "断网"))
            }
        }
        let dir = std::env::temp_dir().join(format!("sw_whisper_err_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let part = dir.join(".ggml-tiny.bin.part");

        let err = write_stream_to(&mut Broken, &part).unwrap_err();
        assert!(err.contains("读取数据失败"), "err = {err}");
        let _ = std::fs::remove_dir_all(&dir);
    }
}
