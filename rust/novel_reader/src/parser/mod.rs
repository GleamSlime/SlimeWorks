mod parser_epub;
mod parser_txt;

pub use parser_epub::EpubParser;
pub use parser_txt::TxtParser;

use anyhow::Result;
use std::path::Path;

use crate::types::{NovelContent, NovelFormat, NovelMetadata};

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
        // strip_html_tags preserves p/b/div/span/img/br/hr/h1-h6/style tags
        let html = "<html><body><p>Hello <b>World</b>!</p></body></html>";
        let text = EpubParser::strip_html_tags(html);
        assert_eq!(text, "<p>Hello <b>World</b>!</p>");

        // Unknown tags like <nav> get stripped
        let html2 = "<nav>Menu</nav><p>Content</p>";
        let text2 = EpubParser::strip_html_tags(html2);
        assert_eq!(text2, "Menu<p>Content</p>");
    }
}
