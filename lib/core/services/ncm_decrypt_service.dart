import 'dart:async';
import 'dart:convert';

import 'package:get/get.dart';
import 'package:slime_works/core/utils/logger.dart';

import 'package:slime_works/src/rust/api/ncm_decrypt.dart' as rust_api;

const Loggers _logger = Loggers(name: 'NCM解密服务');

enum NcmDecryptStatus { idle, scanning, decrypting, completed, failed, cancelled }

class NcmFileInfo {
  final String path;
  final String fileName;
  final int fileSize;

  const NcmFileInfo({
    required this.path,
    required this.fileName,
    required this.fileSize,
  });
}

class NcmDecryptProgressInfo {
  final int totalFiles;
  final int currentFileIndex;
  final String currentFileName;
  final double totalProgress;
  final double elapsedSeconds;
  final NcmDecryptStatus status;

  const NcmDecryptProgressInfo({
    this.totalFiles = 0,
    this.currentFileIndex = 0,
    this.currentFileName = '',
    this.totalProgress = 0.0,
    this.elapsedSeconds = 0.0,
    this.status = NcmDecryptStatus.idle,
  });
}

class NcmDecryptResultInfo {
  final bool success;
  final int totalFiles;
  final int successCount;
  final int failedCount;
  final double elapsedSeconds;
  final List<NcmFailedFile> failedFiles;
  final String? errorMessage;

  const NcmDecryptResultInfo({
    required this.success,
    this.totalFiles = 0,
    this.successCount = 0,
    this.failedCount = 0,
    this.elapsedSeconds = 0.0,
    this.failedFiles = const [],
    this.errorMessage,
  });
}

class NcmFailedFile {
  final String path;
  final String reason;

  const NcmFailedFile({required this.path, required this.reason});
}

class NcmDecryptService extends GetxService {
  final Rx<NcmDecryptProgressInfo> progress = const NcmDecryptProgressInfo().obs;
  final RxBool isDecrypting = false.obs;
  final Rx<NcmDecryptResultInfo?> lastResult = Rx<NcmDecryptResultInfo?>(null);
  final RxList<NcmFileInfo> scannedFiles = <NcmFileInfo>[].obs;

  Timer? _pollTimer;

  @override
  void onClose() {
    _pollTimer?.cancel();
    super.onClose();
  }

  /// 扫描目录下的 NCM 文件
  Future<List<NcmFileInfo>> scanFiles(String dir) async {
    try {
      final json = rust_api.ncmScanFilesJson(dir: dir);
      final list = jsonDecode(json) as List<dynamic>;
      final files = list
          .map(
            (e) => NcmFileInfo(
              path: e['path'] as String,
              fileName: e['file_name'] as String,
              fileSize: e['file_size'] as int,
            ),
          )
          .toList();
      scannedFiles.value = files;
      return files;
    } catch (e) {
      _logger.error('扫描 NCM 文件失败: $e');
      return [];
    }
  }

  /// 启动解密任务
  Future<void> startDecrypt({
    required String sourceDir,
    required bool deleteAfterDecrypt,
  }) async {
    if (isDecrypting.value) return;

    isDecrypting.value = true;
    progress.value = const NcmDecryptProgressInfo(status: NcmDecryptStatus.scanning);
    lastResult.value = null;

    try {
      final configJson = jsonEncode({
        'source_dir': sourceDir,
        'delete_after_decrypt': deleteAfterDecrypt,
      });

      rust_api.ncmDecryptStart(configJson: configJson);
      _startPolling();
    } catch (e) {
      _logger.error('启动 NCM 解密失败: $e');
      lastResult.value = NcmDecryptResultInfo(success: false, errorMessage: e.toString());
      progress.value = const NcmDecryptProgressInfo(status: NcmDecryptStatus.failed);
      isDecrypting.value = false;
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _pollProgress();
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _pollProgress() {
    try {
      final json = rust_api.ncmGetProgressJson();
      if (json == '{}' || json.isEmpty) return;

      final map = jsonDecode(json) as Map<String, dynamic>;
      final statusStr = map['status'] as String? ?? '';
      final status = _parseStatus(statusStr);

      final newProgress = NcmDecryptProgressInfo(
        totalFiles: map['total_files'] as int? ?? 0,
        currentFileIndex: map['current_file_index'] as int? ?? 0,
        currentFileName: map['current_file_name'] as String? ?? '',
        totalProgress: (map['total_progress'] as num?)?.toDouble() ?? 0.0,
        elapsedSeconds: (map['elapsed_seconds'] as num?)?.toDouble() ?? 0.0,
        status: status,
      );

      progress.value = newProgress;

      if (status == NcmDecryptStatus.completed || status == NcmDecryptStatus.failed) {
        _stopPolling();
        _finalizeResult(newProgress);
      }
    } catch (e) {
      _logger.error('轮询 NCM 解密进度失败: $e');
    }
  }

  void _finalizeResult(NcmDecryptProgressInfo finalProgress) {
    try {
      final resultJson = rust_api.ncmGetResultJson();
      if (resultJson != '{}' && resultJson.isNotEmpty) {
        final resultMap = jsonDecode(resultJson) as Map<String, dynamic>;
        lastResult.value = NcmDecryptResultInfo(
          success: resultMap['success'] as bool? ?? false,
          totalFiles: resultMap['total_files'] as int? ?? 0,
          successCount: resultMap['success_count'] as int? ?? 0,
          failedCount: resultMap['failed_count'] as int? ?? 0,
          elapsedSeconds: (resultMap['elapsed_seconds'] as num?)?.toDouble() ?? 0.0,
          failedFiles: (resultMap['failed_files'] as List?)
                  ?.map((e) => NcmFailedFile(
                        path: e['path'] as String,
                        reason: e['reason'] as String,
                      ))
                  .toList() ??
              [],
          errorMessage: resultMap['error_message'] as String?,
        );
      } else {
        lastResult.value = NcmDecryptResultInfo(
          success: finalProgress.status == NcmDecryptStatus.completed,
          totalFiles: finalProgress.totalFiles,
          elapsedSeconds: finalProgress.elapsedSeconds,
        );
      }
    } catch (e) {
      _logger.error('获取 NCM 解密结果失败: $e');
      lastResult.value = NcmDecryptResultInfo(
        success: finalProgress.status == NcmDecryptStatus.completed,
        totalFiles: finalProgress.totalFiles,
        elapsedSeconds: finalProgress.elapsedSeconds,
      );
    }
    isDecrypting.value = false;
  }

  /// 取消解密
  void cancelDecrypt() {
    try {
      rust_api.ncmDecryptCancel();
    } catch (e) {
      _logger.error('取消 NCM 解密失败: $e');
    }
  }

  String formatFileSize(int bytes) {
    const kb = 1024;
    const mb = 1024 * kb;
    const gb = 1024 * mb;
    if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(2)} GB';
    } else if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(2)} MB';
    } else if (bytes >= kb) {
      return '${(bytes / kb).toStringAsFixed(2)} KB';
    }
    return '$bytes B';
  }

  String formatDuration(double seconds) {
    if (seconds < 60) {
      return '${seconds.toStringAsFixed(1)} 秒';
    }
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).round();
    return '$mins 分 $secs 秒';
  }

  NcmDecryptStatus _parseStatus(String status) {
    switch (status) {
      case 'Scanning':
        return NcmDecryptStatus.scanning;
      case 'Decrypting':
        return NcmDecryptStatus.decrypting;
      case 'Completed':
        return NcmDecryptStatus.completed;
      case 'Failed':
        return NcmDecryptStatus.failed;
      case 'Cancelled':
        return NcmDecryptStatus.cancelled;
      default:
        return NcmDecryptStatus.idle;
    }
  }
}
