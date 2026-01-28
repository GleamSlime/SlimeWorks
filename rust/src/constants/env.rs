pub struct Env;

#[rustfmt::skip]
impl Env {
    #[cfg(target_os = "windows")]
    pub const CAPTURE_PROXY_URL: &str = "http://127.0.0.1:5500/rust/target/release/capture_proxy.dll";
    #[cfg(target_os = "macos")]
    pub const CAPTURE_PROXY_URL: &str = "http://127.0.0.1:5500/rust/target/release/libcapture_proxy.dylib";

    #[cfg(target_os = "windows")]
    pub const FFMPEG_URL: &str = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip";
    #[cfg(target_os = "macos")]
    pub const FFMPEG_URL: &str = "https://evermeet.cx/ffmpeg/ffmpeg-8.1.zip";
}
