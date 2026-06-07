use chrono::Utc;
use slime_logger::{sw_info, sw_warn};
use std::sync::{Arc, Mutex, OnceLock};

use crate::scanner;
use crate::types::{CueSheet, EqualizerPreset, MusicItem, PlayRecord, Playlist};

// ── 内存缓存 ──────────────────────────────────────────────────────────────────
static PLAYLISTS: OnceLock<Arc<Mutex<Vec<Playlist>>>> = OnceLock::new();
static MUSIC_ITEMS: OnceLock<Mutex<Option<Vec<MusicItem>>>> = OnceLock::new();
static PLAY_RECORDS: OnceLock<Arc<Mutex<Vec<PlayRecord>>>> = OnceLock::new();
static EQ_PRESETS: OnceLock<Arc<Mutex<Vec<EqualizerPreset>>>> = OnceLock::new();
static DB_INIT_RESULT: OnceLock<Option<String>> = OnceLock::new();

fn playlists_cache() -> &'static Arc<Mutex<Vec<Playlist>>> {
    PLAYLISTS.get_or_init(|| Arc::new(Mutex::new(Vec::new())))
}

fn music_items_cache() -> &'static Mutex<Option<Vec<MusicItem>>> {
    MUSIC_ITEMS.get_or_init(|| Mutex::new(None))
}

fn play_records_cache() -> &'static Arc<Mutex<Vec<PlayRecord>>> {
    PLAY_RECORDS.get_or_init(|| Arc::new(Mutex::new(Vec::new())))
}

fn eq_presets_cache() -> &'static Arc<Mutex<Vec<EqualizerPreset>>> {
    EQ_PRESETS.get_or_init(|| Arc::new(Mutex::new(Vec::new())))
}

// ── 数据库路径 ────────────────────────────────────────────────────────────────
fn app_data_base() -> String {
    #[cfg(windows)]
    return std::env::var("APPDATA").unwrap_or_else(|_| ".".to_string());
    #[cfg(target_os = "macos")]
    return {
        let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
        format!("{}/Library/Application Support", home)
    };
    #[cfg(not(any(windows, target_os = "macos")))]
    return std::env::var("XDG_DATA_HOME").unwrap_or_else(|_| {
        let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
        format!("{}/.local/share", home)
    });
}

fn default_db_path() -> String {
    let dir = std::path::Path::new(&app_data_base()).join("SlimeWorks");
    let _ = std::fs::create_dir_all(&dir);
    dir.join("music_player.db").to_string_lossy().into_owned()
}

fn playlist_table() -> String {
    "music_playlists".to_string()
}

fn item_table() -> String {
    "music_items".to_string()
}

fn record_table() -> String {
    "music_play_records".to_string()
}

fn eq_preset_table() -> String {
    "music_eq_presets".to_string()
}

// ── 辅助：从 db_list_all 提取 JSON 值列表 ────────────────────────────────────
fn db_list_values(table: String) -> Result<Vec<String>, String> {
    let records = db_module::db_list_all(table).map_err(|e| e.to_string())?;
    Ok(records.into_iter().map(|r| r.value).collect())
}

fn db_list_key_values(table: String) -> Result<Vec<(String, String)>, String> {
    let records = db_module::db_list_all(table).map_err(|e| e.to_string())?;
    Ok(records.into_iter().map(|r| (r.key, r.value)).collect())
}

// ── 初始化 ────────────────────────────────────────────────────────────────────
pub fn initialize_db() -> Result<(), String> {
    let result = DB_INIT_RESULT.get_or_init(|| {
        let path = default_db_path();
        sw_info!("[music_db] 初始化数据库: {}", path);
        match db_module::db_init(path) {
            Ok(_) => {
                sw_info!("[music_db] 数据库初始化成功，注册表...");
                // 注册所有表
                for table in &[
                    playlist_table(),
                    item_table(),
                    record_table(),
                    eq_preset_table(),
                ] {
                    if let Err(e) = db_module::db_register_table(table.clone()) {
                        sw_warn!("[music_db] 注册表 {} 失败: {}", table, e);
                    } else {
                        sw_info!("[music_db] 注册表 {} 成功", table);
                    }
                }
                None
            }
            Err(e) => {
                sw_warn!("[music_db] 数据库初始化失败: {}", e);
                Some(e)
            }
        }
    });
    match result {
        None => Ok(()),
        Some(e) => Err(e.clone()),
    }
}

fn ensure_db() {
    let _ = initialize_db();
    // 确保表已注册（即使 db_init 成功但注册表失败也能恢复）
    for table in &[
        playlist_table(),
        item_table(),
        record_table(),
        eq_preset_table(),
    ] {
        let _ = db_module::db_register_table(table.clone());
    }
}

// ── 播放列表 CRUD ─────────────────────────────────────────────────────────────
pub fn get_all_playlists() -> Result<Vec<Playlist>, String> {
    ensure_db();
    let cache = playlists_cache();
    {
        let guard = cache.lock().unwrap();
        if !guard.is_empty() {
            return Ok(guard.clone());
        }
    }

    let _ = db_module::db_register_table(playlist_table());
    let raw = db_list_values(playlist_table())?;
    let mut playlists: Vec<Playlist> = raw
        .into_iter()
        .filter_map(|v| serde_json::from_str::<Playlist>(&v).ok())
        .collect();
    playlists.sort_by(|a, b| a.name.cmp(&b.name));

    let mut guard = cache.lock().unwrap();
    *guard = playlists.clone();
    Ok(playlists)
}

pub fn create_playlist(name: String) -> Result<Playlist, String> {
    ensure_db();
    let _ = db_module::db_register_table(playlist_table());

    let playlist = Playlist {
        id: uuid::Uuid::new_v4().to_string(),
        name,
        cover_path: None,
        item_count: 0,
        created_at: Utc::now(),
        updated_at: Utc::now(),
        is_default: false,
    };

    let json = serde_json::to_string(&playlist).map_err(|e| e.to_string())?;
    db_module::db_set(playlist_table(), playlist.id.clone(), json).map_err(|e| e.to_string())?;

    let mut guard = playlists_cache().lock().unwrap();
    guard.push(playlist.clone());
    Ok(playlist)
}

/// 创建默认播放列表（如果不存在）
pub fn ensure_default_playlist() -> Result<Playlist, String> {
    let playlists = get_all_playlists()?;
    if let Some(default) = playlists.into_iter().find(|p| p.is_default) {
        return Ok(default);
    }
    let mut playlist = create_playlist("默认列表".to_string())?;
    playlist.is_default = true;
    let json = serde_json::to_string(&playlist).map_err(|e| e.to_string())?;
    db_module::db_set(playlist_table(), playlist.id.clone(), json).map_err(|e| e.to_string())?;

    let mut guard = playlists_cache().lock().unwrap();
    if let Some(p) = guard.iter_mut().find(|p| p.id == playlist.id) {
        p.is_default = true;
    }
    Ok(playlist)
}

pub fn rename_playlist(playlist_id: String, name: String) -> Result<bool, String> {
    ensure_db();
    let _ = db_module::db_register_table(playlist_table());

    let raw =
        db_module::db_get(playlist_table(), playlist_id.clone()).map_err(|e| e.to_string())?;
    let value = raw.ok_or("播放列表不存在")?;
    let mut playlist: Playlist = serde_json::from_str(&value).map_err(|e| e.to_string())?;
    playlist.name = name;
    playlist.updated_at = Utc::now();

    let json = serde_json::to_string(&playlist).map_err(|e| e.to_string())?;
    db_module::db_set(playlist_table(), playlist_id.clone(), json).map_err(|e| e.to_string())?;

    let mut guard = playlists_cache().lock().unwrap();
    if let Some(p) = guard.iter_mut().find(|p| p.id == playlist_id) {
        p.name = playlist.name;
        p.updated_at = playlist.updated_at;
    }
    Ok(true)
}

pub fn delete_playlist(playlist_id: String) -> Result<bool, String> {
    ensure_db();
    // 同时删除列表内的音乐条目
    let items = get_playlist_items(playlist_id.clone())?;
    for item in items {
        let _ = db_module::db_delete(item_table(), item.id);
    }
    // 清空音乐缓存
    {
        let mut guard = music_items_cache().lock().unwrap();
        *guard = None;
    }

    db_module::db_delete(playlist_table(), playlist_id.clone()).map_err(|e| e.to_string())?;

    let mut guard = playlists_cache().lock().unwrap();
    guard.retain(|p| p.id != playlist_id);
    Ok(true)
}

// ── 音乐条目 CRUD ─────────────────────────────────────────────────────────────
pub fn get_playlist_items(playlist_id: String) -> Result<Vec<MusicItem>, String> {
    ensure_db();
    let _ = db_module::db_register_table(item_table());

    let raw = db_list_values(item_table())?;
    let mut items: Vec<MusicItem> = raw
        .into_iter()
        .filter_map(|v| serde_json::from_str::<MusicItem>(&v).ok())
        .filter(|i| i.playlist_id == playlist_id)
        .collect();
    items.sort_by_key(|i| i.order);

    Ok(items)
}

pub fn get_all_music_items() -> Result<Vec<MusicItem>, String> {
    ensure_db();
    {
        let guard = music_items_cache().lock().unwrap();
        if let Some(ref items) = *guard {
            return Ok(items.clone());
        }
    }

    let _ = db_module::db_register_table(item_table());
    let raw = db_list_values(item_table())?;
    let items: Vec<MusicItem> = raw
        .into_iter()
        .filter_map(|v| serde_json::from_str::<MusicItem>(&v).ok())
        .collect();

    let mut guard = music_items_cache().lock().unwrap();
    *guard = Some(items.clone());
    Ok(items)
}

/// 导入音乐文件夹到指定播放列表
pub fn import_music_folder(
    playlist_id: String,
    folder_path: String,
) -> Result<Vec<MusicItem>, String> {
    let mut items =
        scanner::scan_audio_files(&folder_path, &playlist_id).map_err(|e| e.to_string())?;

    // 检查同目录下的 .cue 文件并合并信息
    let cue_sheets = scan_cue_files(&folder_path);
    for item in items.iter_mut() {
        // 尝试匹配 CUE 文件
        if let Some(cue) = find_cue_for_item(&item.file_path, &cue_sheets) {
            if let Some(track) = cue.tracks.first() {
                if !track.title.is_empty() {
                    item.title = track.title.clone();
                }
                item.artist = track.performer.clone().or(item.artist.clone());
            }
            item.album = cue.title.clone().or(item.album.clone());
            if cue.performer.is_some() && item.artist.is_none() {
                item.artist = cue.performer.clone();
            }
        }
    }

    // 保存到数据库
    let _ = db_module::db_register_table(item_table());
    for item in &items {
        let json = serde_json::to_string(item).map_err(|e| e.to_string())?;
        db_module::db_set(item_table(), item.id.clone(), json).map_err(|e| e.to_string())?;
    }

    // 更新播放列表的 item_count
    update_playlist_count(&playlist_id)?;

    // 清空缓存
    {
        let mut guard = music_items_cache().lock().unwrap();
        *guard = None;
    }

    sw_info!(
        "[music_player] 导入 {} 首音乐到播放列表 {}",
        items.len(),
        playlist_id
    );
    Ok(items)
}

/// 导入单个音乐文件到播放列表
pub fn import_music_file(playlist_id: String, file_path: String) -> Result<MusicItem, String> {
    let path = std::path::Path::new(&file_path);
    if !path.exists() {
        return Err("文件不存在".to_string());
    }
    if !scanner::is_audio_file(path) {
        return Err("不是支持的音频文件".to_string());
    }

    let metadata = std::fs::metadata(&file_path).map_err(|e| e.to_string())?;
    let title = path
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("未命名")
        .to_string();

    let cover_path = scanner::find_cover_for_audio(path);

    // 获取当前最大 order
    let existing = get_playlist_items(playlist_id.clone()).unwrap_or_default();
    let max_order = existing.iter().map(|i| i.order).max().unwrap_or(-1);

    let item = MusicItem {
        id: uuid::Uuid::new_v4().to_string(),
        playlist_id: playlist_id.clone(),
        title,
        artist: None,
        album: None,
        file_path,
        duration_ms: None,
        track_number: None,
        disc_number: None,
        year: None,
        genre: None,
        cover_path,
        file_size: metadata.len(),
        modified_at: Utc::now(),
        order: max_order + 1,
        is_favorite: false,
    };

    let _ = db_module::db_register_table(item_table());
    let json = serde_json::to_string(&item).map_err(|e| e.to_string())?;
    db_module::db_set(item_table(), item.id.clone(), json).map_err(|e| e.to_string())?;

    update_playlist_count(&playlist_id)?;

    // 清空缓存
    {
        let mut guard = music_items_cache().lock().unwrap();
        *guard = None;
    }

    Ok(item)
}

/// 批量导入音乐文件路径
pub fn import_music_paths(
    playlist_id: String,
    paths: Vec<String>,
) -> Result<Vec<MusicItem>, String> {
    let mut items = Vec::new();
    for path in paths {
        let p = std::path::Path::new(&path);
        if p.is_dir() {
            let dir_items = import_music_folder(playlist_id.clone(), path)?;
            items.extend(dir_items);
        } else if p.is_file() && scanner::is_audio_file(p) {
            match import_music_file(playlist_id.clone(), path) {
                Ok(item) => items.push(item),
                Err(e) => sw_warn!("[music_player] 导入文件失败: {}", e),
            }
        }
    }
    Ok(items)
}

pub fn delete_music_item(item_id: String) -> Result<bool, String> {
    ensure_db();
    db_module::db_delete(item_table(), item_id).map_err(|e| e.to_string())?;

    // 清空缓存
    {
        let mut guard = music_items_cache().lock().unwrap();
        *guard = None;
    }
    Ok(true)
}

/// 删除播放列表内所有音乐条目（不删除物理文件）
pub fn clear_playlist_items(playlist_id: String) -> Result<u32, String> {
    let items = get_playlist_items(playlist_id.clone())?;
    let count = items.len() as u32;
    for item in items {
        let _ = db_module::db_delete(item_table(), item.id);
    }
    update_playlist_count(&playlist_id)?;

    // 清空缓存
    {
        let mut guard = music_items_cache().lock().unwrap();
        *guard = None;
    }
    Ok(count)
}

/// 更新音乐条目信息
pub fn update_music_item(
    item_id: String,
    title: Option<String>,
    artist: Option<String>,
    album: Option<String>,
    is_favorite: Option<bool>,
) -> Result<bool, String> {
    ensure_db();
    let _ = db_module::db_register_table(item_table());

    let raw = db_module::db_get(item_table(), item_id.clone()).map_err(|e| e.to_string())?;
    let value = raw.ok_or("音乐条目不存在")?;
    let mut item: MusicItem = serde_json::from_str(&value).map_err(|e| e.to_string())?;

    if let Some(t) = title {
        item.title = t;
    }
    if let Some(a) = artist {
        item.artist = Some(a);
    }
    if let Some(a) = album {
        item.album = Some(a);
    }
    if let Some(f) = is_favorite {
        item.is_favorite = f;
    }

    let json = serde_json::to_string(&item).map_err(|e| e.to_string())?;
    db_module::db_set(item_table(), item_id, json).map_err(|e| e.to_string())?;

    // 清空缓存
    {
        let mut guard = music_items_cache().lock().unwrap();
        *guard = None;
    }
    Ok(true)
}

/// 保存播放列表排序
pub fn save_playlist_order(_playlist_id: String, item_ids: Vec<String>) -> Result<(), String> {
    ensure_db();
    let _ = db_module::db_register_table(item_table());

    for (order, id) in item_ids.iter().enumerate() {
        let raw = db_module::db_get(item_table(), id.clone()).map_err(|e| e.to_string())?;
        if let Some(value) = raw {
            let mut item: MusicItem = serde_json::from_str(&value).map_err(|e| e.to_string())?;
            item.order = order as i32;
            let json = serde_json::to_string(&item).map_err(|e| e.to_string())?;
            db_module::db_set(item_table(), id.clone(), json).map_err(|e| e.to_string())?;
        }
    }

    // 清空缓存
    {
        let mut guard = music_items_cache().lock().unwrap();
        *guard = None;
    }
    Ok(())
}

// ── CUE 文件解析 ──────────────────────────────────────────────────────────────
/// 扫描目录中的 .cue 文件并解析
pub fn scan_cue_files(dir_path: &str) -> Vec<CueSheet> {
    let path = std::path::Path::new(dir_path);
    if !path.exists() || !path.is_dir() {
        return Vec::new();
    }

    let mut sheets = Vec::new();
    if let Ok(entries) = std::fs::read_dir(path) {
        for entry in entries.flatten() {
            let p = entry.path();
            if scanner::is_cue_file(&p) {
                match scanner::parse_cue_file(&p.to_string_lossy()) {
                    Ok(sheet) => sheets.push(sheet),
                    Err(e) => sw_warn!("[music_player] 解析 CUE 文件失败: {:?}, err={}", p, e),
                }
            }
        }
    }
    sheets
}

/// 解析指定 CUE 文件
pub fn parse_cue(cue_path: String) -> Result<CueSheet, String> {
    scanner::parse_cue_file(&cue_path).map_err(|e| format!("{:?}", e))
}

/// 为音乐条目匹配 CUE 文件（返回克隆值避免生命周期问题）
fn find_cue_for_item(file_path: &str, cue_sheets: &[CueSheet]) -> Option<CueSheet> {
    let file_name = std::path::Path::new(file_path)
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("");
    cue_sheets
        .iter()
        .find(|s| file_name.ends_with(&s.audio_file) || s.audio_file.ends_with(file_name))
        .cloned()
}

// ── 播放记录 ──────────────────────────────────────────────────────────────────
pub fn get_recent_played(limit: u32) -> Result<Vec<PlayRecord>, String> {
    ensure_db();
    let _ = db_module::db_register_table(record_table());

    let raw = db_list_values(record_table())?;
    let mut records: Vec<PlayRecord> = raw
        .into_iter()
        .filter_map(|v| serde_json::from_str::<PlayRecord>(&v).ok())
        .collect();
    records.sort_by(|a, b| b.played_at.cmp(&a.played_at));
    records.truncate(limit as usize);
    Ok(records)
}

pub fn record_play(music_id: String) -> Result<PlayRecord, String> {
    ensure_db();
    let _ = db_module::db_register_table(record_table());

    // 查找已有记录
    let raw = db_list_key_values(record_table())?;
    let existing = raw
        .into_iter()
        .filter_map(|(_, v)| serde_json::from_str::<PlayRecord>(&v).ok())
        .find(|r| r.music_id == music_id);

    let record = if let Some(mut r) = existing {
        r.play_count += 1;
        r.played_at = Utc::now();
        r
    } else {
        PlayRecord {
            id: uuid::Uuid::new_v4().to_string(),
            music_id,
            played_at: Utc::now(),
            play_count: 1,
        }
    };

    let json = serde_json::to_string(&record).map_err(|e| e.to_string())?;
    db_module::db_set(record_table(), record.id.clone(), json).map_err(|e| e.to_string())?;

    let mut guard = play_records_cache().lock().unwrap();
    if let Some(r) = guard.iter_mut().find(|r| r.music_id == record.music_id) {
        r.play_count = record.play_count;
        r.played_at = record.played_at;
    } else {
        guard.push(record.clone());
    }

    Ok(record)
}

// ── 收藏 ──────────────────────────────────────────────────────────────────────
pub fn get_favorite_items() -> Result<Vec<MusicItem>, String> {
    let all = get_all_music_items()?;
    Ok(all.into_iter().filter(|i| i.is_favorite).collect())
}

pub fn toggle_favorite(item_id: String) -> Result<bool, String> {
    ensure_db();
    let _ = db_module::db_register_table(item_table());

    let raw = db_module::db_get(item_table(), item_id.clone()).map_err(|e| e.to_string())?;
    let value = raw.ok_or("音乐条目不存在")?;
    let mut item: MusicItem = serde_json::from_str(&value).map_err(|e| e.to_string())?;
    item.is_favorite = !item.is_favorite;

    let json = serde_json::to_string(&item).map_err(|e| e.to_string())?;
    db_module::db_set(item_table(), item_id, json).map_err(|e| e.to_string())?;

    // 清空缓存
    {
        let mut guard = music_items_cache().lock().unwrap();
        *guard = None;
    }
    Ok(item.is_favorite)
}

// ── 均衡器预设 ────────────────────────────────────────────────────────────────
pub fn get_eq_presets() -> Result<Vec<EqualizerPreset>, String> {
    ensure_db();
    let _ = db_module::db_register_table(eq_preset_table());

    let cache = eq_presets_cache();
    {
        let guard = cache.lock().unwrap();
        if !guard.is_empty() {
            return Ok(guard.clone());
        }
    }

    let raw = db_list_values(eq_preset_table())?;
    let mut presets: Vec<EqualizerPreset> = raw
        .into_iter()
        .filter_map(|v| serde_json::from_str::<EqualizerPreset>(&v).ok())
        .collect();

    // 如果没有预设，创建内置预设
    if presets.is_empty() {
        presets = create_builtin_eq_presets();
        for preset in &presets {
            let json = serde_json::to_string(preset).map_err(|e| e.to_string())?;
            db_module::db_set(eq_preset_table(), preset.id.clone(), json)
                .map_err(|e| e.to_string())?;
        }
    }

    let mut guard = cache.lock().unwrap();
    *guard = presets.clone();
    Ok(presets)
}

pub fn save_eq_preset(name: String, bands: Vec<f32>) -> Result<EqualizerPreset, String> {
    ensure_db();
    let _ = db_module::db_register_table(eq_preset_table());

    if bands.len() != 10 {
        return Err("均衡器需要 10 个频段".to_string());
    }

    let preset = EqualizerPreset {
        id: uuid::Uuid::new_v4().to_string(),
        name,
        bands,
        is_builtin: false,
    };

    let json = serde_json::to_string(&preset).map_err(|e| e.to_string())?;
    db_module::db_set(eq_preset_table(), preset.id.clone(), json).map_err(|e| e.to_string())?;

    let mut guard = eq_presets_cache().lock().unwrap();
    guard.push(preset.clone());
    Ok(preset)
}

pub fn delete_eq_preset(preset_id: String) -> Result<bool, String> {
    ensure_db();
    // 不允许删除内置预设
    let presets = get_eq_presets()?;
    if let Some(p) = presets.iter().find(|p| p.id == preset_id) {
        if p.is_builtin {
            return Err("不能删除内置预设".to_string());
        }
    }

    let preset_id_for_cache = preset_id.clone();
    db_module::db_delete(eq_preset_table(), preset_id).map_err(|e| e.to_string())?;
    let mut guard = eq_presets_cache().lock().unwrap();
    guard.retain(|p| p.id != preset_id_for_cache);
    Ok(true)
}

// ── 内部辅助 ──────────────────────────────────────────────────────────────────
fn update_playlist_count(playlist_id: &str) -> Result<(), String> {
    let items = get_playlist_items(playlist_id.to_string()).unwrap_or_default();
    let count = items.len();

    let _ = db_module::db_register_table(playlist_table());
    let raw =
        db_module::db_get(playlist_table(), playlist_id.to_string()).map_err(|e| e.to_string())?;
    if let Some(value) = raw {
        let mut playlist: Playlist = serde_json::from_str(&value).map_err(|e| e.to_string())?;
        playlist.item_count = count;
        playlist.updated_at = Utc::now();
        let json = serde_json::to_string(&playlist).map_err(|e| e.to_string())?;
        db_module::db_set(playlist_table(), playlist_id.to_string(), json)
            .map_err(|e| e.to_string())?;

        let mut guard = playlists_cache().lock().unwrap();
        if let Some(p) = guard.iter_mut().find(|p| p.id == playlist_id) {
            p.item_count = count;
            p.updated_at = playlist.updated_at;
        }
    }
    Ok(())
}

fn create_builtin_eq_presets() -> Vec<EqualizerPreset> {
    vec![
        EqualizerPreset {
            id: "eq_flat".to_string(),
            name: "平坦".to_string(),
            bands: vec![0.0; 10],
            is_builtin: true,
        },
        EqualizerPreset {
            id: "eq_bass_boost".to_string(),
            name: "低音增强".to_string(),
            bands: vec![6.0, 4.0, 2.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
            is_builtin: true,
        },
        EqualizerPreset {
            id: "eq_treble_boost".to_string(),
            name: "高音增强".to_string(),
            bands: vec![0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.0, 4.0, 6.0, 6.0],
            is_builtin: true,
        },
        EqualizerPreset {
            id: "eq_vocal".to_string(),
            name: "人声增强".to_string(),
            bands: vec![-2.0, -1.0, 0.0, 2.0, 4.0, 4.0, 2.0, 0.0, -1.0, -2.0],
            is_builtin: true,
        },
        EqualizerPreset {
            id: "eq_rock".to_string(),
            name: "摇滚".to_string(),
            bands: vec![4.0, 2.0, -1.0, -2.0, 0.0, 2.0, 3.0, 4.0, 4.0, 4.0],
            is_builtin: true,
        },
        EqualizerPreset {
            id: "eq_classical".to_string(),
            name: "古典".to_string(),
            bands: vec![3.0, 2.0, 1.0, 1.0, -1.0, -1.0, 0.0, 2.0, 3.0, 4.0],
            is_builtin: true,
        },
    ]
}

/// 封面缩略图缓存目录
fn thumb_cache_dir() -> std::path::PathBuf {
    let dir = std::path::Path::new(&app_data_base())
        .join("SlimeWorks")
        .join("library")
        .join("music")
        .join("covers");
    let _ = std::fs::create_dir_all(&dir);
    dir
}

/// FNV-1a 哈希生成路径稳定 key
fn path_key(path: &str) -> String {
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for b in path.bytes() {
        hash ^= b as u64;
        hash = hash.wrapping_mul(0x100_0000_01b3);
    }
    format!("{:016x}", hash)
}

/// 生成封面缩略图（暂不依赖 media_collection，）
pub fn ensure_music_cover_thumbnail(file_path: String, width: u32) -> Option<String> {
    // 使用 ffmpeg 生成缩略图
    let lower = file_path.to_lowercase();
    let is_audio = lower.ends_with(".mp3")
        || lower.ends_with(".flac")
        || lower.ends_with(".aac")
        || lower.ends_with(".m4a")
        || lower.ends_with(".ogg")
        || lower.ends_with(".opus")
        || lower.ends_with(".wav")
        || lower.ends_with(".wma")
        || lower.ends_with(".ape");
    if !is_audio {
        return None;
    }
    let key = format!("{}_w{}", path_key(&file_path), width);
    let cache_dir = thumb_cache_dir();
    let cache_path = cache_dir.join(format!("{}.jpg", key));
    if cache_path.exists() {
        if let Ok(meta) = std::fs::metadata(&cache_path) {
            if meta.len() > 0 {
                return Some(cache_path.to_string_lossy().into_owned());
            }
        }
        let _ = std::fs::remove_file(&cache_path);
    }
    // 生成缩略图
    for _seek in &["00:00:00.000", "00:00:03.000", "00:00:00.000"] {
        let ok = std::process::Command::new("ffmpeg")
            .args([
                "-i",
                &file_path,
                "-map",
                "0:v:0",
                "-vf",
                &format!("scale={}:-1", width),
                "-q:v",
                "3",
                "-frames:v",
                "1",
                "-y",
                &cache_path.to_string_lossy(),
            ])
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status()
            .map(|s| s.success())
            .unwrap_or(false);
        if ok && cache_path.exists() {
            return Some(cache_path.to_string_lossy().into_owned());
        }
    }
    None
}

/// 批量提取封面（后台调用，不阻塞导入流程）
/// 返回成功提取封面的数量
pub fn batch_extract_covers(playlist_id: String) -> Result<usize, String> {
    let items = get_playlist_items(playlist_id)?;
    let mut count = 0usize;
    for item in &items {
        if item.cover_path.is_some() {
            continue;
        }
        if let Some(thumb) = ensure_music_cover_thumbnail(item.file_path.clone(), 300) {
            // 更新数据库
            let updated = MusicItem {
                cover_path: Some(thumb),
                ..item.clone()
            };
            let json = serde_json::to_string(&updated).map_err(|e| e.to_string())?;
            db_module::db_set(item_table(), item.id.clone(), json).map_err(|e| e.to_string())?;
            count += 1;
        }
    }
    // 清空缓存
    {
        let mut guard = music_items_cache().lock().unwrap();
        *guard = None;
    }
    sw_info!("[music_player] 批量提取封面完成，共提取 {} 个", count);
    Ok(count)
}
