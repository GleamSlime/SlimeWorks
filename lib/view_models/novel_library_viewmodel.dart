import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/services/time_consumption_test.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:slime_works/src/rust/api/novel_reader.dart' hide cancelSearch;
import 'package:slime_works/src/rust/api/novel_reader.dart' as rust_api;

Loggers logger = Loggers(name: '书库');

/// 书籍库 ViewModel
class NovelLibraryViewModel extends BaseViewModel {
  // demo 计数器字段（页面中引用）
  int a = 0;

  void add() {
    a += 1;
    update();
  }

  final novels = <NovelMetadata>[].obs;
  final isScanning = false.obs;
  final searchQuery = ''.obs;
  final searchByContent = false.obs; // false=按名字搜索, true=按内容搜索
  final isSearching = false.obs;
  final isCancelling = false.obs; // 取消搜索中
  final searchProgress = 0.0.obs;
  final searchTotal = 0.obs;
  final searchCompleted = 0.obs;
  final contentSearchResults = <NovelMetadata>[].obs;
  final isClearingNovels = false.obs; // 正在清空所有书籍

  // 搜索取消标志
  bool _searchCancelled = false;

  /// 获取过滤后的书籍列表（已排序：最近阅读 > 自定义排序 > 最近添加）
  List<NovelMetadata> get filteredNovels {
    List<NovelMetadata> result;
    final sortTest = TimeConsumptionTest()..start(log: false);

    if (searchQuery.value.isEmpty) {
      result = novels.toList();
    } else if (searchByContent.value) {
      // 按内容搜索时返回搜索结果
      result = contentSearchResults.toList();
    } else {
      // 按名字搜索
      final query = searchQuery.value.toLowerCase();
      result = novels.where((novel) {
        return novel.title.toLowerCase().contains(query);
      }).toList();
    }

    // 排序逻辑：
    // 1. 有最近阅读时间的优先（时间越近越靠前）
    // 2. 没有阅读时间时，使用自定义排序（custom_order 越小越靠前）
    // 3. 没有自定义排序时，按添加时间（时间越近越靠前）
    // 4. 最后按 ID 排序（保证顺序稳定）
    result.sort((a, b) {
      // 1. 有最近阅读时间的优先
      final aHasRead = a.lastReadAt != null;
      final bHasRead = b.lastReadAt != null;

      if (aHasRead && !bHasRead) return -1;
      if (!aHasRead && bHasRead) return 1;
      if (aHasRead && bHasRead) {
        final cmp = b.lastReadAt!.compareTo(a.lastReadAt!);
        if (cmp != 0) return cmp;
      }

      // 2. 都没有阅读时间时，使用自定义排序
      final aHasOrder = a.customOrder != null;
      final bHasOrder = b.customOrder != null;

      if (aHasOrder && !bHasOrder) return -1;
      if (!aHasOrder && bHasOrder) return 1;
      if (aHasOrder && bHasOrder) {
        final cmp = a.customOrder!.compareTo(b.customOrder!);
        if (cmp != 0) return cmp;
      }

      // 3. 都没有自定义排序时，按添加时间
      final addedCmp = b.addedAt.compareTo(a.addedAt);
      if (addedCmp != 0) return addedCmp;

      // 4. 最后按 ID 排序
      return a.id.compareTo(b.id);
    });

    logger.log(
      '排序共 ${result.length} 本书籍，耗时 +${sortTest.end(log: false)}ms，前 3 本最近阅读时间: ${result.take(3).map((n) => '${n.title}: ${n.lastReadAt}').join(', ')}',
      name: '书库',
    );

    return result;
  }

  @override
  Future<void> onInitAsync() async {
    await super.onInitAsync();
    await loadNovels();
  }

  void _showSnack(
    String title,
    String message, {
    SnackPosition? position,
    Color? backgroundColor,
    Color? colorText,
    Duration? duration,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        Get.snackbar(
          title,
          message,
          snackPosition: position,
          backgroundColor: backgroundColor,
          colorText: colorText,
          duration: duration,
        );
      } catch (_) {}
    });
  }

  /// 加载书籍列表
  Future<void> loadNovels() async {
    TimeConsumptionTest desktopTest = TimeConsumptionTest()..start(log: false);
    try {
      final result = getAllNovels();
      novels.value = result;
      logger.log(
        '加载共计 ${result.length}(+${desktopTest.end(log: false)}ms) 本书籍，前 3 本最近阅读时间: ${result.take(3).map((n) => '${n.title}: ${n.lastReadAt}').join(', ')}',
        name: '书库',
      );
    } catch (e) {
      _showSnack('错误', '加载书籍列表失败: $e');
    }
  }

  /// 扫描文件夹（优化版，支持大量书籍）
  Future<void> scanFolder() async {
    try {
      final result = await FilePicker.platform.getDirectoryPath();
      if (result == null) return;

      isScanning.value = true;

      // 使用批量扫描，每批处理100本书籍，避免阻塞
      final batches = await scanNovelsFolderBatched(
        folderPath: result,
        batchSize: BigInt.from(100),
      );

      int totalFound = 0;
      for (final batch in batches) {
        totalFound += batch.novels.length;

        // 每批扫描完成后，立即重新加载显示
        await loadNovels();

        // 显示进度
        if (!batch.isFinished) {
          _showSnack(
            '扫描中',
            '已扫描 ${batch.completed}/${batch.total} 个文件，找到 $totalFound 本书籍',
            duration: const Duration(seconds: 1),
          );
        }
      }

      // 重新加载所有书籍（包括已存在的和新扫描的）
      await loadNovels();

      _showSnack('成功', '扫描完成，共找到 $totalFound 本新书籍');
    } catch (e) {
      _showSnack('错误', '扫描失败: $e');
    } finally {
      isScanning.value = false;
    }
  }

  /// 添加单个书籍
  Future<void> addSingleNovel() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'epub'],
        allowMultiple: true,
      );

      if (result == null || result.files.isEmpty) return;

      final filePath = result.files;
      if (filePath.isEmpty) return;

      final _ = addNovel(filePaths: filePath.map((f) => f.path!).toList()).first;
      await loadNovels();

      _showSnack('成功', '已添加 ${filePath.length} 本书籍');
    } catch (e) {
      _showSnack('错误', '添加书籍失败: $e');
    }
  }

  /// 删除书籍
  Future<void> deleteNovel(String novelId) async {
    try {
      removeNovel(novelId: novelId);
      novels.removeWhere((n) => n.id == novelId);
      _showSnack('成功', '已删除书籍');
    } catch (e) {
      _showSnack('错误', '删除失败: $e');
    }
  }

  /// 清空所有书籍（带确认）
  Future<void> confirmClearAllNovels() async {
    // 现在不在 ViewModel 中显示对话框；UI 层应负责确认弹窗。
    // 此方法保留为直接触发清空操作的入口（无需 UI 弹窗）。
    await clearAllNovelsAction();
  }

  /// 不弹窗的清空实现，供界面在确认后直接调用
  Future<void> clearAllNovelsAction() async {
    try {
      isClearingNovels.value = true;

      // 调用后端绑定的清空方法
      clearAllNovels();

      // 等待一小段时间让操作完成
      await Future.delayed(const Duration(milliseconds: 100));
      await loadNovels();

      _showSnack('成功', '已清空所有书籍');
    } catch (e) {
      _showSnack('错误', '清空失败: $e');
    } finally {
      isClearingNovels.value = false;
    }
  }

  /// 创建新文件夹
  Future<void> createFolder() async {
    try {
      final folderName = '新文件夹 ${DateTime.now().millisecondsSinceEpoch}';
      createNovelFolder(name: folderName);
      await loadNovels();
      _showSnack('成功', '已创建文件夹 "$folderName"');
    } catch (e) {
      _showSnack('错误', '创建文件夹失败: $e');
    }
  }

  /// 在内容中搜索（优化版，在 Rust 端完成批量搜索，支持进度和取消）
  Future<void> searchInContent(String keyword) async {
    if (keyword.isEmpty) {
      contentSearchResults.clear();
      return;
    }

    try {
      _searchCancelled = false;
      isSearching.value = true;
      isCancelling.value = false;
      searchProgress.value = 0.0;
      searchCompleted.value = 0;
      searchTotal.value = novels.length; // 先设置总数
      contentSearchResults.clear();

      final allResults = <NovelMetadata>[];

      // 调用 Rust 端的批量搜索接口，每批处理5本书籍，获取实时进度
      final batches = await searchInAllNovelsBatched(keyword: keyword, batchSize: BigInt.from(5));

      for (final batch in batches) {
        // 检查是否取消
        if (_searchCancelled) {
          _showSnack('搜索', '已取消搜索');
          break;
        }

        // 添加本批次的搜索结果
        allResults.addAll(batch.results.map((r) => r.novel));

        // 更新进度（BigInt 转 int）
        final completed = batch.completed.toInt();
        final total = batch.total.toInt();
        searchCompleted.value = completed;
        searchTotal.value = total;
        searchProgress.value = total > 0 ? completed / total : 0.0;

        // 实时更新搜索结果
        contentSearchResults.value = allResults.toList();
      }

      if (!_searchCancelled) {
        if (allResults.isEmpty) {
          _showSnack('搜索结果', '没有找到包含"$keyword"的书籍');
        } else {
          _showSnack('搜索结果', '找到 ${allResults.length} 本包含关键词的书籍');
        }
      }
    } catch (e) {
      _showSnack('错误', '搜索失败: $e');
    } finally {
      isSearching.value = false;
      searchProgress.value = 0.0;
    }
  }

  /// 取消搜索
  Future<void> cancelSearch() async {
    if (isCancelling.value) return; // 防止重复点击

    isCancelling.value = true;
    _searchCancelled = true;

    // 通知 Rust 层取消搜索
    try {
      rust_api.cancelSearch();
      // 等待一小段时间让 Rust 层响应取消
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (e) {
      if (kDebugMode) {
        print('取消搜索失败: $e');
      }
    } finally {
      isCancelling.value = false;
    }
  }

  /// 重新排序书籍
  Future<void> reorderNovels(int oldIndex, int newIndex) async {
    try {
      final displayNovels = filteredNovels;
      if (oldIndex < 0 ||
          oldIndex >= displayNovels.length ||
          newIndex < 0 ||
          newIndex >= displayNovels.length) {
        return;
      }

      // 提取排序后的ID列表
      final reorderedIds = List<String>.from(displayNovels.map((n) => n.id));
      final movedId = reorderedIds.removeAt(oldIndex);
      reorderedIds.insert(newIndex, movedId);

      // 调用后端批量更新排序
      batchUpdateNovelOrders(novelIds: reorderedIds);

      // 重新加载列表
      await loadNovels();

      _showSnack('成功', '已更新排序');
    } catch (e) {
      _showSnack('错误', '更新排序失败: $e');
    }
  }
}
