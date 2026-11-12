use symphonia::core::audio::Signal;
use symphonia::core::codecs::{DecoderOptions, CODEC_TYPE_NULL};
use symphonia::core::errors::Error as SymphoniaError;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;

/// 从音频文件中提取 PCM 数据（16kHz, 单声道, f32）
pub fn extract_pcm_16k_mono(file_path: &str) -> Result<Vec<f32>, String> {
    let src = std::fs::File::open(file_path).map_err(|e| format!("打开音频文件失败: {}", e))?;
    let mss = MediaSourceStream::new(
        Box::new(src) as Box<dyn symphonia::core::io::MediaSource>,
        Default::default(),
    );

    let hint = Hint::new();
    let format_opts = FormatOptions::default();
    let metadata_opts = MetadataOptions::default();
    let decoder_opts = DecoderOptions::default();

    let probed = symphonia::default::get_probe()
        .format(&hint, mss, &format_opts, &metadata_opts)
        .map_err(|e| format!("探测音频格式失败: {}", e))?;

    let mut format = probed.format;

    // 找到第一个音频轨道
    let mut track_id = format
        .tracks()
        .iter()
        .find(|t| t.codec_params.codec != CODEC_TYPE_NULL)
        .map(|t| t.id)
        .ok_or("未找到音频轨道")?;

    let track = format.tracks().iter().find(|t| t.id == track_id).unwrap();

    let mut decoder = symphonia::default::get_codecs()
        .make(&track.codec_params, &decoder_opts)
        .map_err(|e| format!("创建解码器失败: {}", e))?;

    let mut orig_sample_rate = track.codec_params.sample_rate.unwrap_or(44100);

    // 解码所有帧
    let mut pcm_data = Vec::new();

    // ResetRequired 表示容器里出现了新的轨道/编码（如拼接流）。symphonia 的约定是
    // 重新检查轨道并重建解码器；只 continue 的话 next_packet 会一直报同一个错，
    // 循环空转到程序退出。这里重建一次，并加次数上限兜住坏文件。
    let mut resets = 0u32;
    const MAX_RESETS: u32 = 8;

    loop {
        let packet = match format.next_packet() {
            Ok(p) => p,
            Err(SymphoniaError::ResetRequired) => {
                resets += 1;
                if resets > MAX_RESETS {
                    slime_logger::sw_warn!(
                        "[whisper] 解码需要反复重置（已 {} 次），放弃剩余数据",
                        MAX_RESETS
                    );
                    break;
                }
                // 轨道表可能已经变了，重取当前轨道与采样率；找不到就收工
                let (new_track_id, new_rate) = match format
                    .tracks()
                    .iter()
                    .find(|t| t.codec_params.codec != CODEC_TYPE_NULL)
                {
                    Some(t) => (t.id, t.codec_params.sample_rate.unwrap_or(orig_sample_rate)),
                    None => break,
                };
                let new_params = match format.tracks().iter().find(|t| t.id == new_track_id) {
                    Some(t) => t.codec_params.clone(),
                    None => break,
                };
                match symphonia::default::get_codecs().make(&new_params, &decoder_opts) {
                    Ok(new_decoder) => {
                        decoder = new_decoder;
                        track_id = new_track_id;
                        orig_sample_rate = new_rate;
                    }
                    Err(e) => {
                        slime_logger::sw_warn!("[whisper] 重置解码器失败: {}", e);
                        break;
                    }
                }
                continue;
            }
            Err(SymphoniaError::IoError(_)) => break,
            Err(e) => {
                slime_logger::sw_warn!("[whisper] 解码包错误: {}", e);
                break;
            }
        };

        if packet.track_id() != track_id {
            continue;
        }

        match decoder.decode(&packet) {
            Ok(decoded) => {
                let frames = decoded.frames();
                match decoded {
                    symphonia::core::audio::AudioBufferRef::U8(buf) => {
                        let ch0 = buf.chan(0);
                        for i in 0..frames {
                            pcm_data.push((ch0[i] as f32 - 128.0) / 128.0);
                        }
                    }
                    symphonia::core::audio::AudioBufferRef::S16(buf) => {
                        let ch0 = buf.chan(0);
                        for i in 0..frames {
                            pcm_data.push(ch0[i] as f32 / 32768.0);
                        }
                    }
                    symphonia::core::audio::AudioBufferRef::S24(buf) => {
                        let ch0 = buf.chan(0);
                        for i in 0..frames {
                            pcm_data.push(ch0[i].0 as f32 / 8388608.0);
                        }
                    }
                    symphonia::core::audio::AudioBufferRef::S32(buf) => {
                        let ch0 = buf.chan(0);
                        for i in 0..frames {
                            pcm_data.push(ch0[i] as f32 / 2147483648.0);
                        }
                    }
                    symphonia::core::audio::AudioBufferRef::F32(buf) => {
                        let ch0 = buf.chan(0);
                        for i in 0..frames {
                            pcm_data.push(ch0[i]);
                        }
                    }
                    symphonia::core::audio::AudioBufferRef::F64(buf) => {
                        let ch0 = buf.chan(0);
                        for i in 0..frames {
                            pcm_data.push(ch0[i] as f32);
                        }
                    }
                    // 其他格式统一转为 f32
                    _ => {
                        // 对于不直接支持的格式，使用 convert 方法
                        // 跳过这些不常见的格式
                        slime_logger::sw_warn!("[whisper] 跳过不支持的音频采样格式");
                    }
                }
            }
            Err(e) => {
                slime_logger::sw_warn!("[whisper] 解码错误: {}", e);
                break;
            }
        }
    }

    // 重采样到 16kHz
    let resampled = if orig_sample_rate != 16000 {
        resample(&pcm_data, orig_sample_rate, 16000)
    } else {
        pcm_data
    };

    slime_logger::sw_info!(
        "[whisper] PCM 提取完成: {}Hz -> 16kHz, {} 样本",
        orig_sample_rate,
        resampled.len()
    );

    Ok(resampled)
}

fn resample(data: &[f32], from_rate: u32, to_rate: u32) -> Vec<f32> {
    if from_rate == to_rate {
        return data.to_vec();
    }
    let ratio = from_rate as f64 / to_rate as f64;
    let new_len = (data.len() as f64 / ratio) as usize;
    let mut result = Vec::with_capacity(new_len);

    for i in 0..new_len {
        let src_pos = i as f64 * ratio;
        let src_idx = src_pos as usize;
        let frac = (src_pos - src_idx as f64) as f32;

        if src_idx + 1 < data.len() {
            result.push(data[src_idx] * (1.0 - frac) + data[src_idx + 1] * frac);
        } else if src_idx < data.len() {
            result.push(data[src_idx]);
        }
    }

    result
}
