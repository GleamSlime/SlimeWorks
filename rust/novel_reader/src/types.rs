use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// 书籍格式
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum NovelFormat {
    Txt,
    Epub,
}

impl NovelFormat {
    pub fn from_extension(ext: &str) -> Option<Self> {
        match ext.to_lowercase().as_str() {
            "txt" => Some(NovelFormat::Txt),
            "epub" => Some(NovelFormat::Epub),
            _ => None,
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            NovelFormat::Txt => "txt",
            NovelFormat::Epub => "epub",
        }
    }
}

/// 书籍元数据
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NovelMetadata {
    /// 唯一ID
    pub id: String,
    /// 标题
    pub title: String,
    /// 作者
    pub author: Option<String>,
    /// 文件路径
    pub file_path: String,
    /// 格式
    pub format: NovelFormat,
    /// 文件大小（字节）
    pub file_size: u64,
    /// 最后修改时间
    pub modified_at: DateTime<Utc>,
    /// 是否收藏
    pub is_favorite: bool,
    /// 书籍标签
    pub tags: Vec<String>,
    /// 添加到库的时间
    pub added_at: DateTime<Utc>,
    /// 阅读进度（0.0 ~ 1.0）
    pub progress: f32,
    /// 阅读章节ID（如果有）
    pub current_chapter_id: Option<String>,
    /// 最后阅读时间
    pub last_read_at: Option<DateTime<Utc>>,
    /// 封面图片路径（如果有）
    pub cover_path: Option<String>,
    /// 所属文件夹ID（用于分组）
    pub folder_id: Option<String>,
    /// 自定义排序位置（数字越小越靠前）
    pub custom_order: Option<i32>,
    /// 书籍备注
    pub notes: Option<String>,
}

/// 书籍章节信息（主要用于 epub）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NovelChapter {
    /// 章节 ID
    pub id: String,
    /// 章节标题
    pub title: String,
    /// 章节在书中的索引
    pub index: usize,
    /// 章节内容（可能为空，按需加载）
    pub content: Option<String>,
}

/// 书籍内容
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NovelContent {
    /// 书籍ID
    pub novel_id: String,
    /// 章节列表（epub 有章节，txt 只有一个章节）
    pub chapters: Vec<NovelChapter>,
}

/// 搜索结果项
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchResult {
    /// 书籍ID
    pub novel_id: String,
    /// 书籍标题
    pub title: String,
    /// 匹配的内容片段（高亮显示）
    pub snippet: String,
    /// 章节标题
    pub chapter_title: Option<String>,
    /// 相关性评分
    pub score: f32,
}

/// 扫描进度
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScanProgress {
    /// 已扫描的文件数
    pub scanned: usize,
    /// 找到的书籍数
    pub found: usize,
    /// 当前正在处理的文件
    pub current_file: Option<String>,
}

/// 书籍文件夹
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NovelFolder {
    /// 文件夹ID
    pub id: String,
    /// 文件夹名称
    pub name: String,
    /// 创建时间
    pub created_at: DateTime<Utc>,
    /// 排序位置
    pub order: i32,
    /// 父文件夹ID（None 表示顶级文件夹）
    pub parent_id: Option<String>,
}
