/// FFmpeg 视频处理 API
///
/// 提供视频元数据提取、缩略图生成等功能
/// 自动从配置的 URL 下载 FFmpeg 可执行文件
use lazy_static::lazy_static;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::process::Command;
use std::sync::Mutex;

use super::module_downloader::{ModuleConfig, ModuleDownloader};

lazy_static! {
    static ref FFMPEG_MANAGER: Mutex<Option<FFmpegManager>> = Mutex::new(None);
}

/// 视频元数据
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoMetadata {
    pub duration: f64,   // 时长（秒）
    pub width: u32,      // 宽度
    pub height: u32,     // 高度
    pub frame_rate: f64, // 帧率
    pub bit_rate: u64,   // 比特率（bps）
    pub codec: String,   // 编码格式
    pub file_size: u64,  // 文件大小（字节）
}

/// FFmpeg 配置
#[derive(Debug, Clone)]
pub struct FFmpegConfig {
    pub windows_url: String,
    pub macos_url: String,
    pub install_dir: String,
}

/// FFmpeg 管理器
pub struct FFmpegManager {
    downloader: ModuleDownloader,
    config: FFmpegConfig,
    ffmpeg_path: Option<String>,
    ffprobe_path: Option<String>,
}

impl FFmpegManager {
    /// 创建 FFmpeg 管理器
    pub fn new(config: FFmpegConfig) -> Self {
        let downloader = ModuleDownloader::new(PathBuf::from(&config.install_dir));

        Self {
            downloader,
            config,
            ffmpeg_path: None,
            ffprobe_path: None,
        }
    }

    /// 初始化 FFmpeg（如果需要则下载）
    pub async fn initialize(&mut self) -> Result<(), String> {
        // 检查是否已安装 FFmpeg
        if self.downloader.is_module_installed("ffmpeg", "ffmpeg")
            && self.downloader.is_module_installed("ffmpeg", "ffprobe")
        {
            self.ffmpeg_path = Some(
                self.downloader
                    .get_executable_path("ffmpeg", "ffmpeg")
                    .to_string_lossy()
                    .to_string(),
            );
            self.ffprobe_path = Some(
                self.downloader
                    .get_executable_path("ffmpeg", "ffprobe")
                    .to_string_lossy()
                    .to_string(),
            );
            return Ok(());
        }

        // 下载 FFmpeg
        let module_config = ModuleConfig {
            name: "ffmpeg".to_string(),
            windows_url: self.config.windows_url.clone(),
            macos_url: self.config.macos_url.clone(),
            executable_name: "ffmpeg".to_string(),
        };

        let ffmpeg_path = self.downloader.download_module(&module_config).await?;
        self.ffmpeg_path = Some(ffmpeg_path.to_string_lossy().to_string());

        // FFprobe 通常和 FFmpeg 在同一目录
        self.ffprobe_path = Some(
            self.downloader
                .get_executable_path("ffmpeg", "ffprobe")
                .to_string_lossy()
                .to_string(),
        );

        Ok(())
    }

    /// 获取 FFmpeg 可执行文件路径
    fn get_ffmpeg_path(&self) -> Result<&str, String> {
        self.ffmpeg_path
            .as_ref()
            .map(|s| s.as_str())
            .ok_or_else(|| "FFmpeg not initialized".to_string())
    }

    /// 获取 FFprobe 可执行文件路径
    fn get_ffprobe_path(&self) -> Result<&str, String> {
        self.ffprobe_path
            .as_ref()
            .map(|s| s.as_str())
            .ok_or_else(|| "FFprobe not initialized".to_string())
    }

    /// 获取视频元数据
    pub fn get_metadata(&self, video_path: &str) -> Result<VideoMetadata, String> {
        let ffprobe_path = self.get_ffprobe_path()?;

        // 使用 ffprobe 获取 JSON 格式的视频信息
        let output = Command::new(ffprobe_path)
            .args(&[
                "-v",
                "quiet",
                "-print_format",
                "json",
                "-show_format",
                "-show_streams",
                video_path,
            ])
            .output()
            .map_err(|e| format!("Failed to execute ffprobe: {}", e))?;

        if !output.status.success() {
            let error = String::from_utf8_lossy(&output.stderr);
            return Err(format!("ffprobe failed: {}", error));
        }

        // 解析 JSON 输出
        let output_str = String::from_utf8_lossy(&output.stdout);
        let json: serde_json::Value = serde_json::from_str(&output_str)
            .map_err(|e| format!("Failed to parse ffprobe output: {}", e))?;

        // 提取视频流信息
        let streams = json["streams"].as_array().ok_or("No streams found")?;

        let video_stream = streams
            .iter()
            .find(|s| s["codec_type"] == "video")
            .ok_or("No video stream found")?;

        // 提取元数据
        let width = video_stream["width"].as_u64().unwrap_or(0) as u32;
        let height = video_stream["height"].as_u64().unwrap_or(0) as u32;
        let codec = video_stream["codec_name"]
            .as_str()
            .unwrap_or("unknown")
            .to_string();

        // 计算帧率
        let frame_rate = if let Some(r_frame_rate) = video_stream["r_frame_rate"].as_str() {
            parse_frame_rate(r_frame_rate)
        } else {
            0.0
        };

        // 获取格式信息
        let format = &json["format"];
        let duration = format["duration"]
            .as_str()
            .and_then(|s| s.parse::<f64>().ok())
            .unwrap_or(0.0);

        let bit_rate = format["bit_rate"]
            .as_str()
            .and_then(|s| s.parse::<u64>().ok())
            .unwrap_or(0);

        let file_size = format["size"]
            .as_str()
            .and_then(|s| s.parse::<u64>().ok())
            .unwrap_or(0);

        Ok(VideoMetadata {
            duration,
            width,
            height,
            frame_rate,
            bit_rate,
            codec,
            file_size,
        })
    }

    /// 生成视频缩略图（第一帧）
    pub fn generate_thumbnail(&self, video_url: &str, output_path: &str) -> Result<String, String> {
        let ffmpeg_path = self.get_ffmpeg_path()?;
        let output_path_buf = PathBuf::from(output_path);

        // 确保输出目录存在
        if let Some(parent) = output_path_buf.parent() {
            std::fs::create_dir_all(parent)
                .map_err(|e| format!("Failed to create output directory: {}", e))?;
        }

        // 使用 ffmpeg 提取第一帧
        let output = Command::new(ffmpeg_path)
            .args(&[
                "-i",
                video_url, // 输入文件
                "-ss",
                "00:00:00", // 从开始位置
                "-vframes",
                "1", // 只提取一帧
                "-q:v",
                "2",  // 高质量
                "-y", // 覆盖已存在的文件
                output_path,
            ])
            .output()
            .map_err(|e| format!("Failed to execute ffmpeg: {}", e))?;

        if !output.status.success() {
            let error = String::from_utf8_lossy(&output.stderr);
            return Err(format!("ffmpeg failed: {}", error));
        }

        Ok(output_path.to_string())
    }
}

/// 解析帧率字符串（如 "30/1" -> 30.0）
fn parse_frame_rate(rate_str: &str) -> f64 {
    let parts: Vec<&str> = rate_str.split('/').collect();
    if parts.len() == 2 {
        if let (Ok(num), Ok(den)) = (parts[0].parse::<f64>(), parts[1].parse::<f64>()) {
            if den != 0.0 {
                return num / den;
            }
        }
    }
    0.0
}

// ========== Flutter Rust Bridge 导出函数 ==========

/// 初始化 FFmpeg
///
/// # Arguments
/// * `windows_url` - Windows FFmpeg 下载 URL（从 .env 读取）
/// * `macos_url` - macOS FFmpeg 下载 URL（从 .env 读取）
/// * `install_dir` - 安装目录路径
pub async fn initialize_ffmpeg(
    windows_url: String,
    macos_url: String,
    install_dir: String,
) -> Result<String, String> {
    let config = FFmpegConfig {
        windows_url,
        macos_url,
        install_dir,
    };

    let mut manager = FFmpegManager::new(config);
    manager.initialize().await?;

    // 保存到全局变量
    let mut global_manager = FFMPEG_MANAGER
        .lock()
        .map_err(|e| format!("Failed to lock FFmpeg manager: {}", e))?;
    *global_manager = Some(manager);

    Ok("FFmpeg initialized successfully".to_string())
}

/// 获取视频元数据
///
/// # Arguments
/// * `video_path` - 视频文件路径或 URL
pub fn get_video_metadata(video_path: String) -> Result<VideoMetadata, String> {
    let manager = FFMPEG_MANAGER
        .lock()
        .map_err(|e| format!("Failed to lock FFmpeg manager: {}", e))?;

    let manager = manager
        .as_ref()
        .ok_or("FFmpeg not initialized. Call initialize_ffmpeg first")?;

    manager.get_metadata(&video_path)
}

/// 生成视频缩略图
///
/// # Arguments
/// * `video_url` - 视频 URL
/// * `cache_dir` - 系统缓存目录路径
///
/// # Returns
/// 生成的缩略图文件路径
pub fn generate_video_thumbnail(video_url: String, cache_dir: String) -> Result<String, String> {
    let manager = FFMPEG_MANAGER
        .lock()
        .map_err(|e| format!("Failed to lock FFmpeg manager: {}", e))?;

    let manager = manager
        .as_ref()
        .ok_or("FFmpeg not initialized. Call initialize_ffmpeg first")?;

    // 生成唯一的文件名
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};

    let mut hasher = DefaultHasher::new();
    video_url.hash(&mut hasher);
    let hash = hasher.finish();

    let cache_path = PathBuf::from(cache_dir);
    let thumbnail_path = cache_path.join(format!("thumbnail_{}.jpg", hash));
    let thumbnail_path_str = thumbnail_path.to_string_lossy().to_string();

    manager.generate_thumbnail(&video_url, &thumbnail_path_str)
}

/// 检查 FFmpeg 是否已安装
pub fn is_ffmpeg_installed(install_dir: String) -> bool {
    let downloader = ModuleDownloader::new(PathBuf::from(install_dir));
    downloader.is_module_installed("ffmpeg", "ffmpeg")
}

/// 获取 FFmpeg 版本信息
pub fn get_ffmpeg_version(install_dir: String) -> Result<String, String> {
    let downloader = ModuleDownloader::new(PathBuf::from(install_dir));
    downloader.get_module_version("ffmpeg", "ffmpeg")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_frame_rate() {
        assert_eq!(parse_frame_rate("30/1"), 30.0);
        assert_eq!(parse_frame_rate("60/1"), 60.0);
        assert_eq!(parse_frame_rate("24000/1001"), 23.976023976023978);
        assert_eq!(parse_frame_rate("invalid"), 0.0);
    }
}
