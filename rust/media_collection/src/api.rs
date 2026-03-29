use chrono::Utc;
use std::collections::HashMap;
use std::path::Path;
use std::sync::{Arc, Mutex, OnceLock};

use crate::scanner::MediaFolderScanner;
use crate::types::{MediaCollection, MediaFolder, MediaItem, MediaKind};

static MEDIA_COLLECTIONS: OnceLock<Arc<Mutex<Vec<MediaCollection>>>> = OnceLock::new();
static MEDIA_ITEMS: OnceLock<Arc<Mutex<Vec<MediaItem>>>> = OnceLock::new();
static MEDIA_FOLDERS: OnceLock<Arc<Mutex<Vec<MediaFolder>>>> = OnceLock::new();
/// Caches the DB initialization result: None = success, Some(msg) = failure.
static DB_INIT_RESULT: OnceLock<Option<String>> = OnceLock::new();

/// Returns the platform-specific default base dir for app data.
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

/// Returns the platform-specific default path for the media DB file.
fn default_db_path() -> String {
    let dir = std::path::Path::new(&app_data_base()).join("SlimeWorks");
    let _ = std::fs::create_dir_all(&dir);
    dir.join("media.db").to_string_lossy().into_owned()
}

/// Returns the directory used for video thumbnails / scrub frames.
fn thumbnail_cache_dir() -> std::path::PathBuf {
    let dir = std::path::Path::new(&app_data_base())
        .join("SlimeWorks")
        .join("thumbnails");
    let _ = std::fs::create_dir_all(&dir);
    dir
}

/// Initialise the DB exactly once.  Returns the error string on failure.
/// Exposed publicly so Dart can call it explicitly at startup.
pub fn initialize_db() -> Result<(), String> {
    let result = DB_INIT_RESULT.get_or_init(|| {
        let path = default_db_path();
        log::info!("[media_db] Initializing DB at: {}", path);
        match db_module::db_init(path) {
            Ok(_) => {
                log::info!("[media_db] DB initialized successfully");
                None
            }
            Err(e) => {
                log::error!("[media_db] DB init failed: {}", e);
                Some(e)
            }
        }
    });
    match result {
        None => Ok(()),
        Some(e) => Err(e.clone()),
    }
}

/// Ensures the DB is initialized (idempotent, no-op after first call).
fn ensure_db_initialized() {
    let _ = initialize_db();
}

/// Simple FNV-1a hash for deriving a stable short key from a path string.
fn path_key(path: &str) -> String {
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for b in path.bytes() {
        hash ^= b as u64;
        hash = hash.wrapping_mul(0x100_0000_01b3);
    }
    format!("{:016x}", hash)
}

/// Try to extract a single thumbnail frame from `video_path` using the system
/// ffmpeg binary.  The frame is cached at `thumbnails/{id}.jpg` and the path
/// returned on success.
fn try_extract_video_thumbnail(video_path: &str, thumb_id: &str) -> Option<String> {
    let dir = thumbnail_cache_dir();
    let out = dir.join(format!("{}.jpg", thumb_id));
    if out.exists() {
        return Some(out.to_string_lossy().into_owned());
    }
    let out_str = out.to_string_lossy().into_owned();
    // Try progressively earlier seek positions in case the video is short.
    for seek in &["00:00:10", "00:00:03", "00:00:00"] {
        let ok = std::process::Command::new("ffmpeg")
            .args([
                "-i", video_path, "-ss", seek, "-vframes", "1", "-q:v", "3", "-y", &out_str,
            ])
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status()
            .map(|s| s.success())
            .unwrap_or(false);
        if ok && out.exists() {
            return Some(out_str);
        }
    }
    None
}

/// Use ffprobe to get the video duration in seconds.
fn video_duration_secs(video_path: &str) -> Option<f64> {
    let out = std::process::Command::new("ffprobe")
        .args([
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "default=noprint_wrappers=1:nokey=1",
            video_path,
        ])
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null())
        .output()
        .ok()?;
    String::from_utf8_lossy(&out.stdout)
        .trim()
        .parse::<f64>()
        .ok()
}

/// Extract `frame_count` evenly-spaced frames from a video using system ffmpeg.
/// Frames are cached in `thumbnails/scrub/<path_key>/frame_NN.jpg`.
/// Returns the list of frame file paths that were successfully created.
pub fn extract_video_scrub_frames(
    video_path: String,
    frame_count: u32,
) -> Result<Vec<String>, String> {
    let n = (frame_count.max(2)) as usize;
    let key = path_key(&video_path);
    let frame_dir = thumbnail_cache_dir().join("scrub").join(&key);

    // Return cached frames if they all exist.
    let cached: Vec<String> = (0..n)
        .map(|i| {
            frame_dir
                .join(format!("frame_{:02}.jpg", i))
                .to_string_lossy()
                .into_owned()
        })
        .collect();
    if cached.iter().all(|p| std::path::Path::new(p).exists()) {
        return Ok(cached);
    }
    let _ = std::fs::create_dir_all(&frame_dir);

    let duration = video_duration_secs(&video_path).unwrap_or(60.0).max(1.0);
    let mut paths = Vec::new();
    for i in 0..n {
        let t = duration * i as f64 / (n - 1) as f64;
        let secs = t as u64;
        let seek = format!(
            "{:02}:{:02}:{:02}",
            secs / 3600,
            (secs % 3600) / 60,
            secs % 60
        );
        let out = frame_dir.join(format!("frame_{:02}.jpg", i));
        let out_str = out.to_string_lossy().into_owned();
        let ok = std::process::Command::new("ffmpeg")
            .args([
                "-i",
                &video_path,
                "-ss",
                &seek,
                "-vframes",
                "1",
                "-vf",
                "scale=320:-1",
                "-q:v",
                "5",
                "-y",
                &out_str,
            ])
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status()
            .map(|s| s.success())
            .unwrap_or(false);
        if ok && out.exists() {
            paths.push(out_str);
        }
    }
    if paths.is_empty() {
        Err("ffmpeg not available or failed to extract frames".to_string())
    } else {
        Ok(paths)
    }
}

fn normalize_folder_path(path: &Path) -> Result<String, String> {
    let canonical = std::fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
    let s = canonical.to_string_lossy().into_owned();
    // Windows canonicalize adds \\?\ prefix – strip it for consistent storage/comparison
    #[cfg(windows)]
    let s = s
        .strip_prefix("\\\\?\\")
        .map(|v| v.to_string())
        .unwrap_or(s);
    Ok(s)
}

fn collection_table_name() -> String {
    "media_collections".to_string()
}

fn item_table_name() -> String {
    "media_items".to_string()
}

fn folder_table_name() -> String {
    "media_folders".to_string()
}

fn get_collections() -> &'static Arc<Mutex<Vec<MediaCollection>>> {
    MEDIA_COLLECTIONS.get_or_init(|| {
        ensure_db_initialized();
        let collections = Arc::new(Mutex::new(Vec::new()));
        let _ = db_module::db_register_table(collection_table_name());
        if let Ok(records) = db_module::db_list_all(collection_table_name()) {
            if let Ok(mut guard) = collections.lock() {
                for record in records {
                    if let Ok(collection) = serde_json::from_str::<MediaCollection>(&record.value) {
                        guard.push(collection);
                    }
                }
            }
        }
        collections
    })
}

fn get_items() -> &'static Arc<Mutex<Vec<MediaItem>>> {
    MEDIA_ITEMS.get_or_init(|| {
        ensure_db_initialized();
        let items = Arc::new(Mutex::new(Vec::new()));
        let _ = db_module::db_register_table(item_table_name());
        if let Ok(records) = db_module::db_list_all(item_table_name()) {
            if let Ok(mut guard) = items.lock() {
                for record in records {
                    if let Ok(item) = serde_json::from_str::<MediaItem>(&record.value) {
                        guard.push(item);
                    }
                }
            }
        }
        items
    })
}

fn get_folders() -> &'static Arc<Mutex<Vec<MediaFolder>>> {
    MEDIA_FOLDERS.get_or_init(|| {
        ensure_db_initialized();
        let folders = Arc::new(Mutex::new(Vec::new()));
        let _ = db_module::db_register_table(folder_table_name());
        if let Ok(records) = db_module::db_list_all(folder_table_name()) {
            if let Ok(mut guard) = folders.lock() {
                for record in records {
                    if let Ok(folder) = serde_json::from_str::<MediaFolder>(&record.value) {
                        guard.push(folder);
                    }
                }
            }
        }
        folders
    })
}

fn persist_collection(collection: &MediaCollection) -> Result<(), String> {
    let json = serde_json::to_string(collection).map_err(|error| error.to_string())?;
    db_module::db_set(collection_table_name(), collection.id.clone(), json)
        .map_err(|error| error.to_string())
}

fn persist_item(item: &MediaItem) -> Result<(), String> {
    let json = serde_json::to_string(item).map_err(|error| error.to_string())?;
    db_module::db_set(item_table_name(), item.id.clone(), json).map_err(|error| error.to_string())
}

fn persist_folder(folder: &MediaFolder) -> Result<(), String> {
    let json = serde_json::to_string(folder).map_err(|error| error.to_string())?;
    db_module::db_set(folder_table_name(), folder.id.clone(), json)
        .map_err(|error| error.to_string())
}

fn delete_item_from_db(item_id: &str) {
    let _ = db_module::db_delete(item_table_name(), item_id.to_string());
}

fn delete_collection_from_db(collection_id: &str) {
    let _ = db_module::db_delete(collection_table_name(), collection_id.to_string());
}

fn delete_folder_from_db(folder_id: &str) {
    let _ = db_module::db_delete(folder_table_name(), folder_id.to_string());
}

fn default_collection_title(path: &Path) -> String {
    path.file_name()
        .and_then(|value| value.to_str())
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "未命名集合".to_string())
}

/// Choose cover: prefer first image item; fall back to first video path.
/// Actual video thumbnail generation happens lazily from the Dart side.
fn pick_cover_path(items: &[MediaItem]) -> Option<String> {
    items
        .iter()
        .find(|item| matches!(item.kind, MediaKind::Image))
        .or_else(|| items.first())
        .map(|item| item.file_path.clone())
}

fn upsert_collection_from_folder(
    folder: &Path,
    recursive: bool,
) -> Result<MediaCollection, String> {
    log::debug!(
        "[media_scan] upsert_collection_from_folder: {:?} (recursive={})",
        folder,
        recursive
    );
    if !folder.exists() || !folder.is_dir() {
        let err = format!("Path is not a directory: {:?}", folder);
        log::warn!("[media_scan] {}", err);
        return Err(err);
    }

    let normalized_path = normalize_folder_path(folder)?;
    log::debug!("[media_scan] normalized_path = {:?}", normalized_path);

    let existing = {
        let collections = get_collections()
            .lock()
            .map_err(|error| error.to_string())?;
        collections
            .iter()
            .find(|collection| collection.folder_path == normalized_path)
            .cloned()
    };

    let collection_id = existing
        .as_ref()
        .map(|collection| collection.id.clone())
        .unwrap_or_else(|| format!("media_collection_{}", uuid::Uuid::new_v4()));

    let items = MediaFolderScanner::collect_media_items(&collection_id, folder, recursive)
        .map_err(|error| error.to_string())?;
    log::debug!(
        "[media_scan] collect_media_items returned {} items for {:?}",
        items.len(),
        folder
    );
    if items.is_empty() {
        let err = format!("No media found in {:?}", folder);
        log::warn!("[media_scan] {}", err);
        return Err(err);
    }

    {
        let mut stored_items = get_items().lock().map_err(|error| error.to_string())?;
        let removed_ids = stored_items
            .iter()
            .filter(|item| item.collection_id == collection_id)
            .map(|item| item.id.clone())
            .collect::<Vec<String>>();
        stored_items.retain(|item| item.collection_id != collection_id);
        for item_id in removed_ids {
            delete_item_from_db(&item_id);
        }
        for item in &items {
            if let Err(error) = persist_item(item) {
                log::warn!(
                    "[media_scan] persist_item failed for {:?}: {}",
                    item.file_path,
                    error
                );
            }
        }
        stored_items.extend(items.iter().cloned());
    }

    let now = Utc::now();
    let updated_collection = MediaCollection {
        id: collection_id.clone(),
        title: existing
            .as_ref()
            .map(|collection| collection.title.clone())
            .unwrap_or_else(|| default_collection_title(folder)),
        folder_path: normalized_path,
        folder_id: existing
            .as_ref()
            .and_then(|collection| collection.folder_id.clone()),
        cover_path: pick_cover_path(&items),
        item_count: items.len(),
        created_at: existing
            .as_ref()
            .map(|collection| collection.created_at)
            .unwrap_or(now),
        updated_at: now,
    };

    {
        let mut collections = get_collections()
            .lock()
            .map_err(|error| error.to_string())?;
        if let Some(existing_collection) = collections
            .iter_mut()
            .find(|collection| collection.id == updated_collection.id)
        {
            *existing_collection = updated_collection.clone();
        } else {
            collections.push(updated_collection.clone());
        }
    }
    persist_collection(&updated_collection)?;
    log::debug!(
        "[media_scan] collection persisted: id={} title={:?} item_count={}",
        updated_collection.id,
        updated_collection.title,
        updated_collection.item_count
    );
    Ok(updated_collection)
}

pub fn get_all_media_folders() -> Result<Vec<MediaFolder>, String> {
    let folders = get_folders().lock().map_err(|error| error.to_string())?;
    let mut result = folders.clone();
    result.sort_by(|left, right| {
        left.order
            .cmp(&right.order)
            .then_with(|| left.name.to_lowercase().cmp(&right.name.to_lowercase()))
    });
    Ok(result)
}

pub fn get_child_media_folders(parent_id: String) -> Result<Vec<MediaFolder>, String> {
    let folders = get_folders().lock().map_err(|error| error.to_string())?;
    let mut result = folders
        .iter()
        .filter(|folder| folder.parent_id.as_deref() == Some(parent_id.as_str()))
        .cloned()
        .collect::<Vec<MediaFolder>>();
    result.sort_by(|left, right| {
        left.order
            .cmp(&right.order)
            .then_with(|| left.name.to_lowercase().cmp(&right.name.to_lowercase()))
    });
    Ok(result)
}

pub fn create_media_folder(name: String) -> Result<MediaFolder, String> {
    let normalized_name = name.trim();
    if normalized_name.is_empty() {
        return Err("文件夹名称不能为空".to_string());
    }

    let mut folders = get_folders().lock().map_err(|error| error.to_string())?;
    let folder = MediaFolder {
        id: format!("media_folder_{}", uuid::Uuid::new_v4()),
        name: normalized_name.to_string(),
        created_at: Utc::now(),
        order: folders
            .iter()
            .filter(|folder| folder.parent_id.is_none())
            .count() as i32,
        parent_id: None,
    };
    folders.push(folder.clone());
    persist_folder(&folder)?;
    Ok(folder)
}

pub fn create_child_media_folder(name: String, parent_id: String) -> Result<MediaFolder, String> {
    let normalized_name = name.trim();
    if normalized_name.is_empty() {
        return Err("文件夹名称不能为空".to_string());
    }

    let mut folders = get_folders().lock().map_err(|error| error.to_string())?;
    let folder = MediaFolder {
        id: format!("media_folder_{}", uuid::Uuid::new_v4()),
        name: normalized_name.to_string(),
        created_at: Utc::now(),
        order: folders
            .iter()
            .filter(|folder| folder.parent_id.as_deref() == Some(parent_id.as_str()))
            .count() as i32,
        parent_id: Some(parent_id),
    };
    folders.push(folder.clone());
    persist_folder(&folder)?;
    Ok(folder)
}

pub fn rename_media_folder(folder_id: String, name: String) -> Result<bool, String> {
    let normalized_name = name.trim();
    if normalized_name.is_empty() {
        return Err("文件夹名称不能为空".to_string());
    }

    let mut folders = get_folders().lock().map_err(|error| error.to_string())?;
    if let Some(folder) = folders.iter_mut().find(|folder| folder.id == folder_id) {
        folder.name = normalized_name.to_string();
        persist_folder(folder)?;
        Ok(true)
    } else {
        Ok(false)
    }
}

pub fn delete_media_folder(folder_id: String) -> Result<bool, String> {
    let parent_id = {
        let mut folders = get_folders().lock().map_err(|error| error.to_string())?;
        let parent_id = folders
            .iter()
            .find(|folder| folder.id == folder_id)
            .and_then(|folder| folder.parent_id.clone());
        let previous_len = folders.len();
        folders.retain(|folder| folder.id != folder_id);
        if folders.len() == previous_len {
            return Ok(false);
        }
        for child in folders
            .iter_mut()
            .filter(|folder| folder.parent_id.as_deref() == Some(folder_id.as_str()))
        {
            child.parent_id = parent_id.clone();
            persist_folder(child)?;
        }
        parent_id
    };

    {
        let mut collections = get_collections()
            .lock()
            .map_err(|error| error.to_string())?;
        for collection in collections
            .iter_mut()
            .filter(|collection| collection.folder_id.as_deref() == Some(folder_id.as_str()))
        {
            collection.folder_id = parent_id.clone();
            persist_collection(collection)?;
        }
    }

    delete_folder_from_db(&folder_id);
    Ok(true)
}

pub fn move_media_collection_to_folder(
    collection_id: String,
    folder_id: Option<String>,
) -> Result<bool, String> {
    let mut collections = get_collections()
        .lock()
        .map_err(|error| error.to_string())?;
    if let Some(collection) = collections
        .iter_mut()
        .find(|collection| collection.id == collection_id)
    {
        collection.folder_id = folder_id;
        collection.updated_at = Utc::now();
        persist_collection(collection)?;
        Ok(true)
    } else {
        Ok(false)
    }
}

pub fn get_all_media_collections() -> Result<Vec<MediaCollection>, String> {
    let collections = get_collections()
        .lock()
        .map_err(|error| error.to_string())?;
    let mut result = collections.clone();
    result.sort_by(|left, right| {
        right
            .updated_at
            .cmp(&left.updated_at)
            .then_with(|| left.title.to_lowercase().cmp(&right.title.to_lowercase()))
    });
    Ok(result)
}

pub fn get_media_collection_items(collection_id: String) -> Result<Vec<MediaItem>, String> {
    let items = get_items().lock().map_err(|error| error.to_string())?;
    let mut result = items
        .iter()
        .filter(|item| item.collection_id == collection_id)
        .cloned()
        .collect::<Vec<MediaItem>>();
    result.sort_by(|left, right| {
        left.order
            .cmp(&right.order)
            .then_with(|| left.title.to_lowercase().cmp(&right.title.to_lowercase()))
    });
    Ok(result)
}

/// Aggregated per-collection stats: total file size and all file paths.
/// Used by the Dart layer to populate size/path caches in a single FFI call
/// instead of calling `get_media_collection_items` once per collection.
pub struct CollectionStats {
    pub collection_id: String,
    pub total_size: u64,
    pub file_paths: Vec<String>,
}

/// Return size + file-path list for every collection in one pass over MEDIA_ITEMS.
pub fn get_all_collection_stats() -> Result<Vec<CollectionStats>, String> {
    let items = get_items().lock().map_err(|e| e.to_string())?;
    let mut map: HashMap<String, CollectionStats> = HashMap::new();
    for item in items.iter() {
        let entry = map
            .entry(item.collection_id.clone())
            .or_insert_with(|| CollectionStats {
                collection_id: item.collection_id.clone(),
                total_size: 0,
                file_paths: Vec::new(),
            });
        entry.total_size += item.file_size;
        entry.file_paths.push(item.file_path.clone());
    }
    Ok(map.into_values().collect())
}

pub fn import_media_folder(folder_path: String) -> Result<MediaCollection, String> {
    upsert_collection_from_folder(Path::new(&folder_path), true)
}

pub fn scan_media_folders(folder_path: String) -> Result<Vec<MediaCollection>, String> {
    let root = Path::new(&folder_path);
    log::info!("[media_scan] scan_media_folders called: {:?}", root);
    log::info!(
        "[media_scan] root.exists()={} root.is_dir()={}",
        root.exists(),
        root.is_dir()
    );
    let directories = MediaFolderScanner::scan_media_directories(root).map_err(|error| {
        log::error!("[media_scan] scan_media_directories error: {}", error);
        error.to_string()
    })?;
    log::info!(
        "[media_scan] scan_media_directories found {} dirs with media under {:?}",
        directories.len(),
        root
    );
    for (i, dir) in directories.iter().enumerate() {
        log::info!("[media_scan]   dir[{}] = {:?}", i, dir);
    }
    let mut collections = Vec::new();
    for directory in &directories {
        match upsert_collection_from_folder(directory, false) {
            Ok(collection) => {
                log::info!(
                    "scan_media_folders: imported '{}' from {:?}",
                    collection.title,
                    directory
                );
                collections.push(collection);
            }
            Err(error) => log::warn!("scan_media_folders: failed {:?}: {}", directory, error),
        }
    }
    log::info!(
        "scan_media_folders: result {}/{} collections imported",
        collections.len(),
        directories.len()
    );
    collections.sort_by(|left, right| right.updated_at.cmp(&left.updated_at));
    Ok(collections)
}

pub fn rename_media_collection(collection_id: String, title: String) -> Result<bool, String> {
    let normalized_title = title.trim();
    if normalized_title.is_empty() {
        return Err("集合名称不能为空".to_string());
    }

    let mut collections = get_collections()
        .lock()
        .map_err(|error| error.to_string())?;
    if let Some(collection) = collections
        .iter_mut()
        .find(|collection| collection.id == collection_id)
    {
        collection.title = normalized_title.to_string();
        collection.updated_at = Utc::now();
        persist_collection(collection)?;
        Ok(true)
    } else {
        Ok(false)
    }
}

pub fn delete_media_collection(collection_id: String) -> Result<bool, String> {
    {
        let mut collections = get_collections()
            .lock()
            .map_err(|error| error.to_string())?;
        let previous_len = collections.len();
        collections.retain(|collection| collection.id != collection_id);
        if collections.len() == previous_len {
            return Ok(false);
        }
    }

    {
        let mut items = get_items().lock().map_err(|error| error.to_string())?;
        let removed_ids = items
            .iter()
            .filter(|item| item.collection_id == collection_id)
            .map(|item| item.id.clone())
            .collect::<Vec<String>>();
        items.retain(|item| item.collection_id != collection_id);
        for item_id in removed_ids {
            delete_item_from_db(&item_id);
        }
    }

    delete_collection_from_db(&collection_id);
    Ok(true)
}
