// 音乐播放器模块单元测试

use music_player::scanner;
use music_player::types::*;
use std::fs;
use std::path::Path;
use tempfile::TempDir;

// ── 辅助函数 ───────────────────────────────────────────────────────────────

/// 创建临时目录并写入测试音频文件
fn setup_test_audio_dir() -> TempDir {
    let dir = tempfile::Builder::new()
        .prefix("music_test_")
        .tempdir()
        .expect("创建临时目录失败");
    // 创建空音频文件（仅用于测试文件名解析，不包含实际音频数据）
    for name in &[
        "song1.mp3",
        "song2.flac",
        "song3.m4a",
        "readme.txt",
        "cover.jpg",
    ] {
        let path = dir.path().join(name);
        fs::write(&path, b"fake audio data").expect("写入测试文件失败");
    }
    dir
}

/// 创建 CUE 文件
fn setup_cue_file(dir: &Path, audio_name: &str) -> std::path::PathBuf {
    let cue_content = format!(
        r#"TITLE "测试专辑"
PERFORMER "测试艺术家"
FILE "{}" WAVE
  TRACK 01 AUDIO
    TITLE "第一首"
    PERFORMER "音轨艺术家"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "第二首"
    INDEX 01 03:30:00
"#,
        audio_name
    );
    let cue_path = dir.join(format!(
        "{}.cue",
        Path::new(audio_name).file_stem().unwrap().to_str().unwrap()
    ));
    fs::write(&cue_path, cue_content).expect("写入 CUE 文件失败");
    cue_path
}

// ── 数据结构测试 ───────────────────────────────────────────────────────────

#[test]
fn test_music_item_serialization() {
    let item = MusicItem {
        id: "test-id".to_string(),
        playlist_id: "playlist-1".to_string(),
        title: "测试歌曲".to_string(),
        artist: Some("测试艺术家".to_string()),
        album: Some("测试专辑".to_string()),
        file_path: "/music/test.mp3".to_string(),
        duration_ms: Some(180000),
        track_number: Some(1),
        disc_number: None,
        year: Some(2024),
        genre: Some("Pop".to_string()),
        cover_path: Some("/covers/test.jpg".to_string()),
        file_size: 5000000,
        modified_at: chrono::Utc::now(),
        order: 0,
        is_favorite: false,
        has_cue: false,
    };

    let json = serde_json::to_string(&item).expect("序列化失败");
    let deserialized: MusicItem = serde_json::from_str(&json).expect("反序列化失败");

    assert_eq!(deserialized.id, "test-id");
    assert_eq!(deserialized.title, "测试歌曲");
    assert_eq!(deserialized.artist, Some("测试艺术家".to_string()));
    assert_eq!(deserialized.duration_ms, Some(180000));
    assert_eq!(deserialized.year, Some(2024));
    assert!(!deserialized.is_favorite);
}

#[test]
fn test_playlist_serialization() {
    let playlist = Playlist {
        id: "pl-1".to_string(),
        name: "我的播放列表".to_string(),
        cover_path: None,
        item_count: 42,
        created_at: chrono::Utc::now(),
        updated_at: chrono::Utc::now(),
        is_default: false,
    };

    let json = serde_json::to_string(&playlist).expect("序列化失败");
    let deserialized: Playlist = serde_json::from_str(&json).expect("反序列化失败");

    assert_eq!(deserialized.id, "pl-1");
    assert_eq!(deserialized.name, "我的播放列表");
    assert_eq!(deserialized.item_count, 42);
    assert!(!deserialized.is_default);
}

#[test]
fn test_equalizer_preset_serialization() {
    let preset = EqualizerPreset {
        id: "eq-test".to_string(),
        name: "测试预设".to_string(),
        bands: vec![0.0; 10],
        is_builtin: true,
    };

    let json = serde_json::to_string(&preset).expect("序列化失败");
    let deserialized: EqualizerPreset = serde_json::from_str(&json).expect("反序列化失败");

    assert_eq!(deserialized.id, "eq-test");
    assert_eq!(deserialized.bands.len(), 10);
    assert!(deserialized.is_builtin);
}

#[test]
fn test_play_record_serialization() {
    let record = PlayRecord {
        id: "rec-1".to_string(),
        music_id: "music-1".to_string(),
        played_at: chrono::Utc::now(),
        play_count: 5,
    };

    let json = serde_json::to_string(&record).expect("序列化失败");
    let deserialized: PlayRecord = serde_json::from_str(&json).expect("反序列化失败");

    assert_eq!(deserialized.music_id, "music-1");
    assert_eq!(deserialized.play_count, 5);
}

// ── 扫描器测试 ─────────────────────────────────────────────────────────────

#[test]
fn test_is_audio_file() {
    assert!(scanner::is_audio_file(Path::new("test.mp3")));
    assert!(scanner::is_audio_file(Path::new("test.flac")));
    assert!(scanner::is_audio_file(Path::new("test.aac")));
    assert!(scanner::is_audio_file(Path::new("test.m4a")));
    assert!(scanner::is_audio_file(Path::new("test.ogg")));
    assert!(scanner::is_audio_file(Path::new("test.opus")));
    assert!(scanner::is_audio_file(Path::new("test.wav")));
    assert!(scanner::is_audio_file(Path::new("test.wma")));
    assert!(scanner::is_audio_file(Path::new("test.ape")));
    assert!(scanner::is_audio_file(Path::new("test.MP3"))); // 大写扩展名
    assert!(!scanner::is_audio_file(Path::new("test.txt")));
    assert!(!scanner::is_audio_file(Path::new("test.jpg")));
    assert!(!scanner::is_audio_file(Path::new("test.pdf")));
}

#[test]
fn test_scan_audio_files() {
    let dir = setup_test_audio_dir();
    let dir_path = dir.path().to_str().unwrap();
    let result = scanner::scan_audio_files(dir_path, "test-playlist");

    assert!(result.is_ok(), "扫描不应失败");
    let items = result.unwrap();
    // 应该只扫描到音频文件（mp3, flac, m4a），排除 txt 和 jpg
    let audio_count = items.len();
    assert!(
        audio_count >= 3,
        "应扫描到至少 3 个音频文件，实际扫描到 {} 个: {:?}",
        audio_count,
        items.iter().map(|i| i.title.clone()).collect::<Vec<_>>()
    );

    // 验证所有条目都属于指定播放列表
    for item in &items {
        assert_eq!(item.playlist_id, "test-playlist");
        assert!(!item.title.is_empty());
        assert!(!item.file_path.is_empty());
    }
}

#[test]
fn test_scan_empty_directory() {
    let dir = tempfile::tempdir().expect("创建临时目录失败");
    let result = scanner::scan_audio_files(dir.path().to_str().unwrap(), "test-playlist");

    assert!(result.is_ok());
    let items = result.unwrap();
    assert!(items.is_empty(), "空目录应返回空列表");
}

#[test]
fn test_scan_nonexistent_directory() {
    let result = scanner::scan_audio_files("/nonexistent/path/12345", "test-playlist");
    assert!(result.is_err(), "不存在的目录应返回错误");
}

// ── CUE 解析测试 ───────────────────────────────────────────────────────────

#[test]
fn test_parse_cue_file() {
    let dir = setup_test_audio_dir();
    let _cue_path = setup_cue_file(dir.path(), "song1.mp3");

    let result = scanner::parse_cue_file(dir.path().join("song1.cue").to_str().unwrap());

    assert!(result.is_ok(), "CUE 解析不应失败");
    let sheet = result.unwrap();

    assert_eq!(sheet.title, Some("测试专辑".to_string()));
    assert_eq!(sheet.performer, Some("测试艺术家".to_string()));
    assert_eq!(sheet.tracks.len(), 2);
    assert_eq!(sheet.tracks[0].title, "第一首");
    assert_eq!(sheet.tracks[0].performer, Some("音轨艺术家".to_string()));
    assert_eq!(sheet.tracks[1].title, "第二首");
}

#[test]
fn test_parse_cue_content() {
    let cue_content = r#"TITLE "CUE内容测试"
PERFORMER "内容艺术家"
FILE "audio.mp3" MP3
  TRACK 01 AUDIO
    TITLE "音轨一"
    PERFORMER "表演者一"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "音轨二"
    INDEX 01 05:00:00
"#;

    let result = scanner::parse_cue_content(cue_content);
    assert!(result.is_ok());
    let sheet = result.unwrap();

    assert_eq!(sheet.title, Some("CUE内容测试".to_string()));
    assert_eq!(sheet.tracks.len(), 2);
    assert_eq!(sheet.tracks[0].title, "音轨一");
    assert_eq!(sheet.tracks[1].title, "音轨二");
}

#[test]
fn test_parse_invalid_cue() {
    let result = scanner::parse_cue_content("这不是有效的CUE内容");
    // 无效内容不应 panic，可能返回空 CUE 或错误
    // 具体行为取决于实现，只要不 panic 即可
    let _ = result;
}

// ── 封面查找测试 ───────────────────────────────────────────────────────────

#[test]
fn test_find_cover_for_audio() {
    let dir = setup_test_audio_dir();
    let audio_path = dir.path().join("song1.mp3");

    let cover = scanner::find_cover_for_audio(&audio_path);
    assert!(cover.is_some(), "应找到 cover.jpg");
    let cover_path = cover.unwrap();
    assert!(cover_path.contains("cover.jpg") || cover_path.contains("cover"));
}

#[test]
fn test_find_cover_no_cover_file() {
    let dir = tempfile::tempdir().expect("创建临时目录失败");
    fs::write(dir.path().join("song.mp3"), b"fake").unwrap();
    let audio_path = dir.path().join("song.mp3");

    let cover = scanner::find_cover_for_audio(&audio_path);
    assert!(cover.is_none(), "无封面文件时应返回 None");
}

// ── CUE 文件查找测试 ───────────────────────────────────────────────────────

#[test]
fn test_find_cue_for_audio() {
    let dir = setup_test_audio_dir();
    let _cue_path = setup_cue_file(dir.path(), "song1.mp3");

    let cue = scanner::find_cue_for_audio(dir.path().join("song1.mp3").to_str().unwrap());
    assert!(cue.is_some(), "应找到 song1.cue");
}

#[test]
fn test_find_cue_no_cue_file() {
    let dir = tempfile::tempdir().expect("创建临时目录失败");
    fs::write(dir.path().join("song.mp3"), b"fake").unwrap();

    let cue = scanner::find_cue_for_audio(dir.path().join("song.mp3").to_str().unwrap());
    assert!(cue.is_none(), "无 CUE 文件时应返回 None");
}

// ── PlayMode 枚举测试 ──────────────────────────────────────────────────────

#[test]
fn test_play_mode_default() {
    let mode = PlayMode::default();
    assert_eq!(mode, PlayMode::Sequential);
}

#[test]
fn test_play_mode_variants() {
    let modes = [
        PlayMode::Sequential,
        PlayMode::Loop,
        PlayMode::SingleLoop,
        PlayMode::Shuffle,
    ];
    // 确保所有变体都可创建和比较
    assert_ne!(modes[0], modes[1]);
    assert_ne!(modes[1], modes[2]);
    assert_ne!(modes[2], modes[3]);
}
