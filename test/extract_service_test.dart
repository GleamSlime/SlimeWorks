import 'package:flutter_test/flutter_test.dart';
import 'package:slime_works/core/services/extract_service.dart';
import 'package:slime_works/pages/tools/components/extract_card.dart';

String formatDuration(double seconds) {
  if (seconds < 60) {
    return '${seconds.toStringAsFixed(1)} 秒';
  }
  final mins = (seconds / 60).floor();
  final secs = (seconds % 60).round();
  return '$mins 分 $secs 秒';
}

void main() {
  // ── ExtractOutputMode ────────────────────────────────────────────────────

  group('ExtractOutputMode', () {
    test('包含 4 种模式', () {
      expect(ExtractOutputMode.values.length, 4);
    });

    test('各枚举值唯一', () {
      expect(ExtractOutputMode.values.toSet().length, 4);
    });
  });

  // ── ExtractStatus ────────────────────────────────────────────────────────

  group('ExtractStatus', () {
    test('包含 6 种状态', () {
      expect(ExtractStatus.values.length, 6);
    });

    test('idle 为默认值', () {
      const progress = ExtractProgressInfo();
      expect(progress.status, ExtractStatus.idle);
    });
  });

  // ── ArchiveInfo ──────────────────────────────────────────────────────────

  group('ArchiveInfo', () {
    test('构造函数正确赋值', () {
      const info = ArchiveInfo(
        path: '/archives/test.zip',
        fileName: 'test.zip',
        fileSize: 1024,
        isPasswordProtected: true,
      );
      expect(info.path, '/archives/test.zip');
      expect(info.fileName, 'test.zip');
      expect(info.fileSize, 1024);
      expect(info.isPasswordProtected, isTrue);
    });

    test('isPasswordProtected 默认为 false', () {
      const info = ArchiveInfo(path: '/a.rar', fileName: 'a.rar', fileSize: 0);
      expect(info.isPasswordProtected, isFalse);
    });

    test('fileSize 为 0 时合法', () {
      const info = ArchiveInfo(path: '/empty.zip', fileName: 'empty.zip', fileSize: 0);
      expect(info.fileSize, 0);
    });
  });

  // ── ExtractProgressInfo ──────────────────────────────────────────────────

  group('ExtractProgressInfo', () {
    test('默认构造函数所有字段为合理默认值', () {
      const info = ExtractProgressInfo();
      expect(info.totalArchives, 0);
      expect(info.currentArchiveIndex, 0);
      expect(info.currentArchiveName, '');
      expect(info.currentArchiveProgress, 0.0);
      expect(info.totalProgress, 0.0);
      expect(info.totalFileSize, 0);
      expect(info.extractedFileSize, 0);
      expect(info.elapsedSeconds, 0.0);
      expect(info.estimatedRemainingSeconds, 0.0);
      expect(info.status, ExtractStatus.idle);
    });

    test('自定义构造正确赋值', () {
      const info = ExtractProgressInfo(
        totalArchives: 10,
        currentArchiveIndex: 3,
        currentArchiveName: 'archive_03.zip',
        currentArchiveProgress: 0.5,
        totalProgress: 0.3,
        totalFileSize: 1024000,
        extractedFileSize: 307200,
        elapsedSeconds: 12.5,
        estimatedRemainingSeconds: 29.1,
        status: ExtractStatus.extracting,
      );
      expect(info.totalArchives, 10);
      expect(info.currentArchiveIndex, 3);
      expect(info.currentArchiveName, 'archive_03.zip');
      expect(info.currentArchiveProgress, 0.5);
      expect(info.totalProgress, 0.3);
      expect(info.totalFileSize, 1024000);
      expect(info.extractedFileSize, 307200);
      expect(info.elapsedSeconds, 12.5);
      expect(info.estimatedRemainingSeconds, 29.1);
      expect(info.status, ExtractStatus.extracting);
    });

    test('进度值在 0-1 范围内合法', () {
      const info = ExtractProgressInfo(
        currentArchiveProgress: 1.0,
        totalProgress: 1.0,
        status: ExtractStatus.completed,
      );
      expect(info.currentArchiveProgress, 1.0);
      expect(info.totalProgress, 1.0);
    });
  });

  // ── ExtractResultInfo ────────────────────────────────────────────────────

  group('ExtractResultInfo', () {
    test('成功结果构造正确', () {
      const result = ExtractResultInfo(
        success: true,
        totalArchives: 5,
        totalFileSize: 5000,
        extractedSize: 5000,
        elapsedSeconds: 30.0,
      );
      expect(result.success, isTrue);
      expect(result.totalArchives, 5);
      expect(result.totalFileSize, 5000);
      expect(result.extractedSize, 5000);
      expect(result.elapsedSeconds, 30.0);
      expect(result.failedArchives, isEmpty);
      expect(result.errorMessage, isNull);
    });

    test('失败结果含错误信息', () {
      const result = ExtractResultInfo(
        success: false,
        errorMessage: '磁盘空间不足',
        failedArchives: ['a.zip', 'b.rar'],
      );
      expect(result.success, isFalse);
      expect(result.errorMessage, '磁盘空间不足');
      expect(result.failedArchives, ['a.zip', 'b.rar']);
    });

    test('默认值合理', () {
      const result = ExtractResultInfo(success: true);
      expect(result.totalArchives, 0);
      expect(result.totalFileSize, 0);
      expect(result.extractedSize, 0);
      expect(result.elapsedSeconds, 0.0);
      expect(result.failedArchives, isEmpty);
      expect(result.errorMessage, isNull);
    });
  });

  // ── PasswordEntry ────────────────────────────────────────────────────────

  group('PasswordEntry', () {
    test('构造函数正确赋值', () {
      const entry = PasswordEntry(
        id: 'pw-001',
        password: 'secret123',
        remark: '测试密码',
        createdAt: 1700000000000,
      );
      expect(entry.id, 'pw-001');
      expect(entry.password, 'secret123');
      expect(entry.remark, '测试密码');
      expect(entry.createdAt, 1700000000000);
    });

    test('remark 为 null 时 displayName 返回 password', () {
      const entry = PasswordEntry(id: 'pw-002', password: 'mypass', createdAt: 0);
      expect(entry.displayName, 'mypass');
    });

    test('remark 为空字符串时 displayName 返回 password', () {
      const entry = PasswordEntry(id: 'pw-003', password: 'mypass', remark: '', createdAt: 0);
      expect(entry.displayName, 'mypass');
    });

    test('remark 非空时 displayName 返回 remark', () {
      const entry = PasswordEntry(id: 'pw-004', password: 'mypass', remark: '我的备注', createdAt: 0);
      expect(entry.displayName, '我的备注');
    });
  });

  // ── ExtractParams ────────────────────────────────────────────────────────

  group('ExtractParams', () {
    test('构造函数正确赋值', () {
      const params = ExtractParams(
        sourceDir: '/source',
        outputDir: '/output',
        outputMode: ExtractOutputMode.byArchiveName,
        password: '1234',
        parallelCount: 4,
        deleteAfterExtract: true,
      );
      expect(params.sourceDir, '/source');
      expect(params.outputDir, '/output');
      expect(params.outputMode, ExtractOutputMode.byArchiveName);
      expect(params.password, '1234');
      expect(params.parallelCount, 4);
      expect(params.deleteAfterExtract, isTrue);
    });

    test('默认值合理', () {
      const params = ExtractParams(
        sourceDir: '/src',
        outputDir: '/out',
        outputMode: ExtractOutputMode.sameDirectory,
      );
      expect(params.password, isNull);
      expect(params.parallelCount, 1);
      expect(params.deleteAfterExtract, isFalse);
    });

    test('sameDirectory 模式下 outputDir 可与 sourceDir 相同', () {
      const params = ExtractParams(
        sourceDir: '/same',
        outputDir: '/same',
        outputMode: ExtractOutputMode.sameDirectory,
      );
      expect(params.outputDir, params.sourceDir);
    });
  });

  // ── formatDuration 逻辑镜像 ──────────────────────────────────────────────

  group('formatDuration', () {
    test('不足 60 秒显示秒', () {
      expect(formatDuration(0.0), '0.0 秒');
      expect(formatDuration(30.5), '30.5 秒');
      expect(formatDuration(59.9), '59.9 秒');
    });

    test('超过 60 秒显示分秒', () {
      expect(formatDuration(60.0), '1 分 0 秒');
      expect(formatDuration(90.0), '1 分 30 秒');
      expect(formatDuration(125.0), '2 分 5 秒');
      expect(formatDuration(3600.0), '60 分 0 秒');
    });

    test('边界值 59.9 仍显示秒', () {
      final result = formatDuration(59.9);
      expect(result.contains('秒'), isTrue);
      expect(result.contains('分'), isFalse);
    });

    test('边界值 60.0 显示分秒', () {
      final result = formatDuration(60.0);
      expect(result.contains('分'), isTrue);
    });

    test('小数秒精确到一位小数', () {
      expect(formatDuration(1.23), '1.2 秒');
      expect(formatDuration(5.67), '5.7 秒');
    });
  });

  // ── _parseStatus 逻辑镜像 ──────────────────────────────────────────────

  group('_parseStatus 逻辑镜像', () {
    ExtractStatus parseStatus(String status) {
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

    test('映射所有已知状态', () {
      expect(parseStatus('Extracting'), ExtractStatus.extracting);
      expect(parseStatus('Completed'), ExtractStatus.completed);
      expect(parseStatus('Failed'), ExtractStatus.failed);
      expect(parseStatus('Cancelled'), ExtractStatus.cancelled);
    });

    test('未知字符串返回 idle', () {
      expect(parseStatus(''), ExtractStatus.idle);
      expect(parseStatus('Unknown'), ExtractStatus.idle);
      expect(parseStatus('extracting'), ExtractStatus.idle);
    });
  });

  // ── _outputModeToString 逻辑镜像 ────────────────────────────────────────

  group('_outputModeToString 逻辑镜像', () {
    String outputModeToString(ExtractOutputMode mode) {
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

    test('映射所有模式', () {
      expect(outputModeToString(ExtractOutputMode.sameDirectory), 'SameDirectory');
      expect(outputModeToString(ExtractOutputMode.flatToOutput), 'FlatToOutput');
      expect(outputModeToString(ExtractOutputMode.byArchiveName), 'ByArchiveName');
      expect(outputModeToString(ExtractOutputMode.preserveStructure), 'PreserveStructure');
    });

    test('往返一致性', () {
      for (final mode in ExtractOutputMode.values) {
        final str = outputModeToString(mode);
        expect(str, isNotEmpty, reason: '${mode.name} 应映射到非空字符串');
      }
    });
  });

  // ── _canStart 逻辑镜像 ──────────────────────────────────────────────────

  group('_canStart 逻辑镜像', () {
    bool canStart({
      required String sourceDir,
      required ExtractOutputMode outputMode,
      required String outputDir,
      required bool isScanning,
    }) {
      if (sourceDir.isEmpty) return false;
      if (outputMode != ExtractOutputMode.sameDirectory && outputDir.isEmpty) return false;
      return !isScanning;
    }

    test('sourceDir 为空时不可开始', () {
      expect(
        canStart(
          sourceDir: '',
          outputMode: ExtractOutputMode.byArchiveName,
          outputDir: '/out',
          isScanning: false,
        ),
        isFalse,
      );
    });

    test('sameDirectory 模式下 outputDir 为空也可开始', () {
      expect(
        canStart(
          sourceDir: '/src',
          outputMode: ExtractOutputMode.sameDirectory,
          outputDir: '',
          isScanning: false,
        ),
        isTrue,
      );
    });

    test('非 sameDirectory 模式下 outputDir 为空不可开始', () {
      expect(
        canStart(
          sourceDir: '/src',
          outputMode: ExtractOutputMode.byArchiveName,
          outputDir: '',
          isScanning: false,
        ),
        isFalse,
      );
      expect(
        canStart(
          sourceDir: '/src',
          outputMode: ExtractOutputMode.flatToOutput,
          outputDir: '',
          isScanning: false,
        ),
        isFalse,
      );
      expect(
        canStart(
          sourceDir: '/src',
          outputMode: ExtractOutputMode.preserveStructure,
          outputDir: '',
          isScanning: false,
        ),
        isFalse,
      );
    });

    test('正在扫描时不可开始', () {
      expect(
        canStart(
          sourceDir: '/src',
          outputMode: ExtractOutputMode.sameDirectory,
          outputDir: '',
          isScanning: true,
        ),
        isFalse,
      );
    });

    test('所有条件满足时可开始', () {
      expect(
        canStart(
          sourceDir: '/src',
          outputMode: ExtractOutputMode.byArchiveName,
          outputDir: '/out',
          isScanning: false,
        ),
        isTrue,
      );
    });
  });

  // ── _onStart 逻辑镜像（ExtractParams 构建） ──────────────────────────────

  group('_onStart 逻辑镜像', () {
    ExtractParams buildParams({
      required String sourceDir,
      required String outputDir,
      required ExtractOutputMode outputMode,
      required String password,
      required int parallelCount,
      required bool deleteAfterExtract,
    }) {
      return ExtractParams(
        sourceDir: sourceDir,
        outputDir: outputMode == ExtractOutputMode.sameDirectory ? sourceDir : outputDir,
        outputMode: outputMode,
        password: password.isEmpty ? null : password,
        parallelCount: parallelCount,
        deleteAfterExtract: deleteAfterExtract,
      );
    }

    test('sameDirectory 模式下 outputDir 使用 sourceDir', () {
      final params = buildParams(
        sourceDir: '/src',
        outputDir: '/out',
        outputMode: ExtractOutputMode.sameDirectory,
        password: '',
        parallelCount: 1,
        deleteAfterExtract: false,
      );
      expect(params.outputDir, '/src');
    });

    test('非 sameDirectory 模式下 outputDir 使用实际值', () {
      final params = buildParams(
        sourceDir: '/src',
        outputDir: '/out',
        outputMode: ExtractOutputMode.byArchiveName,
        password: '',
        parallelCount: 1,
        deleteAfterExtract: false,
      );
      expect(params.outputDir, '/out');
    });

    test('空密码转为 null', () {
      final params = buildParams(
        sourceDir: '/src',
        outputDir: '/out',
        outputMode: ExtractOutputMode.byArchiveName,
        password: '',
        parallelCount: 1,
        deleteAfterExtract: false,
      );
      expect(params.password, isNull);
    });

    test('非空密码保留原值', () {
      final params = buildParams(
        sourceDir: '/src',
        outputDir: '/out',
        outputMode: ExtractOutputMode.byArchiveName,
        password: 'mypassword',
        parallelCount: 1,
        deleteAfterExtract: false,
      );
      expect(params.password, 'mypassword');
    });
  });
}
