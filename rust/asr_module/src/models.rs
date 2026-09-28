use std::path::PathBuf;

use crate::runtime::{
    asr_root, dir_size_bytes, download_to_file, extract_tar_bz2, find_file_recursive,
    mark_deploy_idle, set_deploy_progress, set_deploy_stage,
};

/// SenseVoice 多语模型（zh/en/ja/ko/yue，int8 量化，压缩包约 250MB）
const SENSE_VOICE_STEM: &str = "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17";
const RELEASE_ASSETS_BASE: &str =
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models";

/// 模型根目录：asr/models
fn models_root() -> PathBuf {
    let dir = asr_root().join("models");
    let _ = std::fs::create_dir_all(&dir);
    dir
}

/// SenseVoice 模型文件路径（model.int8.onnx）
pub fn sense_voice_model_path() -> Option<PathBuf> {
    find_file_recursive(&models_root(), "model.int8.onnx")
        .or_else(|| find_file_recursive(&models_root(), "model.onnx"))
}

/// tokens.txt 路径
pub fn tokens_path() -> Option<PathBuf> {
    find_file_recursive(&models_root(), "tokens.txt")
}

/// silero VAD 模型路径
pub fn vad_model_path() -> Option<PathBuf> {
    let direct = models_root().join("silero_vad.onnx");
    if direct.exists() {
        Some(direct)
    } else {
        find_file_recursive(&models_root(), "silero_vad.onnx")
    }
}

/// SenseVoice 模型是否就绪
pub fn is_model_ready() -> bool {
    sense_voice_model_path().is_some() && tokens_path().is_some()
}

/// VAD 模型是否就绪
pub fn is_vad_ready() -> bool {
    vad_model_path().is_some()
}

/// 模型占用字节数
pub fn models_disk_usage() -> u64 {
    dir_size_bytes(&models_root())
}

/// 下载全部模型（SenseVoice + silero VAD），阻塞，需在后台线程调用
pub fn download_models() -> Result<(), String> {
    if !is_model_ready() {
        download_sense_voice()?;
    }
    if !is_vad_ready() {
        download_vad()?;
    }
    set_deploy_stage(3);
    set_deploy_progress(10000);
    Ok(())
}

fn download_sense_voice() -> Result<(), String> {
    set_deploy_stage(1);
    set_deploy_progress(0);

    let url = format!("{}/{}.tar.bz2", RELEASE_ASSETS_BASE, SENSE_VOICE_STEM);
    slime_logger::sw_info!("[asr] 开始下载 SenseVoice 模型: {}", url);

    let root = models_root();
    let archive = root.join("_sense_voice.tar.bz2");
    if let Err(e) = download_to_file(&url, &archive) {
        set_deploy_stage(4);
        mark_deploy_idle();
        let _ = std::fs::remove_file(&archive);
        return Err(e);
    }

    set_deploy_stage(2);
    slime_logger::sw_info!("[asr] SenseVoice 模型下载完成，开始解压");
    let extracted = extract_tar_bz2(&archive, &root);
    let _ = std::fs::remove_file(&archive);

    match extracted {
        Ok(()) => {
            // 包内附带大量示例音频，识别流程用不到，顺手清理以省磁盘
            let sample_dir = root.join(SENSE_VOICE_STEM).join("test_wavs");
            if sample_dir.exists() {
                let _ = std::fs::remove_dir_all(&sample_dir);
            }
            if is_model_ready() {
                Ok(())
            } else {
                set_deploy_stage(4);
                mark_deploy_idle();
                Err("解压后未找到 SenseVoice 模型文件".to_string())
            }
        }
        Err(e) => {
            set_deploy_stage(4);
            mark_deploy_idle();
            Err(e)
        }
    }
}

fn download_vad() -> Result<(), String> {
    set_deploy_stage(1);
    set_deploy_progress(0);

    let url = format!("{}/silero_vad.onnx", RELEASE_ASSETS_BASE);
    slime_logger::sw_info!("[asr] 开始下载 silero VAD 模型: {}", url);

    let dest = models_root().join("silero_vad.onnx");
    match download_to_file(&url, &dest) {
        Ok(()) => {
            set_deploy_progress(10000);
            Ok(())
        }
        Err(e) => {
            set_deploy_stage(4);
            mark_deploy_idle();
            let _ = std::fs::remove_file(&dest);
            Err(e)
        }
    }
}

/// 删除全部模型
pub fn remove_models() -> Result<(), String> {
    let dir = models_root();
    if dir.exists() {
        std::fs::remove_dir_all(&dir).map_err(|e| format!("删除模型目录失败: {}", e))?;
    }
    set_deploy_stage(0);
    mark_deploy_idle();
    Ok(())
}
