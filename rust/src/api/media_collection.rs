use flutter_rust_bridge::frb;

/// 封面就绪状态三态（FRB 导出）。
///
/// 这里**重新定义**而不是复用 media_collection 的同名类型：FRB 只扫描
/// `crate::api` 下的类型，crate 外来的 enum 会被降级成不透明的
/// `RustOpaqueInterface`（Dart 侧无法 switch、拿不到字段）。
///
/// 用「状态码 + 可选路径」的扁平结构，而不是 `Ready { path }` 这种带字段的
/// enum 变体：后者会让 FRB 要求 Dart 侧引入 freezed（本项目没有这个依赖，
/// 为一个三态判定加整套代码生成不划算）。扁平结构生成的 plain class
/// 在 Dart 侧判断同样直接。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CoverReadiness {
    /// 状态码：`ready` / `no_cover` / `pending` / `missing`
    pub status: String,
    /// `status == "ready"` 时的封面缓存路径，其余状态为 None
    pub path: Option<String>,
}

impl CoverReadiness {
    fn ready(path: String) -> Self {
        Self {
            status: "ready".to_string(),
            path: Some(path),
        }
    }
    fn no_cover() -> Self {
        Self {
            status: "no_cover".to_string(),
            path: None,
        }
    }
    fn pending() -> Self {
        Self {
            status: "pending".to_string(),
            path: None,
        }
    }
    fn missing() -> Self {
        Self {
            status: "missing".to_string(),
            path: None,
        }
    }
}

impl From<media_collection::CoverReadiness> for CoverReadiness {
    fn from(value: media_collection::CoverReadiness) -> Self {
        match value {
            media_collection::CoverReadiness::Ready { path } => CoverReadiness::ready(path),
            media_collection::CoverReadiness::NoCover => CoverReadiness::no_cover(),
            media_collection::CoverReadiness::Pending => CoverReadiness::pending(),
            media_collection::CoverReadiness::Missing => CoverReadiness::missing(),
        }
    }
}

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

// CollectionStats / get_all_collection_stats 已删除：整表冷加载 + 全量路径
// 跨 FFI 传输的遗留死接口，生产链路无人调用。体积读聚合小表
// （get_cached_collection_live_stats），路径按集合懒查（get_collection_file_paths）。

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

/// 批量版：一次 FFI 判定一整批文件的封面就绪状态（三态）。
///
/// 为什么要有它：单个版每个文件要跨语言往返一次，调用方还要再调一次
/// `ensure_cover_thumbnail`，一个目录几十个音频就是上百次往返。
/// 实测导入后封面队列的平均出图间隔被拖到 75 秒（真正抽帧只需 2.7 秒），
/// 大头全耗在这些空转调用上。
///
/// 三态（对应 [media_collection::CoverReadiness]）：
/// - `Ready{path}` 磁盘已有封面，直接显示，不要再入队；
/// - `NoCover`     音频确定没有内嵌封面（负缓存命中），永远拿不到，别再排队；
/// - `Pending`     还没生成，需要走生成路径；
/// - `Missing`     源文件不存在。
pub fn cover_readiness_batch(file_paths: Vec<String>, width: u32) -> Vec<CoverReadiness> {
    media_collection::cover_readiness_batch(file_paths, width)
        .into_iter()
        .map(CoverReadiness::from)
        .collect()
}

// get_all_collection_stats FFI 导出已删除（遗留死接口，理由见上方注释）。

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

/// 缓存版集合统计行：recorded 为库内记录值，live_* 为最近一次后台 stat 的
/// 现存结论（None = 从未 stat 过，调用方退回记录值口径）。
pub struct CachedCollectionStats {
    pub collection_id: String,
    pub recorded_size: u64,
    pub live_size: Option<u64>,
    pub live_count: Option<u32>,
}

/// 读缓存版现存统计：只查聚合小表（毫秒级），数据过期时 Rust 侧自动起
/// 后台线程补全量 stat。客户端进媒体库的读路径，替代每次全量逐文件 stat。
// 异步：旧库首次补齐可能要冷加载条目表，必须离开 Dart UI 线程
pub fn get_cached_collection_live_stats() -> anyhow::Result<Vec<CachedCollectionStats>> {
    media_collection::get_cached_collection_live_stats()
        .map(|aggregates| {
            aggregates
                .into_iter()
                .map(|a| CachedCollectionStats {
                    collection_id: a.collection_id,
                    recorded_size: a.recorded_size,
                    live_size: a.live_size,
                    live_count: a.live_count,
                })
                .collect()
        })
        .map_err(|error| anyhow::anyhow!(error))
}

/// 按需取单个集合的文件路径快照（文件名智能文件夹/深度搜索/悬停预览用）。
/// 优先查聚合行；旧库未回填时退回条目表现算并落册。
// 异步：兜底路径可能冷加载条目表
pub fn get_collection_file_paths(collection_id: String) -> anyhow::Result<Vec<String>> {
    media_collection::get_collection_file_paths(collection_id).map_err(|error| anyhow::anyhow!(error))
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
/// 返回成功转移的集合数（保留旧签名；需要失败数请用
/// [transfer_collections_with_stats]）。
pub fn transfer_collections(
    collection_ids: Vec<String>,
    target_dir: String,
) -> anyhow::Result<u32> {
    media_collection::transfer_collections(collection_ids, target_dir)
        .map(|c| c as u32)
        .map_err(|e| anyhow::anyhow!(e))
}

/// 集合转移的结果：成功数与失败数分开上报。
///
/// 旧接口只返回成功数，且历史上把「重新导入失败」也计入成功——用户看到
/// 「成功转移 N 个」却找不到任何东西。上层据此区分「全部成功 / 部分失败」。
pub struct TransferOutcome {
    pub success_count: u32,
    pub fail_count: u32,
}

/// 将集合物理转移到目标目录，同时上报成功与失败数量。
pub fn transfer_collections_with_stats(
    collection_ids: Vec<String>,
    target_dir: String,
) -> anyhow::Result<TransferOutcome> {
    media_collection::transfer_collections_with_stats(collection_ids, target_dir)
        .map(|outcome| TransferOutcome {
            success_count: outcome.success_count,
            fail_count: outcome.fail_count,
        })
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

/// 读智能文件夹列表。
/// 异步：内部 get_smart_folders 首次访问要等 initialize_db（SMB 卷唤醒/磁盘忙时
/// 秒级），sync FFI 会把整个 Dart UI isolate 卡住——实测进媒体库首屏因此白等
/// 8~12 秒（日志时间线：onInitAsync 00:34:31 → 智能文件夹加载完成 00:34:43）。
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

/// 返回给上层的「该文件没有音轨」标记文案。
/// Dart 侧据此把它和「真故障」区分开：前者不必重试、不必提示失败。
pub const WAVE_NONE_AUDIO_MARKER: &str = "该文件没有音轨";

/// 该文件是否真的含有音频流。用于「两条链路都解不出」时判断是
/// 「本来就没音轨」还是「有音轨但解坏了/环境异常」——只有前者才值得记负缓存。
fn has_audio_stream(file_path: &str) -> bool {
    let output = std::process::Command::new(media_collection::ffprobe_cmd())
        .args([
            "-v",
            "error",
            "-select_streams",
            "a",
            "-show_entries",
            "stream=index",
            "-of",
            "csv=p=0",
            file_path,
        ])
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null())
        .output();
    match output {
        // 有音频流时 ffprobe 会输出流索引（如 "1"）；空输出 = 没有音轨。
        // 探测本身失败（ffprobe 缺失等）一律当作「有音轨」，避免误记负缓存。
        Ok(out) => !String::from_utf8_lossy(&out.stdout).trim().is_empty(),
        Err(_) => true,
    }
}

/// 波形 dB 动态范围的**上限**（dB）。
///
/// 实际使用的跨度由本片自身的 min/max 量出来（见 normalize_waveform），
/// 这个常量只在两种情况下兜底：
/// - 素材几乎全平（跨度 <1dB）时避免把噪声放大成一片花纹；
/// - 素材含完全静音（min≈0，算不出跨度）时退化成固定范围。
///
/// 取 20 而不是常见的 45~60：输入是**每段的 RMS 能量**不是采样瞬时峰值，
/// RMS 已被平均过，同一部片内通常只跨 10~20 dB；用 45 dB 去铺会把安静段
/// 推到 0.6 以上，看上去还是一排差不多高的柱子。
const DB_RANGE: f64 = 20.0;

/// 波形柱的最低显示高度（占满格的比例）：极静处仍保留一条可见的细线。
const MIN_BAR: f64 = 0.02;

/// 波形算法版本。改动归一化/映射算法时递增，旧缓存会自动失效重算。
///
/// 缓存里带这个字段。历史上踩过两次：
/// - v1「峰值拉满 + gamma 0.85」：响段一排齐平顶到天花板；
/// - v2 只换 dB 轴但聚合仍取 max：一个 bin 覆盖几秒音频时 100% 的柱子被
///   单个瞬态顶满，依旧是平的。
/// 不失效的话用户升级后看到的还是旧图，会以为没修好，故每次改算法都 +1。
const WAVEFORM_ALGO_VERSION: u32 = 3;

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

/// 只查不生成：读取已缓存的波形。没有缓存 / 源文件已变 / bins 不符 /
/// 算法版本过期 → 返回 None。
///
/// 纯读盘，不解码、不起子进程，可安全高频调用（预览打开时先走这条）。
pub fn read_video_waveform(file_path: String, bins: u32) -> Option<Vec<f64>> {
    let cache = waveform_cache_path(&file_path, bins)?;
    let raw = std::fs::read_to_string(&cache).ok()?;
    let value: serde_json::Value = serde_json::from_str(&raw).ok()?;
    // 算法版本校验：旧算法算出来的图看着"都差不多高"，必须重算
    if value.get("algo").and_then(|v| v.as_u64()) != Some(WAVEFORM_ALGO_VERSION as u64) {
        return None;
    }
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

/// 「该文件没有音轨」的负缓存标记路径：
/// `<父目录>/.SlimeWorks/waveform/<文件名>.noaudio`。
///
/// 为什么要它：GIF 转出来的 mp4、纯画面录屏这类文件**根本没有音频流**，
/// 补波形注定失败。但每次导入/重扫都会对它们重新走一遍探测
/// （symphonia 建解码器 + ffmpeg 兜底起子进程），日志里刷一片
/// 「振幅补齐失败（下次预览再试）」，白耗 CPU 且永远不可能成功。
/// 用负缓存把「没有音轨」这个结论钉住：按文件身份（size|mtime）判断，
/// 文件被替换（补了音轨）自动失效、重新探测。
/// `noaudio` 与 `w<bins>.json` 分开：后者是数据，前者是结论。
fn waveform_no_audio_marker_path(file_path: &str) -> Option<std::path::PathBuf> {
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
            .join(format!("{}.noaudio", name)),
    )
}

/// 进程内「无音轨」缓存（源文件路径 → 身份），避免每次都读盘。
static WAVEFORM_NO_AUDIO: std::sync::OnceLock<
    std::sync::Mutex<std::collections::HashMap<String, String>>,
> = std::sync::OnceLock::new();

fn waveform_no_audio_map(
) -> &'static std::sync::Mutex<std::collections::HashMap<String, String>> {
    WAVEFORM_NO_AUDIO.get_or_init(|| std::sync::Mutex::new(std::collections::HashMap::new()))
}

/// 该文件是否已被判定「没有音轨」（进程内或资源旁标记，身份一致才算）。
fn waveform_known_no_audio(file_path: &str, identity: &str) -> bool {
    let map = waveform_no_audio_map()
        .lock()
        .unwrap_or_else(|e| e.into_inner());
    if map.get(file_path).map(String::as_str) == Some(identity) {
        return true;
    }
    drop(map);
    let Some(marker) = waveform_no_audio_marker_path(file_path) else {
        return false;
    };
    let Ok(recorded) = std::fs::read_to_string(&marker) else {
        return false;
    };
    let hit = recorded.trim() == identity;
    if hit {
        waveform_no_audio_map()
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .insert(file_path.to_string(), identity.to_string());
    }
    hit
}

/// 记下「该文件没有音轨」，落盘标记供跨重启复用。写失败不影响正确性。
fn record_waveform_no_audio(file_path: &str, identity: &str) {
    waveform_no_audio_map()
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .insert(file_path.to_string(), identity.to_string());
    let Some(marker) = waveform_no_audio_marker_path(file_path) else {
        return;
    };
    let Some(dir) = marker.parent() else {
        return;
    };
    if std::fs::create_dir_all(dir).is_err() {
        return;
    }
    let _ = std::fs::write(&marker, identity);
}

/// 该文件是不是「已知没有音轨」——导入/重扫前批量查，命中就完全不排波形任务。
///
/// 纯 stat + 读标记，不解码不起进程；但**必须异步**：SMB/外置卷上 stat 是
/// 网络往返（卷休眠时秒级），sync FFI 在 Dart 主线程执行，重扫循环里逐条目
/// 调用会把整个 UI 卡死（实测鼠标转圈 App 无响应）。
pub fn video_waveform_absent(file_path: String) -> bool {
    let Ok(meta) = std::fs::metadata(&file_path) else {
        // 文件不在：当作"没有"，别再排任务（真回来了下次导入会重新进来）
        return true;
    };
    waveform_known_no_audio(&file_path, &waveform_identity(&meta))
}

/// 波形解码并发闸门：最多 2 路同时解码。
///
/// 为什么 Rust 侧也要一道（Dart VideoWaveformService 已有一道）：
/// 节点服务器（node_server）也会调 ensure_video_waveform 给远程客户端算波形，
/// 那条路不经过 Dart 服务层的闸门。FRB 默认线程池大小 = CPU 核数，
/// 超大视频（几 GB / 几小时）整段音频解码是分钟级重活，不设闸就会把池占满，
/// 封面生成（同池的 ensureCoverThumbnail / extractVideoScrubFrames）全部排队。
/// 实测：8 路 symphonia 解码占满池后，封面队列 123/190 停滞 6 分钟。
/// 波形是后台补齐（预览才用），封面是用户立刻可见的，算力优先给封面。
static WAVEFORM_DECODE_PERMITS: std::sync::OnceLock<(std::sync::Mutex<usize>, std::sync::Condvar)> =
    std::sync::OnceLock::new();

const WAVEFORM_MAX_CONCURRENT: usize = 2;

struct WaveformPermit;
impl Drop for WaveformPermit {
    fn drop(&mut self) {
        if let Some((lock, cvar)) = WAVEFORM_DECODE_PERMITS.get() {
            let mut count = lock.lock().unwrap_or_else(|e| e.into_inner());
            *count = count.saturating_sub(1);
            cvar.notify_all();
        }
    }
}

fn acquire_waveform_permit() -> WaveformPermit {
    let (lock, cvar) =
        WAVEFORM_DECODE_PERMITS.get_or_init(|| (std::sync::Mutex::new(0), std::sync::Condvar::new()));
    let guard = lock.lock().unwrap_or_else(|e| e.into_inner());
    let mut count = cvar
        .wait_while(guard, |c| *c >= WAVEFORM_MAX_CONCURRENT)
        .unwrap_or_else(|e| e.into_inner());
    *count += 1;
    WaveformPermit
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

    // 「已知没有音轨」直接短路：GIF 转的 mp4、纯画面录屏本来就没有音频流，
    // 再探一遍也不可能出波形，只是白跑 symphonia + ffmpeg 兜底（见负缓存注释）。
    // 放在取许可之前：这类文件不该占解码名额、不该排队。
    if waveform_known_no_audio(&file_path, &identity) {
        return Err(anyhow::anyhow!(WAVE_NONE_AUDIO_MARKER));
    }

    // 缓存未命中才取解码许可：命中缓存的调用（重扫时大多数文件）不占名额、
    // 不排队，秒回；真正解码的重活最多 2 路并行（见上方闸门注释）。
    let _permit = acquire_waveform_permit();
    // 取到许可后再查一次缓存：排队期间可能已被另一路算好落盘
    if let Some(cached) = read_video_waveform(file_path.clone(), bins) {
        return Ok(cached);
    }

    // ① symphonia：常见 MP4/MP3/FLAC 直接命中，最快
    let peaks = match crate::api::music_player::extract_waveform_for_media(file_path.clone(), bins) {
        Ok(v) if v.len() == bins as usize && v.iter().any(|x| *x > 0.0) => Some(v),
        _ => None,
    };
    // ② ffmpeg 兜底：symphonia 解不了的（部分 MKV/WMV/TS 等）
    let peaks = match peaks {
        Some(v) => v,
        None => match extract_waveform_via_ffmpeg(&file_path, bins) {
            Some(v) => v,
            None => {
                // 两条链路都拿不到音频：绝大多数情况是文件压根没有音轨。
                // 记下结论（按身份），下次导入/重扫/预览直接跳过，不再重复探测。
                // 注意仍需排除"ffmpeg 不可用"这种环境问题——那种情况会立刻失败且
                // 文件清单里通常成片出现，记成无音轨会把整个库的波形永久封死。
                if !media_collection::ffmpeg_cmd().is_empty() && !has_audio_stream(&file_path) {
                    record_waveform_no_audio(&file_path, &identity);
                    return Err(anyhow::anyhow!(WAVE_NONE_AUDIO_MARKER));
                }
                return Err(anyhow::anyhow!("无法从该文件提取音频振幅"));
            }
        },
    };
    let normalized = normalize_waveform(peaks);

    // 落盘（失败不影响本次返回：只读盘等场景下拿不到缓存也能用）
    if let Some(cache) = waveform_cache_path(&file_path, bins) {
        if let Some(dir) = cache.parent() {
            if std::fs::create_dir_all(dir).is_ok() {
                let payload = serde_json::json!({
                    "identity": identity,
                    "bins": bins,
                    "algo": WAVEFORM_ALGO_VERSION,
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

/// 把线性峰值序列映射成 0~1 的显示高度（**按 dB 动态范围**，不是按最大值拉满）。
///
/// 为什么不能用 `peaks/max` + gamma：那样所有接近峰值的段落都会一起顶到 1.0，
/// 整条波形看起来一排齐平的满高柱子，"哪里更响"完全读不出来（用户实测反馈）。
/// 归一化只是把绝对电平搬到显示区间，不该压平相对差异。
///
/// 做法：以本片最响处为 0 dBFS 基准，向下取 [DB_RANGE] 的动态范围线性映射。
/// 峰值电平在真实素材里普遍逼近 0 dB，而安静段常在 -20~-40 dB，用 dB 轴才能
/// 把"大声/中等/安静"三档拉开；线性轴下中低音量会全部挤在顶端附近。
fn normalize_waveform(peaks: Vec<f64>) -> Vec<f64> {
    if peaks.is_empty() {
        return Vec::new();
    }
    let max = peaks.iter().cloned().fold(0.0f64, f64::max);
    let min = peaks.iter().cloned().fold(f64::MAX, f64::min);
    if max <= 1e-6 {
        // 全程静音（如纯黑画面转出的空音轨）：给统一的最低高度，不留空白
        return vec![MIN_BAR; peaks.len()];
    }
    // ★ 动态范围自适应：固定 dB 范围对"素材本身的起伏幅度"是猜的 ——
    //   同一部片内 RMS 往往只跨几 dB，用固定 20dB 去铺只会拉出 0.7~1.0 的
    //   一条带，仍显得差不多高。这里量出本片实际的 dB 跨度，再铺满高度区间，
    //   保证任何素材（极平的配音片 / 起伏极大的音乐片）都能看出层次。
    //   上限 DB_RANGE 挡住"几乎全平"的素材被噪声放大成一片花纹。
    let span_db = if min > 1e-6 {
        (20.0 * (max / min).log10()).min(DB_RANGE).max(1.0)
    } else {
        DB_RANGE
    };
    peaks
        .iter()
        .map(|v| {
            let ratio = v / max;
            if ratio <= 1e-6 {
                return MIN_BAR;
            }
            // 0 dB = 本片最响；低于 -span_db 的压到底
            let db = 20.0 * ratio.log10();
            let t = (1.0 + db / span_db).clamp(0.0, 1.0);
            (MIN_BAR + (1.0 - MIN_BAR) * t).clamp(MIN_BAR, 1.0)
        })
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

/// 把细粒度峰值重采样成 bins 个显示值。
///
/// ★ 用**均方根**而不是最大值。这是「波形看着都差不多高」的真正根因：
///   每块约 31ms，一个 bin 要覆盖几秒音频（2 小时片压 1200 bins 时每格约 6 秒），
///   这几秒里只要有一个响点（鼓点、爆破音、椅子响）就会把 max 顶到接近满刻度，
///   于是绝大多数柱子都被拉到天花板，只剩一条齐平的边。实测模拟里取 max 时
///   100% 的 bin 都 >0.95。
///   RMS 反映的是这一段的**平均能量**，不会被单个瞬态劫持，响段/中等/安静
///   才能分出层次；它仍是幂平均，响段依然明显高于安静段，
///   "一眼看出哪里高声"的验收点不受影响。
fn resample_peaks(peaks: &[f64], bins: usize) -> Vec<f64> {
    if peaks.len() == bins {
        return peaks.to_vec();
    }
    let mut out = vec![0.0f64; bins];
    for (i, slot) in out.iter_mut().enumerate() {
        let start = i * peaks.len() / bins;
        let end = ((i + 1) * peaks.len() / bins).max(start + 1).min(peaks.len());
        let slice = &peaks[start..end];
        let sum_sq: f64 = slice.iter().map(|v| v * v).sum();
        *slot = (sum_sq / slice.len() as f64).sqrt();
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
            serde_json::json!({
                "identity": identity,
                "bins": bins,
                "algo": WAVEFORM_ALGO_VERSION,
                "data": data,
            })
            .to_string(),
        )
        .unwrap();

        let got = read_video_waveform(src_str.clone(), bins).expect("应命中缓存");
        assert_eq!(got.len(), bins as usize);
        assert!((got[4] - data[4]).abs() < 1e-9);

        // 算法版本过期 → 不命中（强制用新算法重算，避免旧图"看着都差不多高"）
        std::fs::write(
            &cache,
            serde_json::json!({
                "identity": identity,
                "bins": bins,
                "algo": WAVEFORM_ALGO_VERSION - 1,
                "data": data,
            })
            .to_string(),
        )
        .unwrap();
        assert!(
            read_video_waveform(src_str.clone(), bins).is_none(),
            "旧算法缓存必须失效"
        );
        // 恢复成当前版本继续后面的身份校验
        std::fs::write(
            &cache,
            serde_json::json!({
                "identity": identity,
                "bins": bins,
                "algo": WAVEFORM_ALGO_VERSION,
                "data": data,
            })
            .to_string(),
        )
        .unwrap();

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
        // dB 动态范围映射：最响处到顶，但**不能把其它响段一起拉平**
        let out = normalize_waveform(vec![0.0, 0.25, 0.5, 1.0]);
        assert!((out[3] - 1.0).abs() < 1e-9, "最响处应到顶: {out:?}");
        assert!(out[2] > out[1] && out[1] > out[0], "相对响度必须保留: {out:?}");
        // 关键回归：半幅峰值的柱子不能也顶到天花板（旧算法 gamma 抬升的毛病）
        assert!(
            out[2] < 0.95,
            "半幅峰值不应接近满高，否则响段看着都差不多: {out:?}"
        );
        // 全零输入不能产出全零（否则波形整排看不见），给最低高度
        let silent = normalize_waveform(vec![0.0, 0.0, 0.0]);
        assert!(silent.iter().all(|v| *v > 0.0));
    }

    #[test]
    fn normalize_separates_loud_from_medium() {
        // 真实素材的长尾分布：少数炸裂段落 + 大量中等 + 一些安静。
        // 关键验收点是"炸裂/正常/安静"三档能看出差别，而不是一起顶满。
        let mut peaks = vec![0.12f64; 80]; // 安静底噪
        peaks.extend(std::iter::repeat_n(0.35f64, 15)); // 正常对白
        peaks.extend(std::iter::repeat_n(0.9f64, 5)); // 炸点
        let out = normalize_waveform(peaks);

        let quiet = out[0];
        let dialogue = out[80];
        let loud = out[95];
        assert!(loud > dialogue, "炸点应高于对白: {loud:.2} vs {dialogue:.2}");
        assert!(dialogue > quiet, "对白应高于底噪: {dialogue:.2} vs {quiet:.2}");
        // 三档之间要有肉眼可分辨的差距（不是都挤在天花板）
        assert!(
            loud - quiet > 0.25,
            "静音与炸点的高度差太小: {loud:.2} vs {quiet:.2}"
        );
        // 且不能全都顶满 —— 这正是用户反馈的毛病
        let saturated = out.iter().filter(|v| **v > 0.97).count();
        assert!(
            saturated < out.len() * 3 / 10,
            "顶满的柱子过多（{saturated}/{}），波形会看着一片齐平",
            out.len()
        );
    }

    #[test]
    fn resample_uses_rms_not_max() {
        // 关键回归：不能被单个瞬态劫持。
        // 前段 0,0,1,0 若取 max 得 1.0（满格），RMS 得 0.5 —— 后者才反映"这一段
        // 整体不怎么响"。一个 bin 覆盖好几秒音频时，取 max 会让几乎所有柱子顶满。
        let peaks = vec![0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.8, 0.0];
        let out = resample_peaks(&peaks, 2);
        assert_eq!(out.len(), 2);
        assert!(
            (out[0] - 0.5).abs() < 1e-9,
            "单瞬态段应被平均，实际 {}",
            out[0]
        );
        assert!(
            (out[1] - 0.4).abs() < 1e-9,
            "0,0,0.8,0 的 RMS 应为 0.4，实际 {}",
            out[1]
        );
        // 纯响段仍明显高于纯静段：响度对比不能被抹平
        let contrast = resample_peaks(&[1.0, 1.0, 0.1, 0.1], 2);
        assert!(contrast[0] > contrast[1] * 5.0, "响/静段必须拉开: {contrast:?}");
        // 等长时原样返回
        assert_eq!(resample_peaks(&peaks, peaks.len()), peaks);
    }

    #[test]
    fn normalize_maps_monotonically_and_hits_ceiling() {
        // 窄分布素材（0.5~1.0）也必须把差异拉开，而不是压成一条平线
        let peaks: Vec<f64> = (0..100).map(|i| 0.5 + i as f64 / 200.0).collect();
        let out = normalize_waveform(peaks);
        assert_eq!(out.len(), 100);
        let max = out.iter().cloned().fold(0.0f64, f64::max);
        let min = out.iter().cloned().fold(1.0f64, f64::min);
        assert!(max > 0.98, "最大值应接近满高: {max}");
        // 关键：最矮与最高必须拉开足够高度差，否则"看着都差不多"
        assert!(
            max - min > 0.5,
            "窄分布也要拉开层次，实际 {min:.2}~{max:.2}"
        );
        // 单调性：原始越大，显示越高（不能打乱相对关系）
        for w in out.windows(2) {
            assert!(w[1] >= w[0] - 1e-9, "高度必须与原始能量同序: {w:?}");
        }
        // 全程静音不留空白
        let silent = normalize_waveform(vec![0.0; 10]);
        assert!(silent.iter().all(|v| (*v - MIN_BAR).abs() < 1e-9));
    }

    // ── 「没有音轨」负缓存 ─────────────────────────────────────────────

    #[test]
    fn no_audio_marker_roundtrip_and_identity_guard() {
        // 记下的结论要能跨进程复用（落盘），且换文件后必须失配重新探测
        let dir = temp_dir("noaudio_marker");
        let src = dir.join("silent.mp4");
        std::fs::write(&src, b"fake-video-bytes").unwrap();
        let path = src.to_string_lossy().into_owned();

        let meta = std::fs::metadata(&src).unwrap();
        let identity = waveform_identity(&meta);

        // 未记录前不认为"没有音轨"
        assert!(!waveform_known_no_audio(&path, &identity));

        record_waveform_no_audio(&path, &identity);
        // 进程内 + 落盘双份：这里清掉进程内那份，只验证磁盘标记仍生效
        waveform_no_audio_map()
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .remove(&path);
        assert!(
            waveform_known_no_audio(&path, &identity),
            "落盘标记必须能独立命中（跨重启复用）"
        );

        // 文件被替换（身份变化）→ 结论失效，应重新探测
        std::fs::write(&src, b"another-video-with-audio").unwrap();
        let new_meta = std::fs::metadata(&src).unwrap();
        let new_identity = waveform_identity(&new_meta);
        assert_ne!(identity, new_identity, "写入不同内容后身份必须变化");
        waveform_no_audio_map()
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .remove(&path);
        assert!(
            !waveform_known_no_audio(&path, &new_identity),
            "身份变了就不能沿用旧的「没有音轨」结论"
        );

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn video_waveform_absent_short_circuits_generator() {
        // ensure_video_waveform 在负缓存命中时必须直接返回、不起解码
        let dir = temp_dir("noaudio_short");
        let src = dir.join("silent2.mp4");
        std::fs::write(&src, b"silent-bytes").unwrap();
        let meta = std::fs::metadata(&src).unwrap();
        let identity = waveform_identity(&meta);
        record_waveform_no_audio(&src.to_string_lossy(), &identity);

        // frb(sync) 入口应报 true（导入/重扫据此不排队）
        assert!(video_waveform_absent(src.to_string_lossy().into_owned()));

        let err = ensure_video_waveform(src.to_string_lossy().into_owned(), 1200)
            .expect_err("负缓存命中不该返回波形");
        assert!(
            err.to_string().contains(WAVE_NONE_AUDIO_MARKER),
            "错误文案要能被上层识别成「没有音轨」而不是真故障，实际={}",
            err
        );

        // 不存在的文件也当作"没有"，别再排任务
        assert!(video_waveform_absent(
            dir.join("nope.mp4").to_string_lossy().into_owned()
        ));

        let _ = std::fs::remove_dir_all(&dir);
    }
}

/// 判定视频容器是否已 faststart（`moov` 在 `mdat` 之前）。
///
/// 只看文件头部的顶层 atom，不解码不整读；非 MP4/MOV 容器返回 None。
/// 异步：文件在 SMB/外置卷上时 open + seek 也是网络往返，不能挂 UI 线程。
pub async fn video_is_faststart(file_path: String) -> anyhow::Result<Option<bool>> {
    media_collection::video_is_faststart(file_path)
        .await
        .map_err(|error| anyhow::anyhow!(error))
}

/// 把非 faststart 的 MP4 重封装成 faststart 副本，返回副本路径（已 faststart 返回 None）。
///
/// 纯 `-c copy` 重封装：不重编码、画质无损（实测 613MB/118min 用 236s）；
/// 副本写资源旁 `.SlimeWorks/faststart/<文件名>`，**不修改原文件**。
/// 由节点在「远程客户端要播非 faststart 视频」时按需调用。
pub async fn ensure_faststart_copy(file_path: String) -> anyhow::Result<Option<String>> {
    media_collection::ensure_faststart_copy(file_path)
        .await
        .map_err(|error| anyhow::anyhow!(error))
}

/// `ensure_faststart_copy` 的同步版（供节点后台线程直接调用）。
///
/// 与异步版共用同一实现：节点在请求线程里排一个后台线程调它，
/// 这样既不改请求路径的时序，也不会把重封装塞进 tokio worker。
#[frb(ignore)]
pub fn ensure_faststart_copy_blocking(file_path: &str) -> anyhow::Result<Option<String>> {
    media_collection::ensure_faststart_copy_blocking(file_path)
        .map_err(|error| anyhow::anyhow!(error))
}
