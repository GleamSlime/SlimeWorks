import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/core/services/time_consumption_test.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:file_picker/file_picker.dart';
import 'package:slime_works/pages/collection/library/components/library_item.dart';
import 'package:slime_works/src/rust/api/novel_reader.dart' hide cancelSearch;
import 'package:slime_works/src/rust/api/novel_reader.dart' as rust_api;

part 'novel_library_viewmodel_novel.dart';
part 'novel_library_viewmodel_actions.dart';

Loggers logger = Loggers(name: '书库');

/// 书库 ViewModel
class NovelLibraryViewModel extends BaseViewModel {
  // 书库 数据
  final novels = <NovelMetadata>[].obs;
  final isScanning = false.obs;
  final searchQuery = ''.obs;
  final searchByContent = false.obs;
  final isSearching = false.obs;
  final isCancelling = false.obs;
  final searchProgress = 0.0.obs;
  final searchTotal = 0.obs;
  final searchCompleted = 0.obs;
  final contentSearchResults = <NovelMetadata>[].obs;
  final isClearingNovels = false.obs;

  // 文件夹数据
  final folders = <NovelFolder>[].obs;

  /// 当前文件夹 ID，null = 根目录
  final currentFolderId = RxnString();

  /// 保存的滚动位置
  final savedScrollOffset = 0.0.obs;

  // 选择相关
  final selectedIds = <String>{}.obs;
  final isSelecting = false.obs;

  // 搜索取消标志
  bool searchCancelled = false;

  // Tag 过滤
  final selectedFilterTags = <String>[].obs;

  // 收藏筛选
  final showFavoritesOnly = false.obs;

  // 关键词规则
  final keywordRules = <Map<String, String>>[].obs;

  /// 当前文件夹名称
  String get currentFolderName {
    final fid = currentFolderId.value;
    if (fid == null) return '';
    return folders.firstWhereOrNull((f) => f.id == fid)?.name ?? '';
  }

  /// 当前展示的 items（文件夹 + 书籍）
  List<LibraryItem> get filteredItems {
    final fid = currentFolderId.value;
    final query = searchQuery.value;
    final filterTags = selectedFilterTags.toSet();
    final favoritesOnly = showFavoritesOnly.value;

    if (query.isNotEmpty) {
      List<NovelMetadata> results;
      if (searchByContent.value) {
        results = contentSearchResults.toList();
      } else {
        final lq = query.toLowerCase();
        results = novels.where((n) => n.title.toLowerCase().contains(lq)).toList();
      }
      if (filterTags.isNotEmpty) {
        results = results.where((n) => n.tags.any((t) => filterTags.contains(t))).toList();
      }
      if (favoritesOnly) {
        results = results.where((n) => n.isFavorite).toList();
      }
      return results.map<LibraryItem>((n) => LibraryBookItem(n)).toList();
    }

    if (fid != null) {
      var folderBooks = novels.where((n) => n.folderId == fid).toList();
      if (filterTags.isNotEmpty) {
        folderBooks = folderBooks.where((n) => n.tags.any((t) => filterTags.contains(t))).toList();
      }
      if (favoritesOnly) {
        folderBooks = folderBooks.where((n) => n.isFavorite).toList();
      }
      _sortBooks(folderBooks);
      return folderBooks.map<LibraryItem>((n) => LibraryBookItem(n)).toList();
    }

    final sortedFolders = folders.toList()
      ..sort((a, b) {
        final cmp = a.order.compareTo(b.order);
        if (cmp != 0) return cmp;
        return b.createdAt.compareTo(a.createdAt);
      });

    var rootBooks = novels.where((n) => n.folderId == null).toList();
    if (filterTags.isNotEmpty) {
      rootBooks = rootBooks.where((n) => n.tags.any((t) => filterTags.contains(t))).toList();
    }
    if (favoritesOnly) {
      rootBooks = rootBooks.where((n) => n.isFavorite).toList();
    }
    _sortBooks(rootBooks);

    return [
      if (filterTags.isEmpty) ...sortedFolders.map<LibraryItem>((f) => LibraryFolderItem(f)),
      ...rootBooks.map<LibraryItem>((n) => LibraryBookItem(n)),
    ];
  }

  /// 所有书籍拥有的 tags
  List<String> get allAvailableTags {
    return allTagCounts.keys.toList()..sort();
  }

  /// 所有书籍标签计数（tag -> count）
  Map<String, int> get allTagCounts {
    final tagCountMap = <String, int>{};
    for (final n in novels) {
      for (final tag in n.tags) {
        tagCountMap[tag] = (tagCountMap[tag] ?? 0) + 1;
      }
    }
    return tagCountMap;
  }

  void _sortBooks(List<NovelMetadata> list) {
    list.sort((a, b) {
      // 1. 收藏的书籍优先
      if (a.isFavorite && !b.isFavorite) return -1;
      if (!a.isFavorite && b.isFavorite) return 1;

      // 2. 按 customOrder 排序（拖动、最近阅读会修改order值）
      final aOrder = a.customOrder ?? 999999;
      final bOrder = b.customOrder ?? 999999;
      if (aOrder != bOrder) return aOrder.compareTo(bOrder);

      // 3. order相同时按添加时间倒序
      return b.addedAt.compareTo(a.addedAt);
    });
  }

  /// 过滤后的书籍列表
  List<NovelMetadata> get filteredNovels {
    final sortTest = TimeConsumptionTest()..start(log: false);
    final result = filteredItems.whereType<LibraryBookItem>().map((i) => i.metadata).toList();
    logger.log('书库 ${result.length} 本，耗时 +${sortTest.end(log: false)}ms', name: '书库');
    return result;
  }

  @override
  Future<void> onInitAsync() async {
    await super.onInitAsync();
    await Future.wait([loadData(), loadKeywordRules()]);
  }

  void showSnack(
    String title,
    String message, {
    SnackPosition? position,
    Color? backgroundColor,
    Color? colorText,
    Duration? duration,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final context = navigatorKey.currentContext;
        if (context == null) return;

        final messenger = ScaffoldMessenger.maybeOf(context);
        if (messenger == null) return;

        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                '$title：$message',
                style: colorText == null ? null : TextStyle(color: colorText),
              ),
              duration: duration ?? const Duration(seconds: 2),
              backgroundColor: backgroundColor,
              behavior: SnackBarBehavior.floating,
            ),
          );
      } catch (_) {}
    });
  }

  Future<void> loadData() async {
    await Future.wait([loadNovels(), loadFolders()]);
  }

  Future<void> loadNovels() async {
    final t = TimeConsumptionTest()..start(log: false);
    try {
      novels.value = getAllNovels();
      logger.log('加载书籍 ${novels.length} 本(+${t.end(log: false)}ms)', name: '书库');
    } catch (e) {
      showSnack('错误', '加载书籍列表失败: $e');
    }
  }

  Future<void> loadFolders() async {
    try {
      folders.value = getAllFolders();
    } catch (e) {
      showSnack('错误', '加载文件夹失败: $e');
    }
  }

  void enterSelection(String firstId) {
    isSelecting.value = true;
    selectedIds.add(firstId);
  }

  void exitSelection() {
    isSelecting.value = false;
    selectedIds.clear();
  }

  void toggleSelection(String id) {
    if (selectedIds.contains(id)) {
      selectedIds.remove(id);
      if (selectedIds.isEmpty) exitSelection();
    } else {
      selectedIds.add(id);
    }
  }

  void toggleSelectAll() {
    final items = filteredItems;
    if (selectedIds.length == items.length) {
      selectedIds.clear();
    } else {
      selectedIds.assignAll(items.map((i) => i.id).toSet());
    }
  }
}
