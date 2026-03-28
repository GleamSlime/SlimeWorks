use chrono::Utc;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};

use crate::scanner::MediaFolderScanner;
use crate::types::{MediaCollection, MediaFolder, MediaItem, MediaKind};

static MEDIA_COLLECTIONS: OnceLock<Arc<Mutex<Vec<MediaCollection>>>> = OnceLock::new();
static MEDIA_ITEMS: OnceLock<Arc<Mutex<Vec<MediaItem>>>> = OnceLock::new();
static MEDIA_FOLDERS: OnceLock<Arc<Mutex<Vec<MediaFolder>>>> = OnceLock::new();

fn normalize_folder_path(path: &Path) -> Result<String, String> {
    let normalized = std::fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
    Ok(normalized.to_string_lossy().to_string())
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
    db_module::db_set(folder_table_name(), folder.id.clone(), json).map_err(|error| error.to_string())
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

fn pick_cover_path(items: &[MediaItem]) -> Option<String> {
    items.iter()
        .find(|item| matches!(item.kind, MediaKind::Image))
        .or_else(|| items.first())
        .map(|item| item.file_path.clone())
}

fn upsert_collection_from_folder(folder_path: &str, recursive: bool) -> Result<MediaCollection, String> {
    let folder = PathBuf::from(folder_path);
    if !folder.exists() || !folder.is_dir() {
        return Err(format!("Path is not a directory: {}", folder_path));
    }

    let normalized_path = normalize_folder_path(&folder)?;

    let existing = {
        let collections = get_collections().lock().map_err(|error| error.to_string())?;
        collections
            .iter()
            .find(|collection| collection.folder_path == normalized_path)
            .cloned()
    };

    let collection_id = existing
        .as_ref()
        .map(|collection| collection.id.clone())
        .unwrap_or_else(|| format!("media_collection_{}", uuid::Uuid::new_v4()));

    let items = MediaFolderScanner::collect_media_items(&collection_id, &folder, recursive)
        .map_err(|error| error.to_string())?;
    if items.is_empty() {
        return Err("未在目标目录中发现图片或视频文件".to_string());
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
            persist_item(item)?;
        }
        stored_items.extend(items.iter().cloned());
    }

    let now = Utc::now();
    let updated_collection = MediaCollection {
        id: collection_id.clone(),
        title: existing
            .as_ref()
            .map(|collection| collection.title.clone())
            .unwrap_or_else(|| default_collection_title(&folder)),
        folder_path: normalized_path,
        folder_id: existing.as_ref().and_then(|collection| collection.folder_id.clone()),
        cover_path: pick_cover_path(&items),
        item_count: items.len(),
        created_at: existing
            .as_ref()
            .map(|collection| collection.created_at)
            .unwrap_or(now),
        updated_at: now,
    };

    {
        let mut collections = get_collections().lock().map_err(|error| error.to_string())?;
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
    Ok(updated_collection)
}

pub fn get_all_media_folders() -> Result<Vec<MediaFolder>, String> {
    let folders = get_folders().lock().map_err(|error| error.to_string())?;
    let mut result = folders.clone();
    result.sort_by(|left, right| left.order.cmp(&right.order).then_with(|| left.name.to_lowercase().cmp(&right.name.to_lowercase())));
    Ok(result)
}

pub fn get_child_media_folders(parent_id: String) -> Result<Vec<MediaFolder>, String> {
    let folders = get_folders().lock().map_err(|error| error.to_string())?;
    let mut result = folders
        .iter()
        .filter(|folder| folder.parent_id.as_deref() == Some(parent_id.as_str()))
        .cloned()
        .collect::<Vec<MediaFolder>>();
    result.sort_by(|left, right| left.order.cmp(&right.order).then_with(|| left.name.to_lowercase().cmp(&right.name.to_lowercase())));
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
        order: folders.iter().filter(|folder| folder.parent_id.is_none()).count() as i32,
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
        for child in folders.iter_mut().filter(|folder| folder.parent_id.as_deref() == Some(folder_id.as_str())) {
            child.parent_id = parent_id.clone();
            persist_folder(child)?;
        }
        parent_id
    };

    {
        let mut collections = get_collections().lock().map_err(|error| error.to_string())?;
        for collection in collections.iter_mut().filter(|collection| collection.folder_id.as_deref() == Some(folder_id.as_str())) {
            collection.folder_id = parent_id.clone();
            persist_collection(collection)?;
        }
    }

    delete_folder_from_db(&folder_id);
    Ok(true)
}

pub fn move_media_collection_to_folder(collection_id: String, folder_id: Option<String>) -> Result<bool, String> {
    let mut collections = get_collections().lock().map_err(|error| error.to_string())?;
    if let Some(collection) = collections.iter_mut().find(|collection| collection.id == collection_id) {
        collection.folder_id = folder_id;
        collection.updated_at = Utc::now();
        persist_collection(collection)?;
        Ok(true)
    } else {
        Ok(false)
    }
}

pub fn get_all_media_collections() -> Result<Vec<MediaCollection>, String> {
    let collections = get_collections().lock().map_err(|error| error.to_string())?;
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

pub fn import_media_folder(folder_path: String) -> Result<MediaCollection, String> {
    upsert_collection_from_folder(&folder_path, true)
}

pub fn scan_media_folders(folder_path: String) -> Result<Vec<MediaCollection>, String> {
    let directories = MediaFolderScanner::scan_media_directories(&folder_path)
        .map_err(|error| error.to_string())?;
    let mut collections = Vec::new();
    for directory in directories {
        match upsert_collection_from_folder(&directory.to_string_lossy(), false) {
            Ok(collection) => collections.push(collection),
            Err(error) => log::warn!("Failed to import media directory {:?}: {}", directory, error),
        }
    }
    collections.sort_by(|left, right| right.updated_at.cmp(&left.updated_at));
    Ok(collections)
}

pub fn rename_media_collection(collection_id: String, title: String) -> Result<bool, String> {
    let normalized_title = title.trim();
    if normalized_title.is_empty() {
        return Err("集合名称不能为空".to_string());
    }

    let mut collections = get_collections().lock().map_err(|error| error.to_string())?;
    if let Some(collection) = collections.iter_mut().find(|collection| collection.id == collection_id) {
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
        let mut collections = get_collections().lock().map_err(|error| error.to_string())?;
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