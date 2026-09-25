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

// ─────────────────────────────────────────────────────────────────────────────
// 全文搜索层 DB / 文件测试（全部走隔离 HOME，见 crate::api::test_env）
// ─────────────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::super::test_env::*;
    use super::*;
    use crate::api::get_all_novels;

    /// 统计某个章节索引上的命中条数
    fn count_by_chapter(matches: &[SearchMatch], chapter_index: usize) -> usize {
        matches.iter().filter(|m| m.chapter_index == chapter_index).count()
    }

    #[test]
    fn search_in_novel_txt_collects_every_occurrence() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        let dir = case_dir("search_txt");
        // 第 0 章 2 处「剑」，第 1 章 1 处
        let p = write_novel_txt(&dir, "剑search", "他提起长剑，剑光如霜。", "剑归鞘中。");

        let matches = search_in_novel(p.to_string_lossy().into_owned(), "剑".to_string()).unwrap();
        assert_eq!(matches.len(), 3, "应找出全部 3 处命中");
        assert_eq!(count_by_chapter(&matches, 0), 2);
        assert_eq!(count_by_chapter(&matches, 1), 1);
        assert_eq!(matches[0].chapter_title, "第一章 开端");
        assert_eq!(matches[2].chapter_title, "第二章 结局");
        for m in &matches {
            assert!(m.snippet.contains('剑'), "片段必须包含命中词");
        }
        // 位置以「字符」为单位且在同一章节内递增
        let first = matches[0].position;
        let second = matches[1].position;
        assert!(second > first, "第二个命中位置应更靠后");
        // 中文多字节：位置必须落在「剑」这个字符上，而不是字节偏移
        let cleaned_first_body = "第一章 开端\n他提起长剑，剑光如霜。".to_string();
        let expect = cleaned_first_body.chars().position(|c| c == '剑').unwrap();
        assert_eq!(first, expect, "命中位置应为字符下标");
    }

    #[test]
    fn search_is_case_insensitive_and_strips_html_tags() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        let dir = case_dir("search_case");
        // 大小写混排 + 关键词被 HTML 标签打断
        let body = "Shadow of the hill.\n<p>星</p>辰大海，<b>星辰</b>之力。";
        let p = dir.join("混合大小写.txt");
        write_text(&p, body);

        let upper = search_in_novel(p.to_string_lossy().into_owned(), "SHADOW".to_string()).unwrap();
        assert_eq!(upper.len(), 1, "大小写不敏感应命中");

        let cn = search_in_novel(p.to_string_lossy().into_owned(), "星辰".to_string()).unwrap();
        assert_eq!(cn.len(), 2, "去掉 HTML 标签后被打断的「星辰」也应命中");
        assert!(cn.iter().all(|m| m.chapter_index == 0), "无章节标记的 txt 应全在第 0 章");

        // 空关键词 → 直接零命中（不报错）
        assert!(search_in_novel(p.to_string_lossy().into_owned(), String::new())
            .unwrap()
            .is_empty());
        // 未命中 → 空列表
        assert!(search_in_novel(p.to_string_lossy().into_owned(), "绝不存在词".to_string())
            .unwrap()
            .is_empty());
    }

    #[test]
    fn search_in_novel_error_branches() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        let dir = case_dir("search_err");
        // 文件不存在
        assert!(search_in_novel(
            dir.join("查无此书.txt").to_string_lossy().into_owned(),
            "任意".to_string()
        )
        .is_err());
        // 无扩展名
        let noext = dir.join("无扩展名");
        write_text(&noext, "一些文字");
        assert_eq!(
            search_in_novel(noext.to_string_lossy().into_owned(), "词".to_string()).unwrap_err(),
            "Invalid file extension"
        );
        // 不支持的扩展名（内容读取阶段就会失败）
        let pdf = dir.join("假书.pdf");
        write_text(&pdf, "%PDF-1.4");
        assert!(search_in_novel(pdf.to_string_lossy().into_owned(), "词".to_string()).is_err());
    }

    #[test]
    fn search_in_novel_epub_matches_right_chapter() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        let dir = case_dir("search_epub");
        let p = write_minimal_epub(&dir, "epub检索", "风起于青萍之末。", "青萍之末风止。");
        // epub 走「按需加载 + 去标签」分支
        let hits = search_in_novel(p.to_string_lossy().into_owned(), "青萍".to_string()).unwrap();
        assert_eq!(hits.len(), 2, "两章各命中一次");
        assert_eq!(hits[0].chapter_index, 0);
        assert_eq!(hits[1].chapter_index, 1);
        assert!(!hits[0].snippet.contains("<p>"), "片段里的 HTML 标签应已被剥掉");
        assert!(hits[0].snippet.contains("青萍"));
    }

    #[test]
    fn search_in_all_novels_ranks_by_hits_and_skips_broken_entries() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        let dir = case_dir("search_all");
        let many = write_novel_txt(&dir, "多命中", "潮水 潮水 潮水。", "退潮。");
        let one = write_novel_txt(&dir, "单命中", "一次潮水。", "别的字。");
        let broken = write_novel_txt(&dir, "文件丢失", "潮水。", "退潮。");
        let nm = add_single_novel(&many);
        let no = add_single_novel(&one);
        let nb = add_single_novel(&broken);
        std::fs::remove_file(&broken).unwrap();

        let results = search_in_all_novels("潮水".to_string()).unwrap();
        assert_eq!(results.len(), 2, "解析失败的条目应被跳过而不是中断搜索");
        assert_eq!(results[0].novel.id, nm.id, "命中数多的必须排在前");
        assert!(results[0].match_count > results[1].match_count);
        assert_eq!(results[1].novel.id, no.id);
        assert_eq!(results[0].novel.file_path, many.to_string_lossy());
        assert!(!results.iter().any(|r| r.novel.id == nb.id));

        // 空关键词 / 全库无命中 → 空结果
        assert!(search_in_all_novels(String::new()).unwrap().is_empty());
        assert!(search_in_all_novels("全库都不会有的词".to_string()).unwrap().is_empty());
        assert_eq!(get_all_novels().unwrap().len(), 3, "搜索不应改变库内容");
    }

    #[test]
    fn search_in_all_novels_batched_reports_progress() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        let dir = case_dir("search_batch");
        let a = write_novel_txt(&dir, "批次甲", "灯塔 灯塔。", "无。");
        let b = write_novel_txt(&dir, "批次乙", "一座灯塔。", "无。");
        add_single_novel(&a);
        add_single_novel(&b);

        let batches = search_in_all_novels_batched("灯塔".to_string(), 1).unwrap();
        assert_eq!(batches.len(), 2, "两本书按批大小 1 应分两批");
        assert_eq!(batches[0].total, 2);
        assert_eq!(batches[0].completed, 1);
        assert!(!batches[0].is_finished);
        assert_eq!(batches[0].results.len(), 1);
        assert_eq!(batches[0].results[0].match_count, 2);
        assert_eq!(batches[1].completed, 2);
        assert!(batches[1].is_finished);
        assert_eq!(batches[1].results[0].match_count, 1);

        // 批大小大于总数 → 单批完成
        let single = search_in_all_novels_batched("灯塔".to_string(), 50).unwrap();
        assert_eq!(single.len(), 1);
        assert!(single[0].is_finished);
        assert_eq!(single[0].completed, 2);

        // 空关键词 → 不产生任何批次
        assert!(search_in_all_novels_batched(String::new(), 1).unwrap().is_empty());

        // 未命中的关键词 → 有批次但结果为空
        let none = search_in_all_novels_batched("不可能存在的词".to_string(), 50).unwrap();
        assert_eq!(none.len(), 1);
        assert!(none[0].results.is_empty());
        assert!(none[0].is_finished);
    }

    #[test]
    fn cancel_search_sets_flag_and_next_run_resets_it() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        let dir = case_dir("search_cancel");
        let a = write_novel_txt(&dir, "可取消", "灯塔在夜里。", "无。");
        add_single_novel(&a);

        // 取消 → 置位全局标志
        cancel_search().unwrap();
        assert!(*get_search_cancelled().lock().unwrap(), "cancel_search 应置位取消标志");

        // 批量搜索入口会先复位标志，因此仍能完整跑完
        let batches = search_in_all_novels_batched("灯塔".to_string(), 1).unwrap();
        assert_eq!(batches.len(), 1);
        assert!(batches[0].is_finished);
        assert_eq!(batches[0].results.len(), 1);
        assert!(
            !*get_search_cancelled().lock().unwrap(),
            "入口复位后标志应为 false（否则后续搜索会被永久取消）"
        );

        // 置位后立刻再取消一次也应保持幂等成功
        cancel_search().unwrap();
        cancel_search().unwrap();
        assert!(*get_search_cancelled().lock().unwrap());
        // 收尾：清掉标志，避免影响其它用例
        cancel_search_reset_for_tests();
    }

    /// 用例收尾：把取消标志复位，防止污染同进程后续用例
    fn cancel_search_reset_for_tests() {
        let mut flag = get_search_cancelled().lock().unwrap();
        *flag = false;
    }
}
