import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// PathProviderPlatform 由 path_provider 内部使用但未对其 re-export，
// 这里直接引用其平台接口包以便注入假的应用支持目录（属传递依赖，测试专用）。
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/core/services/media_prefs_service.dart';

/// 指向临时目录的假 PathProvider，用于测试缓存统计/裁剪逻辑。
/// path_provider 包本身导出了 PathProviderPlatform，因此无需额外依赖。
class _FakeAppDirPathProvider extends PathProviderPlatform {
  _FakeAppDirPathProvider(this.rootPath);

  final String rootPath;

  @override
  Future<String?> getApplicationSupportPath() async => rootPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── 持久化往返：setter 写入后，新建实例再 init() 应读回同值 ──────────────

  group('MediaPrefsService 持久化往返', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('quality 往返', () async {
      final svc = MediaPrefsService();
      await svc.init();
      await svc.setQuality(5);

      final reloaded = MediaPrefsService();
      await reloaded.init();
      expect(reloaded.quality.value, 5);
    });

    test('concurrency 往返', () async {
      final svc = MediaPrefsService();
      await svc.init();
      await svc.setConcurrency(15);

      final reloaded = MediaPrefsService();
      await reloaded.init();
      expect(reloaded.concurrency.value, 15);
    });

    test('remoteCoverWidth 往返（含 followLocalWidth=-1 特殊档）', () async {
      final svc = MediaPrefsService();
      await svc.init();
      await svc.setRemoteCoverWidth(960);

      final reloaded = MediaPrefsService();
      await reloaded.init();
      expect(reloaded.remoteCoverWidth.value, 960);

      await svc.setRemoteCoverWidth(MediaPrefsService.followLocalWidth);
      final reloaded2 = MediaPrefsService();
      await reloaded2.init();
      expect(reloaded2.remoteCoverWidth.value, MediaPrefsService.followLocalWidth);
    });

    test('remoteImageWidth / localPreviewWidth 往返', () async {
      final svc = MediaPrefsService();
      await svc.init();
      await svc.setRemoteImageWidth(1080);
      await svc.setLocalPreviewWidth(0); // 0 = 原图

      final reloaded = MediaPrefsService();
      await reloaded.init();
      expect(reloaded.remoteImageWidth.value, 1080);
      expect(reloaded.localPreviewWidth.value, 0);
    });

    test('cacheLimitBytes 往返（2GB 大值不截断）', () async {
      const twoGigabytes = 2 * 1024 * 1024 * 1024;
      final svc = MediaPrefsService();
      await svc.init();
      await svc.setCacheLimitBytes(twoGigabytes);

      final reloaded = MediaPrefsService();
      await reloaded.init();
      expect(reloaded.cacheLimitBytes.value, twoGigabytes);
    });

    test('privacyMode / videoScrubPreload 布尔开关往返', () async {
      final svc = MediaPrefsService();
      await svc.init();
      await svc.setPrivacyMode(true);
      await svc.setVideoScrubPreload(false);

      final reloaded = MediaPrefsService();
      await reloaded.init();
      expect(reloaded.privacyMode.value, isTrue);
      expect(reloaded.videoScrubPreload.value, isFalse);
    });

    test('privacyBlurSigma 往返', () async {
      final svc = MediaPrefsService();
      await svc.init();
      await svc.setPrivacyBlurSigma(25.5);

      final reloaded = MediaPrefsService();
      await reloaded.init();
      expect(reloaded.privacyBlurSigma.value, 25.5);
    });

    test('fileCheckDepth 往返', () async {
      final svc = MediaPrefsService();
      await svc.init();
      await svc.setFileCheckDepth(FileCheckDepth.deep);

      final reloaded = MediaPrefsService();
      await reloaded.init();
      expect(reloaded.fileCheckDepth.value, FileCheckDepth.deep);
    });

    test('空 prefs 时 init() 得到文档化默认值', () async {
      final svc = MediaPrefsService();
      await svc.init();
      expect(svc.quality.value, 3);
      expect(svc.concurrency.value, 8);
      expect(svc.remoteCoverWidth.value, 240);
      expect(svc.remoteImageWidth.value, 0);
      expect(svc.localPreviewWidth.value, 480);
      expect(svc.cacheLimitBytes.value, 1 * 1024 * 1024 * 1024);
      expect(svc.privacyMode.value, isFalse);
      expect(svc.videoScrubPreload.value, isTrue);
      expect(svc.privacyBlurSigma.value, 15.0);
      expect(svc.fileCheckDepth.value, FileCheckDepth.coverOnly);
    });
  });

  // ── 越界钳制：读代码确认的边界（quality 1-5、concurrency 1-20、blur 5-40） ──

  group('MediaPrefsService 越界钳制', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('setter 立即钳制：quality/concurrency/blurSigma', () async {
      final svc = MediaPrefsService();
      await svc.init();

      await svc.setQuality(0);
      expect(svc.quality.value, 1);
      await svc.setQuality(99);
      expect(svc.quality.value, 5);

      await svc.setConcurrency(-5);
      expect(svc.concurrency.value, 1);
      await svc.setConcurrency(100);
      expect(svc.concurrency.value, 20);

      await svc.setPrivacyBlurSigma(1.0);
      expect(svc.privacyBlurSigma.value, 5.0);
      await svc.setPrivacyBlurSigma(99.0);
      expect(svc.privacyBlurSigma.value, 40.0);
    });

    test('负宽度/负缓存上限被归零，-1 仅 remoteCoverWidth 合法', () async {
      final svc = MediaPrefsService();
      await svc.init();

      await svc.setRemoteCoverWidth(-7); // 非 followLocal 的负数 → 0（原图）
      expect(svc.remoteCoverWidth.value, 0);
      await svc.setRemoteImageWidth(-1);
      expect(svc.remoteImageWidth.value, 0);
      await svc.setLocalPreviewWidth(-100);
      expect(svc.localPreviewWidth.value, 0);
      await svc.setCacheLimitBytes(-3);
      expect(svc.cacheLimitBytes.value, 0); // 0 = 不限制
    });

    test('init() 读回越界值时同样钳制', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'media_thumb_quality': 999,
        'media_thumb_concurrency': 0,
        'media_privacy_blur_sigma': 100.0,
      });
      final svc = MediaPrefsService();
      await svc.init();
      expect(svc.quality.value, 5);
      expect(svc.concurrency.value, 1);
      expect(svc.privacyBlurSigma.value, 40.0);
    });
  });

  // ── 损坏/非法 prefs 值：当前代码的真实降级行为 ────────────────────────────

  group('MediaPrefsService 非法存储值降级', () {
    test('类型错位（String 存进 int key）当前会抛 TypeError —— 如实记录已知缺口', () async {
      // 注：SharedPreferencesLegacy.getInt 内部是 `map[key] as int?` 硬转型，
      // MediaPrefsService.init() 未做 try/catch 逐键降级，因此类型错位目前会直接抛出
      // （bool 存进 int key、int 存进 double key 同理）。因约束禁止修改 lib/，
      // 此测试如实记录现状而非期望行为；若未来 init 增加逐键容错，此断言需同步更新。
      SharedPreferences.setMockInitialValues(<String, Object>{
        'media_thumb_quality': 'abc',
      });
      final svc = MediaPrefsService();
      expect(() => svc.init(), throwsA(isA<TypeError>()));
    });

    test('同类型但越界的非法值 → init 钳制降级（不抛）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'media_thumb_quality': -42, // 合法 int，越界
      });
      final svc = MediaPrefsService();
      await svc.init();
      expect(svc.quality.value, 1); // 被 clamp 到 [1,5] 下界
    });

    test('fileCheckDepth 未知枚举名 → coverOnly', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'media_file_check_depth': 'no_such_depth',
      });
      final svc = MediaPrefsService();
      await svc.init();
      expect(svc.fileCheckDepth.value, FileCheckDepth.coverOnly);
    });
  });

  // ── effectiveRemoteCoverWidth：-1（随本地）时跟随 localPreviewWidth ──────

  group('effectiveRemoteCoverWidth 跟随行为', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('固定档位时不跟随本地', () async {
      final svc = MediaPrefsService();
      await svc.init();
      expect(svc.effectiveRemoteCoverWidth, 240);
      await svc.setLocalPreviewWidth(1080);
      expect(svc.effectiveRemoteCoverWidth, 240); // remoteCoverWidth 仍是 240
    });

    test('followLocalWidth 时严格跟随 localPreviewWidth（含原图 0）', () async {
      final svc = MediaPrefsService();
      await svc.init();
      await svc.setRemoteCoverWidth(MediaPrefsService.followLocalWidth);
      expect(svc.effectiveRemoteCoverWidth, 480); // 默认本地位宽 480

      await svc.setLocalPreviewWidth(720);
      expect(svc.effectiveRemoteCoverWidth, 720);

      await svc.setLocalPreviewWidth(0); // 本地原图 → 远程也原图
      expect(svc.effectiveRemoteCoverWidth, 0);

      expect(svc.remoteCoverWidth.value, MediaPrefsService.followLocalWidth); // 档位本身不被改写
    });
  });

  // ── 缓存统计/裁剪（用假 PathProviderPlatform 指向临时目录） ───────────────

  group('calcCacheSizeBytes / trimCacheToLimit（假 PathProvider）', () {
    late Directory tempRoot;
    late PathProviderPlatform previousPlatform;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      previousPlatform = PathProviderPlatform.instance;
      tempRoot = await Directory.systemTemp.createTemp('sw_media_prefs_test');
      PathProviderPlatform.instance = _FakeAppDirPathProvider(tempRoot.path);
    });

    tearDown(() async {
      PathProviderPlatform.instance = previousPlatform;
      if (tempRoot.existsSync()) {
        await tempRoot.delete(recursive: true);
      }
    });

    /// 在缓存目录写入指定大小/修改时间的文件。
    Future<File> writeCacheFile(
      String relativeDir,
      String name,
      int size,
      DateTime modified,
    ) async {
      final dir = Directory('${tempRoot.path}/$relativeDir');
      await dir.create(recursive: true);
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(List<int>.filled(size, 7));
      file.setLastModifiedSync(modified);
      return file;
    }

    Future<int> countFilesIn(String relativeDir) async {
      final dir = Directory('${tempRoot.path}/$relativeDir');
      if (!dir.existsSync()) return 0;
      return dir.listSync().whereType<File>().length;
    }

    test('getCacheDirs 返回新结构与旧兼容路径', () async {
      final svc = MediaPrefsService();
      final dirs = await svc.getCacheDirs();
      expect(dirs.length, 4);
      final paths = dirs.map((d) => d.path).toList();
      expect(
        paths.any((p) => p.endsWith('library${Platform.pathSeparator}media${Platform.pathSeparator}thumbnails')),
        isTrue,
      );
      expect(
        paths.any((p) => p.endsWith('library${Platform.pathSeparator}media${Platform.pathSeparator}covers')),
        isTrue,
      );
      expect(paths.any((p) => p.endsWith('thumbnails')), isTrue); // 旧路径
      expect(paths.any((p) => p.endsWith('cover_thumb_cache')), isTrue); // 旧路径
    });

    test('calcCacheSizeBytes 统计新旧目录下全部文件字节', () async {
      final now = DateTime.now();
      await writeCacheFile('library/media/thumbnails', 'a.bin', 100, now);
      await writeCacheFile('library/media/covers', 'b.bin', 230, now);
      await writeCacheFile('thumbnails', 'legacy.bin', 50, now); // 旧路径也计入

      final svc = MediaPrefsService();
      expect(await svc.calcCacheSizeBytes(), 380);
    });

    test('目录不存在时 calcCacheSizeBytes 返回 0', () async {
      final svc = MediaPrefsService();
      expect(await svc.calcCacheSizeBytes(), 0);
    });

    test('trimCacheToLimit 超限后按最旧优先删除到 50% 目标', () async {
      final now = DateTime.now();
      // 总大小 320 > 上限 300 → 删到 50% 目标（150）：按修改时间升序删除
      final oldest = await writeCacheFile('library/media/thumbnails', 'old.bin', 100, now.subtract(const Duration(minutes: 10)));
      final middle = await writeCacheFile('library/media/thumbnails', 'mid.bin', 80, now.subtract(const Duration(minutes: 5)));
      final newest = await writeCacheFile('library/media/thumbnails', 'new.bin', 140, now);

      final svc = MediaPrefsService();
      await svc.init();
      await svc.setCacheLimitBytes(300);
      await svc.trimCacheToLimit();

      expect(oldest.existsSync(), isFalse); // 删 100 后剩 220 > 150，继续
      expect(middle.existsSync(), isFalse); // 再删 80 后剩 140 <= 150，停止
      expect(newest.existsSync(), isTrue); // 最新文件最后被动
      expect(await svc.calcCacheSizeBytes(), 140);
    });

    test('未超上限时 trimCacheToLimit 不删除任何文件', () async {
      final now = DateTime.now();
      final keep = await writeCacheFile('library/media/covers', 'keep.bin', 100, now);

      final svc = MediaPrefsService();
      await svc.init();
      await svc.setCacheLimitBytes(1000);
      await svc.trimCacheToLimit();
      expect(keep.existsSync(), isTrue);
    });

    test('cacheLimitBytes=0（无限制）时 trimCacheToLimit 直接跳过', () async {
      final now = DateTime.now();
      final keep = await writeCacheFile('library/media/covers', 'keep.bin', 100, now);

      final svc = MediaPrefsService();
      await svc.init();
      await svc.setCacheLimitBytes(0);
      await svc.trimCacheToLimit();
      expect(keep.existsSync(), isTrue);
    });

    test('clearCache 删除所有缓存目录内容且不抛', () async {
      await writeCacheFile('library/media/thumbnails', 'x.bin', 10, DateTime.now());
      expect(await countFilesIn('library/media/thumbnails'), 1);

      final svc = MediaPrefsService();
      await svc.clearCache();
      expect(Directory('${tempRoot.path}/library/media/thumbnails').existsSync(), isFalse);
    });
  });

  test('PathProvider 不可用时 calcCacheSizeBytes 降级返回 0 不抛', () async {
    // 不设置假平台：方法通道在测试环境会抛 MissingPluginException，服务应捕获并返回 0。
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final svc = MediaPrefsService();
    expect(await svc.calcCacheSizeBytes(), 0);
  });
}
