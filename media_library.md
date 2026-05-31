# 媒体库模块（Media Library）

## 简介

媒体库模块用于管理本地和远程节点上的图片、视频、音频文件。支持按文件夹分组、智能文件夹自动过滤、封面缩略图生成以及多节点联合浏览。核心存储与扫描逻辑由 Rust 的 `media_collection` 模块实现。

## 文件位置

| 层 | 文件 |
|----|------|
| 图片/视频库页面 | `lib/pages/collection/picture/collection_picture_screen.dart` |
| 书库入口（含媒体） | `lib/pages/collection/library/collection_library_screen.dart` |
| 智能文件夹组件 | `lib/pages/collection/picture/components/smart_folder.dart` |
| ViewModel（集合） | `lib/view_models/media_library_viewmodel.dart` |
| ViewModel（智能文件夹） | `lib/view_models/media_library_vm_smart_folders.dart` |
| ViewModel（集合列表） | `lib/view_models/media_library_vm_collections.dart` |
| 媒体偏好服务 | `lib/core/services/media_prefs_service.dart` |
| 节点服务 | `lib/core/services/node/node_settings_service.dart` |
| Rust 核心 | `rust/media_collection/src/types.rs` |
| | `rust/media_collection/src/scanner.rs` |
| | `rust/media_collection/src/api.rs` |

## 数据模型

### `MediaCollection`（集合）

代表磁盘上的一个媒体文件夹，是媒体库的基本单元。

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `String` | UUID |
| `title` | `String` | 显示名称（默认为文件夹名） |
| `folder_path` | `String` | 磁盘绝对路径 |
| `folder_id` | `Option<String>` | 所属媒体文件夹 ID（用于树形分组） |
| `cover_path` | `Option<String>` | 封面图路径 |
| `item_count` | `u64` | 文件数量 |
| `created_at` / `updated_at` | `String` | RFC3339 时间 |

### `MediaFolder`（文件夹）

用于在 UI 中组织多个集合，支持多级嵌套（通过 `parent_id`）。

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `String` | UUID |
| `name` | `String` | 文件夹名 |
| `order` | `i64` | 排序权重 |
| `parent_id` | `Option<String>` | 父文件夹（`null` = 根目录） |

### `MediaItem`（媒体文件）

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `String` | UUID |
| `collection_id` | `String` | 所属集合 |
| `title` | `String` | 文件名（不带扩展名） |
| `file_path` | `String` | 磁盘绝对路径 |
| `kind` | `MediaKind` | `Image / Video / Audio` |
| `file_size` | `u64` | 字节 |
| `width` / `height` | `Option<u32>` | 图片/视频分辨率 |
| `duration_ms` | `Option<u64>` | 音视频时长（毫秒） |

### 支持的媒体格式

| 类型 | 扩展名 |
|------|--------|
| **图片** | jpg / jpeg / jfif / png / gif / webp / bmp / avif / heic / heif / tif / tiff |
| **视频** | mp4 / mov / m4v / mkv / avi / webm / wmv / flv / ts |
| **音频** | mp3 / flac / aac / m4a / ogg / opus / wav / wma / ape / aiff / alac |

## 智能文件夹（`SmartFolder`）

智能文件夹是自动过滤规则，不存储实际文件，仅基于条件筛选已有集合。

```dart
class SmartFolder {
  String id;
  String name;
  String regexPattern;           // 正则表达式（空 = 不过滤名称）
  String regexTarget;            // 'collectionName' | 'fileName'
  String fileTypeFilter;         // 'all' | 'images' | 'videos'
  List<String> targetFolderIds;  // [] = 匹配所有文件夹
}
```

持久化：以 JSON 文件存储于 `<AppSupportDirectory>/slime_smart_folders.json`（`MediaLibraryViewModel._smartFolderFileName`）。

集合排序：存储于 `SharedPreferences`，key 格式 `media_collection_order_<orderKey>`；各智能文件夹/文件夹视图维护独立的顺序。

## 目录扫描

### 本地扫描（`rust/media_collection/src/scanner.rs`）

- 使用 `WalkDir` 递归遍历目录
- 跳过以 `.` 和 `._` 开头的隐藏文件（macOS metadata 文件）
- 返回 `ScanProgress { scanned, found, current_file }` 实时进度
- 支持 `scan_async`（`tokio::task::spawn_blocking`）避免阻塞 UI

### Dart ViewModel（`scanNodeMediaFolders`）

远程节点的目录树浏览通过 `/node/call` action `list_directories` 实现，返回一级子目录路径列表。

## 缩略图生成

### 生成策略（`rust/media_collection/src/api.rs::ensure_cover_thumbnail`）

优先级从高到低：

1. **磁盘缓存命中**：路径 `<AppSupportDir>/SlimeWorks/library/media/covers/<md5>_w<width>.jpg`，文件非空则直接返回
2. **视频**：`ffmpeg -i input -vf scale=<width>:-1 -ss 3 -vframes 1`（先 seek 3s，失败回退 seek 0s）
3. **音频**：`ffmpeg -i input -map 0:v:0 -frames:v 1`（提取内嵌封面）
4. **图片**：`ffmpeg -i input -vf scale=<width>:-1`（支持 HEIC/AVIF 系统解码器）
5. **回退**：纯 Rust `image` crate（JPEG/PNG/WebP/BMP/GIF）
6. **全失败**：返回 `None`；视频/音频返回 404，图片 Dart 侧回退原图

### Dart 内存缓存（LRU）

`NodeSettingsService._resizedBytesCache`：最多 120 条，超出时移除最早条目。  
key 格式：`${filePath.hashCode.toUnsigned(32).toRadixString(16)}_w<width>`

## 远程节点媒体访问

### 媒体文件 URL 构建

```dart
// 缩略图
String url = nodeSettingsService.buildNodeMediaUrl(
  nodeId: nodeId,
  filePath: '/path/to/video.mp4',
  thumbnailWidth: 240,
  isCover: true,   // mode=cover
);
// → http://<host>:<port>/node/media?path=...&width=240&mode=cover
```

### 视频流播放（`/node/media` Range 请求）

远程视频通过 `VideoPlayerController.network(url)` 播放，视频播放器自动以 Range 请求逐段拉取，Rust 服务端 `serve_range_request` 使用文件 **seek** 只读取所需字节范围：

- 每次最多返回 **2MB**（`VIDEO_CHUNK_SIZE`），防止大文件一次性载入内存
- 无 Range 请求时（初始请求），服务端主动返回 `206` 首段（`bytes=0-2MB`）提示客户端改用断点续传
- 完整 `Content-Range: bytes start-end/total` 头确保播放器可正确定位

### 宽度限制策略（双端保护）

服务端读取 `MediaPrefsService` 配置的最大宽度，与客户端请求宽度取最小值，避免传输超过实际需要的大图：

```
effectiveWidth = min(serverMaxWidth, clientRequestedWidth)  // 若任一为 0 则取另一端值
```

封面默认宽度：`240 px`；图片预览宽度根据用户设置（默认 `480 px`，远程 `0` = 原图）。

### 视频流式播放（Range 请求支持）

Rust 节点服务器的 `/node/media` 路由完整支持 HTTP Range 请求，供 media_kit/libmpv 流式播放远程视频：

- 对视频/音频文件，响应 `206 Partial Content`，单次最多返回 **2MB**  
- 图片/封面请求（带 `mode=cover` 或 `width` 参数）继续走缩略图生成路径
- 客户端无 Range 请求时服务端主动返回首个 2MB 切片，促使播放器转用 Range

### 节点操作 Actions

通过 `POST /node/call { action, params }` 调用：

| Action | 说明 |
|--------|------|
| `list_media_collections` | 获取所有集合（含统计） |
| `list_media_folders` | 获取所有文件夹 |
| `get_media_collection_items` | 获取集合内文件列表 |
| `import_media_folder` | 导入文件夹创建集合 |
| `scan_media_folders` | 扫描目录 |
| `list_directories` | 列举一级子目录 |
| `rename_media_collection` | 重命名集合 |
| `delete_media_collection` | 删除集合（保留文件） |
| `delete_collection_local_files` | 删除集合的本地物理文件 |
| `move_media_collection_to_folder` | 将集合移至指定文件夹 |
| `create_media_folder` | 创建根文件夹 |
| `create_child_media_folder` | 创建子文件夹 |
| `rename_media_folder` | 重命名文件夹 |
| `delete_media_folder` | 删除文件夹 |
| `update_collection_cover_base64` | 更新集合封面 |

## ViewModel 关键状态

```dart
// MediaLibraryViewModel
RxList<MediaCollection> collections;         // 本地集合
RxList<MediaCollection> remoteCollections;   // 远程节点集合
RxList<MediaFolder> folders;                 // 本地文件夹
RxList<SmartFolder> smartFolders;            // 智能文件夹（Dart 端维护）
RxBool isLoading;
RxString currentFolderId;                    // 当前浏览的文件夹（null = 根）
```

## 内存管理

| 缓存层 | 限制 | 说明 |
|--------|------|------|
| Flutter imageCache | 80 MB | 网络图片解码后的像素缓存 |
| `_resizedBytesCache`（Dart 侧 LRU） | 80 MB | 远程封面缩略图字节缓存 |
| Rust 磁盘封面缓存 | 无上限（按需生成） | `<AppSupportDir>/SlimeWorks/library/media/covers/` |

> `_resizedBytesCache` 改为按总字节大小（80MB）LRU 淘汰，防止大量远程封面导致内存持续增长。

## 媒体偏好设置（`MediaPrefsService`）

| 设置项 | SharedPreferences Key | 默认值 |
|--------|----------------------|--------|
| 缩略图质量（1-5） | `media_thumb_quality` | 3（240px，qscale=6，6帧） |
| 缩略图并发（1-20） | `media_thumb_concurrency` | 2 |
| 远程封面宽度 | `media_remote_cover_width` | 240 px |
| 远程图片预览宽度 | `media_remote_image_width` | 0（原图） |
| 本地图片预览宽度 | `media_local_preview_width` | 480 px |
| 缓存大小上限 | `media_cache_limit_bytes` | 1 GB |

缓存路径：
- 视频帧缩略图：`<AppSupportDir>/SlimeWorks/library/media/thumbnails/`

| 设置项 | SharedPreferences Key | 默认值 |
|--------|----------------------|--------|
| 缩略图质量（1-5） | `media_thumb_quality` | 3（240px，qscale=6，6帧） |
| 缩略图并发（1-20） | `media_thumb_concurrency` | 2 |
| 远程封面宽度 | `media_remote_cover_width` | 240 px |
| 远程图片预览宽度 | `media_remote_image_width` | 0（原图） |
| 本地图片预览宽度 | `media_local_preview_width` | 480 px |
| 缓存大小上限 | `media_cache_limit_bytes` | 1 GB |

缓存路径：
- 视频帧缩略图：`<AppSupportDir>/SlimeWorks/library/media/thumbnails/`
- 封面缩略图：`<AppSupportDir>/SlimeWorks/library/media/covers/`

## 平台支持

| 功能 | macOS | Windows | iOS | Android |
|------|-------|---------|-----|---------|
| 本地扫描 | ✅ | ✅ | ✅（沙盒路径） | ✅ |
| 视频缩略图（ffmpeg） | ✅ | ✅ | ❌ | ❌ |
| HEIC/AVIF 缩略图 | ✅ | ⚠️ 依赖系统解码 | ✅ | ✅ |
| 远程节点浏览 | ✅ | ✅ | ✅ | ✅ |
| 视频流式播放（远程） | ✅ | ✅ | ✅ | ✅ |
