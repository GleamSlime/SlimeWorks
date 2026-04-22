use serde::{Deserialize, Serialize};

/// 游戏状态枚举
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum GameStatus {
    NotStarted,
    Playing,
    Completed,
    OnHold,
    Dropped,
}

impl GameStatus {
    pub fn from_str(s: &str) -> Self {
        match s {
            "playing" => Self::Playing,
            "completed" => Self::Completed,
            "on_hold" => Self::OnHold,
            "dropped" => Self::Dropped,
            _ => Self::NotStarted,
        }
    }

    pub fn to_db_str(&self) -> &str {
        match self {
            Self::NotStarted => "not_started",
            Self::Playing => "playing",
            Self::Completed => "completed",
            Self::OnHold => "on_hold",
            Self::Dropped => "dropped",
        }
    }
}

/// 游戏信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Game {
    pub id: String,
    pub name: String,
    /// 封面本地路径
    pub cover_path: String,
    pub company: String,
    pub summary: String,
    /// 评分（10分制）
    pub rating: f64,
    /// 发售日期（字符串，如 "2020-01-01"）
    pub release_date: String,
    /// 默认可执行文件路径（桌面端启动用）
    pub path: String,
    /// 游戏状态（GameStatus 序列化字符串）
    pub status: String,
    /// 创建时间（Unix 时间戳秒）
    pub created_at: i64,
    /// 更新时间（Unix 时间戳秒）
    pub updated_at: i64,
    /// 最后游玩时间（Unix 时间戳秒，可选）
    pub last_played_at: Option<i64>,
    /// 总游玩时长（秒）
    pub total_play_time_sec: i64,
    /// 标签列表
    pub tags: Vec<String>,
    /// 所有可执行文件路径列表（批量导入时可能含多个 exe）
    pub exe_paths: Vec<String>,
    /// 游戏根目录路径
    pub game_dir: String,
}

/// 扫描目录得到的候选游戏条目
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScannedGame {
    /// 游戏根目录路径
    pub folder_path: String,
    /// 清理后的显示名（已去除版本号、括号等干扰字符）
    pub folder_name: String,
    /// 目录下发现的可执行文件路径列表
    pub exe_paths: Vec<String>,
}

/// 游戏库设置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameLibrarySettings {
    pub auto_track_play_time: bool,
    pub default_sort: String,
    pub auto_save: bool,
    pub enable_desktop_launch: bool,
}

/// 分类信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Category {
    pub id: String,
    pub name: String,
    pub emoji: String,
    /// 是否为系统分类（不可删除）
    pub is_system: bool,
    /// 该分类下游戏数量
    pub game_count: i64,
    pub created_at: i64,
}

/// 游玩会话记录
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlaySession {
    pub id: String,
    pub game_id: String,
    /// 会话开始时间（Unix 时间戳秒）
    pub start_time: i64,
    /// 会话结束时间（Unix 时间戳秒）
    pub end_time: i64,
    /// 会话时长（秒）
    pub duration_sec: i64,
}

/// 游戏进度记录
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameProgress {
    pub id: String,
    pub game_id: String,
    pub chapter: String,
    pub route: String,
    pub note: String,
    pub updated_at: i64,
}

/// 每日游玩时长
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DayPlayTime {
    /// 日期字符串，如 "2026-04-20"
    pub date: String,
    pub duration_sec: i64,
}

/// 统计数据
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameStats {
    /// 范围内总时长（秒）
    pub total_play_time_sec: i64,
    /// 今日时长（秒）
    pub today_play_time_sec: i64,
    /// 本周时长（秒）
    pub week_play_time_sec: i64,
    /// 会话次数
    pub session_count: i64,
    /// 日维度时间轴
    pub timeline: Vec<DayPlayTime>,
    /// 游戏维度汇总（游戏 id -> 时长秒）
    pub per_game: Vec<GameTimeSummary>,
}

/// 单个游戏时长汇总
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameTimeSummary {
    pub game_id: String,
    pub game_name: String,
    pub total_sec: i64,
}

/// 首页数据
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HomePageData {
    pub last_played_game: Option<Game>,
    pub today_play_time_sec: i64,
    pub week_play_time_sec: i64,
    pub total_games: i64,
    pub total_play_time_sec: i64,
}
