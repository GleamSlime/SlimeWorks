import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/pages/game_library/models/game_library_models.dart';
import 'package:slime_works/view_models/game_library/game_library_detail_viewmodel.dart';

class GameDetailScreen extends BasePage<GameLibraryDetailViewModel> {
  const GameDetailScreen({super.key, required this.gameId});

  final String gameId;

  @override
  State<GameDetailScreen> createState() => _GameDetailScreenState();
}

class _GameDetailScreenState extends BasePageState<GameLibraryDetailViewModel, GameDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _companyController = TextEditingController();
  final TextEditingController _summaryController = TextEditingController();
  final TextEditingController _ratingController = TextEditingController();
  final TextEditingController _releaseController = TextEditingController();
  final TextEditingController _pathController = TextEditingController();

  final TextEditingController _chapterController = TextEditingController();
  final TextEditingController _routeController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  GameStatus _editStatus = GameStatus.notStarted;

  static const List<String> _tabLabels = <String>['统计', '编辑', '启动', '分类', '进度'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabLabels.length, vsync: this);
  }

  @override
  bool get showAppBar => false;

  @override
  GameLibraryDetailViewModel createViewModel() => GameLibraryDetailViewModel();

  @override
  Future<void> onPageInit() async {
    await super.onPageInit();
    await viewModel.load(widget.gameId);
    _syncEditControllers();
  }

  void _syncEditControllers() {
    final GameItem? game = viewModel.game.value;
    if (game == null) {
      return;
    }
    _nameController.text = game.name;
    _companyController.text = game.company;
    _summaryController.text = game.summary;
    _ratingController.text = game.rating > 0 ? game.rating.toStringAsFixed(1) : '';
    _releaseController.text = game.releaseDate;
    _pathController.text = game.path;
    _editStatus = game.status;

    final GameProgress? progress = viewModel.progress.value;
    _chapterController.text = progress?.chapter ?? '';
    _routeController.text = progress?.route ?? '';
    _noteController.text = progress?.note ?? '';
  }

  ScreenChromeData _buildChromeData() {
    return ScreenChromeData(
      title: '游戏详情',
      actions: <Widget>[
        TextButton.icon(
          onPressed: () => GameLibraryRoute().go(context),
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('返回'),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────
  // 主体
  // ──────────────────────────────────────────────────────

  @override
  Widget buildContent(BuildContext context) {
    return ScreenChrome(
      data: _buildChromeData(),
      child: Obx(() {
        final GameItem? game = viewModel.game.value;
        if (game == null) {
          return const Center(child: CircularProgressIndicator());
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildHeader(context, game),
            Container(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
              ),
              child: TabBar(
                controller: _tabController,
                isScrollable: false,
                labelColor: Theme.of(context).colorScheme.primary,
                unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
                indicatorColor: Theme.of(context).colorScheme.primary,
                indicatorWeight: 2,
                tabs: _tabLabels.map((String l) => Tab(text: l)).toList(growable: false),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: <Widget>[
                  _buildStatsTab(game),
                  _buildEditTab(game),
                  _buildLaunchTab(game),
                  _buildCategoriesTab(),
                  _buildProgressTab(),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }

  // ──────────────────────────────────────────────────────
  // 头部：左封面 + 右信息
  // ──────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context, GameItem game) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildCoverCard(context, game),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // 标题
                Text(
                  game.name,
                  style: Theme.of(
                    context,
                  ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),

                // 启动按钮 + 状态 Pills
                _buildActionRow(context, game),
                const SizedBox(height: 16),

                // 元数据网格
                _buildMetaGrid(context, game),
                const SizedBox(height: 12),

                // 简介
                if (game.summary.trim().isNotEmpty) _buildSummary(context, game),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverCard(BuildContext context, GameItem game) {
    return Container(
      width: 180,
      height: 250,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Theme.of(context).shadowColor.withAlpha(60),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: _buildCoverImage(context, game.coverPath.trim()),
      ),
    );
  }

  Widget _buildCoverImage(BuildContext context, String coverPath) {
    if (coverPath.isEmpty) {
      return _coverPlaceholder(context);
    }
    if (coverPath.startsWith('http://') || coverPath.startsWith('https://')) {
      return CachedNetworkImage(
        imageUrl: coverPath,
        fit: BoxFit.cover,
        placeholder: (_, __) => _coverPlaceholder(context),
        errorWidget: (_, __, ___) => _coverPlaceholder(context),
      );
    }
    final File file = File(coverPath);
    if (file.existsSync()) {
      return Image.file(file, fit: BoxFit.cover);
    }
    return _coverPlaceholder(context);
  }

  Widget _coverPlaceholder(BuildContext context) {
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
        child: Icon(
          Icons.sports_esports_outlined,
          size: 48,
          color: Theme.of(context).colorScheme.primary.withAlpha(160),
        ),
      ),
    );
  }

  Widget _buildActionRow(BuildContext context, GameItem game) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        // 启动按钮
        FilledButton.icon(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          onPressed: () => _launchGame(game),
          icon: const Icon(Icons.play_arrow, size: 18),
          label: const Text('启动游戏'),
        ),
        Container(width: 1, height: 24, color: Theme.of(context).dividerColor),

        // 状态 Pills
        ...GameStatus.values.map(
          (GameStatus s) => _StatusPill(
            label: s.label,
            icon: _statusIcon(s),
            active: game.status == s,
            onTap: () async => viewModel.updateGame(game.copyWith(status: s)),
          ),
        ),
        Container(width: 1, height: 24, color: Theme.of(context).dividerColor),

        // 收藏 Pill
        _StatusPill(
          label: viewModel.isFavorite ? '已收藏' : '收藏',
          icon: viewModel.isFavorite ? Icons.favorite : Icons.favorite_border,
          active: viewModel.isFavorite,
          activeColor: Colors.pink,
          onTap: () => viewModel.toggleFavorite(!viewModel.isFavorite),
        ),
      ],
    );
  }

  IconData _statusIcon(GameStatus s) {
    switch (s) {
      case GameStatus.notStarted:
        return Icons.schedule_outlined;
      case GameStatus.playing:
        return Icons.sports_esports_outlined;
      case GameStatus.completed:
        return Icons.emoji_events_outlined;
      case GameStatus.onHold:
        return Icons.pause_circle_outline;
      case GameStatus.dropped:
        return Icons.cancel_outlined;
    }
  }

  Widget _buildMetaGrid(BuildContext context, GameItem game) {
    final List<_MetaItem> items = <_MetaItem>[
      _MetaItem(
        label: '开发商',
        value: game.company.trim().isNotEmpty && game.company != '未知' ? game.company : '-',
      ),
      _MetaItem(
        label: '评分',
        value: game.rating > 0 ? '${game.rating.toStringAsFixed(1)} / 10' : '-',
      ),
      _MetaItem(label: '发售日期', value: game.releaseDate.trim().isNotEmpty ? game.releaseDate : '-'),
      _MetaItem(label: '游玩时长', value: viewModel.formatDuration(game.totalPlayTimeSec)),
    ];

    return Wrap(
      spacing: 24,
      runSpacing: 12,
      children: items
          .map(
            (_MetaItem item) => SizedBox(
              width: 140,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.value,
                    style: Theme.of(context).textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _buildSummary(BuildContext context, GameItem game) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '简介',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          game.summary,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────
  // Tab: 统计
  // ──────────────────────────────────────────────────────

  Widget _buildStatsTab(GameItem game) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final int cols = (constraints.maxWidth / 180).floor().clamp(2, 6);
            final double itemW = (constraints.maxWidth - (cols - 1) * 12) / cols;
            final List<_MetaItem> stats = <_MetaItem>[
              _MetaItem(label: '累计游玩', value: viewModel.formatDuration(game.totalPlayTimeSec)),
              _MetaItem(label: '游玩次数', value: '${viewModel.sessions.length} 次'),
              _MetaItem(label: '当前状态', value: game.status.label),
            ];
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: stats
                  .map(
                    (_MetaItem s) => SizedBox(
                      width: itemW,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                s.label,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                s.value,
                                style: Theme.of(
                                  context,
                                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            );
          },
        ),
        const SizedBox(height: 20),
        Row(
          children: <Widget>[
            Text(
              '游玩记录',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: () async {
                final DateTime end = DateTime.now();
                final DateTime start = end.subtract(const Duration(hours: 1));
                await viewModel.addManualSession(start: start, end: end);
              },
              icon: const Icon(Icons.add, size: 16),
              label: const Text('追加记录'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (viewModel.sessions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                '还没有游玩记录',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          ...viewModel.sessions.map(
            (PlaySession session) => Card(
              child: ListTile(
                leading: const Icon(Icons.history),
                title: Text('${session.startTime} → ${session.endTime}'),
                trailing: Text(viewModel.formatDuration(session.durationSec)),
              ),
            ),
          ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────
  // Tab: 编辑
  // ──────────────────────────────────────────────────────

  Widget _buildEditTab(GameItem game) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: '游戏名', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _companyController,
                decoration: const InputDecoration(labelText: '开发商', border: OutlineInputBorder()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _ratingController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '评分 (0-10)',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _releaseController,
                decoration: const InputDecoration(
                  labelText: '发售日期',
                  hintText: 'YYYY-MM-DD',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pathController,
          decoration: const InputDecoration(
            labelText: '启动路径',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.folder_outlined),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<GameStatus>(
          value: _editStatus,
          decoration: const InputDecoration(labelText: '状态', border: OutlineInputBorder()),
          items: GameStatus.values
              .map((GameStatus e) => DropdownMenuItem<GameStatus>(value: e, child: Text(e.label)))
              .toList(growable: false),
          onChanged: (GameStatus? v) {
            if (v != null) {
              setState(() {
                _editStatus = v;
              });
            }
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _summaryController,
          minLines: 4,
          maxLines: 8,
          decoration: const InputDecoration(labelText: '简介', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _saveEdit,
          icon: const Icon(Icons.save_outlined),
          label: const Text('保存修改'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () async {
            await viewModel.refreshMetadata();
            _syncEditControllers();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('元数据已刷新')));
            }
          },
          icon: const Icon(Icons.cloud_download_outlined),
          label: const Text('从网络刷新元数据'),
        ),
      ],
    );
  }

  Future<void> _saveEdit() async {
    final GameItem? game = viewModel.game.value;
    if (game == null) {
      return;
    }
    await viewModel.updateGame(
      game.copyWith(
        name: _nameController.text.trim(),
        company: _companyController.text.trim(),
        summary: _summaryController.text.trim(),
        rating: double.tryParse(_ratingController.text.trim()) ?? game.rating,
        releaseDate: _releaseController.text.trim(),
        path: _pathController.text.trim(),
        status: _editStatus,
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存')));
    }
  }

  // ──────────────────────────────────────────────────────
  // Tab: 启动
  // ──────────────────────────────────────────────────────

  Widget _buildLaunchTab(GameItem game) {
    final bool hasPath = game.path.trim().isNotEmpty;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '启动配置',
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Icon(Icons.folder_open_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hasPath ? game.path : '未配置启动路径，请在「编辑」标签中填写',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: hasPath ? null : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      ),
                      onPressed: hasPath ? () => _launchGame(game) : null,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('启动游戏'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final DateTime end = DateTime.now();
                        final DateTime start = end.subtract(const Duration(hours: 1));
                        await viewModel.addManualSession(start: start, end: end);
                        if (mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(const SnackBar(content: Text('已追加 1 小时记录')));
                        }
                      },
                      icon: const Icon(Icons.add_alarm),
                      label: const Text('追加 1 小时记录'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _launchGame(GameItem game) async {
    final String path = game.path.trim();
    if (path.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('未配置启动路径，请在「编辑」标签中设置')));
      }
      return;
    }
    try {
      await Process.start(path, <String>[]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('启动失败: $e')));
      }
    }
  }

  // ──────────────────────────────────────────────────────
  // Tab: 分类
  // ──────────────────────────────────────────────────────

  Widget _buildCategoriesTab() {
    return Obx(() {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          Text(
            '分类管理',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (viewModel.categories.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  '还没有分类，点击右上角「分类管理」创建',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            ...viewModel.categories.map(
              (GameCategory category) => CheckboxListTile(
                value: viewModel.selectedCategoryIds.contains(category.id),
                onChanged: (bool? checked) {
                  viewModel.toggleCategory(category.id, checked ?? false);
                },
                title: Text('${category.emoji} ${category.name}'),
                subtitle: category.isSystem ? const Text('系统分类') : null,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
        ],
      );
    });
  }

  // ──────────────────────────────────────────────────────
  // Tab: 进度
  // ──────────────────────────────────────────────────────

  Widget _buildProgressTab() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        Text(
          '游玩进度',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _chapterController,
          decoration: const InputDecoration(
            labelText: '当前章节',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.book_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _routeController,
          decoration: const InputDecoration(
            labelText: '当前路线',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.alt_route_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _noteController,
          minLines: 4,
          maxLines: 10,
          decoration: const InputDecoration(
            labelText: '进度备注',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () async {
            await viewModel.saveProgress(
              chapter: _chapterController.text.trim(),
              route: _routeController.text.trim(),
              note: _noteController.text.trim(),
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('进度已保存')));
            }
          },
          icon: const Icon(Icons.save_outlined),
          label: const Text('保存进度'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _companyController.dispose();
    _summaryController.dispose();
    _ratingController.dispose();
    _releaseController.dispose();
    _pathController.dispose();
    _chapterController.dispose();
    _routeController.dispose();
    _noteController.dispose();
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 状态 Pill 组件
// ─────────────────────────────────────────────────────────────────────────────

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    this.activeColor,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final Color resolvedColor = activeColor ?? Theme.of(context).colorScheme.primary;
    final Color bg = active
        ? resolvedColor.withAlpha(28)
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    final Color fg = active ? resolvedColor : Theme.of(context).colorScheme.onSurfaceVariant;
    final BorderSide border = active
        ? BorderSide(color: resolvedColor, width: 1.5)
        : BorderSide(color: Theme.of(context).dividerColor);

    return InkWell(
      borderRadius: BorderRadius.circular(100),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(100),
          border: Border.fromBorderSide(border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 15, color: fg),
            if (active) ...<Widget>[
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 元数据项数据类
// ─────────────────────────────────────────────────────────────────────────────

class _MetaItem {
  const _MetaItem({required this.label, required this.value});

  final String label;
  final String value;
}
