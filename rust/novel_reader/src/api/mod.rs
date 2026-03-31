mod api_metadata;
mod api_search;

pub use api_metadata::*;
pub use api_search::*;

use chrono::{DateTime, Utc};
use flutter_rust_bridge::frb;
use rayon::prelude::*;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex, OnceLock};

use crate::scanner::DirectoryScanner;
use crate::types::{NovelContent, NovelFolder, NovelMetadata};
use db_module;
use serde_json; // 使用工作区内的 db_module 来持久化元数据

// 全局存储的书籍库
static NOVEL_LIBRARY: OnceLock<Arc<Mutex<Vec<NovelMetadata>>>> = OnceLock::new();

// 全局存储的文件夹列表
static FOLDER_LIST: OnceLock<Arc<Mutex<Vec<NovelFolder>>>> = OnceLock::new();

// ─────────────────────────────────────────────────────────────
// 获取应用数据目录
// ─────────────────────────────────────────────────────────────

/// 获取应用数据目录（跨平台）
/// - Windows: %LOCALAPPDATA%\slimeworks 或 %APPDATA%\slimeworks
/// - macOS: ~/Library/Application Support/slimeworks
/// - Linux: ~/.local/share/slimeworks
pub fn get_app_data_dir() -> PathBuf {
    let app_name = "slimeworks";

    #[cfg(target_os = "windows")]
    {
        // Windows: 优先使用 LOCALAPPDATA，其次 APPDATA
        if let Ok(local_appdata) = std::env::var("LOCALAPPDATA") {
            let path = PathBuf::from(local_appdata).join(app_name);
            let _ = std::fs::create_dir_all(&path);
            return path;
        }
        if let Ok(appdata) = std::env::var("APPDATA") {
            let path = PathBuf::from(appdata).join(app_name);
            let _ = std::fs::create_dir_all(&path);
            return path;
        }
    }

    #[cfg(target_os = "macos")]
    {
        // macOS: ~/Library/Application Support/slimeworks
        if let Ok(home) = std::env::var("HOME") {
            let path = PathBuf::from(home)
                .join("Library")
                .join("Application Support")
                .join(app_name);
            let _ = std::fs::create_dir_all(&path);
            return path;
        }
    }

    #[cfg(target_os = "linux")]
    {
        // Linux: ~/.local/share/slimeworks
        if let Ok(home) = std::env::var("HOME") {
            let path = PathBuf::from(home)
                .join(".local")
                .join("share")
                .join(app_name);
            let _ = std::fs::create_dir_all(&path);
            return path;
        }
    }

    // Fallback: 使用 HOME/.slimeworks 或临时目录
    if let Ok(home) = std::env::var("HOME") {
        let path = PathBuf::from(home).join(format!(".{}", app_name));
        let _ = std::fs::create_dir_all(&path);
        path
    } else {
        let path = std::env::temp_dir().join(app_name);
        let _ = std::fs::create_dir_all(&path);
        println!("[AppData] Using temp directory as fallback: {:?}", path);
        path
    }
}

// ─────────────────────────────────────────────────────────────
// 书籍库管理
// ─────────────────────────────────────────────────────────────

// 内容缓存：存储已解析的书籍内容，避免重复解析
type ContentCache = Arc<Mutex<HashMap<String, (NovelContent, DateTime<Utc>)>>>;
static CONTENT_CACHE: OnceLock<ContentCache> = OnceLock::new();

fn get_content_cache() -> &'static ContentCache {
    CONTENT_CACHE.get_or_init(|| Arc::new(Mutex::new(HashMap::new())))
}

fn get_library() -> &'static Arc<Mutex<Vec<NovelMetadata>>> {
    NOVEL_LIBRARY.get_or_init(|| {
        // 尝试初始化数据库并从表中加载已保存的书籍元数据
        let library = Arc::new(Mutex::new(Vec::new()));

        // 获取应用数据目录（优先使用系统应用数据目录，而非临时目录）
        let db_path = get_app_data_dir().join("db.redb");
        let db_path_str = db_path.to_string_lossy().to_string();

        println!("[NovelLibrary] Database path: {}", db_path_str);

        let _ = db_module::db_init(db_path_str.clone());
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

// ─────────────────────────────────────────────────────────────
// 关键词自动打标签（使用 tag_keyword.json 规则）
// ─────────────────────────────────────────────────────────────

/// 编译时嵌入的默认关键词规则
const DEFAULT_TAG_KEYWORDS: &str = include_str!("../../tag_keyword.json");

/// 加载关键词规则：优先读取可执行文件同目录下的 tag_keyword.json，否则使用内嵌默认
fn load_tag_keyword_rules() -> HashMap<String, Vec<String>> {
    // 尝试在可执行文件目录寻找覆盖文件
    let maybe_exe = std::env::current_exe();
    if let Ok(exe) = maybe_exe {
        if let Some(parent) = exe.parent() {
            let p = parent.join("tag_keyword.json");
            println!("[Tag] checking override file at {:?}", p);
            if p.exists() {
                match std::fs::read_to_string(&p) {
                    Ok(s) => match serde_json::from_str::<HashMap<String, Vec<String>>>(&s) {
                        Ok(map) => {
                            println!(
                                "[Tag] loaded override tag_keyword.json from {:?} ({} keys)",
                                p,
                                map.len(),
                            );
                            return map;
                        }
                        Err(e) => {
                            println!(
                                "[Tag] failed to parse override tag_keyword.json at {:?}: {}",
                                p,
                                e
                            );
                        }
                    },
                    Err(e) => {
                        println!(
                            "[Tag] failed to read override tag_keyword.json at {:?}: {}",
                            p,
                            e
                        );
                    }
                }
            } else {
                println!("[Tag] no override file at {:?}", p);
            }
        }
    } else {
        println!("[Tag] current_exe() failed: {:?}", maybe_exe.err());
    }

    // 使用内嵌默认规则
    match serde_json::from_str::<HashMap<String, Vec<String>>>(DEFAULT_TAG_KEYWORDS) {
        Ok(map) => {
            println!(
                "[Tag] loaded embedded default tag_keyword.json ({} keys)",
                map.len(),
            );
            map
        }
        Err(e) => {
            println!("[Tag] failed to parse embedded DEFAULT_TAG_KEYWORDS: {}", e);
            HashMap::new()
        }
    }
}

/// 读取文件全文（转小写，用于关键词匹配）。支持 TXT 与 EPUB。
fn sample_file_raw(file_path: &str) -> String {
    use std::io::Read;
    let p = PathBuf::from(file_path);
    let ext = p
        .extension()
        .and_then(|e| e.to_str())
        .map(|s| s.to_lowercase());

    match ext.as_deref() {
        Some("txt") => {
            // 使用 TxtParser 解析 TXT（内置 chardetng 编码检测，正确处理 GBK/GB18030 等中文编码）
            match crate::parser::TxtParser::parse(&p) {
                Ok(content) => {
                    let mut acc = String::new();
                    for ch in content.chapters.iter() {
                        if let Some(c) = &ch.content {
                            acc.push_str(c);
                            acc.push('\n');
                        }
                    }
                    println!("[Tag] txt sample_len={} for {}", acc.len(), file_path);
                    acc.to_lowercase()
                }
                Err(e) => {
                    println!("[Tag] TxtParser failed for {}: {}", file_path, e);
                    String::new()
                }
            }
        }
        Some("epub") => {
            // 对 EPUB 使用解析器提取所有章节文本
            match crate::parser::EpubParser::parse(&p) {
                Ok(content) => {
                    let mut acc = String::new();
                    for ch in content.chapters.iter() {
                        if let Some(c) = &ch.content {
                            acc.push_str(c);
                            acc.push('\n');
                        }
                    }
                    acc.to_lowercase()
                }
                Err(_) => String::new(),
            }
        }
        _ => {
            // 其它格式：尝试读取为 UTF-8 文本，回退到读取前 1MB 的二进制并尝试转换
            match std::fs::read_to_string(&p) {
                Ok(s) => s.to_lowercase(),
                Err(_) => {
                    let mut buf = Vec::new();
                    if let Ok(mut f) = std::fs::File::open(&p) {
                        let _ = f.read_to_end(&mut buf);
                    }
                    String::from_utf8_lossy(&buf).to_lowercase()
                }
            }
        }
    }
}

/// 根据关键词规则对书籍自动打标签
fn apply_tag_keywords(novel: &mut NovelMetadata) {
    let rules = load_tag_keyword_rules();
    if rules.is_empty() {
        return;
    }
    let sample = sample_file_raw(&novel.file_path);
    // 调试日志：输出规则预览和样本片段，方便排查匹配失败原因
    println!("[Tag] rules_keys={:?}", rules.keys().collect::<Vec<_>>());
    println!(
        "[Tag] sample_len={} snippet={}",
        sample.len(),
        sample.chars().take(200).collect::<String>(),
    );
    if sample.is_empty() {
        return;
    }
    let mut tags: std::collections::HashSet<String> = novel.tags.iter().cloned().collect();
    for (tag, keywords) in &rules {
        for kw in keywords {
            let kw_l = kw.to_lowercase();
            if sample.contains(kw_l.as_str()) {
                println!(
                    "[Tag] matched tag='{}' keyword='{}' for file={} ",
                    tag,
                    kw,
                    novel.file_path,
                );
                tags.insert(tag.clone());
                break;
            }
        }
    }
    let mut tag_vec: Vec<String> = tags.into_iter().collect();
    tag_vec.sort();
    novel.tags = tag_vec;
}

/// 扫描文件夹获取书籍列表
#[frb(sync)]
pub fn scan_novels_folder(folder_path: String) -> Result<Vec<NovelMetadata>, String> {
    let scanner = DirectoryScanner::new("novels".to_string());
    let novels = scanner.scan(&folder_path).map_err(|e| e.to_string())?;

    let mut library = get_library().lock().map_err(|e| e.to_string())?;
    for novel in &novels {
        if let Some(existing) = library.iter_mut().find(|n| n.id == novel.id) {
            *existing = novel.clone();
        } else {
            library.push(novel.clone());
        }
        if let Ok(json) = serde_json::to_string(novel) {
            let _ = db_module::db_set("novels".to_string(), novel.id.clone(), json);
        }
    }

    Ok(novels)
}

/// 获取所有书籍列表
#[frb(sync)]
pub fn get_all_novels() -> Result<Vec<NovelMetadata>, String> {
    let library = get_library().lock().map_err(|e| e.to_string())?;
    Ok(library.clone())
}

/// 添加多个书籍（支持多路径）
#[frb(sync)]
pub fn add_novel(file_paths: Vec<String>) -> Result<Vec<NovelMetadata>, String> {
    let scanner = DirectoryScanner::new("novels".to_string());

    let mut added = Vec::new();
    let mut library = get_library().lock().map_err(|e| e.to_string())?;

    for path in file_paths.iter() {
        match scanner.scan_file(path) {
            Ok(mut novel) => {
                // 根据 tag_keyword.json 自动打标签
                apply_tag_keywords(&mut novel);

                if let Some(existing) = library.iter_mut().find(|n| n.id == novel.id) {
                    *existing = novel.clone();
                } else {
                    library.push(novel.clone());
                }
                if let Ok(json) = serde_json::to_string(&novel) {
                    let _ = db_module::db_set("novels".to_string(), novel.id.clone(), json);
                }
                added.push(novel);
            }
            Err(e) => {
                println!("[Novel] Failed to add {}: {}", path, e);
                continue;
            }
        }
    }

    Ok(added)
}

/// 删除书籍
#[frb(sync)]
pub fn remove_novel(novel_id: String) -> Result<bool, String> {
    let (removed, cover_path) = {
        let mut library = get_library().lock().map_err(|e| e.to_string())?;
        let cover = library
            .iter()
            .find(|n| n.id == novel_id)
            .and_then(|n| n.cover_path.clone());
        let initial_len = library.len();
        library.retain(|n| n.id != novel_id);
        (library.len() < initial_len, cover)
    };
    if removed {
        let _ = db_module::db_delete("novels".to_string(), novel_id.clone());
        if let Some(path) = cover_path {
            let _ = std::fs::remove_file(&path);
        }
        // 清理相关文件（使用应用数据目录）
        let app_dir = get_app_data_dir();
        let epub_images_dir = app_dir.join("epub_images").join(&novel_id);
        let _ = std::fs::remove_dir_all(&epub_images_dir);
        let covers_dir = app_dir.join("covers");
        for ext in &["jpg", "jpeg", "png", "webp", "gif"] {
            let p = covers_dir.join(format!("{}.{}", novel_id, ext));
            if p.exists() {
                let _ = std::fs::remove_file(&p);
            }
        }
    }
    Ok(removed)
}

/// 删除书籍及其文件
#[frb(sync)]
pub fn remove_novel_with_file(novel_id: String) -> Result<bool, String> {
    let file_path = {
        let library = get_library().lock().map_err(|e| e.to_string())?;
        library
            .iter()
            .find(|n| n.id == novel_id)
            .map(|n| n.file_path.clone())
    };

    let removed = remove_novel(novel_id)?;

    if removed {
        if let Some(path) = file_path {
            match std::fs::remove_file(&path) {
                Ok(_) => println!("[Novel] Deleted file: {}", path),
                Err(e) => println!("[Novel] Failed to delete file {}: {}", path, e),
            }
        }
    }

    Ok(removed)
}

/// 清空所有书籍
#[frb(sync)]
pub fn clear_all_novels() -> Result<(), String> {
    let mut library = get_library().lock().map_err(|e| e.to_string())?;
    for novel in library.iter() {
        let _ = db_module::db_delete("novels".to_string(), novel.id.clone());
    }
    library.clear();
    Ok(())
}

/// 获取书籍内容（带缓存）
pub fn get_novel_content(file_path: String) -> Result<NovelContent, String> {
    use std::fs;
    use std::sync::Once;
    use std::time::Instant;
    // 初始化日志（确保只初始化一次）以便将 Rust 层的 logger.info/debug! 输出到控制台
    static INIT_LOGGER: Once = Once::new();
    INIT_LOGGER.call_once(|| {
        let _ = env_logger::Builder::from_env(env_logger::Env::new().default_filter_or("info"))
            .try_init();
    });

    let start_time = Instant::now();
    println!("[Novel] Starting to load novel: {}", file_path);

    let path = PathBuf::from(&file_path);

    println!("[Novel] Checking file metadata...");
    let metadata = fs::metadata(&path).map_err(|e| {
        println!("[Novel] Failed to read file metadata: {}", e);
        format!("Failed to read file metadata: {}", e)
    })?;
    let modified = metadata
        .modified()
        .map_err(|e| format!("Failed to get file modified time: {}", e))?;
    let modified_time: DateTime<Utc> = modified.into();
    let file_size = metadata.len();
    println!(
        "[Novel] File size: {} bytes, modified: {:?}",
        file_size,
        modified_time,
    );

    {
        println!("[Novel] Checking cache...");
        let cache = get_content_cache().lock().map_err(|e| e.to_string())?;
        if let Some((cached_content, cached_time)) = cache.get(&file_path) {
            if cached_time >= &modified_time {
                let elapsed = start_time.elapsed();
                println!(
                    "[Novel] Cache hit! Returned in {:?}, chapters: {}",
                    elapsed,
                    cached_content.chapters.len(),
                );
                return Ok(cached_content.clone());
            } else {
                println!("[Novel] Cache expired (file modified), will re-parse");
            }
        } else {
            println!("[Novel] Cache miss, will parse file");
        }
    }

    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .ok_or_else(|| "Invalid file extension".to_string())?;

    println!("[Novel] Parsing {} file...", ext);
    let parse_start = Instant::now();
    let content = match ext.to_lowercase().as_str() {
        "txt" => {
            let result = crate::parser::TxtParser::parse(&path).map_err(|e: anyhow::Error| {
                println!("[Novel] TXT parse failed: {}", e);
                e.to_string()
            })?;
            println!(
                "[Novel] TXT parsed in {:?}, chapters: {}",
                parse_start.elapsed(),
                result.chapters.len(),
            );
            result
        }
        "epub" => {
            let result = crate::parser::EpubParser::parse(&path).map_err(|e: anyhow::Error| {
                println!("[Novel] EPUB parse failed: {}", e);
                e.to_string()
            })?;
            println!(
                "[Novel] EPUB parsed in {:?}, chapters: {}",
                parse_start.elapsed(),
                result.chapters.len(),
            );
            result
        }
        _ => return Err(format!("Unsupported file format: {}", ext)),
    };

    {
        println!("[Novel] Updating cache...");
        let mut cache = get_content_cache().lock().map_err(|e| e.to_string())?;
        cache.insert(file_path.clone(), (content.clone(), modified_time));
        println!(
            "[Novel] Cache updated, total cached novels: {}",
            cache.len(),
        );
    }

    let total_elapsed = start_time.elapsed();
    println!("[Novel] Total load time: {:?}", total_elapsed);
    Ok(content)
}

/// 获取书籍章节内容（按需加载）
pub fn get_chapter_content(file_path: String, chapter_index: usize) -> Result<String, String> {
    use std::path::PathBuf;

    println!(
        "[Novel] Getting chapter {} from {}",
        chapter_index,
        file_path,
    );

    let path = PathBuf::from(&file_path);
    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .ok_or_else(|| "Invalid file extension".to_string())?;

    match ext.to_lowercase().as_str() {
        "epub" => {
            // EPUB: 按需加载章节内容和图片
            println!("[Novel] Loading EPUB chapter {} on-demand", chapter_index);
            let result = crate::parser::EpubParser::get_chapter_content(&path, chapter_index)
                .map_err(|e| {
                    println!("[Novel] Failed to load EPUB chapter: {}", e);
                    e.to_string()
                })?;

            println!(
                "[Novel] EPUB chapter {} loaded, length: {} chars",
                chapter_index,
                result.len(),
            );
            Ok(result)
        }
        "txt" => {
            // TXT: 从缓存中获取（已在parse时全部加载）
            println!("[Novel] Loading TXT chapter {} from cache", chapter_index);
            let content = get_novel_content(file_path)?;

            let result = content
                .chapters
                .get(chapter_index)
                .and_then(|ch| ch.content.clone())
                .ok_or_else(|| {
                    println!(
                        "[Novel] Chapter {} not found or has no content",
                        chapter_index
                    );
                    format!("Chapter {} not found or has no content", chapter_index)
                })?;

            println!(
                "[Novel] TXT chapter {} loaded, length: {} chars",
                chapter_index,
                result.len(),
            );
            Ok(result)
        }
        _ => Err(format!("Unsupported file format: {}", ext)),
    }
}

/// 清除书籍内容缓存（强制下次打开时重新解析 epub 图片）
#[frb(sync)]
pub fn clear_novel_cache(file_path: String) -> Result<(), String> {
    let mut cache = get_content_cache().lock().map_err(|e| e.to_string())?;
    cache.remove(&file_path);

    // 同时清理相关的临时文件
    let novel_id = format!("{:x}", md5::compute(file_path.as_bytes()));
    let app_dir = get_app_data_dir();
    let epub_images_dir = app_dir.join("epub_images").join(&novel_id);
    let _ = std::fs::remove_dir_all(epub_images_dir);

    Ok(())
}

/// 移动书籍到文件夹
#[frb(sync)]
pub fn move_novel_to_folder(novel_id: String, folder_id: Option<String>) -> Result<bool, String> {
    let mut library = get_library().lock().map_err(|e| e.to_string())?;

    if let Some(novel) = library.iter_mut().find(|n| n.id == novel_id) {
        novel.folder_id = folder_id;
        if let Ok(json) = serde_json::to_string(&novel) {
            let _ = db_module::db_set("novels".to_string(), novel.id.clone(), json);
        }
        Ok(true)
    } else {
        Ok(false)
    }
}

/// 扫描进度回调结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScanBatchResult {
    pub novels: Vec<NovelMetadata>,
    pub completed: usize,
    pub total: usize,
    pub is_finished: bool,
}

/// 关键词规则（Dart 传入）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KeywordRuleInput {
    pub keyword: String,
    pub tag: String,
}

/// 关键词批处理进度
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KeywordApplyBatchResult {
    pub completed: usize,
    pub total: usize,
    pub updated: usize,
    pub is_finished: bool,
}

fn content_contains_keyword(content: &crate::types::NovelContent, keyword_lower: &str) -> bool {
    if keyword_lower.is_empty() {
        return false;
    }

    for chapter in &content.chapters {
        if let Some(text) = &chapter.content {
            if text.to_lowercase().contains(keyword_lower) {
                return true;
            }
        }
    }
    false
}

/// 对所有书籍分批应用关键词规则。
/// - start: 当前批次起始下标
/// - batch_size: 批大小
/// 返回当前批次结束后的整体进度，用于 Dart 侧显示 `x/y`。
pub fn apply_keyword_rules_to_all_novels_batch(
    rules: Vec<KeywordRuleInput>,
    start: usize,
    batch_size: usize,
) -> Result<KeywordApplyBatchResult, String> {
    if batch_size == 0 {
        return Err("batch_size must be > 0".to_string());
    }

    let cleaned_rules: Vec<(String, String)> = rules
        .into_iter()
        .filter_map(|r| {
            let keyword = r.keyword.trim().to_string();
            let tag = if r.tag.trim().is_empty() {
                keyword.clone()
            } else {
                r.tag.trim().to_string()
            };

            if keyword.is_empty() || tag.is_empty() {
                None
            } else {
                Some((keyword.to_lowercase(), tag))
            }
        })
        .collect();

    if cleaned_rules.is_empty() {
        return Ok(KeywordApplyBatchResult {
            completed: 0,
            total: 0,
            updated: 0,
            is_finished: true,
        });
    }

    let snapshot = {
        let library = get_library().lock().map_err(|e| e.to_string())?;
        library.clone()
    };

    let total = snapshot.len();
    if total == 0 {
        return Ok(KeywordApplyBatchResult {
            completed: 0,
            total: 0,
            updated: 0,
            is_finished: true,
        });
    }

    let begin = start.min(total);
    let end = (begin + batch_size).min(total);
    if begin >= end {
        return Ok(KeywordApplyBatchResult {
            completed: total,
            total,
            updated: 0,
            is_finished: true,
        });
    }

    let updates: Vec<(String, Vec<String>)> = snapshot[begin..end]
        .par_iter()
        .filter_map(|novel| {
            let content = match get_novel_content(novel.file_path.clone()) {
                Ok(c) => c,
                Err(_) => return None,
            };

            let mut tag_set: std::collections::HashSet<String> =
                novel.tags.iter().cloned().collect();
            let before_len = tag_set.len();

            for (keyword_lower, tag) in &cleaned_rules {
                if content_contains_keyword(&content, keyword_lower) {
                    tag_set.insert(tag.clone());
                }
            }

            if tag_set.len() <= before_len {
                return None;
            }

            let mut tags: Vec<String> = tag_set.into_iter().collect();
            tags.sort();
            Some((novel.id.clone(), tags))
        })
        .collect();

    let updated = updates.len();
    if updated > 0 {
        let mut library = get_library().lock().map_err(|e| e.to_string())?;
        for (novel_id, tags) in updates {
            if let Some(novel) = library.iter_mut().find(|n| n.id == novel_id) {
                novel.tags = tags;
                if let Ok(json) = serde_json::to_string(novel) {
                    let _ = db_module::db_set("novels".to_string(), novel.id.clone(), json);
                }
            }
        }
    }

    let completed = end;
    Ok(KeywordApplyBatchResult {
        completed,
        total,
        updated,
        is_finished: completed >= total,
    })
}

/// 批量扫描文件夹（分批返回结果，rayon 并行解析 + 自动打标签，避免 3k+ 文件时串行过慢）
pub fn scan_novels_folder_batched(
    folder_path: String,
    batch_size: usize,
) -> Result<Vec<ScanBatchResult>, String> {
    use rayon::prelude::*;

    let scanner = DirectoryScanner::new("novels".to_string());

    // 1. 收集文件路径（IO bound，顺序即可）
    let novel_paths = scanner
        .scan_paths(&folder_path)
        .map_err(|e| e.to_string())?;
    let total = novel_paths.len();

    // 2. 快照当前已有书籍（只读，避免长时间持锁）
    let existing_map: std::collections::HashMap<String, NovelMetadata> = {
        let library = get_library().lock().map_err(|e| e.to_string())?;
        library.iter().map(|n| (n.id.clone(), n.clone())).collect()
    };

    // 3. rayon 并行扫描 + 自动打标签（CPU bound，各线程独立处理，无锁竞争）
    let all_parsed: Vec<(NovelMetadata, bool)> = novel_paths
        .par_iter()
        .filter_map(|path| match scanner.scan_file(path) {
            Ok(mut novel) => {
                let is_new = !existing_map.contains_key(&novel.id);
                if is_new {
                    apply_tag_keywords(&mut novel);
                } else {
                    let existing = &existing_map[&novel.id];
                    novel.tags = existing.tags.clone();
                    novel.is_favorite = existing.is_favorite;
                    novel.notes = existing.notes.clone();
                    novel.custom_order = existing.custom_order;
                    novel.cover_path = existing.cover_path.clone();
                    novel.folder_id = existing.folder_id.clone();
                    novel.progress = existing.progress;
                    novel.current_chapter_id = existing.current_chapter_id.clone();
                    novel.last_read_at = existing.last_read_at;
                    novel.added_at = existing.added_at;
                }
                Some((novel, is_new))
            }
            Err(_) => None,
        })
        .collect();

    // 4. 统一写锁更新内存库 + 持久化 DB（顺序写入，避免锁竞争）
    {
        let mut library = get_library().lock().map_err(|e| e.to_string())?;
        for (novel, is_new) in &all_parsed {
            if *is_new {
                library.push(novel.clone());
            } else if let Some(existing) = library.iter_mut().find(|n| n.id == novel.id) {
                *existing = novel.clone();
            }
            if let Ok(json) = serde_json::to_string(novel) {
                let _ = db_module::db_set("novels".to_string(), novel.id.clone(), json);
            }
        }
    }

    // 5. 按 batch_size 分批封装返回结果（Dart 端显示进度）
    let novels: Vec<NovelMetadata> = all_parsed.into_iter().map(|(n, _)| n).collect();
    let mut all_batches = Vec::new();
    if novels.is_empty() {
        all_batches.push(ScanBatchResult {
            novels: vec![],
            completed: 0,
            total: 0,
            is_finished: true,
        });
    } else {
        for (batch_idx, chunk) in novels.chunks(batch_size).enumerate() {
            let completed = ((batch_idx + 1) * batch_size).min(total);
            let is_finished = completed >= total;
            all_batches.push(ScanBatchResult {
                novels: chunk.to_vec(),
                completed,
                total,
                is_finished,
            });
        }
    }

    Ok(all_batches)
}
