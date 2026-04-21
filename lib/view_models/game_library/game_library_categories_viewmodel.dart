import 'package:get/get.dart';

import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/game_library_service.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/game_library/models/game_library_models.dart';

class GameLibraryCategoriesViewModel extends BaseViewModel {
  final GameLibraryService _service = getIt<GameLibraryService>();

  final RxList<GameCategory> categories = <GameCategory>[].obs;
  final RxString searchQuery = ''.obs;

  @override
  Future<void> onInitAsync() async {
    await super.onInitAsync();
    await _service.init();
    await refresh();
  }

  @override
  Future<void> refresh() async {
    categories.assignAll(_service.categories);
  }

  List<GameCategory> get filtered {
    final String keyword = searchQuery.value.trim().toLowerCase();
    if (keyword.isEmpty) {
      return categories;
    }
    return categories
        .where((GameCategory c) => c.name.toLowerCase().contains(keyword))
        .toList(growable: false);
  }

  Future<void> addCategory(String name, String emoji) async {
    if (name.trim().isEmpty) {
      setError('分类名不能为空');
      return;
    }
    await _service.addCategory(name: name, emoji: emoji);
    await refresh();
  }

  Future<void> updateCategory(GameCategory category, String name, String emoji) async {
    await _service.updateCategory(category.copyWith(name: name, emoji: emoji));
    await refresh();
  }

  Future<void> deleteCategory(String categoryId) async {
    await _service.deleteCategory(categoryId);
    await refresh();
  }
}
