use chrono::{DateTime, Utc};
use flutter_rust_bridge::frb;

// Dart 友好的类型定义（使用 i64 timestamp 代替 DateTime）
#[derive(Debug, Clone)]
pub struct NovelMetadata {
    pub id: String,
    pub title: String,
    pub author: Option<String>,
    pub file_path: String,
    pub format: NovelFormat,
    pub file_size: u64,
    pub modified_at: i64, // Unix timestamp (seconds)
    pub added_at: i64,    // Unix timestamp (seconds)
    pub progress: f32,
    pub last_read_at: Option<i64>, // Unix timestamp (seconds)
    pub cover_path: Option<String>,
}

#[derive(Debug, Clone)]
pub enum NovelFormat {
    Txt,
    Epub,
}

#[derive(Debug, Clone)]
pub struct NovelChapter {
    pub id: String,
    pub title: String,
    pub index: usize,
    pub content: Option<String>,
}

#[derive(Debug, Clone)]
pub struct NovelContent {
    pub novel_id: String,
    pub chapters: Vec<NovelChapter>,
}

#[derive(Debug, Clone)]
pub struct SearchMatch {
    pub chapter_index: usize,
    pub chapter_title: String,
    pub position: usize,
    pub snippet: String,
}

// 转换辅助函数
fn convert_metadata(meta: novel_reader::types::NovelMetadata) -> NovelMetadata {
    NovelMetadata {
        id: meta.id,
        title: meta.title,
        author: meta.author,
        file_path: meta.file_path,
        format: match meta.format {
            novel_reader::types::NovelFormat::Txt => NovelFormat::Txt,
            novel_reader::types::NovelFormat::Epub => NovelFormat::Epub,
        },
        file_size: meta.file_size,
        modified_at: meta.modified_at.timestamp(),
        added_at: meta.added_at.timestamp(),
        progress: meta.progress,
        last_read_at: meta.last_read_at.map(|dt| dt.timestamp()),
        cover_path: meta.cover_path,
    }
}

fn convert_chapter(chapter: novel_reader::types::NovelChapter) -> NovelChapter {
    NovelChapter {
        id: chapter.id,
        title: chapter.title,
        index: chapter.index,
        content: chapter.content,
    }
}

fn convert_content(content: novel_reader::types::NovelContent) -> NovelContent {
    NovelContent {
        novel_id: content.novel_id,
        chapters: content.chapters.into_iter().map(convert_chapter).collect(),
    }
}

fn convert_search_match(m: novel_reader::api::SearchMatch) -> SearchMatch {
    SearchMatch {
        chapter_index: m.chapter_index,
        chapter_title: m.chapter_title,
        position: m.position,
        snippet: m.snippet,
    }
}

/// 扫描文件夹获取小说列表
#[frb(sync)]
pub fn scan_novels_folder(folder_path: String) -> anyhow::Result<Vec<NovelMetadata>> {
    let novels = novel_reader::scan_novels_folder(folder_path).map_err(|e| anyhow::anyhow!(e))?;
    Ok(novels.into_iter().map(convert_metadata).collect())
}

/// 获取所有小说列表
#[frb(sync)]
pub fn get_all_novels() -> anyhow::Result<Vec<NovelMetadata>> {
    let novels = novel_reader::get_all_novels().map_err(|e| anyhow::anyhow!(e))?;
    Ok(novels.into_iter().map(convert_metadata).collect())
}

/// 添加单个小说
#[frb(sync)]
pub fn add_novel(file_path: String) -> anyhow::Result<NovelMetadata> {
    let novel = novel_reader::add_novel(file_path).map_err(|e| anyhow::anyhow!(e))?;
    Ok(convert_metadata(novel))
}

/// 从库中移除小说
#[frb(sync)]
pub fn remove_novel(novel_id: String) -> anyhow::Result<()> {
    novel_reader::remove_novel(novel_id).map_err(|e| anyhow::anyhow!(e))?;
    Ok(())
}

/// 获取小说的完整内容（包含所有章节）
pub fn get_novel_content(file_path: String) -> anyhow::Result<NovelContent> {
    let content = novel_reader::get_novel_content(file_path).map_err(|e| anyhow::anyhow!(e))?;
    Ok(convert_content(content))
}

/// 获取特定章节的内容
pub fn get_chapter_content(file_path: String, chapter_index: usize) -> anyhow::Result<String> {
    novel_reader::get_chapter_content(file_path, chapter_index).map_err(|e| anyhow::anyhow!(e))
}

/// 在小说中搜索关键词
pub fn search_in_novel(file_path: String, keyword: String) -> anyhow::Result<Vec<SearchMatch>> {
    let matches =
        novel_reader::search_in_novel(file_path, keyword).map_err(|e| anyhow::anyhow!(e))?;
    Ok(matches.into_iter().map(convert_search_match).collect())
}

/// 更新阅读进度
#[frb(sync)]
pub fn update_reading_progress(novel_id: String, progress: f32) -> anyhow::Result<()> {
    novel_reader::update_reading_progress(novel_id, progress).map_err(|e| anyhow::anyhow!(e))?;
    Ok(())
}
