use anyhow::{Context, Result};
use chardetng::EncodingDetector;
use encoding_rs::Encoding;
use std::fs::File;
use std::io::Read;
use std::path::Path;

use crate::types::{NovelChapter, NovelContent, NovelFormat, NovelMetadata};
use std::fs;
use zip::ZipArchive;

/// txt 文件解析器
pub struct TxtParser;

impl TxtParser {
    /// 解析 txt 文件，自动检测编码
    pub fn parse<P: AsRef<Path>>(path: P) -> Result<NovelContent> {
        let path = path.as_ref();
        let mut file = File::open(path).context("Failed to open txt file")?;

        // 读取文件内容
        let mut buffer = Vec::new();
        file.read_to_end(&mut buffer)
            .context("Failed to read txt file")?;

        // 先尝试 UTF-8，无效或存在替换字符时尝试回退到其他常见编码
        let content = Self::robust_decode(&buffer);

        // 从文件名提取小说ID（使用文件路径的 hash）
        let novel_id = format!("{:x}", md5::compute(path.to_string_lossy().as_bytes()));

        // txt 文件作为单个章节
        let chapter = NovelChapter {
            id: format!("{}_chapter_0", novel_id),
            title: "全文".to_string(),
            index: 0,
            content: Some(content.to_string()),
        };

        Ok(NovelContent {
            novel_id,
            chapters: vec![chapter],
        })
    }

    /// 检测文本编码
    fn detect_encoding(buffer: &[u8]) -> &'static Encoding {
        let mut detector = EncodingDetector::new();
        detector.feed(buffer, true);
        detector.guess(None, true)
    }

    /// 更鲁棒的解码：优先 UTF-8，若包含替换字符则尝试其他常见编码
    fn robust_decode(buffer: &[u8]) -> String {
        // 优先尝试直接作为 UTF-8
        if let Ok(s) = std::str::from_utf8(buffer) {
            return s.to_string();
        }

        // 使用检测结果首次解码
        let enc = Self::detect_encoding(buffer);
        let (decoded, _, had_errors) = enc.decode(buffer);
        let decoded = decoded.to_string();
        if !had_errors && !decoded.contains('\u{FFFD}') {
            return decoded;
        }

        // 如果存在替换字符或者有错误，尝试几个常见编码的回退
        let fallbacks: [&'static Encoding; 4] = [
            encoding_rs::GBK,
            encoding_rs::SHIFT_JIS,
            encoding_rs::WINDOWS_1252,
            encoding_rs::EUC_JP,
        ];

        for fb in &fallbacks {
            let (s, _, _) = fb.decode(buffer);
            let s = s.to_string();
            if !s.contains('\u{FFFD}') {
                log::info!("TxtParser: fallback decode used: {}", fb.name());
                return s;
            }
        }

        // 最后仍然返回替换后的字符串（from_utf8_lossy 行为）
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
            modified_at: chrono::DateTime::from(
                metadata.modified().unwrap_or(std::time::SystemTime::now()),
            ),
            added_at: chrono::Utc::now(),
            progress: 0.0,
            last_read_at: None,
            cover_path: None,
        })
    }
}

/// epub 文件解析器
pub struct EpubParser;

impl EpubParser {
    /// 解析 epub 文件
    pub fn parse<P: AsRef<Path>>(path: P) -> Result<NovelContent> {
        let path = path.as_ref();
        let mut doc = epub::doc::EpubDoc::new(path)
            .map_err(|e| anyhow::anyhow!("Failed to open epub: {:?}", e))?;

        let novel_id = format!("{:x}", md5::compute(path.to_string_lossy().as_bytes()));
        let mut chapters = Vec::new();

        // 获取当前资源数量
        let num_pages = doc.get_num_pages();

        // 遍历所有页面
        for index in 0..num_pages {
            doc.set_current_page(index);
            if let Some((content_bytes, _mime)) = doc.get_current() {
                // 尝试转换为字符串（若包含替换字符则使用回退解码）
                let mut content = String::from_utf8_lossy(&content_bytes).to_string();
                if content.contains('\u{FFFD}') {
                    // 如果包含替换字符，尝试使用几种常见编码回退
                    let fallbacks: [&'static encoding_rs::Encoding; 4] = [
                        encoding_rs::GBK,
                        encoding_rs::SHIFT_JIS,
                        encoding_rs::WINDOWS_1252,
                        encoding_rs::EUC_JP,
                    ];
                    for fb in &fallbacks {
                        let (s, _, _) = fb.decode(&content_bytes);
                        let s = s.to_string();
                        if !s.contains('\u{FFFD}') {
                            content = s;
                            log::info!("EpubParser: fallback decode used: {}", fb.name());
                            break;
                        }
                    }
                }

                // 简单的 HTML 标签移除
                let text = Self::strip_html_tags(&content);

                if !text.trim().is_empty() {
                    let chapter = NovelChapter {
                        id: format!("{}_{}", novel_id, index),
                        title: doc
                            .get_current_id()
                            .map(|s| s.to_string())
                            .unwrap_or_else(|| format!("Chapter {}", index + 1)),
                        index,
                        content: Some(text),
                    };
                    chapters.push(chapter);
                }
            }
        }

        Ok(NovelContent { novel_id, chapters })
    }

    /// 提取 epub 文件的元数据
    pub fn extract_metadata<P: AsRef<Path>>(path: P) -> Result<NovelMetadata> {
        let path = path.as_ref();
        let mut doc = epub::doc::EpubDoc::new(path)
            .map_err(|e| anyhow::anyhow!("Failed to open epub: {:?}", e))?;

        let metadata_fs = std::fs::metadata(path).context("Failed to read file metadata")?;

        let title = doc
            .mdata("title")
            .map(|s| s.value.clone())
            .unwrap_or_else(|| {
                path.file_stem()
                    .and_then(|s| s.to_str())
                    .unwrap_or("Unknown")
                    .to_string()
            });

        let author = doc.mdata("creator").map(|s| s.value.clone());

        let novel_id = format!("{:x}", md5::compute(path.to_string_lossy().as_bytes()));

        // 尝试提取封面——优先通过 common cover 文件名，从 epub(zip) 中提取到临时目录
        let mut cover_path: Option<String> = None;
        if let Ok(file) = File::open(path) {
            if let Ok(mut archive) = ZipArchive::new(file) {
                // 查找可能的封面文件名
                let mut found_index: Option<usize> = None;
                for i in 0..archive.len() {
                    if let Ok(file) = archive.by_index(i) {
                        let name = file.name().to_lowercase();
                        if name.ends_with(".jpg")
                            || name.ends_with(".jpeg")
                            || name.ends_with(".png")
                            || name.ends_with(".gif")
                        {
                            if name.contains("cover")
                                || name.contains("封面")
                                || name.contains("image")
                                || name.contains("images")
                            {
                                found_index = Some(i);
                                break;
                            }
                        }
                    }
                }

                // fallback: first image if no explicit cover
                if found_index.is_none() {
                    for i in 0..archive.len() {
                        if let Ok(file) = archive.by_index(i) {
                            let name = file.name().to_lowercase();
                            if name.ends_with(".jpg")
                                || name.ends_with(".jpeg")
                                || name.ends_with(".png")
                                || name.ends_with(".gif")
                            {
                                found_index = Some(i);
                                break;
                            }
                        }
                    }
                }

                if let Some(idx) = found_index {
                    if let Ok(mut f) = archive.by_index(idx) {
                        // prepare output dir
                        let tmp = std::env::temp_dir().join("slimeworks").join("covers");
                        let _ = fs::create_dir_all(&tmp);
                        let ext = f.name().rsplit('.').next().unwrap_or("jpg").to_string();
                        let out_path = tmp.join(format!("{}.{}", novel_id, ext));

                        if let Ok(mut out_file) = File::create(&out_path) {
                            use std::io::copy;
                            let _ = copy(&mut f, &mut out_file);
                            cover_path = Some(out_path.to_string_lossy().to_string());
                        }
                    }
                }
            }
        }

        Ok(NovelMetadata {
            id: novel_id,
            title,
            author,
            file_path: path.to_string_lossy().to_string(),
            format: NovelFormat::Epub,
            file_size: metadata_fs.len(),
            modified_at: chrono::DateTime::from(
                metadata_fs
                    .modified()
                    .unwrap_or(std::time::SystemTime::now()),
            ),
            added_at: chrono::Utc::now(),
            progress: 0.0,
            last_read_at: None,
            cover_path,
        })
    }

    /// 简单的 HTML 标签移除
    fn strip_html_tags(html: &str) -> String {
        let mut result = String::new();
        let mut in_tag = false;

        for ch in html.chars() {
            match ch {
                '<' => in_tag = true,
                '>' => in_tag = false,
                _ if !in_tag => result.push(ch),
                _ => {}
            }
        }

        result
    }
}

/// 通用解析器
pub struct NovelParser;

impl NovelParser {
    /// 根据文件格式自动选择解析器
    pub fn parse<P: AsRef<Path>>(path: P) -> Result<NovelContent> {
        let path = path.as_ref();
        let ext = path
            .extension()
            .and_then(|s| s.to_str())
            .ok_or_else(|| anyhow::anyhow!("No file extension"))?;

        match NovelFormat::from_extension(ext) {
            Some(NovelFormat::Txt) => TxtParser::parse(path),
            Some(NovelFormat::Epub) => EpubParser::parse(path),
            None => Err(anyhow::anyhow!("Unsupported file format: {}", ext)),
        }
    }

    /// 提取元数据
    pub fn extract_metadata<P: AsRef<Path>>(path: P) -> Result<NovelMetadata> {
        let path = path.as_ref();
        let ext = path
            .extension()
            .and_then(|s| s.to_str())
            .ok_or_else(|| anyhow::anyhow!("No file extension"))?;

        match NovelFormat::from_extension(ext) {
            Some(NovelFormat::Txt) => TxtParser::extract_metadata(path),
            Some(NovelFormat::Epub) => EpubParser::extract_metadata(path),
            None => Err(anyhow::anyhow!("Unsupported file format: {}", ext)),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_html_strip() {
        let html = "<p>Hello <b>World</b>!</p>";
        let text = EpubParser::strip_html_tags(html);
        assert_eq!(text, "Hello World!");
    }
}
