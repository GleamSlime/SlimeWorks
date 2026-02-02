use chrono::{DateTime, Utc};
use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex, OnceLock};

use crate::parser::NovelParser;
use crate::scanner::DirectoryScanner;
use crate::types::{
    NovelChapter, NovelContent, NovelFolder, NovelFormat, NovelMetadata, ScanProgress,
};
use db_module;
use serde_json; // 使用工作区内的 db_module 来持久化元数据

// 全局存储的小说库
static NOVEL_LIBRARY: OnceLock<Arc<Mutex<Vec<NovelMetadata>>>> = OnceLock::new();

// 全局存储的文件夹列表
static FOLDER_LIST: OnceLock<Arc<Mutex<Vec<NovelFolder>>>> = OnceLock::new();

// 内容缓存：存储已解析的小说内容，避免重复解析
type ContentCache = Arc<Mutex<HashMap<String, (NovelContent, DateTime<Utc>)>>>;
static CONTENT_CACHE: OnceLock<ContentCache> = OnceLock::new();

fn get_content_cache() -> &'static ContentCache {
    CONTENT_CACHE.get_or_init(|| Arc::new(Mutex::new(HashMap::new())))
}

fn get_library() -> &'static Arc<Mutex<Vec<NovelMetadata>>> {
    NOVEL_LIBRARY.get_or_init(|| {
        // 尝试初始化数据库并从表中加载已保存的小说元数据
        let library = Arc::new(Mutex::new(Vec::new()));

        // 选择一个默认数据库路径（用户 HOME 下的 .slimeworks/db.redb），如果 HOME 不可用则用临时目录
        let db_path = std::env::var("HOME")
            .map(|h| {
                let mut p = std::path::PathBuf::from(h);
                p.push(".slimeworks");
                p.push("db.redb");
                p.to_string_lossy().to_string()
            })
            .unwrap_or_else(|_| {
                let mut p = std::env::temp_dir();
                p.push("slimeworks");
                p.push("db.redb");
                p.to_string_lossy().to_string()
            });

        // 忽略初始化错误（可能已经初始化或权限问题），但继续尝试读取已有记录
        let _ = db_module::db_init(db_path.clone());
        let _ = db_module::db_register_table("novels".to_string());

        if let Ok(records) = db_module::db_list_all("novels".to_string()) {
            if let Ok(mut lib) = library.lock() {
                for rec in records {
                    if let Ok(meta) = serde_json::from_str::<NovelMetadata>(&rec.value) {
                        lib.push(meta);
                    }
                }
            }
        }

        library
    })
}

fn get_folder_list() -> &'static Arc<Mutex<Vec<NovelFolder>>> {
    FOLDER_LIST.get_or_init(|| {
        let folders = Arc::new(Mutex::new(Vec::new()));

        let _ = db_module::db_register_table("novel_folders".to_string());

        if let Ok(records) = db_module::db_list_all("novel_folders".to_string()) {
            if let Ok(mut list) = folders.lock() {
                for rec in records {
                    if let Ok(folder) = serde_json::from_str::<NovelFolder>(&rec.value) {
                        list.push(folder);
                    }
                }
            }
        }

        folders
    })
}

/// 扫描文件夹获取小说列表
#[frb(sync)]
pub fn scan_novels_folder(folder_path: String) -> Result<Vec<NovelMetadata>, String> {
    let scanner = DirectoryScanner::new("novels".to_string());
    let novels = scanner.scan(&folder_path).map_err(|e| e.to_string())?;

    // 更新到全局库
    let mut library = get_library().lock().map_err(|e| e.to_string())?;
    for novel in &novels {
        // 如果已存在则更新，否则添加
        if let Some(existing) = library.iter_mut().find(|n| n.id == novel.id) {
            *existing = novel.clone();
        } else {
            library.push(novel.clone());
        }
        // 持久化到数据库（忽略错误）
        if let Ok(json) = serde_json::to_string(novel) {
            let _ = db_module::db_set("novels".to_string(), novel.id.clone(), json);
        }
    }

    Ok(novels)
}

/// 获取所有小说列表
#[frb(sync)]
pub fn get_all_novels() -> Result<Vec<NovelMetadata>, String> {
    let library = get_library().lock().map_err(|e| e.to_string())?;
    Ok(library.clone())
}

/// 添加单个小说
#[frb(sync)]
pub fn add_novel(file_path: String) -> Result<NovelMetadata, String> {
    let scanner = DirectoryScanner::new("novels".to_string());
    let novel = scanner.scan_file(&file_path).map_err(|e| e.to_string())?;

    let mut library = get_library().lock().map_err(|e| e.to_string())?;
    if let Some(existing) = library.iter_mut().find(|n| n.id == novel.id) {
        *existing = novel.clone();
    } else {
        library.push(novel.clone());
    }

    // 持久化
    if let Ok(json) = serde_json::to_string(&novel) {
        let _ = db_module::db_set("novels".to_string(), novel.id.clone(), json);
    }

    Ok(novel)
}

/// 删除小说
#[frb(sync)]
pub fn remove_novel(novel_id: String) -> Result<bool, String> {
    let mut library = get_library().lock().map_err(|e| e.to_string())?;
    let initial_len = library.len();
    library.retain(|n| n.id != novel_id);
    let removed = library.len() < initial_len;
    if removed {
        let _ = db_module::db_delete("novels".to_string(), novel_id);
    }
    Ok(removed)
}

/// 删除小说及其文件
#[frb(sync)]
pub fn remove_novel_with_file(novel_id: String) -> Result<bool, String> {
    // 先获取文件路径
    let file_path = {
        let library = get_library().lock().map_err(|e| e.to_string())?;
        library
            .iter()
            .find(|n| n.id == novel_id)
            .map(|n| n.file_path.clone())
    };

    // 删除数据库记录
    let removed = remove_novel(novel_id)?;

    // 删除文件
    if removed {
        if let Some(path) = file_path {
            match std::fs::remove_file(&path) {
                Ok(_) => log::info!("[Novel] Deleted file: {}", path),
                Err(e) => log::warn!("[Novel] Failed to delete file {}: {}", path, e),
            }
        }
    }

    Ok(removed)
}

/// 清空所有小说
#[frb(sync)]
pub fn clear_all_novels() -> Result<(), String> {
    let mut library = get_library().lock().map_err(|e| e.to_string())?;

    // 删除数据库中的所有记录
    for novel in library.iter() {
        let _ = db_module::db_delete("novels".to_string(), novel.id.clone());
    }

    // 清空内存库
    library.clear();

    Ok(())
}

/// 获取小说内容（带缓存）
pub fn get_novel_content(file_path: String) -> Result<NovelContent, String> {
    use std::fs;
    use std::time::Instant;

    let start_time = Instant::now();
    log::info!("[Novel] Starting to load novel: {}", file_path);

    let path = PathBuf::from(&file_path);

    // 检查文件修改时间
    log::debug!("[Novel] Checking file metadata...");
    let metadata = fs::metadata(&path).map_err(|e| {
        log::error!("[Novel] Failed to read file metadata: {}", e);
        format!("Failed to read file metadata: {}", e)
    })?;
    let modified = metadata
        .modified()
        .map_err(|e| format!("Failed to get file modified time: {}", e))?;
    let modified_time: DateTime<Utc> = modified.into();
    let file_size = metadata.len();
    log::info!(
        "[Novel] File size: {} bytes, modified: {:?}",
        file_size,
        modified_time
    );

    // 检查缓存
    {
        log::debug!("[Novel] Checking cache...");
        let cache = get_content_cache().lock().map_err(|e| e.to_string())?;
        if let Some((cached_content, cached_time)) = cache.get(&file_path) {
            // 如果文件没有被修改，返回缓存内容
            if cached_time >= &modified_time {
                let elapsed = start_time.elapsed();
                log::info!(
                    "[Novel] Cache hit! Returned in {:?}, chapters: {}",
                    elapsed,
                    cached_content.chapters.len()
                );
                return Ok(cached_content.clone());
            } else {
                log::info!("[Novel] Cache expired (file modified), will re-parse");
            }
        } else {
            log::info!("[Novel] Cache miss, will parse file");
        }
    }

    // 解析文件
    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .ok_or_else(|| "Invalid file extension".to_string())?;

    log::info!("[Novel] Parsing {} file...", ext);
    let parse_start = Instant::now();
    let content = match ext.to_lowercase().as_str() {
        "txt" => {
            let result = crate::parser::TxtParser::parse(&path).map_err(|e| {
                log::error!("[Novel] TXT parse failed: {}", e);
                e.to_string()
            })?;
            log::info!(
                "[Novel] TXT parsed in {:?}, chapters: {}",
                parse_start.elapsed(),
                result.chapters.len()
            );
            result
        }
        "epub" => {
            let result = crate::parser::EpubParser::parse(&path).map_err(|e| {
                log::error!("[Novel] EPUB parse failed: {}", e);
                e.to_string()
            })?;
            log::info!(
                "[Novel] EPUB parsed in {:?}, chapters: {}",
                parse_start.elapsed(),
                result.chapters.len()
            );
            result
        }
        _ => return Err(format!("Unsupported file format: {}", ext)),
    };

    // 更新缓存
    {
        log::debug!("[Novel] Updating cache...");
        let mut cache = get_content_cache().lock().map_err(|e| e.to_string())?;
        cache.insert(file_path.clone(), (content.clone(), modified_time));
        log::info!(
            "[Novel] Cache updated, total cached novels: {}",
            cache.len()
        );
    }

    let total_elapsed = start_time.elapsed();
    log::info!("[Novel] Total load time: {:?}", total_elapsed);
    Ok(content)
}

/// 获取小说章节内容（使用缓存）
pub fn get_chapter_content(file_path: String, chapter_index: usize) -> Result<String, String> {
    log::info!(
        "[Novel] Getting chapter {} from {}",
        chapter_index,
        file_path
    );
    let content = get_novel_content(file_path)?;

    let result = content
        .chapters
        .get(chapter_index)
        .and_then(|ch| ch.content.clone())
        .ok_or_else(|| {
            log::error!(
                "[Novel] Chapter {} not found or has no content",
                chapter_index
            );
            format!("Chapter {} not found or has no content", chapter_index)
        })?;

    log::info!(
        "[Novel] Chapter {} loaded, length: {} chars",
        chapter_index,
        result.len()
    );
    Ok(result)
}

/// 简单地去除所有HTML标签（用于搜索）
fn strip_all_html_tags(html: &str) -> String {
    use regex::Regex;

    // 移除所有 HTML 标签
    let tag_regex = Regex::new(r"<[^>]+>").unwrap();
    let result = tag_regex.replace_all(html, "");

    // 解码常见的 HTML 实体
    let result = result.replace("&nbsp;", " ");
    let result = result.replace("&lt;", "<");
    let result = result.replace("&gt;", ">");
    let result = result.replace("&amp;", "&");
    let result = result.replace("&quot;", "\"");
    let result = result.replace("&#39;", "'");

    result.to_string()
}

/// 搜索小说内容中的关键词（使用缓存）
pub fn search_in_novel(file_path: String, keyword: String) -> Result<Vec<SearchMatch>, String> {
    let content = get_novel_content(file_path)?;
    let mut matches = Vec::new();

    for chapter in &content.chapters {
        if let Some(text) = &chapter.content {
            // 去除HTML标签后再搜索
            let clean_text = strip_all_html_tags(text);

            // 使用基于字符的搜索以避免在多字节 UTF-8 字符上按字节切片导致 panic
            let text_chars: Vec<char> = clean_text.chars().collect();
            let text_lower_chars: Vec<char> = clean_text.to_lowercase().chars().collect();
            let keyword_lower_chars: Vec<char> = keyword.to_lowercase().chars().collect();
            let kw_len = keyword_lower_chars.len();

            if kw_len == 0 || text_lower_chars.len() < kw_len {
                continue;
            }

            for i in 0..=text_lower_chars.len() - kw_len {
                if text_lower_chars[i..i + kw_len] == keyword_lower_chars[..] {
                    // 构建片段（前后各50个字符）
                    let start_char = if i >= 50 { i - 50 } else { 0 };
                    let end_char = (i + kw_len + 50).min(text_chars.len());
                    let snippet: String = text_chars[start_char..end_char].iter().collect();

                    matches.push(SearchMatch {
                        chapter_index: chapter.index,
                        chapter_title: chapter.title.clone(),
                        position: i, // 以字符为单位的位置
                        snippet,
                    });
                }
            }
        }
    }

    Ok(matches)
}

/// 更新阅读进度
#[frb(sync)]
pub fn update_reading_progress(novel_id: String, progress: f32) -> Result<bool, String> {
    let mut library = get_library().lock().map_err(|e| e.to_string())?;

    if let Some(novel) = library.iter_mut().find(|n| n.id == novel_id) {
        novel.progress = progress.clamp(0.0, 1.0);
        novel.last_read_at = Some(chrono::Utc::now());

        // 持久化到数据库
        if let Ok(json) = serde_json::to_string(&novel) {
            let _ = db_module::db_set("novels".to_string(), novel.id.clone(), json);
        }

        Ok(true)
    } else {
        Ok(false)
    }
}

/// 搜索匹配结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchMatch {
    pub chapter_index: usize,
    pub chapter_title: String,
    pub position: usize,
    pub snippet: String,
}

/// 创建文件夹
#[frb(sync)]
pub fn create_folder(name: String) -> Result<NovelFolder, String> {
    let mut folders = get_folder_list().lock().map_err(|e| e.to_string())?;

    let folder = NovelFolder {
        id: format!("folder_{}", uuid::Uuid::new_v4()),
        name,
        created_at: chrono::Utc::now(),
        order: folders.len() as i32,
    };

    folders.push(folder.clone());

    // 持久化
    if let Ok(json) = serde_json::to_string(&folder) {
        let _ = db_module::db_set("novel_folders".to_string(), folder.id.clone(), json);
    }

    Ok(folder)
}

/// 获取所有文件夹
#[frb(sync)]
pub fn get_all_folders() -> Result<Vec<NovelFolder>, String> {
    let folders = get_folder_list().lock().map_err(|e| e.to_string())?;
    let mut result = folders.clone();
    result.sort_by_key(|f| f.order);
    Ok(result)
}

/// 删除文件夹
#[frb(sync)]
pub fn delete_folder(folder_id: String) -> Result<bool, String> {
    let mut folders = get_folder_list().lock().map_err(|e| e.to_string())?;
    let initial_len = folders.len();
    folders.retain(|f| f.id != folder_id);
    let removed = folders.len() < initial_len;

    if removed {
        let _ = db_module::db_delete("novel_folders".to_string(), folder_id.clone());

        // 将该文件夹下的小说移到根目录
        let mut library = get_library().lock().map_err(|e| e.to_string())?;
        for novel in library.iter_mut() {
            if novel.folder_id.as_ref() == Some(&folder_id) {
                novel.folder_id = None;
                if let Ok(json) = serde_json::to_string(&novel) {
                    let _ = db_module::db_set("novels".to_string(), novel.id.clone(), json);
                }
            }
        }
    }

    Ok(removed)
}

/// 移动小说到文件夹
#[frb(sync)]
pub fn move_novel_to_folder(novel_id: String, folder_id: Option<String>) -> Result<bool, String> {
    let mut library = get_library().lock().map_err(|e| e.to_string())?;

    if let Some(novel) = library.iter_mut().find(|n| n.id == novel_id) {
        novel.folder_id = folder_id;

        // 持久化
        if let Ok(json) = serde_json::to_string(&novel) {
            let _ = db_module::db_set("novels".to_string(), novel.id.clone(), json);
        }

        Ok(true)
    } else {
        Ok(false)
    }
}

/// 更新小说排序
#[frb(sync)]
pub fn update_novel_order(novel_id: String, order: i32) -> Result<bool, String> {
    let mut library = get_library().lock().map_err(|e| e.to_string())?;

    if let Some(novel) = library.iter_mut().find(|n| n.id == novel_id) {
        novel.custom_order = Some(order);

        // 持久化
        if let Ok(json) = serde_json::to_string(&novel) {
            let _ = db_module::db_set("novels".to_string(), novel.id.clone(), json);
        }

        Ok(true)
    } else {
        Ok(false)
    }
}

/// 批量更新小说排序
#[frb(sync)]
pub fn batch_update_novel_orders(novel_ids: Vec<String>) -> Result<(), String> {
    let mut library = get_library().lock().map_err(|e| e.to_string())?;

    for (index, novel_id) in novel_ids.iter().enumerate() {
        if let Some(novel) = library.iter_mut().find(|n| n.id == *novel_id) {
            novel.custom_order = Some(index as i32);

            // 持久化
            if let Ok(json) = serde_json::to_string(&novel) {
                let _ = db_module::db_set("novels".to_string(), novel.id.clone(), json);
            }
        }
    }

    Ok(())
}

/// 搜索结果：包含小说元数据和匹配计数
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NovelSearchResult {
    pub novel: NovelMetadata,
    pub match_count: usize,
}

/// 搜索批次结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchBatchResult {
    pub results: Vec<NovelSearchResult>,
    pub completed: usize,
    pub total: usize,
    pub is_finished: bool,
}

// 全局搜索取消标志
static SEARCH_CANCELLED: OnceLock<Arc<Mutex<bool>>> = OnceLock::new();

fn get_search_cancelled() -> &'static Arc<Mutex<bool>> {
    SEARCH_CANCELLED.get_or_init(|| Arc::new(Mutex::new(false)))
}

/// 取消搜索
#[frb(sync)]
pub fn cancel_search() -> Result<(), String> {
    let cancelled = get_search_cancelled();
    if let Ok(mut flag) = cancelled.lock() {
        *flag = true;
    }
    Ok(())
}

/// 在所有小说中搜索关键词（批量搜索，支持进度反馈和取消）
/// 分批返回搜索结果，每批处理若干本小说
pub fn search_in_all_novels_batched(
    keyword: String,
    batch_size: usize,
) -> Result<Vec<SearchBatchResult>, String> {
    if keyword.is_empty() {
        return Ok(Vec::new());
    }

    // 重置取消标志
    {
        let cancelled = get_search_cancelled();
        if let Ok(mut flag) = cancelled.lock() {
            *flag = false;
        }
    }

    let library = get_library().lock().map_err(|e| e.to_string())?;
    let novels = library.clone();
    drop(library); // 释放锁

    let keyword_lower_chars: Vec<char> = keyword.to_lowercase().chars().collect();
    let kw_len = keyword_lower_chars.len();

    if kw_len == 0 {
        return Ok(Vec::new());
    }

    let total = novels.len();
    let mut all_batches: Vec<SearchBatchResult> = Vec::new();

    // 分批处理
    for (batch_idx, chunk) in novels.chunks(batch_size).enumerate() {
        // 检查是否取消
        {
            let cancelled = get_search_cancelled();
            if let Ok(flag) = cancelled.lock() {
                if *flag {
                    // 返回当前已有结果，标记为已完成
                    if !all_batches.is_empty() {
                        // 更新最后一个批次为已完成
                        if let Some(last) = all_batches.last_mut() {
                            last.is_finished = true;
                        }
                    }
                    return Ok(all_batches);
                }
            }
        }

        let mut batch_results = Vec::new();

        for novel in chunk {
            // 再次检查取消标志（更频繁）
            {
                let cancelled = get_search_cancelled();
                if let Ok(flag) = cancelled.lock() {
                    if *flag {
                        break;
                    }
                }
            }

            // 尝试获取小说内容并搜索
            match get_novel_content(novel.file_path.clone()) {
                Ok(content) => {
                    let mut match_count = 0;

                    for chapter in &content.chapters {
                        if let Some(text) = &chapter.content {
                            // 去除HTML标签后再搜索
                            let clean_text = strip_all_html_tags(text);
                            let text_lower_chars: Vec<char> =
                                clean_text.to_lowercase().chars().collect();

                            if text_lower_chars.len() < kw_len {
                                continue;
                            }

                            // 计算当前章节的匹配数
                            for i in 0..=text_lower_chars.len() - kw_len {
                                if text_lower_chars[i..i + kw_len] == keyword_lower_chars[..] {
                                    match_count += 1;
                                }
                            }
                        }
                    }

                    if match_count > 0 {
                        batch_results.push(NovelSearchResult {
                            novel: novel.clone(),
                            match_count,
                        });
                    }
                }
                Err(_) => continue,
            }
        }

        let completed = (batch_idx + 1) * batch_size.min(total);
        let is_finished = completed >= total;

        // 按匹配数排序当前批次
        batch_results.sort_by(|a, b| b.match_count.cmp(&a.match_count));

        all_batches.push(SearchBatchResult {
            results: batch_results,
            completed: completed.min(total),
            total,
            is_finished,
        });
    }

    Ok(all_batches)
}

/// 在所有小说中搜索关键词（批量搜索，性能优化）
/// 返回包含关键词的小说列表及其匹配数
/// 注意：此函数不支持取消和进度反馈，建议使用 search_in_all_novels_batched
pub fn search_in_all_novels(keyword: String) -> Result<Vec<NovelSearchResult>, String> {
    if keyword.is_empty() {
        return Ok(Vec::new());
    }

    let library = get_library().lock().map_err(|e| e.to_string())?;
    let novels = library.clone();
    drop(library); // 释放锁以允许并发处理

    let keyword_lower_chars: Vec<char> = keyword.to_lowercase().chars().collect();
    let kw_len = keyword_lower_chars.len();

    if kw_len == 0 {
        return Ok(Vec::new());
    }

    let mut results = Vec::new();

    // 并发搜索所有小说
    use rayon::prelude::*;

    let search_results: Vec<_> = novels
        .par_iter()
        .filter_map(|novel| {
            // 尝试获取小说内容并搜索
            match get_novel_content(novel.file_path.clone()) {
                Ok(content) => {
                    let mut match_count = 0;

                    for chapter in &content.chapters {
                        if let Some(text) = &chapter.content {
                            let text_lower_chars: Vec<char> = text.to_lowercase().chars().collect();

                            if text_lower_chars.len() < kw_len {
                                continue;
                            }

                            // 计算当前章节的匹配数
                            for i in 0..=text_lower_chars.len() - kw_len {
                                if text_lower_chars[i..i + kw_len] == keyword_lower_chars[..] {
                                    match_count += 1;
                                }
                            }
                        }
                    }

                    if match_count > 0 {
                        Some(NovelSearchResult {
                            novel: novel.clone(),
                            match_count,
                        })
                    } else {
                        None
                    }
                }
                Err(_) => None,
            }
        })
        .collect();

    results.extend(search_results);

    // 按匹配数排序（匹配越多越靠前）
    results.sort_by(|a, b| b.match_count.cmp(&a.match_count));

    Ok(results)
}

/// 扫描进度回调结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScanBatchResult {
    pub novels: Vec<NovelMetadata>,
    pub completed: usize,
    pub total: usize,
    pub is_finished: bool,
}

/// 批量扫描文件夹（分批返回结果，避免阻塞）
/// 每次返回一批扫描的小说，前端可以逐步显示
pub fn scan_novels_folder_batched(
    folder_path: String,
    batch_size: usize,
) -> Result<Vec<ScanBatchResult>, String> {
    let scanner = DirectoryScanner::new("novels".to_string());

    // 首先快速扫描获取所有文件路径
    let novel_paths = scanner
        .scan_paths(&folder_path)
        .map_err(|e| e.to_string())?;
    let total = novel_paths.len();

    let mut all_batches = Vec::new();
    let mut library = get_library().lock().map_err(|e| e.to_string())?;

    // 分批处理
    for (batch_idx, chunk) in novel_paths.chunks(batch_size).enumerate() {
        let mut batch_novels = Vec::new();

        for path in chunk {
            match scanner.scan_file(path) {
                Ok(novel) => {
                    // 更新到全局库
                    if let Some(existing) = library.iter_mut().find(|n| n.id == novel.id) {
                        *existing = novel.clone();
                    } else {
                        library.push(novel.clone());
                    }

                    // 持久化到数据库
                    if let Ok(json) = serde_json::to_string(&novel) {
                        let _ = db_module::db_set("novels".to_string(), novel.id.clone(), json);
                    }

                    batch_novels.push(novel);
                }
                Err(_) => continue,
            }
        }

        let completed = (batch_idx + 1) * batch_size.min(total);
        let is_finished = completed >= total;

        all_batches.push(ScanBatchResult {
            novels: batch_novels,
            completed: completed.min(total),
            total,
            is_finished,
        });
    }

    Ok(all_batches)
}
