import 'dart:io';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';

import 'package:slime_works/core/provider/main.dart';

import 'package:slime_works/components/window/collapsible_sidebar.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/screen_provider.dart';
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

  bool _exeListExpanded = false;
  final GlobalKey _twodfanPickerKey = GlobalKey();
  bool _twodfanPickerLoading = false;

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
    // 打开详情页时自动收起侧边栏
    try {
      Get.find<SidebarController>().closeSidebar();
    } catch (_) {}
    await viewModel.load(widget.gameId);
    // 设置全局模糊背景
    final String cover = viewModel.game.value?.coverPath ?? '';
    if (cover.isNotEmpty) {
      getIt<DesktopScreenProvider>().globalBackgroundPath.value = cover;
    }
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
      leading: TextButton.icon(
        onPressed: () => GameLibraryRoute().go(context),
        icon: const Icon(Icons.arrow_back_ios_new, size: 16),
        label: const Text('返回'),
      ),
    );
  }

  // ──────────────────────────────────────────────────────
  // 主体
  // ──────────────────────────────────────────────────────

  Widget _buildBlurBackground(BuildContext context, String coverPath) {
    // 全局背景已在 DesktopScaffold 层渲染，这里仅返回透明层
    return const SizedBox.shrink();
  }

  @override
  Widget buildContent(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          if (context.canPop()) context.pop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ScreenChrome(
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
      ),
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
        // 启动按钮（含运行中状态 + 多 exe 下拉选择）
        Obx(() {
          final bool running = viewModel.processTracker.isRunning(game.id);
          if (running) {
            return FilledButton.icon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                backgroundColor: Colors.green,
              ),
              onPressed: null,
              icon: const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              label: const Text('游戏运行中...'),
            );
          }

          final List<String> exePaths = viewModel.gameExePaths;

          // 单 exe / 无 exe：普通按钮
          if (exePaths.length <= 1) {
            return FilledButton.icon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onPressed: () => _launchGame(game),
              icon: const Icon(Icons.play_arrow, size: 18),
              label: const Text('启动游戏'),
            );
          }

          // 多 exe：分割按钮（左：启动默认，右：下拉选择其他 exe）
          final ColorScheme cs = Theme.of(context).colorScheme;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.horizontal(left: Radius.circular(20)),
                  ),
                ),
                onPressed: () => _launchGame(game),
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('启动游戏'),
              ),
              Container(width: 1, height: 36, color: cs.onPrimary.withAlpha(60)),
              PopupMenuButton<String>(
                tooltip: '选择其他可执行文件启动',
                offset: const Offset(0, 44),
                onSelected: (String p) => _launchWithExe(game, p),
                shadowColor: Colors.transparent,
                itemBuilder: (_) => exePaths.map((String p) {
                  final bool isDefault = p.trim() == (viewModel.game.value?.path.trim() ?? '');
                  return PopupMenuItem<String>(
                    value: p,
                    child: Row(
                      children: <Widget>[
                        Icon(
                          isDefault ? Icons.star_rounded : Icons.play_arrow_outlined,
                          size: 16,
                          color: isDefault ? Colors.amber : null,
                        ),
                        const SizedBox(width: 8),
                        Flexible(child: Text(p.split(Platform.pathSeparator).last)),
                      ],
                    ),
                  );
                }).toList(),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
                  ),
                  child: Icon(Icons.arrow_drop_down, color: cs.onPrimary, size: 20),
                ),
              ),
            ],
          );
        }),
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
                        color: Theme.of(context).colorScheme.surface.withOpacity(0.72),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.outline.withOpacity(0.12),
                          ),
                        ),
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
              color: Theme.of(context).colorScheme.surface.withOpacity(0.72),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Theme.of(context).colorScheme.outline.withOpacity(0.12)),
              ),
              child: ListTile(
                leading: const Icon(Icons.history),
                title: Text('${session.startTime} → ${session.endTime}'),
                trailing: Text(viewModel.formatDuration(session.durationSec)),
              ),
            ),
          ),

        // ── 萌娘百科 ──
        const SizedBox(height: 20),
        _buildMoegirlSection(),
      ],
    );
  }

  Widget _buildMoegirlSection() {
    return Obx(() {
      final bool loading = viewModel.moegirlLoading.value;
      final String html = viewModel.moegirlHtml.value;
      final String error = viewModel.moegirlError.value;
      if (loading) {
        return Card(
          color: Theme.of(context).colorScheme.surface.withOpacity(0.72),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Theme.of(context).colorScheme.outline.withOpacity(0.12)),
          ),
          child: const Padding(
            padding: EdgeInsets.all(20),
            child: Row(
              children: <Widget>[
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 12),
                Text('正在加载萌娘百科...'),
              ],
            ),
          ),
        );
      }
      if (error.isNotEmpty) {
        return Card(
          color: Theme.of(context).colorScheme.surface.withOpacity(0.72),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Theme.of(context).colorScheme.outline.withOpacity(0.12)),
          ),
          child: ListTile(
            leading: const Icon(Icons.warning_amber_outlined),
            title: const Text('萌娘百科加载失败'),
            subtitle: Text(error, style: Theme.of(context).textTheme.bodySmall),
            trailing: IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '重试',
              onPressed: viewModel.retryMoegirl,
            ),
          ),
        );
      }
      if (html.isEmpty) return const SizedBox.shrink();
      return Card(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.72),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Theme.of(context).colorScheme.outline.withOpacity(0.12)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.menu_book_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text('萌娘百科', style: Theme.of(context).textTheme.titleSmall),
                  const Spacer(),
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () async {
                      final String name = viewModel.game.value?.name ?? '';
                      if (name.isEmpty) return;
                      final String encoded = Uri.encodeComponent(name);
                      final String url = 'https://zh.moegirl.org.cn/$encoded';
                      try {
                        await Process.run('open', [url]);
                      } catch (_) {}
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            Icons.open_in_new,
                            size: 14,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '原文',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              HtmlWidget(
                html,
                buildAsync: true,
                baseUrl: Uri.parse('https://zh.moegirl.org.cn'),
                textStyle: Theme.of(context).textTheme.bodySmall,
                onTapUrl: (url) async {
                  try {
                    await Process.run('open', [url]);
                  } catch (_) {}
                  return true;
                },
                customStylesBuilder: (element) {
                  switch (element.localName) {
                    case 'img':
                      // 强制块级渲染，避免内联 WidgetSpan 路径下
                      // CircularProgressIndicator 调用 computeDryBaseline 崩溃
                      return {'display': 'block', 'max-width': '100%', 'margin': '4px 0'};
                    case 'p':
                    case 'li':
                      return {'margin': '0', 'padding': '0'};
                    case 'ul':
                    case 'ol':
                      return {'margin': '2px 0', 'padding-left': '16px'};
                    case 'h1':
                    case 'h2':
                    case 'h3':
                    case 'h4':
                    case 'h5':
                    case 'h6':
                      return {'margin': '4px 0 2px 0'};
                    default:
                      return null;
                  }
                },
              ),
            ],
          ),
        ),
      );
    });
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
                decoration: InputDecoration(
                  labelText: '游戏名',
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface.withOpacity(0.6),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _companyController,
                decoration: InputDecoration(
                  labelText: '开发商',
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface.withOpacity(0.6),
                ),
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
                decoration: InputDecoration(
                  labelText: '评分 (0-10)',
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface.withOpacity(0.6),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _releaseController,
                decoration: InputDecoration(
                  labelText: '发售日期',
                  hintText: 'YYYY-MM-DD',
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface.withOpacity(0.6),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pathController,
          decoration: InputDecoration(
            labelText: '启动路径',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.folder_outlined),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surface.withOpacity(0.6),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<GameStatus>(
          value: _editStatus,
          decoration: InputDecoration(
            labelText: '状态',
            border: const OutlineInputBorder(),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surface.withOpacity(0.6),
          ),
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
          decoration: InputDecoration(
            labelText: '简介',
            border: const OutlineInputBorder(),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surface.withOpacity(0.6),
          ),
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
    return Obx(() {
      // 读取最新游戏数据（响应 setDefaultExe / removeExePath 后的更新）
      final GameItem g = viewModel.game.value ?? game;
      final List<String> exePaths = viewModel.gameExePaths;
      final bool running = viewModel.processTracker.isRunning(g.id);

      return ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          // 运行状态提示卡
          if (running)
            Card(
              color: Colors.green.shade50,
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: <Widget>[
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.green),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '游戏运行中... 退出后将自动记录游玩时间',
                      style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),

          // 启动配置卡
          Card(
            color: Theme.of(context).colorScheme.surface.withOpacity(0.72),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Theme.of(context).colorScheme.outline.withOpacity(0.12)),
            ),
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

                  // 游戏目录
                  if (g.gameDir.trim().isNotEmpty) ...<Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Icon(Icons.folder_open_outlined, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '游戏目录: ${g.gameDir}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── macOS：使用 open 启动开关（仅 macOS 显示）──
                  if (Platform.isMacOS)
                    Obx(
                      () => SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('使用 open 命令启动'),
                        subtitle: const Text(
                          '适用于 Wine/Crossover 包装或需要 macOS 关联打开的程序',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: viewModel.useOpenOnMacos.value,
                        onChanged: (bool v) async {
                          viewModel.useOpenOnMacos.value = v;
                          // 持久化到设置
                          try {
                            final GameLibrarySettings cur = await viewModel.getSettings();
                            await viewModel.saveSettings(cur.copyWith(useOpenOnMacos: v));
                          } catch (_) {}
                        },
                      ),
                    ),

                  // ── 启动按钮行 ──
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      // 主启动按钮
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          ),
                          onPressed: (g.path.trim().isNotEmpty || exePaths.isNotEmpty) && !running
                              ? () => _launchGame(g)
                              : null,
                          icon: running
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.play_arrow),
                          label: Text(
                            running
                                ? '游戏运行中...'
                                : exePaths.isEmpty
                                ? '启动游戏'
                                : '启动游戏（${_exeName(g.path.isNotEmpty ? g.path : exePaths.first)}）',
                          ),
                        ),
                      ),
                      // 打开所在文件夹按钮
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: '打开所在文件夹',
                        onPressed: () {
                          final String openPath = g.gameDir.trim().isNotEmpty
                              ? g.gameDir.trim()
                              : (g.path.trim().isNotEmpty ? File(g.path).parent.path : '');
                          if (openPath.isNotEmpty) {
                            _openContainingFolder(openPath);
                          }
                        },
                        icon: const Icon(Icons.folder_open_outlined),
                      ),
                      // 展开/收起可执行文件列表
                      if (exePaths.isNotEmpty) ...<Widget>[
                        const SizedBox(width: 8),
                        IconButton.outlined(
                          tooltip: _exeListExpanded ? '收起选项' : '展开可执行文件列表',
                          onPressed: () => setState(() => _exeListExpanded = !_exeListExpanded),
                          icon: AnimatedRotation(
                            turns: _exeListExpanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: const Icon(Icons.expand_more),
                          ),
                        ),
                      ],
                    ],
                  ),

                  // ── 可执行文件列表（展开时显示）──
                  if (_exeListExpanded && exePaths.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Theme.of(context).dividerColor),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: exePaths.asMap().entries.map((MapEntry<int, String> entry) {
                          final String p = entry.value;
                          final bool isDefault = g.path.trim() == p;
                          final bool isLast = entry.key == exePaths.length - 1;
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 0,
                                ),
                                // 单选按钮：选中即设为默认
                                leading: Radio<String>(
                                  value: p,
                                  groupValue: g.path.trim().isNotEmpty
                                      ? g.path.trim()
                                      : (exePaths.isNotEmpty ? exePaths.first : ''),
                                  onChanged: (_) async {
                                    await viewModel.setDefaultExe(p);
                                  },
                                ),
                                title: Text(
                                  _exeName(p),
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: isDefault ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                                subtitle: Text(
                                  p,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                // X 按钮：移除该 exe
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    if (!running)
                                      IconButton(
                                        tooltip: '直接启动此文件',
                                        icon: const Icon(Icons.play_circle_outline, size: 20),
                                        onPressed: () => _launchWithExe(g, p),
                                      ),
                                    IconButton(
                                      tooltip: '移除此启动项',
                                      icon: Icon(
                                        Icons.close,
                                        size: 18,
                                        color: Theme.of(context).colorScheme.error,
                                      ),
                                      onPressed: exePaths.length > 1
                                          ? () async {
                                              await viewModel.removeExePath(p);
                                            }
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                              if (!isLast)
                                Divider(
                                  height: 1,
                                  indent: 8,
                                  endIndent: 8,
                                  color: Theme.of(context).dividerColor,
                                ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),
                  // 检测到的存档目录（若有）
                  Obx(() {
                    final String savePath = viewModel.detectedSaveFolder.value;
                    if (savePath.trim().isEmpty) return const SizedBox.shrink();
                    return Column(
                      children: <Widget>[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Icon(Icons.save_outlined, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '存档目录: $savePath',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton.icon(
                              onPressed: () => _openContainingFolder(savePath),
                              icon: const Icon(Icons.open_in_new, size: 16),
                              label: const Text('打开'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                    );
                  }),
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
            ),
          ),

          // 万物皆可萌
          const SizedBox(height: 16),
          Card(
            color: Theme.of(context).colorScheme.surface.withOpacity(0.72),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Theme.of(context).colorScheme.outline.withOpacity(0.12)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '万物皆可萌',
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () {
                      final String url = 'https://zh.moegirl.org.cn/${Uri.encodeComponent(g.name)}';
                      Process.run('open', <String>[url]);
                    },
                    icon: const Icon(Icons.open_in_browser),
                    label: Text('在萌娘百科查看「${g.name}」'),
                  ),
                ],
              ),
            ),
          ),

          // 2DFan
          const SizedBox(height: 16),
          _buildTwodfanCard(g),
        ],
      );
    });
  }

  Widget _buildTwodfanCard(GameItem g) {
    return Card(
      color: Theme.of(context).colorScheme.surface.withOpacity(0.72),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outline.withOpacity(0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '2DFan',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),

            // 在浏览器打开搜索页
            OutlinedButton.icon(
              onPressed: () {
                final String url =
                    'https://2dfan.com/subjects/search?keyword=${Uri.encodeComponent(g.name)}';
                Process.run('open', <String>[url]);
              },
              icon: const Icon(Icons.search),
              label: Text('在 2DFan 搜索「${g.name}」'),
            ),
            const SizedBox(height: 10),

            // 一键下载存档 + 选择存档版本
            Obx(() {
              final bool processing = viewModel.twodfanProcessing.value;
              final String status = viewModel.twodfanStatus.value;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      FilledButton.icon(
                        onPressed: processing ? null : () => viewModel.downloadTwodfanSave(),
                        icon: processing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.download_outlined),
                        label: Text(processing ? '处理中...' : '一键下载存档'),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: '选择存档版本',
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: OutlinedButton(
                            key: _twodfanPickerKey,
                            onPressed: viewModel.twodfanProcessing.value || _twodfanPickerLoading
                                ? null
                                : () => _showTwodfanMenu(g),
                            style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.zero,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.all(Radius.circular(8)),
                              ),
                            ),
                            child: _twodfanPickerLoading
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 1.5),
                                  )
                                : const Icon(Icons.expand_more, size: 18),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (status.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      status,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: status.startsWith('下载完成')
                            ? Colors.green
                            : (status.startsWith('下载失败') || status.startsWith('未'))
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              );
            }),

            // 存档简介（下载后展示）
            Obx(() {
              final String desc = viewModel.twodfanDesc.value;
              if (desc.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    '存档说明',
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  _buildTwodfanDescWidget(desc),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  /// 在按钮位置弹出 popup menu 让用户选择存档版本。
  Future<void> _showTwodfanMenu(GameItem g) async {
    setState(() => _twodfanPickerLoading = true);
    try {
      final List<Map<String, String>> items = await viewModel.fetchTwodfanDownloadItems();
      if (!mounted) return;
      if (items.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未找到存档资源')));
        return;
      }
      final RenderBox? btnBox = _twodfanPickerKey.currentContext?.findRenderObject() as RenderBox?;
      final RenderBox overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
      final RelativeRect position = btnBox != null
          ? RelativeRect.fromRect(
              Rect.fromPoints(
                btnBox.localToGlobal(Offset.zero, ancestor: overlay),
                btnBox.localToGlobal(btnBox.size.bottomRight(Offset.zero), ancestor: overlay),
              ),
              Offset.zero & overlay.size,
            )
          : RelativeRect.fill;
      final Map<String, String>? selected = await showMenu<Map<String, String>>(
        context: context,
        position: position,
        items: items
            .asMap()
            .entries
            .map(
              (MapEntry<int, Map<String, String>> entry) => PopupMenuItem<Map<String, String>>(
                value: entry.value,
                child: Text(
                  '${entry.key + 1}. ${entry.value['title'] ?? entry.value['path'] ?? ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
      );
      if (selected != null && mounted) {
        final String? path = selected['path'];
        if (path != null && path.isNotEmpty) {
          viewModel.downloadTwodfanSave(downloadItemPath: path);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('获取存档列表失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _twodfanPickerLoading = false);
    }
  }

  /// 渲染 2DFan 存档简介，将 Windows 路径高亮为可点击/可复制链接，替换用户名占位符。
  Widget _buildTwodfanDescWidget(String rawDesc) {
    final String username =
        Platform.environment['USER'] ?? Platform.environment['USERNAME'] ?? '用户名';

    final String text = rawDesc
        .replaceAll('你的用户名', username)
        .replaceAll('(你的|用户名)', username)
        .replaceAll('ユーザー名', username)
        .replaceAll('あなたのユーザー名', username);

    final RegExp pathRegex = RegExp(r'[A-Z]:\\(?:[^\\\r\n]+\\)*[^\\\r\n]*');
    final List<InlineSpan> spans = <InlineSpan>[];
    int lastEnd = 0;

    for (final RegExpMatch match in pathRegex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      final String path = match.group(0)!;
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Tooltip(
            message: '点击：复制路径并尝试打开',
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () {
                Clipboard.setData(ClipboardData(text: path));
                Process.run('open', <String>[path]);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已复制: $path'), duration: const Duration(seconds: 2)),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  path,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    decoration: TextDecoration.underline,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return SelectionArea(
      child: Text.rich(
        TextSpan(
          style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.7),
          children: spans,
        ),
      ),
    );
  }

  String _exeName(String path) {
    if (path.isEmpty) return '未设置';
    return path.split(Platform.pathSeparator).last;
  }

  Future<void> _launchGame(GameItem game) async {
    final bool ok = await viewModel.launchGame();
    if (!ok && mounted) {
      final String? err = viewModel.errorMessage;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(err?.isNotEmpty == true ? err! : '启动失败')));
    }
  }

  Future<void> _launchWithExe(GameItem game, String exePath) async {
    final bool ok = await viewModel.launchGame(overrideExePath: exePath);
    if (!ok && mounted) {
      final String? err = viewModel.errorMessage;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(err?.isNotEmpty == true ? err! : '启动失败')));
    }
  }

  void _openContainingFolder(String path) {
    try {
      if (Platform.isWindows) {
        Process.start('explorer.exe', <String>[path]);
      } else if (Platform.isMacOS) {
        Process.start('open', <String>[path]);
      } else {
        Process.start('xdg-open', <String>[path]);
      }
    } catch (_) {}
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
          decoration: InputDecoration(
            labelText: '当前章节',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.book_outlined),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surface.withOpacity(0.6),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _routeController,
          decoration: InputDecoration(
            labelText: '当前路线',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.alt_route_outlined),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surface.withOpacity(0.6),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _noteController,
          minLines: 4,
          maxLines: 10,
          decoration: InputDecoration(
            labelText: '进度备注',
            border: const OutlineInputBorder(),
            alignLabelWithHint: true,
            filled: true,
            fillColor: Theme.of(context).colorScheme.surface.withOpacity(0.6),
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
    // 离开详情页时，等路由反向过渡动画结束后再清除全局背景（避免淡出动画中途背景消失）
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      getIt<DesktopScreenProvider>().globalBackgroundPath.value = '';
    });
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
