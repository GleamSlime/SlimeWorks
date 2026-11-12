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

    /// 读取章节原始 HTML（不含图片 base64，也不落盘 CSS）。
    ///
    /// 全文搜索只要文本：旧实现沿着 get_chapter_content 走，每章都把**全书所有图片**
    /// base64 塞进 image_map 再替换一遍，搜索一本书等于把整本图集在内存里编几轮 base64。
    pub fn get_chapter_raw_html<P: AsRef<Path>>(path: P, chapter_index: usize) -> Result<String> {
        let path = path.as_ref();
        let mut doc = epub::doc::EpubDoc::new(path)
            .map_err(|e| anyhow::anyhow!("Failed to open epub: {:?}", e))?;

        // 越界防护：epub crate 的 set_current_chapter 对非法索引仅返回 false，
        // 不会改变 current，会导致静默返回第 0 章内容。这里显式校验 spine 边界并报错。
        if chapter_index >= doc.spine.len() {
            return Err(anyhow::anyhow!(
                "Chapter {} not found (spine has {} chapters)",
                chapter_index,
                doc.spine.len()
            ));
        }
        doc.set_current_chapter(chapter_index);
        let (content_bytes, _mime) = doc
            .get_current()
            .ok_or_else(|| anyhow::anyhow!("Chapter {} not found", chapter_index))?;
        Ok(Self::decode_chapter_bytes(&content_bytes))
    }

    /// 章节字节 → 字符串，遇到替换字符时按常见中文/日文编码回退。
    fn decode_chapter_bytes(content_bytes: &[u8]) -> String {
        let content = String::from_utf8_lossy(content_bytes).to_string();
        if content.contains('\u{FFFD}') {
            let fallbacks: [&'static encoding_rs::Encoding; 4] = [
                encoding_rs::GBK,
                encoding_rs::SHIFT_JIS,
                encoding_rs::WINDOWS_1252,
                encoding_rs::EUC_JP,
            ];
            for fb in &fallbacks {
                let (s, _, _) = fb.decode(content_bytes);
                let s = s.to_string();
                if !s.contains('\u{FFFD}') {
                    println!("EpubParser: fallback decode used: {}", fb.name());
                    return s;
                }
            }
        }
        content
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

        // 越界防护：epub crate 的 set_current_chapter 对非法索引仅返回 false，
        // 不会改变 current，会导致静默返回第 0 章内容。这里显式校验 spine 边界并报错。
        if chapter_index >= doc.spine.len() {
            return Err(anyhow::anyhow!(
                "Chapter {} not found (spine has {} chapters)",
                chapter_index,
                doc.spine.len()
            ));
        }

        // 读取章节内容
        doc.set_current_chapter(chapter_index);
        let (content_bytes, _mime) = doc
            .get_current()
            .ok_or_else(|| anyhow::anyhow!("Chapter {} not found", chapter_index))?;
        // 章节文件在 epub 内的路径：图片 src 是相对它解析的；取不到就退回按文件名匹配
        let chapter_path = doc.get_current_path();

        let mut content = Self::decode_chapter_bytes(&content_bytes);

        // 图片与 CSS 共用同一个 zip 句柄：旧实现每章要为图片和 CSS 各开一次 zip
        // （plus EpubDoc 自己那次），三次解析中央目录纯属重复劳动。
        let file = File::open(path)?;
        let mut archive = ZipArchive::new(file)?;
        let cache_key = epub_cache_key(path);

        // 将图片转为base64内嵌（不写本地，只处理本章真正引用到的图）
        content = Self::embed_images_as_base64(
            &mut archive,
            &cache_key,
            chapter_path.as_deref(),
            &content,
        )?;

        // 提取CSS（如果还没有）
        let css_content = match Self::extract_css(&mut archive, &css_dir) {
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

    /// 将HTML中的图片转为base64内嵌（直接从EPUB读取，不写本地）。
    ///
    /// 只处理**本章 HTML 实际引用到的**图片：旧实现每章遍历整本 zip 把全书图片
    /// base64 进 image_map（且每张存 4 个路径变体），插图本单章峰值 ≈ 全书图片体积 ×5。
    fn embed_images_as_base64(
        archive: &mut ZipArchive<File>,
        epub_key: &str,
        chapter_path: Option<&Path>,
        html: &str,
    ) -> Result<String> {
        use regex::Regex;

        let img_regex = Regex::new(r#"<img[^>]*src\s*=\s*["']([^"']+)["'][^>]*>"#)?;

        // 先收集本章引用的 src 集合，同名只读一次 zip
        let mut wanted: Vec<String> = Vec::new();
        for caps in img_regex.captures_iter(html) {
            let src = caps[1].to_string();
            if !wanted.contains(&src) {
                wanted.push(src);
            }
        }
        if wanted.is_empty() {
            return Ok(html.to_string());
        }

        let mut image_map: std::collections::HashMap<String, String> =
            std::collections::HashMap::new();
        for src in &wanted {
            if let Some(data_url) = load_image_data_url(archive, epub_key, chapter_path, src) {
                image_map.insert(src.clone(), data_url);
            } else {
                println!("EpubParser: Image not found in archive: {}", src);
            }
        }

        if image_map.is_empty() {
            return Ok(html.to_string());
        }

        let result = img_regex.replace_all(html, |caps: &regex::Captures| {
            let full_tag = &caps[0];
            let original_src = &caps[1];
            let Some(data_url) = image_map.get(original_src) else {
                return full_tag.to_string();
            };

            // 安全替换：先尝试双引号，再尝试单引号
            if full_tag.contains(&format!("src=\"{}\"", original_src)) {
                full_tag.replace(
                    &format!("src=\"{}\"", original_src),
                    &format!("src=\"{}\"", data_url),
                )
            } else if full_tag.contains(&format!("src='{}'", original_src)) {
                full_tag.replace(
                    &format!("src='{}'", original_src),
                    &format!("src='{}'", data_url),
                )
            } else {
                println!("EpubParser: Unusual img tag format: {}", full_tag);
                full_tag.to_string()
            }
        });

        Ok(result.to_string())
    }


    // ─── 图片资源查找（含跨章缓存）──────────────────────────────────────

    // ─── CSS 相关 ──────────────────────────────────────────────────────

    /// 从EPUB中提取所有CSS文件并合并。
    ///
    /// archive 由调用方复用：同一章既要取图又要取 CSS，各开一次 zip 等于把中央目录
    /// 解析三遍（EpubDoc 自己还有一次）。
    fn extract_css(archive: &mut ZipArchive<File>, output_dir: &Path) -> Result<String> {
        let mut all_css = String::new();

        // 先收名字再逐个读：ZipArchive 同一时刻只能借用出一个条目，不能边遍历边嵌套打开
        let names: Vec<String> = archive
            .file_names()
            .filter(|n| n.ends_with(".css"))
            .map(|n| n.to_string())
            .collect();

        for name in names {
            let mut file = archive.by_name(&name)?;
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
    #[allow(dead_code)]
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
    #[allow(dead_code)]
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
    #[allow(dead_code)]
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
    #[allow(dead_code)]
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


// ─── epub 图片资源查找与跨章缓存 ────────────────────────────────────────
//
// 三个目标：① 只读本章引用到的图片（不再整本扫描）；② 同名变体只存一份
// （旧实现每张图往 image_map 塞 4 个路径别名，等于把内存放大 4 倍）；
// ③ 跨章复用已编码的 base64，避免翻页时反复读 zip + 反复编码。

/// 跨章 base64 缓存的总字节预算。插图本单张常见 100KB~2MB，
/// 32 MiB 大约覆盖一章到两章的图；超出后按 LRU 淘汰，保证内存有上界。
const IMAGE_CACHE_BUDGET_BYTES: usize = 32 * 1024 * 1024;

/// 缓存键：epub 绝对路径。条目值为 (base64 data URL, 字节数)。
type ImageCache = std::collections::HashMap<String, std::collections::VecDeque<(String, String)>>;

fn image_cache() -> &'static std::sync::Mutex<ImageCache> {
    static CACHE: std::sync::OnceLock<std::sync::Mutex<ImageCache>> = std::sync::OnceLock::new();
    CACHE.get_or_init(|| std::sync::Mutex::new(std::collections::HashMap::new()))
}

/// 缓存键 = 路径 + mtime：同一路径的 epub 被替换/重导出后，
/// 旧 base64 就不能再用了，否则会把上一版书的图当成本版的图显示。
fn epub_cache_key(path: &Path) -> String {
    let mtime = std::fs::metadata(path)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_millis())
        .unwrap_or(0);
    format!("{}#{}", path.to_string_lossy(), mtime)
}

/// 取缓存里的 data URL（命中即提到队首，淘汰发生在插入时）。
fn cache_get(epub_key: &str, resource: &str) -> Option<String> {
    let mut cache = image_cache().lock().ok()?;
    let queue = cache.get_mut(epub_key)?;
    let pos = queue.iter().position(|(k, _)| k == resource)?;
    let entry = queue.remove(pos)?;
    let url = entry.1.clone();
    queue.push_front(entry);
    Some(url)
}

/// 写入缓存并按预算淘汰队尾；单张超出预算的图不缓存（仍会正常返回）。
fn cache_put(epub_key: &str, resource: &str, url: String) {
    let size = url.len();
    if size > IMAGE_CACHE_BUDGET_BYTES {
        return;
    }
    let Ok(mut cache) = image_cache().lock() else {
        return;
    };
    let queue = cache.entry(epub_key.to_string()).or_default();
    if let Some(pos) = queue.iter().position(|(k, _)| k == resource) {
        queue.remove(pos);
    }
    queue.push_front((resource.to_string(), url));
    let mut total: usize = queue.iter().map(|(_, v)| v.len()).sum();
    while total > IMAGE_CACHE_BUDGET_BYTES {
        let Some((_, dropped)) = queue.pop_back() else {
            break;
        };
        total = total.saturating_sub(dropped.len());
    }
}

/// 按 zip 条目名猜测图片 MIME。
fn guess_image_mime(name_lower: &str) -> &'static str {
    if name_lower.ends_with(".png") {
        "image/png"
    } else if name_lower.ends_with(".gif") {
        "image/gif"
    } else if name_lower.ends_with(".svg") {
        "image/svg+xml"
    } else if name_lower.ends_with(".webp") {
        "image/webp"
    } else {
        "image/jpeg"
    }
}

fn is_image_entry(name_lower: &str) -> bool {
    name_lower.ends_with(".jpg")
        || name_lower.ends_with(".jpeg")
        || name_lower.ends_with(".png")
        || name_lower.ends_with(".gif")
        || name_lower.ends_with(".svg")
        || name_lower.ends_with(".webp")
}

/// 把 HTML 里的 src 解析成 epub 内部的条目名候选（按优先级排列）。
///
/// src 相对**章节文件所在目录**；旧实现只按裸文件名匹配，遇到 A/ch1.xhtml 引用
/// ../images/a.png 这种布局会全靠「全书图片同名别名」蒙对，也可能张冠李戴。
fn resource_candidates(chapter_path: Option<&Path>, src: &str) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    let src = src.split('#').next().unwrap_or(src);
    let src = src.split('?').next().unwrap_or(src);

    if let Some(base) = chapter_path.and_then(|p| p.parent()) {
        // 逐段手工消解 "." 与 ".."，不依赖文件系统（条目名是 zip 内部虚拟路径）
        let mut parts: Vec<String> = base
            .components()
            .map(|c| c.as_os_str().to_string_lossy().into_owned())
            .filter(|s| !s.is_empty() && s != ".")
            .collect();
        let mut ok = true;
        for seg in src.split('/') {
            match seg {
                "" | "." => continue,
                ".." => {
                    // 越过 epub 根目录说明引用了包外资源，直接放弃这条候选
                    if parts.pop().is_none() {
                        ok = false;
                        break;
                    }
                }
                other => parts.push(other.to_string()),
            }
        }
        if ok && !parts.is_empty() {
            out.push(parts.join("/"));
        }
    }

    // 裸 src（去掉前导 ./ ../）
    out.push(src.trim_start_matches("./").trim_start_matches("../").to_string());
    // 仅文件名兜底
    if let Some(name) = src.rsplit(['/', '\\']).next() {
        out.push(name.to_string());
    }
    // 保序去重：候选是按优先级排的，排序会打乱「先精确路径、后裸文件名」的次序
    let mut seen = std::collections::HashSet::new();
    out.retain(|c| !c.is_empty() && seen.insert(c.clone()));
    out
}

/// 读取 src 对应图片并编码成 data URL；找不到返回 None。
fn load_image_data_url(
    archive: &mut ZipArchive<File>,
    epub_key: &str,
    chapter_path: Option<&Path>,
    src: &str,
) -> Option<String> {
    for candidate in resource_candidates(chapter_path, src) {
        if let Some(url) = cache_get(epub_key, &candidate) {
            return Some(url);
        }
        // 中央目录里按名字精确查一次即可，不再遍历全部条目
        let Ok(mut entry) = archive.by_name(&candidate) else {
            continue;
        };
        if entry.is_dir() {
            continue;
        }
        let name_lower = entry.name().to_lowercase();
        if !is_image_entry(&name_lower) {
            continue;
        }
        let mut buffer = Vec::new();
        if entry.read_to_end(&mut buffer).is_err() || buffer.is_empty() {
            continue;
        }
        let base64_data =
            base64::Engine::encode(&base64::engine::general_purpose::STANDARD, &buffer);
        let url = format!("data:{};base64,{}", guess_image_mime(&name_lower), base64_data);
        cache_put(epub_key, &candidate, url.clone());
        return Some(url);
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use std::path::PathBuf;
    use zip::write::FileOptions;
    use zip::CompressionMethod;

    /// 构造测试用最小 epub 的选项
    struct EpubBuildOptions {
        /// dc:title 内容，None 表示完全不写 title 字段
        title: Option<&'static str>,
        /// 是否写入 dc:creator
        with_creator: bool,
        /// 是否写入 NCX 目录（toc）
        with_toc: bool,
    }

    impl Default for EpubBuildOptions {
        fn default() -> Self {
            Self {
                title: Some("测试书籍"),
                with_creator: true,
                with_toc: true,
            }
        }
    }

    /// 用 zip 写入库程序化构造一个最小合法 EPUB2 文件（epub 本质是 zip）
    fn build_minimal_epub(dir: &Path, file_name: &str, opts: &EpubBuildOptions) -> PathBuf {
        let path = dir.join(file_name);
        let file = File::create(&path).expect("创建 epub 文件失败");
        let mut writer = zip::ZipWriter::new(file);
        let stored = FileOptions::default().compression_method(CompressionMethod::Stored);

        // mimetype（规范要求为首个条目）
        writer.start_file("mimetype", stored).unwrap();
        writer.write_all(b"application/epub+zip").unwrap();

        // META-INF/container.xml 指向 OPF
        writer.start_file("META-INF/container.xml", stored).unwrap();
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

        // OPF：元数据 + manifest + spine
        let title_xml = match opts.title {
            Some(t) => format!("<dc:title>{}</dc:title>", t),
            None => String::new(),
        };
        let creator_xml = if opts.with_creator {
            "<dc:creator>测试作者</dc:creator>"
        } else {
            ""
        };
        let ncx_item = if opts.with_toc {
            r#"<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>"#
        } else {
            ""
        };
        let spine_attrs = if opts.with_toc {
            r#"toc="ncx" progression="ltr""#
        } else {
            r#"progression="ltr""#
        };
        let opf = format!(
            r#"<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    {}
    {}
    <dc:identifier id="bookid">urn:uuid:1a2b3c4d-0000-4000-8000-000000000001</dc:identifier>
    <dc:language>zh-CN</dc:language>
    <meta name="generator" content="test"/>
  </metadata>
  <manifest>
    {}
    <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine {}>
    <itemref idref="ch1"/>
    <itemref idref="ch2"/>
  </spine>
</package>"#,
            title_xml, creator_xml, ncx_item, spine_attrs
        );
        writer.start_file("OEBPS/content.opf", stored).unwrap();
        writer.write_all(opf.as_bytes()).unwrap();

        // NCX 目录
        if opts.with_toc {
            let ncx = r#"<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head>
    <meta name="dtb:uid" content="urn:uuid:1a2b3c4d-0000-4000-8000-000000000001"/>
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
        }

        // 两个 XHTML 章节
        let ch1 = r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "xhtml11.dtd">
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>第一章</title></head>
<body><h1>第一章 开端</h1><p>正文内容一：风起于青萍之末。</p></body></html>"#;
        let ch2 = r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "xhtml11.dtd">
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>第二章</title></head>
<body><h1>第二章 结局</h1><p>正文内容二：一切归于平静。</p></body></html>"#;
        writer.start_file("OEBPS/chapter1.xhtml", stored).unwrap();
        writer.write_all(ch1.as_bytes()).unwrap();
        writer.start_file("OEBPS/chapter2.xhtml", stored).unwrap();
        writer.write_all(ch2.as_bytes()).unwrap();

        writer.finish().expect("写入 epub zip 失败");
        path
    }

    /// 构造一本「插图本」：每章引用**一张自己的图**，另有一批全书共享/无人引用的图。
    /// 用来验证章节产物只含本章引用到的图片，而不是把全书图片都塞进去。
    fn build_illustrated_epub(dir: &Path, file_name: &str, chapter_count: usize) -> PathBuf {
        let path = dir.join(file_name);
        let file = File::create(&path).expect("创建 epub 文件失败");
        let mut writer = zip::ZipWriter::new(file);
        let stored = FileOptions::default().compression_method(CompressionMethod::Stored);

        writer.start_file("mimetype", stored).unwrap();
        writer.write_all(b"application/epub+zip").unwrap();

        writer.start_file("META-INF/container.xml", stored).unwrap();
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

        let mut manifest = String::new();
        let mut spine = String::new();
        for i in 0..chapter_count {
            manifest.push_str(&format!(
                "    <item id=\"ch{i}\" href=\"text/ch{i}.xhtml\" media-type=\"application/xhtml+xml\"/>\n"
            ));
            spine.push_str(&format!("    <itemref idref=\"ch{i}\"/>\n"));
        }
        let opf = format!(
            r#"<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>插图书</dc:title>
    <dc:creator>测试作者</dc:creator>
    <dc:identifier id="bookid">urn:uuid:1a2b3c4d-0000-4000-8000-000000000009</dc:identifier>
    <dc:language>zh-CN</dc:language>
  </metadata>
  <manifest>
{manifest}  </manifest>
  <spine progression="ltr">
{spine}  </spine>
</package>"#
        );
        writer.start_file("OEBPS/content.opf", stored).unwrap();
        writer.write_all(opf.as_bytes()).unwrap();

        // 每章只引用 img/chN.png；img/unused.png 谁都不引用
        for i in 0..chapter_count {
            // 章节在 OEBPS/text/ 下，图片引用写相对路径 ../../ 形式的前缀变化，
            // 顺便验证按章节路径解析 src 的能力
            let xhtml = format!(
                r#"<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>第{i}章</title></head>
<body><h1>第{i}章</h1><p>正文{i}：插图如下。</p>
<img src="../img/ch{i}.png" alt="插图{i}"/>
</body></html>"#
            );
            writer
                .start_file(format!("OEBPS/text/ch{i}.xhtml"), stored)
                .unwrap();
            writer.write_all(xhtml.as_bytes()).unwrap();

            writer
                .start_file(format!("OEBPS/img/ch{i}.png"), stored)
                .unwrap();
            writer
                .write_all(format!("PNG-PAYLOAD-CH{i}").as_bytes())
                .unwrap();
        }
        writer.start_file("OEBPS/img/unused.png", stored).unwrap();
        writer.write_all(b"PNG-PAYLOAD-UNUSED").unwrap();

        writer.finish().expect("写入 epub zip 失败");
        path
    }

    /// 创建唯一临时目录
    fn make_temp_dir(tag: &str) -> PathBuf {
        // 先把进程 HOME 拉进隔离临时目录：get_chapter_content 会把 epub_css 缓存
        // 写到 get_app_data_dir() 下，若不隔离将污染（并永久残留于）真实用户目录
        crate::api::test_env::db_test_env();
        let dir = std::env::temp_dir().join(format!(
            "novel_reader_epub_{}_{}",
            tag,
            uuid::Uuid::new_v4()
        ));
        std::fs::create_dir_all(&dir).expect("创建临时目录失败");
        dir
    }

    /// 计算 get_chapter_content 写入的 epub_css 缓存目录（novel_id = 路径 md5）
    fn css_cache_dir(path: &std::path::Path) -> PathBuf {
        crate::api::get_app_data_dir()
            .join("epub_css")
            .join(format!("{:x}", md5::compute(path.to_string_lossy().as_bytes())))
    }

    /// 写入后归零：断言 CSS 缓存目录位于隔离 HOME 内，随后删除并确认不再残留
    fn delete_css_cache_and_assert_zero(path: &std::path::Path) {
        let css_dir = css_cache_dir(path);
        let home = crate::api::test_env::db_test_env().home.clone();
        assert!(
            css_dir.starts_with(&home),
            "缓存目录必须位于隔离 HOME 内: {css_dir:?}"
        );
        assert!(css_dir.exists(), "get_chapter_content 应创建 CSS 缓存目录");
        std::fs::remove_dir_all(&css_dir).expect("删除 CSS 缓存目录失败");
        assert!(!css_dir.exists(), "删除后不应残留任何缓存（写入即归零）");
    }

    #[test]
    fn test_parse_chapters_from_spine_and_toc() {
        // 标准 epub：应从 spine 得到 2 章，标题来自 NCX，内容为延迟加载（None）
        let dir = make_temp_dir("parse");
        let path = build_minimal_epub(&dir, "book.epub", &EpubBuildOptions::default());

        let content = EpubParser::parse(&path).expect("epub 解析应成功");
        assert_eq!(content.chapters.len(), 2, "应从 spine 解析出 2 章");
        assert_eq!(content.chapters[0].title, "第一章 开端");
        assert_eq!(content.chapters[1].title, "第二章 结局");
        assert_eq!(content.chapters[0].index, 0);
        assert_eq!(content.chapters[1].index, 1);
        // parse 不加载正文，内容延迟由 get_chapter_content 提供
        assert!(content.chapters[0].content.is_none(), "章节内容应延迟加载");
        assert!(content.chapters[0].id.contains("::res::ch1"));
        assert_eq!(content.novel_id.len(), 32, "novel_id 应为 md5 十六进制");

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn test_parse_without_toc_falls_back_to_resource_id() {
        // 无 NCX 目录时，章节标题应回退为 spine 的 resource id
        let dir = make_temp_dir("notoc");
        let opts = EpubBuildOptions {
            with_toc: false,
            ..EpubBuildOptions::default()
        };
        let path = build_minimal_epub(&dir, "notoc.epub", &opts);

        let content = EpubParser::parse(&path).expect("无 NCX 的 epub 也应能解析");
        assert_eq!(content.chapters.len(), 2);
        assert_eq!(content.chapters[0].title, "ch1", "无 toc 时标题回退为 idref");
        assert_eq!(content.chapters[1].title, "ch2");

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn test_get_chapter_content_valid_index() {
        // 正常索引：应返回包含正文的 HTML 内容
        let dir = make_temp_dir("content");
        let path = build_minimal_epub(&dir, "book.epub", &EpubBuildOptions::default());

        let c0 = EpubParser::get_chapter_content(&path, 0).expect("读取第 0 章应成功");
        assert!(
            c0.contains("正文内容一"),
            "第 0 章内容应含正文，实际: {}",
            c0.chars().take(200).collect::<String>()
        );

        let c1 = EpubParser::get_chapter_content(&path, 1).expect("读取第 1 章应成功");
        assert!(c1.contains("正文内容二"));

        // 写入后删除归零：清掉本用例产生的 CSS 缓存目录
        delete_css_cache_and_assert_zero(&path);

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn test_get_chapter_content_out_of_range() {
        // 越界索引：应返回错误（epub crate 对越界 set_current_chapter 返回 false，
        // get_current 返回 None），不应 panic
        let dir = make_temp_dir("oor");
        let path = build_minimal_epub(&dir, "book.epub", &EpubBuildOptions::default());

        let err = EpubParser::get_chapter_content(&path, 99).unwrap_err();
        assert!(
            err.to_string().contains("not found"),
            "越界应报 not found，实际: {}",
            err
        );

        // 越界路径仍会先行创建 CSS 缓存目录：同样删除归零
        delete_css_cache_and_assert_zero(&path);

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn test_extract_metadata_full() {
        // 完整元数据：title/creator 均存在
        let dir = make_temp_dir("meta");
        let path = build_minimal_epub(&dir, "book.epub", &EpubBuildOptions::default());

        let meta = EpubParser::extract_metadata(&path).expect("元数据提取应成功");
        assert_eq!(meta.title, "测试书籍");
        assert_eq!(meta.author.as_deref(), Some("测试作者"));
        assert_eq!(meta.format, crate::types::NovelFormat::Epub);
        assert_eq!(meta.file_size, std::fs::metadata(&path).unwrap().len());
        assert_eq!(meta.id.len(), 32);
        // 测试 epub 不含图片，封面应为 None
        assert!(meta.cover_path.is_none(), "无图片时不应有封面");

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn test_extract_metadata_missing_creator() {
        // 缺少 dc:creator：author 应为 None，其余字段正常
        let dir = make_temp_dir("nocreator");
        let opts = EpubBuildOptions {
            with_creator: false,
            ..EpubBuildOptions::default()
        };
        let path = build_minimal_epub(&dir, "nocreator.epub", &opts);

        let meta = EpubParser::extract_metadata(&path).expect("缺 creator 也应容错");
        assert_eq!(meta.title, "测试书籍");
        assert!(meta.author.is_none(), "缺 creator 时 author 应为 None");

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn test_extract_metadata_missing_title_falls_back_to_filename() {
        // 缺少 dc:title：标题应回退为文件名（去扩展名）
        let dir = make_temp_dir("notitle");
        let opts = EpubBuildOptions {
            title: None,
            ..EpubBuildOptions::default()
        };
        let path = build_minimal_epub(&dir, "回退书名.epub", &opts);

        let meta = EpubParser::extract_metadata(&path).expect("缺 title 也应容错");
        assert_eq!(meta.title, "回退书名", "标题应回退为文件 stem");
        assert_eq!(meta.author.as_deref(), Some("测试作者"));

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn test_inline_css_styles() {
        // CSS 类样式应被内联到对应 class 的标签上
        let html = r#"<p class="note">文本</p><div>无 class</div>"#;
        let css = ".note { text-indent: 2em; margin: 0 }";
        let out = EpubParser::inline_css_styles(html, css);
        assert!(out.contains("style=\"text-indent: 2em; margin: 0\""));
        assert!(out.contains("<div>无 class</div>"), "无 class 标签不受影响");

        // class 无对应规则时保持原样
        let out2 = EpubParser::inline_css_styles(r#"<p class="other">x</p>"#, css);
        assert_eq!(out2, r#"<p class="other">x</p>"#);
    }

    #[test]
    fn test_chapter_only_embeds_images_referenced_by_itself() {
        // P2-5：章节产物只应含本章 HTML 实际引用的图片
        let dir = make_temp_dir("onlyref");
        let path = build_illustrated_epub(&dir, "illus.epub", 3);

        let html = EpubParser::get_chapter_content(&path, 1).expect("读取第 1 章失败");

        // 本章引用的图被内嵌
        assert!(
            html.contains("data:image/png;base64,"),
            "本章图片应被内嵌: {}",
            html.chars().take(300).collect::<String>()
        );
        let expected = base64::Engine::encode(
            &base64::engine::general_purpose::STANDARD,
            b"PNG-PAYLOAD-CH1",
        );
        assert!(html.contains(&expected), "应内嵌本章自己的图片");

        // 其他章与无人引用的图绝不能被带进来
        for other in ["CH0", "CH2", "UNUSED"] {
            let b64 = base64::Engine::encode(
                &base64::engine::general_purpose::STANDARD,
                format!("PNG-PAYLOAD-{other}").as_bytes(),
            );
            assert!(
                !html.contains(&b64),
                "{other} 的图片不应出现在第 1 章产物中"
            );
        }

        // 正文仍在
        assert!(html.contains("正文1"), "正文不应丢失");

        delete_css_cache_and_assert_zero(&path);
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn test_image_cache_reuses_across_chapters_and_respects_budget() {
        // 跨章缓存：同一本书重复读章不应反复读 zip、反复 base64（需 mtime 参与缓存键）
        let dir = make_temp_dir("cache");
        let path = build_illustrated_epub(&dir, "illus.epub", 2);

        let key = epub_cache_key(&path);
        assert!(!cache_get(&key, "OEBPS/img/ch0.png").is_some());
        let _ = EpubParser::get_chapter_content(&path, 0).expect("读取第 0 章失败");
        let cached = cache_get(&key, "OEBPS/img/ch0.png");
        assert!(cached.is_some(), "读过的图片应进跨章缓存");
        assert!(cached.unwrap().starts_with("data:image/png;base64,"));

        // 预算上限：塞一张超预算的巨图必须被拒绝缓存
        let huge = "x".repeat(IMAGE_CACHE_BUDGET_BYTES + 1);
        cache_put(&key, "OEBPS/img/huge.png", huge);
        assert!(
            cache_get(&key, "OEBPS/img/huge.png").is_none(),
            "单张超预算的图不得进缓存"
        );

        delete_css_cache_and_assert_zero(&path);
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn test_resource_candidates_resolve_relative_to_chapter() {
        // 章节在 OEBPS/text/ch1.xhtml 引用 ../img/a.png → 应解析为 OEBPS/img/a.png
        let chapter = Path::new("OEBPS/text/ch1.xhtml");
        let candidates = resource_candidates(Some(chapter), "../img/a.png");
        assert_eq!(
            candidates.first().map(|s| s.as_str()),
            Some("OEBPS/img/a.png"),
            "首选候选必须按章节路径解析出的绝对条目名，got: {candidates:?}"
        );
        assert!(candidates.iter().any(|c| c == "img/a.png"), "裸 src 兜底");
        assert!(candidates.iter().any(|c| c == "a.png"), "文件名兜底");

        // 越过 epub 根的 ../ 不再产出绝对候选，只留兜底，避免拼出包外路径
        let escape = resource_candidates(Some(chapter), "../../../etc/passwd");
        assert!(
            !escape.iter().any(|c| c.starts_with("OEBPS/")),
            "越界相对路径不得拼出包内路径: {escape:?}"
        );
    }

    #[test]
    fn test_search_relevant_raw_html_has_no_base64_images() {
        // P2-5 第一步：搜索走 raw 路径，绝不触碰图片
        let dir = make_temp_dir("raw");
        let path = build_illustrated_epub(&dir, "illus.epub", 2);

        let raw = EpubParser::get_chapter_raw_html(&path, 0).expect("读取原始章节失败");
        assert!(raw.contains("正文0"), "原始章节应含正文");
        assert!(!raw.contains("data:image"), "raw 路径不得内嵌任何图片");

        // 对照：读内容路径会内嵌
        let with_img = EpubParser::get_chapter_content(&path, 0).expect("读取第 0 章失败");
        assert!(with_img.contains("data:image/png;base64,"));

        delete_css_cache_and_assert_zero(&path);
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn test_paired_tags_and_void_tag_strip_helpers() {
        // 说明：EPUB 里 <img> 保留（阅读器自行渲染），这里只确认 strip_html_tags
        // 不会误删图片标签——图片内嵌与文本抽取互不干扰。
        let html = r#"<div><p>正文</p><img src="../img/a.png"/></div>"#;
        let text = EpubParser::strip_html_tags(html);
        assert!(text.contains("<img"), "img 标签应保留供给搜索前的标签剥离");
    }

    #[test]
    fn test_parse_invalid_file_returns_error() {
        // 非 zip / 损坏文件：解析应返回错误而非 panic
        let dir = make_temp_dir("bad");
        let path = dir.join("broken.epub");
        std::fs::write(&path, "这不是一个合法的 epub/zip 文件").unwrap();

        assert!(EpubParser::parse(&path).is_err(), "损坏文件应报错");
        assert!(EpubParser::extract_metadata(&path).is_err());

        std::fs::remove_dir_all(&dir).ok();
    }
}
