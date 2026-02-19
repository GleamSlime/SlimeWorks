use anyhow::{Context, Result};
use std::fs::File;
use std::io::Read;
use std::path::Path;

use crate::types::{NovelChapter, NovelContent, NovelFormat, NovelMetadata};
use std::fs;
use zip::ZipArchive;

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

        // 检查是否需要重新提取图片：比较epub内图片数量与缓存目录中文件数量
        let archive_image_count = (|| -> Result<usize> {
            let f = File::open(path)?;
            let mut archive = ZipArchive::new(f)?;
            let mut cnt: usize = 0;
            for i in 0..archive.len() {
                if let Ok(file) = archive.by_index(i) {
                    let name = file.name().to_lowercase();
                    if name.ends_with(".jpg")
                        || name.ends_with(".jpeg")
                        || name.ends_with(".png")
                        || name.ends_with(".gif")
                        || name.ends_with(".svg")
                        || name.ends_with(".webp")
                    {
                        cnt += 1;
                    }
                }
            }
            Ok(cnt)
        })()
        .unwrap_or(0);

        // 统计缓存目录中文件数量
        let existing_count = Self::count_files_in_dir(&image_dir).unwrap_or(0);

        let need_extract = existing_count == 0 || archive_image_count > existing_count;

        log::info!(
            "EpubParser: archive_images={} cached_images={} image_dir={:?}",
            archive_image_count,
            existing_count,
            image_dir
        );

        if need_extract {
            log::info!("EpubParser: Image directory missing/partial, extracting images...");
            match Self::extract_images(path, &image_dir) {
                Ok(_) => log::info!("EpubParser: Images extracted successfully"),
                Err(e) => log::warn!("EpubParser: Failed to extract images: {:?}", e),
            };
        } else {
            log::info!("EpubParser: Using existing images from cache");
        }

        // 创建CSS目录并提取CSS文件
        let css_dir = std::env::temp_dir()
            .join("slimeworks")
            .join("epub_css")
            .join(&novel_id);
        let _ = fs::create_dir_all(&css_dir);

        let css_content = match Self::extract_css(path, &css_dir) {
            Ok(css) => {
                log::info!("EpubParser: CSS extracted, {} bytes", css.len());
                css
            }
            Err(e) => {
                log::warn!("EpubParser: Failed to extract CSS: {:?}", e);
                String::new()
            }
        };

        let mut chapters = Vec::new();
        let num_pages = doc.get_num_pages();

        for index in 0..num_pages {
            doc.set_current_page(index);
            if let Some((content_bytes, _mime)) = doc.get_current() {
                let mut content = String::from_utf8_lossy(&content_bytes).to_string();
                if content.contains('\u{FFFD}') {
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

                let mut content = Self::convert_image_paths(&content, &image_dir);

                if !css_content.is_empty() {
                    content = Self::inline_css_styles(&content, &css_content);
                }

                let text = Self::strip_html_tags(&content);

                if !text.trim().is_empty() {
                    let extracted_title = Self::extract_title_from_content(&text);

                    let resource_id = doc
                        .get_current_id()
                        .map(|s| s.to_string())
                        .unwrap_or_default();
                    let chapter = NovelChapter {
                        id: format!("{}_{}::res::{}", novel_id, index, resource_id),
                        title: extracted_title
                            .or_else(|| Self::extract_title_from_html(&content))
                            .or_else(|| Self::extract_first_paragraph_as_title(&text))
                            .unwrap_or_else(|| {
                                if !resource_id.is_empty() {
                                    resource_id.clone()
                                } else {
                                    format!("第{}章", index + 1)
                                }
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

    // ─── 图片相关 ──────────────────────────────────────────────────────

    /// 从EPUB中提取所有图片
    fn extract_images<P: AsRef<Path>>(epub_path: P, output_dir: &Path) -> Result<()> {
        let file = File::open(epub_path)?;
        let mut archive = ZipArchive::new(file)?;

        for i in 0..archive.len() {
            let mut file = archive.by_index(i)?;
            let name = file.name().to_string();

            if name.ends_with(".jpg")
                || name.ends_with(".jpeg")
                || name.ends_with(".png")
                || name.ends_with(".gif")
                || name.ends_with(".svg")
                || name.ends_with(".webp")
            {
                let file_path = output_dir.join(&name);
                if let Some(parent) = file_path.parent() {
                    fs::create_dir_all(parent)?;
                }
                let mut out_file = File::create(&file_path)?;
                let copied = std::io::copy(&mut file, &mut out_file)?;
                if copied > 0 {
                    log::info!(
                        "EpubParser: Extracted image: {} ({} bytes)",
                        file_path.display(),
                        copied
                    );
                } else {
                    log::warn!(
                        "EpubParser: Extracted image {} but size is 0",
                        file_path.display()
                    );
                    let _ = std::fs::remove_file(&file_path);
                }
            }
        }

        Ok(())
    }

    /// 递归统计目录中文件数量
    fn count_files_in_dir(dir: &Path) -> Option<usize> {
        let mut cnt: usize = 0;
        if let Ok(entries) = fs::read_dir(dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.is_dir() {
                    if let Some(sub) = Self::count_files_in_dir(&path) {
                        cnt += sub;
                    }
                } else {
                    cnt += 1;
                }
            }
            return Some(cnt);
        }
        None
    }

    /// 转换HTML中的图片路径为本地文件路径
    fn convert_image_paths(html: &str, image_dir: &Path) -> String {
        use regex::Regex;

        let img_regex = Regex::new(r#"<img[^>]*src\s*=\s*["']([^"']+)["'][^>]*>"#).unwrap();

        let result = img_regex.replace_all(html, |caps: &regex::Captures| {
            let src = &caps[1];
            let cleaned_src = src.trim_start_matches("../").trim_start_matches("./");
            let mut local_path = image_dir.join(cleaned_src);

            if !local_path.exists() {
                if let Some(file_name) = cleaned_src
                    .split('/')
                    .last()
                    .or_else(|| cleaned_src.split('\\').last())
                {
                    if let Some(found) = Self::find_image_recursive(image_dir, file_name) {
                        local_path = found;
                        log::debug!(
                            "EpubParser: Found image via recursive search: {}",
                            local_path.display()
                        );
                    }
                }
            }

            if !local_path.exists() {
                log::warn!(
                    "EpubParser: Image referenced not found after search: {}",
                    src
                );
                return caps[0].to_string();
            }

            #[cfg(target_os = "windows")]
            let file_url = format!(
                "file:///{}",
                local_path.to_string_lossy().replace('\\', "/")
            );

            #[cfg(not(target_os = "windows"))]
            let file_url = format!("file://{}", local_path.to_string_lossy());

            log::debug!("EpubParser: Image path converted: {} -> {}", src, file_url);
            caps[0].replace(src, &file_url)
        });

        result.to_string()
    }

    /// 递归查找图片文件（不区分大小写）
    fn find_image_recursive(dir: &Path, file_name: &str) -> Option<std::path::PathBuf> {
        if let Ok(entries) = std::fs::read_dir(dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.is_dir() {
                    if let Some(found) = Self::find_image_recursive(&path, file_name) {
                        return Some(found);
                    }
                } else if path
                    .file_name()
                    .and_then(|n| n.to_str())
                    .map(|n| n.eq_ignore_ascii_case(file_name))
                    .unwrap_or(false)
                {
                    return Some(path);
                }
            }
        }
        None
    }

    // ─── CSS 相关 ──────────────────────────────────────────────────────

    /// 从EPUB中提取所有CSS文件并合并
    fn extract_css<P: AsRef<Path>>(epub_path: P, output_dir: &Path) -> Result<String> {
        let file = File::open(epub_path)?;
        let mut archive = ZipArchive::new(file)?;
        let mut all_css = String::new();

        for i in 0..archive.len() {
            let mut file = archive.by_index(i)?;
            let name = file.name().to_string();

            if name.ends_with(".css") {
                let mut content = String::new();
                std::io::Read::read_to_string(&mut file, &mut content)?;

                let file_path = output_dir.join(&name);
                if let Some(parent) = file_path.parent() {
                    fs::create_dir_all(parent)?;
                }
                fs::write(&file_path, &content)?;

                all_css.push_str(&content);
                all_css.push('\n');

                log::info!("EpubParser: Extracted CSS: {}", name);
            }
        }

        Ok(all_css)
    }

    /// 将CSS样式内联到HTML元素中
    fn inline_css_styles(html: &str, css: &str) -> String {
        use regex::Regex;
        use std::collections::HashMap;

        let mut class_styles: HashMap<String, String> = HashMap::new();
        let css_rule_regex = Regex::new(r"\.([a-zA-Z0-9_-]+)\s*\{([^}]+)\}").unwrap();

        for caps in css_rule_regex.captures_iter(css) {
            let class_name = caps[1].to_string();
            let properties = caps[2].trim().to_string();
            class_styles.insert(class_name, properties);
        }

        log::info!("EpubParser: Parsed {} CSS class rules", class_styles.len());

        if class_styles.is_empty() {
            log::debug!("EpubParser: No CSS class rules found to inline");
            return html.to_string();
        }

        let tag_regex =
            Regex::new(r#"<([a-zA-Z0-9]+)([^>]*?)class\s*=\s*["']([^"']+)["']([^>]*?)>"#)
                .unwrap();

        let result = tag_regex.replace_all(html, |caps: &regex::Captures| {
            let tag_name = &caps[1];
            let before_class = &caps[2];
            let class_names = &caps[3];
            let after_class = &caps[4];

            let mut combined_styles = Vec::new();
            for class_name in class_names.split_whitespace() {
                if let Some(style) = class_styles.get(class_name) {
                    combined_styles.push(style.clone());
                }
            }

            if combined_styles.is_empty() {
                return caps[0].to_string();
            }

            let inline_style = combined_styles.join(" ");

            if after_class.contains("style=") || before_class.contains("style=") {
                let style_regex = Regex::new(r#"style\s*=\s*["']([^"']*)["']"#).unwrap();
                let full_attrs = format!("{}{}", before_class, after_class);
                let updated = style_regex.replace(&full_attrs, |s_caps: &regex::Captures| {
                    format!("style=\"{} {}\"", &s_caps[1], inline_style)
                });
                format!("<{} class=\"{}\"{}>", tag_name, class_names, updated)
            } else {
                format!(
                    "<{}{} class=\"{}\" style=\"{}\"{}>",
                    tag_name, before_class, class_names, inline_style, after_class
                )
            }
        });

        result.to_string()
    }

    // ─── HTML 处理 ─────────────────────────────────────────────────────

    /// 简单的 HTML 标签移除（保留 img, style 标签及常用格式化标签）
    pub(crate) fn strip_html_tags(html: &str) -> String {
        use regex::Regex;

        let preserve_pattern = r"(?s)(<style\b[^>]*>.*?</style>)|(<p\b[^>]*>.*?</p>)|(<div\b[^>]*>.*?</div>)|(<span\b[^>]*>.*?</span>)|(<a\b[^>]*>.*?</a>)|(<strong\b[^>]*>.*?</strong>)|(<em\b[^>]*>.*?</em>)|(<b\b[^>]*>.*?</b>)|(<i\b[^>]*>.*?</i>)|(<u\b[^>]*>.*?</u>)|(<h[1-6]\b[^>]*>.*?</h[1-6]>)|(<img\b[^>]*\/?>)|(<br\b[^>]*\/?>)|(<hr\b[^>]*\/?>)";
        let preserve_regex = match Regex::new(&preserve_pattern) {
            Ok(r) => r,
            Err(e) => {
                log::warn!("EpubParser: Failed to compile preserve_regex: {}", e);
                Regex::new(r"(<img\b[^>]*\/?>)|(<br\b[^>]*\/?>)|(<hr\b[^>]*\/?>)").unwrap()
            }
        };

        let mut preserved_tags = Vec::new();
        let mut html_with_placeholders = html.to_string();

        for (i, mat) in preserve_regex.find_iter(html).enumerate() {
            let tag = mat.as_str();
            preserved_tags.push(tag.to_string());
            html_with_placeholders =
                html_with_placeholders.replacen(tag, &format!("__PRESERVE_TAG_{}__", i), 1);
        }

        let tag_regex = Regex::new(r"<[^>]+>").unwrap();
        let mut result = tag_regex
            .replace_all(&html_with_placeholders, "")
            .to_string();

        for (i, tag) in preserved_tags.iter().enumerate() {
            result = result.replace(&format!("__PRESERVE_TAG_{}__", i), tag);
        }

        result
    }

    // ─── 标题提取 ──────────────────────────────────────────────────────

    /// 从原始 HTML 中提取 h1/h2/h3 标签文本作为标题
    fn extract_title_from_html(html: &str) -> Option<String> {
        use regex::Regex;
        let re = Regex::new(r"(?si)<h[1-3][^>]*>\s*([^<]{2,60})\s*</h[1-3]>").ok()?;
        for cap in re.captures_iter(html) {
            let title = cap[1].trim().to_string();
            if title.len() >= 2 && title.len() <= 60 && !title.chars().all(char::is_whitespace) {
                return Some(title);
            }
        }
        None
    }

    /// 以去除 HTML 后的首段非空文本作为标题兜底
    fn extract_first_paragraph_as_title(text: &str) -> Option<String> {
        for line in text.lines() {
            let trimmed = line.trim();
            if trimmed.chars().count() < 2 {
                continue;
            }
            let title: String = trimmed.chars().take(50).collect();
            return Some(title);
        }
        None
    }

    /// 从内容中提取标题（支持多种格式）
    fn extract_title_from_content(content: &str) -> Option<String> {
        use regex::Regex;

        let preview = if content.len() > 500 {
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

        let patterns = vec![
            r"(?m)^第[零一二三四五六七八九十百千万0-9]+章[^\n]{0,40}",
            r"(?m)^第[零一二三四五六七八九十百千万0-9]+节[^\n]{0,40}",
            r"(?m)^第[零一二三四五六七八九十百千万0-9]+回[^\n]{0,40}",
            r"(?m)^第[零一二三四五六七八九十百千万0-9]+话[^\n]{0,40}",
            r"(?m)^第[零一二三四五六七八九十百千万0-9]+卷[^\n]{0,40}",
            r"(?m)^(简介|彩页|序章|楔子|前言|后记|尾声|番外|插图)[^\n]{0,30}",
            r"(?im)^Chapter [0-9]+[^\n]{0,40}",
            r"(?m)^[0-9]+[\.、\s][^\n]{1,40}",
        ];

        for pattern in &patterns {
            if let Ok(re) = Regex::new(pattern) {
                if let Some(mat) = re.find(preview) {
                    let title = mat.as_str().trim().to_string();
                    if title.len() >= 2 && title.len() <= 50 {
                        return Some(title);
                    }
                }
            }
        }

        None
    }

    // ─── 元数据 ────────────────────────────────────────────────────────

    /// 提取 epub 文件的元数据
    pub fn extract_metadata<P: AsRef<Path>>(path: P) -> Result<NovelMetadata> {
        let path = path.as_ref();
        let doc = epub::doc::EpubDoc::new(path)
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

        let mut cover_path: Option<String> = None;
        if let Ok(file) = File::open(path) {
            if let Ok(mut archive) = ZipArchive::new(file) {
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
                        let tmp = std::env::temp_dir().join("slimeworks").join("covers");
                        let _ = fs::create_dir_all(&tmp);
                        let out_path = tmp.join(format!("{}.jpg", novel_id));

                        let mut buf = Vec::new();
                        use std::io::Read;
                        match f.read_to_end(&mut buf) {
                            Ok(bytes_read) if bytes_read > 0 => {
                                let compressed = (|| -> Result<()> {
                                    use image::imageops::FilterType;
                                    let img = image::load_from_memory(&buf)?;
                                    let (w, h) = (img.width(), img.height());
                                    let img = if w > 400 || h > 600 {
                                        img.resize(400, 600, FilterType::Lanczos3)
                                    } else {
                                        img
                                    };
                                    img.save_with_format(&out_path, image::ImageFormat::Jpeg)?;
                                    Ok(())
                                })();

                                match compressed {
                                    Ok(_) => {
                                        cover_path = Some(out_path.to_string_lossy().to_string());
                                        log::info!(
                                            "EpubParser: Cover compressed and saved: {:?}",
                                            out_path
                                        );
                                    }
                                    Err(e) => {
                                        log::warn!(
                                            "EpubParser: Cover compression failed ({}), saving raw",
                                            e
                                        );
                                        if let Ok(mut out_file) = File::create(&out_path) {
                                            use std::io::Write;
                                            if out_file.write_all(&buf).is_ok() {
                                                cover_path =
                                                    Some(out_path.to_string_lossy().to_string());
                                            }
                                        }
                                    }
                                }
                            }
                            Ok(_) => log::warn!("EpubParser: Cover file is empty, skipping"),
                            Err(e) => log::warn!("EpubParser: Failed to read cover: {}", e),
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
            is_favorite: false,
            tags: Vec::new(),
            modified_at: chrono::DateTime::from(
                metadata_fs
                    .modified()
                    .unwrap_or(std::time::SystemTime::now()),
            ),
            added_at: chrono::Utc::now(),
            progress: 0.0,
            current_chapter_id: None,
            last_read_at: None,
            cover_path,
            folder_id: None,
            custom_order: None,
            notes: None,
        })
    }
}
