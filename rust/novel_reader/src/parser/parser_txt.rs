use anyhow::{Context, Result};
use chardetng::EncodingDetector;
use encoding_rs::Encoding;
use std::fs::File;
use std::io::Read;
use std::path::Path;

use crate::types::{NovelChapter, NovelContent, NovelFormat, NovelMetadata};

/// txt 文件解析器
pub struct TxtParser;

impl TxtParser {
    /// 解析 txt 文件，自动检测编码
    pub fn parse<P: AsRef<Path>>(path: P) -> Result<NovelContent> {
        use std::time::Instant;
        let start_time = Instant::now();

        let path = path.as_ref();
        log::info!("[TxtParser] Starting to parse: {:?}", path);

        let open_start = Instant::now();
        let mut file = File::open(path).context("Failed to open txt file")?;
        log::debug!("[TxtParser] File opened in {:?}", open_start.elapsed());

        // 读取文件内容
        log::debug!("[TxtParser] Reading file into memory...");
        let read_start = Instant::now();
        let mut buffer = Vec::new();
        file.read_to_end(&mut buffer)
            .context("Failed to read txt file")?;
        log::info!(
            "[TxtParser] Read {} bytes in {:?}",
            buffer.len(),
            read_start.elapsed()
        );

        // 先尝试 UTF-8，无效或存在替换字符时尝试回退到其他常见编码
        log::debug!("[TxtParser] Decoding content...");
        let decode_start = Instant::now();
        let content = Self::robust_decode(&buffer);
        log::info!(
            "[TxtParser] Decoded {} chars in {:?}",
            content.len(),
            decode_start.elapsed()
        );

        // 从文件名提取书籍ID（使用文件路径的 hash）
        let novel_id = format!("{:x}", md5::compute(path.to_string_lossy().as_bytes()));

        // 尝试自动识别章节
        log::debug!("[TxtParser] Detecting chapters...");
        let chapter_detect_start = Instant::now();
        let chapters = Self::detect_chapters(&novel_id, &content);
        log::info!(
            "[TxtParser] Detected {} chapters in {:?}",
            chapters.len(),
            chapter_detect_start.elapsed()
        );

        let total_time = start_time.elapsed();
        log::info!("[TxtParser] Total parse time: {:?}", total_time);

        Ok(NovelContent { novel_id, chapters })
    }

    /// 自动检测并拆分章节
    fn detect_chapters(novel_id: &str, content: &str) -> Vec<NovelChapter> {
        use regex::Regex;

        // 常见章节标题模式 - 修复：去掉行末约束$，允许章节标题后有内容
        let patterns = vec![
            r"(?m)^第[零一二三四五六七八九十百千万0-9]+章[^\n]{0,30}",
            r"(?m)^第[零一二三四五六七八九十百千万0-9]+节[^\n]{0,30}",
            r"(?m)^第[零一二三四五六七八九十百千万0-9]+回[^\n]{0,30}",
            r"(?m)^第[零一二三四五六七八九十百千万0-9]+卷[^\n]{0,30}",
            r"(?m)^Chapter [0-9]+[^\n]{0,30}",
            r"(?m)^[0-9]+\.[^\n]{1,30}",
        ];

        let mut chapter_positions: Vec<(usize, String)> = Vec::new();

        for pattern in &patterns {
            if let Ok(re) = Regex::new(pattern) {
                for mat in re.find_iter(content) {
                    let title = mat.as_str().trim().to_string();
                    chapter_positions.push((mat.start(), title));
                }
            }
        }

        // 如果没找到章节，返回整篇文章
        if chapter_positions.is_empty() {
            log::debug!("[TxtParser] No chapters detected, using full text");
            return vec![NovelChapter {
                id: format!("{}_chapter_0", novel_id),
                title: "全文".to_string(),
                index: 0,
                content: Some(content.to_string()),
            }];
        }

        // 按位置排序并去重
        chapter_positions.sort_by_key(|k| k.0);
        chapter_positions.dedup_by_key(|k| k.0);

        // 限制章节数量，避免过度拆分
        if chapter_positions.len() > 1000 {
            log::warn!(
                "[TxtParser] Too many chapters detected ({}), using full text",
                chapter_positions.len()
            );
            return vec![NovelChapter {
                id: format!("{}_chapter_0", novel_id),
                title: "全文".to_string(),
                index: 0,
                content: Some(content.to_string()),
            }];
        }

        let mut chapters = Vec::new();

        for (i, (start_pos, title)) in chapter_positions.iter().enumerate() {
            let end_pos = if i + 1 < chapter_positions.len() {
                chapter_positions[i + 1].0
            } else {
                content.len()
            };

            // 提取章节内容（使用字节索引直接切片字符串）
            let chapter_content = &content[*start_pos..end_pos];

            chapters.push(NovelChapter {
                id: format!("{}_chapter_{}", novel_id, i),
                title: title.to_string(),
                index: i,
                content: Some(chapter_content.to_string()),
            });
        }

        chapters
    }

    /// 检测文本编码
    fn detect_encoding(buffer: &[u8]) -> &'static Encoding {
        let mut detector = EncodingDetector::new();
        detector.feed(buffer, true);
        detector.guess(None, true)
    }

    /// 更鲁棒的解码：优先 UTF-8，仅在失败时尝试其他编码
    fn robust_decode(buffer: &[u8]) -> String {
        use std::time::Instant;
        let start = Instant::now();

        // 优先尝试直接作为 UTF-8（最快）
        log::debug!("[TxtParser] Trying UTF-8...");
        if let Ok(s) = std::str::from_utf8(buffer) {
            log::info!(
                "[TxtParser] UTF-8 decode succeeded in {:?}",
                start.elapsed()
            );
            return s.to_string();
        }
        log::debug!("[TxtParser] UTF-8 failed, trying detector...");

        // UTF-8 失败，尝试使用检测器
        let detect_start = Instant::now();
        let enc = Self::detect_encoding(buffer);
        log::debug!(
            "[TxtParser] Detected encoding: {} in {:?}",
            enc.name(),
            detect_start.elapsed()
        );

        let (decoded, _, had_errors) = enc.decode(buffer);

        // 如果检测的编码解码成功且没有替换字符，直接返回
        if !had_errors && !decoded.contains('\u{FFFD}') {
            log::info!(
                "[TxtParser] Decoded with {} in {:?}",
                enc.name(),
                start.elapsed()
            );
            return decoded.to_string();
        }
        log::debug!("[TxtParser] Detected encoding had errors, trying fallbacks...");

        // 仅在检测失败时才尝试常见编码（大多数情况不会到达这里）
        let fallbacks: [&'static Encoding; 2] = [
            encoding_rs::GBK,       // 中文最常见
            encoding_rs::SHIFT_JIS, // 日文
        ];

        for fb in &fallbacks {
            let (s, _, _) = fb.decode(buffer);
            if !s.contains('\u{FFFD}') {
                log::info!(
                    "[TxtParser] Fallback decode succeeded with {} in {:?}",
                    fb.name(),
                    start.elapsed()
                );
                return s.to_string();
            }
        }

        // 最后使用lossy转换（总是成功）
        log::warn!("[TxtParser] All encodings failed, using lossy conversion");
        String::from_utf8_lossy(buffer).to_string()
    }

    /// 提取 txt 文件的元数据（标题从文件名获取）
    pub fn extract_metadata<P: AsRef<Path>>(path: P) -> Result<NovelMetadata> {
        let path = path.as_ref();
        let metadata = std::fs::metadata(path).context("Failed to read file metadata")?;

        let title = path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("Unknown")
            .to_string();

        let novel_id = format!("{:x}", md5::compute(path.to_string_lossy().as_bytes()));

        Ok(NovelMetadata {
            id: novel_id,
            title,
            author: None,
            file_path: path.to_string_lossy().to_string(),
            format: NovelFormat::Txt,
            file_size: metadata.len(),
            is_favorite: false,
            tags: Vec::new(),
            modified_at: chrono::DateTime::from(
                metadata.modified().unwrap_or(std::time::SystemTime::now()),
            ),
            added_at: chrono::Utc::now(),
            progress: 0.0,
            current_chapter_id: None,
            last_read_at: None,
            cover_path: None,
            folder_id: None,
            custom_order: None,
            notes: None,
        })
    }
}
