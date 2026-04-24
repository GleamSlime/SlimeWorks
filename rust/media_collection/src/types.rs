use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum MediaKind {
    Image,
    Video,
    Audio,
}

impl MediaKind {
    pub fn from_extension(ext: &str) -> Option<Self> {
        match ext.to_ascii_lowercase().as_str() {
            "jpg" | "jpeg" | "jfif" | "png" | "gif" | "webp" | "bmp" | "avif" | "heic" | "heif"
            | "tif" | "tiff" => Some(MediaKind::Image),
            "mp4" | "mov" | "m4v" | "mkv" | "avi" | "webm" | "wmv" | "flv" | "ts" => {
                Some(MediaKind::Video)
            }
            "mp3" | "flac" | "aac" | "m4a" | "ogg" | "opus" | "wav" | "wma" | "ape" | "aiff"
            | "alac" => Some(MediaKind::Audio),
            _ => None,
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            MediaKind::Image => "image",
            MediaKind::Video => "video",
            MediaKind::Audio => "audio",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MediaCollection {
    pub id: String,
    pub title: String,
    pub folder_path: String,
    pub folder_id: Option<String>,
    pub cover_path: Option<String>,
    pub item_count: usize,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MediaFolder {
    pub id: String,
    pub name: String,
    pub created_at: DateTime<Utc>,
    pub order: i32,
    pub parent_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MediaItem {
    pub id: String,
    pub collection_id: String,
    pub title: String,
    pub file_path: String,
    pub kind: MediaKind,
    pub file_size: u64,
    pub modified_at: DateTime<Utc>,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub duration_ms: Option<u64>,
    pub order: i32,
}

/// 智能文件夹（虚拟过滤规则，不存储实际文件）。
/// JSON 字段名使用 camelCase 以与 Dart 端及节点服务器保持兼容。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SmartFolder {
    pub id: String,
    pub name: String,
    /// 正则表达式（空字符串表示不过滤）
    pub regex_pattern: String,
    /// 匹配目标：collectionName | fileName
    pub regex_target: String,
    /// 文件类型过滤：all | images | videos
    pub file_type_filter: String,
    /// 目标文件夹 ID 列表（空 = 匹配所有文件夹）
    pub target_folder_ids: Vec<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    // ── MediaKind::from_extension ──────────────────────────────────────────

    #[test]
    fn image_extensions_map_to_image_kind() {
        for ext in &[
            "jpg", "jpeg", "jfif", "png", "gif", "webp", "bmp", "avif", "heic", "heif", "tif",
            "tiff",
        ] {
            assert_eq!(
                MediaKind::from_extension(ext),
                Some(MediaKind::Image),
                "Extension '{ext}' should map to Image"
            );
        }
    }

    #[test]
    fn video_extensions_map_to_video_kind() {
        for ext in &[
            "mp4", "mov", "m4v", "mkv", "avi", "webm", "wmv", "flv", "ts",
        ] {
            assert_eq!(
                MediaKind::from_extension(ext),
                Some(MediaKind::Video),
                "Extension '{ext}' should map to Video"
            );
        }
    }

    #[test]
    fn audio_extensions_map_to_audio_kind() {
        for ext in &[
            "mp3", "flac", "aac", "m4a", "ogg", "opus", "wav", "wma", "ape", "aiff", "alac",
        ] {
            assert_eq!(
                MediaKind::from_extension(ext),
                Some(MediaKind::Audio),
                "Extension '{ext}' should map to Audio"
            );
        }
    }

    #[test]
    fn unknown_extension_returns_none() {
        assert_eq!(MediaKind::from_extension("txt"), None);
        assert_eq!(MediaKind::from_extension("pdf"), None);
        assert_eq!(MediaKind::from_extension(""), None);
    }

    #[test]
    fn from_extension_is_case_insensitive() {
        assert_eq!(MediaKind::from_extension("JPG"), Some(MediaKind::Image));
        assert_eq!(MediaKind::from_extension("MP4"), Some(MediaKind::Video));
        assert_eq!(MediaKind::from_extension("FLAC"), Some(MediaKind::Audio));
    }

    // ── MediaKind::as_str ──────────────────────────────────────────────────

    #[test]
    fn as_str_returns_correct_labels() {
        assert_eq!(MediaKind::Image.as_str(), "image");
        assert_eq!(MediaKind::Video.as_str(), "video");
        assert_eq!(MediaKind::Audio.as_str(), "audio");
    }

    // ── Serde round-trip ───────────────────────────────────────────────────

    #[test]
    fn media_kind_serializes_and_deserializes() {
        for kind in &[MediaKind::Image, MediaKind::Video, MediaKind::Audio] {
            let json = serde_json::to_string(kind).expect("serialize");
            let restored: MediaKind = serde_json::from_str(&json).expect("deserialize");
            assert_eq!(&restored, kind);
        }
    }
}
