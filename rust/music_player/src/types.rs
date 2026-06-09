use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// 音乐播放模式
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum PlayMode {
    /// 顺序播放
    #[default]
    Sequential,
    /// 列表循环
    Loop,
    /// 单曲循环
    SingleLoop,
    /// 随机播放
    Shuffle,
}

impl PlayMode {
    pub fn as_str(&self) -> &'static str {
        match self {
            PlayMode::Sequential => "sequential",
            PlayMode::Loop => "loop",
            PlayMode::SingleLoop => "single_loop",
            PlayMode::Shuffle => "shuffle",
        }
    }

    pub fn from_str_name(name: &str) -> Self {
        match name {
            "loop" => PlayMode::Loop,
            "single_loop" => PlayMode::SingleLoop,
            "shuffle" => PlayMode::Shuffle,
            _ => PlayMode::Sequential,
        }
    }
}

/// 音乐播放列表
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Playlist {
    pub id: String,
    pub name: String,
    pub cover_path: Option<String>,
    pub item_count: usize,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub is_default: bool,
    /// 所属目录 ID，null 表示根级
    pub folder_id: Option<String>,
}

/// 音乐条目
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MusicItem {
    pub id: String,
    pub playlist_id: String,
    pub title: String,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub file_path: String,
    pub duration_ms: Option<u64>,
    pub track_number: Option<u32>,
    pub disc_number: Option<u32>,
    pub year: Option<u32>,
    pub genre: Option<String>,
    pub cover_path: Option<String>,
    pub file_size: u64,
    pub modified_at: DateTime<Utc>,
    pub order: i32,
    pub is_favorite: bool,
}

/// CUE 音轨信息（从 .cue 文件解析）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CueTrack {
    pub title: String,
    pub performer: Option<String>,
    pub start_ms: u64,
    pub end_ms: Option<u64>,
    pub track_number: u32,
}

/// CUE 文件解析结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CueSheet {
    pub title: Option<String>,
    pub performer: Option<String>,
    pub audio_file: String,
    pub tracks: Vec<CueTrack>,
}

/// 最近播放记录
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlayRecord {
    pub id: String,
    pub music_id: String,
    pub played_at: DateTime<Utc>,
    pub play_count: u32,
}

/// 均衡器预设
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EqualizerPreset {
    pub id: String,
    pub name: String,
    /// 10 段均衡器增益值（dB），对应 32/64/125/250/500/1k/2k/4k/8k/16k Hz
    pub bands: Vec<f32>,
    pub is_builtin: bool,
}

/// 目录节点（最多三级）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Folder {
    pub id: String,
    pub name: String,
    /// 父目录 ID，根级为 None
    pub parent_id: Option<String>,
    /// 目录层级：1=根级，2=二级，3=三级
    pub level: u32,
    /// 目录封面路径
    pub cover_path: Option<String>,
    /// 标签（逗号分隔）
    pub tags: Option<String>,
    /// 作者/演唱者
    pub author: Option<String>,
    /// 目录下所有音乐的累计播放次数
    pub play_count: u32,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}
