import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/pages/game_library/models/game_library_models.dart';
import 'package:slime_works/view_models/game_library/game_library_library_viewmodel.dart';

class GameLibraryScreen extends BasePage<GameLibraryViewModel> {
  const GameLibraryScreen({super.key});

  @override
  State<GameLibraryScreen> createState() => _GameLibraryScreenState();
}

class _GameLibraryScreenState extends BasePageState<GameLibraryViewModel, GameLibraryScreen> {
  bool _isDraggingExternalPaths = false;

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

      return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // 根据宽度计算列数（每列最小160px）
          final int crossAxisCount = (constraints.maxWidth / 180).floor().clamp(2, 8);
          return GridView.builder(
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
              return _GameCard(
                game: game,
                isFavorite: viewModel.isFavorite(game.id),
                formatDuration: viewModel.formatDuration,
                onTap: () => GameDetailRoute(gameId: game.id).push<void>(context),
                onToggleFavorite: () => viewModel.toggleFavorite(game),
                onLaunch: () => viewModel.launchGame(game),
                onDelete: () => _confirmDelete(game),
              );
            },
          );
        },
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

    return ScreenChrome(data: _buildChromeData(), child: desktopDropBody);
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

  Future<void> _batchImport() async {
    final BuildContext currentContext = context;
    final int count = await viewModel.batchImportFromDirectory();
    if (!currentContext.mounted) {
      return;
    }
    if (count <= 0) {
      ScaffoldMessenger.of(currentContext).showSnackBar(const SnackBar(content: Text('未导入新游戏')));
      return;
    }
    ScaffoldMessenger.of(currentContext).showSnackBar(SnackBar(content: Text('成功导入 $count 个游戏')));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 游戏封面卡片（网格视图专用）
// ─────────────────────────────────────────────────────────────────────────────

class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.game,
    required this.isFavorite,
    required this.formatDuration,
    required this.onTap,
    required this.onToggleFavorite,
    required this.onLaunch,
    required this.onDelete,
  });

  final GameItem game;
  final bool isFavorite;
  final String Function(int) formatDuration;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final VoidCallback onLaunch;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // 封面图（占卡片上方约65%）
            Expanded(
              flex: 65,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  _buildCover(context),
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
                        if (value == 'favorite') {
                          onToggleFavorite();
                        } else if (value == 'launch') {
                          onLaunch();
                        } else if (value == 'delete') {
                          onDelete();
                        }
                      },
                      itemBuilder: (_) => <PopupMenuEntry<String>>[
                        PopupMenuItem<String>(
                          value: 'favorite',
                          child: Text(isFavorite ? '取消收藏' : '添加收藏'),
                        ),
                        const PopupMenuItem<String>(value: 'launch', child: Text('启动游戏')),
                        const PopupMenuItem<String>(value: 'delete', child: Text('删除')),
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
                        game.status.label,
                        style: const TextStyle(color: Colors.white, fontSize: 10),
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
                      game.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    if (game.company.isNotEmpty && game.company != '未知')
                      Text(
                        game.company,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    const Spacer(),
                    Row(
                      children: <Widget>[
                        if (game.rating > 0) ...<Widget>[
                          const Icon(Icons.star_rounded, size: 12, color: Colors.amber),
                          const SizedBox(width: 2),
                          Text(
                            game.rating.toStringAsFixed(1),
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            formatDuration(game.totalPlayTimeSec),
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isFavorite) const Icon(Icons.favorite, size: 12, color: Colors.pink),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCover(BuildContext context) {
    final String value = game.coverPath.trim();
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
      return Image.file(file, fit: BoxFit.cover);
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
              game.name.isNotEmpty ? game.name[0].toUpperCase() : '?',
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
