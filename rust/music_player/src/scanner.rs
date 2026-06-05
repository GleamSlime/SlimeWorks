use anyhow::Result;
use regex::Regex;
use slime_logger::{sw_debug, sw_info, sw_warn};
use std::path::Path;
use walkdir::{DirEntry, WalkDir};

use crate::types::{CueSheet, CueTrack, MusicItem};

/// 支持的音频文件扩展名
const AUDIO_EXTENSIONS: &[&str] = &[
    "mp3", "flac", "aac", "m4a", "ogg", "opus", "wav", "wma", "ape", "aiff", "alac", "wv", "tta",
    "dsd", "dsf", "dff",
];

/// 判断是否为音频文件
pub fn is_audio_file(path: &Path) -> bool {
    path.extension()
        .and_then(|e| e.to_str())
        .map(|e| AUDIO_EXTENSIONS.contains(&e.to_ascii_lowercase().as_str()))
        .unwrap_or(false)
}

/// 判断是否为 CUE 文件
pub fn is_cue_file(path: &Path) -> bool {
    path.extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_ascii_lowercase() == "cue")
        .unwrap_or(false)
}

fn is_hidden_entry(entry: &DirEntry) -> bool {
    entry
        .path()
        .components()
        .any(|c| matches!(c, std::path::Component::Normal(name) if name.to_str().map_or(false, |n| n.starts_with('.'))))
}

/// 扫描目录中的音频文件，返回 MusicItem 列表
pub fn scan_audio_files(dir_path: &str, playlist_id: &str) -> Result<Vec<MusicItem>> {
    let path = Path::new(dir_path);
    if !path.exists() || !path.is_dir() {
        return Err(anyhow::anyhow!("目录不存在或不是有效目录: {}", dir_path));
    }

    sw_info!("[music_scanner] 开始扫描音频目录: {}", dir_path);
    let mut items = Vec::new();
    let mut order = 0;

    for entry in WalkDir::new(path)
        .into_iter()
        .filter_entry(|e| !is_hidden_entry(e))
        .filter_map(|e| e.ok())
    {
        if !entry.file_type().is_file() {
            continue;
        }
        let file_path = entry.path();
        if !is_audio_file(file_path) {
            continue;
        }

        let metadata = match std::fs::metadata(file_path) {
            Ok(m) => m,
            Err(e) => {
                sw_warn!(
                    "[music_scanner] 无法读取文件元数据: {:?}, err={}",
                    file_path,
                    e
                );
                continue;
            }
        };

        let title = file_path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("未命名")
            .to_string();

        let modified_at = metadata
            .modified()
            .ok()
            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
            .map(|d| chrono::DateTime::from_timestamp(d.as_secs() as i64, 0).unwrap_or_default())
            .unwrap_or_default();

        let file_path_str = file_path.to_string_lossy().to_string();

        // 尝试从同级目录查找 .cue 文件
        let _cue_path = find_cue_for_audio(&file_path_str);

        // 尝试提取封面（同目录下的 cover.jpg / folder.jpg 等）
        let cover_path = find_cover_for_audio(file_path);

        let item = MusicItem {
            id: uuid::Uuid::new_v4().to_string(),
            playlist_id: playlist_id.to_string(),
            title,
            artist: None,
            album: None,
            file_path: file_path_str,
            duration_ms: None,
            track_number: None,
            disc_number: None,
            year: None,
            genre: None,
            cover_path,
            file_size: metadata.len(),
            modified_at,
            order,
            is_favorite: false,
        };
        order += 1;
        items.push(item);
    }

    sw_info!(
        "[music_scanner] 扫描完成，共发现 {} 个音频文件",
        items.len()
    );
    Ok(items)
}

/// 查找音频文件对应的 .cue 文件
fn find_cue_for_audio(audio_path: &str) -> Option<String> {
    let audio = Path::new(audio_path);
    let dir = audio.parent()?;
    let stem = audio.file_stem()?.to_str()?;

    for cue_name in &[format!("{}.cue", stem), format!("{}.CUE", stem)] {
        let cue_path = dir.join(cue_name);
        if cue_path.exists() {
            return Some(cue_path.to_string_lossy().to_string());
        }
    }
    None
}

/// 查找音频文件所在目录的封面图片
pub fn find_cover_for_audio(audio_path: &Path) -> Option<String> {
    let dir = audio_path.parent()?;
    let cover_names = &[
        "cover.jpg",
        "cover.jpeg",
        "cover.png",
        "folder.jpg",
        "folder.jpeg",
        "folder.png",
        "front.jpg",
        "front.jpeg",
        "front.png",
        "album.jpg",
        "album.jpeg",
        "album.png",
    ];
    for name in cover_names {
        let cover_path = dir.join(name);
        if cover_path.exists() {
            return Some(cover_path.to_string_lossy().to_string());
        }
    }
    None
}

/// 解析 .cue 文件内容，返回 CueSheet
pub fn parse_cue_file(cue_path: &str) -> Result<CueSheet> {
    let content = std::fs::read_to_string(cue_path)
        .map_err(|e| anyhow::anyhow!("读取 CUE 文件失败: {}", e))?;
    parse_cue_content(&content)
}

/// 解析 CUE 文件内容
pub fn parse_cue_content(content: &str) -> Result<CueSheet> {
    let mut title: Option<String> = None;
    let mut performer: Option<String> = None;
    let mut audio_file: Option<String> = None;
    let mut tracks: Vec<CueTrack> = Vec::new();

    // 当前音轨的临时字段
    let mut cur_title: Option<String> = None;
    let mut cur_performer: Option<String> = None;
    let mut cur_number: u32 = 0;
    let mut cur_start_ms: u64 = 0;

    let title_re = Regex::new(r#"^TITLE\s+"(.*)""#)?;
    let performer_re = Regex::new(r#"^PERFORMER\s+"(.*)""#)?;
    let file_re = Regex::new(r#"^FILE\s+"(.*)"\s+WAVE"#)?;
    let track_re = Regex::new(r#"^TRACK\s+(\d+)\s+AUDIO"#)?;
    let index_re = Regex::new(r#"^INDEX\s+01\s+(\d+):(\d+):(\d+)"#)?;

    for line in content.lines() {
        let line = line.trim();

        if let Some(caps) = track_re.captures(line) {
            // 保存前一个音轨
            if cur_number > 0 {
                tracks.push(CueTrack {
                    title: cur_title.take().unwrap_or_default(),
                    performer: cur_performer.take(),
                    start_ms: cur_start_ms,
                    end_ms: None,
                    track_number: cur_number,
                });
            }
            cur_number = caps[1].parse().unwrap_or(0);
            cur_title = None;
            cur_performer = None;
            cur_start_ms = 0;
        } else if cur_number == 0 {
            // 全局字段
            if let Some(caps) = title_re.captures(line) {
                title = Some(caps[1].to_string());
            } else if let Some(caps) = performer_re.captures(line) {
                performer = Some(caps[1].to_string());
            } else if let Some(caps) = file_re.captures(line) {
                audio_file = Some(caps[1].to_string());
            }
        } else {
            // 音轨内字段
            if let Some(caps) = title_re.captures(line) {
                cur_title = Some(caps[1].to_string());
            } else if let Some(caps) = performer_re.captures(line) {
                cur_performer = Some(caps[1].to_string());
            } else if let Some(caps) = index_re.captures(line) {
                let min: u64 = caps[1].parse().unwrap_or(0);
                let sec: u64 = caps[2].parse().unwrap_or(0);
                let frames: u64 = caps[3].parse().unwrap_or(0);
                cur_start_ms = (min * 60 + sec) * 1000 + frames * 1000 / 75;
            }
        }
    }

    // 保存最后一个音轨
    if cur_number > 0 {
        tracks.push(CueTrack {
            title: cur_title.unwrap_or_default(),
            performer: cur_performer,
            start_ms: cur_start_ms,
            end_ms: None,
            track_number: cur_number,
        });
    }

    // 填充每个音轨的 end_ms（下一个音轨的 start_ms）
    for i in 0..tracks.len().saturating_sub(1) {
        tracks[i].end_ms = Some(tracks[i + 1].start_ms);
    }

    sw_debug!(
        "[cue_parser] 解析完成: {} 个音轨, 音频文件={:?}",
        tracks.len(),
        audio_file
    );

    Ok(CueSheet {
        title,
        performer,
        audio_file: audio_file.unwrap_or_default(),
        tracks,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_cue_content() {
        let cue = r#"
            TITLE "测试专辑"
            PERFORMER "测试艺术家"
            FILE "audio.flac" WAVE
              TRACK 01 AUDIO
                TITLE "第一首"
                PERFORMER "歌手A"
                INDEX 01 00:00:00
              TRACK 02 AUDIO
                TITLE "第二首"
                INDEX 01 03:25:40
              TRACK 03 AUDIO
                TITLE "第三首"
                INDEX 01 07:10:20
        "#;
        let sheet = parse_cue_content(cue).unwrap();
        assert_eq!(sheet.title, Some("测试专辑".to_string()));
        assert_eq!(sheet.performer, Some("测试艺术家".to_string()));
        assert_eq!(sheet.audio_file, "audio.flac");
        assert_eq!(sheet.tracks.len(), 3);
        assert_eq!(sheet.tracks[0].title, "第一首");
        assert_eq!(sheet.tracks[0].start_ms, 0);
        assert_eq!(sheet.tracks[1].start_ms, 205400); // 3*60*1000 + 25*1000 + 40*1000/75
        assert_eq!(sheet.tracks[0].end_ms, Some(205400));
        assert_eq!(sheet.tracks[2].end_ms, None);
    }

    #[test]
    fn test_is_audio_file() {
        assert!(is_audio_file(Path::new("test.mp3")));
        assert!(is_audio_file(Path::new("test.FLAC")));
        assert!(!is_audio_file(Path::new("test.txt")));
        assert!(!is_audio_file(Path::new("test.mp4")));
    }

    #[test]
    fn test_is_cue_file() {
        assert!(is_cue_file(Path::new("test.cue")));
        assert!(is_cue_file(Path::new("test.CUE")));
        assert!(!is_cue_file(Path::new("test.mp3")));
    }
}
