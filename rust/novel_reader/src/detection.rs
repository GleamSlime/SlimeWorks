use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;
use std::path::Path;

use crate::api::{get_chapter_content, get_novel_content};

pub const NOVEL_GENRES: [&str; 17] = [
    "玄幻",
    "武侠",
    "仙侠",
    "都市",
    "科幻",
    "悬疑",
    "推理",
    "恐怖",
    "奇幻",
    "历史",
    "军事",
    "言情",
    "游戏",
    "竞技",
    "体育",
    "轻小说",
    "其他",
];

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NovelDetectionSample {
    pub chapter_index: usize,
    pub chapter_title: String,
    pub position: String,
    pub content: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NovelDetectionDocument {
    pub title: String,
    pub author: Option<String>,
    pub total_chapters: usize,
    pub sampled_chapters: usize,
    pub samples: Vec<NovelDetectionSample>,
}

pub(crate) fn sample_chapter_indexes(total: usize, limit: usize) -> Vec<usize> {
    if total == 0 || limit == 0 {
        return Vec::new();
    }
    let count = total.min(limit);
    let mut indexes = BTreeSet::new();
    indexes.insert(0);
    if count > 1 {
        indexes.insert(total - 1);
    }
    if count > 2 {
        for slot in 1..count - 1 {
            indexes.insert(slot * (total - 1) / (count - 1));
        }
    }
    indexes.into_iter().collect()
}

fn is_frontmatter_title(title: &str) -> bool {
    let normalized = title.trim().to_ascii_lowercase();
    const PREFIXES: [&str; 14] = [
        "cover",
        "封面",
        "扉页",
        "书名页",
        "版权页",
        "出版信息",
        "内容简介",
        "简介",
        "前言",
        "序言",
        "自序",
        "作者的话",
        "后记",
        "跋",
    ];
    normalized.contains("后记")
        || PREFIXES
            .iter()
            .any(|prefix| normalized == *prefix || normalized.starts_with(prefix))
}

fn is_meaningful_body_text(chapter_title: &str, text: &str) -> bool {
    let text = text.trim();
    if text
        .chars()
        .filter(|character| !character.is_whitespace())
        .count()
        < 40
    {
        return false;
    }
    let compact = |value: &str| {
        value
            .chars()
            .filter(|character| {
                !character.is_whitespace() && !matches!(character, '·' | '—' | '–' | '-')
            })
            .collect::<String>()
    };
    let title = compact(chapter_title);
    let body = compact(text);
    title.is_empty() || (body != title && body != title.repeat(2))
}

fn sample_detection_chapter_indexes<'a>(
    titles: impl IntoIterator<Item = &'a str>,
    limit: usize,
) -> Vec<usize> {
    let eligible = titles
        .into_iter()
        .enumerate()
        .filter_map(|(index, title)| (!is_frontmatter_title(title)).then_some(index))
        .collect::<Vec<_>>();
    sample_chapter_indexes(eligible.len(), limit)
        .into_iter()
        .map(|index| eligible[index])
        .collect()
}

pub(crate) fn excerpt_chars(text: &str, start: usize, max_chars: usize) -> String {
    let normalized = text.replace("\r\n", "\n").replace('\r', "\n");
    let chars: Vec<char> = normalized.chars().collect();
    if chars.is_empty() || max_chars == 0 {
        return String::new();
    }
    let start = start.min(chars.len().saturating_sub(1));
    let end = (start + max_chars).min(chars.len());
    chars[start..end].iter().collect()
}

pub(crate) fn select_excerpt(
    text: &str,
    ordinal: usize,
    max_chars: usize,
) -> (String, &'static str) {
    let char_count = text.chars().count();
    if char_count <= max_chars {
        return (excerpt_chars(text, 0, max_chars), "全文");
    }
    let starts = [
        0,
        char_count.saturating_sub(max_chars) / 2,
        char_count.saturating_sub(max_chars),
    ];
    let position = ["开头", "中部", "结尾"][ordinal % starts.len()];
    (
        excerpt_chars(text, starts[ordinal % starts.len()], max_chars),
        position,
    )
}

fn html_to_plain_text(html: &str) -> String {
    use regex::Regex;
    use std::sync::OnceLock;

    static STYLE_OR_SCRIPT: OnceLock<Regex> = OnceLock::new();
    static TAG_OR_COMMENT: OnceLock<Regex> = OnceLock::new();
    let without_blocks = STYLE_OR_SCRIPT
        .get_or_init(|| {
            Regex::new(r"(?is)<script\b[^>]*>.*?</script>|<style\b[^>]*>.*?</style>").unwrap()
        })
        .replace_all(html, " ");
    let without_tags = TAG_OR_COMMENT
        .get_or_init(|| Regex::new(r"(?s)<!--.*?-->|<[^>]+>").unwrap())
        .replace_all(&without_blocks, "\n");
    without_tags
        .replace("&nbsp;", " ")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&amp;", "&")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .collect::<Vec<_>>()
        .join("\n")
}

pub(crate) async fn sample_novel_for_detection_impl(
    file_path: String,
    title: String,
    author: Option<String>,
    max_sample_chars: usize,
    max_samples: usize,
) -> Result<NovelDetectionDocument, String> {
    let path = Path::new(&file_path);
    let ext = path
        .extension()
        .and_then(|value| value.to_str())
        .ok_or_else(|| "无法识别书籍格式".to_string())?
        .to_ascii_lowercase();
    if !matches!(ext.as_str(), "txt" | "epub") {
        return Err("仅支持 TXT 和 EPUB 书籍".to_string());
    }

    let max_sample_chars = max_sample_chars.clamp(400, 2400);
    let max_samples = max_samples.clamp(4, 64);
    let content = get_novel_content(file_path.clone())?;
    let indexes = sample_detection_chapter_indexes(
        content
            .chapters
            .iter()
            .map(|chapter| chapter.title.as_str()),
        max_samples,
    );
    let mut samples = Vec::with_capacity(indexes.len());
    let mut fallback_samples = Vec::with_capacity(indexes.len());

    for (ordinal, chapter_index) in indexes.into_iter().enumerate() {
        let chapter = content
            .chapters
            .get(chapter_index)
            .ok_or_else(|| format!("章节 {} 不存在", chapter_index))?;
        let chapter_text = match chapter.content.as_deref() {
            Some(text) => text.to_string(),
            None if ext == "epub" => {
                let html = crate::parser::EpubParser::get_chapter_raw_html(path, chapter.index)
                    .map_err(|error| error.to_string())?;
                html_to_plain_text(&html)
            }
            None => get_chapter_content(file_path.clone(), chapter_index)?,
        };
        if chapter_text.trim().is_empty() {
            continue;
        }
        let (excerpt, position) = select_excerpt(&chapter_text, ordinal, max_sample_chars);
        if excerpt.trim().is_empty() {
            continue;
        }
        let meaningful = is_meaningful_body_text(&chapter.title, &excerpt);
        let sample = NovelDetectionSample {
            chapter_index,
            chapter_title: chapter.title.clone(),
            position: position.to_string(),
            content: excerpt,
        };
        if meaningful {
            samples.push(sample);
        } else {
            fallback_samples.push(sample);
        }
    }

    if samples.is_empty() {
        samples = fallback_samples;
    }
    if samples.is_empty() {
        return Err("书籍没有可检测的正文".to_string());
    }

    Ok(NovelDetectionDocument {
        title,
        author,
        total_chapters: content.chapters.len(),
        sampled_chapters: samples.len(),
        samples,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stratified_samples_cover_both_ends() {
        assert_eq!(sample_chapter_indexes(10, 4), vec![0, 3, 6, 9]);
        assert_eq!(sample_chapter_indexes(2, 24), vec![0, 1]);
        assert_eq!(sample_chapter_indexes(1, 24), vec![0]);
        assert!(sample_chapter_indexes(0, 24).is_empty());
    }

    #[test]
    fn detection_sampling_skips_frontmatter_titles() {
        assert_eq!(
            sample_detection_chapter_indexes(
                ["cover.xhtml", "第一章 开端", "第二章 相遇", "日常的后记"].into_iter(),
                2,
            ),
            vec![1, 2]
        );
        assert!(is_frontmatter_title("封面"));
        assert!(is_frontmatter_title("作者的话"));
        assert!(!is_frontmatter_title("第一章 前言与开端"));
    }

    #[test]
    fn detection_sampling_rejects_title_only_text() {
        assert!(!is_meaningful_body_text("封面", "Cover"));
        assert!(!is_meaningful_body_text(
            "黄金时代（上）",
            "黄金时代（上）\n黄金时代（上）"
        ));
        assert!(is_meaningful_body_text("第一章", &"甲".repeat(80)));
    }

    #[test]
    fn excerpts_preserve_unicode_boundaries() {
        assert_eq!(excerpt_chars("甲乙丙丁", 1, 2), "乙丙");
        assert_eq!(excerpt_chars("甲乙丙丁", 99, 2), "丁");
        assert_eq!(excerpt_chars("", 0, 10), "");
    }

    #[test]
    fn epub_html_becomes_plain_bounded_text() {
        let text = html_to_plain_text(
            "<html><style>secret{color:red}</style><body><p>甲&amp;乙</p><script>bad()</script><p>丙</p></body></html>",
        );
        assert_eq!(text, "甲&乙\n丙");
    }

    #[test]
    fn long_chapter_uses_bounded_positions() {
        let text = "字".repeat(1000);
        assert_eq!(select_excerpt(&text, 0, 100).1, "开头");
        assert_eq!(select_excerpt(&text, 1, 100).1, "中部");
        assert_eq!(select_excerpt(&text, 2, 100).1, "结尾");
        assert_eq!(select_excerpt(&text, 0, 100).0.chars().count(), 100);
    }
}
