# 集合卡片「相似查找」功能

## Context（背景）

用户在集合卡片右键菜单（`media_collection_card.dart` 的【收藏/取消收藏】项下方）新增一个「相似查找」入口：
- 点击后，**以被右击的这个集合的名称作为查询词**，在**当前层级 + 子子孙孙文件夹**下的所有集合中，搜索名称相似的集合。
- 匹配并**排序**采用三层亲和度：**资源全名称 > 资源名称分词 > 资源名称逐字匹配**。
- 结果**复用现有浏览网格的搜索筛选机制**展示（合并进当前网格，按匹配层级排序）。
- 页面**底部居中悬浮**一个「清除搜索结果」按钮，点击清除该筛选。
- 进入某个命中集合查看资源列表时，**搜索筛选逻辑仍保留**（资源列表同样被过滤）。
- 本次实现采取**独立于现有搜索框的相似搜索状态**（不污染现有 `searchQuery` 深度搜索逻辑）。

媒体层级约定：`文件夹(Folder) → 智能文件夹(SmartFolder) → 集合(Collection) → 资源列表(MediaItem 列表) → 资源(MediaItem)`。本功能搜索对象是**集合(Collection)**。

## 修改文件与方案

### 1. `lib/view_models/media_library_viewmodel.dart`（核心逻辑）

新增状态与方法：

- 状态字段：
  ```dart
  /// 相似查找是否激活及查询词（被右击集合的名称）
  final similarSearchQuery = ''.obs;
  /// 相似查找的来源集合 id（结果中排除自身）
  final similarSourceId = Rxn<String>();
  ```
- `void startSimilarSearch(media_api.MediaCollection source)`
  - 设置 `similarSearchQuery.value = source.title`、`similarSourceId.value = source.id`；
  - 同时把现有 `searchQuery` 置空（避免两套搜索互相干扰）。
- `void clearSimilarSearch()`：清空 `similarSearchQuery` 与 `similarSourceId`。

- 新增 `List<MediaLibraryItem> _similarSearchItems(String query)`：
  - **复用** `_deepSearchItems`（第 776 行起）里 BFS 收集 `scopeFolderIds` 的逻辑（当前层级 + 全部后代文件夹）。
  - 候选集合 = `mergedCollections.where((c) => scopeFolderIds.contains(c.folderId))`，剔除 `c.id == similarSourceId` 的自身。
  - 对每个候选集合标题 `t`，按以下顺序计算**最高命中层级**（`query = source.title.toLowerCase()`，`tLow = c.title.toLowerCase()`）：
    - **tier1 全名称**：`tLow.contains(query)`
    - **tier2 分词**：将 query 按分隔符（空白、`_ - . ,` 等）切词并过滤长度 < 2 的 token，任一 token 是 `tLow` 的子串
    - **tier3 逐字匹配**：query 与 `tLow` 的**唯一字符交集个数 ≥ 2**
    - 取命中的最高层级；都不命中则跳过。
  - 排序：按 tier 升序（1 → 2 → 3），同一 tier 内保持原始顺序稳定输出。
  - 返回 `MediaLibraryCollectionItem` 列表。

- 在 `visibleItems` getter（第 715 行）**最前面**加判断：
  ```dart
  final similar = similarSearchQuery.value.trim().toLowerCase();
  if (similar.isNotEmpty) {
    return _similarSearchItems(similar);
  }
  ```
- 在 `sortedCurrentItems`（第 876 行）里，让资源列表同样受相似查找过滤，使进入集合后**筛选逻辑保留**：
  ```dart
  final similarText = similarSearchQuery.value.trim().toLowerCase();
  if (similarText.isNotEmpty) {
    items = items.where((i) => i.title.toLowerCase().contains(similarText)).toList();
  }
  ```

### 2. `lib/pages/collection/picture/components/media_collection_card.dart`

- 增加可选回调参数 `final VoidCallback? onSimilarSearch;`。
- 在【收藏/取消收藏】`PopupMenuItem`（第 292–295 行）**正下方**新增：
  ```dart
  if (widget.onSimilarSearch != null)
    const PopupMenuItem<String>(value: 'similar', child: Text('相似查找')),
  ```
- 在 `action` 分发中新增：`else if (action == 'similar') { widget.onSimilarSearch?.call(); }`（第 317 行分支处）。

### 3. `lib/pages/collection/picture/components/media_browse_grid.dart`

- 在 `_buildCollectionCard`（第 282 行）给 `MediaCollectionCard` 传入：
  ```dart
  onSimilarSearch: () => vm.startSimilarSearch(collection),
  ```

### 4. `lib/pages/collection/picture/collection_picture_screen.dart`（底部悬浮「清除搜索结果」按钮）

- 新增私有方法，返回底部居中悬浮按钮（`similarSearchQuery` 非空时构建，点为清除）：
  ```dart
  Widget? _similarClearOverlay(BuildContext context) {
    if (viewModel.similarSearchQuery.value.trim().isEmpty) return null;
    return Positioned(
      left: 0, right: 0, bottom: AppTheme.metrics.kSpace20,
      child: Center(child: /* 圆角胶囊按钮：“清除搜索结果” + 关闭图标，onPressed: viewModel.clearSimilarSearch() */),
    );
  }
  ```
  （该方法放在 `buildContent` 内的 `Obx` 闭包中使用，读取 `similarSearchQuery.value` 即注册响应式依赖。）
- 在 `buildContent` 的三个返回点把该 overlay 叠加到 `body` 之上（这样浏览网格与集合详情都能显示清除按钮）：
  1. 移动端「无内部层级」分支（当前 `return body;`，约第 373 行）→ 包装为 `Stack([body, overlay])`（overlay 非空时）。
  2. 移动端「有内部层级」分支的 `Stack`（约第 374 行）→ 追加 overlay。
  3. 桌面端 `DropTarget` 内的 `Stack`（约第 413 行，拖拽高亮分支）→ 追加 overlay。

## 关键复用点（不改动）

- `visibleItems` / `mergedCollections` / `_deepSearchItems` 的 BFS scope 逻辑（media_library_viewmodel.dart）。
- `sortedCurrentItems` 在集合详情（`media_collection_detail.dart:45`）中被渲染，用于“进入集合后保留筛选”。
- `MediaCollectionCard` 现有 `onToggleFavorite` 回调接线模式（media_browse_grid.dart:338）。

## 验证方式

1. `flutter analyze` 确认无静态错误。
2. `flutter run -d windows`（桌面端）手动验证：
   - 右键集合卡片 → 菜单在【收藏】下方出现【相似查找】。
   - 点击后：网格仅显示当前层 + 子孙文件夹里名称与来源集合相似的集合，且按 全名称→分词→逐字 分层排序，来源集合自身被排除。
   - 页面底部居中出现「清除搜索结果」胶囊按钮。
   - 点进某个命中集合，资源列表仍按相似查询词过滤；点「清除搜索结果」后恢复全部集合与资源列表，且按钮消失。
3. 回归：普通工具栏搜索框行为不受影响。