use flutter_rust_bridge::frb;

#[derive(Debug, Clone)]
pub enum MediaKind {
    Image,
    Video,
    Audio,
}

/// 注册 ffmpeg/ffprobe 可执行文件的绝对路径到 media_collection 模块。
/// 必须在应用启动时（RustLib.init 之后）调用，确保缩略图生成能找到 ffmpeg。
/// 若传入 None 则回退到系统 PATH 中的 "ffmpeg"/"ffprobe"。
#[frb(sync)]
pub fn register_ffmpeg_paths(ffmpeg_path: Option<String>, ffprobe_path: Option<String>) {
    // 落文件日志：Dart 侧 Loggers 只进内存环形缓冲、不写文件，
    // 注册结果否则完全不可观测（排查「用的是 brew 原生 arm64 版还是内置 Intel 版」只能靠猜）
    slime_logger::sw_info!(
        "[ffmpeg-path] 注册到 Rust | ffmpeg={:?} | ffprobe={:?}",
        ffmpeg_path,
        ffprobe_path
    );
    if let Some(p) = ffmpeg_path {
        media_collection::register_ffmpeg_path(p);
    }
    if let Some(p) = ffprobe_path {
        media_collection::register_ffprobe_path(p);
    }
}

/// 设置 Rust 端 ffmpeg 子进程的全局并发上限。
/// Flutter 端 mediaPrefs.concurrency 变更时调用，确保 ffmpeg 进程数不超过此值。
#[frb(sync)]
pub fn register_ffmpeg_concurrency(limit: u32) {
    media_collection::register_ffmpeg_concurrency(limit as usize);
}

/// 清理所有残留的 ffmpeg/ffprobe 子进程。应用退出时调用。
#[frb(sync)]
pub fn kill_all_ffmpeg_processes() {
    media_collection::kill_all_ffmpeg_processes();
}

/// 在集合目录树内搜索 `.SlimeWorks` 缓存目录。
/// 缓存目录建立在媒体文件实际所在目录旁（懒创建），不一定位于集合根目录。
/// 返回首个命中的路径；未命中返回 None。
#[frb(sync)]
pub fn find_collection_config_dir(root_dir: String) -> Option<String> {
    media_collection::find_collection_config_dir(root_dir)
}

/// 获取集合配置目录（`.SlimeWorks`），不存在时在集合根目录创建（Windows 下隐藏）。
/// 集合根目录不存在或创建失败时返回 None。
#[frb(sync)]
pub fn ensure_collection_config_dir(root_dir: String) -> Option<String> {
    media_collection::ensure_collection_config_dir(root_dir)
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

// 异步：FRB 在后台线程池执行，避免大数据集反序列化阻塞 Dart UI 线程
pub fn get_all_media_collections() -> anyhow::Result<Vec<MediaCollection>> {
    let collections =
        media_collection::get_all_media_collections().map_err(|error| anyhow::anyhow!(error))?;
    Ok(collections.into_iter().map(convert_collection).collect())
}

// 异步：FRB 在后台线程池执行，避免阻塞 UI
pub fn get_all_media_folders() -> anyhow::Result<Vec<MediaFolder>> {
    let folders =
        media_collection::get_all_media_folders().map_err(|error| anyhow::anyhow!(error))?;
    Ok(folders.into_iter().map(convert_folder).collect())
}

// 异步：FRB 在后台线程池执行
pub fn get_child_media_folders(parent_id: String) -> anyhow::Result<Vec<MediaFolder>> {
    let folders = media_collection::get_child_media_folders(parent_id)
        .map_err(|error| anyhow::anyhow!(error))?;
    Ok(folders.into_iter().map(convert_folder).collect())
}

// 异步：FRB 在后台线程池执行，避免大量 item 反序列化阻塞 UI
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

/// 重新扫描已导入集合的物理目录，增量同步磁盘变动（不做"已导入"拦截）。
pub fn rescan_media_folder(folder_path: String) -> anyhow::Result<MediaCollection> {
    let collection = media_collection::rescan_media_folder(folder_path)
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

/// 清空本地媒体库：单事务清空所有业务表（保留 media_meta 迁移标记），
/// 同时清空内存缓存。不删除原始媒体文件。可选清理磁盘缩略图缓存。
/// 返回 (清空表数, 已清理缓存文件数)。
#[frb(sync)]
pub fn clear_all_local_media(
    clear_app_thumbnail_cache: bool,
    clear_resource_thumbnail_cache: bool,
) -> anyhow::Result<(u32, u32)> {
    media_collection::clear_all_local_media(
        clear_app_thumbnail_cache,
        clear_resource_thumbnail_cache,
    )
    .map_err(|e| anyhow::anyhow!(e))
}

/// 缩略图任务持久化记录（用于重启后恢复未完成任务）。
#[derive(Debug, Clone)]
pub struct ThumbnailTaskInfo {
    pub file_path: String,
    pub width: u32,
    pub status: String,
    pub retries: u32,
    pub updated_at: i64,
}

/// 获取所有未完成的缩略图任务（pending/running/failed 全部）。
/// 应用启动时调用此函数，将未完成任务重新入队到 Flutter 端 VideoThumbQueue。
/// failed 状态也会重新入队，让用户能重新尝试生成。
// 异步：FRB 在后台线程池执行，避免阻塞启动流程的 UI 渲染
pub fn get_all_pending_thumbnail_tasks() -> anyhow::Result<Vec<ThumbnailTaskInfo>> {
    let tasks = media_collection::get_all_pending_thumbnail_tasks()
        .map_err(|e| anyhow::anyhow!(e))?;
    Ok(tasks
        .into_iter()
        .map(|t| ThumbnailTaskInfo {
            file_path: t.file_path,
            width: t.width,
            status: t.status,
            retries: t.retries,
            updated_at: t.updated_at,
        })
        .collect())
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
/// 异步（非 sync）：FRB 会在后台线程池执行，避免大图解码阻塞 Dart UI 线程；
/// 调用方需 await，不可依赖同步返回。
pub fn ensure_cover_thumbnail(file_path: String, width: u32) -> Option<String> {
    media_collection::ensure_cover_thumbnail(file_path, width)
}

/// 只查不生成：该文件在指定宽度下的缩略图缓存是否已就绪。
///
/// 上层在入队前用它过滤掉"文件没变、封面已在"的集合与条目，
/// 使「重新导入」「重新扫描封面」在无变动时不再产生任务。
/// 纯 stat 级别操作，不解码不落盘，可安全高频调用。
/// 就绪时返回缓存路径（可直接用于显示）；音频"无内嵌封面"负缓存命中时返回 None。
pub fn ready_cover_thumbnail_path(file_path: String, width: u32) -> Option<String> {
    media_collection::ready_cover_thumbnail_path(file_path, width)
}

/// Return size + file-path list for every local collection in one pass.
/// Replaces the N-calls pattern in `_computeCollectionSizesAsync`.
// 异步：FRB 在后台线程池执行，单次批量返回所有集合的 size + file_paths
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

/// Batch-check whether each file path exists on the local filesystem.
/// Returns a `Vec<bool>` aligned with the input — `true` means the file exists.
// 异步：FRB 在后台线程池执行，避免大量文件存在性检查阻塞 UI
pub fn check_paths_exist(paths: Vec<String>) -> Vec<bool> {
    media_collection::check_paths_exist(paths)
}

/// FFI version of [media_collection::CollectionLiveStats].
pub struct CollectionLiveStats {
    pub collection_id: String,
    pub live_size: u64,
    pub live_count: u32,
}

/// 每个集合「磁盘上仍然存在」的资源体积与条数（失效资源不计）。
// 异步：全库逐文件 stat，必须离开 Dart UI 线程
pub fn get_all_collection_live_stats() -> anyhow::Result<Vec<CollectionLiveStats>> {
    media_collection::get_all_collection_live_stats()
        .map(|stats| {
            stats
                .into_iter()
                .map(|s| CollectionLiveStats {
                    collection_id: s.collection_id,
                    live_size: s.live_size,
                    live_count: s.live_count,
                })
                .collect()
        })
        .map_err(|error| anyhow::anyhow!(error))
}

/// Lightweight per-collection counts (no file paths), for polling file-count changes.
// 异步：FRB 在后台线程池执行
pub fn get_all_collection_counts() -> anyhow::Result<Vec<CollectionCount>> {
    media_collection::get_all_collection_counts()
        .map(|counts| {
            counts
                .into_iter()
                .map(CollectionCount::from_inner)
                .collect()
        })
        .map_err(|e| anyhow::anyhow!(e))
}

/// FFI version of [media_collection::CollectionCount].
pub struct CollectionCount {
    pub collection_id: String,
    pub item_count: u32,
    pub total_size: u64,
}

impl CollectionCount {
    fn from_inner(c: media_collection::CollectionCount) -> Self {
        Self {
            collection_id: c.collection_id,
            item_count: c.item_count,
            total_size: c.total_size,
        }
    }
}

/// Extract evenly-spaced scrub frames from a video file.
pub fn extract_video_scrub_frames(
    video_path: String,
    frame_count: u32,
) -> anyhow::Result<Vec<String>> {
    media_collection::extract_video_scrub_frames(video_path, frame_count)
        .map_err(|e| anyhow::anyhow!(e))
}

// ── 文件操作 FFI 绑定 ────────────────────────────────────────────────────────

/// 删除单个媒体文件的物理文件，然后重新导入集合目录以同步数据库。
#[frb(sync)]
pub fn delete_media_item_file(item_file_path: String) -> anyhow::Result<bool> {
    media_collection::delete_media_item_file(item_file_path).map_err(|e| anyhow::anyhow!(e))
}

/// 删除集合内所有媒体文件的物理文件，返回已删除的文件数量。
#[frb(sync)]
pub fn delete_collection_local_files(collection_id: String) -> anyhow::Result<u32> {
    media_collection::delete_collection_local_files(collection_id)
        .map(|c| c as u32)
        .map_err(|e| anyhow::anyhow!(e))
}

/// 将集合物理转移到目标目录。
pub fn transfer_collections(
    collection_ids: Vec<String>,
    target_dir: String,
) -> anyhow::Result<u32> {
    media_collection::transfer_collections(collection_ids, target_dir)
        .map(|c| c as u32)
        .map_err(|e| anyhow::anyhow!(e))
}

/// 打开文件所在目录（跨平台）。
pub fn open_in_file_manager(file_path: String) -> anyhow::Result<()> {
    media_collection::open_in_file_manager(file_path).map_err(|e| anyhow::anyhow!(e))
}

// ── 集合排序 FFI 绑定 ────────────────────────────────────────────────────────

/// 获取所有集合排序记录。
// 异步：FRB 在后台线程池执行
pub fn get_all_collection_orders() -> anyhow::Result<Vec<(String, Vec<String>)>> {
    media_collection::get_all_collection_orders().map_err(|e| anyhow::anyhow!(e))
}

/// 保存集合排序。
#[frb(sync)]
pub fn save_collection_order(order_key: String, ids: Vec<String>) -> anyhow::Result<()> {
    media_collection::save_collection_order(order_key, ids).map_err(|e| anyhow::anyhow!(e))
}

// ── 收藏集合 FFI 绑定 ────────────────────────────────────────────────────────

/// 获取收藏集合 ID 列表。
// 异步：FRB 在后台线程池执行
pub fn get_favorite_collection_ids() -> anyhow::Result<Vec<String>> {
    media_collection::get_favorite_collection_ids().map_err(|e| anyhow::anyhow!(e))
}

/// 保存收藏集合 ID 列表。
#[frb(sync)]
pub fn save_favorite_collection_ids(ids: Vec<String>) -> anyhow::Result<()> {
    media_collection::save_favorite_collection_ids(ids).map_err(|e| anyhow::anyhow!(e))
}

// ── 智能文件夹 FFI 绑定 ──────────────────────────────────────────────────────

/// 正则匹配目标
#[derive(Debug, Clone)]
pub enum SmartFolderRegexTarget {
    CollectionName,
    FileName,
}

/// 文件类型过滤
#[derive(Debug, Clone)]
pub enum SmartFolderFileType {
    All,
    Images,
    Videos,
}

/// 智能文件夹
#[derive(Debug, Clone)]
pub struct SmartFolderInfo {
    pub id: String,
    pub name: String,
    pub regex_pattern: String,
    pub keywords: Vec<String>,
    pub regex_target: SmartFolderRegexTarget,
    pub file_type_filter: SmartFolderFileType,
    pub target_folder_ids: Vec<String>,
}

fn convert_smart_folder(sf: media_collection::types::SmartFolder) -> SmartFolderInfo {
    SmartFolderInfo {
        id: sf.id,
        name: sf.name,
        regex_pattern: sf.regex_pattern,
        keywords: sf.keywords,
        regex_target: match sf.regex_target {
            media_collection::types::SmartFolderRegexTarget::CollectionName => {
                SmartFolderRegexTarget::CollectionName
            }
            media_collection::types::SmartFolderRegexTarget::FileName => {
                SmartFolderRegexTarget::FileName
            }
        },
        file_type_filter: match sf.file_type_filter {
            media_collection::types::SmartFolderFileType::All => SmartFolderFileType::All,
            media_collection::types::SmartFolderFileType::Images => SmartFolderFileType::Images,
            media_collection::types::SmartFolderFileType::Videos => SmartFolderFileType::Videos,
        },
        target_folder_ids: sf.target_folder_ids,
    }
}

#[frb(sync)]
pub fn get_all_smart_folders() -> anyhow::Result<Vec<SmartFolderInfo>> {
    let sfs = media_collection::get_all_smart_folders().map_err(|e| anyhow::anyhow!(e))?;
    Ok(sfs.into_iter().map(convert_smart_folder).collect())
}

#[frb(sync)]
pub fn create_smart_folder(
    name: String,
    regex_pattern: String,
    keywords: Vec<String>,
    regex_target: String,
    file_type_filter: String,
    target_folder_ids: Vec<String>,
) -> anyhow::Result<SmartFolderInfo> {
    let sf = media_collection::create_smart_folder(
        name,
        regex_pattern,
        keywords,
        regex_target,
        file_type_filter,
        target_folder_ids,
    )
    .map_err(|e| anyhow::anyhow!(e))?;
    Ok(convert_smart_folder(sf))
}

#[frb(sync)]
pub fn update_smart_folder(
    id: String,
    name: String,
    regex_pattern: String,
    keywords: Vec<String>,
    regex_target: String,
    file_type_filter: String,
    target_folder_ids: Vec<String>,
) -> anyhow::Result<SmartFolderInfo> {
    let sf = media_collection::update_smart_folder(
        id,
        name,
        regex_pattern,
        keywords,
        regex_target,
        file_type_filter,
        target_folder_ids,
    )
    .map_err(|e| anyhow::anyhow!(e))?;
    Ok(convert_smart_folder(sf))
}

#[frb(sync)]
pub fn delete_smart_folder(id: String) -> anyhow::Result<bool> {
    media_collection::delete_smart_folder(id).map_err(|e| anyhow::anyhow!(e))
}

// ── 视频/音频振幅（波形）────────────────────────────────────────────────────
//
// 设计要点（对应用户诉求）：
// 1. 缓存落在**资源旁** `<资源目录>/.SlimeWorks/waveform/<文件名>.w<bins>.json`，
//    随资源目录一起移动/共享，而不是塞进各自机器的应用数据目录。
// 2. 远程节点在**节点侧**算：客户端只取回几 KB 的 JSON，绝不再把整段视频
//    拉到本地跑 ffmpeg —— 移动端走远程节点时那是致命的流量与耗时。
// 3. 只查不生成的读取口（read_video_waveform）与生成口（ensure_video_waveform）
//    分开，导入/重扫时用后者补齐，预览时用前者优先命中。

/// 资源旁的波形缓存文件路径：`<父目录>/.SlimeWorks/waveform/<文件名>.w<bins>.json`。
fn waveform_cache_path(file_path: &str, bins: u32) -> Option<std::path::PathBuf> {
    let src = std::path::Path::new(file_path);
    let parent = src.parent()?;
    let name = src.file_name()?.to_string_lossy();
    if name.is_empty() {
        return None;
    }
    Some(
        parent
            .join(".SlimeWorks")
            .join("waveform")
            .join(format!("{}.w{}.json", name, bins)),
    )
}

/// 缓存内容带源文件身份（size|mtime）：文件被替换后缓存自动失效。
fn waveform_identity(meta: &std::fs::Metadata) -> String {
    let mtime = meta
        .modified()
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_secs())
        .unwrap_or(0);
    format!("{}|{}", meta.len(), mtime)
}

/// 只查不生成：读取已缓存的波形。没有缓存 / 源文件已变 / bins 不符 → 返回 None。
///
/// 纯读盘，不解码、不起子进程，可安全高频调用（预览打开时先走这条）。
pub fn read_video_waveform(file_path: String, bins: u32) -> Option<Vec<f64>> {
    let cache = waveform_cache_path(&file_path, bins)?;
    let raw = std::fs::read_to_string(&cache).ok()?;
    let value: serde_json::Value = serde_json::from_str(&raw).ok()?;
    // 身份校验：文件换了就不能用旧波形
    let meta = std::fs::metadata(&file_path).ok()?;
    if value.get("identity").and_then(|v| v.as_str()) != Some(waveform_identity(&meta).as_str()) {
        return None;
    }
    if value.get("bins").and_then(|v| v.as_u64()) != Some(bins as u64) {
        return None;
    }
    let arr = value.get("data")?.as_array()?;
    let out: Vec<f64> = arr.iter().filter_map(|v| v.as_f64()).collect();
    if out.len() == bins as usize {
        Some(out)
    } else {
        None
    }
}

/// 该文件是否已有可用的波形缓存（导入/重扫时用来决定要不要补算）。
#[frb(sync)]
pub fn has_video_waveform(file_path: String, bins: u32) -> bool {
    read_video_waveform(file_path, bins).is_some()
}

/// 生成（或读缓存）视频/音频的振幅数组，归一化到 0~1，长度 = bins。
///
/// 优先 symphonia 流式解码（内存只留 bins 个峰值）；解不了的容器/编码回退
/// ffmpeg 输出 8kHz 单声道 PCM，边读边折叠峰值，绝不把整段 PCM 读进内存。
/// 结果写入资源旁 `.SlimeWorks/waveform/`，下次（含节点重启、换客户端）直接命中。
pub fn ensure_video_waveform(file_path: String, bins: u32) -> anyhow::Result<Vec<f64>> {
    let bins = bins.clamp(64, 4096);
    if let Some(cached) = read_video_waveform(file_path.clone(), bins) {
        return Ok(cached);
    }
    let meta = std::fs::metadata(&file_path)
        .map_err(|e| anyhow::anyhow!("源文件不可读: {}", e))?;
    let identity = waveform_identity(&meta);

    // ① symphonia：常见 MP4/MP3/FLAC 直接命中，最快
    let peaks = match crate::api::music_player::extract_waveform_for_media(file_path.clone(), bins) {
        Ok(v) if v.len() == bins as usize && v.iter().any(|x| *x > 0.0) => Some(v),
        _ => None,
    };
    // ② ffmpeg 兜底：symphonia 解不了的（部分 MKV/WMV/TS 等）
    let peaks = match peaks {
        Some(v) => v,
        None => extract_waveform_via_ffmpeg(&file_path, bins)
            .ok_or_else(|| anyhow::anyhow!("无法从该文件提取音频振幅"))?,
    };
    let normalized = normalize_waveform(peaks);

    // 落盘（失败不影响本次返回：只读盘等场景下拿不到缓存也能用）
    if let Some(cache) = waveform_cache_path(&file_path, bins) {
        if let Some(dir) = cache.parent() {
            if std::fs::create_dir_all(dir).is_ok() {
                let payload = serde_json::json!({
                    "identity": identity,
                    "bins": bins,
                    "data": normalized,
                });
                if let Ok(text) = serde_json::to_string(&payload) {
                    let _ = std::fs::write(&cache, text);
                }
            }
        }
    }
    Ok(normalized)
}

/// 按全局峰值归一化到 0~1，并轻微抬升中小音量段（gamma 0.85）。
///
/// 用户的验收点是"能显著看出哪里高声"：不归一的话整段低音量的片子会糊成
/// 一排矮条；纯线性又让安静对白几乎看不见，故用 <1 的指数抬中段、高声段仍顶满。
fn normalize_waveform(peaks: Vec<f64>) -> Vec<f64> {
    let max = peaks.iter().cloned().fold(0.0f64, f64::max);
    if max <= 1e-6 {
        return vec![0.05; peaks.len()];
    }
    let scale = 1.0 / max;
    peaks
        .iter()
        .map(|v| (v * scale).powf(0.85).clamp(0.0, 1.0))
        .collect()
}

/// ffmpeg 兜底提取：8kHz 单声道 s16le 走管道，边读边折叠成 bins 个峰值。
fn extract_waveform_via_ffmpeg(file_path: &str, bins: u32) -> Option<Vec<f64>> {
    use std::io::Read;
    use std::process::{Command, Stdio};

    let mut child = Command::new(media_collection::ffmpeg_cmd())
        .args([
            "-v", "quiet",
            "-i", file_path,
            "-vn",
            "-f", "s16le",
            "-ac", "1",
            "-acodec", "pcm_s16le",
            "-ar", "8000",
            "-",
        ])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .ok()?;

    let mut stdout = child.stdout.take()?;
    // 每 250 个样本（约 31ms）折一个峰值，再聚合到 bins
    const BLOCK_SAMPLES: usize = 250;
    let mut block = vec![0u8; BLOCK_SAMPLES * 2];
    let mut block_peaks: Vec<f64> = Vec::new();
    let mut used = 0usize;
    loop {
        match stdout.read(&mut block[used..]) {
            Ok(0) => break,
            Ok(n) => {
                used += n;
                if used == block.len() {
                    let mut peak = 0i32;
                    for chunk in block.chunks_exact(2) {
                        let s = i16::from_le_bytes([chunk[0], chunk[1]]).unsigned_abs() as i32;
                        if s > peak {
                            peak = s;
                        }
                    }
                    block_peaks.push(peak as f64 / 32768.0);
                    used = 0;
                }
            }
            Err(_) => break,
        }
    }
    let _ = child.wait();
    if block_peaks.is_empty() {
        return None;
    }
    Some(resample_peaks(&block_peaks, bins as usize))
}

/// 把任意长度的峰值序列重采样到 bins 个（每段取最大值，保住高声段不被平均掉）。
fn resample_peaks(peaks: &[f64], bins: usize) -> Vec<f64> {
    if peaks.len() == bins {
        return peaks.to_vec();
    }
    let mut out = vec![0.0f64; bins];
    for (i, slot) in out.iter_mut().enumerate() {
        let start = i * peaks.len() / bins;
        let end = ((i + 1) * peaks.len() / bins).max(start + 1).min(peaks.len());
        *slot = peaks[start..end].iter().cloned().fold(0.0f64, f64::max);
    }
    out
}

#[cfg(test)]
mod waveform_tests {
    use super::*;

    /// 每个用例独立临时目录，避免并发互相踩踏
    fn temp_dir(tag: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "slime_waveform_{}_{}",
            tag,
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn cache_path_sits_beside_resource() {
        // 缓存必须落在资源旁（随资源目录移动/共享），不是应用数据目录
        let p = waveform_cache_path("/media/movies/a.mp4", 1200).unwrap();
        assert_eq!(
            p,
            std::path::Path::new("/media/movies/.SlimeWorks/waveform/a.mp4.w1200.json")
        );
    }

    #[test]
    fn cache_path_separates_bins() {
        // 不同颗粒度是两份缓存，互不覆盖
        let a = waveform_cache_path("/m/a.mp4", 480).unwrap();
        let b = waveform_cache_path("/m/a.mp4", 1200).unwrap();
        assert_ne!(a, b);
    }

    #[test]
    fn read_returns_none_without_cache_and_never_generates() {
        let dir = temp_dir("read_empty");
        let src = dir.join("a.mp4");
        std::fs::write(&src, b"not-a-real-video").unwrap();
        let src_str = src.to_string_lossy().to_string();

        assert!(read_video_waveform(src_str.clone(), 1200).is_none());
        // 只读接口绝不能顺手生成缓存
        let cache = waveform_cache_path(&src_str, 1200).unwrap();
        assert!(!cache.exists(), "read_video_waveform 不得产生任何文件");

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn read_roundtrip_and_identity_invalidation() {
        let dir = temp_dir("roundtrip");
        let src = dir.join("a.mp4");
        std::fs::write(&src, b"payload-v1").unwrap();
        let src_str = src.to_string_lossy().to_string();
        let bins = 8u32;

        // 手工写一份合法缓存，验证读取与身份校验
        let cache = waveform_cache_path(&src_str, bins).unwrap();
        std::fs::create_dir_all(cache.parent().unwrap()).unwrap();
        let identity = waveform_identity(&std::fs::metadata(&src).unwrap());
        let data: Vec<f64> = (0..bins).map(|i| i as f64 / bins as f64).collect();
        std::fs::write(
            &cache,
            serde_json::json!({"identity": identity, "bins": bins, "data": data}).to_string(),
        )
        .unwrap();

        let got = read_video_waveform(src_str.clone(), bins).expect("应命中缓存");
        assert_eq!(got.len(), bins as usize);
        assert!((got[4] - data[4]).abs() < 1e-9);

        // bins 不符 → 不命中
        assert!(read_video_waveform(src_str.clone(), bins + 1).is_none());

        // 源文件被替换（身份变了）→ 缓存自动失效
        std::fs::write(&src, b"payload-v2-longer").unwrap();
        assert!(
            read_video_waveform(src_str, bins).is_none(),
            "源文件变了旧波形必须失效"
        );

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn normalize_keeps_relative_loudness_and_floor() {
        // 全局峰值归一化：最大值顶到 1，相对响度保留
        let out = normalize_waveform(vec![0.0, 0.25, 0.5, 1.0]);
        assert!((out[3] - 1.0).abs() < 1e-9);
        assert!(out[2] > out[1] && out[1] > out[0]);
        // 全零输入不能产出全零（否则波形整排看不见），给最低高度
        let silent = normalize_waveform(vec![0.0, 0.0, 0.0]);
        assert!(silent.iter().all(|v| *v > 0.0));
    }

    #[test]
    fn resample_preserves_peaks_not_average() {
        // 每段取最大值：高声段不能被平均掉（这是"看出哪里高声"的关键）
        let peaks = vec![0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.8, 0.0];
        let out = resample_peaks(&peaks, 2);
        assert_eq!(out.len(), 2);
        assert!((out[0] - 1.0).abs() < 1e-9);
        assert!((out[1] - 0.8).abs() < 1e-9);
        // 等长时原样返回
        assert_eq!(resample_peaks(&peaks, peaks.len()), peaks);
    }
}
