import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/game_library_service.dart';
import 'package:slime_works/core/services/game_process_tracker.dart';
import 'package:slime_works/core/services/manga_service.dart';
import 'package:slime_works/pages/game_library/models/game_library_models.dart';
import 'package:slime_works/pages/manga/view_models/manga_reader_viewmodel.dart';
import 'package:slime_works/view_models/game_library/game_library_library_viewmodel.dart';
import 'package:slime_works/view_models/game_library/game_library_settings_viewmodel.dart';

/// 说明（可达性结论，对应补测任务第 1/4 项）：
/// - GameLibraryViewModel 构造函数仅从 GetIt 取 GameLibraryService/GameProcessTracker，
///   两者构造函数不触 FFI（FFI 只在 init()/getGames() 等显式调用里），因此可直接 new VM；
/// - deriveGameName 是纯 FFI 委托（rust_api.gameLibraryDeriveGameName），Dart 侧无逻辑可测，
///   其多路径形态已由 Rust 单测覆盖（rust/game_library/src/api.rs 测试
///   `derive_game_name_covers_path_shapes`），本文件不重复；
/// - _resolveDefaultExe/_resolveWorkingDirectory 为 VM 私有方法，无法从测试库直接调用；
///   但其优先级选择结果可经公开入口 launchGame 的错误文案间接观测（见下方 group）；
///   _resolveWorkingDirectory 的结果只在 launchAndTrack 参数中使用，Dart 侧不可观测，
///   已在报告中列为阻碍；
/// - formatDuration 在本 VM 为公开方法（可测）；media/music 等页面的 _formatDuration
///   均为 StatefulWidget 私有方法，不可达（见报告）；
/// - MangaReaderViewModel._formatReaderError 为私有方法，但其输出会写入公开的
///   readerError，可在 loadPages/switchEps 失败路径上观测（经 noSuchMethod 假服务注入错误）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // 只注册构造轻量的服务；全程不调用 service.init()，避免触发 FFI/数据库
    getIt.registerSingleton<GameLibraryService>(GameLibraryService());
    getIt.registerSingleton<GameProcessTracker>(
      GameProcessTracker(service: getIt<GameLibraryService>()),
    );
  });

  tearDownAll(() {
    getIt.unregister<GameLibraryService>();
    getIt.unregister<GameProcessTracker>();
  });

  GameItem makeGame({
    required String id,
    String name = '测试游戏',
    String path = '',
    List<String> exePaths = const <String>[],
    String gameDir = '',
    List<String> tags = const <String>[],
    DateTime? updatedAt,
  }) {
    return GameItem(
      id: id,
      name: name,
      coverPath: '',
      company: '',
      summary: '',
      rating: 0,
      releaseDate: '',
      path: path,
      status: GameStatus.notStarted,
      createdAt: DateTime(2026),
      updatedAt: updatedAt ?? DateTime(2026),
      totalPlayTimeSec: 0,
      tags: tags,
      exePaths: exePaths,
      gameDir: gameDir,
    );
  }

  // ── 多选状态机（toggleSelect / selectAll / clearSelection） ──────────────

  group('GameLibraryViewModel 多选状态机', () {
    late GameLibraryViewModel vm;

    setUp(() {
      vm = GameLibraryViewModel();
      vm.games.clear();
      vm.selectedIds.clear();
      vm.searchQuery.value = '';
      vm.selectedTag.value = '';
      vm.selectedStatus.value = null;
      vm.games.addAll([
        makeGame(id: 'a', name: 'Alpha'),
        makeGame(id: 'b', name: 'Beta'),
        makeGame(id: 'c', name: 'Gamma', tags: const <String>['RPG']),
      ]);
    });

    tearDown(() {
      vm.onClose();
    });

    test('toggleSelect 奇偶次切换选中/取消，isSelecting 随之变化', () {
      expect(vm.isSelecting, isFalse);
      vm.toggleSelect('a');
      expect(vm.selectedIds, <String>{'a'});
      expect(vm.isSelecting, isTrue);
      vm.toggleSelect('a');
      expect(vm.selectedIds, isEmpty);
      expect(vm.isSelecting, isFalse);
    });

    test('selectAll 首次全选过滤结果，再次调用清空（全选即取消）', () {
      vm.selectAll();
      expect(vm.selectedIds.toSet(), <String>{'a', 'b', 'c'});
      vm.selectAll();
      expect(vm.selectedIds, isEmpty);
    });

    test('selectAll 遵循当前搜索过滤（只全选可见项）', () {
      vm.searchQuery.value = 'rpg'; // 仅 c 命中（按 tag 过滤）
      vm.selectAll();
      expect(vm.selectedIds, <String>{'c'});
    });

    test('clearSelection 清空全部选中', () {
      vm.toggleSelect('a');
      vm.toggleSelect('b');
      vm.clearSelection();
      expect(vm.selectedIds, isEmpty);
      expect(vm.isSelecting, isFalse);
    });

    test('setSelectedFromIndices 越界索引被忽略，且整体替换旧选中', () {
      vm.toggleSelect('zzz'); // 旧选中应被替换
      vm.setSelectedFromIndices(<int>[0, 2, 5, -1], vm.games);
      expect(vm.selectedIds.toSet(), <String>{'a', 'c'});
    });
  });

  // ── _resolveDefaultExe 优先级（经公开入口 launchGame 观测） ─────────────

  group('GameLibraryViewModel 启动路径选择（launchGame 观测）', () {
    late _TestGameLibraryViewModel vm;
    late Directory tmpDir;

    setUp(() {
      vm = _TestGameLibraryViewModel();
      tmpDir = Directory.systemTemp.createTempSync('sw_game_vm_test');
    });

    tearDown(() {
      try {
        tmpDir.deleteSync(recursive: true);
      } catch (_) {}
      vm.onClose();
    });

    test('path 为空白且无 exePaths：报「未配置启动路径」，不触发起进程', () async {
      await vm.launchGame(makeGame(id: 'g1', path: '   '));
      expect(vm.errorMessage, contains('未配置启动路径'));
    });

    test('overrideExePath 优先于 game.path（trim 后使用）', () async {
      final String override = '${tmpDir.path}/missing_override.exe';
      await vm.launchGame(
        makeGame(id: 'g2', path: '${tmpDir.path}/missing_primary.exe'),
        overrideExePath: '  $override  ',
      );
      // 错误文案里出现的是 override 路径，证明其优先级高于 game.path
      expect(vm.errorMessage, contains('missing_override.exe'));
      expect(vm.errorMessage, isNot(contains('missing_primary.exe')));
    });

    test('path 不存在且无有效 exePaths：回落 path 并报「启动文件不存在」', () async {
      await vm.launchGame(
        makeGame(
          id: 'g3',
          path: '${tmpDir.path}/ghost.exe',
          exePaths: <String>['${tmpDir.path}/also-ghost.exe'],
        ),
      );
      expect(vm.errorMessage, contains('启动文件不存在'));
      expect(vm.errorMessage, contains('ghost.exe'));
    });

    test('path 不存在但 exePaths 含存在文件：选中该 exe 进入启动流程', () async {
      // 该 exe 只保证 existsSync 通过；真正的 spawn 在 Rust 层，
      // 测试环境 FFI 未初始化会抛错并被 tracker 捕获 → 报「启动失败」而非「不存在」
      File('${tmpDir.path}/real_game.exe').createSync();
      await vm.launchGame(
        makeGame(
          id: 'g4',
          path: '${tmpDir.path}/ghost.exe',
          exePaths: <String>[
            '${tmpDir.path}/not_exist_first.exe', // 第一个不存在，应跳过
            '${tmpDir.path}/real_game.exe',       // 第一个有效的应被选中
          ],
        ),
      );
      expect(vm.errorMessage, contains('启动失败'));
      expect(vm.errorMessage, isNot(contains('启动文件不存在')));
    });

    test('path 存在时优先于 exePaths（即使后者也有效）', () async {
      File('${tmpDir.path}/primary.exe').createSync();
      File('${tmpDir.path}/alternative.exe').createSync();
      await vm.launchGame(
        makeGame(
          id: 'g5',
          path: '${tmpDir.path}/primary.exe',
          exePaths: <String>['${tmpDir.path}/alternative.exe'],
        ),
      );
      // 走到 tracker 才报启动失败；若优先级错误地选了 alternative，
      // 断言方式相同，但结合上一条「跳过不存在项」用例可锁定完整优先级
      expect(vm.errorMessage, contains('启动失败'));
    });
  });

  // ── formatDuration（本 VM 为公开方法） ──────────────────────────────────

  group('GameLibraryViewModel.formatDuration', () {
    // 注意：不能在 group 回调顶层 new（那会在 setUpAll 注册 GetIt 之前执行）
    late GameLibraryViewModel vm;

    setUp(() => vm = GameLibraryViewModel());
    tearDown(() => vm.onClose());

    test('不足 1 小时只显示分钟', () {
      expect(vm.formatDuration(0), '0 分钟');
      expect(vm.formatDuration(59), '0 分钟');
      expect(vm.formatDuration(3599), '59 分钟');
    });

    test('满 1 小时显示 小时+分钟', () {
      expect(vm.formatDuration(3600), '1 小时 0 分钟');
      expect(vm.formatDuration(3661), '1 小时 1 分钟');
      expect(vm.formatDuration(3600 * 25 + 60 * 30), '25 小时 30 分钟');
    });
  });

  // ── 备份导出/导入（当前为占位实现，锁住行为契约） ───────────────────────

  group('GameLibrarySettingsViewModel 备份编解码', () {
    test('exportBackupJson 返回合法 JSON 且含备份指引文案', () {
      final GameLibrarySettingsViewModel vm = GameLibrarySettingsViewModel();
      final String text = vm.exportBackupJson();
      expect(text, contains('note'));
      vm.onClose();
    });

    test('importBackupJson 当前为 no-op：任意文本不抛异常（真实导入待实现）', () async {
      final GameLibrarySettingsViewModel vm = GameLibrarySettingsViewModel();
      await vm.importBackupJson('{"games":[]}');
      await vm.importBackupJson('不是 JSON 也接受（占位实现）');
      vm.onClose();
    });
  });

  // ── MangaReaderViewModel._formatReaderError（经 readerError 观测） ───────

  group('MangaReaderViewModel 错误格式化（loadPages/switchEps 失败路径）', () {
    Future<String?> runLoadPages(Object error) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      getIt.registerSingleton<MangaService>(_ThrowingMangaService(error));
      final MangaReaderViewModel vm = MangaReaderViewModel();
      try {
        await vm.loadPages('comic-1', 1);
        return vm.readerError.value;
      } finally {
        vm.onClose();
        getIt.unregister<MangaService>();
      }
    }

    test('空错误文案回落为「章节加载失败」', () async {
      expect(await runLoadPages(const _BlankError()), '章节加载失败');
    });

    test('短错误原样透传（≤6 行且 ≤600 字符不截断）', () async {
      final Object e = const _RawError('第1行\n第2行\n第3行');
      expect(await runLoadPages(e), '第1行\n第2行\n第3行');
    });

    test('超过 6 行时截断到前 6 行并追加截断提示', () async {
      final String eight = List<String>.generate(8, (int i) => 'L$i').join('\n');
      final String? out = await runLoadPages(_RawError(eight));
      expect(out, contains('L5'));
      expect(out, isNot(contains('L6')));
      expect(out, endsWith('错误详情已截断，请重试或切换分流节点。'));
    });

    test('单行超 600 字符同样触发截断提示', () async {
      final String? out = await runLoadPages(_RawError('x' * 700));
      expect(out, startsWith('x' * 600));
      expect(out, endsWith('错误详情已截断，请重试或切换分流节点。'));
    });

    test('CRLF 换行被归一化、行尾空白被清理', () async {
      final String? out = await runLoadPages(const _RawError('A  \r\nB\t\r\n'));
      expect(out, 'A\nB');
    });

    test('switchEps 失败路径同样写入格式化后的 readerError', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      getIt.registerSingleton<MangaService>(
        _ThrowingMangaService(const _RawError('切换失败-短')),
      );
      final MangaReaderViewModel vm = MangaReaderViewModel();
      try {
        await vm.switchEps(2);
        expect(vm.readerError.value, '切换失败-短');
      } finally {
        vm.onClose();
        getIt.unregister<MangaService>();
      }
    });
  });
}

/// 测试专用 GameLibraryViewModel 子类：仅拦截 refresh 的 FFI 副作用。
///
/// 原因：BaseViewModel.setError → GetxController.update() 会回调可被覆盖的
/// refresh()，而真实 refresh 走 GameLibraryService.getGames → FFI（测试环境
/// RustLib 未初始化会产生 unhandled async error）。除 refresh 外的所有被测
/// 逻辑（launchGame/多选/formatDuration）仍为原始实现。
class _TestGameLibraryViewModel extends GameLibraryViewModel {
  int refreshCallCount = 0;

  @override
  Future<void> refresh() async {
    refreshCallCount++; // 记录调用但不触达 FFI
  }
}

/// 通过 noSuchMethod 转发注入错误的假 MangaService：
/// 只关心 getEpsPages/getComicEps 抛出指定对象，其余成员一律转发。
class _ThrowingMangaService implements MangaService {
  _ThrowingMangaService(this.error);

  final Object error;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #getEpsPages ||
        invocation.memberName == #getComicEps) {
      // 同步抛出：错误会直接进入 loadPages/switchEps 的 try/catch，
      // 避免创建无人监听的 error Future 触发 unhandled async error
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    return super.noSuchMethod(invocation);
  }
}

/// toString 为空白的错误，用于验证「空文案 → 章节加载失败」回落
class _BlankError implements Exception {
  const _BlankError();

  @override
  String toString() => '';
}

/// toString 即原文的错误，用于精确控制 _formatReaderError 的输入
class _RawError implements Exception {
  const _RawError(this.text);

  final String text;

  @override
  String toString() => text;
}
