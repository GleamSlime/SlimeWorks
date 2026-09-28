use std::path::{Path, PathBuf};

use crate::types::AsrSegment;

/// 毫秒 → SRT 时间戳 `HH:MM:SS,mmm`
pub fn format_srt_time(ms: u64) -> String {
    let hours = ms / 3_600_000;
    let minutes = (ms % 3_600_000) / 60_000;
    let seconds = (ms % 60_000) / 1000;
    let millis = ms % 1000;
    format!("{:02}:{:02}:{:02},{:03}", hours, minutes, seconds, millis)
}

/// 解析 SRT 时间戳 `HH:MM:SS,mmm`
///
/// 兼容三种常见写法：`,` 或 `.` 作毫秒分隔，以及 `00:01:02 --> 00:01:03,500` 中
/// 省略毫秒的左值
fn parse_srt_time(text: &str) -> Option<u64> {
    let text = text.trim().split_whitespace().next()?;
    let (hms, millis) = match text.split_once([',', '.']) {
        Some((hms, ms)) => (hms, ms),
        None => (text, "0"),
    };
    let mut it = hms.split(':');
    let hours: u64 = it.next()?.trim().parse().ok()?;
    let minutes: u64 = it.next()?.trim().parse().ok()?;
    let seconds: u64 = it.next()?.trim().parse().ok()?;
    // 毫秒位可能带空白或不足三位，取前三位数字
    let millis: u64 = millis
        .chars()
        .filter(|c| c.is_ascii_digit())
        .take(3)
        .collect::<String>()
        .parse()
        .unwrap_or(0);
    Some(((hours * 60 + minutes) * 60 + seconds) * 1000 + millis)
}

/// 解析 SRT 文本为片段列表
///
/// 只做"字幕翻译"流程需要的最小解析：序号可缺失、兼容 BOM/CRLF/`.` 毫秒分隔，
/// 同一条字幕的多行文本合并为一行（逐行送翻译更容易对齐，回写也不会撑破条目）。
/// 时间轴解析失败的条目直接丢弃，避免生成非法 SRT。
pub fn parse_srt(content: &str) -> Vec<AsrSegment> {
    let normalized = content.trim_start_matches('\u{feff}').replace("\r\n", "\n");
    let mut segments = Vec::new();

    for block in normalized.split("\n\n") {
        let lines: Vec<&str> = block
            .lines()
            .map(|l| l.trim())
            .filter(|l| !l.is_empty())
            .collect();
        let Some(idx) = lines.iter().position(|l| l.contains("-->")) else {
            continue;
        };
        let mut times = lines[idx].splitn(2, "-->");
        let (Some(start), Some(end)) = (
            times.next().and_then(parse_srt_time),
            times.next().and_then(parse_srt_time),
        ) else {
            continue;
        };
        let text = lines[idx + 1..].join(" ").trim().to_string();
        if text.is_empty() || end <= start {
            continue;
        }
        segments.push(AsrSegment {
            start_ms: start,
            end_ms: end,
            text,
        });
    }

    segments
}

/// 读取并解析磁盘上的 .srt 文件
pub fn read_srt(path: &str) -> Result<Vec<AsrSegment>, String> {
    let raw = std::fs::read_to_string(path).map_err(|e| format!("读取字幕文件失败: {}", e))?;
    let segments = parse_srt(&raw);
    if segments.is_empty() {
        return Err("字幕文件为空或不是标准 SRT 格式".to_string());
    }
    Ok(segments)
}

/// 生成 SRT 文本内容（标准编号 + 时间轴 + 文本，条目间空行分隔）
pub fn format_srt_content(segments: &[AsrSegment]) -> String {
    let mut out = String::new();
    for (i, seg) in segments.iter().enumerate() {
        out.push_str(&format!("{}\n", i + 1));
        out.push_str(&format!(
            "{} --> {}\n",
            format_srt_time(seg.start_ms),
            format_srt_time(seg.end_ms)
        ));
        out.push_str(&format!("{}\n\n", seg.text));
    }
    out
}

/// 把识别结果写成 .srt 文件
///
/// - 传入目录：文件名取媒体文件主名（同名会覆盖）
/// - 传入 .srt 结尾的文件路径：直接作为输出文件
pub fn write_srt(media_path: &str, segments: &[AsrSegment], out: &Path) -> Result<String, String> {
    let target: PathBuf = if out
        .extension()
        .map(|e| e.eq_ignore_ascii_case("srt"))
        .unwrap_or(false)
    {
        out.to_path_buf()
    } else {
        let stem = Path::new(media_path)
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("subtitle");
        out.join(format!("{}.srt", stem))
    };

    if let Some(parent) = target.parent() {
        std::fs::create_dir_all(parent).map_err(|e| format!("创建字幕目录失败: {}", e))?;
    }

    std::fs::write(&target, format_srt_content(segments))
        .map_err(|e| format!("写入字幕文件失败: {}", e))?;

    Ok(target.to_string_lossy().into_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_format_srt_time() {
        assert_eq!(format_srt_time(0), "00:00:00,000");
        assert_eq!(format_srt_time(3_723_456), "01:02:03,456");
    }

    #[test]
    fn test_format_srt_content() {
        let segs = vec![
            AsrSegment { start_ms: 0, end_ms: 1500, text: "你好".into() },
            AsrSegment { start_ms: 1500, end_ms: 3000, text: "world".into() },
        ];
        let content = format_srt_content(&segs);
        assert!(content.starts_with("1\n00:00:00,000 --> 00:00:01,500\n你好\n\n2\n"));
        assert!(content.ends_with("00:00:01,500 --> 00:00:03,000\nworld\n\n"));
    }

    #[test]
    fn test_parse_srt_roundtrip() {
        let segs = vec![
            AsrSegment { start_ms: 806, end_ms: 3692, text: "조금만 생각을 하면서 살면".into() },
            AsrSegment { start_ms: 3723, end_ms: 6100, text: " 훨씬 편할 거야".into() },
        ];
        let parsed = parse_srt(&format_srt_content(&segs));
        assert_eq!(parsed.len(), 2);
        assert_eq!(parsed[0].start_ms, 806);
        assert_eq!(parsed[1].end_ms, 6100);
        assert_eq!(parsed[0].text, "조금만 생각을 하면서 살면");
    }

    #[test]
    fn test_parse_srt_tolerates_real_world_variants() {
        // BOM + CRLF + 缺序号 + `.` 毫秒 + 单行时间轴省略毫秒 + 条目内多行 + 脏数据
        let raw = "\u{feff}1\r\n00:00:01,000 --> 00:00:02,500\r\n第一句\r\n第二句\r\n\r\n\
                   00:03:00 --> 00:03:04.250\r\n换行前的第二条\r\n\r\n\
                   垃圾条目没有时间轴\r\n\r\n\
                   3\r\n00:00:05,000 --> 00:00:05,000\r\n时间轴倒挂应丢弃\r\n";
        let parsed = parse_srt(raw);
        assert_eq!(parsed.len(), 2);
        assert_eq!(parsed[0].text, "第一句 第二句");
        assert_eq!(parsed[0].start_ms, 1000);
        assert_eq!(parsed[1].start_ms, 180_000);
        assert_eq!(parsed[1].end_ms, 184_250);
    }
}
