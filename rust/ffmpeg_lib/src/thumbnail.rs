/// 视频缩略图提取模块
use anyhow::{Context, Result};
use ffmpeg_sys_next::AVCodecID::{AV_CODEC_ID_BMP, AV_CODEC_ID_MJPEG, AV_CODEC_ID_PNG};
use std::ffi::CString;
use std::path::Path;
use std::ptr;

/// 图片格式
#[derive(Debug, Clone, Copy)]
pub enum ImageFormat {
    JPEG,
    PNG,
    BMP,
}

impl ImageFormat {
    pub fn extension(&self) -> &str {
        match self {
            ImageFormat::JPEG => "jpg",
            ImageFormat::PNG => "png",
            ImageFormat::BMP => "bmp",
        }
    }

    pub fn codec_id(&self) -> ffmpeg_sys_next::AVCodecID {
        match self {
            ImageFormat::JPEG => AV_CODEC_ID_MJPEG,
            ImageFormat::PNG => AV_CODEC_ID_PNG,
            ImageFormat::BMP => AV_CODEC_ID_BMP,
        }
    }
}

/// 缩略图配置
#[derive(Debug, Clone)]
pub struct ThumbnailConfig {
    /// 视频URL或本地路径
    pub input_url: String,
    /// 输出目录
    pub output_dir: String,
    /// 输出文件名（不含扩展名，None则自动生成）
    pub output_filename: Option<String>,
    /// 图片格式
    pub format: ImageFormat,
    /// 图片质量 (1-100，仅JPEG有效)
    pub quality: u32,
    /// 目标宽度（0表示保持原始）
    pub width: u32,
    /// 目标高度（0表示保持原始）
    pub height: u32,
    /// 是否保存为临时文件
    pub use_temp: bool,
}

impl Default for ThumbnailConfig {
    fn default() -> Self {
        Self {
            input_url: String::new(),
            output_dir: String::from("."),
            output_filename: None,
            format: ImageFormat::JPEG,
            quality: 85,
            width: 0,
            height: 0,
            use_temp: false,
        }
    }
}

/// 视频缩略图提取器
pub struct VideoThumbnail {
    config: ThumbnailConfig,
}

impl VideoThumbnail {
    /// 创建新的缩略图提取器
    pub fn new(config: ThumbnailConfig) -> Result<Self> {
        if config.input_url.is_empty() {
            return Err(anyhow::anyhow!("输入URL不能为空"));
        }

        // 确保输出目录存在
        let output_dir = if config.use_temp {
            std::env::temp_dir().to_string_lossy().to_string()
        } else {
            config.output_dir.clone()
        };

        let output_path = Path::new(&output_dir);
        if !output_path.exists() {
            std::fs::create_dir_all(output_path).context("创建输出目录失败")?;
        }

        Ok(Self { config })
    }

    /// 提取第一帧作为缩略图
    pub fn extract_first_frame(&self) -> Result<String> {
        crate::init_ffmpeg();

        unsafe {
            // 打开输入文件
            let input_url =
                CString::new(self.config.input_url.as_str()).context("无效的输入URL")?;

            let mut format_ctx: *mut ffmpeg_sys_next::AVFormatContext = ptr::null_mut();
            let ret = ffmpeg_sys_next::avformat_open_input(
                &mut format_ctx,
                input_url.as_ptr(),
                ptr::null_mut(),
                ptr::null_mut(),
            );

            if ret < 0 {
                return Err(anyhow::anyhow!("打开输入文件失败: {}", ret));
            }

            // 查找流信息
            let ret = ffmpeg_sys_next::avformat_find_stream_info(format_ctx, ptr::null_mut());
            if ret < 0 {
                ffmpeg_sys_next::avformat_close_input(&mut format_ctx);
                return Err(anyhow::anyhow!("查找流信息失败: {}", ret));
            }

            // 查找视频流
            let video_stream_index = ffmpeg_sys_next::av_find_best_stream(
                format_ctx,
                ffmpeg_sys_next::AVMediaType::AVMEDIA_TYPE_VIDEO,
                -1,
                -1,
                ptr::null_mut(),
                0,
            );

            if video_stream_index < 0 {
                ffmpeg_sys_next::avformat_close_input(&mut format_ctx);
                return Err(anyhow::anyhow!("未找到视频流"));
            }

            let video_stream = *(*format_ctx).streams.add(video_stream_index as usize);
            let codecpar = (*video_stream).codecpar;

            // 查找解码器
            let codec = ffmpeg_sys_next::avcodec_find_decoder((*codecpar).codec_id);
            if codec.is_null() {
                ffmpeg_sys_next::avformat_close_input(&mut format_ctx);
                return Err(anyhow::anyhow!("未找到解码器"));
            }

            // 创建解码器上下文
            let codec_ctx = ffmpeg_sys_next::avcodec_alloc_context3(codec);
            if codec_ctx.is_null() {
                ffmpeg_sys_next::avformat_close_input(&mut format_ctx);
                return Err(anyhow::anyhow!("分配解码器上下文失败"));
            }

            let ret = ffmpeg_sys_next::avcodec_parameters_to_context(codec_ctx, codecpar);
            if ret < 0 {
                ffmpeg_sys_next::avcodec_free_context(&mut (codec_ctx as *mut _));
                ffmpeg_sys_next::avformat_close_input(&mut format_ctx);
                return Err(anyhow::anyhow!("复制解码器参数失败: {}", ret));
            }

            // 打开解码器
            let ret = ffmpeg_sys_next::avcodec_open2(codec_ctx, codec, ptr::null_mut());
            if ret < 0 {
                ffmpeg_sys_next::avcodec_free_context(&mut (codec_ctx as *mut _));
                ffmpeg_sys_next::avformat_close_input(&mut format_ctx);
                return Err(anyhow::anyhow!("打开解码器失败: {}", ret));
            }

            // 分配帧
            let frame = ffmpeg_sys_next::av_frame_alloc();
            if frame.is_null() {
                ffmpeg_sys_next::avcodec_free_context(&mut (codec_ctx as *mut _));
                ffmpeg_sys_next::avformat_close_input(&mut format_ctx);
                return Err(anyhow::anyhow!("分配帧失败"));
            }

            // 读取第一个视频帧
            let mut packet = std::mem::zeroed::<ffmpeg_sys_next::AVPacket>();
            let mut got_frame = false;

            while !got_frame {
                let ret = ffmpeg_sys_next::av_read_frame(format_ctx, &mut packet);
                if ret < 0 {
                    break;
                }

                if packet.stream_index == video_stream_index {
                    // 发送数据包到解码器
                    let ret = ffmpeg_sys_next::avcodec_send_packet(codec_ctx, &packet);
                    if ret >= 0 {
                        // 接收解码后的帧
                        let ret = ffmpeg_sys_next::avcodec_receive_frame(codec_ctx, frame);
                        if ret >= 0 {
                            got_frame = true;
                        }
                    }
                }

                ffmpeg_sys_next::av_packet_unref(&mut packet);
            }

            if !got_frame {
                ffmpeg_sys_next::av_frame_free(&mut (frame as *mut _));
                ffmpeg_sys_next::avcodec_free_context(&mut (codec_ctx as *mut _));
                ffmpeg_sys_next::avformat_close_input(&mut format_ctx);
                return Err(anyhow::anyhow!("无法读取视频帧"));
            }

            // 生成输出文件路径
            let output_dir = if self.config.use_temp {
                std::env::temp_dir().to_string_lossy().to_string()
            } else {
                self.config.output_dir.clone()
            };

            let output_filename = self.config.output_filename.clone().unwrap_or_else(|| {
                format!("thumbnail_{}", chrono::Local::now().format("%Y%m%d_%H%M%S"))
            });
            let output_path = Path::new(&output_dir).join(format!(
                "{}.{}",
                output_filename,
                self.config.format.extension()
            ));
            let output_path_str = output_path.to_string_lossy().to_string();

            // 保存帧为图片
            self.save_frame_as_image(frame, &output_path_str)?;

            // 清理资源
            ffmpeg_sys_next::av_frame_free(&mut (frame as *mut _));
            ffmpeg_sys_next::avcodec_free_context(&mut (codec_ctx as *mut _));
            ffmpeg_sys_next::avformat_close_input(&mut format_ctx);

            println!("[缩略图] 提取成功，保存到: {}", output_path_str);
            Ok(output_path_str)
        }
    }

    /// 保存帧为图片
    unsafe fn save_frame_as_image(
        &self,
        frame: *mut ffmpeg_sys_next::AVFrame,
        output_path: &str,
    ) -> Result<()> {
        // 查找图片编码器
        let codec = ffmpeg_sys_next::avcodec_find_encoder(self.config.format.codec_id());
        if codec.is_null() {
            return Err(anyhow::anyhow!("未找到图片编码器"));
        }

        // 创建编码器上下文
        let codec_ctx = ffmpeg_sys_next::avcodec_alloc_context3(codec);
        if codec_ctx.is_null() {
            return Err(anyhow::anyhow!("分配编码器上下文失败"));
        }

        // 设置编码参数
        let width = if self.config.width > 0 {
            self.config.width as i32
        } else {
            (*frame).width
        };
        let height = if self.config.height > 0 {
            self.config.height as i32
        } else {
            (*frame).height
        };

        (*codec_ctx).width = width;
        (*codec_ctx).height = height;
        (*codec_ctx).time_base = ffmpeg_sys_next::AVRational { num: 1, den: 1 };
        
        // 根据图片格式设置像素格式
        (*codec_ctx).pix_fmt = match self.config.format {
            ImageFormat::JPEG => ffmpeg_sys_next::AVPixelFormat::AV_PIX_FMT_YUVJ420P,
            ImageFormat::PNG => ffmpeg_sys_next::AVPixelFormat::AV_PIX_FMT_RGB24,
            ImageFormat::BMP => ffmpeg_sys_next::AVPixelFormat::AV_PIX_FMT_BGR24,
        };

        // JPEG质量设置
        if matches!(self.config.format, ImageFormat::JPEG) {
            (*codec_ctx).flags |= ffmpeg_sys_next::AV_CODEC_FLAG_QSCALE as i32;
            (*codec_ctx).global_quality = ffmpeg_sys_next::FF_QP2LAMBDA as i32 * 2;
        }

        // 打开编码器
        let ret = ffmpeg_sys_next::avcodec_open2(codec_ctx, codec, ptr::null_mut());
        if ret < 0 {
            ffmpeg_sys_next::avcodec_free_context(&mut (codec_ctx as *mut _));
            return Err(anyhow::anyhow!("打开编码器失败: {}", ret));
        }

        // 创建输出包
        let mut packet = std::mem::zeroed::<ffmpeg_sys_next::AVPacket>();

        // 发送帧到编码器
        let ret = ffmpeg_sys_next::avcodec_send_frame(codec_ctx, frame);
        if ret < 0 {
            ffmpeg_sys_next::avcodec_free_context(&mut (codec_ctx as *mut _));
            return Err(anyhow::anyhow!("发送帧到编码器失败: {}", ret));
        }

        // 接收编码后的包
        let ret = ffmpeg_sys_next::avcodec_receive_packet(codec_ctx, &mut packet);
        if ret < 0 {
            ffmpeg_sys_next::avcodec_free_context(&mut (codec_ctx as *mut _));
            return Err(anyhow::anyhow!("接收编码包失败: {}", ret));
        }

        // 写入文件
        let output_file = CString::new(output_path).context("无效的输出路径")?;
        let file = libc::fopen(output_file.as_ptr(), b"wb\0".as_ptr() as *const i8);
        if file.is_null() {
            ffmpeg_sys_next::av_packet_unref(&mut packet);
            ffmpeg_sys_next::avcodec_free_context(&mut (codec_ctx as *mut _));
            return Err(anyhow::anyhow!("打开输出文件失败"));
        }

        libc::fwrite(packet.data as *const _, 1, packet.size as usize, file);
        libc::fclose(file);

        // 清理
        ffmpeg_sys_next::av_packet_unref(&mut packet);
        ffmpeg_sys_next::avcodec_free_context(&mut (codec_ctx as *mut _));

        Ok(())
    }
}
