use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};
use std::sync::{Arc, Mutex, OnceLock};

use crate::types::NovelMetadata;

use super::{get_library, get_novel_content};

/// 搜索匹配结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchMatch {
    pub chapter_index: usize,
    pub chapter_title: String,
    pub position: usize,
    pub snippet: String,
}

/// 搜索结果：包含书籍元数据和匹配计数
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

/// 搜索书籍内容中的关键词（支持EPUB按需加载）
pub fn search_in_novel(file_path: String, keyword: String) -> Result<Vec<SearchMatch>, String> {
    use std::path::PathBuf;

    let path = PathBuf::from(&file_path);
    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .ok_or_else(|| "Invalid file extension".to_string())?;

    let content = get_novel_content(file_path.clone())?;
    let mut matches = Vec::new();

    match ext.to_lowercase().as_str() {
        "epub" => {
            // EPUB: 按需加载每一章节内容
            println!(
                "[Search] Searching in EPUB, {} chapters",
                content.chapters.len()
            );

            for chapter in &content.chapters {
                // 按需加载章节内容
                let text =
                    match crate::parser::EpubParser::get_chapter_content(&path, chapter.index) {
                        Ok(content) => content,
                        Err(e) => {
                            println!("[Search] Failed to load chapter {}: {}", chapter.index, e);
                            continue;
                        }
                    };

                // 去除HTML标签后再搜索
                let clean_text = strip_all_html_tags(&text);
                search_in_text(&clean_text, &keyword, chapter, &mut matches);
            }
        }
        "txt" => {
            // TXT: 从缓存中获取（已在parse时全部加载）
            println!(
                "[Search] Searching in TXT, {} chapters",
                content.chapters.len()
            );

            for chapter in &content.chapters {
                if let Some(text) = &chapter.content {
                    // 去除HTML标签后再搜索
                    let clean_text = strip_all_html_tags(text);
                    search_in_text(&clean_text, &keyword, chapter, &mut matches);
                }
            }
        }
        _ => return Err(format!("Unsupported file format: {}", ext)),
    }

    Ok(matches)
}

/// 在文本中搜索关键词并添加到匹配列表
fn search_in_text(
    clean_text: &str,
    keyword: &str,
    chapter: &crate::types::NovelChapter,
    matches: &mut Vec<SearchMatch>,
) {
    // 使用基于字符的搜索以避免在多字节 UTF-8 字符上按字节切片导致 panic
    let text_chars: Vec<char> = clean_text.chars().collect();
    let text_lower_chars: Vec<char> = clean_text.to_lowercase().chars().collect();
    let keyword_lower_chars: Vec<char> = keyword.to_lowercase().chars().collect();
    let kw_len = keyword_lower_chars.len();

    if kw_len == 0 || text_lower_chars.len() < kw_len {
        return;
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

/// 取消搜索
#[frb(sync)]
pub fn cancel_search() -> Result<(), String> {
    let cancelled = get_search_cancelled();
    if let Ok(mut flag) = cancelled.lock() {
        *flag = true;
    }
    Ok(())
}

/// 在所有书籍中搜索关键词（批量搜索，支持进度反馈和取消）
/// 分批返回搜索结果，每批处理若干本书籍
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

            // 尝试获取书籍内容并搜索
            match get_novel_content(novel.file_path.clone()) {
                Ok(content) => {
                    let mut match_count = 0;

                    // 判断文件类型
                    let path = std::path::PathBuf::from(&novel.file_path);
                    let is_epub = path
                        .extension()
                        .and_then(|e| e.to_str())
                        .map(|e| e.eq_ignore_ascii_case("epub"))
                        .unwrap_or(false);

                    if is_epub {
                        // EPUB: 按需加载每一章
                        for chapter in &content.chapters {
                            if let Ok(text) =
                                crate::parser::EpubParser::get_chapter_content(&path, chapter.index)
                            {
                                let clean_text = strip_all_html_tags(&text);
                                let text_lower_chars: Vec<char> =
                                    clean_text.to_lowercase().chars().collect();

                                if text_lower_chars.len() >= kw_len {
                                    for i in 0..=text_lower_chars.len() - kw_len {
                                        if text_lower_chars[i..i + kw_len]
                                            == keyword_lower_chars[..]
                                        {
                                            match_count += 1;
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        // TXT: 从缓存获取
                        for chapter in &content.chapters {
                            if let Some(text) = &chapter.content {
                                let clean_text = strip_all_html_tags(text);
                                let text_lower_chars: Vec<char> =
                                    clean_text.to_lowercase().chars().collect();

                                if text_lower_chars.len() >= kw_len {
                                    for i in 0..=text_lower_chars.len() - kw_len {
                                        if text_lower_chars[i..i + kw_len]
                                            == keyword_lower_chars[..]
                                        {
                                            match_count += 1;
                                        }
                                    }
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

/// 在所有书籍中搜索关键词（批量搜索，性能优化）
/// 返回包含关键词的书籍列表及其匹配数
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

    // 并发搜索所有书籍
    use rayon::prelude::*;

    let search_results: Vec<_> = novels
        .par_iter()
        .filter_map(|novel| {
            // 尝试获取书籍内容并搜索
            match get_novel_content(novel.file_path.clone()) {
                Ok(content) => {
                    let mut match_count = 0;

                    // 判断文件类型
                    let path = std::path::PathBuf::from(&novel.file_path);
                    let is_epub = path
                        .extension()
                        .and_then(|e| e.to_str())
                        .map(|e| e.eq_ignore_ascii_case("epub"))
                        .unwrap_or(false);

                    if is_epub {
                        // EPUB: 按需加载每一章
                        for chapter in &content.chapters {
                            if let Ok(text) =
                                crate::parser::EpubParser::get_chapter_content(&path, chapter.index)
                            {
                                let clean_text = strip_all_html_tags(&text);
                                let text_lower_chars: Vec<char> =
                                    clean_text.to_lowercase().chars().collect();

                                if text_lower_chars.len() >= kw_len {
                                    for i in 0..=text_lower_chars.len() - kw_len {
                                        if text_lower_chars[i..i + kw_len]
                                            == keyword_lower_chars[..]
                                        {
                                            match_count += 1;
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        // TXT: 从缓存获取
                        for chapter in &content.chapters {
                            if let Some(text) = &chapter.content {
                                let clean_text = strip_all_html_tags(text);
                                let text_lower_chars: Vec<char> =
                                    clean_text.to_lowercase().chars().collect();

                                if text_lower_chars.len() >= kw_len {
                                    for i in 0..=text_lower_chars.len() - kw_len {
                                        if text_lower_chars[i..i + kw_len]
                                            == keyword_lower_chars[..]
                                        {
                                            match_count += 1;
                                        }
                                    }
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
