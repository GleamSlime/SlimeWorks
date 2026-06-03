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

/// 正则匹配目标字段
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SmartFolderRegexTarget {
    /// 匹配集合名称与集合路径
    #[serde(rename = "collectionName")]
    CollectionName,
    /// 匹配集合内媒体文件的文件名
    #[serde(rename = "fileName")]
    FileName,
}

impl SmartFolderRegexTarget {
    pub fn as_str(&self) -> &'static str {
        match self {
            SmartFolderRegexTarget::CollectionName => "collectionName",
            SmartFolderRegexTarget::FileName => "fileName",
        }
    }

    pub fn from_str_name(name: &str) -> Self {
        match name {
            "fileName" => SmartFolderRegexTarget::FileName,
            _ => SmartFolderRegexTarget::CollectionName,
        }
    }
}

/// 文件类型过滤（仅 regexTarget == FileName 时生效）
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SmartFolderFileType {
    #[serde(rename = "all")]
    All,
    #[serde(rename = "images")]
    Images,
    #[serde(rename = "videos")]
    Videos,
}

impl SmartFolderFileType {
    pub fn as_str(&self) -> &'static str {
        match self {
            SmartFolderFileType::All => "all",
            SmartFolderFileType::Images => "images",
            SmartFolderFileType::Videos => "videos",
        }
    }

    pub fn from_str_name(name: &str) -> Self {
        match name {
            "images" => SmartFolderFileType::Images,
            "videos" => SmartFolderFileType::Videos,
            _ => SmartFolderFileType::All,
        }
    }
}

/// 智能文件夹：使用正则/关键词过滤媒体集合的虚拟文件夹
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SmartFolder {
    pub id: String,
    pub name: String,
    /// 正则匹配规则
    pub regex_pattern: String,
    /// 关键词列表
    pub keywords: Vec<String>,
    /// 正则匹配目标
    pub regex_target: SmartFolderRegexTarget,
    /// 文件类型过滤
    pub file_type_filter: SmartFolderFileType,
    /// 目标文件夹 ID 列表，空=全部
    pub target_folder_ids: Vec<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn smart_folder_serde_roundtrip() {
        let sf = SmartFolder {
            id: "sf_1".to_string(),
            name: "测试".to_string(),
            regex_pattern: "关键词".to_string(),
            keywords: vec!["k1".to_string(), "k2".to_string()],
            regex_target: SmartFolderRegexTarget::CollectionName,
            file_type_filter: SmartFolderFileType::All,
            target_folder_ids: vec!["folder_1".to_string()],
        };
        let json = serde_json::to_string(&sf).expect("serialize");
        let restored: SmartFolder = serde_json::from_str(&json).expect("deserialize");
        assert_eq!(restored.id, sf.id);
        assert_eq!(restored.name, sf.name);
        assert_eq!(restored.keywords, sf.keywords);
        assert_eq!(restored.regex_target, sf.regex_target);
    }

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
