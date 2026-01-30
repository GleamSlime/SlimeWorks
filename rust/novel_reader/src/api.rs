use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::sync::{Arc, Mutex, OnceLock};

use crate::parser::NovelParser;
use crate::scanner::DirectoryScanner;
use crate::types::{NovelChapter, NovelContent, NovelFormat, NovelMetadata, ScanProgress};
use db_module;
use serde_json; // 使用工作区内的 db_module 来持久化元数据

// 全局存储的小说库
static NOVEL_LIBRARY: OnceLock<Arc<Mutex<Vec<NovelMetadata>>>> = OnceLock::new();

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

/// 获取小说内容
#[frb(sync)]
pub fn get_novel_content(file_path: String) -> Result<NovelContent, String> {
    let path = PathBuf::from(&file_path);
    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .ok_or_else(|| "Invalid file extension".to_string())?;

    match ext.to_lowercase().as_str() {
        "txt" => {
            let content = crate::parser::TxtParser::parse(&path).map_err(|e| e.to_string())?;
            Ok(content)
        }
        "epub" => {
            let content = crate::parser::EpubParser::parse(&path).map_err(|e| e.to_string())?;
            Ok(content)
        }
        _ => Err(format!("Unsupported file format: {}", ext)),
    }
}

/// 获取小说章节内容
#[frb(sync)]
pub fn get_chapter_content(file_path: String, chapter_index: usize) -> Result<String, String> {
    let content = get_novel_content(file_path)?;

    content
        .chapters
        .get(chapter_index)
        .and_then(|ch| ch.content.clone())
        .ok_or_else(|| format!("Chapter {} not found or has no content", chapter_index))
}

/// 搜索小说内容中的关键词
#[frb(sync)]
pub fn search_in_novel(file_path: String, keyword: String) -> Result<Vec<SearchMatch>, String> {
    let content = get_novel_content(file_path)?;
    let mut matches = Vec::new();

    for chapter in &content.chapters {
        if let Some(text) = &chapter.content {
            // 使用基于字符的搜索以避免在多字节 UTF-8 字符上按字节切片导致 panic
            let text_chars: Vec<char> = text.chars().collect();
            let text_lower_chars: Vec<char> = text.to_lowercase().chars().collect();
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
