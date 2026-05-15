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
    /// macOS 下使用 `open` 命令启动游戏（适用于非 .app 的 Wine/Crossover 包装）
    #[serde(default)]
    pub use_open_on_macos: bool,
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn game_status_from_str_known() {
        assert_eq!(GameStatus::from_str("playing"), GameStatus::Playing);
        assert_eq!(GameStatus::from_str("completed"), GameStatus::Completed);
        assert_eq!(GameStatus::from_str("on_hold"), GameStatus::OnHold);
        assert_eq!(GameStatus::from_str("dropped"), GameStatus::Dropped);
        assert_eq!(GameStatus::from_str("not_started"), GameStatus::NotStarted);
    }

    #[test]
    fn game_status_from_str_unknown_defaults_to_not_started() {
        assert_eq!(GameStatus::from_str("unknown"), GameStatus::NotStarted);
        assert_eq!(GameStatus::from_str(""), GameStatus::NotStarted);
        assert_eq!(GameStatus::from_str("random"), GameStatus::NotStarted);
    }

    #[test]
    fn game_status_to_db_str_round_trip() {
        for status in &[
            GameStatus::NotStarted,
            GameStatus::Playing,
            GameStatus::Completed,
            GameStatus::OnHold,
            GameStatus::Dropped,
        ] {
            let db_str = status.to_db_str();
            let restored = GameStatus::from_str(db_str);
            assert_eq!(&restored, status);
        }
    }

    #[test]
    fn game_status_serde_round_trip() {
        for status in &[
            GameStatus::NotStarted,
            GameStatus::Playing,
            GameStatus::Completed,
            GameStatus::OnHold,
            GameStatus::Dropped,
        ] {
            let json = serde_json::to_string(status).expect("serialize");
            let restored: GameStatus = serde_json::from_str(&json).expect("deserialize");
            assert_eq!(&restored, status);
        }
    }

    #[test]
    fn scanned_game_serde_round_trip() {
        let game = ScannedGame {
            folder_path: "/games/rpg".to_string(),
            folder_name: "RPG Game".to_string(),
            exe_paths: vec!["/games/rpg/game.exe".to_string()],
        };
        let json = serde_json::to_string(&game).expect("serialize");
        let restored: ScannedGame = serde_json::from_str(&json).expect("deserialize");
        assert_eq!(restored.folder_path, game.folder_path);
        assert_eq!(restored.folder_name, game.folder_name);
        assert_eq!(restored.exe_paths, game.exe_paths);
    }

    #[test]
    fn day_play_time_serde_round_trip() {
        let day = DayPlayTime {
            date: "2026-04-20".to_string(),
            duration_sec: 3600,
        };
        let json = serde_json::to_string(&day).expect("serialize");
        let restored: DayPlayTime = serde_json::from_str(&json).expect("deserialize");
        assert_eq!(restored.date, day.date);
        assert_eq!(restored.duration_sec, day.duration_sec);
    }

    #[test]
    fn category_serde_round_trip() {
        let cat = Category {
            id: "cat-001".to_string(),
            name: "RPG".to_string(),
            emoji: "🎮".to_string(),
            is_system: false,
            game_count: 5,
            created_at: 1700000000,
        };
        let json = serde_json::to_string(&cat).expect("serialize");
        let restored: Category = serde_json::from_str(&json).expect("deserialize");
        assert_eq!(restored.id, cat.id);
        assert_eq!(restored.emoji, cat.emoji);
        assert_eq!(restored.is_system, cat.is_system);
    }

    #[test]
    fn play_session_serde_round_trip() {
        let session = PlaySession {
            id: "ps-001".to_string(),
            game_id: "g-001".to_string(),
            start_time: 1700000000,
            end_time: 1700003600,
            duration_sec: 3600,
        };
        let json = serde_json::to_string(&session).expect("serialize");
        let restored: PlaySession = serde_json::from_str(&json).expect("deserialize");
        assert_eq!(restored.duration_sec, 3600);
    }
}
