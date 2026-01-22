/// 视频录制模块
use anyhow::{Context, Result};
use ffmpeg_sys_next::AVRounding::{AV_ROUND_NEAR_INF, AV_ROUND_PASS_MINMAX};
use std::ffi::CString;
use std::path::Path;
use std::ptr;

/// 视频格式
#[derive(Debug, Clone, Copy)]
pub enum VideoFormat {
    TS,
    FLV,
    MP4,
    MKV,
}

impl VideoFormat {
    pub fn as_str(&self) -> &str {
        match self {
            VideoFormat::TS => "mpegts",
            VideoFormat::FLV => "flv",
            VideoFormat::MP4 => "mp4",
            VideoFormat::MKV => "matroska",
        }
    }

    pub fn extension(&self) -> &str {
        match self {
            VideoFormat::TS => "ts",
            VideoFormat::FLV => "flv",
            VideoFormat::MP4 => "mp4",
            VideoFormat::MKV => "mkv",
        }
    }
}

/// 录制配置
#[derive(Debug, Clone)]
pub struct RecordConfig {
    /// 视频URL或本地路径
    pub input_url: String,
    /// 输出目录
    pub output_dir: String,
    /// 输出文件名（不含扩展名）
    pub output_filename: Option<String>,
    /// 视频格式
    pub format: VideoFormat,
    /// 最大帧率（0表示不限制）
    pub max_fps: u32,
    /// 最大录制时长（秒，0表示不限制）
    pub max_duration: u32,
    /// 视频比特率（kbps，0表示使用原始比特率）
    pub video_bitrate: u32,
    /// 音频比特率（kbps，0表示使用原始比特率）
    pub audio_bitrate: u32,
}

impl Default for RecordConfig {
    fn default() -> Self {
        Self {
            input_url: String::new(),
            output_dir: String::from("."),
            output_filename: None,
            format: VideoFormat::MP4,
            max_fps: 0,
            max_duration: 0,
            video_bitrate: 0,
            audio_bitrate: 0,
        }
    }
}

/// 视频录制器
pub struct VideoRecorder {
    config: RecordConfig,
}

impl VideoRecorder {
    /// 创建新的录制器
    pub fn new(config: RecordConfig) -> Result<Self> {
        // 验证输入URL
        if config.input_url.is_empty() {
            return Err(anyhow::anyhow!("输入URL不能为空"));
        }

        // 确保输出目录存在
        let output_path = Path::new(&config.output_dir);
        if !output_path.exists() {
            std::fs::create_dir_all(output_path).context("创建输出目录失败")?;
        }

        Ok(Self { config })
    }

    /// 开始录制
    pub fn start_recording(&self) -> Result<String> {
        crate::init_ffmpeg();

        unsafe {
            // 打开输入文件/流
            let input_url =
                CString::new(self.config.input_url.as_str()).context("无效的输入URL")?;

            let mut input_ctx: *mut ffmpeg_sys_next::AVFormatContext = ptr::null_mut();
            let ret = ffmpeg_sys_next::avformat_open_input(
                &mut input_ctx,
                input_url.as_ptr(),
                ptr::null_mut(),
                ptr::null_mut(),
            );

            if ret < 0 {
                return Err(anyhow::anyhow!("打开输入流失败: {}", ret));
            }

            // 获取流信息
            let ret = ffmpeg_sys_next::avformat_find_stream_info(input_ctx, ptr::null_mut());
            if ret < 0 {
                ffmpeg_sys_next::avformat_close_input(&mut input_ctx);
                return Err(anyhow::anyhow!("查找流信息失败: {}", ret));
            }

            // 生成输出文件名
            let output_filename = self.config.output_filename.clone().unwrap_or_else(|| {
                format!("record_{}", chrono::Local::now().format("%Y%m%d_%H%M%S"))
            });
            let output_path = Path::new(&self.config.output_dir).join(format!(
                "{}.{}",
                output_filename,
                self.config.format.extension()
            ));
            let output_path_str = output_path.to_string_lossy().to_string();

            // 创建输出上下文
            let output_format =
                CString::new(self.config.format.as_str()).context("无效的输出格式")?;
            let output_file = CString::new(output_path_str.as_str()).context("无效的输出路径")?;

            let mut output_ctx: *mut ffmpeg_sys_next::AVFormatContext = ptr::null_mut();
            let ret = ffmpeg_sys_next::avformat_alloc_output_context2(
                &mut output_ctx,
                ptr::null_mut(),
                output_format.as_ptr(),
                output_file.as_ptr(),
            );

            if ret < 0 || output_ctx.is_null() {
                ffmpeg_sys_next::avformat_close_input(&mut input_ctx);
                return Err(anyhow::anyhow!("创建输出上下文失败: {}", ret));
            }

            // 复制流
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

            // 读取并写入数据包
            let mut packet: ffmpeg_sys_next::AVPacket = unsafe { std::mem::zeroed() };

            let start_time = std::time::Instant::now();
            let mut frame_count = 0u64;

            loop {
                let ret = ffmpeg_sys_next::av_read_frame(input_ctx, &mut packet);
                if ret < 0 {
                    break;
                }

                // 检查是否超过最大时长
                if self.config.max_duration > 0 {
                    if start_time.elapsed().as_secs() >= self.config.max_duration as u64 {
                        ffmpeg_sys_next::av_packet_unref(&mut packet);
                        break;
                    }
                }

                let in_stream = *(*input_ctx).streams.add(packet.stream_index as usize);
                let out_stream = *(*output_ctx).streams.add(packet.stream_index as usize);

                // 转换时间戳（只转换有效时间戳）
                // 使用av_rescale_q而不是av_rescale_q_rnd避免enum转换问题
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

                // 写入数据包
                let ret = ffmpeg_sys_next::av_interleaved_write_frame(output_ctx, &mut packet);
                if ret < 0 {
                    ffmpeg_sys_next::av_packet_unref(&mut packet);
                    break;
                }

                ffmpeg_sys_next::av_packet_unref(&mut packet);
                frame_count += 1;
            }

            // 写入文件尾
            ffmpeg_sys_next::av_write_trailer(output_ctx);

            // 清理资源
            if !(*output_ctx).pb.is_null() {
                ffmpeg_sys_next::avio_closep(&mut (*output_ctx).pb);
            }
            ffmpeg_sys_next::avformat_close_input(&mut input_ctx);
            ffmpeg_sys_next::avformat_free_context(output_ctx);

            println!(
                "[录制] 完成录制，共{}帧，保存到: {}",
                frame_count, output_path_str
            );
            Ok(output_path_str)
        }
    }
}

// 添加chrono依赖
