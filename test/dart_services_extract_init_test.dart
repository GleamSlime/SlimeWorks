// P1-3 回归：解压密码表必须真的被初始化。
//
// 生产注册是 GetIt.registerLazySingleton<ExtractService>()，而它**不会**触发
// GetxService.onInit——旧实现把 extractInitPasswordTable 只放在 onInit 里，
// 于是密码表从未绑定：列表恒空、addPassword 写进未初始化的库后读不回来。
//
// 这里用 FRB 官方注入点 RustLib.initMock 桩掉整条 FFI 链，并让桩**模拟真实
// Rust 侧语义**：没有 init 过就写/读都抛错（旧实现下 addPassword 之所以"假成功"
// 正是因为它把异常吞掉了）。这样就能断言「新实例 addPassword 后，另一个新实例
// （模拟重启）仍能读回密码」。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/core/services/extract_service.dart';
import 'package:slime_works/src/rust/frb_generated.dart';

/// 假的 documents 目录（密码表 db 路径由它拼出来）。
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.rootPath);

  final String rootPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => rootPath;
}

class _Call {
  _Call(this.method);

  final String method;
}

/// FRB 桩：把「密码表」放在内存里，并强制「必须先 init」的真实约束。
class _MockExtractApi implements RustLibApi {
  final List<_Call> calls = <_Call>[];

  /// 模拟 Rust 侧持久化的密码表（跨实例共享 = 模拟"重启后同一份存储"）
  static List<Map<String, dynamic>> table = <Map<String, dynamic>>[];
  static bool tableBound = false;

  static void reset() {
    table = <Map<String, dynamic>>[];
    tableBound = false;
  }

  int callCount(String method) => calls.where((c) => c.method == method).length;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = _symbolName(invocation.memberName);
    calls.add(_Call(name));
    switch (name) {
      case 'crateApiExtractExtractInitPasswordTable':
        return _init(invocation.namedArguments);
      case 'crateApiExtractExtractListPasswordsJson':
        _requireBound();
        return jsonEncode(table);
      case 'crateApiExtractExtractAddPassword':
        _requireBound();
        return _add(invocation.namedArguments);
      case 'crateApiExtractExtractRemovePassword':
        _requireBound();
        return _remove(invocation.namedArguments);
      case 'crateApiExtractExtractUpdatePasswordRemark':
        _requireBound();
        return true;
      case 'crateApiExtractExtractFormatFileSize':
        return '0 B';
    }
    throw StateError('mock 未配置该 FFI: $name');
  }

  void _requireBound() {
    if (!tableBound) {
      // 真实 Rust 侧未 init 就调用会报错——正是旧实现下密码丢失的根因
      throw StateError('密码表未初始化');
    }
  }

  dynamic _init(Map<Symbol, Object?> args) {
    tableBound = true;
    return null;
  }

  String _add(Map<Symbol, Object?> args) {
    final password = args[Symbol('password')] as String? ?? '';
    final remark = args[Symbol('remark')] as String?;
    final entry = <String, dynamic>{
      'id': 'pw-${table.length + 1}',
      'password': password,
      'remark': remark,
      'created_at': 1700000000000,
    };
    table = <Map<String, dynamic>>[...table, entry];
    return jsonEncode(entry);
  }

  bool _remove(Map<Symbol, Object?> args) {
    final id = args[Symbol('id')] as String? ?? '';
    final before = table.length;
    table = table.where((e) => e['id'] != id).toList();
    return table.length != before;
  }
}

String _symbolName(Symbol symbol) {
  final text = symbol.toString();
  final match = RegExp(r'Symbol\("(.+?)"\)').firstMatch(text);
  return match?.group(1) ?? text;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mock = _MockExtractApi();
  late PathProviderPlatform previousProvider;

  setUpAll(() {
    RustLib.initMock(api: mock);
  });

  setUp(() {
    mock.calls.clear();
    _MockExtractApi.reset();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    previousProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider('/tmp/sw_extract_test');
  });

  tearDown(() {
    PathProviderPlatform.instance = previousProvider;
  });

  group('密码表初始化（P1-3）', () {
    test('新实例 addPassword 会先初始化密码表', () async {
      final svc = ExtractService();
      await svc.addPassword('s3cret', remark: '测试');

      expect(
        mock.callCount('crateApiExtractExtractInitPasswordTable'),
        1,
        reason: 'addPassword 入口必须先过 _ensureInit',
      );
      expect(svc.passwords.map((e) => e.password), contains('s3cret'));
    });

    test('模拟重启：另一个新实例仍能读回已写入的密码', () async {
      final first = ExtractService();
      await first.addPassword('持久密码');
      expect(first.passwords.length, 1);

      // 新实例 = 模拟进程重启（同一份 Rust 侧存储）
      final second = ExtractService();
      // 触发任意入口的初始化 + 读回
      await second.updatePasswordRemark('nope', 'noop');

      expect(second.passwords.length, 1);
      expect(second.passwords.first.password, '持久密码');
    });

    test('注册方式不变（lazySingleton 不触发 onInit）也能工作', () async {
      // 关键：**不调用 onInit**，只直接调公开方法
      final svc = ExtractService();
      await svc.addPassword('a');
      await svc.addPassword('b');

      expect(svc.passwords.length, 2);
      expect(
        mock.callCount('crateApiExtractExtractInitPasswordTable'),
        1,
        reason: '同实例多次调用只初始化一次',
      );
    });

    test('并发调用只初始化一次', () async {
      final svc = ExtractService();

      // 5 个入口同时进来：第一个在 await 拿目录时，其余 4 个必须复用同一份
      // Completer 等待，而不是各自再初始化一遍（各自初始化会让密码表被重复
      // 绑定/重复读，且写入口在未绑定窗口里丢数据）
      await Future.wait(<Future<void>>[
        svc.addPassword('p1'),
        svc.removePassword('nope'),
        svc.updatePasswordRemark('x', 'y'),
        svc.ensurePasswordExists('p2'),
        svc.addPassword('p3'),
      ]);

      expect(svc.passwords, isNotEmpty);

      expect(
        mock.callCount('crateApiExtractExtractInitPasswordTable'),
        1,
        reason: '并发入口必须共用同一份 Completer，不能各初始化一次',
      );
    });

    test('ensurePasswordExists 会先初始化再比对（避免重复写入）', () async {
      final svc = ExtractService();
      await svc.addPassword('dup');

      final added = await svc.ensurePasswordExists('dup');
      expect(added, isFalse, reason: '已存在就不该再写一遍');
      expect(svc.passwords.length, 1);
    });

    test('初始化失败可重试：表恢复后下次调用仍能读到数据', () async {
      // 让 documents 目录拿不到 → _initPasswordTable 抛错 → 守卫放开
      PathProviderPlatform.instance = _FailingPathProvider();
      final svc = ExtractService();
      await svc.addPassword('lost');
      expect(svc.passwords, isEmpty);

      // 路径恢复后重试应成功（_initDone 未被钉死）
      PathProviderPlatform.instance = _FakePathProvider('/tmp/sw_extract_test');
      await svc.addPassword('recovered');
      expect(svc.passwords.map((e) => e.password), contains('recovered'));
    });
  });
}

class _FailingPathProvider extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    throw StateError('documents 目录不可用');
  }
}
