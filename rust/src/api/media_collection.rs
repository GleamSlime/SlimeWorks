use flutter_rust_bridge::frb;

#[derive(Debug, Clone)]
pub enum MediaKind {
    Image,
    Video,
    Audio,
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
        media_collection::types::MediaKind::Audio => MediaKind::Audio,
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

// ── 智能文件夹 FFI ───────────────────────────────────────────────────────────

/// 智能文件夹数据（供 FFI 传输，字段与 Dart 端 SmartFolder 保持一致）。
#[derive(Debug, Clone)]
pub struct SmartFolderData {
    pub id: String,
    pub name: String,
    pub regex_pattern: String,
    /// 匹配目标字符串：collectionName | fileName
    pub regex_target: String,
    /// 文件类型过滤字符串：all | images | videos
    pub file_type_filter: String,
    pub target_folder_ids: Vec<String>,
}

fn to_smart_folder(data: SmartFolderData) -> media_collection::types::SmartFolder {
    media_collection::types::SmartFolder {
        id: data.id,
        name: data.name,
        regex_pattern: data.regex_pattern,
        regex_target: data.regex_target,
        file_type_filter: data.file_type_filter,
        target_folder_ids: data.target_folder_ids,
    }
}

fn from_smart_folder(sf: media_collection::types::SmartFolder) -> SmartFolderData {
    SmartFolderData {
        id: sf.id,
        name: sf.name,
        regex_pattern: sf.regex_pattern,
        regex_target: sf.regex_target,
        file_type_filter: sf.file_type_filter,
        target_folder_ids: sf.target_folder_ids,
    }
}

/// 从磁盘加载所有本地智能文件夹。
#[frb(sync)]
pub fn list_smart_folders() -> Vec<SmartFolderData> {
    media_collection::list_smart_folders()
        .into_iter()
        .map(from_smart_folder)
        .collect()
}

/// 将智能文件夹列表持久化到磁盘（全量覆盖）。
#[frb(sync)]
pub fn save_all_smart_folders(folders: Vec<SmartFolderData>) -> anyhow::Result<()> {
    media_collection::save_all_smart_folders(folders.into_iter().map(to_smart_folder).collect())
        .map_err(|e| anyhow::anyhow!(e))
}

// ── 集合排序 FFI ─────────────────────────────────────────────────────────────

/// 单条集合排序记录（orderKey → 有序 collectionId 列表）。
#[derive(Debug, Clone)]
pub struct CollectionOrder {
    pub key: String,
    pub ids: Vec<String>,
}

/// 加载所有集合排序记录。
#[frb(sync)]
pub fn load_all_collection_orders() -> Vec<CollectionOrder> {
    media_collection::load_all_collection_orders()
        .into_iter()
        .map(|(k, v)| CollectionOrder { key: k, ids: v })
        .collect()
}

/// 保存单条集合排序（ids 为空时删除该 key）。
#[frb(sync)]
pub fn save_collection_order(order_key: String, ids: Vec<String>) -> anyhow::Result<()> {
    media_collection::save_collection_order(order_key, ids)
        .map_err(|e| anyhow::anyhow!(e))
}

// ── 收藏 FFI ─────────────────────────────────────────────────────────────────

/// 加载收藏的集合 ID 列表。
#[frb(sync)]
pub fn load_media_favorites() -> Vec<String> {
    media_collection::load_media_favorites()
}

/// 保存收藏的集合 ID 列表。
#[frb(sync)]
pub fn save_media_favorites(ids: Vec<String>) -> anyhow::Result<()> {
    media_collection::save_media_favorites(ids).map_err(|e| anyhow::anyhow!(e))
}

// ── 集合文件物理转移 FFI ──────────────────────────────────────────────────────

/// 集合批量转移结果。
#[derive(Debug, Clone)]
pub struct TransferResult {
    pub success_count: u32,
    pub fail_count: u32,
}

/// 将指定集合的文件物理迁移到 `<target_root>/<container_name>/` 子目录，
/// 并在数据库中重新注册。Dart 侧负责通过文件选择器获取 `target_root`，
/// 核心文件 I/O 和数据库操作在 Rust 层完成。
pub fn transfer_collections(
    collection_ids: Vec<String>,
    target_root: String,
    container_name: String,
) -> anyhow::Result<TransferResult> {
    media_collection::transfer_collections(collection_ids, target_root, container_name)
        .map(|(success_count, fail_count)| TransferResult {
            success_count,
            fail_count,
        })
        .map_err(|e| anyhow::anyhow!(e))
}

