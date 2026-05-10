import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/pages/game_library/models/game_library_models.dart';
import 'package:slime_works/view_models/game_library/game_library_categories_viewmodel.dart';

class GameCategoriesScreen extends BasePage<GameLibraryCategoriesViewModel> {
  const GameCategoriesScreen({super.key});

  @override
  State<GameCategoriesScreen> createState() => _GameCategoriesScreenState();
}

class _GameCategoriesScreenState
    extends BasePageState<GameLibraryCategoriesViewModel, GameCategoriesScreen> {
  @override
  bool get showAppBar => false;

  @override
  GameLibraryCategoriesViewModel createViewModel() => GameLibraryCategoriesViewModel();

  ScreenChromeData _buildChromeData() {
    return ScreenChromeData(
      title: '分类管理',
      actions: <Widget>[
        FilledButton.icon(
          onPressed: _showCreateDialog,
          icon: const Icon(Icons.create_new_folder_outlined),
          label: const Text('新增分类'),
        ),
      ],
      toolbar: SizedBox(
        width: 280,
        child: TextField(
          decoration: const InputDecoration(
            hintText: '搜索分类',
            prefixIcon: Icon(Icons.search),
            isDense: true,
          ),
          onChanged: (String value) => viewModel.searchQuery.value = value,
        ),
      ),
      toolbarHeight: AppTheme.metrics.kSpace48,
    );
  }

  @override
  Widget buildContent(BuildContext context) {
    return ScreenChrome(
      data: _buildChromeData(),
      child: Obx(() {
        final List<GameCategory> list = viewModel.filtered;
        if (list.isEmpty) {
          return const Center(child: Text('暂无分类，先创建一个吧'));
        }

        return ListView.separated(
          padding: EdgeInsets.all(AppTheme.metrics.kSpace16),
          itemCount: list.length,
          separatorBuilder: (_, _) => SizedBox(height: AppTheme.metrics.kSpace8),
          itemBuilder: (BuildContext context, int index) {
            final GameCategory category = list[index];
            return Card(
              child: ListTile(
                leading: Text(category.emoji, style: TextStyle(fontSize: AppTheme.metrics.fontSize20)),
                title: Text(category.name),
                subtitle: Text('游戏数量 ${category.gameCount}${category.isSystem ? ' · 系统分类' : ''}'),
                onTap: () {
                  GameCategoryDetailRoute(categoryId: category.id).push<void>(context);
                },
                trailing: category.isSystem
                    ? const Icon(Icons.lock_outline)
                    : PopupMenuButton<String>(
                        onSelected: (String value) {
                          if (value == 'edit') {
                            _showEditDialog(category);
                          }
                          if (value == 'delete') {
                            _confirmDelete(category);
                          }
                        },
                        itemBuilder: (_) => const <PopupMenuEntry<String>>[
                          PopupMenuItem<String>(value: 'edit', child: Text('编辑')),
                          PopupMenuItem<String>(value: 'delete', child: Text('删除')),
                        ],
                      ),
              ),
            );
          },
        );
      }),
    );
  }

  Future<void> _showCreateDialog() async {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController emojiController = TextEditingController(text: '📁');

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('新增分类'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: '分类名'),
              ),
              TextField(
                controller: emojiController,
                decoration: const InputDecoration(labelText: 'Emoji'),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                await viewModel.addCategory(nameController.text, emojiController.text);
                if (!context.mounted) return;
                Navigator.of(context).pop();
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );

    nameController.dispose();
    emojiController.dispose();
  }

  Future<void> _showEditDialog(GameCategory category) async {
    final TextEditingController nameController = TextEditingController(text: category.name);
    final TextEditingController emojiController = TextEditingController(text: category.emoji);

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('编辑分类'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: '分类名'),
              ),
              TextField(
                controller: emojiController,
                decoration: const InputDecoration(labelText: 'Emoji'),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                await viewModel.updateCategory(category, nameController.text, emojiController.text);
                if (!context.mounted) return;
                Navigator.of(context).pop();
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );

    nameController.dispose();
    emojiController.dispose();
  }

  Future<void> _confirmDelete(GameCategory category) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('删除分类'),
          content: Text('确认删除 ${category.name} 吗？'),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('删除')),
          ],
        );
      },
    );

    if (ok == true) {
      await viewModel.deleteCategory(category.id);
    }
  }
}
