import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/window/desktop_head.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/view_models/media_library_viewmodel.dart';

/// 图片库操作工具栏。
///
/// 在桌面端放置于 [ScreenChromeData.toolbar]（右侧），
/// 移动端同样放置于 [ScreenChromeData.toolbar]（AppBar 下方第二行）。
///
/// 当 [columnCount] 非 null 时表示处于移动端详情模式，
/// 工具栏会额外显示列数调节按钮和资源排序按钮。
/// 桌面端此二控件已由 `_buildActionBar` 的 `leading` 区域负责，
/// 因此传入 null 以避免重复。
class PictureLibraryToolbar extends StatelessWidget {
  const PictureLibraryToolbar({
    super.key,
    required this.viewModel,
    required this.onCreateFolder,
    required this.onScanFolder,
    required this.onImportFolder,
    required this.onRefresh,
    required this.onClearLibrary,
    required this.onCreateSmartFolder,
    this.columnCount,
    this.onColumnDecrement,
    this.onColumnIncrement,
    this.onUpload,
  });

  final MediaLibraryViewModel viewModel;
  final VoidCallback onCreateFolder;
  final VoidCallback onScanFolder;
  final VoidCallback onImportFolder;
  final VoidCallback onRefresh;
  final VoidCallback onClearLibrary;
  final VoidCallback onCreateSmartFolder;

  /// 移动端详情模式当前列数；null 表示桌面模式（不显示列数控件）。
  final int? columnCount;

  /// 列数减少回调（移动端详情模式）。
  final VoidCallback? onColumnDecrement;

  /// 列数增加回调（移动端详情模式）。
  final VoidCallback? onColumnIncrement;

  /// 移动端远程集合详情模式：上传文件到当前集合。
  final VoidCallback? onUpload;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isScanning = viewModel.isScanning.value;
      final statusText = viewModel.scanStatusText.value;
      final inDetail = viewModel.isInDetail;
      final thumbProgress = viewModel.thumbProgress.value;
      final remoteThumbProgress = viewModel.remoteThumbProgress.value;
      // columnCount 非 null 表示移动端，需要在 toolbar 中显示列数 + 排序
      final showMobileDetailControls = columnCount != null && inDetail;
      final showMobileBrowseSortControl = columnCount != null && !inDetail;

      return Align(
        alignment: Alignment.centerRight,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: AppTheme.metrics.kSpace8,
              children: [
                // 扫描进度（opacity 不增删节点，避免 AX tree 闪烁）
                if (statusText.isNotEmpty)
                  AnimatedOpacity(
                    opacity: isScanning ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: IgnorePointer(
                      ignoring: !isScanning,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: AppTheme.metrics.kSpace8,
                        children: [
                          SizedBox(
                            width: AppTheme.metrics.kSpace20,
                            height: AppTheme.metrics.kSpace20,
                            child: const CircularProgressIndicator(strokeWidth: 2),
                          ),
                          Text(
                            statusText.isNotEmpty ? statusText : ' ',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                // 缩略图生成进度：悬停时显示取消按钮；暂停后显示恢复入口
                if (thumbProgress != null)
                  _ThumbProgressIndicator(
                    progress: thumbProgress,
                    onCancel: viewModel.cancelThumbGeneration,
                  )
                // 远程节点缩略图生成进度：任务在节点端执行，客户端仅展示进度
                else if (remoteThumbProgress != null)
                  _ThumbProgressIndicator(progress: remoteThumbProgress)
                else if (viewModel.thumbGenerationPaused.value)
                  _ThumbPausedIndicator(onResume: viewModel.resumeThumbGeneration),
                // 搜索：浏览模式深度搜索当前层级；详情模式按文件名过滤资源列表
                _LibrarySearchField(
                  viewModel: viewModel,
                  hintText: inDetail ? '搜索资源文件名' : '搜索文件夹/集合/资源',
                ),
                // 浏览模式：图书馆操作按钮
                if (!isScanning && !inDetail)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: AppTheme.metrics.kSpace8,
                    children: [
                      Tooltip(
                        message: '新建文件夹',
                        child: DesktopHeadToolsButton(
                          icon: const Icon(Icons.create_new_folder_outlined),
                          size: AppTheme.metrics.kSpace40,
                          onTap: onCreateFolder,
                        ),
                      ),
                      Tooltip(
                        message: '扫描文件夹',
                        child: DesktopHeadToolsButton(
                          icon: const Icon(Icons.travel_explore_outlined),
                          size: AppTheme.metrics.kSpace40,
                          onTap: onScanFolder,
                        ),
                      ),
                      Tooltip(
                        message: '导入文件夹',
                        child: DesktopHeadToolsButton(
                          icon: const Icon(Icons.folder_open_outlined),
                          size: AppTheme.metrics.kSpace40,
                          onTap: onImportFolder,
                        ),
                      ),
                      Tooltip(
                        message: '清空媒体库',
                        child: DesktopHeadToolsButton(
                          icon: const Icon(Icons.delete_sweep_outlined),
                          size: AppTheme.metrics.kSpace40,
                          onTap: onClearLibrary,
                        ),
                      ),
                      Tooltip(
                        message: '新建智能文件夹',
                        child: DesktopHeadToolsButton(
                          icon: const Icon(Icons.auto_awesome_outlined),
                          size: AppTheme.metrics.kSpace40,
                          onTap: onCreateSmartFolder,
                        ),
                      ),
                      Tooltip(
                        message: viewModel.showFavoritesOnly.value ? '显示全部' : '只显示收藏',
                        child: DesktopHeadToolsButton(
                          icon: Icon(
                            viewModel.showFavoritesOnly.value
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: viewModel.showFavoritesOnly.value ? Colors.redAccent : null,
                          ),
                          size: AppTheme.metrics.kSpace40,
                          onTap: () => viewModel.showFavoritesOnly.value =
                              !viewModel.showFavoritesOnly.value,
                        ),
                      ),
                    ],
                  ),
                // 移动端浏览模式：集合排序按钮（桌面端此按钮在 leading 区域）
                if (showMobileBrowseSortControl)
                  PopupMenuButton<CollectionSortOrder>(
                    tooltip: '集合排序',
                    icon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.sort_rounded, size: scaleW(18)),
                        SizedBox(width: AppTheme.metrics.kSpace4),
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: scaleW(72)),
                          child: Text(
                            viewModel.collectionSortOrder.value.label,
                            style: Theme.of(context).textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    onSelected: (v) => viewModel.collectionSortOrder.value = v,
                    itemBuilder: (_) => CollectionSortOrder.values
                        .map(
                          (o) => PopupMenuItem<CollectionSortOrder>(
                            value: o,
                            child: Row(
                              children: [
                                if (viewModel.collectionSortOrder.value == o)
                                  Icon(Icons.check_rounded, size: scaleW(16))
                                else
                                  SizedBox(width: scaleW(16)),
                                SizedBox(width: AppTheme.metrics.kSpace8),
                                Text(o.label),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                if (inDetail)
                  Tooltip(
                    message: viewModel.showMediaOverlay.value ? '隐藏叠加信息' : '显示叠加信息',
                    child: DesktopHeadToolsButton(
                      icon: Icon(
                        viewModel.showMediaOverlay.value
                            ? Icons.layers_rounded
                            : Icons.layers_clear_rounded,
                        color: viewModel.showMediaOverlay.value
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      size: AppTheme.metrics.kSpace40,
                      onTap: () =>
                          viewModel.showMediaOverlay.value = !viewModel.showMediaOverlay.value,
                    ),
                  ),
                // 移动端详情模式：列数调节 + 资源排序 + 上传（桌面端此控件在 leading 区域）
                if (showMobileDetailControls) ...[
                  if (onUpload != null)
                    Tooltip(
                      message: '上传文件到当前集合',
                      child: IconButton(
                        icon: const Icon(Icons.upload_rounded),
                        iconSize: scaleW(18),
                        padding: EdgeInsets.all(AppTheme.metrics.kSpace4),
                        constraints: BoxConstraints(minWidth: scaleW(28), minHeight: scaleW(28)),
                        onPressed: onUpload,
                      ),
                    ),
                  Icon(
                    Icons.grid_view_rounded,
                    size: scaleW(16),
                    color: Theme.of(context).hintColor,
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_rounded),
                    iconSize: scaleW(16),
                    padding: EdgeInsets.all(AppTheme.metrics.kSpace4),
                    constraints: BoxConstraints(minWidth: scaleW(28), minHeight: scaleW(28)),
                    tooltip: '减少列数',
                    onPressed: (columnCount! > 1) ? onColumnDecrement : null,
                  ),
                  Text('$columnCount 列', style: Theme.of(context).textTheme.bodySmall),
                  IconButton(
                    icon: const Icon(Icons.add_rounded),
                    iconSize: scaleW(16),
                    padding: EdgeInsets.all(AppTheme.metrics.kSpace4),
                    constraints: BoxConstraints(minWidth: scaleW(28), minHeight: scaleW(28)),
                    tooltip: '增加列数',
                    onPressed: (columnCount! < 10) ? onColumnIncrement : null,
                  ),
                  SizedBox(width: AppTheme.metrics.kSpace4),
                  PopupMenuButton<MediaItemSortOrder>(
                    tooltip: '排序',
                    icon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [Icon(Icons.sort_rounded, size: scaleW(18))],
                    ),
                    onSelected: (v) => viewModel.itemSortOrder.value = v,
                    itemBuilder: (_) => MediaItemSortOrder.values
                        .map(
                          (o) => PopupMenuItem<MediaItemSortOrder>(
                            value: o,
                            child: Row(
                              children: [
                                if (viewModel.itemSortOrder.value == o)
                                  Icon(Icons.check_rounded, size: scaleW(16))
                                else
                                  SizedBox(width: scaleW(16)),
                                SizedBox(width: AppTheme.metrics.kSpace8),
                                Text(o.label),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
                // 桌面端/移动端详情模式：瀑布流布局切换
                if (inDetail)
                  Tooltip(
                    message: viewModel.useMasonryGrid.value ? '切换为网格布局' : '切换为瀑布流布局',
                    child: DesktopHeadToolsButton(
                      icon: Icon(
                        viewModel.useMasonryGrid.value
                            ? Icons.view_comfy_rounded
                            : Icons.grid_view_rounded,
                        color: viewModel.useMasonryGrid.value
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      size: AppTheme.metrics.kSpace40,
                      onTap: () => viewModel.useMasonryGrid.value = !viewModel.useMasonryGrid.value,
                    ),
                  ),
                // 刷新/同步按钮（始终显示）
                DesktopHeadToolsButton(
                  icon: const Icon(Icons.refresh),
                  size: AppTheme.metrics.kSpace40,
                  onTap: onRefresh,
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

/// 库内搜索框：点击图标展开输入，输入即过滤；
/// 清除按钮清空关键词并收起，过滤立即解除。
class _LibrarySearchField extends StatefulWidget {
  const _LibrarySearchField({required this.viewModel, required this.hintText});

  final MediaLibraryViewModel viewModel;

  /// 输入框占位文案（浏览/详情两种模式）。
  final String hintText;

  @override
  State<_LibrarySearchField> createState() => _LibrarySearchFieldState();
}

class _LibrarySearchFieldState extends State<_LibrarySearchField> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.viewModel.searchQuery.value);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final active = widget.viewModel.isSearchActive.value;
      if (!active) {
        return Tooltip(
          message: '搜索',
          child: DesktopHeadToolsButton(
            icon: const Icon(Icons.search_rounded),
            size: AppTheme.metrics.kSpace40,
            onTap: () {
              widget.viewModel.isSearchActive.value = true;
              _focusNode.requestFocus();
            },
          ),
        );
      }
      return Row(
        mainAxisSize: MainAxisSize.min,
        spacing: AppTheme.metrics.kSpace4,
        children: [
          SizedBox(
            width: scaleW(150),
            height: AppTheme.metrics.kSpace32,
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              onChanged: (value) => widget.viewModel.searchQuery.value = value,
              style: Theme.of(context).textTheme.bodySmall,
              decoration: InputDecoration(
                hintText: widget.hintText,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppTheme.metrics.kSpace8,
                  vertical: AppTheme.metrics.kSpace4,
                ),
                border: OutlineInputBorder(
                  borderRadius: AppTheme.metrics.radius8,
                  borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                ),
              ),
            ),
          ),
          Tooltip(
            message: '清除搜索',
            child: DesktopHeadToolsButton(
              icon: const Icon(Icons.close_rounded),
              size: AppTheme.metrics.kSpace40,
              onTap: () {
                _controller.clear();
                widget.viewModel.searchQuery.value = '';
                widget.viewModel.isSearchActive.value = false;
              },
            ),
          ),
        ],
      );
    });
  }
}

/// 封面生成进度指示器：默认显示进度环 + 百分比，
/// 鼠标悬停时额外显示取消按钮（暂停封面生成）。
/// [onCancel] 为 null 时表示远程节点任务，仅展示进度不可取消。
class _ThumbProgressIndicator extends StatefulWidget {
  const _ThumbProgressIndicator({required this.progress, this.onCancel});

  final (int, int) progress;
  final VoidCallback? onCancel;

  @override
  State<_ThumbProgressIndicator> createState() => _ThumbProgressIndicatorState();
}

class _ThumbProgressIndicatorState extends State<_ThumbProgressIndicator> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final completed = widget.progress.$1;
    final total = widget.progress.$2;
    final isRemote = widget.onCancel == null;
    final label = isRemote ? '节点封面生成中' : '封面生成中';
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Tooltip(
        message: isRemote ? '$label $completed/$total（远程节点任务）' : '$label $completed/$total（悬停可取消）',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: AppTheme.metrics.kSpace4,
          children: [
            SizedBox(
              width: AppTheme.metrics.kSpace18,
              height: AppTheme.metrics.kSpace18,
              child: CircularProgressIndicator(
                value: total > 0 ? completed / total : 0,
                strokeWidth: 2,
              ),
            ),
            Text(
              '$label $completed/$total',
              style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor),
            ),
            // 悬停时显示取消按钮（仅本地任务）
            if (_hovering && !isRemote)
              Tooltip(
                message: '暂停封面生成',
                child: InkWell(
                  onTap: widget.onCancel,
                  borderRadius: AppTheme.metrics.radius999,
                  child: Padding(
                    padding: EdgeInsets.all(AppTheme.metrics.kSpace4),
                    child: Icon(
                      Icons.cancel_outlined,
                      size: AppTheme.metrics.iconSize16,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 封面生成已暂停指示器：提供恢复按钮继续生成。
class _ThumbPausedIndicator extends StatelessWidget {
  const _ThumbPausedIndicator({required this.onResume});

  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '封面生成已暂停',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: AppTheme.metrics.kSpace4,
        children: [
          Text('封面生成已暂停', style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
          Tooltip(
            message: '继续生成封面',
            child: InkWell(
              onTap: onResume,
              borderRadius: AppTheme.metrics.radius999,
              child: Padding(
                padding: EdgeInsets.all(AppTheme.metrics.kSpace4),
                child: Icon(
                  Icons.play_circle_outline_rounded,
                  size: AppTheme.metrics.iconSize16,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
