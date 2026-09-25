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
        println!("[TxtParser] Starting to parse: {:?}", path);

        let open_start = Instant::now();
        let mut file = File::open(path).context("Failed to open txt file")?;
        println!("[TxtParser] File opened in {:?}", open_start.elapsed());

        // 读取文件内容
        println!("[TxtParser] Reading file into memory...");
        let read_start = Instant::now();
        let mut buffer = Vec::new();
        file.read_to_end(&mut buffer)
            .context("Failed to read txt file")?;
        println!(
            "[TxtParser] Read {} bytes in {:?}",
            buffer.len(),
            read_start.elapsed()
        );

        // 先尝试 UTF-8，无效或存在替换字符时尝试回退到其他常见编码
        println!("[TxtParser] Decoding content...");
        let decode_start = Instant::now();
        let content = Self::robust_decode(&buffer);
        println!(
            "[TxtParser] Decoded {} chars in {:?}",
            content.len(),
            decode_start.elapsed()
        );

        // 从文件名提取书籍ID（使用文件路径的 hash）
        let novel_id = format!("{:x}", md5::compute(path.to_string_lossy().as_bytes()));

        // 尝试自动识别章节
        println!("[TxtParser] Detecting chapters...");
        let chapter_detect_start = Instant::now();
        let chapters = Self::detect_chapters(&novel_id, &content);
        println!(
            "[TxtParser] Detected {} chapters in {:?}",
            chapters.len(),
            chapter_detect_start.elapsed()
        );

        let total_time = start_time.elapsed();
        println!("[TxtParser] Total parse time: {:?}", total_time);

        Ok(NovelContent { novel_id, chapters })
    }

    /// 自动检测并拆分章节
    fn detect_chapters(novel_id: &str, content: &str) -> Vec<NovelChapter> {
        use regex::Regex;

        // 常见章节标题模式 - 允许行首空白字符（包括全角空格）
        let patterns = vec![
            r"(?m)^\s*第[零一二三四五六七八九十百千万0-9]+章[^\n]{0,40}",
            r"(?m)^\s*第[零一二三四五六七八九十百千万0-9]+节[^\n]{0,40}",
            r"(?m)^\s*第[零一二三四五六七八九十百千万0-9]+回[^\n]{0,40}",
            r"(?m)^\s*第[零一二三四五六七八九十百千万0-9]+卷[^\n]{0,40}",
            r"(?m)^\s*Chapter [0-9]+[^\n]{0,40}",
            r"(?m)^\s*[0-9]+\.[^\n]{1,40}",
        ];

        let mut chapter_positions: Vec<(usize, String)> = Vec::new();

        for pattern in &patterns {
            if let Ok(re) = Regex::new(pattern) {
                let matches: Vec<_> = re.find_iter(content).collect();
                if !matches.is_empty() {
                    println!(
                        "[TxtParser] Pattern matched {} times: {}",
                        matches.len(),
                        pattern
                    );
                }
                for mat in matches {
                    let title = mat.as_str().trim().to_string();
                    chapter_positions.push((mat.start(), title));
                }
            }
        }

        // 如果没找到章节，返回整篇文章
        if chapter_positions.is_empty() {
            println!(
                "[TxtParser] No chapters detected, using full text (content length: {} chars)",
                content.len()
            );
            return vec![NovelChapter {
                id: format!("{}_chapter_0", novel_id),
                title: "全文".to_string(),
                index: 0,
                content: Some(content.to_string()),
            }];
        }

        // 按位置排序
        chapter_positions.sort_by_key(|k| k.0);

        // 去重：同一位置只保留最长的标题（避免"第X章"和"第X卷"重复匹配）
        let mut deduplicated: Vec<(usize, String)> = Vec::new();
        for (pos, title) in &chapter_positions {
            if let Some(last) = deduplicated.last_mut() {
                // 如果位置相同或非常接近（<10字符），保留更长的标题
                if pos.saturating_sub(last.0) < 10 {
                    if title.len() > last.1.len() {
                        last.1 = title.clone();
                    }
                    continue;
                }
            }
            deduplicated.push((*pos, title.clone()));
        }

        println!(
            "[TxtParser] After deduplication: {} chapters (from {} raw matches)",
            deduplicated.len(),
            chapter_positions.len()
        );

        // 限制章节数量，避免过度拆分（提高到5000，支持超长小说）
        if deduplicated.len() > 5000 {
            println!(
                "[TxtParser] Too many chapters detected ({}), using full text",
                deduplicated.len()
            );
            return vec![NovelChapter {
                id: format!("{}_chapter_0", novel_id),
                title: "全文".to_string(),
                index: 0,
                content: Some(content.to_string()),
            }];
        }

        let chapter_positions = deduplicated;

        let mut chapters = Vec::new();

        println!(
            "[TxtParser] Creating {} chapter objects...",
            chapter_positions.len()
        );

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
        println!("[TxtParser] Trying UTF-8...");
        if let Ok(s) = std::str::from_utf8(buffer) {
            println!(
                "[TxtParser] UTF-8 decode succeeded in {:?}",
                start.elapsed()
            );
            return s.to_string();
        }
        println!("[TxtParser] UTF-8 failed, trying detector...");

        // UTF-8 失败，尝试使用检测器
        let detect_start = Instant::now();
        let enc = Self::detect_encoding(buffer);
        println!(
            "[TxtParser] Detected encoding: {} in {:?}",
            enc.name(),
            detect_start.elapsed()
        );

        let (decoded, _, had_errors) = enc.decode(buffer);

        // 如果检测的编码解码成功且没有替换字符，直接返回
        if !had_errors && !decoded.contains('\u{FFFD}') {
            println!(
                "[TxtParser] Decoded with {} in {:?}",
                enc.name(),
                start.elapsed()
            );
            return decoded.to_string();
        }
        println!("[TxtParser] Detected encoding had errors, trying fallbacks...");

        // 仅在检测失败时才尝试常见编码（大多数情况不会到达这里）
        let fallbacks: [&'static Encoding; 2] = [
            encoding_rs::GBK,       // 中文最常见
            encoding_rs::SHIFT_JIS, // 日文
        ];

        for fb in &fallbacks {
            let (s, _, _) = fb.decode(buffer);
            if !s.contains('\u{FFFD}') {
                println!(
                    "[TxtParser] Fallback decode succeeded with {} in {:?}",
                    fb.name(),
                    start.elapsed()
                );
                return s.to_string();
            }
        }

        // 最后使用lossy转换（总是成功）
        println!("[TxtParser] All encodings failed, using lossy conversion");
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

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    /// 创建一个唯一的临时目录（基于 uuid，避免并行测试互相覆盖）
    fn make_temp_dir(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "novel_reader_txt_{}_{}",
            tag,
            uuid::Uuid::new_v4()
        ));
        std::fs::create_dir_all(&dir).expect("创建临时目录失败");
        dir
    }

    /// 多章节 UTF-8 文本样例（三章，含正文与空行分隔）
    fn sample_multi_chapter() -> String {
        "第一章 起风\n内容A第一段。\n内容A第二段。\n\n第二章 过客\n内容B第一段。\n\n第三章 终章\n内容C第一段。"
            .to_string()
    }

    #[test]
    fn test_parse_utf8_multi_chapter() {
        // UTF-8 多章节文件：应切出 3 章，标题与正文归属正确
        let dir = make_temp_dir("utf8");
        let path = dir.join("多章节小说.txt");
        let text = sample_multi_chapter();
        std::fs::write(&path, text.as_bytes()).unwrap();

        let content = TxtParser::parse(&path).expect("UTF-8 解析应成功");
        assert_eq!(content.chapters.len(), 3, "应识别出 3 个章节");
        assert_eq!(content.chapters[0].title, "第一章 起风");
        assert_eq!(content.chapters[1].title, "第二章 过客");
        assert_eq!(content.chapters[2].title, "第三章 终章");
        assert_eq!(content.chapters[0].index, 0);
        assert_eq!(content.chapters[2].index, 2);

        // 第一章内容应包含自己的正文，且不越界包含第二章正文
        let ch0 = content.chapters[0].content.as_ref().unwrap();
        assert!(ch0.contains("内容A第一段"), "第一章应含首段正文");
        assert!(!ch0.contains("内容B第一段"), "第一章不应吞并第二章正文");
        // 末章内容应包含结尾正文
        let ch2 = content.chapters[2].content.as_ref().unwrap();
        assert!(ch2.contains("内容C第一段"));
        // novel_id 为路径 md5 的十六进制（32 位）
        assert_eq!(content.novel_id.len(), 32, "novel_id 应为 32 位十六进制");

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn test_parse_gbk_encoded() {
        // GBK 编码文件：UTF-8 解码失败后应回退到 GBK，标题/正文均正确
        let dir = make_temp_dir("gbk");
        let path = dir.join("gbk小说.txt");
        // 用足够长的中文内容提高编码检测置信度
        let text = "第一章 起风\n那是个动荡的年代，风从海面吹来，带着咸湿的气息。内容A第二段。\n\n第二章 过客\n他在小镇停留了三日，结识了许多有趣的人，随后继续北上。内容B第二段。\n\n第三章 归途\n故事的最后，所有人都回到了出发的地方。";
        let (gbk_bytes, _, _) = encoding_rs::GBK.encode(text);
        std::fs::write(&path, &gbk_bytes).unwrap();
        // 确认写入的不是合法 UTF-8（否则测不到回退路径）
        assert!(std::str::from_utf8(&gbk_bytes).is_err(), "样例应为非 UTF-8 字节");

        let content = TxtParser::parse(&path).expect("GBK 解析应成功");
        assert_eq!(content.chapters.len(), 3, "GBK 文件应切出 3 章");
        assert_eq!(content.chapters[0].title, "第一章 起风");
        assert_eq!(content.chapters[2].title, "第三章 归途");
        let ch0 = content.chapters[0].content.as_ref().unwrap();
        assert!(ch0.contains("风从海面吹来"), "GBK 正文应正确解码");

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn test_parse_gb18030_encoded() {
        // GB18030 编码（常见中文超集）：应能通过检测或 GBK 回退正确解码常用汉字
        let dir = make_temp_dir("gb18030");
        let path = dir.join("gb18030小说.txt");
        let text = "第一章 序幕\n序幕拉开，万众瞩目，这是属于他们的时代。第一章第二段正文。\n\n第二章 风云\n风云际会，英雄辈出，谁主沉浮。第二章第二段正文。";
        let (bytes, _, _) = encoding_rs::GB18030.encode(text);
        std::fs::write(&path, &bytes).unwrap();

        let content = TxtParser::parse(&path).expect("GB18030 解析应成功");
        assert_eq!(content.chapters.len(), 2, "应切出 2 章");
        assert_eq!(content.chapters[0].title, "第一章 序幕");
        assert_eq!(content.chapters[1].title, "第二章 风云");

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn test_parse_empty_file_single_fulltext_chapter() {
        // 空文件：无章节标题可匹配，按现有行为归为 1 个「全文」章节，内容为空串
        let dir = make_temp_dir("empty");
        let path = dir.join("empty.txt");
        std::fs::write(&path, b"").unwrap();

        let content = TxtParser::parse(&path).expect("空文件解析不应报错");
        assert_eq!(content.chapters.len(), 1, "空文件应返回单个全文章节");
        assert_eq!(content.chapters[0].title, "全文");
        assert_eq!(content.chapters[0].content.as_deref(), Some(""));

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn test_parse_no_chapter_title() {
        // 无章节标题的文本：全部归入单个「全文」章节
        let dir = make_temp_dir("noch");
        let path = dir.join("无章节.txt");
        let text = "这是一段没有任何章节标记的普通文字。\n它只有两行，应当整体作为一个全文章节返回。";
        std::fs::write(&path, text.as_bytes()).unwrap();

        let content = TxtParser::parse(&path).expect("解析应成功");
        assert_eq!(content.chapters.len(), 1);
        assert_eq!(content.chapters[0].title, "全文");
        assert_eq!(
            content.chapters[0].content.as_deref(),
            Some(text),
            "全文章节应保留完整原文"
        );

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn test_detect_chapters_english_and_numeric_patterns() {
        // 英文 Chapter 与数字编号标题也应被识别
        let id = "test";
        let text = "Chapter 1 The Beginning\nfirst body.\n\nChapter 2 The End\nsecond body.";
        let chapters = TxtParser::detect_chapters(id, text);
        assert_eq!(chapters.len(), 2, "Chapter N 模式应切出 2 章");
        assert!(chapters[0].content.as_ref().unwrap().contains("first body"));
        assert!(!chapters[0].content.as_ref().unwrap().contains("second body"));

        let numbered = "1. 引言\n正文一。\n2. 方法\n正文二。";
        let chapters2 = TxtParser::detect_chapters(id, numbered);
        assert_eq!(chapters2.len(), 2, "数字编号模式应切出 2 章");
    }

    #[test]
    fn test_detect_chapters_dedup_same_position() {
        // 同一行同时命中「第X卷」与「第X章」时，应去重并保留更长标题
        let text = "第一卷 第一章 合并标题\n正文。\n第二卷 第二章 另一章\n正文二。";
        let chapters = TxtParser::detect_chapters("id", text);
        assert_eq!(chapters.len(), 2, "同行重复匹配应去重为 2 章");
        assert!(chapters[0].title.starts_with('第'));
    }

    #[test]
    fn test_robust_decode_paths() {
        // 1) 合法 UTF-8 直通
        let utf8 = "中文内容 hello".as_bytes();
        assert_eq!(TxtParser::robust_decode(utf8), "中文内容 hello");

        // 2) GBK 字节回退解码（使用足够长的中文提高检测置信度）
        let (gbk, _, _) =
            encoding_rs::GBK.encode("测试中文解码，这是一段用于验证回退路径的较长中文文本，包含标点与常用汉字。");
        let decoded = TxtParser::robust_decode(&gbk);
        assert!(
            decoded.starts_with("测试中文解码"),
            "GBK 短文本应回退解码成功，实际: {}",
            decoded
        );

        // 3) 全零字节：任何编码都无法给出「非空可打印」结果，
        //    但解码必须无损返回（空串），不应 panic
        assert_eq!(TxtParser::robust_decode(b""), "");

        // 4) 明显非法字节序列：应走 lossy 兜底且包含替换字符，不 panic
        let garbage: Vec<u8> = vec![0xFF, 0xFE, 0x80, 0x81, 0xFF, 0x00, 0xFF];
        let lossy = TxtParser::robust_decode(&garbage);
        // 至少不应崩溃，且长度与字符层面可预期（lossy 至少产出等长字节对应的字符）
        assert!(!lossy.is_empty(), "非法字节解码应返回非空 lossy 字符串");
    }

    #[test]
    fn test_detect_encoding_returns_known() {
        // 编码检测函数对纯 GBK 中文应返回非 UTF-8 编码
        let (gbk, _, _) = encoding_rs::GBK.encode("这是一段足够长的中文文本用于编码检测测试，应当能识别出非UTF8编码。");
        let enc = TxtParser::detect_encoding(&gbk);
        assert_ne!(enc.name(), "UTF-8", "GBK 字节不应被判为 UTF-8");
    }

    #[test]
    fn test_extract_metadata_txt() {
        // 元数据：标题取自文件名（去扩展名），格式为 Txt，文件大小准确
        let dir = make_temp_dir("meta");
        let path = dir.join("测试小说.txt");
        let text = "一些内容".repeat(10);
        std::fs::write(&path, text.as_bytes()).unwrap();

        let meta = TxtParser::extract_metadata(&path).expect("元数据提取应成功");
        assert_eq!(meta.title, "测试小说", "标题应为文件名去扩展名");
        assert_eq!(meta.format, crate::types::NovelFormat::Txt);
        assert_eq!(meta.file_size, text.len() as u64);
        assert!(meta.author.is_none(), "txt 无作者元数据");
        assert_eq!(meta.id.len(), 32, "id 应为路径 md5 十六进制");
        assert_eq!(meta.file_path, path.to_string_lossy().to_string());

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn test_parse_missing_file_returns_error() {
        // 文件不存在时 parse 应返回错误而非 panic
        let dir = make_temp_dir("missing");
        let path = dir.join("不存在.txt");
        let err = TxtParser::parse(&path);
        assert!(err.is_err(), "不存在的文件应报错");
        std::fs::remove_dir_all(&dir).ok();
    }
}
