import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/pages/game_library/models/game_library_models.dart';
import 'package:slime_works/view_models/game_library/game_library_library_viewmodel.dart';

class GameCategoryDetailScreen extends BasePage<GameLibraryViewModel> {
  const GameCategoryDetailScreen({super.key, required this.categoryId});

  final String categoryId;

  @override
  State<GameCategoryDetailScreen> createState() => _GameCategoryDetailScreenState();
}

class _GameCategoryDetailScreenState
    extends BasePageState<GameLibraryViewModel, GameCategoryDetailScreen> {
  @override
  bool get showAppBar => false;

  @override
  GameLibraryViewModel createViewModel() => GameLibraryViewModel();

  @override
  Future<void> onPageInit() async {
    await super.onPageInit();
    await viewModel.refresh();
  }

  ScreenChromeData _buildChromeData() {
    return ScreenChromeData(
      title: '分类详情',
      actions: <Widget>[
        OutlinedButton.icon(
          onPressed: () => GameCategoriesRoute().go(context),
          icon: const Icon(Icons.arrow_back),
          label: const Text('返回分类'),
        ),
      ],
    );
  }

  @override
  Widget buildContent(BuildContext context) {
    return ScreenChrome(
      data: _buildChromeData(),
      child: Obx(() {
        final List<GameItem> display = viewModel.getGamesByCategory(widget.categoryId);

        if (display.isEmpty) {
          return const Center(child: Text('该分类下暂无游戏'));
        }

        return ListView.separated(
          padding: EdgeInsets.all(AppTheme.metrics.kSpace16),
          itemCount: display.length,
          separatorBuilder: (_, _) => SizedBox(height: AppTheme.metrics.kSpace8),
          itemBuilder: (BuildContext context, int index) {
            final GameItem game = display[index];
            return Card(
              child: ListTile(
                title: Text(game.name),
                subtitle: Text('${game.company} · ${game.status.label}'),
                trailing: Text(viewModel.formatDuration(game.totalPlayTimeSec)),
                onTap: () => GameDetailRoute(gameId: game.id).push<void>(context),
              ),
            );
          },
        );
      }),
    );
  }
}
