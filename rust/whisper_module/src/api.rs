use std::path::Path;

use crate::audio::extract_pcm_16k_mono;
use crate::model;
use crate::types::{ModelStatus, TranscriptionResult, TranscriptionSegment, WhisperModelPreset};

/// whisper 语言 ID 到字符串的映射
/// 参考 whisper.cpp 的 whisper_lang_str() 函数
fn whisper_lang_id_to_str(lang_id: i32) -> &'static str {
    match lang_id {
        0 => "en",
        1 => "zh",
        2 => "de",
        3 => "es",
        4 => "ru",
        5 => "ko",
        6 => "fr",
        7 => "ja",
        8 => "pt",
        9 => "tr",
        10 => "pl",
        11 => "ca",
        12 => "nl",
        13 => "ar",
        14 => "sv",
        15 => "it",
        16 => "id",
        17 => "hi",
        18 => "fi",
        19 => "vi",
        20 => "he",
        21 => "uk",
        22 => "el",
        23 => "ms",
        24 => "cs",
        25 => "ro",
        26 => "da",
        27 => "hu",
        28 => "ta",
        29 => "no",
        30 => "th",
        31 => "ur",
        32 => "hr",
        33 => "bg",
        34 => "lt",
        35 => "la",
        36 => "mi",
        37 => "ml",
        38 => "cy",
        39 => "sk",
        40 => "te",
        41 => "fa",
        42 => "lv",
        43 => "bn",
        44 => "sr",
        45 => "az",
        46 => "sl",
        47 => "kn",
        48 => "et",
        49 => "mk",
        50 => "br",
        51 => "eu",
        52 => "is",
        53 => "hy",
        54 => "ne",
        55 => "mn",
        56 => "bs",
        57 => "kk",
        58 => "sq",
        59 => "sw",
        60 => "gl",
        61 => "mr",
        62 => "pa",
        63 => "si",
        64 => "km",
        65 => "sn",
        66 => "yo",
        67 => "so",
        68 => "af",
        69 => "oc",
        70 => "ka",
        71 => "be",
        72 => "tg",
        73 => "sd",
        74 => "gu",
        75 => "am",
        76 => "yi",
        77 => "lo",
        78 => "uz",
        79 => "fo",
        80 => "ht",
        81 => "ps",
        82 => "tk",
        83 => "nn",
        84 => "mt",
        85 => "sa",
        86 => "lb",
        87 => "my",
        88 => "bo",
        89 => "tl",
        90 => "mg",
        91 => "as",
        92 => "tt",
        93 => "haw",
        94 => "ln",
        95 => "ha",
        96 => "ba",
        97 => "jw",
        98 => "su",
        _ => "unknown",
    }
}

/// 获取所有可用模型预设的状态
pub fn get_all_model_statuses() -> Result<Vec<ModelStatus>, String> {
    let presets = WhisperModelPreset::as_str_list();
    let mut statuses = Vec::new();

    for preset_name in presets {
        let preset = WhisperModelPreset::from_str_name(&preset_name);
        let path = model::get_model_path(preset);
        let exists = path.exists();
        let size = if exists {
            std::fs::metadata(&path).ok().map(|m| m.len())
        } else {
            None
        };

        statuses.push(ModelStatus {
            selected_model: preset,
            model_file_exists: exists,
            model_file_path: if exists {
                Some(path.to_string_lossy().into_owned())
            } else {
                None
            },
            model_file_size: size,
        });
    }

    Ok(statuses)
}

/// 获取当前选中的模型预设
pub fn get_selected_model() -> WhisperModelPreset {
    // 从配置中读取，默认 LargeV3
    let config_key = "whisper_selected_model";
    if let Ok(Some(value)) = db_module::db_get("whisper_config".to_string(), config_key.to_string())
    {
        serde_json::from_str::<WhisperModelPreset>(&value).unwrap_or(WhisperModelPreset::LargeV3)
    } else {
        WhisperModelPreset::LargeV3
    }
}

/// 设置当前选中的模型预设
pub fn set_selected_model(preset_name: String) -> Result<bool, String> {
    let preset = WhisperModelPreset::from_str_name(&preset_name);
    let config_key = "whisper_selected_model";
    let value = serde_json::to_string(&preset).map_err(|e: serde_json::Error| e.to_string())?;
    db_module::db_set("whisper_config".to_string(), config_key.to_string(), value)
        .map_err(|e: String| e)?;
    Ok(true)
}

/// 下载指定模型
pub fn download_model(preset_name: String) -> Result<u64, String> {
    let preset = WhisperModelPreset::from_str_name(&preset_name);
    model::download_model(preset)
}

/// 删除指定模型
pub fn delete_model(preset_name: String) -> Result<bool, String> {
    let preset = WhisperModelPreset::from_str_name(&preset_name);
    model::delete_model(preset)
}

/// 初始化 whisper 配置表
pub fn initialize_whisper_db() -> Result<(), String> {
    db_module::db_register_table("whisper_config".to_string()).map_err(|e: String| e)?;
    Ok(())
}

/// 识别音频文件并生成 CUE 文件
/// 返回识别结果和生成的 CUE 文件路径
pub fn transcribe_and_generate_cue(
    audio_file_path: String,
    language: Option<String>,
) -> Result<TranscriptionResult, String> {
    let preset = get_selected_model();

    // 检查模型是否存在
    if !model::is_model_downloaded(preset) {
        return Err(format!(
            "模型 {} 未下载，请先下载模型",
            preset.display_name()
        ));
    }

    let model_path = model::get_model_path(preset);

    // 提取 PCM 数据
    let pcm_data = extract_pcm_16k_mono(&audio_file_path)?;

    // 使用 whisper-rs 进行识别
    let result = transcribe_with_whisper(
        &model_path.to_string_lossy(),
        &pcm_data,
        language.as_deref(),
    )?;

    // 生成 CUE 文件
    let cue_path = generate_cue_file(&audio_file_path, &result)?;

    slime_logger::sw_info!(
        "[whisper] 识别完成: {} 片段, CUE 文件: {:?}",
        result.segments.len(),
        cue_path
    );

    Ok(result)
}

/// 使用 whisper-rs 进行识别
fn transcribe_with_whisper(
    model_path: &str,
    pcm_data: &[f32],
    language: Option<&str>,
) -> Result<TranscriptionResult, String> {
    use whisper_rs::{FullParams, SamplingStrategy, WhisperContext, WhisperContextParameters};

    // 创建上下文
    let ctx_params = WhisperContextParameters::default();
    let ctx = WhisperContext::new_with_params(model_path, ctx_params)
        .map_err(|e| format!("加载 Whisper 模型失败: {}", e))?;

    // 创建参数
    let mut params = FullParams::new(SamplingStrategy::BeamSearch {
        beam_size: 5,
        patience: -1.0,
    });

    // 设置语言
    if let Some(lang) = language {
        params.set_language(Some(lang));
    } else {
        params.set_language(None); // 自动检测
    }

    params.set_print_progress(false);
    params.set_print_timestamps(false);
    params.set_single_segment(false);
    params.set_no_timestamps(false);

    // 创建状态并运行识别
    let mut state = ctx
        .create_state()
        .map_err(|e| format!("创建 Whisper 状态失败: {}", e))?;

    state
        .full(params, pcm_data)
        .map_err(|e| format!("Whisper 识别失败: {}", e))?;

    // 获取识别结果
    let num_segments = state.full_n_segments();

    let mut segments = Vec::new();
    let mut full_text = String::new();
    let mut detected_language = String::from("unknown");

    // 获取检测到的语言
    let lang_id = state.full_lang_id_from_state();
    if lang_id >= 0 {
        // whisper 语言 ID 映射（whisper.cpp 内部定义）
        detected_language = whisper_lang_id_to_str(lang_id).to_string();
    }

    for i in 0..num_segments {
        // 使用 get_segment 获取片段信息
        let segment = match state.get_segment(i) {
            Some(s) => s,
            None => continue,
        };

        // whisper.cpp 时间单位是 centiseconds (10ms)
        let start_ms = segment.start_timestamp() as u64 * 10;
        let end_ms = segment.end_timestamp() as u64 * 10;

        let text = segment.to_str_lossy().unwrap_or_default().into_owned();
        let trimmed_text = text.trim();
        if !trimmed_text.is_empty() {
            segments.push(TranscriptionSegment {
                start_ms,
                end_ms,
                text: trimmed_text.to_string(),
            });
            if !full_text.is_empty() {
                full_text.push(' ');
            }
            full_text.push_str(trimmed_text);
        }
    }

    Ok(TranscriptionResult {
        language: detected_language,
        segments,
        full_text,
    })
}

/// 根据识别结果生成 CUE 文件
fn generate_cue_file(
    audio_file_path: &str,
    result: &TranscriptionResult,
) -> Result<String, String> {
    let audio_path = Path::new(audio_file_path);
    let audio_filename = audio_path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("audio.wav");

    // CUE 文件放在音频文件同级目录
    let cue_path = audio_path.with_extension("cue");
    let cue_content = format_cue_content(audio_filename, result);

    std::fs::write(&cue_path, cue_content).map_err(|e| format!("写入 CUE 文件失败: {}", e))?;

    Ok(cue_path.to_string_lossy().into_owned())
}

/// 格式化 CUE 文件内容
fn format_cue_content(audio_filename: &str, result: &TranscriptionResult) -> String {
    let mut cue = String::new();
    cue.push_str("REM Generated by SlimeWorks Whisper Module\n");
    cue.push_str(&format!("REM Language: {}\n", result.language));
    cue.push_str(&format!("FILE \"{}\" WAVE\n", audio_filename));

    for (i, seg) in result.segments.iter().enumerate() {
        cue.push_str(&format!("  TRACK {} AUDIO\n", i + 1));
        cue.push_str(&format!("    TITLE \"{}\"\n", seg.text));
        let start_min = seg.start_ms / 60000;
        let start_sec = (seg.start_ms % 60000) / 1000;
        let start_frame = ((seg.start_ms % 1000) * 75 / 1000) as u32;
        cue.push_str(&format!(
            "    INDEX 01 {:02}:{:02}:{:02}\n",
            start_min, start_sec, start_frame
        ));
    }

    cue
}
