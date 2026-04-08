# 书库模块（Novel Library）

## 简介

书库模块用于管理本地和远程节点上的电子书（TXT、EPUB），支持章节浏览、阅读进度记录、标签管理以及跨节点联合书库。核心解析与数据库逻辑由 Rust 的 `novel_reader` 模块实现。

## 文件位置

| 层 | 文件 |
|----|------|
| 书库入口 | `lib/pages/collection/library/collection_library_screen.dart` |
| 旧版书库页 | `lib/pages/novel_library/novel_library_page.dart` |
| 阅读器 | `lib/pages/novel_reader/novel_reader_page.dart` |
| | `lib/pages/novel_reader/` (子组件) |
| ViewModel | `lib/view_models/novel_library_viewmodel.dart` |
| | `lib/view_models/novel_library_vm_novel.dart`（part） |
| | `lib/view_models/novel_library_vm_actions.dart`（part） |
| Rust 核心 | `rust/novel_reader/src/types.rs` |
| | `rust/novel_reader/src/scanner.rs` |
| | `rust/novel_reader/src/parser/parser_epub.rs` |
| | `rust/novel_reader/src/parser/parser_txt.rs` |
| | `rust/novel_reader/src/search.rs` |
| | `rust/novel_reader/src/api.rs` |

## 数据模型

### `NovelMetadata`（书籍元数据）

Rust 与 Dart 两端同构，通过 JSON 在 FFI 边界传递。

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `String` | UUID |
| `title` | `String` | 书名 |
| `author` | `Option<String>` | 作者 |
| `file_path` | `String` | 磁盘绝对路径 |
| `format` | `NovelFormat` | `Txt` / `Epub` |
| `file_size` | `u64` | 字节 |
| `modified_at` | `String` | 文件修改时间（RFC3339） |
| `is_favorite` | `bool` | 收藏标记 |
| `tags` | `Vec<String>` | 标签列表 |
| `added_at` | `String` | 加入书库时间 |
| `progress` | `f32` | 阅读进度 `0.0 ~ 1.0` |
| `current_chapter_id` | `Option<String>` | 当前阅读章节 ID |
| `last_read_at` | `Option<String>` | 最近阅读时间 |
| `cover_path` | `Option<String>` | 封面图路径 |
| `folder_id` | `Option<String>` | 所属文件夹 ID |
| `custom_order` | `Option<i64>` | 自定义排序权重 |
| `notes` | `Option<String>` | 用户备注 |

### `NovelChapter`（章节）

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `String` | 章节 ID（EPUB 内部路径 / TXT 自动序号） |
| `title` | `String` | 章节标题 |
| `index` | `u32` | 序号（从 0 开始） |
| `content` | `Option<String>` | 按需加载的章节正文 |

### `NovelFolder`（书库文件夹）

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `String` | UUID |
| `name` | `String` | 文件夹名 |
| `order` | `i64` | 排序权重 |
| `parent_id` | `Option<String>` | 父文件夹（`null` = 根） |

## 支持的书籍格式

### TXT（`TxtParser`）

- 自动编码检测：`chardetng` crate，支持 GB2312 / GBK / UTF-8 等常见编码
- 自动章节识别：正则匹配"第X章"、"Chapter X"等常见章节格式
- 长文件自动分章节，每章节按需读取，不全部载入内存

### EPUB（`EpubParser`）

- 解析 `epub` crate，从 OPF/NCX/NAV 中提取 TOC 和 spine
- 章节顺序遵循 spine 定义
- 封面图从 `epub` 资源（`cover.jpg` 或 `metadata cover` 属性）中提取
- Windows 特殊支持：`.epub` 目录（解压后的 epub 文件夹）

## 目录扫描（`DirectoryScanner`）

```rust
// 递归遍历目录，返回所有支持格式的书籍文件路径
scan_async(dir_path: String, progress_callback: ...) -> Result<Vec<NovelMetadata>>
```

- 使用 `WalkDir` 递归遍历，跳过 `.` 和 `._` 开头的隐藏路径
- 实时上报进度：`ScanProgress { scanned: u64, found: u64, current_file: String }`
- 同步运行在 `tokio::task::spawn_blocking` 避免阻塞异步运行时

## 阅读进度追踪

进度数据存储在 `NovelMetadata` 中，通过以下 FFI 调用更新：

```dart
// ViewModel 调用
await viewModel.updateNovelProgress(
  id: novelId,
  progress: 0.45,       // 0.0 ~ 1.0
  chapterId: 'ch_12',
);
// → rust_api.updateReadingProgress(id, progress, chapterId)
```

最近阅读时间 `last_read_at` 同步写回，用于"最近阅读"排序。

## ViewModel 关键状态

```dart
// NovelLibraryViewModel
RxList<NovelMetadata> novels;              // 本地书库列表
RxList<NovelMetadata> remoteNovels;        // 远程节点书库列表（聚合所有节点）
RxList<NovelFolder> folders;              // 文件夹（含树形 parent_id）
RxnString currentFolderId;               // null = 根目录
Map<String, String> remoteNovelNodeId;   // novelId → nodeId（标记来源节点）
RxBool isLoading;
RxString searchKeyword;                   // 搜索关键词
```

通过 `isRemoteNovel(id)` 判断是否来自远程节点，通过 `getNovelNodeName(id)` 获取来源节点名称。

## 远程节点书库访问

### 节点 Actions

通过 `POST /node/call { action, params }` 调用：

| Action | 参数 | 说明 |
|--------|------|------|
| `list_novels` | — | 返回所有书籍元数据（含章节数、文件夹名） |
| `search_all_novels` | `keyword` | 关键词搜索 |
| `get_novel_content` | `file_path` | 获取章节列表（不含正文） |
| `get_chapter_content` | `file_path, chapter_index` | 获取指定章节正文 |
| `delete_novel` | `novel_id` | 删除书籍 |
| `update_novel_info` | `novel_id, title?, author?, notes?, tags?` | 更新元数据 |
| `set_novel_favorite` | `novel_id, is_favorite` | 收藏/取消收藏 |
| `move_novel_to_folder` | `novel_id, folder_id?` | 移至文件夹 |
| `update_novel_cover_base64` | `novel_id, image_base64, image_ext` | 更新封面（Base64） |

### 数据合并流程

```dart
// ViewModel 拉取所有启用节点的书库并合并
for (final node in nodeSettingsService.enabledRemoteNodes) {
  final novels = await nodeSettingsService.fetchNodeNovels(node);
  // 合并至 remoteNovels，通过 remoteNovelNodeId 记录来源
}
```

## 全文搜索

本地搜索通过 `rust_api.searchNovels(keyword)` 调用，Rust 侧在内存中对已加载的书籍元数据（标题、作者）进行匹配。远程搜索通过节点的 `search_all_novels` action 执行。

## 阅读器功能

| 功能 | 说明 |
|------|------|
| 章节目录 | 从 `get_novel_content` 获取章节列表展示 |
| 正文渲染 | Dart `SelectableText.rich` 渲染，支持字体大小调整 |
| 进度保存 | 翻页时自动 debounce 写回 Rust |
| 夜间模式 | 遵从全局 `AppTheme.themeModeObs` |
| 字体缩放 | `MediaPrefsService` 或专属设置 |

## 平台支持

| 功能 | macOS | Windows | iOS | Android |
|------|-------|---------|-----|---------|
| 本地扫描 | ✅ | ✅ | ✅（沙盒） | ✅ |
| TXT 编码检测 | ✅ | ✅ | ✅ | ✅ |
| EPUB 解析 | ✅ | ✅（含 .epub 目录） | ✅ | ✅ |
| 远程节点访问 | ✅ | ✅ | ✅ | ✅ |
