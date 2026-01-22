/// FFmpeg视频处理API - Flutter Rust Bridge接口
use flutter_rust_bridge::frb;

/// 视频录制配置
#[derive(Debug, Clone)]
pub struct VideoRecordConfig {
    pub input_url: String,
    pub output_dir: String,
    pub output_filename: Option<String>,
    pub format: String, // "ts", "flv", "mp4", "mkv"
    pub max_fps: u32,
    pub max_duration: u32,
    pub video_bitrate: u32,
    pub audio_bitrate: u32,
}

/// 缩略图配置
#[derive(Debug, Clone)]
pub struct VideoThumbnailConfig {
    pub input_url: String,
    pub output_dir: String,
    pub output_filename: Option<String>,
    pub format: String, // "jpg", "png", "bmp"
    pub quality: u32,
    pub width: u32,
    pub height: u32,
    pub use_temp: bool,
}

/// 视频压缩配置
#[derive(Debug, Clone)]
pub struct VideoCompressConfig {
    pub input_path: String,
    pub output_dir: String,
    pub output_filename: Option<String>,
    pub codec: String, // "h264", "h265", "vp9", "av1"
    pub use_hardware_accel: bool,
    pub bitrate: u32,
    pub crf: u32,
    pub preset: String, // "ultrafast", "fast", "medium", "slow", etc.
    pub width: u32,
    pub height: u32,
    pub fps: u32,
    pub audio_bitrate: u32,
}

/// 录制视频
#[frb(sync)]
pub fn record_video(config: VideoRecordConfig) -> Result<String, String> {
    let format = match config.format.as_str() {
        "ts" => ffmpeg_lib::VideoFormat::TS,
        "flv" => ffmpeg_lib::VideoFormat::FLV,
        "mp4" => ffmpeg_lib::VideoFormat::MP4,
        "mkv" => ffmpeg_lib::VideoFormat::MKV,
        _ => ffmpeg_lib::VideoFormat::MP4,
    };

    let record_config = ffmpeg_lib::RecordConfig {
        input_url: config.input_url,
        output_dir: config.output_dir,
        output_filename: config.output_filename,
        format,
        max_fps: config.max_fps,
        max_duration: config.max_duration,
        video_bitrate: config.video_bitrate,
        audio_bitrate: config.audio_bitrate,
    };

    let recorder = ffmpeg_lib::VideoRecorder::new(record_config)
        .map_err(|e| e.to_string())?;
    
    recorder.start_recording()
        .map_err(|e| e.to_string())
}

/// 提取视频缩略图
#[frb(sync)]
pub fn extract_video_thumbnail(config: VideoThumbnailConfig) -> Result<String, String> {
    let format = match config.format.as_str() {
        "jpg" | "jpeg" => ffmpeg_lib::ImageFormat::JPEG,
        "png" => ffmpeg_lib::ImageFormat::PNG,
        "bmp" => ffmpeg_lib::ImageFormat::BMP,
        _ => ffmpeg_lib::ImageFormat::JPEG,
    };

    let thumbnail_config = ffmpeg_lib::ThumbnailConfig {
        input_url: config.input_url,
        output_dir: config.output_dir,
        output_filename: config.output_filename,
        format,
        quality: config.quality,
        width: config.width,
        height: config.height,
        use_temp: config.use_temp,
    };

    let thumbnail = ffmpeg_lib::VideoThumbnail::new(thumbnail_config)
        .map_err(|e| e.to_string())?;
    
    thumbnail.extract_first_frame()
        .map_err(|e| e.to_string())
}

/// 压缩视频
#[frb(sync)]
pub fn compress_video(config: VideoCompressConfig) -> Result<String, String> {
    let codec = match config.codec.as_str() {
        "h264" => ffmpeg_lib::VideoCodec::H264,
        "h265" => ffmpeg_lib::VideoCodec::H265,
        "vp9" => ffmpeg_lib::VideoCodec::VP9,
        "av1" => ffmpeg_lib::VideoCodec::AV1,
        _ => ffmpeg_lib::VideoCodec::H264,
    };

    let preset = match config.preset.as_str() {
        "ultrafast" => ffmpeg_lib::Preset::UltraFast,
        "superfast" => ffmpeg_lib::Preset::SuperFast,
        "veryfast" => ffmpeg_lib::Preset::VeryFast,
        "faster" => ffmpeg_lib::Preset::Faster,
        "fast" => ffmpeg_lib::Preset::Fast,
        "medium" => ffmpeg_lib::Preset::Medium,
        "slow" => ffmpeg_lib::Preset::Slow,
        "slower" => ffmpeg_lib::Preset::Slower,
        "veryslow" => ffmpeg_lib::Preset::VerySlow,
        _ => ffmpeg_lib::Preset::Medium,
    };

    let compress_config = ffmpeg_lib::CompressConfig {
        input_path: config.input_path,
        output_dir: config.output_dir,
        output_filename: config.output_filename,
        codec,
        use_hardware_accel: config.use_hardware_accel,
        bitrate: config.bitrate,
        crf: config.crf,
        preset,
        width: config.width,
        height: config.height,
        fps: config.fps,
        audio_bitrate: config.audio_bitrate,
    };

    let compressor = ffmpeg_lib::VideoCompressor::new(compress_config)
        .map_err(|e| e.to_string())?;
    
    compressor.compress()
        .map_err(|e| e.to_string())
}

/// 初始化FFmpeg（可选，会自动调用）
#[frb(sync)]
pub fn init_ffmpeg() {
    ffmpeg_lib::init_ffmpeg();
}
