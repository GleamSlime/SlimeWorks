use aes::cipher::{BlockDecrypt, KeyInit, KeyIvInit, StreamCipher};
use aes::Aes128;
use anyhow::{bail, Context, Result};
use base64::Engine;
use ctr::Ctr128BE;
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

type Aes128Ctr = Ctr128BE<Aes128>;

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

    if data.len() < 8 {
        bail!("文件太小，不是有效的 NCM 文件: {}", file_path);
    }

    // 验证魔数
    if data[..8] != NCM_MAGIC {
        bail!("文件头不匹配，不是有效的 NCM 文件: {}", file_path);
    }

    let mut offset = 8usize;

    // 读取 Key 长度和数据
    let key_len = read_u32_le(&data, &mut offset)?;
    if offset + key_len as usize > data.len() {
        bail!("Key 数据超出文件范围: {}", file_path);
    }
    let key_data = &data[offset..offset + key_len as usize];
    offset += key_len as usize;

    // 解密 Key
    let decrypted_key = decrypt_key(key_data)?;

    // 读取元数据长度和数据
    let meta_len = read_u32_le(&data, &mut offset)?;
    let metadata_json = if meta_len > 0 {
        if offset + meta_len as usize > data.len() {
            bail!("元数据超出文件范围: {}", file_path);
        }
        let meta_data = &data[offset..offset + meta_len as usize];
        offset += meta_len as usize;
        Some(decrypt_metadata(meta_data)?)
    } else {
        offset += meta_len as usize;
        None
    };

    // 跳过 CRC (5 字节) + 间隔
    offset += 5;
    // 跳过专辑封面图片
    let cover_len = read_u32_le(&data, &mut offset)?;
    let cover_data = if cover_len > 0 && offset + cover_len as usize <= data.len() {
        let cover = data[offset..offset + cover_len as usize].to_vec();
        offset += cover_len as usize;
        Some(cover)
    } else {
        offset += cover_len as usize;
        None
    };

    // 剩余数据为加密的音频数据
    let audio_data = decrypt_audio(&data[offset..], &decrypted_key)?;

    // 从元数据中提取信息
    let (format, title, artist, album) = if let Some(ref meta) = metadata_json {
        parse_metadata(meta)
    } else {
        ("mp3".to_string(), None, None, None)
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
        bail!("数据不足，无法读取 u32");
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

/// 解密核心密钥
fn decrypt_key(key_data: &[u8]) -> Result<Vec<u8>> {
    // 对每个字节与 0x64 异或
    let xored: Vec<u8> = key_data.iter().map(|b| b ^ 0x64).collect();

    // AES-128-ECB 解密
    let decrypted = aes_ecb_decrypt(&CORE_KEY, &xored);

    // 去掉 "neteasecloudmusic" 前缀（17 字节）
    if decrypted.len() < 17 {
        bail!("解密后的 Key 数据太短");
    }
    let key = decrypted[17..].to_vec();
    Ok(key)
}

/// 解密元数据
fn decrypt_metadata(meta_data: &[u8]) -> Result<String> {
    // 对每个字节与 0x63 异或
    let xored: Vec<u8> = meta_data.iter().map(|b| b ^ 0x63).collect();

    // 去掉 "163 key(Don't modify):" 前缀（22 字节）
    if xored.len() < 22 {
        bail!("元数据太短");
    }
    let base64_data = &xored[22..];

    // Base64 解码
    let decoded = base64::engine::general_purpose::STANDARD
        .decode(base64_data)
        .map_err(|e| anyhow::anyhow!("Base64 解码失败: {}", e))?;

    // AES-128-ECB 解密
    let decrypted = aes_ecb_decrypt(&META_KEY, &decoded);

    // 去掉 "music:" 前缀（6 字节）
    if decrypted.len() < 6 {
        bail!("解密后的元数据太短");
    }
    let json_bytes = &decrypted[6..];

    // 去除末尾的填充字节
    let json_str = trim_pkcs7_padding(json_bytes);

    Ok(json_str)
}

/// 去除 PKCS7 填充
fn trim_pkcs7_padding(data: &[u8]) -> String {
    if data.is_empty() {
        return String::new();
    }
    // 找到第一个有效的 JSON 结束位置
    let json_str = String::from_utf8_lossy(data);
    // 尝试找到 JSON 的结束位置（最后一个 } ）
    if let Some(pos) = json_str.rfind('}') {
        json_str[..=pos].to_string()
    } else {
        json_str.to_string()
    }
}

/// 解密音频数据
fn decrypt_audio(encrypted: &[u8], key: &[u8]) -> Result<Vec<u8>> {
    // 构建 AES-128-CTR 的 nonce
    let mut nonce = [0u8; 16];
    nonce[..8].copy_from_slice(&key[..8.min(key.len())]);

    // 对每个字节与 0x99 异或
    let xored: Vec<u8> = encrypted.iter().map(|b| b ^ 0x99).collect();

    // 使用 AES-128-CTR 解密
    let mut ctr = Aes128Ctr::new_from_slices(key, &nonce)
        .map_err(|e| anyhow::anyhow!("创建 AES-CTR 解密器失败: {}", e))?;
    let mut decrypted = xored;
    ctr.apply_keystream(&mut decrypted);

    // 检测音频格式并去除可能的填充
    let result = detect_and_trim_audio(&decrypted);
    Ok(result)
}

/// 检测音频格式并去除填充
fn detect_and_trim_audio(data: &[u8]) -> Vec<u8> {
    // MP3: 以 ID3 或 0xFF 0xFB 开头
    if data.len() >= 3 && &data[..3] == b"ID3" {
        return data.to_vec();
    }
    if data.len() >= 2 && data[0] == 0xFF && (data[1] & 0xE0) == 0xE0 {
        return data.to_vec();
    }
    // FLAC: 以 fLaC 开头
    if data.len() >= 4 && &data[..4] == b"fLaC" {
        return data.to_vec();
    }
    // 如果都不匹配，返回原始数据
    data.to_vec()
}

/// 从元数据 JSON 中提取信息
fn parse_metadata(json_str: &str) -> (String, Option<String>, Option<String>, Option<String>) {
    let meta: serde_json::Value = match serde_json::from_str(json_str) {
        Ok(v) => v,
        Err(_) => return ("mp3".to_string(), None, None, None),
    };

    let format = meta["format"]
        .as_str()
        .unwrap_or("mp3")
        .to_string();

    let title = meta["musicName"]
        .as_str()
        .map(|s| s.to_string());

    let artist = meta["artist"]
        .as_array()
        .and_then(|arr| {
            let names: Vec<String> = arr
                .iter()
                .filter_map(|v| {
                    if v.is_array() {
                        v.as_array()?.first()?.as_str().map(|s| s.to_string())
                    } else if v.is_string() {
                        v.as_str().map(|s| s.to_string())
                    } else {
                        None
                    }
                })
                .collect();
            if names.is_empty() {
                None
            } else {
                Some(names.join(" / "))
            }
        });

    let album = meta["album"]
        .as_str()
        .map(|s| s.to_string());

    (format, title, artist, album)
}

/// 执行批量解密
pub fn run_decrypt(
    config: &NcmDecryptConfig,
    progress_callback: &dyn Fn(NcmDecryptProgress),
) -> NcmDecryptResult {
    let start_time = std::time::Instant::now();

    // 扫描 NCM 文件
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
                success: false,
                total_files: 0,
                success_count: 0,
                failed_count: 0,
                elapsed_seconds: start_time.elapsed().as_secs_f64(),
                failed_files: vec![],
                error_message: Some(format!("扫描目录失败: {}", e)),
            };
        }
    };

    let total = ncm_files.len() as u32;
    if total == 0 {
        return NcmDecryptResult {
            success: true,
            total_files: 0,
            success_count: 0,
            failed_count: 0,
            elapsed_seconds: start_time.elapsed().as_secs_f64(),
            failed_files: vec![],
            error_message: None,
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
        status: if success {
            NcmDecryptStatus::Completed
        } else {
            NcmDecryptStatus::Failed
        },
    });

    NcmDecryptResult {
        success,
        total_files: total,
        success_count,
        failed_count,
        elapsed_seconds: start_time.elapsed().as_secs_f64(),
        failed_files,
        error_message: if failed_count > 0 {
            Some(format!("{} 个文件解密失败", failed_count))
        } else {
            None
        },
    }
}

/// 解密单个 NCM 文件并保存到同目录
fn decrypt_and_save(ncm_file: &NcmFileInfo, delete_after: bool) -> Result<()> {
    let decrypted = decrypt_ncm_file(&ncm_file.path)?;

    // 构建输出路径：同目录，扩展名替换为音频格式
    let source_path = Path::new(&ncm_file.path);
    let output_path = source_path.with_extension(&decrypted.format);

    // 写入音频文件
    std::fs::write(&output_path, &decrypted.audio_data)
        .with_context(|| format!("写入音频文件失败: {}", output_path.display()))?;

    // 如果有封面数据，保存封面图片
    if let Some(ref cover_data) = decrypted.cover_data {
        if !cover_data.is_empty() {
            let cover_path = source_path.with_extension("jpg");
            let _ = std::fs::write(&cover_path, cover_data);
        }
    }

    // 如果勾选了删除源文件，且解密成功
    if delete_after {
        if let Err(e) = std::fs::remove_file(source_path) {
            sw_warn!("[ncm_decrypt] 删除源文件失败: {}, 原因: {}", ncm_file.path, e);
        } else {
            sw_info!("[ncm_decrypt] 已删除源文件: {}", ncm_file.path);
        }
    }

    Ok(())
}
