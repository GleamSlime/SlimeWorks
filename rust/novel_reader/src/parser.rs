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

        // 从文件名提取小说ID（使用文件路径的 hash）
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

        // 常见章节标题模式
        let patterns = vec![
            r"(?m)^第[零一二三四五六七八九十百千万0-9]+章[^\n]{0,30}$",
            r"(?m)^第[零一二三四五六七八九十百千万0-9]+节[^\n]{0,30}$",
            r"(?m)^第[零一二三四五六七八九十百千万0-9]+回[^\n]{0,30}$",
            r"(?m)^第[零一二三四五六七八九十百千万0-9]+卷[^\n]{0,30}$",
            r"(?m)^Chapter [0-9]+[^\n]{0,30}$",
            r"(?m)^[0-9]+\.[^\n]{1,30}$",
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
            modified_at: chrono::DateTime::from(
                metadata.modified().unwrap_or(std::time::SystemTime::now()),
            ),
            added_at: chrono::Utc::now(),
            progress: 0.0,
            last_read_at: None,
            cover_path: None,
            folder_id: None,
            custom_order: None,
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

        // 创建临时目录存储提取的图片
        let image_dir = std::env::temp_dir()
            .join("slimeworks")
            .join("epub_images")
            .join(&novel_id);
        let _ = fs::create_dir_all(&image_dir);
        log::info!("EpubParser: Image directory: {:?}", image_dir);

        // 提取所有图片资源
        match Self::extract_images(path, &image_dir) {
            Ok(_) => log::info!("EpubParser: Images extracted successfully"),
            Err(e) => log::warn!("EpubParser: Failed to extract images: {:?}", e),
        };

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

                // 转换图片路径为本地文件路径
                let content = Self::convert_image_paths(&content, &image_dir);

                // 处理HTML标签（保留img标签）
                let text = Self::strip_html_tags(&content);

                if !text.trim().is_empty() {
                    // 尝试从内容中提取真实标题（如"第x章 xxx"、"简介"、"彩页"等）
                    let extracted_title = Self::extract_title_from_content(&text);

                    let chapter = NovelChapter {
                        id: format!("{}_{}", novel_id, index),
                        title: extracted_title.unwrap_or_else(|| {
                            // 如果没有提取到标题，使用文件ID或默认名称
                            doc.get_current_id()
                                .map(|s| s.to_string())
                                .unwrap_or_else(|| format!("Chapter {}", index + 1))
                        }),
                        index,
                        content: Some(text),
                    };
                    chapters.push(chapter);
                }
            }
        }

        Ok(NovelContent { novel_id, chapters })
    }

    /// 从EPUB中提取所有图片
    fn extract_images<P: AsRef<Path>>(epub_path: P, output_dir: &Path) -> Result<()> {
        let file = File::open(epub_path)?;
        let mut archive = ZipArchive::new(file)?;

        for i in 0..archive.len() {
            let mut file = archive.by_index(i)?;
            let name = file.name();

            // 检查是否是图片文件
            if name.ends_with(".jpg")
                || name.ends_with(".jpeg")
                || name.ends_with(".png")
                || name.ends_with(".gif")
                || name.ends_with(".svg")
                || name.ends_with(".webp")
            {
                // 保持原有目录结构
                let file_path = output_dir.join(name);

                // 创建父目录
                if let Some(parent) = file_path.parent() {
                    fs::create_dir_all(parent)?;
                }

                // 写入文件
                let mut out_file = File::create(&file_path)?;
                std::io::copy(&mut file, &mut out_file)?;
            }
        }

        Ok(())
    }

    /// 转换HTML中的图片路径为本地文件路径
    fn convert_image_paths(html: &str, image_dir: &Path) -> String {
        use regex::Regex;

        // 匹配 <img> 标签中的 src 属性
        let img_regex = Regex::new(r#"<img[^>]*src\s*=\s*["']([^"']+)["'][^>]*>"#).unwrap();

        let result = img_regex.replace_all(html, |caps: &regex::Captures| {
            let src = &caps[1];

            // 清理路径（移除开头的 ../ 或 ./）
            let cleaned_src = src.trim_start_matches("../").trim_start_matches("./");

            // 构建本地文件路径
            let local_path = image_dir.join(cleaned_src);

            // 将路径转换为 file:// URL（Windows路径需要特殊处理）
            #[cfg(target_os = "windows")]
            let file_url = format!(
                "file:///{}",
                local_path.to_string_lossy().replace('\\', "/")
            );

            #[cfg(not(target_os = "windows"))]
            let file_url = format!("file://{}", local_path.to_string_lossy());

            log::debug!("EpubParser: Image path converted: {} -> {}", src, file_url);

            // 替换原有的 src
            caps[0].replace(src, &file_url)
        });

        result.to_string()
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
                            match copy(&mut f, &mut out_file) {
                                Ok(bytes_copied) => {
                                    if bytes_copied > 0 {
                                        cover_path = Some(out_path.to_string_lossy().to_string());
                                        log::info!(
                                            "EpubParser: Cover extracted successfully, {} bytes",
                                            bytes_copied
                                        );
                                    } else {
                                        log::warn!("EpubParser: Cover file is empty, skipping");
                                        // 删除空文件
                                        let _ = std::fs::remove_file(&out_path);
                                    }
                                }
                                Err(e) => {
                                    log::warn!("EpubParser: Failed to copy cover: {}", e);
                                    // 删除可能创建的空文件
                                    let _ = std::fs::remove_file(&out_path);
                                }
                            }
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
            folder_id: None,
            custom_order: None,
        })
    }

    /// 简单的 HTML 标签移除（保留 img 标签用于图片显示）
    fn strip_html_tags(html: &str) -> String {
        use regex::Regex;

        // 先保存 img 标签
        let img_regex = Regex::new(r"<img[^>]*>").unwrap();
        let mut img_tags = Vec::new();
        let mut html_with_placeholders = html.to_string();

        for (i, cap) in img_regex.captures_iter(html).enumerate() {
            let img_tag = cap.get(0).unwrap().as_str();
            img_tags.push(img_tag.to_string());
            html_with_placeholders =
                html_with_placeholders.replacen(img_tag, &format!("__IMG_PLACEHOLDER_{}__", i), 1);
        }

        // 移除其他 HTML 标签
        let mut result = String::new();
        let mut in_tag = false;

        for ch in html_with_placeholders.chars() {
            match ch {
                '<' => in_tag = true,
                '>' => in_tag = false,
                _ if !in_tag => result.push(ch),
                _ => {}
            }
        }

        // 还原 img 标签
        for (i, img_tag) in img_tags.iter().enumerate() {
            result = result.replace(&format!("__IMG_PLACEHOLDER_{}__", i), img_tag);
        }

        result
    }

    /// 从内容中提取标题（支持多种格式）
    fn extract_title_from_content(content: &str) -> Option<String> {
        use regex::Regex;

        // 只检查前500字符（使用字符边界安全的切片）
        let preview = if content.len() > 500 {
            // 找到第500个字符的边界
            let mut char_count = 0;
            let mut byte_index = 0;
            for (idx, _) in content.char_indices() {
                if char_count >= 500 {
                    byte_index = idx;
                    break;
                }
                char_count += 1;
            }
            &content[..byte_index]
        } else {
            content
        };

        // 常见章节标题模式（按优先级排序）
        let patterns = vec![
            // 中文章节
            r"(?m)^第[零一二三四五六七八九十百千万0-9]+章[^\n]{0,40}",
            r"(?m)^第[零一二三四五六七八九十百千万0-9]+节[^\n]{0,40}",
            r"(?m)^第[零一二三四五六七八九十百千万0-9]+回[^\n]{0,40}",
            r"(?m)^第[零一二三四五六七八九十百千万0-9]+话[^\n]{0,40}",
            r"(?m)^第[零一二三四五六七八九十百千万0-9]+卷[^\n]{0,40}",
            // 常见固定标题
            r"(?m)^(简介|彩页|序章|楔子|前言|后记|尾声|番外|插图)[^\n]{0,30}",
            // 英文章节
            r"(?im)^Chapter [0-9]+[^\n]{0,40}",
            // 纯数字
            r"(?m)^[0-9]+[\.、\s][^\n]{1,40}",
        ];

        for pattern in &patterns {
            if let Ok(re) = Regex::new(pattern) {
                if let Some(mat) = re.find(preview) {
                    let title = mat.as_str().trim().to_string();
                    // 过滤太短或太长的标题
                    if title.len() >= 2 && title.len() <= 50 {
                        return Some(title);
                    }
                }
            }
        }

        None
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
