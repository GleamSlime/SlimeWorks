use aes::cipher::{BlockDecrypt, KeyInit};
use aes::Aes128;
use anyhow::{bail, Context, Result};
use base64::Engine;
use slime_logger::{sw_info, sw_warn};
use std::io::Read;
use std::path::Path;
use walkdir::WalkDir;

use crate::types::*;

// NCM 文件魔数 CTENFDAM
const NCM_MAGIC: [u8; 8] = [0x43, 0x54, 0x45, 0x4E, 0x46, 0x44, 0x41, 0x4D];

// 核心密钥（网易云音乐客户端内置）
const CORE_KEY: [u8; 16] = [
    0x68, 0x7A, 0x48, 0x52, 0x41, 0x6D, 0x73, 0x6F,
    0x35, 0x6B, 0x49, 0x6E, 0x62, 0x61, 0x78, 0x57,
];

// 元数据密钥
const META_KEY: [u8; 16] = [
    0x23, 0x31, 0x34, 0x6C, 0x6A, 0x6B, 0x5F, 0x21,
    0x5C, 0x5D, 0x26, 0x30, 0x55, 0x3C, 0x27, 0x28,
];

/// 扫描目录下所有 NCM 文件
pub fn scan_ncm_files(dir: &str) -> Result<Vec<NcmFileInfo>> {
    let path = Path::new(dir);
    if !path.exists() || !path.is_dir() {
        bail!("目录不存在或不是有效目录: {}", dir);
    }

    sw_info!("[ncm_decrypt] 开始扫描 NCM 文件: {}", dir);
    let mut files = Vec::new();

    for entry in WalkDir::new(path).into_iter().filter_map(|e| e.ok()) {
        if !entry.file_type().is_file() {
            continue;
        }
        let file_path = entry.path();
        let ext = file_path
            .extension()
            .and_then(|e| e.to_str())
            .map(|e| e.to_ascii_lowercase());
        if ext.as_deref() != Some("ncm") {
            continue;
        }

        let metadata = match std::fs::metadata(file_path) {
            Ok(m) => m,
            Err(e) => {
                sw_warn!("[ncm_decrypt] 无法读取文件元数据: {:?}, err={}", file_path, e);
                continue;
            }
        };

        files.push(NcmFileInfo {
            path: file_path.to_string_lossy().into_owned(),
            file_name: file_path
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("未知")
                .to_string(),
            file_size: metadata.len(),
        });
    }

    sw_info!("[ncm_decrypt] 扫描完成，共发现 {} 个 NCM 文件", files.len());
    Ok(files)
}

/// 解密单个 NCM 文件，返回解密后的音频数据和元数据
pub fn decrypt_ncm_file(file_path: &str) -> Result<NcmDecryptedData> {
    let mut file = std::fs::File::open(file_path)
        .with_context(|| format!("无法打开文件: {}", file_path))?;
    let mut data = Vec::new();
    file.read_to_end(&mut data)
        .with_context(|| format!("无法读取文件: {}", file_path))?;

    let file_size = data.len();
    if file_size < 16 {
        bail!("文件太小，不是有效的 NCM 文件: {}", file_path);
    }

    // 验证魔数 CTENFDAM
    if data[..8] != NCM_MAGIC {
        bail!("文件头不匹配，不是有效的 NCM 文件: {}", file_path);
    }

    let mut offset = 10usize; // 8 字节魔数 + 2 字节间隔

    // ===== 读取并解密 Key =====
    let key_len = read_u32_le(&data, &mut offset)?;
    if key_len == 0 || offset + key_len as usize > file_size {
        bail!("Key 数据异常 (key_len={}, offset={}, file_size={}): {}", key_len, offset, file_size, file_path);
    }
    let key_data = &data[offset..offset + key_len as usize];
    offset += key_len as usize;

    let decrypted_key = decrypt_key(key_data)?;

    // ===== 读取并解密元数据 =====
    let meta_len = read_u32_le(&data, &mut offset)?;
    let metadata_json = if meta_len > 0 && offset + meta_len as usize <= file_size {
        let meta_data = &data[offset..offset + meta_len as usize];
        offset += meta_len as usize;
        match decrypt_metadata(meta_data) {
            Ok(json) => Some(json),
            Err(e) => {
                sw_warn!("[ncm_decrypt] 元数据解密失败（不影响音频解密）: {}", e);
                None
            }
        }
    } else {
        if meta_len > 0 {
            sw_warn!("[ncm_decrypt] meta_len={} 超出范围，跳过元数据", meta_len);
        }
        offset = offset.saturating_add(meta_len as usize).min(file_size);
        None
    };

    // ===== 跳过 CRC (5 字节) =====
    if offset + 5 > file_size {
        bail!("CRC 数据超出文件范围: {}", file_path);
    }
    offset += 5;

    // ===== 读取专辑封面 =====
    // image_space (4 字节) + image_size (4 字节)
    let image_space = read_u32_le(&data, &mut offset)?;
    let image_size = read_u32_le(&data, &mut offset)?;
    let cover_data = if image_size > 0 && offset + image_size as usize <= file_size {
        let cover = data[offset..offset + image_size as usize].to_vec();
        offset += image_size as usize;
        Some(cover)
    } else {
        offset = offset.saturating_add(image_size as usize).min(file_size);
        None
    };

    // 跳过 image_space 和 image_size 之间的间隔
    let gap = image_space as usize - image_size as usize;
    if gap > 0 && offset + gap <= file_size {
        offset += gap;
    }

    // ===== 解密音频数据 =====
    if offset >= file_size {
        bail!("无音频数据: {}", file_path);
    }

    let audio_data = decrypt_audio(&data[offset..], &decrypted_key);

    // 从元数据中提取信息
    let (format, title, artist, album) = if let Some(ref meta) = metadata_json {
        parse_metadata(meta)
    } else {
        let fmt = detect_audio_format(&audio_data);
        (fmt, None, None, None)
    };

    Ok(NcmDecryptedData {
        audio_data,
        format,
        title,
        artist,
        album,
        cover_data,
        metadata_json,
    })
}

/// 解密后的数据
pub struct NcmDecryptedData {
    pub audio_data: Vec<u8>,
    pub format: String,
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub cover_data: Option<Vec<u8>>,
    pub metadata_json: Option<String>,
}

/// 读取小端 u32
fn read_u32_le(data: &[u8], offset: &mut usize) -> Result<u32> {
    if *offset + 4 > data.len() {
        bail!("数据不足，无法读取 u32 (offset={}, len={})", *offset, data.len());
    }
    let val = u32::from_le_bytes([data[*offset], data[*offset + 1], data[*offset + 2], data[*offset + 3]]);
    *offset += 4;
    Ok(val)
}

/// AES-128-ECB 解密（手动分块）
fn aes_ecb_decrypt(key: &[u8; 16], data: &[u8]) -> Vec<u8> {
    let cipher = Aes128::new_from_slice(key).expect("AES key 长度错误");
    let mut result = Vec::with_capacity(data.len());
    for chunk in data.chunks(16) {
        if chunk.len() < 16 {
            break;
        }
        let mut block = [0u8; 16];
        block.copy_from_slice(chunk);
        cipher.decrypt_block((&mut block).into());
        result.extend_from_slice(&block);
    }
    result
}

/// 去除 PKCS7 填充，返回有效数据
fn unpad_pkcs7(data: Vec<u8>) -> Vec<u8> {
    if data.is_empty() {
        return data;
    }
    let last = data[data.len() - 1];
    if last >= 1 && last <= 16 {
        let padding_start = data.len() - last as usize;
        if data[padding_start..].iter().all(|&b| b == last) {
            return data[..padding_start].to_vec();
        }
    }
    data
}

/// 解密核心密钥
fn decrypt_key(key_data: &[u8]) -> Result<Vec<u8>> {
    let xored: Vec<u8> = key_data.iter().map(|b| b ^ 0x64).collect();
    let decrypted = aes_ecb_decrypt(&CORE_KEY, &xored);
    let decrypted = unpad_pkcs7(decrypted);

    if decrypted.len() < 17 || &decrypted[..17] != b"neteasecloudmusic" {
        bail!("Key 前缀不匹配");
    }

    let key = decrypted[17..].to_vec();
    sw_info!("[ncm_decrypt] 解密得到 key 长度: {} 字节", key.len());
    Ok(key)
}

/// 解密元数据
fn decrypt_metadata(meta_data: &[u8]) -> Result<String> {
    let xored: Vec<u8> = meta_data.iter().map(|b| b ^ 0x63).collect();

    if xored.len() < 22 {
        bail!("元数据太短: {} 字节", xored.len());
    }
    let base64_data = &xored[22..];

    let decoded = base64::engine::general_purpose::STANDARD
        .decode(base64_data)
        .map_err(|e| anyhow::anyhow!("Base64 解码失败: {}", e))?;

    let decrypted = aes_ecb_decrypt(&META_KEY, &decoded);
    let decrypted = unpad_pkcs7(decrypted);

    if decrypted.len() < 6 {
        bail!("解密后的元数据太短: {} 字节", decrypted.len());
    }

    let json_str = String::from_utf8_lossy(&decrypted[6..]).to_string();
    Ok(json_str)
}

/// 构建 RC4 流密钥（与 Python ncmdump 完全一致）
///
/// Python: stream = [S[(S[i] + S[(i + S[i]) & 0xFF]) & 0xFF] for i in range(256)]
/// 然后: stream = bytes(bytearray(stream * (len(data) // 256 + 1))[1:1 + len(data)])
fn decrypt_audio(data: &[u8], key: &[u8]) -> Vec<u8> {
    let key_len = key.len();

    // RC4 KSA (Key-scheduling algorithm)
    let mut s = [0u8; 256];
    for i in 0..256 {
        s[i] = i as u8;
    }
    let mut j: u8 = 0;
    for i in 0..256 {
        j = j.wrapping_add(s[i]).wrapping_add(key[i % key_len]);
        s.swap(i, j as usize);
    }

    // Modified RC4 PRGA - 生成 256 字节的流密钥
    let mut stream_256 = [0u8; 256];
    for i in 0..256 {
        let si = s[i] as usize;
        let idx = (i + si) & 0xFF;
        stream_256[i] = s[(si + s[idx] as usize) & 0xFF];
    }

    // 重复 stream_256 以覆盖整个数据，从索引 1 开始（与 Python 一致）
    // Python: stream * (len(data) // 256 + 1))[1:1 + len(data)]
    let mut result = vec![0u8; data.len()];

    for (idx, result_byte) in result.iter_mut().enumerate() {
        // Python 索引从 1 开始，所以 stream_idx = idx + 1
        let stream_idx = idx + 1;
        let stream_byte = stream_256[stream_idx % 256];
        *result_byte = data[idx] ^ stream_byte;
    }

    result
}

/// 从音频数据头部检测格式
fn detect_audio_format(data: &[u8]) -> String {
    if data.len() >= 3 && &data[..3] == b"ID3" {
        return "mp3".to_string();
    }
    if data.len() >= 2 && data[0] == 0xFF && (data[1] & 0xE0) == 0xE0 {
        return "mp3".to_string();
    }
    if data.len() >= 4 && &data[..4] == b"fLaC" {
        return "flac".to_string();
    }
    "mp3".to_string()
}

/// 从元数据 JSON 中提取信息
fn parse_metadata(json_str: &str) -> (String, Option<String>, Option<String>, Option<String>) {
    let meta: serde_json::Value = match serde_json::from_str(json_str) {
        Ok(v) => v,
        Err(_) => return ("mp3".to_string(), None, None, None),
    };

    let format = meta["format"].as_str().unwrap_or("mp3").to_string();
    let title = meta["musicName"].as_str().map(|s| s.to_string());
    let artist = meta["artist"].as_array().and_then(|arr| {
        let names: Vec<String> = arr.iter().filter_map(|v| {
            if v.is_array() { v.as_array()?.first()?.as_str().map(|s| s.to_string()) }
            else if v.is_string() { v.as_str().map(|s| s.to_string()) }
            else { None }
        }).collect();
        if names.is_empty() { None } else { Some(names.join(" / ")) }
    });
    let album = meta["album"].as_str().map(|s| s.to_string());

    (format, title, artist, album)
}

/// 执行批量解密
pub fn run_decrypt(
    config: &NcmDecryptConfig,
    progress_callback: &dyn Fn(NcmDecryptProgress),
) -> NcmDecryptResult {
    let start_time = std::time::Instant::now();

    progress_callback(NcmDecryptProgress {
        total_files: 0,
        current_file_index: 0,
        current_file_name: String::new(),
        total_progress: 0.0,
        elapsed_seconds: 0.0,
        status: NcmDecryptStatus::Scanning,
    });

    let ncm_files = match scan_ncm_files(&config.source_dir) {
        Ok(f) => f,
        Err(e) => {
            return NcmDecryptResult {
                success: false, total_files: 0, success_count: 0, failed_count: 0,
                elapsed_seconds: start_time.elapsed().as_secs_f64(),
                failed_files: vec![], error_message: Some(format!("扫描目录失败: {}", e)),
            };
        }
    };

    let total = ncm_files.len() as u32;
    if total == 0 {
        return NcmDecryptResult {
            success: true, total_files: 0, success_count: 0, failed_count: 0,
            elapsed_seconds: start_time.elapsed().as_secs_f64(),
            failed_files: vec![], error_message: None,
        };
    }

    let mut success_count = 0u32;
    let mut failed_files = Vec::new();

    for (i, ncm_file) in ncm_files.iter().enumerate() {
        let progress = (i as f64 / total as f64) * 100.0;
        progress_callback(NcmDecryptProgress {
            total_files: total,
            current_file_index: i as u32,
            current_file_name: ncm_file.file_name.clone(),
            total_progress: progress,
            elapsed_seconds: start_time.elapsed().as_secs_f64(),
            status: NcmDecryptStatus::Decrypting,
        });

        match decrypt_and_save(ncm_file, config.delete_after_decrypt) {
            Ok(_) => {
                success_count += 1;
                sw_info!("[ncm_decrypt] 解密成功: {}", ncm_file.file_name);
            }
            Err(e) => {
                sw_warn!("[ncm_decrypt] 解密失败: {}, 原因: {}", ncm_file.file_name, e);
                failed_files.push(NcmFailedFile {
                    path: ncm_file.path.clone(),
                    reason: e.to_string(),
                });
            }
        }
    }

    let failed_count = total - success_count;
    let success = failed_count == 0;

    progress_callback(NcmDecryptProgress {
        total_files: total,
        current_file_index: total,
        current_file_name: String::new(),
        total_progress: 100.0,
        elapsed_seconds: start_time.elapsed().as_secs_f64(),
        status: if success { NcmDecryptStatus::Completed } else { NcmDecryptStatus::Failed },
    });

    NcmDecryptResult {
        success, total_files: total, success_count, failed_count,
        elapsed_seconds: start_time.elapsed().as_secs_f64(),
        failed_files,
        error_message: if failed_count > 0 { Some(format!("{} 个文件解密失败", failed_count)) } else { None },
    }
}

/// 解密单个 NCM 文件并保存到同目录
fn decrypt_and_save(ncm_file: &NcmFileInfo, delete_after: bool) -> Result<()> {
    let decrypted = decrypt_ncm_file(&ncm_file.path)?;

    let source_path = Path::new(&ncm_file.path);
    let output_path = source_path.with_extension(&decrypted.format);

    std::fs::write(&output_path, &decrypted.audio_data)
        .with_context(|| format!("写入音频文件失败: {}", output_path.display()))?;

    if let Some(ref cover_data) = decrypted.cover_data {
        if !cover_data.is_empty() {
            let cover_path = source_path.with_extension("jpg");
            let _ = std::fs::write(&cover_path, cover_data);
        }
    }

    if delete_after {
        if let Err(e) = std::fs::remove_file(source_path) {
            sw_warn!("[ncm_decrypt] 删除源文件失败: {}, 原因: {}", ncm_file.path, e);
        } else {
            sw_info!("[ncm_decrypt] 已删除源文件: {}", ncm_file.path);
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn get_test_ncm_dir() -> std::path::PathBuf {
        std::path::PathBuf::from("/Users/shilaimu/Music/网易云音乐")
    }

    #[test]
    fn test_scan_ncm_files() {
        let dir = get_test_ncm_dir();
        if !dir.exists() { eprintln!("测试目录不存在，跳过"); return; }
        let files = scan_ncm_files(dir.to_str().unwrap()).unwrap();
        println!("扫描到 {} 个 NCM 文件", files.len());
        for f in &files { println!("  - {} ({} bytes)", f.file_name, f.file_size); }
        assert!(!files.is_empty());
    }

    #[test]
    fn test_decrypt_ncm_file() {
        let dir = get_test_ncm_dir();
        if !dir.exists() { eprintln!("测试目录不存在，跳过"); return; }
        let files = scan_ncm_files(dir.to_str().unwrap()).unwrap();
        if files.is_empty() { eprintln!("没有 NCM 文件可测试"); return; }

        for ncm_file in &files {
            println!("正在解密: {}", ncm_file.file_name);
            match decrypt_ncm_file(&ncm_file.path) {
                Ok(decrypted) => {
                    println!("  解密成功!");
                    println!("  格式: {}", decrypted.format);
                    println!("  音频数据大小: {} bytes", decrypted.audio_data.len());
                    let head = &decrypted.audio_data[..16.min(decrypted.audio_data.len())];
                    println!("  头部字节: {:02X?}", head);
                    if let Some(title) = &decrypted.title { println!("  标题: {}", title); }
                    if let Some(artist) = &decrypted.artist { println!("  艺术家: {}", artist); }
                    if let Some(album) = &decrypted.album { println!("  专辑: {}", album); }

                    if decrypted.format == "mp3" {
                        assert!(
                            decrypted.audio_data.len() >= 3
                                && (&decrypted.audio_data[..3] == b"ID3"
                                    || (decrypted.audio_data[0] == 0xFF && (decrypted.audio_data[1] & 0xE0) == 0xE0)),
                            "MP3 文件头不匹配: {:02X?}", &decrypted.audio_data[..4.min(decrypted.audio_data.len())]
                        );
                    } else if decrypted.format == "flac" {
                        assert!(
                            decrypted.audio_data.len() >= 4 && &decrypted.audio_data[..4] == b"fLaC",
                            "FLAC 文件头不匹配: {:02X?}", &decrypted.audio_data[..4.min(decrypted.audio_data.len())]
                        );
                    }
                }
                Err(e) => { panic!("解密失败: {} - {}", ncm_file.file_name, e); }
            }
        }
    }
}
