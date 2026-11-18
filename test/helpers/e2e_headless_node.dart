// 真端到端测试的公共夹具：**真的**起一个 `slime_node` 无头进程，走**真的** HTTP。
//
// 为什么不用 test/helpers/fake_node_server.dart：
//   那个假节点只能证明「客户端发出了什么请求」，证明不了「节点上数据真的变了」。
//   本次要回归的 bug 恰恰是「节点回了 success:true 但什么都没做」——这种缺陷
//   只有对着真节点的真数据库才暴露得出来。
//
// 三个硬性前提（踩过，别改）：
//   1. 二进制用仓库里 cargo 编出来的 `rust/target/debug/slime_node`（arm64 原生，
//      直接跑即可）。测试不负责编译它：缺了就在报告里明确说要先 cargo build。
//   2. `--data-dir` 必须指到测试自己的临时目录。节点进程会把这个目录写进 HOME
//      （见 rust/src/bin/slime_node.rs 的 apply_data_dir_env），所以所有业务模块
//      的数据库都落在临时目录里，绝不碰 `~/Library/Application Support/SlimeWorks`
//      那个 217MB 的真实 media.db。
//   3. 端口必须自己挑且避开 Lead 常驻的 17901。
//
// 跑法见 test/e2e_headless_node_contract_test.dart 头部注释。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';

/// 仓库根目录：测试进程的 cwd 恒为仓库根（flutter test 的约定），
/// 但用 `Directory.current` 显式算一遍，便于报错时打印绝对路径。
String get repoRoot => Directory.current.path;

/// 无头节点可执行文件（arm64 原生构建；x86_64 dylib 是给 Flutter 侧用的，两者不通用）。
///
/// 允许用 `SLIME_E2E_NODE_BIN` 覆盖：这是「用同一份测试跑修复前二进制」的开关，
/// 拿它去 git worktree 编一个基线版本的 slime_node，就能证明这批断言在修复前是红的。
String get slimeNodeBinary =>
    Platform.environment['SLIME_E2E_NODE_BIN']?.trim().isNotEmpty == true
        ? Platform.environment['SLIME_E2E_NODE_BIN']!.trim()
        : '$repoRoot/rust/target/debug/slime_node';

/// Flutter 侧要加载的 Rust 动态库。
///
/// 必须显式指定这一条 x86_64 路径：`/private/tmp/fl/flutter`（3.50.0）的引擎产物
/// 只有 x86_64（Mac 上走 Rosetta），而 `RustLib.init()` 默认去 `rust/target/release/`
/// 捞 arm64 的同名库，符号能对上、架构对不上，初始化必失败。
String get rustDylibPath =>
    '$repoRoot/rust/target/x86_64-apple-darwin/debug/librust_lib_slime_works.dylib';

/// 是否在隔离环境里跑。
///
/// 只在 `SLIME_E2E_HOME` 存在且指向一个真实目录时返回该目录，否则返回 null，
/// 调用方据此跳过整组用例——**这是数据安全闸门**：未隔离 HOME 直接跑会把
/// 用例数据写进开发者真实媒体库（已经发生过去一次，那次碰的是 217MB 的 media.db）。
String? get e2eIsolatedHome {
  final value = Platform.environment['SLIME_E2E_HOME'];
  if (value == null || value.trim().isEmpty) return null;
  final dir = Directory(value);
  if (!dir.existsSync()) return null;
  return dir.absolute.path;
}

/// 未隔离时的跳过原因（打印出来比一句 skip 有用得多）。
const String kNeedIsolatedHomeHint = '''
缺少 SLIME_E2E_HOME，已跳过真端到端用例（这是保护你真实媒体库的闸门）。
正确跑法（HOME 必须隔离到临时目录）：

  HOME=/tmp/sw_e2e_home SLIME_E2E_HOME=/tmp/sw_e2e_home \\
    /private/tmp/fl/flutter/bin/flutter test test/e2e_*.dart --no-pub
''';

/// 一个真实跑起来的无头节点进程 + 指向它的 HTTP 客户端。
///
/// 生命周期：`start()` 起进程并等到 `/health` 真的应答（不是 sleep 猜），
/// `dispose()` 先 SIGTERM 再兜底 SIGKILL，并清掉临时数据目录。
class RealHeadlessNode {
  RealHeadlessNode._(this._process, this.baseUrl, this.dataDir);

  final Process _process;
  final String baseUrl;

  /// 节点的数据目录（数据库/日志/缩略图都在这里），删掉即完全还原。
  final String dataDir;

  /// 节流：每条 action 的原始请求/响应都记下来，失败时能直接贴进报告。
  final List<String> callLog = <String>[];

  late final Dio _dio = Dio(
    BaseOptions(
      // 节点侧导入/删文件可能跑几秒（要 rescan 目录），给足余量
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 60),
      // 原样拿 JSON，不让 Dio 把 4xx/5xx 抛成异常：节点契约里业务失败也是
      // HTTP 200 + success:false，断言要看 body 而不是状态码
      validateStatus: (_) => true,
    ),
  );

  /// 起一个真实节点：[dataDir] 给了就复用（重启用例），否则新建临时目录。
  ///
  /// 端口随机取 17990~18090 段并避开已被占用的：Lead 的常驻节点在 17901，
  /// 直接复用会污染他正在调试的数据。
  static Future<RealHeadlessNode> start({
    String? dataDir,
    Directory? sandboxRoot,
    Duration readyTimeout = const Duration(seconds: 90),
  }) async {
    final binary = File(slimeNodeBinary);
    if (!binary.existsSync()) {
      throw StateError(
        '找不到无头节点二进制 $slimeNodeBinary\n'
        '请先构建（arm64 原生）：cd rust && cargo build --bin slime_node',
      );
    }

    final dir = dataDir ?? _newDataDir(sandboxRoot);
    final port = await _pickFreePort();
    final process = await Process.start(
      slimeNodeBinary,
      <String>[
        '--host', '127.0.0.1',
        '--port', '$port',
        '--data-dir', dir,
        '--name', 'E2E 测试节点',
        // 关掉自更新：CI/本机都不该在测试里碰网络去查 GitHub
        '--no-auto-update',
      ],
      workingDirectory: repoRoot,
      // 节点日志走管道收集：启动失败时（端口占用/目录不可写）能直接报出原因，
      // 而不是干等到 readyTimeout 之后只有一句"超时"
      environment: <String, String>{'RUST_BACKTRACE': '1'},
    );

    final node = RealHeadlessNode._(process, 'http://127.0.0.1:$port', dir);
    node._drainOutput();
    try {
      await node._waitUntilHealthy(readyTimeout);
    } catch (_) {
      await node.dispose();
      rethrow;
    }
    return node;
  }

  /// 子进程 stdout/stderr 缓冲（启动失败时用来解释原因）。
  final StringBuffer _output = StringBuffer();
  String get output => _output.toString();

  /// 进程是否已退出。`exitCode` 是个只会完成一次的 Future，
  /// 反复 await 都拿到同一个值，所以这里存成字段反复查是安全的。
  bool _exited = false;

  void _drainOutput() {
    _process.stdout.transform(utf8.decoder).listen(_output.write);
    _process.stderr.transform(utf8.decoder).listen(_output.write);
    // 只挂一个 exitCode 监听器：再 await 一次同一个 Future 拿到的还是这个值
    unawaited(_process.exitCode.then((_) => _exited = true));
  }

  Future<void> _waitUntilHealthy(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    Object? lastError;
    while (DateTime.now().isBefore(deadline)) {
      // 进程已经退出就没必要再等了：直接把它的输出抛出来
      if (_exited) {
        throw StateError('无头节点进程已退出，输出：\n$_output');
      }
      try {
        final resp = await _dio.get<dynamic>('$baseUrl/health');
        if (resp.statusCode == 200 && resp.data is Map && resp.data['success'] == true) {
          return;
        }
      } catch (e) {
        lastError = e;
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    throw StateError('无头节点在 ${timeout.inSeconds}s 内未就绪，输出：\n$_output\n最后错误：$lastError');
  }

  /// 调一次 `/node/call`，返回**原始响应体**（含 success/error/data 三个字段）。
  ///
  /// 刻意不做「失败就抛异常」的包装：本次的核心断言是
  /// 「不存在的 id 必须 success:false」，把异常语义藏进客户端会掩盖这条契约。
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> params = const <String, dynamic>{},
  ]) async {
    final resp = await _dio.post<dynamic>(
      '$baseUrl/node/call',
      data: <String, dynamic>{'action': action, 'params': params},
    );
    final body = resp.data is Map
        ? Map<String, dynamic>.from(resp.data as Map)
        : <String, dynamic>{'raw': resp.data};
    callLog.add('$action(${jsonEncode(params)}) -> ${jsonEncode(body)}');
    return body;
  }

  /// 期望成功的调用：success 不是 true 时直接抛，附上原始响应。
  Future<dynamic> callOk(
    String action, [
    Map<String, dynamic> params = const <String, dynamic>{},
  ]) async {
    final body = await call(action, params);
    if (body['success'] != true) {
      throw StateError('$action 本应成功但失败了：${jsonEncode(body)}');
    }
    return body['data'];
  }

  /// 期望失败的调用：success 为 true（=「假成功」）时抛，这正是本次 bug 的形状。
  Future<String> callFails(
    String action, [
    Map<String, dynamic> params = const <String, dynamic>{},
  ]) async {
    final body = await call(action, params);
    if (body['success'] == true) {
      throw StateError(
        '★假成功★ $action 对不存在的目标回了 success:true（本次回归的核心缺陷）：'
        'params=${jsonEncode(params)} body=${jsonEncode(body)}',
      );
    }
    final error = (body['error'] ?? '').toString();
    if (error.trim().isEmpty) {
      throw StateError('$action 回了 success:false 但没有 error 文案：${jsonEncode(body)}');
    }
    return error;
  }

  // ── 常用查询（测试里反复用，收在这里避免重复拼 action 名） ────────────────

  Future<List<Map<String, dynamic>>> listFolders() async =>
      _asMapList(await callOk('list_media_folders'));

  Future<List<Map<String, dynamic>>> listCollections() async =>
      _asMapList(await callOk('list_media_collections'));

  Future<List<Map<String, dynamic>>> listItems(String collectionId) async =>
      _asMapList(await callOk('get_media_collection_items', <String, dynamic>{
        'collection_id': collectionId,
      }));

  static List<Map<String, dynamic>> _asMapList(dynamic data) {
    if (data is! List) return const <Map<String, dynamic>>[];
    return data.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }

  /// 关节点：先给 5 秒让 tokio 线程自己退（SIGTERM 实际走不到，节点没装信号处理器），
  /// 超时直接 SIGKILL，最后删数据目录。
  Future<void> dispose({bool keepData = false}) async {
    _dio.close(force: true);
    _process.kill(ProcessSignal.sigterm);
    final exited = await _process.exitCode
        .timeout(const Duration(seconds: 5), onTimeout: () => -1);
    if (exited == -1) {
      _process.kill(ProcessSignal.sigkill);
      await _process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () => -1,
      );
    }
    if (!keepData) {
      try {
        final dir = Directory(dataDir);
        if (dir.existsSync()) await dir.delete(recursive: true);
      } catch (_) {
        // 临时目录清不掉不影响用例结论（系统会自己回收 /tmp）
      }
    }
  }

  // ── 内部工具 ──────────────────────────────────────────────────────────────

  static Directory _newSandboxBase(Directory? sandboxRoot) {
    final base = sandboxRoot ?? Directory.systemTemp;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return Directory('${base.path}/slime_e2e_node_$stamp')..createSync(recursive: true);
  }

  static String _newDataDir(Directory? sandboxRoot) {
    final dir = Directory('${_newSandboxBase(sandboxRoot).path}/data')
      ..createSync(recursive: true);
    return dir.path;
  }

  /// 在 17990~18100 里随机挑一个**真能 bind 上**的端口。
  ///
  /// 不用 0（系统分配）是因为节点进程需要提前知道端口；不用固定端口是因为
  /// 并行跑测试/Lead 同时在调试时必然撞车。
  static Future<int> _pickFreePort() async {
    final rnd = Random.secure();
    for (var attempt = 0; attempt < 60; attempt++) {
      final port = 17990 + rnd.nextInt(110);
      ServerSocket? socket;
      try {
        socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
        await socket.close();
        return port;
      } catch (_) {
        await socket?.close();
      }
    }
    throw StateError('17990~18100 没有可用端口');
  }
}

/// 造一个能被媒体库导入的最小音频样本目录。
///
/// 用 wav 而不是图片/视频：节点导入 wav 只读文件头，不依赖 ffmpeg 抽帧，
/// 在只有 CLT 的本机上最稳、也最快（整组用例秒级）。
Directory createAudioSampleDir(
  String parentDir,
  int count, {
  String name = '样本集合',
}) {
  final dir = Directory('$parentDir/$name')..createSync(recursive: true);
  for (var i = 1; i <= count; i++) {
    _writeWav(File('${dir.path}/track_$i.wav'), frequency: 220.0 + i * 55.0);
  }
  return dir;
}

/// 写一个 16bit/8kHz 单声道 wav（约 0.6 秒，10KB 以内）。
void _writeWav(File file, {double frequency = 440.0, int sampleRate = 8000}) {
  final frames = <int>[];
  final total = (sampleRate * 0.6).round();
  for (var i = 0; i < total; i++) {
    final value = (4000 * sin(2 * pi * frequency * i / sampleRate)).round();
    // 小端 16bit
    frames..add(value & 0xFF)..add((value >> 8) & 0xFF);
  }
  final dataSize = frames.length;
  final header = <int>[
    ...ascii.encode('RIFF'),
    ..._le32(36 + dataSize),
    ...ascii.encode('WAVE'),
    ...ascii.encode('fmt '),
    ..._le32(16), // fmt chunk 长度
    ..._le16(1), // PCM
    ..._le16(1), // 单声道
    ..._le32(sampleRate),
    ..._le32(sampleRate * 2), // 字节率
    ..._le16(2), // 块对齐
    ..._le16(16), // 位深
    ...ascii.encode('data'),
    ..._le32(dataSize),
  ];
  file.writeAsBytesSync(<int>[...header, ...frames]);
}

List<int> _le32(int v) => <int>[v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];
List<int> _le16(int v) => <int>[v & 0xFF, (v >> 8) & 0xFF];

/// 递归列出目录下所有文件（用于断言「磁盘文件真的没了」）。
List<String> listFilesRecursive(String dirPath) {
  final dir = Directory(dirPath);
  if (!dir.existsSync()) return const <String>[];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path)
      .toList(growable: false);
}
