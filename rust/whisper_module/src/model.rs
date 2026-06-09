use std::path::PathBuf;
use std::sync::OnceLock;

use crate::types::WhisperModelPreset;

/// 模型存储根目录
static MODEL_DIR: OnceLock<PathBuf> = OnceLock::new();

fn model_dir() -> &'static PathBuf {
    MODEL_DIR.get_or_init(|| {
        let base = std::env::var("APPDATA")
            .unwrap_or_else(|_| ".".to_string());
        let dir = PathBuf::from(base)
            .join("SlimeWorks")
            .join("whisper_models");
        let _ = std::fs::create_dir_all(&dir);
        dir
    })
}

/// 获取模型文件路径
pub fn get_model_path(preset: WhisperModelPreset) -> PathBuf {
    model_dir().join(preset.model_filename())
}

/// 检查模型文件是否存在
pub fn is_model_downloaded(preset: WhisperModelPreset) -> bool {
    get_model_path(preset).exists()
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

    slime_logger::sw_info!("[whisper] 开始下载模型: {} -> {:?}", url, dest);

    let mut response = reqwest::blocking::Client::new()
        .get(&url)
        .send()
        .map_err(|e| format!("下载请求失败: {}", e))?;

    if !response.status().is_success() {
        return Err(format!("下载失败，HTTP 状态: {}", response.status()));
    }

    let mut file = std::fs::File::create(&dest)
        .map_err(|e| format!("创建文件失败: {}", e))?;

    let mut total_bytes: u64 = 0;
    let mut buffer = [0u8; 8192];
    loop {
        use std::io::{Read, Write};
        let n = response.read(&mut buffer)
            .map_err(|e| format!("读取数据失败: {}", e))?;
        if n == 0 { break; }
        file.write_all(&buffer[..n])
            .map_err(|e| format!("写入文件失败: {}", e))?;
        total_bytes += n as u64;
    }

    slime_logger::sw_info!("[whisper] 模型下载完成: {} 字节", total_bytes);
    Ok(total_bytes)
}

/// 删除模型文件
pub fn delete_model(preset: WhisperModelPreset) -> Result<bool, String> {
    let path = get_model_path(preset);
    if path.exists() {
        std::fs::remove_file(&path)
            .map_err(|e| format!("删除模型失败: {}", e))?;
        slime_logger::sw_info!("[whisper] 模型已删除: {:?}", path);
        Ok(true)
    } else {
        Ok(false)
    }
}
