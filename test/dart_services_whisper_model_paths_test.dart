// P0-5 连带回归：whisper 模型下载进度条必须看得见进度。
//
// Rust 侧把模型下载改成「先写 .ggml-{preset}.bin.part，成功后 rename 到最终名」
// （见 rust/whisper_module/src/model.rs 的 part_path_of）。下载期间最终文件名
// **完全不存在**，旧进度条只盯最终名 → 进度恒 0、结束时才跳到 100。
//
// 另外旧实现的数据目录口径是 `APPDATA ?? '$HOME/Library/Application Support'`：
// Windows 上缺 APPDATA 会拿到 macOS 目录、Linux 完全不认 XDG，读的目录根本不是
// 模型落地的目录。这里逐条锁定与 Rust db_module::paths 一致的口径。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slime_works/core/services/whisper_model_paths.dart';

void main() {
  setUp(() {});

  group('模型路径口径与 Rust 侧一致（P0-5 连带）', () {
    test('Windows 用 APPDATA，缺失时回落 "."（与 Rust 相同）', () {
      final base = WhisperModelPaths.dataBase(
        environment: <String, String>{'APPDATA': r'C:UsersmeAppDataRoaming'},
        operatingSystem: 'windows',
      );
      expect(base, r'C:UsersmeAppDataRoaming');

      // 只有 HOME 没有 APPDATA：不能去拿 macOS 目录，Rust 侧回落 "."
      final fallback = WhisperModelPaths.dataBase(
        environment: <String, String>{'HOME': r'C:Usersme'},
        operatingSystem: 'windows',
      );
      expect(fallback, '.');
    });

    test('macOS 用 ~/Library/Application Support', () {
      final base = WhisperModelPaths.dataBase(
        environment: <String, String>{'HOME': '/Users/me'},
        operatingSystem: 'macos',
      );
      expect(base, '/Users/me/Library/Application Support');
    });

    test('Linux 优先 XDG_DATA_HOME，其次 ~/.local/share', () {
      expect(
        WhisperModelPaths.dataBase(
          environment: <String, String>{'XDG_DATA_HOME': '/xdg', 'HOME': '/home/me'},
          operatingSystem: 'linux',
        ),
        '/xdg',
      );
      expect(
        WhisperModelPaths.dataBase(
          environment: <String, String>{'HOME': '/home/me'},
          operatingSystem: 'linux',
        ),
        '/home/me/.local/share',
      );
    });

    test('模型文件名与 Rust 的 model_filename() 一致', () {
      expect(WhisperModelPaths.fileName('large-v3'), 'ggml-large-v3.bin');
      expect(WhisperModelPaths.fileName('tiny'), 'ggml-tiny.bin');
    });

    test('.part 名与 Rust part_path_of 逐字一致（前导点 + .part 后缀）', () {
      // Rust 侧断言：/tmp/models/.ggml-tiny.bin.part
      expect(WhisperModelPaths.partFileName('tiny'), '.ggml-tiny.bin.part');
      expect(WhisperModelPaths.partFileName('large-v3-turbo'), '.ggml-large-v3-turbo.bin.part');
    });

    test('Windows 下用反斜杠拼路径（与 Rust PathBuf 显示一致）', () {
      final part = WhisperModelPaths.partPath(
        'tiny',
        environment: <String, String>{'APPDATA': r'C:\Users\me\AppData\Roaming'},
        operatingSystem: 'windows',
      );
      expect(part, endsWith('.ggml-tiny.bin.part'));
      expect(part.contains('/'), isFalse, reason: 'Windows 路径不该出现正斜杠');
    });

    test('partPath 与最终路径同目录、且不是同一个文件', () {
      final paths = WhisperModelPaths.partPath(
        'small',
        environment: <String, String>{'HOME': '/Users/me'},
        operatingSystem: 'macos',
      );
      final finalPath = WhisperModelPaths.filePath(
        'small',
        environment: <String, String>{'HOME': '/Users/me'},
        operatingSystem: 'macos',
      );
      expect(paths, isNot(finalPath));
      expect(paths.endsWith('.ggml-small.bin.part'), isTrue);
      expect(finalPath.endsWith('ggml-small.bin'), isTrue);
      // 同目录：rename 才能在同一个文件系统内原子完成
      expect(paths.substring(0, paths.lastIndexOf('/')),
          finalPath.substring(0, finalPath.lastIndexOf('/')));
      expect(paths, contains('Library/Application Support/SlimeWorks/whisper_models'));
    });
  });

  group('下载进度探测器（读 .part → rename 后读最终名）', () {
    const preset = 'tiny';
    const total = 1000;

    /// 用一张「路径 → 大小」表模拟磁盘，避免真建几个 GB 的文件。
    WhisperModelDownloadTracker trackerWith(
      Map<String, int> sizes,
      void Function(double) onProgress,
    ) {
      return WhisperModelDownloadTracker(
        presetName: preset,
        totalBytes: total,
        onProgress: onProgress,
        environment: <String, String>{'HOME': '/Users/me'},
        operatingSystem: 'macos',
        fileSizeReader: (path) => sizes[path],
      );
    }

    test('下载中：只有 .part 时按已写大小报进度（不再恒为 0）', () {
      final reported = <double>[];
      final partPath = WhisperModelPaths.partPath(
        preset,
        environment: <String, String>{'HOME': '/Users/me'},
        operatingSystem: 'macos',
      );

      // 下载到 30%
      final tracker = trackerWith(<String, int>{partPath: 300}, reported.add);
      expect(tracker.pollOnce(), closeTo(0.3, 1e-9));
      expect(reported, hasLength(1));

      // 继续下到 80%
      final tracker80 = trackerWith(<String, int>{partPath: 800}, reported.add);
      expect(tracker80.pollOnce(), closeTo(0.8, 1e-9));
    });

    test('.part 未装满时封顶 0.99（rename 完成前不能说完成）', () {
      final partPath = WhisperModelPaths.partPath(
        preset,
        environment: <String, String>{'HOME': '/Users/me'},
        operatingSystem: 'macos',
      );
      // 容器允许 size 略超（chunked 写入竞态），但没 rename 就不能报 1.0
      final tracker = trackerWith(<String, int>{partPath: 1200}, (_) {});
      expect(tracker.pollOnce(), 0.99);
    });

    test('rename 完成：只有最终名时直接报 1.0', () {
      final finalPath = WhisperModelPaths.filePath(
        preset,
        environment: <String, String>{'HOME': '/Users/me'},
        operatingSystem: 'macos',
      );
      final reported = <double>[];
      final tracker = trackerWith(<String, int>{finalPath: total}, reported.add);

      expect(tracker.pollOnce(), 1.0);
      expect(reported, <double>[1.0]);
    });

    test('.part 还在时优先读 .part（旧文件名残留不会让进度假满）', () {
      final partPath = WhisperModelPaths.partPath(
        preset,
        environment: <String, String>{'HOME': '/Users/me'},
        operatingSystem: 'macos',
      );
      final finalPath = WhisperModelPaths.filePath(
        preset,
        environment: <String, String>{'HOME': '/Users/me'},
        operatingSystem: 'macos',
      );
      // 上一次下载残留了一个旧最终名（半截），本次下载刚开始写了 .part
      final tracker = trackerWith(
        <String, int>{partPath: 100, finalPath: total},
        (_) {},
      );
      expect(tracker.pollOnce(), closeTo(0.1, 1e-9),
          reason: '在写 .part 就说明还在下载，不能被旧最终名骗成完成');
    });

    test('下载失败/取消（.part 被删）：返回 null 且不回退进度、不卡死', () {
      final partPath = WhisperModelPaths.partPath(
        preset,
        environment: <String, String>{'HOME': '/Users/me'},
        operatingSystem: 'macos',
      );
      final reported = <double>[];
      final sizes = <String, int>{partPath: 600};
      final tracker = trackerWith(sizes, reported.add);

      expect(tracker.pollOnce(), closeTo(0.6, 1e-9));
      expect(tracker.lastProgress, closeTo(0.6, 1e-9));

      // Rust 侧失败清理：删掉 .part
      sizes.remove(partPath);
      expect(tracker.pollOnce(), isNull, reason: '文件都没了，本次没有新进度');
      expect(tracker.lastProgress, closeTo(0.6, 1e-9), reason: '进度不回退');
      // 关键：不能一直往上飘，也不该再回调一次（页面 finally 会清掉整个下载态）
      expect(reported, hasLength(1));
      expect(reported.single, closeTo(0.6, 1e-9));
    });

    test('值没变化就不重复回调（避免每 500ms 一次 setState）', () {
      final partPath = WhisperModelPaths.partPath(
        preset,
        environment: <String, String>{'HOME': '/Users/me'},
        operatingSystem: 'macos',
      );
      final reported = <double>[];
      final tracker = trackerWith(<String, int>{partPath: 500}, reported.add);

      tracker.pollOnce();
      tracker.pollOnce();
      tracker.pollOnce();

      expect(reported, hasLength(1), reason: '大小没变就不该重复 setState');
    });

    test('totalBytes 未知（<=0）时不除零，返回 0', () {
      final partPath = WhisperModelPaths.partPath(
        preset,
        environment: <String, String>{'HOME': '/Users/me'},
        operatingSystem: 'macos',
      );
      final tracker = WhisperModelDownloadTracker(
        presetName: preset,
        totalBytes: 0,
        onProgress: (_) {},
        environment: <String, String>{'HOME': '/Users/me'},
        operatingSystem: 'macos',
        fileSizeReader: (path) => path == partPath ? 12345 : null,
      );

      expect(tracker.pollOnce(), 0);
    });

    test('真实文件系统：写 .part 能读到进度，rename 后读到 1.0', () {
      // 不注入 reader，走真实 File API（验证 existsSync/lengthSync 那条路径）
      final tempDir = Directory.systemTemp.createTempSync('sw_whisper_part_test');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final part = File('${tempDir.path}/.ggml-tiny.bin.part');
      final dest = File('${tempDir.path}/ggml-tiny.bin');
      final reported = <double>[];

      final tracker = WhisperModelDownloadTracker(
        presetName: preset,
        totalBytes: 1000,
        onProgress: reported.add,
        fileSizeReader: (path) {
          // 把注入的绝对路径映射到临时目录里的同名文件
          final name = path.split(Platform.pathSeparator).last;
          final file = File('${tempDir.path}/$name');
          if (!file.existsSync()) return null;
          return file.lengthSync();
        },
      );

      part.writeAsBytesSync(List<int>.filled(400, 0));
      expect(tracker.pollOnce(), closeTo(0.4, 1e-9));

      // 模拟 rename
      part.renameSync(dest.path);
      expect(tracker.pollOnce(), 1.0);
      expect(reported.first, closeTo(0.4, 1e-9));
      expect(reported.last, 1.0);
    });

    test('start() 立即采样一次，cancel() 后不再采样', () async {
      final partPath = WhisperModelPaths.partPath(
        preset,
        environment: <String, String>{'HOME': '/Users/me'},
        operatingSystem: 'macos',
      );
      var reads = 0;
      final tracker = WhisperModelDownloadTracker(
        presetName: preset,
        totalBytes: total,
        onProgress: (_) {},
        environment: <String, String>{'HOME': '/Users/me'},
        operatingSystem: 'macos',
        pollInterval: const Duration(milliseconds: 20),
        fileSizeReader: (path) {
          if (path == partPath) reads++;
          return path == partPath ? 100 : null;
        },
      );

      tracker.start();
      expect(reads, greaterThanOrEqualTo(1), reason: 'start 应立刻采样一次');

      await Future<void>.delayed(const Duration(milliseconds: 50));
      final afterStart = reads;
      expect(afterStart, greaterThan(1), reason: '定时器应持续采样');

      tracker.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(reads, afterStart, reason: 'cancel 之后不该再采样');
    });
  });

  group('下载进度「不会卡死」的端到端语义', () {
    test('完整生命周期：0 → 中途 → 1.0（三条状态都被观察到）', () {
      const total = 1000;
      final partPath = WhisperModelPaths.partPath(
        'tiny',
        environment: <String, String>{'HOME': '/Users/me'},
        operatingSystem: 'macos',
      );
      final finalPath = WhisperModelPaths.filePath(
        'tiny',
        environment: <String, String>{'HOME': '/Users/me'},
        operatingSystem: 'macos',
      );
      final sizes = <String, int>{};
      final reported = <double>[];

      final tracker = WhisperModelDownloadTracker(
        presetName: 'tiny',
        totalBytes: total,
        onProgress: reported.add,
        environment: <String, String>{'HOME': '/Users/me'},
        operatingSystem: 'macos',
        fileSizeReader: (path) => sizes[path],
      );

      // 还没开始写
      expect(tracker.pollOnce(), isNull);
      // 下到 25%
      sizes[partPath] = 250;
      expect(tracker.pollOnce(), closeTo(0.25, 1e-9));
      // 下到 75%
      sizes[partPath] = 750;
      expect(tracker.pollOnce(), closeTo(0.75, 1e-9));
      // rename
      sizes.remove(partPath);
      sizes[finalPath] = total;
      expect(tracker.pollOnce(), 1.0);

      expect(reported, hasLength(3));
      // 单调不减（否则 UI 会来回跳）
      for (var i = 1; i < reported.length; i++) {
        expect(reported[i], greaterThanOrEqualTo(reported[i - 1]));
      }
    });
  });
}
