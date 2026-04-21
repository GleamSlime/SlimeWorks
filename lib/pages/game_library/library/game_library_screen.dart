import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:slime_works/core/services/game_process_tracker.dart';
import 'package:slime_works/pages/game_library/models/game_library_models.dart';
import 'package:slime_works/view_models/game_library/game_library_library_viewmodel.dart';

class GameLibraryScreen extends BasePage<GameLibraryViewModel> {
  const GameLibraryScreen({super.key});

  @override
  State<GameLibraryScreen> createState() => _GameLibraryScreenState();
}

class _GameLibraryScreenState extends BasePageState<GameLibraryViewModel, GameLibraryScreen> {
  bool _isDraggingExternalPaths = false;

  // 键盘 & 框选状态
  final FocusNode _focusNode = FocusNode();
  final ScrollController _gridScrollController = ScrollController();
  Offset? _boxStart;
  Offset? _boxEnd;
  // 临时记录 layoutbuilder 状态供框选计算
  int _crossAxisCount = 2;
  double _gridAreaWidth = 0;

  @override
  void dispose() {
    _focusNode.dispose();
    _gridScrollController.dispose();
    super.dispose();
  }

  @override
  bool get showAppBar => false;

  @override
  GameLibraryViewModel createViewModel() => GameLibraryViewModel();

  ScreenChromeData _buildChromeData() {
    return ScreenChromeData(
      title: '游戏库',
      actions: <Widget>[
        OutlinedButton.icon(
          onPressed: _batchImport,
          icon: const Icon(Icons.drive_folder_upload_outlined),
          label: const Text('批量导入'),
        ),
        FilledButton.icon(
          onPressed: _showAddDialog,
          icon: const Icon(Icons.add),
          label: const Text('添加游戏'),
        ),
        IconButton(
          onPressed: () => GameCategoriesRoute().go(context),
          icon: const Icon(Icons.folder_copy_outlined),
          tooltip: '分类管理',
        ),
        IconButton(
          onPressed: () => GameStatsRoute().go(context),
          icon: const Icon(Icons.query_stats),
          tooltip: '统计',
        ),
      ],
      toolbarHeight: AppTheme.metrics.kSpace48,
      toolbar: Obx(() {
        return Row(
          children: <Widget>[
            SizedBox(
              width: 220,
              child: TextField(
                decoration: const InputDecoration(
                  hintText: '搜索游戏 / 公司 / 标签',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (String value) => viewModel.searchQuery.value = value,
              ),
            ),
            SizedBox(width: AppTheme.metrics.kSpace8),
            DropdownButton<GameStatus?>(
              value: viewModel.selectedStatus.value,
              items: <DropdownMenuItem<GameStatus?>>[
                const DropdownMenuItem<GameStatus?>(value: null, child: Text('全部状态')),
                ...GameStatus.values.map(
                  (GameStatus e) => DropdownMenuItem<GameStatus?>(value: e, child: Text(e.label)),
                ),
              ],
              onChanged: (GameStatus? value) => viewModel.selectedStatus.value = value,
            ),
            SizedBox(width: AppTheme.metrics.kSpace8),
            DropdownButton<String>(
              value: viewModel.selectedSort.value,
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(value: 'updatedAt_desc', child: Text('最近更新')),
                DropdownMenuItem<String>(value: 'name_asc', child: Text('名称 A-Z')),
                DropdownMenuItem<String>(value: 'name_desc', child: Text('名称 Z-A')),
                DropdownMenuItem<String>(value: 'rating_desc', child: Text('评分高到低')),
                DropdownMenuItem<String>(value: 'release_desc', child: Text('发售新到旧')),
                DropdownMenuItem<String>(value: 'last_played_desc', child: Text('最近游玩')),
              ],
              onChanged: (String? value) {
                if (value != null) {
                  viewModel.selectedSort.value = value;
                }
              },
            ),
          ],
        );
      }),
    );
  }

  @override
  Widget buildContent(BuildContext context) {
    final Widget body = Obx(() {
      final List<GameItem> items = viewModel.filteredGames;
      if (items.isEmpty) {
        return Center(
          child: Text('暂无游戏，点击右上角「添加游戏」开始迁移。', style: Theme.of(context).textTheme.bodyLarge),
        );
      }

      return Column(
        children: <Widget>[
          // 多选工具栏（选中时才显示）
          Obx(() {
            final int count = viewModel.selectedIds.length;
            if (count == 0) {
              return const SizedBox.shrink();
            }
            return Material(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: AppTheme.metrics.kSpace16,
                  vertical: AppTheme.metrics.kSpace8,
                ),
                child: Row(
                  children: <Widget>[
                    Text(
                      '已选 $count 个游戏',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: viewModel.selectAll,
                      icon: const Icon(Icons.select_all, size: 18),
                      label: Text(
                        viewModel.selectedIds.length == viewModel.filteredGames.length
                            ? '取消全选'
                            : '全选',
                      ),
                    ),
                    SizedBox(width: AppTheme.metrics.kSpace8),
                    OutlinedButton.icon(
                      onPressed: () => _batchRefreshMetadata(),
                      icon: const Icon(Icons.cloud_download_outlined, size: 18),
                      label: const Text('刷新元数据'),
                    ),
                    SizedBox(width: AppTheme.metrics.kSpace8),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                      ),
                      onPressed: () => _confirmBatchDelete(),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('批量删除'),
                    ),
                    SizedBox(width: AppTheme.metrics.kSpace8),
                    IconButton(
                      onPressed: viewModel.clearSelection,
                      icon: const Icon(Icons.close),
                      tooltip: '取消选择',
                    ),
                  ],
                ),
              ),
            );
          }),
          // 游戏网格
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final int crossAxisCount = (constraints.maxWidth / 180).floor().clamp(2, 8);
                // 保存最新布局参数供框选计算使用
                _crossAxisCount = crossAxisCount;
                _gridAreaWidth = constraints.maxWidth;

                final Widget grid = GridView.builder(
                  controller: _gridScrollController,
                  // 框选模式下禁止滚动，避免和拖拽手势冲突
                  physics: viewModel.isSelecting
                      ? const NeverScrollableScrollPhysics()
                      : const ClampingScrollPhysics(),
                  padding: EdgeInsets.all(AppTheme.metrics.kSpace16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    childAspectRatio: 0.62,
                    crossAxisSpacing: AppTheme.metrics.kSpace12,
                    mainAxisSpacing: AppTheme.metrics.kSpace12,
                  ),
                  itemCount: items.length,
                  itemBuilder: (BuildContext context, int index) {
                    final GameItem game = items[index];
                    return Obx(() {
                      final bool running = getIt<GameProcessTracker>().isRunning(game.id);
                      final bool isSelected = viewModel.selectedIds.contains(game.id);
                      return _GameCard(
                        game: game,
                        isFavorite: viewModel.isFavorite(game.id),
                        isRunning: running,
                        isSelected: isSelected,
                        formatDuration: viewModel.formatDuration,
                        onTap: () {
                          if (viewModel.isSelecting) {
                            viewModel.toggleSelect(game.id);
                          } else {
                            // 导航前预设封面背景，确保过渡动画期间背景已就绪
                            final String cover = game.coverPath.trim();
                            if (cover.isNotEmpty) {
                              getIt<DesktopScreenProvider>().globalBackgroundPath.value = cover;
                            }
                            GameDetailRoute(gameId: game.id).push<void>(context);
                          }
                        },
                        onLongPress: () => viewModel.toggleSelect(game.id),
                        onToggleFavorite: () => viewModel.toggleFavorite(game),
                        onLaunch: () => _launchGameFromCard(game),
                        onDelete: () => _confirmDelete(game),
                        onSelect: () => viewModel.toggleSelect(game.id),
                        onRefreshMeta: () => _refreshSingleMeta(game),
                      );
                    });
                  },
                );

                if (!viewModel.isSelecting) {
                  return grid;
                }

                // 框选手势覆盖层（仅在选择模式下激活）
                return GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanStart: (DragStartDetails d) {
                    setState(() {
                      _boxStart = d.localPosition;
                      _boxEnd = d.localPosition;
                    });
                  },
                  onPanUpdate: (DragUpdateDetails d) {
                    setState(() => _boxEnd = d.localPosition);
                    if (_boxStart != null && _boxEnd != null) {
                      final double scrollOffset = _gridScrollController.hasClients
                          ? _gridScrollController.offset
                          : 0.0;
                      final List<int> selected = _computeBoxSelectedIndices(
                        start: _boxStart! + Offset(0, scrollOffset),
                        end: _boxEnd! + Offset(0, scrollOffset),
                        crossAxisCount: crossAxisCount,
                        gridWidth: constraints.maxWidth,
                        itemCount: items.length,
                        scrollOffset: scrollOffset,
                      );
                      viewModel.setSelectedFromIndices(selected, items);
                    }
                  },
                  onPanEnd: (_) => setState(() {
                    _boxStart = null;
                    _boxEnd = null;
                  }),
                  onPanCancel: () => setState(() {
                    _boxStart = null;
                    _boxEnd = null;
                  }),
                  child: Stack(
                    children: <Widget>[
                      grid,
                      if (_boxStart != null && _boxEnd != null)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _BoxSelectPainter(
                                start: _boxStart!,
                                end: _boxEnd!,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      );
    });

    final Widget desktopDropBody = (Platform.isAndroid || Platform.isIOS)
        ? body
        : DropTarget(
            onDragEntered: (_) {
              setState(() {
                _isDraggingExternalPaths = true;
              });
            },
            onDragExited: (_) {
              setState(() {
                _isDraggingExternalPaths = false;
              });
            },
            onDragDone: (DropDoneDetails details) async {
              setState(() {
                _isDraggingExternalPaths = false;
              });
              await _importDroppedPaths(details.files.map((file) => file.path).toList());
            },
            child: Stack(
              children: <Widget>[
                body,
                if (_isDraggingExternalPaths)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withAlpha(36),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                Icons.inventory_2_outlined,
                                size: 64,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              SizedBox(height: AppTheme.metrics.kSpace12),
                              Text(
                                '松开以导入游戏文件夹',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );

    return ScreenChrome(
      data: _buildChromeData(),
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (FocusNode node, KeyEvent event) {
          if (event is KeyDownEvent) {
            final bool ctrlHeld =
                HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed;
            if (ctrlHeld && event.logicalKey == LogicalKeyboardKey.keyA) {
              viewModel.selectAll();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              viewModel.clearSelection();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: desktopDropBody,
      ),
    );
  }

  Future<void> _importDroppedPaths(List<String> droppedPaths) async {
    final BuildContext currentContext = context;
    final int count = await viewModel.batchImportFromDroppedPaths(droppedPaths);
    if (!currentContext.mounted) {
      return;
    }
    if (count <= 0) {
      ScaffoldMessenger.of(
        currentContext,
      ).showSnackBar(const SnackBar(content: Text('未从拖拽内容中识别到可导入游戏')));
      return;
    }
    ScaffoldMessenger.of(
      currentContext,
    ).showSnackBar(SnackBar(content: Text('拖拽导入成功，共导入 $count 个游戏')));
  }

  Future<void> _confirmDelete(GameItem game) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('删除游戏'),
          content: Text('确认删除 ${game.name} 吗？此操作会删除游玩记录。'),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('删除')),
          ],
        );
      },
    );

    if (ok == true) {
      await viewModel.deleteGame(game.id);
    }
  }

  Future<void> _showAddDialog() async {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController companyController = TextEditingController();
    final TextEditingController summaryController = TextEditingController();
    final TextEditingController ratingController = TextEditingController(text: '8.0');
    final TextEditingController releaseDateController = TextEditingController();
    final TextEditingController pathController = TextEditingController();
    final TextEditingController coverController = TextEditingController();

    GameStatus selectedStatus = GameStatus.notStarted;

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, void Function(void Function()) setState) {
            return AlertDialog(
              title: const Text('添加游戏'),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: '游戏名'),
                      ),
                      TextField(
                        controller: companyController,
                        decoration: const InputDecoration(labelText: '公司'),
                      ),
                      TextField(
                        controller: summaryController,
                        decoration: const InputDecoration(labelText: '简介'),
                      ),
                      TextField(
                        controller: ratingController,
                        decoration: const InputDecoration(labelText: '评分 (0-10)'),
                        keyboardType: TextInputType.number,
                      ),
                      TextField(
                        controller: releaseDateController,
                        decoration: const InputDecoration(labelText: '发售日期 (YYYY-MM-DD)'),
                      ),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: TextField(
                              controller: pathController,
                              decoration: const InputDecoration(labelText: '启动路径（桌面端可用）'),
                            ),
                          ),
                          IconButton(
                            onPressed: () async {
                              final String? picked = await viewModel.pickExecutablePath();
                              if (picked != null) {
                                pathController.text = picked;
                                // 若游戏名仍为空，从路径自动推导文件夹名
                                if (nameController.text.trim().isEmpty) {
                                  final String derived = viewModel.deriveGameName(picked);
                                  if (derived.isNotEmpty) {
                                    nameController.text = derived;
                                  }
                                }
                              }
                            },
                            icon: const Icon(Icons.folder_open),
                          ),
                        ],
                      ),
                      TextField(
                        controller: coverController,
                        decoration: const InputDecoration(labelText: '封面路径（可选）'),
                      ),
                      SizedBox(height: AppTheme.metrics.kSpace8),
                      DropdownButtonFormField<GameStatus>(
                        initialValue: selectedStatus,
                        decoration: const InputDecoration(labelText: '状态'),
                        items: GameStatus.values
                            .map(
                              (GameStatus e) =>
                                  DropdownMenuItem<GameStatus>(value: e, child: Text(e.label)),
                            )
                            .toList(growable: false),
                        onChanged: (GameStatus? value) {
                          if (value != null) {
                            setState(() {
                              selectedStatus = value;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
                FilledButton(
                  onPressed: () async {
                    final double rating = double.tryParse(ratingController.text.trim()) ?? 0;
                    final GameItem? game = await viewModel.addGame(
                      name: nameController.text,
                      company: companyController.text,
                      summary: summaryController.text,
                      rating: rating,
                      releaseDate: releaseDateController.text,
                      path: pathController.text,
                      status: selectedStatus,
                      coverPath: coverController.text,
                    );
                    if (game == null) return;
                    if (!context.mounted) return;
                    Navigator.of(context).pop();
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    companyController.dispose();
    summaryController.dispose();
    ratingController.dispose();
    releaseDateController.dispose();
    pathController.dispose();
    coverController.dispose();
  }

  Future<void> _confirmBatchDelete() async {
    final int count = viewModel.selectedIds.length;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('批量删除'),
        content: Text('确认删除选中的 $count 个游戏？此操作不可撤销。'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await viewModel.batchDelete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已删除 $count 个游戏')));
      }
    }
  }

  Future<void> _batchRefreshMetadata() async {
    final int count = viewModel.selectedIds.length;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('正在刷新 $count 个游戏元数据...')));
    await viewModel.batchRefreshMetadata();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('元数据刷新完成')));
    }
  }

  Future<void> _refreshSingleMeta(GameItem game) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('正在刷新 ${game.name} 元数据...')));
    final Set<String> saved = Set<String>.from(viewModel.selectedIds);
    viewModel.selectedIds.assignAll(<String>{game.id});
    await viewModel.batchRefreshMetadata();
    viewModel.selectedIds.assignAll(saved);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${game.name} 元数据已刷新')));
    }
  }

  Future<void> _batchImport() async {
    final BuildContext currentContext = context;
    final int count = await viewModel.batchImportFromDirectory();
    if (!currentContext.mounted) {
      return;
    }
    if (count <= 0) {
      ScaffoldMessenger.of(
        currentContext,
      ).showSnackBar(const SnackBar(content: Text('未导入新游戏（仅导入 API 能搜索到的游戏）')));
      return;
    }
    ScaffoldMessenger.of(currentContext).showSnackBar(SnackBar(content: Text('成功导入 $count 个游戏')));
  }

  /// 从卡片启动游戏；若含多个 exe 且无默认，则弹窗选择
  Future<void> _launchGameFromCard(GameItem game) async {
    final List<String> exePaths = viewModel.getGameExePaths(game);
    String? selectedExe;

    if (exePaths.length > 1 && (game.path.trim().isEmpty || !File(game.path.trim()).existsSync())) {
      // 需要用户选择启动 exe
      if (!mounted) return;
      selectedExe = await _showExePickerDialog(exePaths);
      if (selectedExe == null) return; // 用户取消
    }

    await viewModel.launchGame(game, overrideExePath: selectedExe);
    if (viewModel.errorMessage != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(viewModel.errorMessage!)));
    }
  }

  /// 弹出 exe 选择对话框，返回用户选择的 exe 路径，取消时返回 null
  Future<String?> _showExePickerDialog(List<String> exePaths) async {
    return showDialog<String>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('选择启动文件'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: exePaths
                  .map((String p) {
                    final String name = p.split(Platform.pathSeparator).last;
                    return ListTile(
                      leading: const Icon(Icons.play_arrow_outlined),
                      title: Text(name),
                      subtitle: Text(
                        p,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                      onTap: () => Navigator.of(ctx).pop(p),
                    );
                  })
                  .toList(growable: false),
            ),
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 框选辅助函数
// ─────────────────────────────────────────────────────────────────────────────

/// 计算在 [start]..[end] 框内（滚动坐标系）的 item 索引列表
List<int> _computeBoxSelectedIndices({
  required Offset start,
  required Offset end,
  required int crossAxisCount,
  required double gridWidth,
  required int itemCount,
  required double scrollOffset,
}) {
  final double pad = AppTheme.metrics.kSpace16;
  final double spacing = AppTheme.metrics.kSpace12;
  final double totalSpacing = spacing * (crossAxisCount - 1);
  final double itemWidth = (gridWidth - 2 * pad - totalSpacing) / crossAxisCount;
  final double itemHeight = itemWidth / 0.62;

  final Rect selRect = Rect.fromPoints(start, end);
  final List<int> result = <int>[];
  for (int i = 0; i < itemCount; i++) {
    final int col = i % crossAxisCount;
    final int row = i ~/ crossAxisCount;
    final double left = pad + col * (itemWidth + spacing);
    final double top = pad + row * (itemHeight + spacing);
    final Rect itemRect = Rect.fromLTWH(left, top, itemWidth, itemHeight);
    if (selRect.overlaps(itemRect)) {
      result.add(i);
    }
  }
  return result;
}

// ─────────────────────────────────────────────────────────────────────────────
// 框选矩形绘制
// ─────────────────────────────────────────────────────────────────────────────

class _BoxSelectPainter extends CustomPainter {
  const _BoxSelectPainter({required this.start, required this.end, required this.color});

  final Offset start;
  final Offset end;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Rect.fromPoints(start, end);
    canvas.drawRect(
      rect,
      Paint()
        ..color = color.withAlpha(40)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_BoxSelectPainter old) =>
      old.start != start || old.end != end || old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// 游戏封面卡片（网格视图专用）
// ─────────────────────────────────────────────────────────────────────────────

class _GameCard extends StatefulWidget {
  const _GameCard({
    required this.game,
    required this.isFavorite,
    required this.isRunning,
    required this.isSelected,
    required this.formatDuration,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleFavorite,
    required this.onLaunch,
    required this.onDelete,
    required this.onSelect,
    required this.onRefreshMeta,
  });

  final GameItem game;
  final bool isFavorite;
  final bool isRunning;
  final bool isSelected;
  final String Function(int) formatDuration;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggleFavorite;
  final VoidCallback onLaunch;
  final VoidCallback onDelete;
  final VoidCallback onSelect;
  final VoidCallback onRefreshMeta;

  @override
  State<_GameCard> createState() => _GameCardState();
}

class _GameCardState extends State<_GameCard> {
  bool _hover = false;

  void _showContextMenu(BuildContext context, Offset globalPosition) {
    final RenderBox? overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final Offset localPos = overlay.globalToLocal(globalPosition);
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        localPos.dx,
        localPos.dy,
        overlay.size.width - localPos.dx,
        overlay.size.height - localPos.dy,
      ),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'select',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(widget.isSelected ? Icons.check_box_outlined : Icons.check_box_outline_blank),
            title: Text(widget.isSelected ? '取消选择' : '选择'),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'launch',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.play_circle_outline),
            title: Text('启动游戏'),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'favorite',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(widget.isFavorite ? Icons.favorite : Icons.favorite_border),
            title: Text(widget.isFavorite ? '取消收藏' : '添加收藏'),
          ),
        ),
        const PopupMenuItem<String>(
          value: 'refresh_meta',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.cloud_download_outlined),
            title: Text('刷新元数据'),
          ),
        ),
        const PopupMenuItem<String>(
          value: 'open_folder',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.folder_open_outlined),
            title: Text('打开所在文件夹'),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'delete',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_outline, color: Colors.red),
            title: Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ),
      ],
    ).then((String? value) {
      switch (value) {
        case 'select':
          widget.onSelect();
          break;
        case 'launch':
          widget.onLaunch();
          break;
        case 'favorite':
          widget.onToggleFavorite();
          break;
        case 'refresh_meta':
          widget.onRefreshMeta();
          break;
        case 'open_folder':
          _openContainingFolder();
          break;
        case 'delete':
          widget.onDelete();
          break;
      }
    });
  }

  void _openContainingFolder() {
    final String openPath = widget.game.gameDir.trim().isNotEmpty
        ? widget.game.gameDir.trim()
        : (widget.game.path.trim().isNotEmpty ? File(widget.game.path).parent.path : '');
    if (openPath.isEmpty) return;
    try {
      if (Platform.isWindows) {
        Process.start('explorer.exe', <String>[openPath]);
      } else if (Platform.isMacOS) {
        Process.start('open', <String>[openPath]);
      } else {
        Process.start('xdg-open', <String>[openPath]);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final bool isSelected = widget.isSelected;
    return GestureDetector(
      onSecondaryTapUp: (TapUpDetails details) => _showContextMenu(context, details.globalPosition),
      onLongPress: widget.onLongPress,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: isSelected
                ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2.5)
                : null,
          ),
          child: Card(
            clipBehavior: Clip.antiAlias,
            margin: EdgeInsets.zero,
            child: InkWell(
              onTap: widget.onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // 封面图（占卡片上方约65%）
                  Expanded(
                    flex: 65,
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        AnimatedScale(
                          scale: _hover ? 1.06 : 1.0,
                          duration: const Duration(milliseconds: 160),
                          child: _buildCover(context),
                        ),
                        // 多选时左上角勾选标记
                        if (isSelected)
                          Positioned(
                            top: 4,
                            left: 4,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.check, color: Colors.white, size: 16),
                            ),
                          ),
                        // 右上角收藏/菜单
                        Positioned(
                          top: 4,
                          right: 4,
                          child: PopupMenuButton<String>(
                            icon: Container(
                              decoration: const BoxDecoration(
                                color: Colors.black38,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.more_vert, color: Colors.white, size: 18),
                            ),
                            onSelected: (String value) {
                              switch (value) {
                                case 'favorite':
                                  widget.onToggleFavorite();
                                  break;
                                case 'launch':
                                  widget.onLaunch();
                                  break;
                                case 'delete':
                                  widget.onDelete();
                                  break;
                                case 'open_folder':
                                  _openContainingFolder();
                                  break;
                              }
                            },
                            itemBuilder: (_) => <PopupMenuEntry<String>>[
                              PopupMenuItem<String>(
                                value: 'favorite',
                                child: ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(widget.isFavorite ? Icons.favorite : Icons.favorite_border),
                                  title: Text(widget.isFavorite ? '取消收藏' : '添加收藏'),
                                ),
                              ),
                              const PopupMenuItem<String>(
                                value: 'launch',
                                child: ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.play_circle_outline),
                                  title: Text('启动游戏'),
                                ),
                              ),
                              const PopupMenuItem<String>(
                                value: 'open_folder',
                                child: ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.folder_open_outlined),
                                  title: Text('打开所在文件夹'),
                                ),
                              ),
                              const PopupMenuItem<String>(
                                value: 'delete',
                                child: ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.delete_outline, color: Colors.red),
                                  title: Text('删除', style: TextStyle(color: Colors.red)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // 状态徽章（左下角）
                        Positioned(
                          left: 6,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              widget.game.status.label,
                              style: const TextStyle(color: Colors.white, fontSize: 10),
                            ),
                          ),
                        ),
                        // 游戏运行中提示（居中显示在封面上方）
                        if (widget.isRunning)
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(color: Colors.black.withAlpha(100)),
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(height: 6),
                                  Text(
                                    '游戏运行中',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // 信息区（占约35%）
                  Expanded(
                    flex: 35,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            widget.game.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(
                              context,
                            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          if (widget.game.company.isNotEmpty && widget.game.company != '未知')
                            Text(
                              widget.game.company,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          const Spacer(),
                          Row(
                            children: <Widget>[
                              if (widget.game.rating > 0) ...<Widget>[
                                const Icon(Icons.star_rounded, size: 12, color: Colors.amber),
                                const SizedBox(width: 2),
                                Text(
                                  widget.game.rating.toStringAsFixed(1),
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                                const SizedBox(width: 8),
                              ],
                              Expanded(
                                child: Text(
                                  widget.formatDuration(widget.game.totalPlayTimeSec),
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (widget.isFavorite)
                                const Icon(Icons.favorite, size: 12, color: Colors.pink),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCover(BuildContext context) {
    final String value = widget.game.coverPath.trim();
    if (value.isEmpty) {
      return _placeholder(context);
    }
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return CachedNetworkImage(
        imageUrl: value,
        fit: BoxFit.cover,
        placeholder: (_, __) => _placeholder(context),
        errorWidget: (_, __, ___) => _placeholder(context),
      );
    }
    final File file = File(value);
    if (file.existsSync()) {
      return Image.file(file, fit: BoxFit.cover, alignment: Alignment.center);
    }
    return _placeholder(context);
  }

  Widget _placeholder(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Theme.of(context).colorScheme.primaryContainer,
            Theme.of(context).colorScheme.secondaryContainer,
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.sports_esports_outlined,
              size: 32,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 4),
            Text(
              widget.game.name.isNotEmpty ? widget.game.name[0].toUpperCase() : '?',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
