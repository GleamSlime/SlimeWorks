import 'package:get/get.dart';
import 'package:file_picker/file_picker.dart';
import 'package:slime_works/src/rust/api/novel_reader.dart';

/// 小说库 ViewModel
class NovelLibraryViewModel extends GetxController {
  final novels = <NovelMetadata>[].obs;
  final isScanning = false.obs;

  @override
  void onInit() {
    super.onInit();
    loadNovels();
  }

  /// 加载小说列表
  Future<void> loadNovels() async {
    try {
      final result = getAllNovels();
      novels.value = result;
    } catch (e) {
      Get.snackbar('错误', '加载小说列表失败: $e');
    }
  }

  /// 扫描文件夹
  Future<void> scanFolder() async {
    try {
      final result = await FilePicker.platform.getDirectoryPath();
      if (result == null) return;

      isScanning.value = true;

      final scannedNovels = scanNovelsFolder(folderPath: result);
      novels.value = scannedNovels;

      Get.snackbar('成功', '扫描完成，找到 ${scannedNovels.length} 本小说');
    } catch (e) {
      Get.snackbar('错误', '扫描失败: $e');
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

      Get.snackbar('成功', '已添加《${novel.title}》');
    } catch (e) {
      Get.snackbar('错误', '添加小说失败: $e');
    }
  }

  /// 删除小说
  Future<void> deleteNovel(String novelId) async {
    try {
      removeNovel(novelId: novelId);
      novels.removeWhere((n) => n.id == novelId);
      Get.snackbar('成功', '已删除小说');
    } catch (e) {
      Get.snackbar('错误', '删除失败: $e');
    }
  }
}
