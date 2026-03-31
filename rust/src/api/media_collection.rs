use flutter_rust_bridge::frb;

#[derive(Debug, Clone)]
pub enum MediaKind {
    Image,
    Video,
}

#[derive(Debug, Clone)]
pub struct MediaCollection {
    pub id: String,
    pub title: String,
    pub folder_path: String,
    pub folder_id: Option<String>,
    pub cover_path: Option<String>,
    pub item_count: usize,
    pub created_at: i64,
    pub updated_at: i64,
}

#[derive(Debug, Clone)]
pub struct MediaFolder {
    pub id: String,
    pub name: String,
    pub created_at: i64,
    pub order: i32,
    pub parent_id: Option<String>,
}

#[derive(Debug, Clone)]
pub struct MediaItem {
    pub id: String,
    pub collection_id: String,
    pub title: String,
    pub file_path: String,
    pub kind: MediaKind,
    pub file_size: u64,
    pub modified_at: i64,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub duration_ms: Option<u64>,
    pub order: i32,
}

fn convert_kind(kind: media_collection::types::MediaKind) -> MediaKind {
    match kind {
        media_collection::types::MediaKind::Image => MediaKind::Image,
        media_collection::types::MediaKind::Video => MediaKind::Video,
    }
}

fn convert_collection(collection: media_collection::types::MediaCollection) -> MediaCollection {
    MediaCollection {
        id: collection.id,
        title: collection.title,
        folder_path: collection.folder_path,
        folder_id: collection.folder_id,
        cover_path: collection.cover_path,
        item_count: collection.item_count,
        created_at: collection.created_at.timestamp(),
        updated_at: collection.updated_at.timestamp(),
    }
}

fn convert_folder(folder: media_collection::types::MediaFolder) -> MediaFolder {
    MediaFolder {
        id: folder.id,
        name: folder.name,
        created_at: folder.created_at.timestamp(),
        order: folder.order,
        parent_id: folder.parent_id,
    }
}

fn convert_item(item: media_collection::types::MediaItem) -> MediaItem {
    MediaItem {
        id: item.id,
        collection_id: item.collection_id,
        title: item.title,
        file_path: item.file_path,
        kind: convert_kind(item.kind),
        file_size: item.file_size,
        modified_at: item.modified_at.timestamp(),
        width: item.width,
        height: item.height,
        duration_ms: item.duration_ms,
        order: item.order,
    }
}

#[frb(sync)]
pub fn get_all_media_collections() -> anyhow::Result<Vec<MediaCollection>> {
    let collections =
        media_collection::get_all_media_collections().map_err(|error| anyhow::anyhow!(error))?;
    Ok(collections.into_iter().map(convert_collection).collect())
}

#[frb(sync)]
pub fn get_all_media_folders() -> anyhow::Result<Vec<MediaFolder>> {
    let folders =
        media_collection::get_all_media_folders().map_err(|error| anyhow::anyhow!(error))?;
    Ok(folders.into_iter().map(convert_folder).collect())
}

#[frb(sync)]
pub fn get_child_media_folders(parent_id: String) -> anyhow::Result<Vec<MediaFolder>> {
    let folders = media_collection::get_child_media_folders(parent_id)
        .map_err(|error| anyhow::anyhow!(error))?;
    Ok(folders.into_iter().map(convert_folder).collect())
}

#[frb(sync)]
pub fn get_media_collection_items(collection_id: String) -> anyhow::Result<Vec<MediaItem>> {
    let items = media_collection::get_media_collection_items(collection_id)
        .map_err(|error| anyhow::anyhow!(error))?;
    Ok(items.into_iter().map(convert_item).collect())
}

pub fn import_media_folder(folder_path: String) -> anyhow::Result<MediaCollection> {
    let collection = media_collection::import_media_folder(folder_path)
        .map_err(|error| anyhow::anyhow!(error))?;
    Ok(convert_collection(collection))
}

pub fn scan_media_folders(folder_path: String) -> anyhow::Result<Vec<MediaCollection>> {
    let collections = media_collection::scan_media_folders(folder_path)
        .map_err(|error| anyhow::anyhow!(error))?;
    Ok(collections.into_iter().map(convert_collection).collect())
}

#[frb(sync)]
pub fn create_media_folder(name: String) -> anyhow::Result<MediaFolder> {
    let folder =
        media_collection::create_media_folder(name).map_err(|error| anyhow::anyhow!(error))?;
    Ok(convert_folder(folder))
}

#[frb(sync)]
pub fn create_child_media_folder(name: String, parent_id: String) -> anyhow::Result<MediaFolder> {
    let folder = media_collection::create_child_media_folder(name, parent_id)
        .map_err(|error| anyhow::anyhow!(error))?;
    Ok(convert_folder(folder))
}

#[frb(sync)]
pub fn rename_media_collection(collection_id: String, title: String) -> anyhow::Result<bool> {
    media_collection::rename_media_collection(collection_id, title)
        .map_err(|error| anyhow::anyhow!(error))
}

#[frb(sync)]
pub fn move_media_collection_to_folder(
    collection_id: String,
    folder_id: Option<String>,
) -> anyhow::Result<bool> {
    media_collection::move_media_collection_to_folder(collection_id, folder_id)
        .map_err(|error| anyhow::anyhow!(error))
}

#[frb(sync)]
pub fn rename_media_folder(folder_id: String, name: String) -> anyhow::Result<bool> {
    media_collection::rename_media_folder(folder_id, name).map_err(|error| anyhow::anyhow!(error))
}

#[frb(sync)]
pub fn delete_media_folder(folder_id: String) -> anyhow::Result<bool> {
    media_collection::delete_media_folder(folder_id).map_err(|error| anyhow::anyhow!(error))
}

#[frb(sync)]
pub fn delete_media_collection(collection_id: String) -> anyhow::Result<bool> {
    media_collection::delete_media_collection(collection_id).map_err(|error| anyhow::anyhow!(error))
}

/// Aggregated per-collection stats returned in a single batch FFI call.
#[derive(Debug, Clone)]
pub struct CollectionStats {
    pub collection_id: String,
    pub total_size: u64,
    pub file_paths: Vec<String>,
}

/// Generate (or serve from disk cache) a JPEG thumbnail for `file_path` at
/// `width` pixels wide.  Returns the path to the cached thumbnail, or `None`
/// on failure (unsupported format, decode error, etc.).
/// Resolution strategy: ffmpeg first (supports HEIC/AVIF), then pure-Rust
/// `image` crate as fallback.
#[frb(sync)]
pub fn ensure_cover_thumbnail(file_path: String, width: u32) -> Option<String> {
    media_collection::ensure_cover_thumbnail(file_path, width)
}

/// Return size + file-path list for every local collection in one pass.
/// Replaces the N-calls pattern in `_computeCollectionSizesAsync`.
#[frb(sync)]
pub fn get_all_collection_stats() -> anyhow::Result<Vec<CollectionStats>> {
    let stats =
        media_collection::get_all_collection_stats().map_err(|error| anyhow::anyhow!(error))?;
    Ok(stats
        .into_iter()
        .map(|s| CollectionStats {
            collection_id: s.collection_id,
            total_size: s.total_size,
            file_paths: s.file_paths,
        })
        .collect())
}
