import 'dart:async';
import 'dart:convert';

import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/src/rust/api/extract.dart' as rust_api;

enum ExtractOutputMode { sameDirectory, flatToOutput, byArchiveName, preserveStructure }

enum ExtractStatus { idle, scanning, extracting, completed, failed, cancelled }

class ArchiveInfo {
  final String path;
  final String fileName;
  final int fileSize;
  final bool isPasswordProtected;

  const ArchiveInfo({
    required this.path,
    required this.fileName,
    required this.fileSize,
    this.isPasswordProtected = false,
  });
}

class ExtractProgressInfo {
  final int totalArchives;
  final int currentArchiveIndex;
  final String currentArchiveName;
  final double currentArchiveProgress;
  final double totalProgress;
  final int totalFileSize;
  final int extractedFileSize;
  final double elapsedSeconds;
  final double estimatedRemainingSeconds;
  final ExtractStatus status;

  const ExtractProgressInfo({
    this.totalArchives = 0,
    this.currentArchiveIndex = 0,
    this.currentArchiveName = '',
    this.currentArchiveProgress = 0.0,
    this.totalProgress = 0.0,
    this.totalFileSize = 0,
    this.extractedFileSize = 0,
    this.elapsedSeconds = 0.0,
    this.estimatedRemainingSeconds = 0.0,
    this.status = ExtractStatus.idle,
  });
}

class ExtractResultInfo {
  final bool success;
  final int totalArchives;
  final int totalFileSize;
  final int extractedSize;
  final double elapsedSeconds;
  final List<String> failedArchives;
  final String? errorMessage;

  const ExtractResultInfo({
    required this.success,
    this.totalArchives = 0,
    this.totalFileSize = 0,
    this.extractedSize = 0,
    this.elapsedSeconds = 0.0,
    this.failedArchives = const [],
    this.errorMessage,
  });
}

class PasswordEntry {
  final String id;
  final String password;
  final String? remark;
  final int createdAt;

  const PasswordEntry({
    required this.id,
    required this.password,
    this.remark,
    required this.createdAt,
  });

  String get displayName => remark?.isNotEmpty == true ? remark! : password;
}

class ExtractService extends GetxService {
  final Rx<ExtractProgressInfo> progress = const ExtractProgressInfo().obs;
  final RxBool isExtracting = false.obs;
  final RxList<PasswordEntry> passwords = <PasswordEntry>[].obs;
  final Rx<ExtractResultInfo?> lastResult = Rx<ExtractResultInfo?>(null);

  Timer? _pollTimer;

  @override
  void onInit() {
    super.onInit();
    _initPasswordTable();
  }

  @override
  void onClose() {
    _pollTimer?.cancel();
    super.onClose();
  }

  Future<void> _initPasswordTable() async {
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final dbPath = '${appDocDir.path}/slime_extract.redb';
      rust_api.extractInitPasswordTable(dbPath: dbPath);
      await _loadPasswords();
    } catch (e) {
      logger.e('初始化解压密码表失败: $e');
    }
  }

  Future<void> _loadPasswords() async {
    try {
      final json = rust_api.extractListPasswordsJson();
      final list = jsonDecode(json) as List<dynamic>;
      passwords.value = list
          .map(
            (e) => PasswordEntry(
              id: e['id'] as String,
              password: e['password'] as String,
              remark: e['remark'] as String?,
              createdAt: e['created_at'] as int,
            ),
          )
          .toList();
    } catch (e) {
      logger.e('加载解压密码失败: $e');
    }
  }

  Future<void> addPassword(String password, {String? remark}) async {
    try {
      final json = rust_api.extractAddPassword(password: password, remark: remark);
      final map = jsonDecode(json) as Map<String, dynamic>;
      passwords.add(
        PasswordEntry(
          id: map['id'] as String,
          password: map['password'] as String,
          remark: map['remark'] as String?,
          createdAt: map['created_at'] as int,
        ),
      );
    } catch (e) {
      logger.e('添加解压密码失败: $e');
    }
  }

  Future<void> removePassword(String id) async {
    try {
      rust_api.extractRemovePassword(id: id);
      passwords.removeWhere((e) => e.id == id);
    } catch (e) {
      logger.e('删除解压密码失败: $e');
    }
  }

  Future<void> updatePasswordRemark(String id, String? remark) async {
    try {
      rust_api.extractUpdatePasswordRemark(id: id, remark: remark);
      final index = passwords.indexWhere((e) => e.id == id);
      if (index >= 0) {
        final old = passwords[index];
        passwords[index] = PasswordEntry(
          id: old.id,
          password: old.password,
          remark: remark,
          createdAt: old.createdAt,
        );
      }
    } catch (e) {
      logger.e('更新解压密码备注失败: $e');
    }
  }

  Future<bool> ensurePasswordExists(String password) async {
    final exists = passwords.any((e) => e.password == password);
    if (!exists) {
      await addPassword(password);
      return true;
    }
    return false;
  }

  Future<List<ArchiveInfo>> scanArchives(String dir) async {
    try {
      final json = rust_api.extractScanArchivesJson(dir: dir);
      final list = jsonDecode(json) as List<dynamic>;
      return list
          .map(
            (e) => ArchiveInfo(
              path: e['path'] as String,
              fileName: e['file_name'] as String,
              fileSize: e['file_size'] as int,
              isPasswordProtected: e['is_password_protected'] as bool,
            ),
          )
          .toList();
    } catch (e) {
      logger.e('扫描压缩包失败: $e');
      return [];
    }
  }

  Future<void> startExtract({
    required String sourceDir,
    required String outputDir,
    required ExtractOutputMode outputMode,
    String? password,
    int parallelCount = 1,
    bool deleteAfterExtract = false,
  }) async {
    if (isExtracting.value) return;

    isExtracting.value = true;
    progress.value = const ExtractProgressInfo(status: ExtractStatus.scanning);
    lastResult.value = null;

    try {
      if (password != null && password.isNotEmpty) {
        await ensurePasswordExists(password);
      }

      final configJson = jsonEncode({
        'source_dir': sourceDir,
        'output_dir': outputDir,
        'output_mode': _outputModeToString(outputMode),
        'password': password,
        'parallel_count': parallelCount,
        'delete_after_extract': deleteAfterExtract,
      });

      rust_api.extractStart(configJson: configJson);

      _startPolling();
    } catch (e) {
      logger.e('启动解压失败: $e');
      lastResult.value = ExtractResultInfo(success: false, errorMessage: e.toString());
      progress.value = const ExtractProgressInfo(status: ExtractStatus.failed);
      isExtracting.value = false;
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
      final json = rust_api.extractGetProgressJson();
      if (json == '{}' || json.isEmpty) return;

      final map = jsonDecode(json) as Map<String, dynamic>;
      final statusStr = map['status'] as String? ?? '';
      final status = _parseStatus(statusStr);

      final newProgress = ExtractProgressInfo(
        totalArchives: map['total_archives'] as int? ?? 0,
        currentArchiveIndex: map['current_archive_index'] as int? ?? 0,
        currentArchiveName: map['current_archive_name'] as String? ?? '',
        currentArchiveProgress: (map['current_archive_progress'] as num?)?.toDouble() ?? 0.0,
        totalProgress: (map['total_progress'] as num?)?.toDouble() ?? 0.0,
        totalFileSize: map['total_file_size'] as int? ?? 0,
        extractedFileSize: map['extracted_file_size'] as int? ?? 0,
        elapsedSeconds: (map['elapsed_seconds'] as num?)?.toDouble() ?? 0.0,
        estimatedRemainingSeconds: (map['estimated_remaining_seconds'] as num?)?.toDouble() ?? 0.0,
        status: status,
      );

      progress.value = newProgress;

      if (status == ExtractStatus.completed || status == ExtractStatus.failed) {
        _stopPolling();
        _finalizeResult(newProgress);
      }
    } catch (e) {
      logger.e('轮询进度失败: $e');
    }
  }

  void _finalizeResult(ExtractProgressInfo finalProgress) {
    try {
      final resultJson = rust_api.extractGetResultJson();
      if (resultJson != '{}' && resultJson.isNotEmpty) {
        final resultMap = jsonDecode(resultJson) as Map<String, dynamic>;
        lastResult.value = ExtractResultInfo(
          success: resultMap['success'] as bool? ?? false,
          totalArchives: resultMap['total_archives'] as int? ?? 0,
          totalFileSize: resultMap['total_file_size'] as int? ?? 0,
          extractedSize: resultMap['extracted_size'] as int? ?? 0,
          elapsedSeconds: (resultMap['elapsed_seconds'] as num?)?.toDouble() ?? 0.0,
          failedArchives: (resultMap['failed_archives'] as List?)?.cast<String>() ?? [],
          errorMessage: resultMap['error_message'] as String?,
        );
      } else {
        lastResult.value = ExtractResultInfo(
          success: finalProgress.status == ExtractStatus.completed,
          totalArchives: finalProgress.totalArchives,
          totalFileSize: finalProgress.totalFileSize,
          extractedSize: finalProgress.extractedFileSize,
          elapsedSeconds: finalProgress.elapsedSeconds,
        );
      }
    } catch (e) {
      logger.e('获取解压结果失败: $e');
      lastResult.value = ExtractResultInfo(
        success: finalProgress.status == ExtractStatus.completed,
        totalArchives: finalProgress.totalArchives,
        totalFileSize: finalProgress.totalFileSize,
        extractedSize: finalProgress.extractedFileSize,
        elapsedSeconds: finalProgress.elapsedSeconds,
      );
    }
    isExtracting.value = false;
  }

  void cancelExtract() {
    try {
      rust_api.extractCancel();
    } catch (e) {
      logger.e('取消解压失败: $e');
    }
  }

  String formatFileSize(int bytes) {
    return rust_api.extractFormatFileSize(bytes: BigInt.from(bytes));
  }

  String formatDuration(double seconds) {
    if (seconds < 60) {
      return '${seconds.toStringAsFixed(1)} 秒';
    }
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).round();
    return '$mins 分 $secs 秒';
  }

  ExtractStatus _parseStatus(String status) {
    switch (status) {
      case 'Extracting':
        return ExtractStatus.extracting;
      case 'Completed':
        return ExtractStatus.completed;
      case 'Failed':
        return ExtractStatus.failed;
      case 'Cancelled':
        return ExtractStatus.cancelled;
      default:
        return ExtractStatus.idle;
    }
  }

  String _outputModeToString(ExtractOutputMode mode) {
    switch (mode) {
      case ExtractOutputMode.sameDirectory:
        return 'SameDirectory';
      case ExtractOutputMode.flatToOutput:
        return 'FlatToOutput';
      case ExtractOutputMode.byArchiveName:
        return 'ByArchiveName';
      case ExtractOutputMode.preserveStructure:
        return 'PreserveStructure';
    }
  }
}
