use std::path::Path;
use std::sync::atomic::{AtomicU32, Ordering};

use crate::audio::extract_pcm_16k_mono;
use crate::model;
use crate::types::{ModelStatus, TranscriptionResult, TranscriptionSegment, WhisperModelPreset};

/// 全局转录进度（百分比 × 100，即 0~10000），用于跨线程/FI 读取
static TRANSCRIPTION_PROGRESS: AtomicU32 = AtomicU32::new(0);

/// 获取当前转录进度（0~100 的浮点数），无转录进行时返回 -1.0
pub fn get_transcription_progress() -> f64 {
    let val = TRANSCRIPTION_PROGRESS.load(Ordering::Relaxed);
    if val == u32::MAX {
        -1.0
    } else {
        val as f64 / 100.0
    }
}

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
    // 确保数据库实例已初始化（与 music_player 共用同一数据库文件）
    let db_path = {
        let app_data = std::env::var("APPDATA").unwrap_or_else(|_| ".".to_string());
        let dir = std::path::Path::new(&app_data).join("SlimeWorks");
        let _ = std::fs::create_dir_all(&dir);
        dir.join("music_player.db").to_string_lossy().into_owned()
    };
    let _ = db_module::db_init(db_path.clone());
    // 绑定到专属文件，避免历史上全局单例被其他模块抢先导致配置写错文件
    db_module::db_bind_table("whisper_config".to_string(), db_path.clone())
        .map_err(|e: String| e)?;
    // 一次性迁移：历史上配置可能被写入 media.db / db.redb
    migrate_scattered_whisper_config(&db_path);
    Ok(())
}

/// 一次性迁移：把散落在其他数据库文件中的 whisper_config 合并回 music_player.db（幂等）。
fn migrate_scattered_whisper_config(db_path: &str) {
    // 幂等标记存于 whisper_config 表内部（配置表，不影响其他逻辑）
    if let Ok(Some(flag)) =
        db_module::db_get("whisper_config".to_string(), "scatter_merged_v1".to_string())
    {
        if flag == "1" {
            return;
        }
    }
    let base = std::path::Path::new(db_path)
        .parent()
        .map(|p| p.to_path_buf());
    if let Some(base) = base {
        for name in ["media.db"] {
            let candidate = base.join(name);
            if !candidate.exists() {
                continue;
            }
            let src = candidate.to_string_lossy().into_owned();
            let _ = db_module::db_merge_tables(
                src,
                db_path.to_string(),
                vec!["whisper_config".to_string()],
                false,
            );
        }
    }
    let _ = db_module::db_set(
        "whisper_config".to_string(),
        "scatter_merged_v1".to_string(),
        "1".to_string(),
    );
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

    // 重置进度
    TRANSCRIPTION_PROGRESS.store(0, Ordering::Relaxed);

    // 提取 PCM 数据
    let pcm_data = extract_pcm_16k_mono(&audio_file_path)?;

    // 使用 whisper-rs 进行识别（带进度回调）
    let result = transcribe_with_whisper(
        &model_path.to_string_lossy(),
        &pcm_data,
        language.as_deref(),
    )?;

    // 生成 CUE 文件
    let cue_path = generate_cue_file(&audio_file_path, &result)?;

    // 标记进度完成
    TRANSCRIPTION_PROGRESS.store(10000, Ordering::Relaxed);

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

    // 创建上下文（启用 GPU 加速）
    let mut ctx_params = WhisperContextParameters::default();
    ctx_params.use_gpu = true;
    let ctx = WhisperContext::new_with_params(model_path, ctx_params)
        .map_err(|e| format!("加载 Whisper 模型失败: {}", e))?;

    // 创建参数
    let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 1 });

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

    // 防重复参数
    params.set_suppress_blank(true); // 抑制空白输出
    params.set_no_speech_thold(0.6); // 跳过静音段

    // 设置初始提示词，帮助模型理解上下文，减少重复
    if let Some(ref lang) = language {
        match &**lang {
            "ja" => params.set_initial_prompt("以下是日语的语音内容。"),
            "zh" => params.set_initial_prompt("以下是中文的语音内容。"),
            "en" => params.set_initial_prompt("The following is English speech content."),
            "ko" => params.set_initial_prompt("다음은 한국어 음성 콘텐츠입니다."),
            _ => {}
        }
    }

    // 设置进度回调，将进度写入全局原子变量
    params.set_progress_callback_safe(move |progress: i32| {
        // progress 是 0~100 的整数百分比
        let stored = (progress * 100) as u32; // 转为 0~10000
        TRANSCRIPTION_PROGRESS.store(stored, Ordering::Relaxed);
    });

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
