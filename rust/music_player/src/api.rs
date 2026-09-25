use chrono::Utc;
use slime_logger::{sw_info, sw_warn};
use std::sync::{Arc, Mutex, OnceLock};

use crate::scanner;
use crate::types::{CueSheet, EqualizerPreset, Folder, MusicItem, PathMappingNode, PlayRecord, Playlist, RemoteMusicItem};

// ── 内存缓存 ──────────────────────────────────────────────────────────────────
static PLAYLISTS: OnceLock<Arc<Mutex<Vec<Playlist>>>> = OnceLock::new();
static MUSIC_ITEMS: OnceLock<Mutex<Option<Vec<MusicItem>>>> = OnceLock::new();
static PLAY_RECORDS: OnceLock<Arc<Mutex<Vec<PlayRecord>>>> = OnceLock::new();
static EQ_PRESETS: OnceLock<Arc<Mutex<Vec<EqualizerPreset>>>> = OnceLock::new();
static FOLDERS: OnceLock<Arc<Mutex<Vec<Folder>>>> = OnceLock::new();
/// 数据库初始化成功标记。只缓存「成功」结果：失败时不写入，
/// 下次调用会重试（若数据库文件被另一进程独占锁定，锁定解除后即可恢复）。
static DB_INIT_RESULT: OnceLock<()> = OnceLock::new();

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

fn folders_cache() -> &'static Arc<Mutex<Vec<Folder>>> {
    FOLDERS.get_or_init(|| Arc::new(Mutex::new(Vec::new())))
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

/// 批量落库音乐条目：合并到单个 redb 事务。
/// 逐条 `db_set` 会为每个条目触发一次 commit（一趟磁盘刷写），
/// 导入上千曲目时这是分钟级与秒级的差距。
fn persist_items_batch(items: &[MusicItem]) -> Result<(), String> {
    if items.is_empty() {
        return Ok(());
    }
    let sets = items
        .iter()
        .filter_map(|item| {
            serde_json::to_string(item)
                .ok()
                .map(|value| db_module::DbRecord { key: item.id.clone(), value })
        })
        .collect::<Vec<_>>();
    db_module::db_batch_write(item_table(), sets, Vec::new()).map(|_| ())
}

fn record_table() -> String {
    "music_play_records".to_string()
}

fn eq_preset_table() -> String {
    "music_eq_presets".to_string()
}

fn folder_table() -> String {
    "music_folders".to_string()
}

/// 音乐库内部元数据表（迁移标记等）
fn meta_table() -> String {
    "music_meta".to_string()
}

/// 音乐库需要绑定的全部表（含 whisper_module 共用的配置表）
fn music_table_names() -> Vec<String> {
    vec![
        playlist_table(),
        item_table(),
        record_table(),
        eq_preset_table(),
        folder_table(),
        meta_table(),
        "whisper_config".to_string(),
    ]
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
    // 已成功过：直接返回（幂等）
    if DB_INIT_RESULT.get().is_some() {
        return Ok(());
    }
    let path = default_db_path();
    sw_info!("[music_db] 初始化数据库: {}", path);
    match db_module::db_init(path.clone()) {
        Ok(_) => {
            sw_info!("[music_db] 数据库初始化成功，绑定表...");
            // 将所有表绑定到 music_player.db，避免历史上多模块共享全局单例
            // 时因初始化顺序不同导致数据写入错误文件的问题
            for table in music_table_names() {
                if let Err(e) = db_module::db_bind_table(table.clone(), path.clone()) {
                    sw_warn!("[music_db] 绑定表 {} 失败: {}", table, e);
                } else {
                    sw_info!("[music_db] 绑定表 {} 成功", table);
                }
            }
            migrate_scattered_music_data(&path);
            // 仅在成功时写入标记；失败不缓存，下次调用可重试
            let _ = DB_INIT_RESULT.set(());
            Ok(())
        }
        Err(e) => {
            sw_warn!("[music_db] 数据库初始化失败: {}", e);
            Err(e)
        }
    }
}

fn ensure_db() {
    let _ = initialize_db();
    // 确保表已绑定（即使 db_init 成功但绑定失败也能恢复）
    let path = default_db_path();
    for table in music_table_names() {
        let _ = db_module::db_bind_table(table.clone(), path.clone());
    }
}

/// 一次性迁移：历史上全局 db 单例「先到先得」时，音乐数据可能被写入其他模块的
/// 文件（如 media.db / db.redb）。这里把散落记录合并回 music_player.db（幂等，只执行一次）。
fn migrate_scattered_music_data(music_db_path: &str) {
    // 幂等标记：已迁移过则跳过
    if let Ok(Some(flag)) = db_module::db_get(meta_table(), "scatter_merged_v1".to_string()) {
        if flag == "1" {
            return;
        }
    }

    let base = std::path::Path::new(&app_data_base()).join("SlimeWorks");
    let candidates = [base.join("media.db"), base.join("db.redb")];
    let tables = music_table_names();

    for candidate in &candidates {
        let src = candidate.to_string_lossy().into_owned();
        if src == music_db_path || !candidate.exists() {
            continue;
        }
        // 只补齐目标缺失的记录，不覆盖已有数据（音乐播放记录等取并集即可）
        match db_module::db_merge_tables(
            src.clone(),
            music_db_path.to_string(),
            tables.clone(),
            false,
        ) {
            Ok(n) if n > 0 => sw_info!("[music_db] 从 {} 合并散落记录 {} 条", src, n),
            Ok(_) => {}
            Err(e) => sw_warn!("[music_db] 合并 {} 失败: {}", src, e),
        }
    }
    let _ = db_module::db_set(
        meta_table(),
        "scatter_merged_v1".to_string(),
        "1".to_string(),
    );
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
    create_playlist_in_folder(name, None)
}

/// 在指定目录下创建播放列表
pub fn create_playlist_in_folder(
    name: String,
    folder_id: Option<String>,
) -> Result<Playlist, String> {
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
        folder_id,
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
    let mut playlist = create_playlist_in_folder("默认列表".to_string(), None)?;
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

    // 保存到数据库（单事务批量写入）
    let _ = db_module::db_register_table(item_table());
    persist_items_batch(&items).map_err(|e| e.to_string())?;

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

    // 检查是否有 CUE 文件
    let has_cue = scanner::find_cue_for_audio(&file_path).is_some();

    // 提取音频元数据（时长、标签等）
    let audio_meta = scanner::extract_audio_metadata(path);

    // 获取当前最大 order
    let existing = get_playlist_items(playlist_id.clone()).unwrap_or_default();
    let max_order = existing.iter().map(|i| i.order).max().unwrap_or(-1);

    let item = MusicItem {
        id: uuid::Uuid::new_v4().to_string(),
        playlist_id: playlist_id.clone(),
        title: audio_meta.title.unwrap_or(title),
        artist: audio_meta.artist,
        album: audio_meta.album,
        file_path,
        duration_ms: audio_meta.duration_ms,
        track_number: audio_meta.track_number,
        disc_number: None,
        year: audio_meta.year,
        genre: audio_meta.genre,
        cover_path,
        file_size: metadata.len(),
        modified_at: Utc::now(),
        order: max_order + 1,
        is_favorite: false,
        has_cue,
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

/// 批量添加远程音乐项（HTTP 流地址，不检查本地文件存在性）
pub fn add_remote_music_items(
    playlist_id: String,
    remote_items: Vec<RemoteMusicItem>,
) -> Result<Vec<MusicItem>, String> {
    ensure_db();
    let existing = get_playlist_items(playlist_id.clone()).unwrap_or_default();
    let mut max_order = existing.iter().map(|i| i.order).max().unwrap_or(-1);

    let _ = db_module::db_register_table(item_table());
    let mut items = Vec::new();
    for r in remote_items {
        max_order += 1;
        let item = MusicItem {
            id: uuid::Uuid::new_v4().to_string(),
            playlist_id: playlist_id.clone(),
            title: r.title,
            artist: None,
            album: None,
            file_path: r.url,
            duration_ms: r.duration_ms,
            track_number: r.track_number,
            disc_number: None,
            year: None,
            genre: None,
            cover_path: None,
            file_size: 0,
            modified_at: Utc::now(),
            order: max_order,
            is_favorite: false,
            has_cue: false,
        };
        items.push(item);
    }
    persist_items_batch(&items).map_err(|e| e.to_string())?;

    if !items.is_empty() {
        update_playlist_count(&playlist_id)?;
        // 清空缓存
        let mut guard = music_items_cache().lock().unwrap();
        *guard = None;
    }
    sw_info!("[music_player] 批量添加远程音乐项 {} 首", items.len());
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

    let mut reordered = Vec::new();
    for (order, id) in item_ids.iter().enumerate() {
        let raw = db_module::db_get(item_table(), id.clone()).map_err(|e| e.to_string())?;
        if let Some(value) = raw {
            let mut item: MusicItem = serde_json::from_str(&value).map_err(|e| e.to_string())?;
            item.order = order as i32;
            reordered.push(item);
        }
    }
    persist_items_batch(&reordered).map_err(|e| e.to_string())?;

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

/// 修复已有音乐条目的缺失元数据（时长、标签等）
pub fn repair_missing_metadata(playlist_id: String) -> Result<usize, String> {
    ensure_db();
    let items = get_playlist_items(playlist_id)?;
    let mut count = 0usize;
    for item in &items {
        // 跳过已有时长且已有标签的条目
        if item.duration_ms.is_some() && item.artist.is_some() && item.album.is_some() {
            continue;
        }
        let path = std::path::Path::new(&item.file_path);
        if !path.exists() {
            continue;
        }
        let audio_meta = scanner::extract_audio_metadata(path);
        let mut updated = item.clone();
        if updated.duration_ms.is_none() {
            updated.duration_ms = audio_meta.duration_ms;
        }
        if updated.title
            == path
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or("未命名")
        {
            // 标题仍是文件名，尝试用标签替换
            if let Some(t) = audio_meta.title {
                updated.title = t;
            }
        }
        if updated.artist.is_none() {
            updated.artist = audio_meta.artist;
        }
        if updated.album.is_none() {
            updated.album = audio_meta.album;
        }
        if updated.track_number.is_none() {
            updated.track_number = audio_meta.track_number;
        }
        if updated.year.is_none() {
            updated.year = audio_meta.year;
        }
        if updated.genre.is_none() {
            updated.genre = audio_meta.genre;
        }
        let json = serde_json::to_string(&updated).map_err(|e| e.to_string())?;
        db_module::db_set(item_table(), item.id.clone(), json).map_err(|e| e.to_string())?;
        count += 1;
    }
    // 清空缓存
    {
        let mut guard = music_items_cache().lock().unwrap();
        *guard = None;
    }
    sw_info!("[music_player] 修复元数据完成，共修复 {} 条", count);
    Ok(count)
}

// ── 目录 CRUD ─────────────────────────────────────────────────────────────────

/// 获取所有目录
pub fn get_all_folders() -> Result<Vec<Folder>, String> {
    ensure_db();
    let cache = folders_cache();
    {
        let guard = cache.lock().unwrap();
        if !guard.is_empty() {
            return Ok(guard.clone());
        }
    }

    let _ = db_module::db_register_table(folder_table());
    let raw = db_list_values(folder_table())?;
    let folders: Vec<Folder> = raw
        .into_iter()
        .filter_map(|v| serde_json::from_str::<Folder>(&v).ok())
        .collect();

    let mut guard = cache.lock().unwrap();
    *guard = folders.clone();
    Ok(folders)
}

/// 获取指定父目录下的子目录
pub fn get_sub_folders(parent_id: Option<String>) -> Result<Vec<Folder>, String> {
    let all = get_all_folders()?;
    Ok(all
        .into_iter()
        .filter(|f| f.parent_id == parent_id)
        .collect())
}

/// 获取指定目录下的播放列表
pub fn get_playlists_by_folder(folder_id: Option<String>) -> Result<Vec<Playlist>, String> {
    let all = get_all_playlists()?;
    Ok(all
        .into_iter()
        .filter(|p| p.folder_id == folder_id)
        .collect())
}

/// 创建目录（最多三级）
pub fn create_folder(name: String, parent_id: Option<String>) -> Result<Folder, String> {
    ensure_db();
    let _ = db_module::db_register_table(folder_table());

    // 计算层级
    let level = if let Some(ref pid) = parent_id {
        let all = get_all_folders()?;
        let parent = all.iter().find(|f| &f.id == pid).ok_or("父目录不存在")?;
        if parent.level >= 3 {
            return Err("已达到最大目录深度（3级）".to_string());
        }
        parent.level + 1
    } else {
        1
    };

    let folder = Folder {
        id: uuid::Uuid::new_v4().to_string(),
        name,
        parent_id,
        level,
        cover_path: None,
        tags: None,
        author: None,
        play_count: 0,
        created_at: Utc::now(),
        updated_at: Utc::now(),
    };

    let json = serde_json::to_string(&folder).map_err(|e| e.to_string())?;
    db_module::db_set(folder_table(), folder.id.clone(), json).map_err(|e| e.to_string())?;

    let mut guard = folders_cache().lock().unwrap();
    guard.push(folder.clone());
    Ok(folder)
}

/// 重命名目录
pub fn rename_folder(folder_id: String, name: String) -> Result<bool, String> {
    ensure_db();
    let _ = db_module::db_register_table(folder_table());

    let raw = db_module::db_get(folder_table(), folder_id.clone()).map_err(|e| e.to_string())?;
    let value = raw.ok_or("目录不存在")?;
    let mut folder: Folder = serde_json::from_str(&value).map_err(|e| e.to_string())?;
    folder.name = name;
    folder.updated_at = Utc::now();

    let json = serde_json::to_string(&folder).map_err(|e| e.to_string())?;
    db_module::db_set(folder_table(), folder_id.clone(), json).map_err(|e| e.to_string())?;

    let mut guard = folders_cache().lock().unwrap();
    if let Some(f) = guard.iter_mut().find(|f| f.id == folder_id) {
        f.name = folder.name;
        f.updated_at = folder.updated_at;
    }
    Ok(true)
}

/// 删除目录（级联删除子目录和关联的播放列表）
pub fn delete_folder(folder_id: String) -> Result<bool, String> {
    ensure_db();

    // 递归收集所有子目录 ID
    let all_folders = get_all_folders()?;
    let mut to_delete = vec![folder_id.clone()];
    let mut queue = vec![folder_id.clone()];
    while let Some(current) = queue.pop() {
        for child in all_folders
            .iter()
            .filter(|f| f.parent_id.as_deref() == Some(&current))
        {
            to_delete.push(child.id.clone());
            queue.push(child.id.clone());
        }
    }

    // 删除所有子目录关联的播放列表及其音乐条目
    for fid in &to_delete {
        let playlists = get_playlists_by_folder(Some(fid.clone()))?;
        for pl in playlists {
            let _ = delete_playlist(pl.id);
        }
        db_module::db_delete(folder_table(), fid.clone()).map_err(|e| e.to_string())?;
    }

    // 清空缓存
    {
        let mut guard = folders_cache().lock().unwrap();
        guard.retain(|f| !to_delete.contains(&f.id));
    }
    Ok(true)
}

/// 更新目录信息（封面、标签、作者等）
pub fn update_folder(
    folder_id: String,
    name: Option<String>,
    cover_path: Option<String>,
    tags: Option<String>,
    author: Option<String>,
) -> Result<bool, String> {
    ensure_db();
    let _ = db_module::db_register_table(folder_table());

    let raw = db_module::db_get(folder_table(), folder_id.clone()).map_err(|e| e.to_string())?;
    let value = raw.ok_or("目录不存在")?;
    let mut folder: Folder = serde_json::from_str(&value).map_err(|e| e.to_string())?;

    if let Some(n) = name {
        folder.name = n;
    }
    if let Some(c) = cover_path {
        folder.cover_path = Some(c);
    }
    if let Some(t) = tags {
        folder.tags = Some(t);
    }
    if let Some(a) = author {
        folder.author = Some(a);
    }
    folder.updated_at = Utc::now();

    let json = serde_json::to_string(&folder).map_err(|e| e.to_string())?;
    db_module::db_set(folder_table(), folder_id.clone(), json).map_err(|e| e.to_string())?;

    // 清空缓存
    {
        let mut guard = folders_cache().lock().unwrap();
        *guard = Vec::new();
    }
    Ok(true)
}

/// 递增目录播放次数
pub fn increment_folder_play_count(folder_id: String) -> Result<bool, String> {
    ensure_db();
    let _ = db_module::db_register_table(folder_table());

    let raw = db_module::db_get(folder_table(), folder_id.clone()).map_err(|e| e.to_string())?;
    let value = raw.ok_or("目录不存在")?;
    let mut folder: Folder = serde_json::from_str(&value).map_err(|e| e.to_string())?;
    folder.play_count += 1;
    folder.updated_at = Utc::now();

    let json = serde_json::to_string(&folder).map_err(|e| e.to_string())?;
    db_module::db_set(folder_table(), folder_id.clone(), json).map_err(|e| e.to_string())?;

    let mut guard = folders_cache().lock().unwrap();
    if let Some(f) = guard.iter_mut().find(|f| f.id == folder_id) {
        f.play_count = folder.play_count;
    }
    Ok(true)
}

// ── 路径映射 ─────────────────────────────────────────────────────────────────

/// 扫描文件夹路径映射（返回树形结构，不限制文件类型，不限深度）
pub fn scan_path_mapping(dir_path: String) -> Result<PathMappingNode, String> {
    scanner::scan_path_mapping(&dir_path).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    //! api.rs DB 层单元测试。
    //! 安全隔离：所有 DB 用例通过 DbTestEnv 在首次 initialize_db 之前把 HOME
    //! 重定向到进程唯一临时目录，music_player.db 只会在隔离 HOME 内被创建/打开，
    //! 真实用户曲库（~/Library/Application Support/SlimeWorks）从头到尾不被触碰；
    //! 运行时另有断言校验 DB 路径确实位于隔离 HOME 内（双保险）。

    use super::*;
    use crate::types::PathMappingNodeType;
    use std::fs;
    use std::path::{Path, PathBuf};
    use std::sync::atomic::{AtomicUsize, Ordering as AtomicOrdering};

    // ════════════════════════════ DB 隔离环境 ════════════════════════════
    //
    // 直接借鉴 media_collection/src/api.rs 的 DbTestEnv / DB_TEST_LOCK 范式：
    // default_db_path() 完全由 $HOME 推导（macOS:
    // ~/Library/Application Support/SlimeWorks/music_player.db），且 db_module 的
    // 实例表/表路由是进程级静态。因此必须在首次 initialize_db 之前把 HOME 重定向
    // 到独立临时目录；所有走 DB / 进程全局内存缓存的用例统一持 DB_TEST_LOCK
    // 串行执行，避免共享表与缓存互踩。

    /// DB 用例全局串行锁
    static DB_TEST_LOCK: Mutex<()> = Mutex::new(());
    /// 用例唯一序号（配合 pid 生成不冲突的 tag）
    static SEQ: AtomicUsize = AtomicUsize::new(0);

    struct DbTestEnv {
        /// 隔离 HOME 路径（固定名临时目录，每次运行开跑前清旧重建，避免按
        /// 随机后缀在系统临时目录里无限累积）
        #[allow(dead_code)]
        home_path: PathBuf,
        #[allow(dead_code)]
        db_path: String,
    }

    /// 初始化（且只初始化一次）隔离 DB 环境
    fn db_test_env() -> &'static DbTestEnv {
        static ENV: OnceLock<DbTestEnv> = OnceLock::new();
        ENV.get_or_init(|| {
            let home_path = std::env::temp_dir().join("music_db_test_home");
            assert_eq!(
                home_path.parent(),
                Some(std::env::temp_dir().as_path()),
                "清理目标必须恰好位于系统临时目录下，防误删"
            );
            let _ = std::fs::remove_dir_all(&home_path);
            std::fs::create_dir_all(&home_path).expect("创建隔离 HOME 失败");
            // edition 2021：set_var 是安全接口；只在 OnceLock 初始化闭包里调用一次，
            // 之后 HOME 永不再变化，DB 用例又全部串行，不存在反复改环境变量的竞态
            std::env::set_var("HOME", &home_path);
            initialize_db().expect("隔离 HOME 下 initialize_db 应成功");
            // initialize_db 必须幂等
            initialize_db().expect("initialize_db 应幂等");
            let db_path = default_db_path();
            assert!(
                db_path.starts_with(home_path.to_string_lossy().as_ref()),
                "DB 路径必须位于隔离 HOME 内，绝不触碰真实用户库: {db_path}"
            );
            // db_module 的首个全局实例路径也必须落在隔离 HOME 内（双保险）
            let first = db_module::db_get_path().expect("db_get_path 应可用");
            assert!(
                first.starts_with(home_path.to_string_lossy().as_ref()),
                "db_module 全局首实例必须位于隔离 HOME 内: {first}"
            );
            // redb 语义：表只有被首次写入后才在文件中存在，纯新库上先读会报
            // TableNotFound（生产代码边界行为）。这里以「探针写入再删除」把全部
            // 表物化，保证各用例无论执行顺序如何都确定性可跑
            //（真实用户库里各表早已被首写建立，不存在该窗口）。
            for table in music_table_names() {
                db_module::db_set(table.clone(), "__bootstrap__".into(), "1".into()).unwrap();
                db_module::db_delete(table.clone(), "__bootstrap__".into()).unwrap();
            }
            DbTestEnv {
                home_path,
                db_path,
            }
        })
    }

    /// 取 DB 串行锁，并在持锁状态下确保隔离环境已初始化
    fn lock_db_test_serial() -> std::sync::MutexGuard<'static, ()> {
        let guard = DB_TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        db_test_env();
        guard
    }

    // ── 通用辅助 ──────────────────────────────────────────────────────────

    /// 进程内唯一 tag，避免用例间 id/名称互踩
    fn unique_tag() -> String {
        format!(
            "{}-{}",
            std::process::id(),
            SEQ.fetch_add(1, AtomicOrdering::SeqCst)
        )
    }

    /// 直读底层 redb 表：按 key 取回原始 JSON 字符串（media_collection 测试同款先例）
    fn db_row(table: String, key: &str) -> Option<String> {
        db_module::db_get(table, key.to_string()).unwrap()
    }

    /// 在系统临时目录（非隔离 HOME）下建独立用例目录
    fn case_dir(name: &str) -> tempfile::TempDir {
        tempfile::Builder::new()
            .prefix(&format!("music_api_{}_{tag}_", name, tag = std::process::id()))
            .tempdir()
            .expect("创建用例临时目录失败")
    }

    /// 写入一个假音频文件（15 字节，lofty 解析失败时元数据回退为默认值）
    fn write_audio(dir: &Path, name: &str) -> PathBuf {
        let p = dir.join(name);
        fs::write(&p, b"fake audio data").expect("写入测试音频文件失败");
        p
    }

    /// 清空全部进程级内存缓存，模拟「应用重启后重新从 DB 加载」
    fn invalidate_all_caches() {
        *playlists_cache().lock().unwrap() = Vec::new();
        *music_items_cache().lock().unwrap() = None;
        *play_records_cache().lock().unwrap() = Vec::new();
        *eq_presets_cache().lock().unwrap() = Vec::new();
        *folders_cache().lock().unwrap() = Vec::new();
    }

    // ── initialize_db / 表绑定 ────────────────────────────────────────────

    #[test]
    fn initialize_db_is_isolated_idempotent_and_binds_all_tables() {
        let _serial = lock_db_test_serial();
        let env = db_test_env();
        // DB 文件确实创建于隔离 HOME 之下
        assert!(Path::new(&env.db_path).exists(), "music_player.db 应已落盘");
        // 全部音乐表（含 whisper_config）都已绑定：注册 + 直读直写往返
        for table in music_table_names() {
            db_module::db_register_table(table.clone()).expect("表注册应成功");
            let key = format!("__route_probe__{table}");
            db_module::db_set(table.clone(), key.clone(), "1".into()).unwrap();
            assert_eq!(
                db_row(table.clone(), &key).as_deref(),
                Some("1"),
                "表 {table} 应已绑定到隔离 DB 并可直接读写"
            );
            db_module::db_delete(table.clone(), key).unwrap();
        }
        // 一次性散落数据迁移标记已写入（migrate_scattered_music_data 执行过）
        assert_eq!(
            db_row(meta_table(), "scatter_merged_v1").as_deref(),
            Some("1"),
            "迁移标记 scatter_merged_v1 应已落库"
        );
    }

    // ── 播放列表 CRUD ─────────────────────────────────────────────────────

    #[test]
    fn playlist_crud_roundtrip_api_and_db() {
        let _serial = lock_db_test_serial();
        let tag = unique_tag();
        let name = format!("歌单 {tag}");

        let pl = create_playlist(name.clone()).unwrap();
        assert!(!pl.id.is_empty());
        assert_eq!(pl.item_count, 0);
        assert!(!pl.is_default);
        assert!(pl.folder_id.is_none());

        // API 侧可见
        let all = get_all_playlists().unwrap();
        assert!(all.iter().any(|p| p.id == pl.id && p.name == name));

        // 直读 music_playlists 表验证真正落库
        let raw = db_row(playlist_table(), &pl.id).expect("播放列表应已落库");
        let stored: Playlist = serde_json::from_str(&raw).unwrap();
        assert_eq!(stored.name, name);
        assert!(stored.created_at <= stored.updated_at);

        // 改名同步落库
        rename_playlist(pl.id.clone(), format!("改名 {tag}")).unwrap();
        let stored: Playlist =
            serde_json::from_str(&db_row(playlist_table(), &pl.id).unwrap()).unwrap();
        assert_eq!(stored.name, format!("改名 {tag}"));
        assert!(get_all_playlists()
            .unwrap()
            .iter()
            .any(|p| p.id == pl.id && p.name == format!("改名 {tag}")));

        // 非法 id 错误分支
        assert!(rename_playlist(format!("ghost-{tag}"), "x".into()).is_err());

        // 删除后 API 与底层表都查不到
        assert!(delete_playlist(pl.id.clone()).unwrap());
        assert!(get_all_playlists().unwrap().iter().all(|p| p.id != pl.id));
        assert!(db_row(playlist_table(), &pl.id).is_none());
    }

    #[test]
    fn ensure_default_playlist_is_idempotent() {
        let _serial = lock_db_test_serial();
        let first = ensure_default_playlist().unwrap();
        assert!(first.is_default);
        assert_eq!(first.name, "默认列表");
        // 二次调用应复用同一条记录，不重复创建
        let second = ensure_default_playlist().unwrap();
        assert_eq!(first.id, second.id);
        // 落库校验：DB 里的 JSON is_default=true
        let stored: Playlist =
            serde_json::from_str(&db_row(playlist_table(), &first.id).unwrap()).unwrap();
        assert!(stored.is_default);
        // 全量列表里只应有一个默认列表
        let defaults = get_all_playlists()
            .unwrap()
            .into_iter()
            .filter(|p| p.is_default)
            .count();
        assert_eq!(defaults, 1);
    }

    #[test]
    fn create_playlist_in_folder_links_folder_id() {
        let _serial = lock_db_test_serial();
        let tag = unique_tag();
        let folder = create_folder(format!("归属目录 {tag}"), None).unwrap();
        let pl =
            create_playlist_in_folder(format!("夹内歌单 {tag}"), Some(folder.id.clone())).unwrap();
        assert_eq!(pl.folder_id.as_deref(), Some(folder.id.as_str()));

        // 落库 JSON 带 folder_id
        let stored: Playlist =
            serde_json::from_str(&db_row(playlist_table(), &pl.id).unwrap()).unwrap();
        assert_eq!(stored.folder_id.as_deref(), Some(folder.id.as_str()));

        // 按目录过滤可见；根级过滤不含它
        let in_folder = get_playlists_by_folder(Some(folder.id.clone())).unwrap();
        assert!(in_folder.iter().any(|p| p.id == pl.id));
        let at_root = get_playlists_by_folder(None).unwrap();
        assert!(at_root.iter().all(|p| p.id != pl.id));

        // 清理
        let _ = delete_playlist(pl.id);
        let _ = delete_folder(folder.id);
    }

    // ── 目录树 ────────────────────────────────────────────────────────────

    #[test]
    fn folder_tree_levels_and_errors() {
        let _serial = lock_db_test_serial();
        let tag = unique_tag();
        let l1 = create_folder(format!("一级 {tag}"), None).unwrap();
        assert_eq!(l1.level, 1);
        assert!(l1.parent_id.is_none());
        let l2 = create_folder(format!("二级 {tag}"), Some(l1.id.clone())).unwrap();
        assert_eq!(l2.level, 2);
        let l3 = create_folder(format!("三级 {tag}"), Some(l2.id.clone())).unwrap();
        assert_eq!(l3.level, 3);

        // 第四级：超过最大深度应报错
        let deep = create_folder("四级".into(), Some(l3.id.clone()));
        assert!(deep.is_err());
        assert!(deep.unwrap_err().contains("最大目录深度"));

        // 父目录不存在
        assert!(create_folder("x".into(), Some(format!("ghost-{tag}"))).is_err());

        // 子目录查询过滤
        let subs_of_l1 = get_sub_folders(Some(l1.id.clone())).unwrap();
        assert!(subs_of_l1.iter().any(|f| f.id == l2.id));
        assert!(subs_of_l1
            .iter()
            .all(|f| f.parent_id.as_deref() == Some(l1.id.as_str())));
        assert!(get_sub_folders(Some(l3.id.clone())).unwrap().is_empty());

        // 根级目录里包含 l1
        assert!(get_all_folders().unwrap().iter().any(|f| f.id == l1.id));

        // 落库校验 + 重命名
        let stored: Folder = serde_json::from_str(&db_row(folder_table(), &l3.id).unwrap()).unwrap();
        assert_eq!(stored.level, 3);
        assert_eq!(stored.play_count, 0);
        assert!(rename_folder(l2.id.clone(), format!("二级改名 {tag}")).unwrap());
        let stored: Folder = serde_json::from_str(&db_row(folder_table(), &l2.id).unwrap()).unwrap();
        assert_eq!(stored.name, format!("二级改名 {tag}"));
        // 非法 id 错误分支
        assert!(rename_folder(format!("ghost-{tag}"), "x".into()).is_err());

        // 清理
        let _ = delete_folder(l1.id);
    }

    #[test]
    fn delete_folder_cascades_children_playlists_and_items() {
        let _serial = lock_db_test_serial();
        let tag = unique_tag();
        let dir = case_dir(&format!("cascade_{tag}"));
        let l1 = create_folder(format!("根 {tag}"), None).unwrap();
        let l2 = create_folder(format!("子 {tag}"), Some(l1.id.clone())).unwrap();
        let l3 = create_folder(format!("孙 {tag}"), Some(l2.id.clone())).unwrap();
        let pl =
            create_playlist_in_folder(format!("孙级歌单 {tag}"), Some(l3.id.clone())).unwrap();
        let item = import_music_file(
            pl.id.clone(),
            write_audio(dir.path(), "cascade.mp3").to_string_lossy().into_owned(),
        )
        .unwrap();

        // 前置：全部数据均已落库
        assert!(db_row(folder_table(), &l1.id).is_some());
        assert!(db_row(folder_table(), &l3.id).is_some());
        assert!(db_row(playlist_table(), &pl.id).is_some());
        assert!(db_row(item_table(), &item.id).is_some());

        // 级联删除：子孙目录、关联播放列表、播放列表内条目全部消失
        assert!(delete_folder(l1.id.clone()).unwrap());
        for fid in [&l1.id, &l2.id, &l3.id] {
            assert!(db_row(folder_table(), fid).is_none(), "目录 {fid} 应被级联删除");
        }
        assert!(db_row(playlist_table(), &pl.id).is_none(), "关联播放列表应被级联删除");
        assert!(db_row(item_table(), &item.id).is_none(), "播放列表条目应被级联删除");
        invalidate_all_caches();
        let ids: Vec<String> = get_all_folders().unwrap().into_iter().map(|f| f.id).collect();
        assert!(!ids.contains(&l2.id) && !ids.contains(&l3.id));
        assert!(get_all_playlists().unwrap().iter().all(|p| p.id != pl.id));
    }

    #[test]
    fn update_folder_and_increment_play_count_persist() {
        let _serial = lock_db_test_serial();
        let tag = unique_tag();
        let f = create_folder(format!("信息目录 {tag}"), None).unwrap();

        assert!(update_folder(
            f.id.clone(),
            Some(format!("改名 {tag}")),
            Some("/tmp/cover.jpg".into()),
            Some("流行,华语".into()),
            Some("某歌手".into()),
        )
        .unwrap());
        // 直读底层表验证字段
        let stored: Folder = serde_json::from_str(&db_row(folder_table(), &f.id).unwrap()).unwrap();
        assert_eq!(stored.name, format!("改名 {tag}"));
        assert_eq!(stored.cover_path.as_deref(), Some("/tmp/cover.jpg"));
        assert_eq!(stored.tags.as_deref(), Some("流行,华语"));
        assert_eq!(stored.author.as_deref(), Some("某歌手"));
        // update_folder 清空缓存后，重新查询应拿到新值
        assert!(get_all_folders()
            .unwrap()
            .iter()
            .any(|x| x.id == f.id && x.name == format!("改名 {tag}")));

        // 播放次数累加两次
        assert!(increment_folder_play_count(f.id.clone()).unwrap());
        assert!(increment_folder_play_count(f.id.clone()).unwrap());
        let stored: Folder = serde_json::from_str(&db_row(folder_table(), &f.id).unwrap()).unwrap();
        assert_eq!(stored.play_count, 2);

        // 非法 id 错误分支
        assert!(
            update_folder(format!("ghost-{tag}"), Some("x".into()), None, None, None).is_err()
        );
        assert!(increment_folder_play_count(format!("ghost-{tag}")).is_err());

        let _ = delete_folder(f.id);
    }

    // ── 音乐条目导入 / 顺序 ───────────────────────────────────────────────

    #[test]
    fn import_music_folder_persists_ordered_items() {
        let _serial = lock_db_test_serial();
        let tag = unique_tag();
        let dir = case_dir(&format!("dir_import_{tag}"));
        write_audio(dir.path(), "a.mp3");
        let sub = dir.path().join("sub");
        fs::create_dir_all(&sub).unwrap();
        write_audio(&sub, "b.flac");
        fs::write(dir.path().join("note.txt"), b"not audio").unwrap();
        // 隐藏目录里的音频必须被跳过
        let hidden = dir.path().join(".hidden");
        fs::create_dir_all(&hidden).unwrap();
        write_audio(&hidden, "ghost.mp3");

        let pl = create_playlist(format!("目录导入 {tag}")).unwrap();
        let items =
            import_music_folder(pl.id.clone(), dir.path().to_string_lossy().into_owned()).unwrap();

        // 只收 2 个音频文件；order 从 0 开始连续编号
        assert_eq!(items.len(), 2, "应扫描到 a.mp3 与 sub/b.flac");
        assert!(items.iter().all(|i| i.file_path.find(".hidden").is_none()));
        let mut orders: Vec<i32> = items.iter().map(|i| i.order).collect();
        orders.sort();
        assert_eq!(orders, vec![0, 1]);

        // 每条都真实落库，playlist_id 正确
        for item in &items {
            let stored: MusicItem =
                serde_json::from_str(&db_row(item_table(), &item.id).expect("条目应落库")).unwrap();
            assert_eq!(stored.playlist_id, pl.id);
            assert_eq!(stored.file_size, 15);
        }

        // get_playlist_items 按 order 升序返回
        let listed = get_playlist_items(pl.id.clone()).unwrap();
        assert_eq!(listed.len(), 2);
        assert!(listed.windows(2).all(|w| w[0].order <= w[1].order));

        // 播放列表 item_count 同步为 2
        let p: Playlist = serde_json::from_str(&db_row(playlist_table(), &pl.id).unwrap()).unwrap();
        assert_eq!(p.item_count, 2);

        // 目录不存在 → 错误分支
        assert!(import_music_folder(pl.id.clone(), format!("/nonexistent/{tag}")).is_err());

        // 清理
        let _ = delete_playlist(pl.id);
    }

    #[test]
    fn import_music_folder_merges_cue_metadata() {
        let _serial = lock_db_test_serial();
        let tag = unique_tag();
        let dir = case_dir(&format!("cue_merge_{tag}"));
        write_audio(dir.path(), "album.mp3");
        fs::write(
            dir.path().join("album.cue"),
            "TITLE \"测试专辑\"\nPERFORMER \"整体艺术家\"\nFILE \"album.mp3\" WAVE\n  TRACK 01 AUDIO\n    TITLE \"第一首\"\n    PERFORMER \"歌手A\"\n    INDEX 01 00:00:00\n  TRACK 02 AUDIO\n    TITLE \"第二首\"\n    INDEX 01 03:30:00\n",
        )
        .unwrap();

        let pl = create_playlist(format!("CUE 导入 {tag}")).unwrap();
        let items =
            import_music_folder(pl.id.clone(), dir.path().to_string_lossy().into_owned()).unwrap();
        assert_eq!(items.len(), 1);
        let item = &items[0];
        // 标题/专辑/艺术家来自 CUE 首轨合并，has_cue 置真
        assert_eq!(item.title, "第一首");
        assert_eq!(item.album.as_deref(), Some("测试专辑"));
        assert_eq!(item.artist.as_deref(), Some("歌手A"));
        assert!(item.has_cue);
        // 合并结果已持久化
        let stored: MusicItem =
            serde_json::from_str(&db_row(item_table(), &item.id).unwrap()).unwrap();
        assert_eq!(stored.title, "第一首");

        // scan_cue_files 目录级解析
        let sheets = scan_cue_files(dir.path().to_string_lossy().as_ref());
        assert_eq!(sheets.len(), 1);
        assert_eq!(sheets[0].tracks.len(), 2);
        assert_eq!(sheets[0].tracks[1].start_ms, 210000);
        // 不存在的目录返回空集合
        assert!(scan_cue_files(&format!("/nonexistent/{tag}")).is_empty());
        // parse_cue 非法路径报错
        assert!(parse_cue(format!("/nonexistent/{tag}.cue")).is_err());

        let _ = delete_playlist(pl.id);
    }

    #[test]
    fn import_single_file_appends_order_and_updates_errors_delete_roundtrip() {
        let _serial = lock_db_test_serial();
        let tag = unique_tag();
        let dir = case_dir(&format!("single_{tag}"));
        let pl = create_playlist(format!("单曲导入 {tag}")).unwrap();

        let it1 = import_music_file(
            pl.id.clone(),
            write_audio(dir.path(), "one.mp3").to_string_lossy().into_owned(),
        )
        .unwrap();
        let it2 = import_music_file(
            pl.id.clone(),
            write_audio(dir.path(), "two.m4a").to_string_lossy().into_owned(),
        )
        .unwrap();
        // 逐首导入 order 依次追加（max_order+1）
        assert_eq!(it1.order, 0);
        assert_eq!(it2.order, 1);
        assert_eq!(it1.title, "one");
        assert!(!it1.is_favorite);

        // 错误分支：文件不存在 / 非音频扩展名
        assert!(import_music_file(pl.id.clone(), format!("/nonexistent/{tag}.mp3")).is_err());
        let txt = dir.path().join("readme.txt");
        fs::write(&txt, b"x").unwrap();
        assert!(import_music_file(pl.id.clone(), txt.to_string_lossy().into_owned()).is_err());

        // update_music_item：字段级更新并落库
        assert!(update_music_item(
            it1.id.clone(),
            Some("新标题".into()),
            Some("新艺术家".into()),
            Some("新专辑".into()),
            Some(true),
        )
        .unwrap());
        let stored: MusicItem =
            serde_json::from_str(&db_row(item_table(), &it1.id).unwrap()).unwrap();
        assert_eq!(stored.title, "新标题");
        assert_eq!(stored.artist.as_deref(), Some("新艺术家"));
        assert_eq!(stored.album.as_deref(), Some("新专辑"));
        assert!(stored.is_favorite);
        // 非法 id 错误分支
        assert!(
            update_music_item(format!("ghost-{tag}"), Some("x".into()), None, None, None).is_err()
        );

        // delete_music_item：底层表行消失
        assert!(delete_music_item(it2.id.clone()).unwrap());
        assert!(db_row(item_table(), &it2.id).is_none());
        assert_eq!(get_playlist_items(pl.id.clone()).unwrap().len(), 1);

        // import_music_paths 混合输入：有效文件 + 目录 + 无效项全部容忍
        let sub = dir.path().join("subdir");
        fs::create_dir_all(&sub).unwrap();
        write_audio(&sub, "three.wav");
        let added = import_music_paths(
            pl.id.clone(),
            vec![
                write_audio(dir.path(), "four.opus").to_string_lossy().into_owned(),
                sub.to_string_lossy().into_owned(),
                txt.to_string_lossy().into_owned(),
                format!("/nonexistent/{tag}.mp3"),
            ],
        )
        .unwrap();
        assert_eq!(added.len(), 2, "1 个直传文件 + 目录内 1 个，应成功导入 2 项");

        // clear_playlist_items：清空条目但保留播放列表本体
        let cleared = clear_playlist_items(pl.id.clone()).unwrap();
        assert_eq!(cleared, 3, "it1 + four + three 共 3 条被清空");
        assert!(get_playlist_items(pl.id.clone()).unwrap().is_empty());
        assert!(db_row(playlist_table(), &pl.id).is_some());

        let _ = delete_playlist(pl.id);
    }

    #[test]
    fn save_playlist_order_persists_reordered_values() {
        let _serial = lock_db_test_serial();
        let tag = unique_tag();
        let dir = case_dir(&format!("order_{tag}"));
        let pl = create_playlist(format!("曲序 {tag}")).unwrap();
        let mut ids = Vec::new();
        for name in ["x.mp3", "y.mp3", "z.mp3"] {
            let item = import_music_file(
                pl.id.clone(),
                write_audio(dir.path(), name).to_string_lossy().into_owned(),
            )
            .unwrap();
            ids.push(item.id);
        }

        // 倒序保存：曲序 0/1/2 重排并落库
        save_playlist_order(pl.id.clone(), vec![ids[2].clone(), ids[0].clone(), ids[1].clone()])
            .unwrap();
        let listed = get_playlist_items(pl.id.clone()).unwrap();
        assert_eq!(
            listed.iter().map(|i| i.id.clone()).collect::<Vec<_>>(),
            vec![ids[2].clone(), ids[0].clone(), ids[1].clone()]
        );
        for (expected_order, item) in listed.iter().enumerate() {
            let stored: MusicItem =
                serde_json::from_str(&db_row(item_table(), &item.id).unwrap()).unwrap();
            assert_eq!(stored.order, expected_order as i32);
        }

        // 非法 id 不报错但被跳过（当前实现：跳过项仍占用序号位次）
        save_playlist_order(
            pl.id.clone(),
            vec![ids[0].clone(), format!("ghost-{tag}"), ids[1].clone()],
        )
        .unwrap();
        let stored0: MusicItem =
            serde_json::from_str(&db_row(item_table(), &ids[0]).unwrap()).unwrap();
        let stored1: MusicItem =
            serde_json::from_str(&db_row(item_table(), &ids[1]).unwrap()).unwrap();
        assert_eq!(stored0.order, 0);
        assert_eq!(stored1.order, 2, "被跳过的幽灵 id 仍消耗一个位次");

        let _ = delete_playlist(pl.id);
    }

    #[test]
    fn add_remote_music_items_batches_and_appends_order() {
        let _serial = lock_db_test_serial();
        let tag = unique_tag();
        let pl = create_playlist(format!("远程 {tag}")).unwrap();

        let batch = add_remote_music_items(
            pl.id.clone(),
            vec![
                RemoteMusicItem {
                    title: "流一".into(),
                    url: "https://example.com/a.mp3".into(),
                    duration_ms: Some(1000),
                    track_number: Some(1),
                },
                RemoteMusicItem {
                    title: "流二".into(),
                    url: "https://example.com/b.mp3".into(),
                    duration_ms: None,
                    track_number: None,
                },
            ],
        )
        .unwrap();
        assert_eq!(batch.len(), 2);
        assert_eq!(batch[0].order, 0);
        assert_eq!(batch[1].order, 1);
        assert_eq!(batch[0].file_path, "https://example.com/a.mp3");
        assert_eq!(batch[0].file_size, 0);

        // 再追加一条：order 从既有最大值 +1 连续
        let more = add_remote_music_items(
            pl.id.clone(),
            vec![RemoteMusicItem {
                title: "流三".into(),
                url: "https://example.com/c.mp3".into(),
                duration_ms: None,
                track_number: None,
            }],
        )
        .unwrap();
        assert_eq!(more[0].order, 2);

        // 批量写入已落库 + item_count 同步为 3
        let stored: MusicItem =
            serde_json::from_str(&db_row(item_table(), &more[0].id).unwrap()).unwrap();
        assert_eq!(stored.title, "流三");
        let p: Playlist = serde_json::from_str(&db_row(playlist_table(), &pl.id).unwrap()).unwrap();
        assert_eq!(p.item_count, 3);

        // 空数组：不改动任何数据
        assert!(add_remote_music_items(pl.id.clone(), Vec::new()).unwrap().is_empty());
        let p: Playlist = serde_json::from_str(&db_row(playlist_table(), &pl.id).unwrap()).unwrap();
        assert_eq!(p.item_count, 3);

        let _ = delete_playlist(pl.id);
    }

    // ── 播放记录 / 收藏 ───────────────────────────────────────────────────

    #[test]
    fn record_play_accumulates_count_and_recent_ordering() {
        let _serial = lock_db_test_serial();
        let tag = unique_tag();
        let dir = case_dir(&format!("record_{tag}"));
        let pl = create_playlist(format!("记录 {tag}")).unwrap();
        let item = import_music_file(
            pl.id.clone(),
            write_audio(dir.path(), "play.mp3").to_string_lossy().into_owned(),
        )
        .unwrap();

        let r1 = record_play(item.id.clone()).unwrap();
        assert_eq!(r1.play_count, 1);
        assert_eq!(r1.music_id, item.id);
        let r2 = record_play(item.id.clone()).unwrap();
        // 再次播放：复用同一条记录，计数累加、时间刷新
        assert_eq!(r2.id, r1.id);
        assert_eq!(r2.play_count, 2);
        assert!(r2.played_at >= r1.played_at);

        // 直读底层表：以记录 id 为 key 的 JSON 已累加
        let stored: PlayRecord =
            serde_json::from_str(&db_row(record_table(), &r2.id).unwrap()).unwrap();
        assert_eq!(stored.play_count, 2);
        assert_eq!(stored.music_id, item.id);

        // 最近播放按时间倒序
        let recent = get_recent_played(200).unwrap();
        assert!(recent.windows(2).all(|w| w[0].played_at >= w[1].played_at));
        let mine: Vec<&PlayRecord> = recent.iter().filter(|r| r.music_id == item.id).collect();
        assert_eq!(mine.len(), 1);
        assert_eq!(mine[0].play_count, 2);
        // limit=0 截断为空
        assert!(get_recent_played(0).unwrap().is_empty());

        let _ = delete_playlist(pl.id);
    }

    #[test]
    fn toggle_favorite_is_invertible_and_idempotent_pair() {
        let _serial = lock_db_test_serial();
        let tag = unique_tag();
        let dir = case_dir(&format!("fav_{tag}"));
        let pl = create_playlist(format!("收藏 {tag}")).unwrap();
        let item = import_music_file(
            pl.id.clone(),
            write_audio(dir.path(), "fav.mp3").to_string_lossy().into_owned(),
        )
        .unwrap();

        // 第一次 toggle 置真，第二次回到假：成对操作幂等
        assert!(toggle_favorite(item.id.clone()).unwrap());
        let stored: MusicItem =
            serde_json::from_str(&db_row(item_table(), &item.id).unwrap()).unwrap();
        assert!(stored.is_favorite);
        assert!(get_favorite_items().unwrap().iter().any(|i| i.id == item.id));

        assert!(!toggle_favorite(item.id.clone()).unwrap());
        let stored: MusicItem =
            serde_json::from_str(&db_row(item_table(), &item.id).unwrap()).unwrap();
        assert!(!stored.is_favorite);
        assert!(get_favorite_items().unwrap().iter().all(|i| i.id != item.id));

        // 非法 id 错误分支
        assert!(toggle_favorite(format!("ghost-{tag}")).is_err());

        let _ = delete_playlist(pl.id);
    }

    // ── 均衡器预设 ────────────────────────────────────────────────────────

    #[test]
    fn eq_presets_builtin_read_custom_write_delete() {
        let _serial = lock_db_test_serial();
        let tag = unique_tag();
        let presets = get_eq_presets().unwrap();
        for id in [
            "eq_flat",
            "eq_bass_boost",
            "eq_treble_boost",
            "eq_vocal",
            "eq_rock",
            "eq_classical",
        ] {
            assert!(presets.iter().any(|p| p.id == id), "内置预设 {id} 应存在");
            // 内置预设全部落库且 is_builtin=true
            let stored: EqualizerPreset =
                serde_json::from_str(&db_row(eq_preset_table(), id).expect("内置预设应落库"))
                    .unwrap();
            assert!(stored.is_builtin);
            assert_eq!(stored.bands.len(), 10);
        }

        // 频段数非法 → 拒绝
        assert!(save_eq_preset(format!("坏预设 {tag}"), vec![0.0; 9]).is_err());

        // 保存自定义预设：返回 + 落库 + API 可见
        let custom = save_eq_preset(format!("自定义 {tag}"), vec![1.0; 10]).unwrap();
        assert!(!custom.is_builtin);
        let stored: EqualizerPreset =
            serde_json::from_str(&db_row(eq_preset_table(), &custom.id).unwrap()).unwrap();
        assert_eq!(stored.name, format!("自定义 {tag}"));
        assert!(get_eq_presets().unwrap().iter().any(|p| p.id == custom.id));

        // 内置预设禁止删除
        assert!(delete_eq_preset("eq_flat".into()).is_err());

        // 删除自定义预设：DB 行消失
        assert!(delete_eq_preset(custom.id.clone()).unwrap());
        assert!(db_row(eq_preset_table(), &custom.id).is_none());
        assert!(get_eq_presets().unwrap().iter().all(|p| p.id != custom.id));
    }

    // ── 损坏数据容错 ──────────────────────────────────────────────────────

    #[test]
    fn corrupt_json_rows_are_skipped_not_panicked() {
        let _serial = lock_db_test_serial();
        let tag = unique_tag();
        let pl = create_playlist(format!("容错 {tag}")).unwrap();

        // 直接向底层表塞损坏 JSON
        db_module::db_set(playlist_table(), format!("corrupt_pl_{tag}"), "{ 不是JSON".into())
            .unwrap();
        db_module::db_set(item_table(), format!("corrupt_item_{tag}"), "[1,2,3".into()).unwrap();

        // 强制走 DB 重载：损坏行被静默过滤，正常行不受影响，不 panic
        invalidate_all_caches();
        let playlists = get_all_playlists().unwrap();
        assert!(playlists.iter().all(|p| p.id != format!("corrupt_pl_{tag}")));
        assert!(playlists.iter().any(|p| p.id == pl.id));

        let items = get_all_music_items().unwrap();
        assert!(items.iter().all(|i| i.id != format!("corrupt_item_{tag}")));

        // 清理损坏行，恢复缓存
        db_module::db_delete(playlist_table(), format!("corrupt_pl_{tag}")).unwrap();
        db_module::db_delete(item_table(), format!("corrupt_item_{tag}")).unwrap();
        invalidate_all_caches();
        let _ = delete_playlist(pl.id);
    }

    // ── 重启持久化 ────────────────────────────────────────────────────────

    #[test]
    fn data_survives_full_cache_reset_like_restart() {
        let _serial = lock_db_test_serial();
        let tag = unique_tag();
        let dir = case_dir(&format!("restart_{tag}"));

        // 造齐五类数据：目录、播放列表、条目、播放记录、自定义 EQ
        let folder = create_folder(format!("重启目录 {tag}"), None).unwrap();
        let pl =
            create_playlist_in_folder(format!("重启歌单 {tag}"), Some(folder.id.clone())).unwrap();
        let item = import_music_file(
            pl.id.clone(),
            write_audio(dir.path(), "alive.mp3").to_string_lossy().into_owned(),
        )
        .unwrap();
        toggle_favorite(item.id.clone()).unwrap();
        let record = record_play(item.id.clone()).unwrap();
        let preset = save_eq_preset(format!("重启预设 {tag}"), vec![2.0; 10]).unwrap();

        // 清空全部进程级缓存，模拟应用重启后冷启动
        invalidate_all_caches();

        assert!(get_all_folders().unwrap().iter().any(|f| f.id == folder.id));
        let loaded_pl = get_all_playlists()
            .unwrap()
            .into_iter()
            .find(|p| p.id == pl.id)
            .expect("播放列表应跨缓存重建存在");
        assert_eq!(loaded_pl.folder_id.as_deref(), Some(folder.id.as_str()));
        let loaded_items = get_all_music_items().unwrap();
        let loaded_item = loaded_items
            .iter()
            .find(|i| i.id == item.id)
            .expect("音乐条目应持久化");
        assert!(loaded_item.is_favorite, "收藏状态应从 DB 恢复");
        assert_eq!(get_playlist_items(pl.id.clone()).unwrap().len(), 1);
        assert!(get_recent_played(500).unwrap().iter().any(|r| r.id == record.id));
        assert!(get_eq_presets().unwrap().iter().any(|p| p.id == preset.id));

        // 清理
        let _ = delete_playlist(pl.id);
        let _ = delete_folder(folder.id);
        let _ = delete_eq_preset(preset.id);
    }

    // ── 路径映射（scanner.scan_path_mapping 的 api 转发）──────────────────

    #[test]
    fn scan_path_mapping_builds_classified_tree() {
        // 纯文件系统用例，不触碰 DB，无需串行锁
        let tag = unique_tag();
        let dir = case_dir(&format!("pathmap_{tag}"));
        let sub = dir.path().join("sub");
        fs::create_dir_all(&sub).unwrap();
        write_audio(&sub, "inner.flac");
        write_audio(dir.path(), "a.mp3");
        fs::write(dir.path().join("b.cue"), b"FILE \"a.mp3\" WAVE").unwrap();
        fs::write(dir.path().join("c.jpg"), b"fake jpeg").unwrap();
        fs::write(dir.path().join("d.txt"), b"plain").unwrap();
        fs::write(dir.path().join(".DS_Store"), b"hidden").unwrap();

        let root = scan_path_mapping(dir.path().to_string_lossy().into_owned()).unwrap();
        assert_eq!(root.name, dir.path().file_name().unwrap().to_str().unwrap());
        assert!(matches!(root.node_type, PathMappingNodeType::Directory));
        assert!(root.file_size.is_none(), "目录节点不应带文件大小");
        assert!(root.has_audio, "子树含音频，has_audio 应向上冒泡");
        assert_eq!(root.folder_id, None);

        // 排序规则：目录在前，文件按名排序；隐藏文件被跳过
        let names: Vec<&str> = root.children.iter().map(|c| c.name.as_str()).collect();
        assert_eq!(names, vec!["sub", "a.mp3", "b.cue", "c.jpg", "d.txt"]);

        // 子树结构：sub > inner.flac
        let sub_node = &root.children[0];
        assert!(sub_node.has_audio);
        assert_eq!(sub_node.children.len(), 1);
        assert_eq!(sub_node.children[0].name, "inner.flac");
        assert!(matches!(
            sub_node.children[0].node_type,
            PathMappingNodeType::AudioFile
        ));

        // 各文件类型分类正确 + file_size 落地
        let a = &root.children[1];
        assert!(matches!(a.node_type, PathMappingNodeType::AudioFile));
        assert_eq!(a.file_size, Some(15));
        assert!(a.has_audio);
        assert!(matches!(root.children[2].node_type, PathMappingNodeType::CueFile));
        assert!(!root.children[2].has_audio, "CUE 文件本身不算音频");
        assert!(matches!(root.children[3].node_type, PathMappingNodeType::ImageFile));
        assert!(matches!(root.children[4].node_type, PathMappingNodeType::OtherFile));

        // 纯空目录（无音频）has_audio=false
        let empty_dir = case_dir(&format!("pathmap_empty_{tag}"));
        let empty_root =
            scan_path_mapping(empty_dir.path().to_string_lossy().into_owned()).unwrap();
        assert!(!empty_root.has_audio);
        assert!(empty_root.children.is_empty());

        // 错误分支：不存在的路径 / 传入文件而非目录
        assert!(scan_path_mapping(format!("/nonexistent/{tag}")).is_err());
        let a_file = dir.path().join("a.mp3");
        assert!(scan_path_mapping(a_file.to_string_lossy().into_owned()).is_err());
    }
}

