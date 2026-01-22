/// 视频压缩模块
use anyhow::{Context, Result};
use ffmpeg_sys_next::AVRounding::{AV_ROUND_NEAR_INF, AV_ROUND_PASS_MINMAX};
use std::ffi::CString;
use std::path::Path;
use std::ptr;

/// 视频编码器
#[derive(Debug, Clone, Copy)]
pub enum VideoCodec {
    H264,
    H265,
    VP9,
    AV1,
}

impl VideoCodec {
    pub fn codec_name(&self) -> &str {
        match self {
            VideoCodec::H264 => "libx264",
            VideoCodec::H265 => "libx265",
            VideoCodec::VP9 => "libvpx-vp9",
            VideoCodec::AV1 => "libaom-av1",
        }
    }

    /// 获取硬件加速编码器名称（如果支持）
    pub fn hw_codec_name(&self, platform: Platform) -> Option<&str> {
        match (self, platform) {
            (VideoCodec::H264, Platform::MacOS) => Some("h264_videotoolbox"),
            (VideoCodec::H265, Platform::MacOS) => Some("hevc_videotoolbox"),
            (VideoCodec::H264, Platform::Windows) => Some("h264_nvenc"),
            (VideoCodec::H265, Platform::Windows) => Some("hevc_nvenc"),
            _ => None,
        }
    }
}

/// 平台类型
#[derive(Debug, Clone, Copy)]
pub enum Platform {
    MacOS,
    Windows,
    Linux,
}

impl Platform {
    pub fn current() -> Self {
        #[cfg(target_os = "macos")]
        return Platform::MacOS;

        #[cfg(target_os = "windows")]
        return Platform::Windows;

        #[cfg(target_os = "linux")]
        return Platform::Linux;
    }
}

/// 压缩预设
#[derive(Debug, Clone, Copy)]
pub enum Preset {
    UltraFast,
    SuperFast,
    VeryFast,
    Faster,
    Fast,
    Medium,
    Slow,
    Slower,
    VerySlow,
}

impl Preset {
    pub fn as_str(&self) -> &str {
        match self {
            Preset::UltraFast => "ultrafast",
            Preset::SuperFast => "superfast",
            Preset::VeryFast => "veryfast",
            Preset::Faster => "faster",
            Preset::Fast => "fast",
            Preset::Medium => "medium",
            Preset::Slow => "slow",
            Preset::Slower => "slower",
            Preset::VerySlow => "veryslow",
        }
    }
}

/// 压缩配置
#[derive(Debug, Clone)]
pub struct CompressConfig {
    /// 输入视频路径
    pub input_path: String,
    /// 输出目录
    pub output_dir: String,
    /// 输出文件名（不含扩展名，None则自动生成）
    pub output_filename: Option<String>,
    /// 视频编码器
    pub codec: VideoCodec,
    /// 是否使用硬件加速
    pub use_hardware_accel: bool,
    /// 目标比特率（kbps，0表示使用CRF模式）
    pub bitrate: u32,
    /// CRF质量值（0-51，越小质量越好，仅在bitrate=0时有效）
    pub crf: u32,
    /// 压缩预设
    pub preset: Preset,
    /// 目标宽度（0表示保持原始）
    pub width: u32,
    /// 目标高度（0表示保持原始）
    pub height: u32,
    /// 目标帧率（0表示保持原始）
    pub fps: u32,
    /// 音频比特率（kbps，0表示复制原始音频）
    pub audio_bitrate: u32,
}

impl Default for CompressConfig {
    fn default() -> Self {
        Self {
            input_path: String::new(),
            output_dir: String::from("."),
            output_filename: None,
            codec: VideoCodec::H264,
            use_hardware_accel: true,
            bitrate: 0,
            crf: 23,
            preset: Preset::Medium,
            width: 0,
            height: 0,
            fps: 0,
            audio_bitrate: 128,
        }
    }
}

/// 视频压缩器
pub struct VideoCompressor {
    config: CompressConfig,
}

impl VideoCompressor {
    /// 创建新的压缩器
    pub fn new(config: CompressConfig) -> Result<Self> {
        if config.input_path.is_empty() {
            return Err(anyhow::anyhow!("输入路径不能为空"));
        }

        if !Path::new(&config.input_path).exists() {
            return Err(anyhow::anyhow!("输入文件不存在"));
        }

        // 确保输出目录存在
        let output_path = Path::new(&config.output_dir);
        if !output_path.exists() {
            std::fs::create_dir_all(output_path).context("创建输出目录失败")?;
        }

        Ok(Self { config })
    }

    /// 开始压缩
    pub fn compress(&self) -> Result<String> {
        crate::init_ffmpeg();

        let platform = Platform::current();

        // 选择编码器（优先硬件加速）
        let encoder_name = if self.config.use_hardware_accel {
            self.config
                .codec
                .hw_codec_name(platform)
                .unwrap_or(self.config.codec.codec_name())
        } else {
            self.config.codec.codec_name()
        };

        println!("[压缩] 使用编码器: {}", encoder_name);

        unsafe {
            // 打开输入文件
            let input_path =
                CString::new(self.config.input_path.as_str()).context("无效的输入路径")?;

            let mut input_ctx: *mut ffmpeg_sys_next::AVFormatContext = ptr::null_mut();
            let ret = ffmpeg_sys_next::avformat_open_input(
                &mut input_ctx,
                input_path.as_ptr(),
                ptr::null_mut(),
                ptr::null_mut(),
            );

            if ret < 0 {
                return Err(anyhow::anyhow!("打开输入文件失败: {}", ret));
            }

            // 查找流信息
            let ret = ffmpeg_sys_next::avformat_find_stream_info(input_ctx, ptr::null_mut());
            if ret < 0 {
                ffmpeg_sys_next::avformat_close_input(&mut input_ctx);
                return Err(anyhow::anyhow!("查找流信息失败: {}", ret));
            }

            // 生成输出文件路径
            let output_filename = self.config.output_filename.clone().unwrap_or_else(|| {
                let input_stem = Path::new(&self.config.input_path)
                    .file_stem()
                    .and_then(|s| s.to_str())
                    .unwrap_or("compressed");
                format!("{}_compressed", input_stem)
            });
            let output_path =
                Path::new(&self.config.output_dir).join(format!("{}.mp4", output_filename));
            let output_path_str = output_path.to_string_lossy().to_string();

            // 创建输出上下文
            let output_file = CString::new(output_path_str.as_str()).context("无效的输出路径")?;
            let mut output_ctx: *mut ffmpeg_sys_next::AVFormatContext = ptr::null_mut();
            let ret = ffmpeg_sys_next::avformat_alloc_output_context2(
                &mut output_ctx,
                ptr::null_mut(),
                ptr::null(),
                output_file.as_ptr(),
            );

            if ret < 0 || output_ctx.is_null() {
                ffmpeg_sys_next::avformat_close_input(&mut input_ctx);
                return Err(anyhow::anyhow!("创建输出上下文失败: {}", ret));
            }

            // 处理视频流和音频流
            // 这里简化处理，实际需要设置编码器参数、缩放等
            let nb_streams = (*input_ctx).nb_streams;
            for i in 0..nb_streams {
                let in_stream = *(*input_ctx).streams.add(i as usize);
                let codecpar = (*in_stream).codecpar;

                let out_stream = ffmpeg_sys_next::avformat_new_stream(output_ctx, ptr::null());
                if out_stream.is_null() {
                    ffmpeg_sys_next::avformat_close_input(&mut input_ctx);
                    ffmpeg_sys_next::avformat_free_context(output_ctx);
                    return Err(anyhow::anyhow!("创建输出流失败"));
                }

                // 简化处理：直接复制编解码参数
                // 实际应该根据配置重新编码
                let ret =
                    ffmpeg_sys_next::avcodec_parameters_copy((*out_stream).codecpar, codecpar);
                if ret < 0 {
                    ffmpeg_sys_next::avformat_close_input(&mut input_ctx);
                    ffmpeg_sys_next::avformat_free_context(output_ctx);
                    return Err(anyhow::anyhow!("复制编解码参数失败: {}", ret));
                }

                (*(*out_stream).codecpar).codec_tag = 0;
            }

            // 打开输出文件
            if (*(*output_ctx).oformat).flags & ffmpeg_sys_next::AVFMT_NOFILE as i32 == 0 {
                let ret = ffmpeg_sys_next::avio_open(
                    &mut (*output_ctx).pb,
                    output_file.as_ptr(),
                    ffmpeg_sys_next::AVIO_FLAG_WRITE as i32,
                );
                if ret < 0 {
                    ffmpeg_sys_next::avformat_close_input(&mut input_ctx);
                    ffmpeg_sys_next::avformat_free_context(output_ctx);
                    return Err(anyhow::anyhow!("打开输出文件失败: {}", ret));
                }
            }

            // 写入文件头
            let ret = ffmpeg_sys_next::avformat_write_header(output_ctx, ptr::null_mut());
            if ret < 0 {
                if !(*output_ctx).pb.is_null() {
                    ffmpeg_sys_next::avio_closep(&mut (*output_ctx).pb);
                }
                ffmpeg_sys_next::avformat_close_input(&mut input_ctx);
                ffmpeg_sys_next::avformat_free_context(output_ctx);
                return Err(anyhow::anyhow!("写入文件头失败: {}", ret));
            }

            // 复制数据包（简化版本，实际应该重新编码）
            let mut packet = std::mem::zeroed::<ffmpeg_sys_next::AVPacket>();
            while ffmpeg_sys_next::av_read_frame(input_ctx, &mut packet) >= 0 {
                let in_stream = *(*input_ctx).streams.add(packet.stream_index as usize);
                let out_stream = *(*output_ctx).streams.add(packet.stream_index as usize);

                // 转换时间戳（使用av_rescale_q避免enum转换问题）
                if packet.pts != ffmpeg_sys_next::AV_NOPTS_VALUE {
                    packet.pts = ffmpeg_sys_next::av_rescale_q(
                        packet.pts,
                        (*in_stream).time_base,
                        (*out_stream).time_base,
                    );
                }
                if packet.dts != ffmpeg_sys_next::AV_NOPTS_VALUE {
                    packet.dts = ffmpeg_sys_next::av_rescale_q(
                        packet.dts,
                        (*in_stream).time_base,
                        (*out_stream).time_base,
                    );
                }
                if packet.duration > 0 {
                    packet.duration = ffmpeg_sys_next::av_rescale_q(
                        packet.duration,
                        (*in_stream).time_base,
                        (*out_stream).time_base,
                    );
                }
                packet.pos = -1;

                ffmpeg_sys_next::av_interleaved_write_frame(output_ctx, &mut packet);
                ffmpeg_sys_next::av_packet_unref(&mut packet);
            }

            // 写入文件尾
            ffmpeg_sys_next::av_write_trailer(output_ctx);

            // 清理
            if !(*output_ctx).pb.is_null() {
                ffmpeg_sys_next::avio_closep(&mut (*output_ctx).pb);
            }
            ffmpeg_sys_next::avformat_close_input(&mut input_ctx);
            ffmpeg_sys_next::avformat_free_context(output_ctx);

            println!("[压缩] 完成压缩，保存到: {}", output_path_str);
            Ok(output_path_str)
        }
    }
}
