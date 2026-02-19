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
    pub folder_id: Option<String>,
    pub custom_order: Option<i32>,
    pub is_favorite: bool,
    pub tags: Vec<String>,
    /// 书籍备注
    pub notes: Option<String>,
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
        folder_id: meta.folder_id,
        custom_order: meta.custom_order,
        is_favorite: meta.is_favorite,
        tags: meta.tags,
        notes: meta.notes,
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

/// 扫描文件夹获取书籍列表
#[frb(sync)]
pub fn scan_novels_folder(folder_path: String) -> anyhow::Result<Vec<NovelMetadata>> {
    let novels = novel_reader::scan_novels_folder(folder_path).map_err(|e| anyhow::anyhow!(e))?;
    Ok(novels.into_iter().map(convert_metadata).collect())
}

/// 获取所有书籍列表
#[frb(sync)]
pub fn get_all_novels() -> anyhow::Result<Vec<NovelMetadata>> {
    let novels = novel_reader::get_all_novels().map_err(|e| anyhow::anyhow!(e))?;
    Ok(novels.into_iter().map(convert_metadata).collect())
}

/// 添加书籍（支持单个路径或多路径）
#[frb(sync)]
pub fn add_novel(file_paths: Vec<String>) -> anyhow::Result<Vec<NovelMetadata>> {
    let novels = novel_reader::add_novel(file_paths).map_err(|e| anyhow::anyhow!(e))?;
    Ok(novels.into_iter().map(convert_metadata).collect())
}

/// 从库中移除书籍
#[frb(sync)]
pub fn remove_novel(novel_id: String) -> anyhow::Result<()> {
    novel_reader::remove_novel(novel_id).map_err(|e| anyhow::anyhow!(e))?;
    Ok(())
}

/// 从库中移除书籍及其文件
#[frb(sync)]
pub fn remove_novel_with_file(novel_id: String) -> anyhow::Result<()> {
    novel_reader::remove_novel_with_file(novel_id).map_err(|e| anyhow::anyhow!(e))?;
    Ok(())
}

/// 清空所有书籍
#[frb(sync)]
pub fn clear_all_novels() -> anyhow::Result<()> {
    novel_reader::clear_all_novels().map_err(|e| anyhow::anyhow!(e))?;
    Ok(())
}

/// 获取书籍的完整内容（包含所有章节）
pub fn get_novel_content(file_path: String) -> anyhow::Result<NovelContent> {
    let content = novel_reader::get_novel_content(file_path).map_err(|e| anyhow::anyhow!(e))?;
    Ok(convert_content(content))
}

/// 获取特定章节的内容
pub fn get_chapter_content(file_path: String, chapter_index: usize) -> anyhow::Result<String> {
    novel_reader::get_chapter_content(file_path, chapter_index).map_err(|e| anyhow::anyhow!(e))
}

/// 在书籍中搜索关键词
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

// Folder management

#[derive(Debug, Clone)]
pub struct NovelFolder {
    pub id: String,
    pub name: String,
    pub created_at: i64,
    pub order: i32,
    /// 父文件夹ID（None 表示顶级）
    pub parent_id: Option<String>,
}

fn convert_folder(folder: novel_reader::types::NovelFolder) -> NovelFolder {
    NovelFolder {
        id: folder.id,
        name: folder.name,
        created_at: folder.created_at.timestamp(),
        order: folder.order,
        parent_id: folder.parent_id,
    }
}

/// 创建文件夹
#[frb(sync)]
pub fn create_folder(name: String) -> anyhow::Result<NovelFolder> {
    let folder = novel_reader::create_folder(name).map_err(|e| anyhow::anyhow!(e))?;
    Ok(convert_folder(folder))
}

/// 获取所有文件夹
#[frb(sync)]
pub fn get_all_folders() -> anyhow::Result<Vec<NovelFolder>> {
    let folders = novel_reader::get_all_folders().map_err(|e| anyhow::anyhow!(e))?;
    Ok(folders.into_iter().map(convert_folder).collect())
}

/// 删除文件夹
#[frb(sync)]
pub fn delete_folder(folder_id: String) -> anyhow::Result<()> {
    novel_reader::delete_folder(folder_id).map_err(|e| anyhow::anyhow!(e))?;
    Ok(())
}

/// 移动书籍到文件夹
#[frb(sync)]
pub fn move_novel_to_folder(novel_id: String, folder_id: Option<String>) -> anyhow::Result<()> {
    novel_reader::move_novel_to_folder(novel_id, folder_id).map_err(|e| anyhow::anyhow!(e))?;
    Ok(())
}

/// 更新书籍排序
#[frb(sync)]
pub fn update_novel_order(novel_id: String, order: i32) -> anyhow::Result<()> {
    novel_reader::update_novel_order(novel_id, order).map_err(|e| anyhow::anyhow!(e))?;
    Ok(())
}

/// 批量更新书籍排序
#[frb(sync)]
pub fn batch_update_novel_orders(novel_ids: Vec<String>) -> anyhow::Result<()> {
    novel_reader::batch_update_novel_orders(novel_ids).map_err(|e| anyhow::anyhow!(e))?;
    Ok(())
}

/// 重命名书籍标题
#[frb(sync)]
pub fn rename_novel(novel_id: String, title: String) -> anyhow::Result<()> {
    novel_reader::rename_novel(novel_id, title).map_err(|e| anyhow::anyhow!(e))?;
    Ok(())
}

/// 设置收藏状态
#[frb(sync)]
pub fn set_novel_favorite(novel_id: String, is_favorite: bool) -> anyhow::Result<()> {
    novel_reader::set_novel_favorite(novel_id, is_favorite).map_err(|e| anyhow::anyhow!(e))?;
    Ok(())
}

/// 更新书籍标签
#[frb(sync)]
pub fn update_novel_tags(novel_id: String, tags: Vec<String>) -> anyhow::Result<()> {
    novel_reader::update_novel_tags(novel_id, tags).map_err(|e| anyhow::anyhow!(e))?;
    Ok(())
}

/// 清除书籍内容缓存（强制下次重新解析 epub 图片）
#[frb(sync)]
pub fn clear_novel_cache(file_path: String) -> anyhow::Result<()> {
    novel_reader::clear_novel_cache(file_path).map_err(|e| anyhow::anyhow!(e))?;
    Ok(())
}

/// 重命名文件夹
#[frb(sync)]
pub fn rename_folder(folder_id: String, name: String) -> anyhow::Result<()> {
    novel_reader::rename_folder(folder_id, name).map_err(|e| anyhow::anyhow!(e))?;
    Ok(())
}

/// 批量更新文件夹排序
#[frb(sync)]
pub fn batch_update_folder_orders(folder_ids: Vec<String>) -> anyhow::Result<()> {
    novel_reader::batch_update_folder_orders(folder_ids).map_err(|e| anyhow::anyhow!(e))?;
    Ok(())
}

/// 删除文件夹及其内所有书籍
#[frb(sync)]
pub fn delete_folder_with_novels(folder_id: String) -> anyhow::Result<()> {
    novel_reader::delete_folder_with_novels(folder_id).map_err(|e| anyhow::anyhow!(e))?;
    Ok(())
}

/// 书籍搜索结果
#[derive(Debug, Clone)]
pub struct NovelSearchResult {
    pub novel: NovelMetadata,
    pub match_count: usize,
}

fn convert_search_result(result: novel_reader::api::NovelSearchResult) -> NovelSearchResult {
    NovelSearchResult {
        novel: convert_metadata(result.novel),
        match_count: result.match_count,
    }
}

/// 搜索批次结果
#[derive(Debug, Clone)]
pub struct SearchBatchResult {
    pub results: Vec<NovelSearchResult>,
    pub completed: usize,
    pub total: usize,
    pub is_finished: bool,
}

fn convert_search_batch_result(result: novel_reader::api::SearchBatchResult) -> SearchBatchResult {
    SearchBatchResult {
        results: result
            .results
            .into_iter()
            .map(convert_search_result)
            .collect(),
        completed: result.completed,
        total: result.total,
        is_finished: result.is_finished,
    }
}

/// 取消搜索
#[frb(sync)]
pub fn cancel_search() -> anyhow::Result<()> {
    novel_reader::cancel_search().map_err(|e| anyhow::anyhow!(e))?;
    Ok(())
}

/// 在所有书籍中搜索关键词（批量搜索，支持进度反馈和取消）
pub fn search_in_all_novels_batched(
    keyword: String,
    batch_size: usize,
) -> anyhow::Result<Vec<SearchBatchResult>> {
    let results = novel_reader::search_in_all_novels_batched(keyword, batch_size)
        .map_err(|e| anyhow::anyhow!(e))?;
    Ok(results
        .into_iter()
        .map(convert_search_batch_result)
        .collect())
}

/// 在所有书籍中搜索关键词（批量搜索，性能优化）
pub fn search_in_all_novels(keyword: String) -> anyhow::Result<Vec<NovelSearchResult>> {
    let results = novel_reader::search_in_all_novels(keyword).map_err(|e| anyhow::anyhow!(e))?;
    Ok(results.into_iter().map(convert_search_result).collect())
}

/// 扫描批次结果
#[derive(Debug, Clone)]
pub struct ScanBatchResult {
    pub novels: Vec<NovelMetadata>,
    pub completed: usize,
    pub total: usize,
    pub is_finished: bool,
}

fn convert_scan_batch_result(result: novel_reader::api::ScanBatchResult) -> ScanBatchResult {
    ScanBatchResult {
        novels: result.novels.into_iter().map(convert_metadata).collect(),
        completed: result.completed,
        total: result.total,
        is_finished: result.is_finished,
    }
}

/// 批量扫描文件夹（分批返回结果，避免阻塞）
pub fn scan_novels_folder_batched(
    folder_path: String,
    batch_size: usize,
) -> anyhow::Result<Vec<ScanBatchResult>> {
    let results = novel_reader::scan_novels_folder_batched(folder_path, batch_size)
        .map_err(|e| anyhow::anyhow!(e))?;
    Ok(results.into_iter().map(convert_scan_batch_result).collect())
}
// ─────────────────────────────────────────────────────────────────────────────
// 扩展书籍元数据操作
// ─────────────────────────────────────────────────────────────────────────────

/// 更新书籍封面（压缩后保存，异步执行避免阻塞 UI）
pub fn update_novel_cover(novel_id: String, image_path: String) -> anyhow::Result<()> {
    novel_reader::update_novel_cover(novel_id, image_path).map_err(|e| anyhow::anyhow!(e))
}

/// 更新书籍作者
#[frb(sync)]
pub fn update_novel_author(novel_id: String, author: String) -> anyhow::Result<()> {
    novel_reader::update_novel_author(novel_id, author).map_err(|e| anyhow::anyhow!(e))
}

/// 更新书籍备注
#[frb(sync)]
pub fn update_novel_notes(novel_id: String, notes: String) -> anyhow::Result<()> {
    novel_reader::update_novel_notes(novel_id, notes).map_err(|e| anyhow::anyhow!(e))
}

/// 批量更新书籍基本信息
#[frb(sync)]
pub fn update_novel_info(
    novel_id: String,
    title: Option<String>,
    author: Option<String>,
    notes: Option<String>,
    tags: Option<Vec<String>>,
) -> anyhow::Result<()> {
    novel_reader::update_novel_info(novel_id, title, author, notes, tags)
        .map_err(|e| anyhow::anyhow!(e))
}

/// 创建子文件夹
#[frb(sync)]
pub fn create_child_folder(name: String, parent_id: String) -> anyhow::Result<NovelFolder> {
    let folder =
        novel_reader::create_child_folder(name, parent_id).map_err(|e| anyhow::anyhow!(e))?;
    Ok(convert_folder(folder))
}

/// 获取子文件夹列表
#[frb(sync)]
pub fn get_child_folders(parent_id: String) -> anyhow::Result<Vec<NovelFolder>> {
    let folders = novel_reader::get_child_folders(parent_id).map_err(|e| anyhow::anyhow!(e))?;
    Ok(folders.into_iter().map(convert_folder).collect())
}

/// 添加书籍并关联到指定文件夹
#[frb(sync)]
pub fn add_novel_to_folder(
    file_paths: Vec<String>,
    folder_id: String,
) -> anyhow::Result<Vec<NovelMetadata>> {
    let novels =
        novel_reader::add_novel_to_folder(file_paths, folder_id).map_err(|e| anyhow::anyhow!(e))?;
    Ok(novels.into_iter().map(convert_metadata).collect())
}
