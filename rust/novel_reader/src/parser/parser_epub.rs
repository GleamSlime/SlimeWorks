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
    /// 解析 epub 文件（仅从 TOC/spine 元数据获取章节列表，不加载任何内容）
    pub fn parse<P: AsRef<Path>>(path: P) -> Result<NovelContent> {
        let path = path.as_ref();
        let doc = epub::doc::EpubDoc::new(path)
            .map_err(|e| anyhow::anyhow!("Failed to open epub: {:?}", e))?;

        let novel_id = format!("{:x}", md5::compute(path.to_string_lossy().as_bytes()));
        println!("EpubParser: Parsing metadata from TOC/spine (no content loading)");

        // ── 1. 从 TOC 构建 资源路径 → 标题 映射 ──
        let mut toc_title_map: std::collections::HashMap<String, String> =
            std::collections::HashMap::new();
        fn collect_toc(
            toc: &[epub::doc::NavPoint],
            map: &mut std::collections::HashMap<String, String>,
        ) {
            for nav in toc {
                let path_str = nav.content.to_string_lossy().to_string();
                // 去掉 fragment（#anchor）以匹配 resource path
                let base_path = path_str.split('#').next().unwrap_or(&path_str).to_string();
                if !nav.label.trim().is_empty() {
                    let label = nav.label.trim().to_string();
                    map.entry(base_path.clone()).or_insert(label.clone());
                    // 也用文件名作为后备匹配键
                    if let Some(filename) = base_path.split('/').last() {
                        map.entry(filename.to_string()).or_insert(label);
                    }
                }
                collect_toc(&nav.children, map);
            }
        }
        collect_toc(&doc.toc, &mut toc_title_map);
        println!("EpubParser: TOC has {} label entries", toc_title_map.len());

        // ── 2. 遍历 spine，直接构建章节列表（不加载内容） ──
        let mut chapters = Vec::new();
        for (index, spine_item) in doc.spine.iter().enumerate() {
            let resource_id = &spine_item.idref;

            // 查找资源路径和 MIME 类型
            let resource = match doc.resources.get(resource_id.as_str()) {
                Some(r) => r,
                None => continue, // 未知资源，跳过
            };

            // 跳过非内容资源（图片、CSS 等）
            let mime_lower = resource.mime.to_lowercase();
            if !mime_lower.contains("html") && !mime_lower.contains("xml") {
                continue;
            }

            let resource_path = resource.path.to_string_lossy().to_string();

            // 从 TOC 映射获取标题
            let title = toc_title_map
                .get(&resource_path)
                .or_else(|| {
                    // 尝试只用文件名匹配
                    resource_path
                        .split('/')
                        .last()
                        .and_then(|filename| toc_title_map.get(filename))
                })
                .cloned()
                .unwrap_or_else(|| {
                    if !resource_id.is_empty() {
                        resource_id.clone()
                    } else {
                        format!("第{}章", index + 1)
                    }
                });

            chapters.push(NovelChapter {
                id: format!("{}_{}::res::{}", novel_id, index, resource_id),
                title,
                index,
                content: None, // 延迟加载，由 get_chapter_content 提供
            });
        }

        println!(
            "EpubParser: Parsed {} chapters from spine (no content loaded)",
            chapters.len()
        );
        Ok(NovelContent { novel_id, chapters })
    }

    /// 获取指定章节的内容（按需提取图片并转base64）
    pub fn get_chapter_content<P: AsRef<Path>>(path: P, chapter_index: usize) -> Result<String> {
        let path = path.as_ref();
        let mut doc = epub::doc::EpubDoc::new(path)
            .map_err(|e| anyhow::anyhow!("Failed to open epub: {:?}", e))?;

        let novel_id = format!("{:x}", md5::compute(path.to_string_lossy().as_bytes()));

        // CSS目录（使用应用数据目录而非临时目录）
        let css_dir = crate::api::get_app_data_dir()
            .join("epub_css")
            .join(&novel_id);
        let _ = fs::create_dir_all(&css_dir);

        // 读取章节内容
        doc.set_current_chapter(chapter_index);
        let (content_bytes, _mime) = doc
            .get_current()
            .ok_or_else(|| anyhow::anyhow!("Chapter {} not found", chapter_index))?;

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
                    println!("EpubParser: fallback decode used: {}", fb.name());
                    break;
                }
            }
        }

        // 将图片转为base64内嵌（不写本地）
        content = Self::embed_images_as_base64(path, &content)?;

        // 提取CSS（如果还没有）
        let css_content = match Self::extract_css(path, &css_dir) {
            Ok(css) => {
                println!("EpubParser: CSS loaded, {} bytes", css.len());
                css
            }
            Err(_) => String::new(),
        };

        // 应用CSS样式
        if !css_content.is_empty() {
            content = Self::inline_css_styles(&content, &css_content);
        }

        // 返回处理后的HTML内容（保留HTML标签和base64图片）
        println!(
            "EpubParser: Returning chapter content, length: {} chars, contains 'data:image': {}",
            content.len(),
            content.contains("data:image")
        );

        // 打印前500个字符用于调试
        let preview: String = content.chars().take(500).collect();
        if content.chars().count() > 500 {
            println!("EpubParser: Content preview: {}", preview);
        } else {
            println!("EpubParser: Full content: {}", content);
        }

        Ok(content)
    }

    // ─── 图片相关 ──────────────────────────────────────────────────────

    /// 将HTML中的图片转为base64内嵌（直接从EPUB读取，不写本地）
    fn embed_images_as_base64<P: AsRef<Path>>(epub_path: P, html: &str) -> Result<String> {
        use regex::Regex;

        println!(
            "EpubParser: embed_images_as_base64 called, HTML length: {}",
            html.len()
        );

        // 找出HTML中引用的所有图片路径
        let img_regex = Regex::new(r#"<img[^>]*src\s*=\s*["']([^"']+)["'][^>]*>"#)?;

        // 打开EPUB archive
        let file = File::open(epub_path)?;
        let mut archive = ZipArchive::new(file)?;

        // 构建图片路径到base64的映射
        let mut image_map: std::collections::HashMap<String, String> =
            std::collections::HashMap::new();

        // 遍历archive找到所有图片
        for i in 0..archive.len() {
            if let Ok(mut file) = archive.by_index(i) {
                let name = file.name().to_string();
                let name_lower = name.to_lowercase();

                if name_lower.ends_with(".jpg")
                    || name_lower.ends_with(".jpeg")
                    || name_lower.ends_with(".png")
                    || name_lower.ends_with(".gif")
                    || name_lower.ends_with(".svg")
                    || name_lower.ends_with(".webp")
                {
                    // 读取图片数据
                    let mut buffer = Vec::new();
                    if file.read_to_end(&mut buffer).is_ok() && !buffer.is_empty() {
                        // 转为base64
                        let base64_data = base64::Engine::encode(
                            &base64::engine::general_purpose::STANDARD,
                            &buffer,
                        );

                        // 猜测MIME类型
                        let mime_type = if name_lower.ends_with(".png") {
                            "image/png"
                        } else if name_lower.ends_with(".gif") {
                            "image/gif"
                        } else if name_lower.ends_with(".svg") {
                            "image/svg+xml"
                        } else if name_lower.ends_with(".webp") {
                            "image/webp"
                        } else {
                            "image/jpeg"
                        };

                        let data_url = format!("data:{};base64,{}", mime_type, base64_data);

                        // 存储多个变体路径（去掉 ../ 等）
                        image_map.insert(name.clone(), data_url.clone());
                        image_map
                            .insert(name.trim_start_matches("../").to_string(), data_url.clone());
                        image_map
                            .insert(name.trim_start_matches("./").to_string(), data_url.clone());

                        // 只存储文件名
                        if let Some(file_name) = name.split('/').last() {
                            image_map.insert(file_name.to_string(), data_url.clone());
                        }

                        println!("EpubParser: Converted image to base64: {}", name);
                    }
                }
            }
        }

        if image_map.is_empty() {
            println!("EpubParser: No images found in this chapter");
            return Ok(html.to_string());
        }

        println!("EpubParser: Converted {} images to base64", image_map.len());

        // 检查HTML中是否有img标签
        let img_count = img_regex.find_iter(html).count();
        println!(
            "EpubParser: Found {} img tags in HTML before replacement",
            img_count
        );

        // 替换HTML中的图片路径
        let _replaced_count = 0;
        let result = img_regex.replace_all(html, |caps: &regex::Captures| {
            let full_tag = &caps[0]; // 完整的 <img> 标签
            let original_src = &caps[1]; // src 属性原始值
            let cleaned_src = original_src
                .trim_start_matches("../")
                .trim_start_matches("./");

            // 尝试从映射中找到base64数据
            if let Some(data_url) = image_map
                .get(cleaned_src)
                .or_else(|| image_map.get(original_src))
                .or_else(|| {
                    // 尝试只用文件名匹配
                    let file_name = cleaned_src
                        .split('/')
                        .last()
                        .or_else(|| cleaned_src.split('\\').last())?;
                    image_map.get(file_name)
                })
            {
                println!(
                    "EpubParser: Embedding image: {} ({}KB base64)",
                    original_src,
                    data_url.len() / 1024
                );

                // 安全替换：先尝试双引号，再尝试单引号
                if full_tag.contains(&format!("src=\"{}\"", original_src)) {
                    return full_tag.replace(
                        &format!("src=\"{}\"", original_src),
                        &format!("src=\"{}\"", data_url),
                    );
                } else if full_tag.contains(&format!("src='{}'", original_src)) {
                    return full_tag.replace(
                        &format!("src='{}'", original_src),
                        &format!("src='{}'", data_url),
                    );
                } else {
                    // 如果都不匹配，说明可能有特殊格式，记录日志
                    println!("EpubParser: Unusual img tag format: {}", full_tag);
                    return full_tag.to_string();
                }
            }

            println!("EpubParser: Image not found in archive: {}", original_src);
            full_tag.to_string()
        });

        let result_str = result.to_string();

        // 验证替换结果
        let result_img_count = img_regex.find_iter(&result_str).count();
        println!(
            "EpubParser: Image replacement complete - {} img tags remain, original had {}",
            result_img_count, img_count
        );

        // 检查是否有不完整的img标签
        let img_open_count = result_str.matches("<img").count();
        if img_open_count != result_img_count {
            println!(
                "EpubParser: WARNING - Found {} '<img' but only {} complete img tags!",
                img_open_count, result_img_count
            );
        }

        Ok(result_str)
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

                println!("EpubParser: Extracted CSS: {}", name);
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

        println!("EpubParser: Parsed {} CSS class rules", class_styles.len());

        if class_styles.is_empty() {
            println!("EpubParser: No CSS class rules found to inline");
            return html.to_string();
        }

        let tag_regex =
            Regex::new(r#"<([a-zA-Z0-9]+)([^>]*?)class\s*=\s*["']([^"']+)["']([^>]*?)>"#).unwrap();

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
                println!("EpubParser: Failed to compile preserve_regex: {}", e);
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
                        let tmp = crate::api::get_app_data_dir().join("covers");
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
                                        println!(
                                            "EpubParser: Cover compressed and saved: {:?}",
                                            out_path
                                        );
                                    }
                                    Err(e) => {
                                        println!(
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
                            Ok(_) => println!("EpubParser: Cover file is empty, skipping"),
                            Err(e) => println!("EpubParser: Failed to read cover: {}", e),
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
