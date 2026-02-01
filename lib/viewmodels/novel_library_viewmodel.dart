import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:file_picker/file_picker.dart';
import 'package:slime_works/src/rust/api/novel_reader.dart';

/// 小说库 ViewModel
class NovelLibraryViewModel extends GetxController {
  final novels = <NovelMetadata>[].obs;
  final isScanning = false.obs;
  final searchQuery = ''.obs;
  final searchByContent = false.obs; // false=按名字搜索, true=按内容搜索
  final isSearching = false.obs;
  final searchProgress = 0.0.obs;
  final contentSearchResults = <NovelMetadata>[].obs;

  // 搜索取消标志
  bool _searchCancelled = false;

  /// 获取过滤后的小说列表（已排序：最近阅读 > 自定义排序 > 最近添加）
  List<NovelMetadata> get filteredNovels {
    List<NovelMetadata> result;

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

    print('[Library] Sorted ${result.length} novels, first 3: ${result.take(3).map((n) => '${n.title} (lastReadAt: ${n.lastReadAt})').join(', ')}');

    return result;
  }

  @override
  void onInit() {
    super.onInit();
    loadNovels();
  }

  void _showSnack(String title, String message, {SnackPosition? position, Color? backgroundColor, Color? colorText, Duration? duration}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        Get.snackbar(title, message, snackPosition: position, backgroundColor: backgroundColor, colorText: colorText, duration: duration);
      } catch (_) {}
    });
  }

  /// 加载小说列表
  Future<void> loadNovels() async {
    try {
      final result = getAllNovels();
      novels.value = result;
      print('[Library] Loaded ${result.length} novels, first 3 lastReadAt: ${result.take(3).map((n) => '${n.title}: ${n.lastReadAt}').join(', ')}');
    } catch (e) {
      _showSnack('错误', '加载小说列表失败: $e');
    }
  }

  /// 扫描文件夹
  Future<void> scanFolder() async {
    try {
      final result = await FilePicker.platform.getDirectoryPath();
      if (result == null) return;

      isScanning.value = true;

      final scannedNovels = scanNovelsFolder(folderPath: result);

      // 重新加载所有小说（包括已存在的和新扫描的）
      await loadNovels();

      _showSnack('成功', '扫描完成，找到 ${scannedNovels.length} 本新小说');
    } catch (e) {
      _showSnack('错误', '扫描失败: $e');
    } finally {
      isScanning.value = false;
    }
  }

  /// 添加单个小说
  Future<void> addSingleNovel() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['txt', 'epub'], allowMultiple: false);

      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.first.path;
      if (filePath == null) return;

      final novel = addNovel(filePath: filePath);
      await loadNovels();

      _showSnack('成功', '已添加《${novel.title}》');
    } catch (e) {
      _showSnack('错误', '添加小说失败: $e');
    }
  }

  /// 删除小说
  Future<void> deleteNovel(String novelId) async {
    try {
      removeNovel(novelId: novelId);
      novels.removeWhere((n) => n.id == novelId);
      _showSnack('成功', '已删除小说');
    } catch (e) {
      _showSnack('错误', '删除失败: $e');
    }
  }

  /// 清空所有小说（带确认）
  Future<void> confirmClearAllNovels() async {
    // 确认对话框
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除所有 ${novels.length} 本小说吗？此操作不可恢复！'),
        actions: [
          TextButton(onPressed: () => Get.back(result: false), child: const Text('取消')),
          TextButton(
            onPressed: () => Get.back(result: true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // 调用后端绑定的清空方法
      clearAllNovels();
      await loadNovels();
      _showSnack('成功', '已清空所有小说');
    } catch (e) {
      _showSnack('错误', '清空失败: $e');
    }
  }

  /// 在内容中搜索（并发+可取消）
  Future<void> searchInContent(String keyword) async {
    if (keyword.isEmpty) {
      contentSearchResults.clear();
      return;
    }

    try {
      _searchCancelled = false;
      isSearching.value = true;
      searchProgress.value = 0.0;
      contentSearchResults.clear();

      final totalNovels = novels.length;
      final results = <NovelMetadata>[];
      int completed = 0;

      // 并发搜索，每批次处理 5 本小说
      const batchSize = 5;
      for (int batchStart = 0; batchStart < totalNovels; batchStart += batchSize) {
        if (_searchCancelled) {
          _showSnack('搜索', '已取消搜索');
          break;
        }

        final batchEnd = (batchStart + batchSize).clamp(0, totalNovels);
        final batch = novels.sublist(batchStart, batchEnd);

        // 并发搜索当前批次
        final futures = batch.map((novel) async {
          try {
            final matches = await searchInNovel(filePath: novel.filePath, keyword: keyword);
            return matches.isNotEmpty ? novel : null;
          } catch (e) {
            return null;
          }
        });

        final batchResults = await Future.wait(futures);

        // 添加找到的结果
        for (final novel in batchResults) {
          if (novel != null) {
            results.add(novel);
          }
        }

        completed += batch.length;
        searchProgress.value = completed / totalNovels;
      }

      if (!_searchCancelled) {
        contentSearchResults.value = results;

        if (results.isEmpty) {
          _showSnack('搜索结果', '没有找到包含"$keyword"的小说');
        } else {
          _showSnack('搜索结果', '找到 ${results.length} 本包含关键词的小说');
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
  void cancelSearch() {
    _searchCancelled = true;
  }

  /// 重新排序小说
  Future<void> reorderNovels(int oldIndex, int newIndex) async {
    try {
      final displayNovels = filteredNovels;
      if (oldIndex < 0 || oldIndex >= displayNovels.length || newIndex < 0 || newIndex >= displayNovels.length) {
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
