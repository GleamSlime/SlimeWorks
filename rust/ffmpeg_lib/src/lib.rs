mod compressor;
/// FFmpeg 库 - 视频录制、封面提取、压缩功能
mod recorder;
mod thumbnail;

pub use compressor::{CompressConfig, Platform, Preset, VideoCodec, VideoCompressor};
pub use recorder::{RecordConfig, VideoFormat, VideoRecorder};
pub use thumbnail::{ImageFormat, ThumbnailConfig, VideoThumbnail};

use std::sync::Once;

static INIT: Once = Once::new();

/// 初始化FFmpeg（全局只需调用一次）
pub fn init_ffmpeg() {
    INIT.call_once(|| {
        unsafe {
            // FFmpeg 4.0+不需要显式注册
            // av_register_all() 和 avformat_network_init() 已被废弃
            ffmpeg_sys_next::avformat_network_init();
        }
    });
}
