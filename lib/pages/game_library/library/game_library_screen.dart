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
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/core/widgets/app_text_field.dart';

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
          icon: DrawIcon(StrokeIcons.driveFolderUpload),
          label: const Text('批量导入'),
        ),
        FilledButton.icon(onPressed: _showAddDialog, icon: DrawIcon(StrokeIcons.add), label: const Text('添加游戏')),
        IconButton(
          onPressed: () => const GameCategoriesRoute().go(context),
          icon: DrawIcon(StrokeIcons.folderCopy),
          tooltip: '分类管理',
        ),
        IconButton(
          onPressed: () => const GameStatsRoute().go(context),
          icon: DrawIcon(StrokeIcons.queryStats),
          tooltip: '统计',
        ),
      ],
      toolbarHeight: AppTheme.metrics.kSpace48,
      toolbar: Obx(() {
        return Row(
          children: <Widget>[
            SizedBox(
              width: scaleW(220),
              child: AppTextField(
                decoration: const InputDecoration(
                  hintText: '搜索游戏 / 公司 / 标签',
                  prefixIcon: DrawIcon(StrokeIcons.search),
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
    final s = AppSemantic.of(context);
    final Widget body = Obx(() {
      final List<GameItem> items = viewModel.filteredGames;
      if (items.isEmpty) {
        return Center(
          child: Text(
            '暂无游戏，点击右上角「添加游戏」开始迁移。',
            style: AppTextStyles.role(
              context,
              fontSize: AppTheme.metrics.fontSize14,
              color: s.textPrimary,
              height: 1.7,
            ),
          ),
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
              color: s.accentContainer,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: AppTheme.metrics.kSpace16,
                  vertical: AppTheme.metrics.kSpace8,
                ),
                child: Row(
                  children: <Widget>[
                    Text(
                      '已选 $count 个游戏',
                      style: AppTextStyles.role(
                        context,
                        fontSize: AppTheme.metrics.fontSize13,
                        weight: FontWeight.w600,
                        color: s.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: viewModel.selectAll,
                      icon: DrawIcon(StrokeIcons.selectAll, size: AppTheme.metrics.iconSize18),
                      label: Text(
                        viewModel.selectedIds.length == viewModel.filteredGames.length
                            ? '取消全选'
                            : '全选',
                      ),
                    ),
                    SizedBox(width: AppTheme.metrics.kSpace8),
                    OutlinedButton.icon(
                      onPressed: () => _batchRefreshMetadata(),
                      icon: DrawIcon(StrokeIcons.cloudDownload, size: AppTheme.metrics.iconSize18),
                      label: const Text('刷新元数据'),
                    ),
                    SizedBox(width: AppTheme.metrics.kSpace8),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: s.danger.color,
                      ),
                      onPressed: () => _confirmBatchDelete(),
                      icon: DrawIcon(StrokeIcons.deleteOutline, size: AppTheme.metrics.iconSize18),
                      label: const Text('批量删除'),
                    ),
                    SizedBox(width: AppTheme.metrics.kSpace8),
                    IconButton(
                      onPressed: viewModel.clearSelection,
                      icon: DrawIcon(StrokeIcons.close),
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
                                color: s.accent,
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
                          color: s.accent.withAlpha(36),
                          border: Border.all(
                            color: s.accent,
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              DrawIcon(StrokeIcons.inventory2,
                                size: AppTheme.metrics.iconSize64,
                                color: s.accent,
                              ),
                              SizedBox(height: AppTheme.metrics.kSpace12),
                              Text(
                                '松开以导入游戏文件夹',
                                style: AppTextStyles.role(
                                  context,
                                  fontSize: AppTheme.metrics.fontSize14,
                                  weight: FontWeight.w700,
                                  color: s.accent,
                                  height: 1.55,
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
                width: scaleW(560),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      AppTextField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: '游戏名'),
                      ),
                      AppTextField(
                        controller: companyController,
                        decoration: const InputDecoration(labelText: '公司'),
                      ),
                      AppTextField(
                        controller: summaryController,
                        decoration: const InputDecoration(labelText: '简介'),
                      ),
                      AppTextField(
                        controller: ratingController,
                        decoration: const InputDecoration(labelText: '评分 (0-10)'),
                        keyboardType: TextInputType.number,
                      ),
                      AppTextField(
                        controller: releaseDateController,
                        decoration: const InputDecoration(labelText: '发售日期 (YYYY-MM-DD)'),
                      ),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: AppTextField(
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
                            icon: DrawIcon(StrokeIcons.folderOpen),
                          ),
                        ],
                      ),
                      AppTextField(
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
            style: FilledButton.styleFrom(
              backgroundColor: AppSemantic.of(ctx).danger.color,
            ),
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
            width: scaleW(400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: exePaths
                  .map((String p) {
                    final String name = p.split(Platform.pathSeparator).last;
                    return ListTile(
                      leading: DrawIcon(StrokeIcons.playArrow),
                      title: Text(name),
                      subtitle: Text(
                        p,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption(ctx),
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
        GlassMenuItem<String>(
          value: 'select',
          label: widget.isSelected ? '取消选择' : '选择',
          icon: widget.isSelected
              ? StrokeIcons.checkBox
              : StrokeIcons.checkBoxOutlineBlank,
        ),
        const PopupMenuDivider(),
        GlassMenuItem<String>(
          value: 'launch',
          label: '启动游戏',
          icon: StrokeIcons.playCircleOutline,
        ),
        const PopupMenuDivider(),
        GlassMenuItem<String>(
          value: 'favorite',
          label: widget.isFavorite ? '取消收藏' : '添加收藏',
          icon: widget.isFavorite ? StrokeIcons.favorite : StrokeIcons.favoriteBorder,
        ),
        GlassMenuItem<String>(
          value: 'refresh_meta',
          label: '刷新元数据',
          icon: StrokeIcons.cloudDownload,
        ),
        GlassMenuItem<String>(
          value: 'open_folder',
          label: '打开所在文件夹',
          icon: StrokeIcons.folderOpen,
        ),
        const PopupMenuDivider(),
        GlassMenuItem<String>(
          value: 'delete',
          label: '删除',
          icon: StrokeIcons.deleteOutline,
          destructive: true,
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
    final s = AppSemantic.of(context);
    final bool isSelected = widget.isSelected;
    return GestureDetector(
      onSecondaryTapUp: (TapUpDetails details) => _showContextMenu(context, details.globalPosition),
      onLongPress: widget.onLongPress,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          decoration: BoxDecoration(
            borderRadius: AppTheme.metrics.radius12,
            border: isSelected
                ? Border.all(color: s.accent, width: 2.5)
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
                          duration: AppMotion.fast,
                          child: _buildCover(context),
                        ),
                        // 多选时左上角勾选标记
                        if (isSelected)
                          Positioned(
                            top: AppTheme.metrics.kSpace4,
                            left: AppTheme.metrics.kSpace4,
                            child: Container(
                              decoration: BoxDecoration(
                                color: s.accent,
                                shape: BoxShape.circle,
                              ),
                              child: DrawIcon(StrokeIcons.check, color: s.accentOn, size: AppTheme.metrics.iconSize16),
                            ),
                          ),
                        // 右上角收藏/菜单
                        Positioned(
                          top: AppTheme.metrics.kSpace4,
                          right: AppTheme.metrics.kSpace4,
                          child: PopupMenuButton<String>(
                            icon: Container(
                              decoration: const BoxDecoration(
                                color: Colors.black38,
                                shape: BoxShape.circle,
                              ),
                              child: DrawIcon(StrokeIcons.moreVert, color: Colors.white, size: AppTheme.metrics.iconSize18),
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
                              GlassMenuItem<String>(
                                value: 'favorite',
                                label: widget.isFavorite ? '取消收藏' : '添加收藏',
                                icon: widget.isFavorite
                                    ? StrokeIcons.favorite
                                    : StrokeIcons.favoriteBorder,
                              ),
                              GlassMenuItem<String>(
                                value: 'launch',
                                label: '启动游戏',
                                icon: StrokeIcons.playCircleOutline,
                              ),
                              GlassMenuItem<String>(
                                value: 'open_folder',
                                label: '打开所在文件夹',
                                icon: StrokeIcons.folderOpen,
                              ),
                              GlassMenuItem<String>(
                                value: 'delete',
                                label: '删除',
                                icon: StrokeIcons.deleteOutline,
                                destructive: true,
                              ),
                            ],
                          ),
                        ),
                        // 状态徽章（左下角）
                        Positioned(
                          left: AppTheme.metrics.kSpace6,
                          bottom: AppTheme.metrics.kSpace6,
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace6, vertical: AppTheme.metrics.kSpace2),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: AppTheme.metrics.radius4,
                            ),
                            child: Text(
                              widget.game.status.label,
                              // 封面上的徽章是恒定浅色（不随主题翻转），走 onMedia 白
                              style: AppTextStyles.role(
                                context,
                                fontSize: AppTheme.metrics.fontSize10,
                                color: Colors.white,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ),
                        // 游戏运行中提示（居中显示在封面上方）
                        if (widget.isRunning)
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(color: Colors.black.withAlpha(100)),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  SizedBox(
                                    width: AppTheme.metrics.kSpace24,
                                    height: AppTheme.metrics.kSpace24,
                                    child: const CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(height: AppTheme.metrics.kSpace6),
                                  Text(
                                    '游戏运行中',
                                    // 封面上的提示是恒定浅色（不随主题翻转）
                                    style: AppTextStyles.role(
                                      context,
                                      fontSize: AppTheme.metrics.fontSize11,
                                      weight: FontWeight.w600,
                                      color: Colors.white,
                                      height: 1.2,
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
                      padding: EdgeInsets.symmetric(
                        horizontal: AppTheme.metrics.kSpace8,
                        vertical: AppTheme.metrics.kSpace6,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            widget.game.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.role(
                              context,
                              fontSize: AppTheme.metrics.fontSize13,
                              weight: FontWeight.w600,
                              color: s.textSecondary,
                            ),
                          ),
                          SizedBox(height: AppTheme.metrics.kSpace2),
                          if (widget.game.company.isNotEmpty && widget.game.company != '未知')
                            Text(
                              widget.game.company,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.role(
                                context,
                                fontSize: AppTheme.metrics.fontSize12,
                                color: s.textSecondary,
                                height: 1.6,
                              ),
                            ),
                          const Spacer(),
                          Row(
                            children: <Widget>[
                              if (widget.game.rating > 0) ...<Widget>[
                                DrawIcon(StrokeIcons.star, size: AppTheme.metrics.iconSize12, color: s.warning.color),
                                SizedBox(width: AppTheme.metrics.kSpace2),
                                Text(
                                  widget.game.rating.toStringAsFixed(1),
                                  style: AppTextStyles.role(
                                    context,
                                    fontSize: AppTheme.metrics.fontSize11,
                                    weight: FontWeight.w600,
                                    color: s.textTertiary,
                                    height: 1.5,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                                SizedBox(width: AppTheme.metrics.kSpace8),
                              ],
                              Expanded(
                                child: Text(
                                  widget.formatDuration(widget.game.totalPlayTimeSec),
                                  style: AppTextStyles.role(
                                    context,
                                    fontSize: AppTheme.metrics.fontSize11,
                                    weight: FontWeight.w600,
                                    color: s.textSecondary,
                                    height: 1.5,
                                    letterSpacing: 0.6,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // 收藏属于"选中"状态，按规范用 accent 而非红/粉
                              if (widget.isFavorite)
                                DrawIcon(StrokeIcons.favorite, size: AppTheme.metrics.iconSize12, color: s.accent),
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
        placeholder: (_, _) => _placeholder(context),
        errorWidget: (_, _, _) => _placeholder(context),
      );
    }
    final File file = File(value);
    if (file.existsSync()) {
      return Image.file(file, fit: BoxFit.cover, alignment: Alignment.center);
    }
    return _placeholder(context);
  }

  Widget _placeholder(BuildContext context) {
    final s = AppSemantic.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            s.accentContainer,
            // secondaryContainer 在语义层没有对等角色，暂保留字阶色
            Theme.of(context).colorScheme.secondaryContainer,
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DrawIcon(StrokeIcons.sportsEsports,
              size: AppTheme.metrics.iconSize32,
              color: s.accent,
            ),
            SizedBox(height: AppTheme.metrics.kSpace4),
            Text(
              widget.game.name.isNotEmpty ? widget.game.name[0].toUpperCase() : '?',
              style: AppTextStyles.role(
                context,
                fontSize: AppTheme.metrics.fontSize20,
                weight: FontWeight.w700,
                color: s.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
