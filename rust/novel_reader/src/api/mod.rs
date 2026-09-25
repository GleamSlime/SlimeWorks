use slime_logger::sw_info;
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

/// 小说库数据库文件路径（<应用数据目录>/db.redb）
fn novel_db_path() -> String {
    get_app_data_dir()
        .join("db.redb")
        .to_string_lossy()
        .to_string()
}

/// 将小说相关表绑定到 db.redb，并执行一次性散落数据迁移（幂等）。
/// 返回数据库路径。
fn bind_novel_tables() -> String {
    let db_path_str = novel_db_path();
    let _ = db_module::db_init(db_path_str.clone());
    // 绑定到专属文件，避免历史上全局单例被其他模块抢先导致数据写错文件
    for table in [
        "novels".to_string(),
        "novel_folders".to_string(),
        "novel_meta".to_string(),
    ] {
        let _ = db_module::db_bind_table(table, db_path_str.clone());
    }
    migrate_scattered_novel_data(&db_path_str);
    db_path_str
}

/// 一次性迁移：历史上全局 db 单例「先到先得」时，小说数据可能被写入其他模块的
/// 文件（如 media.db / music_player.db）。这里把散落记录合并回 db.redb（幂等，只执行一次）。
fn migrate_scattered_novel_data(db_path: &str) {
    // 幂等标记：已迁移过则跳过
    if let Ok(Some(flag)) =
        db_module::db_get("novel_meta".to_string(), "scatter_merged_v1".to_string())
    {
        if flag == "1" {
            return;
        }
    }

    // 显式标注类型：Android 等平台无 push 分支，否则类型推导失败（E0282）
    let mut candidates: Vec<std::path::PathBuf> = Vec::new();
    #[cfg(windows)]
    if let Ok(appdata) = std::env::var("APPDATA") {
        let base = std::path::Path::new(&appdata).join("SlimeWorks");
        candidates.push(base.join("media.db"));
        candidates.push(base.join("music_player.db"));
    }
    #[cfg(target_os = "macos")]
    if let Ok(home) = std::env::var("HOME") {
        let base = std::path::Path::new(&home)
            .join("Library")
            .join("Application Support")
            .join("SlimeWorks");
        candidates.push(base.join("media.db"));
        candidates.push(base.join("music_player.db"));
    }

    for candidate in &candidates {
        let src = candidate.to_string_lossy().into_owned();
        if src == db_path || !candidate.exists() {
            continue;
        }
        match db_module::db_merge_tables(
            src.clone(),
            db_path.to_string(),
            vec!["novels".to_string(), "novel_folders".to_string()],
            false,
        ) {
            Ok(n) if n > 0 => sw_info!("[novel_db] 从 {} 合并散落记录 {} 条", src, n),
            Ok(_) => {}
            Err(e) => sw_info!("[novel_db] 合并 {} 失败: {}", src, e),
        }
    }
    let _ = db_module::db_set(
        "novel_meta".to_string(),
        "scatter_merged_v1".to_string(),
        "1".to_string(),
    );
}

fn get_library() -> &'static Arc<Mutex<Vec<NovelMetadata>>> {
    NOVEL_LIBRARY.get_or_init(|| {
        // 尝试初始化数据库并从表中加载已保存的书籍元数据
        let library = Arc::new(Mutex::new(Vec::new()));

        // 绑定表到专属文件并迁移散落数据（优先使用系统应用数据目录，而非临时目录）
        let db_path_str = bind_novel_tables();
        println!("[NovelLibrary] Database path: {}", db_path_str);

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

        // 确保表已绑定到专属文件（幂等）
        let _ = bind_novel_tables();

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
                                p, e
                            );
                        }
                    },
                    Err(e) => {
                        println!(
                            "[Tag] failed to read override tag_keyword.json at {:?}: {}",
                            p, e
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
                    tag, kw, novel.file_path,
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
    use std::time::Instant;
    let start_time = Instant::now();
    sw_info!("[Novel] Starting to load novel: {}", file_path);

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
        file_size, modified_time,
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
        chapter_index, file_path,
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

// ─────────────────────────────────────────────────────────────
// 测试公共设施（仅 cfg(test) 编译，不进入生产二进制）
// ─────────────────────────────────────────────────────────────

/// 安全红线说明：
/// novel_reader 的 api 层全部经 `get_library()` / `get_folder_list()` 两个
/// `OnceLock` 单例 + db_module 的进程级表路由落库，DB 文件路径由
/// `get_app_data_dir()` → `$HOME/Library/Application Support/slimeworks/db.redb`
/// 推导（macOS 上大小写不敏感，正是用户真实小说库）。
///
/// 因此所有落库用例必须：
/// 1. 在**首次** DB 初始化之前，把 `HOME` 重定向到固定名临时目录（OnceLock 保证只设一次，开跑前清旧）；
/// 2. 由 `DB_TEST_LOCK` 全局串行，避免共享内存库/表路由互踩；
/// 3. 每个用例开头调用 `assert_db_isolated()` 做运行时自校验。
#[cfg(test)]
pub(crate) mod test_env {
    use std::io::Write;
    use std::path::{Path, PathBuf};
    use std::sync::{Mutex, MutexGuard, OnceLock};
    use std::time::{Duration, SystemTime};

    use super::{
        add_novel, bind_novel_tables, clear_all_novels, delete_folder, get_all_folders,
        novel_db_path,
    };
    use crate::types::NovelMetadata;

    /// DB 用例全局串行锁
    static DB_TEST_LOCK: Mutex<()> = Mutex::new(());

    /// 隔离后的运行环境（HOME + DB 文件路径）
    pub struct DbTestEnv {
        /// 隔离 HOME 根目录（固定名临时目录，下次运行开跑前清旧重建）
        pub home: PathBuf,
        /// 隔离后的小说库 redb 文件绝对路径
        pub db_path: String,
    }

    /// 初始化（且只初始化一次）隔离 DB 环境
    pub fn db_test_env() -> &'static DbTestEnv {
        static ENV: OnceLock<DbTestEnv> = OnceLock::new();
        ENV.get_or_init(|| {
            // 固定目录名 + 开跑前清旧：每次运行都从空目录开始，跑完至多一份残留，
            // 不会按 pid 在临时目录里无限累积（写入后归零的目录级保障）
            let home = std::env::temp_dir().join("novel_db_test_home");
            assert_eq!(
                home.parent(),
                Some(std::env::temp_dir().as_path()),
                "清理目标必须恰好位于系统临时目录下，防误删"
            );
            let _ = std::fs::remove_dir_all(&home);
            std::fs::create_dir_all(&home).expect("创建隔离 HOME 失败");
            // edition 2021：set_var 是安全接口；只在 OnceLock 初始化闭包里调用一次，
            // 之后 HOME 永不再变化，落库用例又全部串行，不存在反复改环境变量的竞态
            std::env::set_var("HOME", &home);
            // 关键：必须在任何 api 触发 get_library()/get_folder_list() 之前完成表绑定，
            // 否则 db_module 会把 novels 表路由到（此刻仍是真实的）用户库文件
            let db_path = bind_novel_tables();
            // 幂等性自检：重复绑定应成功且不改变路径
            let again = bind_novel_tables();
            assert_eq!(db_path, again, "bind_novel_tables 必须幂等");
            let home_str = home.to_string_lossy().into_owned();
            assert!(
                db_path.starts_with(&home_str),
                "DB 路径必须位于隔离 HOME 内，绝不触碰真实用户库: {db_path}"
            );
            DbTestEnv { home, db_path }
        })
    }

    /// 取 DB 串行锁，并在持锁状态下确保隔离环境已初始化
    pub fn lock_db_test_serial() -> MutexGuard<'static, ()> {
        let guard = DB_TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        db_test_env();
        guard
    }

    /// 运行时安全断言：DB 文件确实落在临时 HOME 内（每个落库用例开头调用）
    pub fn assert_db_isolated() {
        let env = db_test_env();
        let now = novel_db_path();
        assert_eq!(now, env.db_path, "测试期间 DB 路径不应发生变化");
        assert!(
            now.starts_with(env.home.to_string_lossy().as_ref()),
            "检测到 DB 路径逃逸出隔离 HOME: {now}"
        );
        assert!(
            std::env::var("HOME").map(|h| h == env.home.to_string_lossy()) .unwrap_or(false),
            "检测到 HOME 环境变量被改回真实用户目录"
        );
    }

    /// 用例目录树守卫：测试函数结束（含 panic  unwind）时自动整树删除，
    /// 实现「写入后删除、跑完归零」
    pub struct CaseDir(PathBuf);
    impl std::ops::Deref for CaseDir {
        type Target = PathBuf;
        fn deref(&self) -> &PathBuf {
            &self.0
        }
    }
    impl Drop for CaseDir {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    /// 在系统临时目录（隔离 HOME 之外）为某个用例准备一棵独立目录树。
    /// 固定名（tag 全局唯一，不再拼 pid），开跑前清旧 + 用例结束自动删除
    pub fn case_dir(tag: &str) -> CaseDir {
        let dir = std::env::temp_dir().join(format!("novel_api_test_{}", tag));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("创建用例目录失败");
        CaseDir(dir)
    }

    /// 写入任意文本文件
    pub fn write_text(path: &Path, content: &str) {
        if let Some(parent) = path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        let mut f = std::fs::File::create(path).expect("写入测试文件失败");
        f.write_all(content.as_bytes()).expect("写入测试文件内容失败");
        f.flush().ok();
    }

    /// 写一本固定两章的 txt 小说，返回文件路径
    pub fn write_novel_txt(dir: &Path, file_stem: &str, body1: &str, body2: &str) -> PathBuf {
        let path = dir.join(format!("{}.txt", file_stem));
        let text = format!("第一章 开端\n{}\n第二章 结局\n{}\n", body1, body2);
        write_text(&path, &text);
        path
    }

    /// 写一本单章（无章节标记 → 解析为「全文」）的 txt 小说
    pub fn write_plain_txt(dir: &Path, file_stem: &str, body: &str) -> PathBuf {
        let path = dir.join(format!("{}.txt", file_stem));
        write_text(&path, body);
        path
    }

    /// 设置文件修改时间（不截断内容）
    pub fn set_mtime(path: &Path, when: SystemTime) {
        let f = std::fs::OpenOptions::new()
            .write(true)
            .open(path)
            .expect("打开文件以设置 mtime 失败");
        f.set_modified(when).expect("设置文件修改时间失败");
    }

    /// 可稳定复现的固定时间戳（用于缓存过期判定用例）
    pub fn fixed_mtime() -> SystemTime {
        SystemTime::UNIX_EPOCH + Duration::from_secs(1_700_000_000)
    }

    /// 用 zip 写入库构造一个最小合法 EPUB2（含 NCX 目录 + 两章 XHTML）
    pub fn write_minimal_epub(dir: &Path, file_stem: &str, ch1_body: &str, ch2_body: &str) -> PathBuf {
        use zip::write::FileOptions;
        use zip::CompressionMethod;

        let path = dir.join(format!("{}.epub", file_stem));
        let file = std::fs::File::create(&path).expect("创建 epub 文件失败");
        let mut writer = zip::ZipWriter::new(file);
        let stored = FileOptions::default().compression_method(CompressionMethod::Stored);

        // mimetype（规范要求为首个条目）
        writer.start_file("mimetype", stored).unwrap();
        writer.write_all(b"application/epub+zip").unwrap();

        writer
            .start_file("META-INF/container.xml", stored)
            .unwrap();
        writer
            .write_all(
                br#"<?xml version="1.0" encoding="UTF-8"?>
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>"#,
            )
            .unwrap();

        let opf = r#"<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>接口层测试书</dc:title>
    <dc:creator>测试作者</dc:creator>
    <dc:identifier id="bookid">urn:uuid:1a2b3c4d-0000-4000-8000-0000000000aa</dc:identifier>
    <dc:language>zh-CN</dc:language>
    <meta name="generator" content="test"/>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx" progression="ltr">
    <itemref idref="ch1"/>
    <itemref idref="ch2"/>
  </spine>
</package>"#;
        writer.start_file("OEBPS/content.opf", stored).unwrap();
        writer.write_all(opf.as_bytes()).unwrap();

        let ncx = r#"<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head>
    <meta name="dtb:uid" content="urn:uuid:1a2b3c4d-0000-4000-8000-0000000000aa"/>
    <meta name="dtb:depth" content="1"/>
    <meta name="dtb:totalPageCount" content="0"/>
    <meta name="dtb:maxPageNumber" content="0"/>
  </head>
  <docTitle><text>测试目录</text></docTitle>
  <navMap>
    <navPoint id="np1" playOrder="1">
      <navLabel><text>第一章 开端</text></navLabel>
      <content src="chapter1.xhtml"/>
    </navPoint>
    <navPoint id="np2" playOrder="2">
      <navLabel><text>第二章 结局</text></navLabel>
      <content src="chapter2.xhtml"/>
    </navPoint>
  </navMap>
</ncx>"#;
        writer.start_file("OEBPS/toc.ncx", stored).unwrap();
        writer.write_all(ncx.as_bytes()).unwrap();

        let ch1 = format!(
            r#"<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>第一章</title></head>
<body><h1>第一章 开端</h1><p>{}</p></body></html>"#,
            ch1_body
        );
        let ch2 = format!(
            r#"<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>第二章</title></head>
<body><h1>第二章 结局</h1><p>{}</p></body></html>"#,
            ch2_body
        );
        writer
            .start_file("OEBPS/chapter1.xhtml", stored)
            .unwrap();
        writer.write_all(ch1.as_bytes()).unwrap();
        writer
            .start_file("OEBPS/chapter2.xhtml", stored)
            .unwrap();
        writer.write_all(ch2.as_bytes()).unwrap();

        writer.finish().expect("写入 epub zip 失败");
        path
    }

    /// 生成一张可解码的小 PNG（供封面用例做源图）
    pub fn write_test_png(path: &Path, w: u32, h: u32) {
        let img = image::RgbImage::from_fn(w, h, |x, y| {
            image::Rgb([(x * 7 + y) as u8, (x * 3) as u8, (y * 11) as u8])
        });
        img.save(path).expect("写入测试 PNG 失败");
    }

    /// 读回 DB 中一条记录的原始 JSON
    pub fn db_row(table: &str, key: &str) -> Option<String> {
        db_module::db_get(table.to_string(), key.to_string()).unwrap()
    }

    /// 列出某张表全部 (key, value)
    pub fn db_rows(table: &str) -> Vec<(String, String)> {
        db_module::db_list_all(table.to_string())
            .unwrap_or_default()
            .into_iter()
            .map(|r| (r.key, r.value))
            .collect()
    }

    /// 复位内存库 + 隔离库中的两张表，让每个用例从干净状态开始
    pub fn reset_library_state() {
        // 先删文件夹（delete_folder 会把书退回根目录），再清书
        for folder in get_all_folders().unwrap_or_default() {
            let _ = delete_folder(folder.id);
        }
        clear_all_novels().expect("清空书籍库失败");
        // 兜底：确保隔离库两张表彻底为空（用例断言依赖干净起点）
        let _ = db_module::db_clear_table("novels".to_string());
        let _ = db_module::db_clear_table("novel_folders".to_string());
        assert!(get_all_novels_is_empty_after_reset(), "复位后内存库应为空");
    }

    fn get_all_novels_is_empty_after_reset() -> bool {
        super::get_all_novels().map(|v| v.is_empty()).unwrap_or(false)
    }

    /// 添加单个文件并断言成功，返回其元数据
    pub fn add_single_novel(path: &Path) -> NovelMetadata {
        let added = add_novel(vec![path.to_string_lossy().into_owned()])
            .expect("add_novel 调用应成功");
        assert_eq!(added.len(), 1, "单文件添加应返回 1 条记录");
        added.into_iter().next().expect("刚才已断言长度为 1")
    }
}

#[cfg(test)]
mod tests {
    use super::test_env::*;
    use super::*;
    use crate::types::NovelFormat;
    use std::time::Duration;

    // ── 隔离环境自证 ───────────────────────────────────────────────────────

    #[test]
    fn db_env_stays_inside_temporary_home() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        let env = db_test_env();
        // 隔离 HOME 必须在系统临时目录下，且真实用户库文件不应被打开
        assert!(env
            .home
            .starts_with(std::env::temp_dir()));
        assert!(env.db_path.ends_with("db.redb"));
        // novel_meta 里的一次性迁移标记应写在隔离库内
        let flag = db_module::db_get("novel_meta".to_string(), "scatter_merged_v1".to_string())
            .unwrap();
        assert_eq!(flag.as_deref(), Some("1"), "迁移标记应落在隔离库");
    }

    // ── scan_novels_folder ─────────────────────────────────────────────────

    #[test]
    fn scan_folder_persists_supported_files_only() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        let dir = case_dir("scan");
        write_novel_txt(&dir, "剑影江湖", "少年踏入山城，雨落无声。", "刀光过后，长街归寂。");
        write_novel_txt(&dir.join("sub"), "嵌套书", "山一程。", "水一程。");
        write_text(&dir.join("说明.pdf"), "%PDF-1.4 伪装文件");
        write_text(&dir.join(".隐藏.txt"), "隐藏文件应被跳过");

        let novels = scan_novels_folder(dir.to_string_lossy().into_owned()).unwrap();
        assert_eq!(novels.len(), 2, "只应收录 txt/epub（含递归子目录）");

        // 内存库 + DB 双落地
        let lib = get_all_novels().unwrap();
        assert_eq!(lib.len(), 2);
        for novel in &novels {
            let raw = db_row("novels", &novel.id).expect("扫描结果必须落库");
            let stored: NovelMetadata = serde_json::from_str(&raw).unwrap();
            assert_eq!(stored.title, novel.title);
            assert_eq!(stored.file_path, novel.file_path);
        }

        // 再次扫描走「已存在则覆盖」分支，不产生重复记录
        let again = scan_novels_folder(dir.to_string_lossy().into_owned()).unwrap();
        assert_eq!(again.len(), 2);
        assert_eq!(get_all_novels().unwrap().len(), 2, "重复扫描不应产生重复条目");
        assert_eq!(db_rows("novels").len(), 2);
    }

    #[test]
    fn scan_folder_rejects_missing_dir_and_plain_file() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        let dir = case_dir("scan_err");
        let p = write_novel_txt(&dir, "正常书", "一句。", "两句。");
        // 不存在的目录
        assert!(scan_novels_folder(dir.join("不存在的路径").to_string_lossy().into_owned()).is_err());
        // 传文件而非目录
        assert!(scan_novels_folder(p.to_string_lossy().into_owned()).is_err());
    }

    // ── scan_novels_folder_batched ─────────────────────────────────────────

    #[test]
    fn scan_batched_reports_progress_and_tags_new_books() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        let dir = case_dir("batched");
        write_novel_txt(&dir, "武侠一", "他习武多年，一朝行走武侠世界。", "刀再快，也快不过人心。");
        write_novel_txt(&dir, "武侠二", "武侠之路无绝期。", "归来仍是少年。");
        write_novel_txt(&dir, "闲书", "市井烟火气。", "柴米油盐。");

        let batches = scan_novels_folder_batched(dir.to_string_lossy().into_owned(), 2).unwrap();
        assert_eq!(batches.len(), 2, "3 本书按批大小 2 应分两批");
        assert_eq!(batches[0].novels.len(), 2);
        assert_eq!(batches[0].total, 3);
        assert_eq!(batches[0].completed, 2);
        assert!(!batches[0].is_finished);
        assert_eq!(batches[1].novels.len(), 1);
        assert_eq!(batches[1].completed, 3);
        assert!(batches[1].is_finished, "最后一批必须标记完成");

        // 新书走 apply_tag_keywords：含「武侠」的应被打上内置规则标签
        let lib = get_all_novels().unwrap();
        let wuxia = lib.iter().find(|n| n.title == "武侠一").unwrap();
        assert!(wuxia.tags.iter().any(|t| t == "武侠"), "内置关键词规则应命中");
        let plain = lib.iter().find(|n| n.title == "闲书").unwrap();
        assert!(!plain.tags.contains(&"武侠".to_string()), "未命中关键词不应带该标签");
    }

    #[test]
    fn scan_batched_preserves_user_edited_fields() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        let dir = case_dir("batched_keep");
        let p = write_novel_txt(&dir, "原名书", "第一段。", "第二段。");
        let novel = add_single_novel(&p);
        // 用户侧编辑
        rename_novel(novel.id.clone(), "我改的名".to_string()).unwrap();
        set_novel_favorite(novel.id.clone(), true).unwrap();
        update_reading_progress(novel.id.clone(), 0.42).unwrap();
        update_novel_tags(novel.id.clone(), vec!["我的标签".to_string()]).unwrap();

        // 重扫：已存在条目应保留用户字段，而不是被解析器结果覆盖
        let batches = scan_novels_folder_batched(dir.to_string_lossy().into_owned(), 10).unwrap();
        let rescan = &batches[0].novels[0];
        assert!(rescan.is_favorite);
        assert!((rescan.progress - 0.42).abs() < 1e-6);
        assert_eq!(rescan.tags, vec!["我的标签".to_string()]);
        assert_eq!(rescan.added_at, novel.added_at, "已收录书籍的加入时间不应被刷新");
        // 已知行为缺陷：批量重扫只回填 tags/favorite/progress 等字段，
        // title 仍取解析器结果（文件名），自定义标题会被冲掉。此处按实际行为断言并留档。
        assert_eq!(rescan.title, "原名书");
        assert_eq!(rescan.id, novel.id, "同一路径重扫必须复用同一 id");
        // 重扫后落库内容也要与内存一致
        let raw = db_row("novels", &novel.id).unwrap();
        let stored: NovelMetadata = serde_json::from_str(&raw).unwrap();
        assert_eq!(stored.tags, vec!["我的标签".to_string()]);
        assert!((stored.progress - 0.42).abs() < 1e-6);
    }

    #[test]
    fn scan_batched_on_empty_dir_returns_single_finished_batch() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        let dir = case_dir("batched_empty");
        let batches = scan_novels_folder_batched(dir.to_string_lossy().into_owned(), 3).unwrap();
        assert_eq!(batches.len(), 1);
        assert!(batches[0].novels.is_empty());
        assert_eq!(batches[0].total, 0);
        assert!(batches[0].is_finished);
        // 不存在的目录仍应报错
        assert!(scan_novels_folder_batched(dir.join("没有这层").to_string_lossy().into_owned(), 3).is_err());
    }

    // ── add_novel + 内容往返 ───────────────────────────────────────────────

    #[test]
    fn add_novel_roundtrip_content_and_chapter() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        let dir = case_dir("roundtrip");
        let p = write_novel_txt(&dir, "往返测试", "少年握剑走入雨中。", "雨停之后剑已入鞘。");

        let novel = add_single_novel(&p);
        assert_eq!(novel.title, "往返测试", "标题取文件名去扩展名");
        assert_eq!(novel.id, format!("{:x}", md5::compute(p.to_string_lossy().as_bytes())));
        assert_eq!(novel.file_path, p.to_string_lossy().to_string());
        assert_eq!(novel.file_size, std::fs::metadata(&p).unwrap().len());
        assert!(get_all_novels().unwrap().iter().any(|n| n.id == novel.id));
        assert!(db_row("novels", &novel.id).is_some(), "添加后必须落库");

        let content = get_novel_content(p.to_string_lossy().into_owned()).unwrap();
        assert_eq!(content.novel_id, novel.id);
        assert_eq!(content.chapters.len(), 2, "两章标记应拆成两章");
        assert_eq!(content.chapters[0].title, "第一章 开端");
        assert_eq!(content.chapters[1].index, 1);
        assert!(content.chapters[1]
            .content
            .as_ref()
            .unwrap()
            .contains("剑已入鞘"));

        let ch0 = get_chapter_content(p.to_string_lossy().into_owned(), 0).unwrap();
        assert!(ch0.contains("走入雨中"));
        // 第二次读取走缓存，结果一致
        let ch0_again = get_chapter_content(p.to_string_lossy().into_owned(), 0).unwrap();
        assert_eq!(ch0, ch0_again);
    }

    #[test]
    fn add_novel_applies_embedded_keyword_rules() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        let dir = case_dir("autotag");
        // 命中内置规则 tag_keyword.json 的「玄幻」关键词
        let hit = write_plain_txt(&dir, "玄幻书", "这是一部玄幻长篇，跨越山海。");
        // 不命中任何规则
        let miss = write_plain_txt(&dir, "无规则书", "市井之间，烟火日常。");

        let hit_novel = add_single_novel(&hit);
        assert!(hit_novel.tags.iter().any(|t| t == "玄幻"), "命中关键词应自动打标签");
        let miss_novel = add_single_novel(&miss);
        assert!(!miss_novel.tags.contains(&"玄幻".to_string()));
        assert!(!miss_novel.tags.contains(&"武侠".to_string()));

        // 自动标签同样要落库
        let raw = db_row("novels", &hit_novel.id).unwrap();
        assert!(raw.contains("玄幻"), "标签持久化后应能从 DB JSON 中看到");
    }

    #[test]
    fn add_novel_skips_missing_paths_and_updates_existing() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        let dir = case_dir("add_dedup");
        let p = write_novel_txt(&dir, "重复书", "一。", "二。");
        let missing = dir.join("不存在.txt");

        let added = add_novel(vec![
            missing.to_string_lossy().into_owned(),
            p.to_string_lossy().into_owned(),
        ])
        .unwrap();
        assert_eq!(added.len(), 1, "不存在的路径应被跳过而不是报错");
        assert_eq!(get_all_novels().unwrap().len(), 1);

        // 同一路径重复添加 → 覆盖已有条目，条目数不变
        let again = add_novel(vec![p.to_string_lossy().into_owned()]).unwrap();
        assert_eq!(again.len(), 1);
        assert_eq!(get_all_novels().unwrap().len(), 1);
        assert_eq!(db_rows("novels").len(), 1);

        // 全部路径无效 → Ok 且返回空
        assert!(add_novel(vec![missing.to_string_lossy().into_owned()]).unwrap().is_empty());
    }

    // ── get_novel_content / get_chapter_content 错误分支 ───────────────────

    #[test]
    fn get_novel_content_error_branches() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        let dir = case_dir("content_err");
        // 1) 文件不存在
        let err = get_novel_content(dir.join("查无此书.txt").to_string_lossy().into_owned()).unwrap_err();
        assert!(err.contains("metadata"), "错误信息应说明读元数据失败: {err}");
        // 2) 不支持的扩展名
        let pdf = dir.join("假书.pdf");
        write_text(&pdf, "%PDF-1.4");
        let err = get_novel_content(pdf.to_string_lossy().into_owned()).unwrap_err();
        assert!(err.contains("Unsupported file format"), "应报不支持格式: {err}");
        // 3) 无扩展名
        let noext = dir.join("无扩展名");
        write_text(&noext, "随便一些文字");
        let err = get_novel_content(noext.to_string_lossy().into_owned()).unwrap_err();
        assert_eq!(err, "Invalid file extension");
    }

    #[test]
    fn get_chapter_content_error_branches() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        let dir = case_dir("chapter_err");
        let p = write_novel_txt(&dir, "越界书", "第一章正文。", "第二章正文。");
        // 正常索引
        assert!(get_chapter_content(p.to_string_lossy().into_owned(), 1).is_ok());
        // 越界索引
        let err = get_chapter_content(p.to_string_lossy().into_owned(), 99).unwrap_err();
        assert!(err.contains("not found"), "越界章节应报未找到: {err}");
        // 不支持的扩展名（扩展名检查发生在读文件之前）
        assert!(get_chapter_content("/tmp/某书.pdf".to_string(), 0)
            .unwrap_err()
            .contains("Unsupported file format"));
        // 无扩展名
        assert_eq!(
            get_chapter_content("/tmp/no_extension_here".to_string(), 0).unwrap_err(),
            "Invalid file extension"
        );
    }

    // ── 内容缓存 + clear_novel_cache ───────────────────────────────────────

    #[test]
    fn content_cache_serves_stale_copy_until_cleared() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        let dir = case_dir("cache");
        let p = dir.join("缓存书.txt");
        let stamp = fixed_mtime();

        write_text(&p, "第一版：内容甲");
        set_mtime(&p, stamp);
        let first = get_novel_content(p.to_string_lossy().into_owned()).unwrap();
        assert!(first.chapters[0].content.as_ref().unwrap().contains("内容甲"));

        // 内容变了但 mtime 复位成同一时刻 → 命中缓存拿到旧内容
        write_text(&p, "第二版：内容乙");
        set_mtime(&p, stamp);
        let cached = get_novel_content(p.to_string_lossy().into_owned()).unwrap();
        assert!(
            cached.chapters[0].content.as_ref().unwrap().contains("内容甲"),
            "缓存未被判过期时应返回旧内容"
        );

        // 显式清缓存 → 强制重解析拿到新内容
        clear_novel_cache(p.to_string_lossy().into_owned()).unwrap();
        let fresh = get_novel_content(p.to_string_lossy().into_owned()).unwrap();
        assert!(fresh.chapters[0].content.as_ref().unwrap().contains("内容乙"));

        // 清理未知路径不应报错
        assert!(clear_novel_cache(dir.join("没缓存.txt").to_string_lossy().into_owned()).is_ok());
    }

    #[test]
    fn cache_expires_when_file_modified_newer() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        let dir = case_dir("cache_expire");
        let p = dir.join("更新书.txt");
        write_text(&p, "旧版：甲");
        set_mtime(&p, fixed_mtime());
        assert!(get_novel_content(p.to_string_lossy().into_owned())
            .unwrap()
            .chapters[0]
            .content
            .as_ref()
            .unwrap()
            .contains("旧版"));

        // 把 mtime 往前推一小时 → 缓存时间早于文件时间，判过期并重解析
        write_text(&p, "新版：乙");
        set_mtime(
            &p,
            fixed_mtime() + Duration::from_secs(3600),
        );
        let content = get_novel_content(p.to_string_lossy().into_owned()).unwrap();
        assert!(content.chapters[0].content.as_ref().unwrap().contains("新版"));
    }

    // ── remove / clear ─────────────────────────────────────────────────────

    #[test]
    fn remove_novel_clears_memory_and_db() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        let dir = case_dir("remove");
        let a = write_novel_txt(&dir, "将被删", "甲。", "乙。");
        let b = write_novel_txt(&dir, "继续留", "甲二。", "乙二。");
        let na = add_single_novel(&a);
        let nb = add_single_novel(&b);

        assert!(remove_novel(na.id.clone()).unwrap());
        assert_eq!(db_row("novels", &na.id), None, "删除后 DB 记录应消失");
        let lib = get_all_novels().unwrap();
        assert_eq!(lib.len(), 1);
        assert_eq!(lib[0].id, nb.id, "另一本书不应被误删");
        assert!(a.exists(), "remove_novel 不删源文件");

        // 重复删除 / 非法 id → false
        assert!(!remove_novel(na.id.clone()).unwrap());
        assert!(!remove_novel("不存在的id".to_string()).unwrap());
        assert!(!remove_novel_with_file("不存在的id".to_string()).unwrap());
    }

    #[test]
    fn remove_novel_with_file_deletes_source_file() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        let dir = case_dir("remove_file");
        let p = write_novel_txt(&dir, "带文件删", "甲。", "乙。");
        let novel = add_single_novel(&p);

        assert!(remove_novel_with_file(novel.id.clone()).unwrap());
        assert!(!p.exists(), "带文件删除应移除磁盘上的 txt");
        assert!(get_all_novels().unwrap().is_empty());
        assert_eq!(db_row("novels", &novel.id), None);
    }

    #[test]
    fn clear_all_novels_empties_library_and_table() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        let dir = case_dir("clear");
        write_novel_txt(&dir, "一本书", "甲。", "乙。");
        write_novel_txt(&dir, "二本书", "甲。", "乙。");
        scan_novels_folder(dir.to_string_lossy().into_owned()).unwrap();
        assert_eq!(get_all_novels().unwrap().len(), 2);

        clear_all_novels().unwrap();
        assert!(get_all_novels().unwrap().is_empty());
        assert!(db_rows("novels").is_empty(), "清空后表内不应残留记录");
        // 空库再次清空仍成功
        clear_all_novels().unwrap();
    }

    // ── move_novel_to_folder ───────────────────────────────────────────────

    #[test]
    fn move_novel_to_folder_persists_folder_id() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        let dir = case_dir("move");
        let p = write_novel_txt(&dir, "待移动", "甲。", "乙。");
        let novel = add_single_novel(&p);
        let folder = create_folder("我的书架".to_string()).unwrap();

        assert!(move_novel_to_folder(novel.id.clone(), Some(folder.id.clone())).unwrap());
        let moved = get_all_novels().unwrap().into_iter().find(|n| n.id == novel.id).unwrap();
        assert_eq!(moved.folder_id.as_deref(), Some(folder.id.as_str()));
        let raw = db_row("novels", &novel.id).unwrap();
        assert!(raw.contains(&folder.id), "folder_id 必须写入 DB JSON");

        // 移回根目录
        assert!(move_novel_to_folder(novel.id.clone(), None).unwrap());
        assert_eq!(
            get_all_novels()
                .unwrap()
                .into_iter()
                .find(|n| n.id == novel.id)
                .unwrap()
                .folder_id,
            None
        );
        // 非法 id → false
        assert!(!move_novel_to_folder("查无此书".to_string(), Some(folder.id)).unwrap());
    }

    // ── apply_keyword_rules_to_all_novels_batch ────────────────────────────

    #[test]
    fn apply_keyword_rules_batches_hits_misses_and_idempotence() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        let dir = case_dir("kw_rules");
        let a = write_novel_txt(&dir, "星辰之子", "他抬头望见漫天星辰。", "星辰之下是故乡。");
        let b = write_novel_txt(&dir, "无关之书", "只谈风月。", "不谈别的。");
        let c = write_novel_txt(&dir, "文件丢失", "甲。", "乙。");
        let na = add_single_novel(&a);
        let nb = add_single_novel(&b);
        let nc = add_single_novel(&c);
        // 制造「解析失败」分支：源文件被删除
        std::fs::remove_file(&c).unwrap();

        let rules = vec![
            KeywordRuleInput {
                keyword: "星辰".to_string(),
                tag: "星辰类".to_string(),
            },
            KeywordRuleInput {
                keyword: "   ".to_string(), // 空白关键词应被过滤
                tag: "不该出现".to_string(),
            },
            KeywordRuleInput {
                keyword: "绝不存在之词".to_string(),
                tag: "也不该出现".to_string(),
            },
            KeywordRuleInput {
                keyword: "漫天".to_string(),
                tag: "  ".to_string(), // tag 为空白 → 回退成关键词本身
            },
        ];

        // 第一批：a + b
        let first = apply_keyword_rules_to_all_novels_batch(rules.clone(), 0, 2).unwrap();
        assert_eq!(first.total, 3);
        assert_eq!(first.completed, 2);
        assert!(!first.is_finished);
        assert_eq!(first.updated, 1, "只有 a 命中");

        // 第二批：c（文件已删 → 跳过，不计入 updated）
        let second = apply_keyword_rules_to_all_novels_batch(rules.clone(), 2, 2).unwrap();
        assert_eq!(second.completed, 3);
        assert!(second.is_finished);
        assert_eq!(second.updated, 0);

        let lib = get_all_novels().unwrap();
        let ta = lib.iter().find(|n| n.id == na.id).unwrap();
        assert!(ta.tags.contains(&"星辰类".to_string()));
        assert!(ta.tags.contains(&"漫天".to_string()), "空白 tag 应回退成关键词");
        assert!(!ta.tags.contains(&"不该出现".to_string()));
        assert!(!ta.tags.contains(&"也不该出现".to_string()));
        let tb = lib.iter().find(|n| n.id == nb.id).unwrap();
        assert!(!tb.tags.contains(&"星辰类".to_string()), "正文未命中的书不应被打该标签");
        assert!(db_row("novels", &na.id).unwrap().contains("星辰类"), "标签更新要落库");
        assert!(db_row("novels", &nc.id).is_some(), "解析失败的书仍在库里");

        // 幂等：再跑一遍不应有新更新
        let third = apply_keyword_rules_to_all_novels_batch(rules, 0, 10).unwrap();
        assert_eq!(third.updated, 0);
        assert_eq!(third.completed, 3);
        assert!(third.is_finished);
    }

    #[test]
    fn apply_keyword_rules_edge_parameters() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        let one_rule = vec![KeywordRuleInput {
            keyword: "星辰".to_string(),
            tag: "星辰类".to_string(),
        }];

        // batch_size = 0 → 参数错误
        assert_eq!(
            apply_keyword_rules_to_all_novels_batch(one_rule.clone(), 0, 0).unwrap_err(),
            "batch_size must be > 0"
        );
        // 规则为空 / 全部无效 → 直接完成
        assert!(apply_keyword_rules_to_all_novels_batch(vec![], 0, 5).unwrap().is_finished);
        let only_blank = vec![KeywordRuleInput {
            keyword: " ".to_string(),
            tag: "x".to_string(),
        }];
        let r = apply_keyword_rules_to_all_novels_batch(only_blank, 0, 5).unwrap();
        assert_eq!((r.completed, r.total, r.updated, r.is_finished), (0, 0, 0, true));

        // 空库 + 有效规则 → total 0
        let r = apply_keyword_rules_to_all_novels_batch(one_rule.clone(), 0, 5).unwrap();
        assert_eq!((r.completed, r.total, r.updated, r.is_finished), (0, 0, 0, true));

        // 起始下标越界 → 直接返回完成
        let dir = case_dir("kw_edge");
        let p = write_novel_txt(&dir, "越界起点", "甲。", "乙。");
        add_single_novel(&p);
        let r = apply_keyword_rules_to_all_novels_batch(one_rule, 99, 2).unwrap();
        assert_eq!((r.completed, r.total, r.updated), (1, 1, 0));
        assert!(r.is_finished);
    }

    // ── EPUB 分支（api 层）─────────────────────────────────────────────────

    #[test]
    fn epub_content_and_chapter_via_api() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        let dir = case_dir("epub_api");
        let p = write_minimal_epub(&dir, "接口_epub", "风起于青萍之末。", "一切归于平静。");
        let novel = add_single_novel(&p);
        assert_eq!(novel.title, "接口层测试书", "epub 标题应取 dc:title");
        assert_eq!(novel.author.as_deref(), Some("测试作者"));
        assert!(matches!(novel.format, NovelFormat::Epub));

        let content = get_novel_content(p.to_string_lossy().into_owned()).unwrap();
        assert_eq!(content.chapters.len(), 2, "epub 应解析出两章");

        // epub 走按需加载分支
        let ch0 = get_chapter_content(p.to_string_lossy().into_owned(), 0).unwrap();
        assert!(ch0.contains("风起于青萍之末"), "按需加载应返回章节 HTML 内容: {ch0}");
        let ch1 = get_chapter_content(p.to_string_lossy().into_owned(), 1).unwrap();
        assert!(ch1.contains("归于平静"));
        // 越界索引 → 解析器报错
        assert!(get_chapter_content(p.to_string_lossy().into_owned(), 42).is_err());
    }
}
