// 真 App 集成测试的公共夹具：**从真 macOS App 进程里**起一个真 `slime_node`。
//
// ═══════════════════════════════════════════════════════════════════════════
// 为什么在 App 进程里起节点，而不是在外面先起好
// ═══════════════════════════════════════════════════════════════════════════
// 1. 生命周期绑定：测试结束/崩溃时子进程由 tearDown 收掉，不会留一堆孤儿
//    节点占着端口和临时目录（上一轮就因此攒出过几个残留实例）。
// 2. 数据目录可以精确地建在「本次测试自己的沙箱」里，和 App 的 HOME 沙箱
//    分开：App 沙箱管客户端数据，节点沙箱管服务端数据，两者互不干扰，
//    这样「客户端的写有没有真的到节点」才能被独立验证。
// 3. 端口可以每条用例自己挑，避开任何人工调试中的实例。
//
// 为什么不用 test/helpers/fake_node_server.dart：假节点只能证明「客户端发了
// 什么 HTTP」，证明不了「节点上数据到底变没变」。用户报的正是「提示成功但
// 数据没变化」——这种缺陷只有对着真节点真数据库才抓得住。
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';

/// 仓库根目录。`flutter test` 的 cwd 恒为仓库根。
String get repoRoot => Directory.current.path;

/// 无头节点可执行文件。
///
/// 默认用仓库里 cargo 编出来的 debug 版（arm64 原生，直接跑）。
/// `SLIME_E2E_NODE_BIN` 可覆盖——那是「同一份测试跑修复前二进制」的开关。
String get slimeNodeBinary {
  final override = Platform.environment['SLIME_E2E_NODE_BIN'];
  if (override != null && override.trim().isNotEmpty) return override.trim();
  return '$repoRoot/rust/target/debug/slime_node';
}

/// 一个真实跑起来的无头节点进程 + 指向它的 HTTP 客户端。
///
/// 关键点：**每一种 action 的原始请求/响应都记进 [callLog]**，
/// 用例失败时可以直接贴进报告，不用回头重跑。
class RealHeadlessNode {
  RealHeadlessNode._(this._process, this.baseUrl, this.dataDir);

  final Process _process;

  /// 形如 `http://127.0.0.1:18123`
  final String baseUrl;

  /// 节点数据目录（数据库/日志/缩略图都在这），删掉即完全还原。
  final String dataDir;

  /// 所有真实调用的流水，断言失败时用来贴证据。
  final List<String> callLog = <String>[];

  late final Dio _dio = Dio(
    BaseOptions(
      // 导入/删文件会触发目录 rescan，给足余量
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 60),
      // 节点契约里「业务失败」也是 HTTP 200 + success:false，
      // 断言要看 body 而不是状态码，所以不能让 Dio 把异常抛出来。
      validateStatus: (_) => true,
    ),
  );

  /// 起一个真实节点，并等到 `/health` 真的应答（不是靠 sleep 猜）。
  ///
  /// [sandboxRoot] 下的 `node_data` 作为节点数据目录。
  static Future<RealHeadlessNode> start({required Directory sandboxRoot}) async {
    final binary = File(slimeNodeBinary);
    if (!binary.existsSync()) {
      throw StateError(
        '找不到无头节点二进制 $slimeNodeBinary\n'
        '先在仓库根执行：cd rust && cargo build --bin slime_node',
      );
    }

    final dataDir = Directory('${sandboxRoot.path}/node_data');
    dataDir.createSync(recursive: true);
    final port = await _pickFreePort();

    final process = await Process.start(
      slimeNodeBinary,
      <String>[
        '--host', '127.0.0.1',
        '--port', '$port',
        '--data-dir', dataDir.path,
        '--name', 'E2E真节点',
        // 授权码留空：本夹具只验证数据语义，不验证鉴权链路
        '--auth', '',
      ],
      // 节点日志不吞掉：测试失败时这些行就是现场证据
      mode: ProcessStartMode.normal,
    );
    // 节点 stdout 转发到一个有上限的环形缓冲，避免长时间跑把内存喂爆
    final nodeLogTail = <String>[];
    void pumpLine(String line) {
      nodeLogTail.add(line);
      if (nodeLogTail.length > 200) nodeLogTail.removeAt(0);
    }

    process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(pumpLine);
    process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(pumpLine);

    final node = RealHeadlessNode._(process, 'http://127.0.0.1:$port', dataDir.path);
    node._nodeLogTail = nodeLogTail;

    // 等 /health 真应答。节点首次起来要初始化各模块数据库，可能几秒。
    //
    // 同时盯着进程退出：节点一启动就崩（端口占用/数据目录不可写）时，
    // 干等到 60s 超时只会得到一句「未就绪」，把真正的报错淹掉。
    var exited = false;
    unawaited(process.exitCode.then((_) => exited = true));
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline)) {
      if (exited) {
        // 进程已退出：直接把节点日志贴出来，比一句超时有用地多
        throw StateError('节点进程启动即退出：\n${nodeLogTail.join('\n')}');
      }
      try {
        final resp = await node._dio.get<dynamic>('${node.baseUrl}/health');
        if (resp.statusCode == 200) {
          return node;
        }
      } catch (_) {
        // 还没起来，继续等
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await node.dispose();
    throw StateError('节点 /health 60s 内未就绪：\n${nodeLogTail.join('\n')}');
  }

  List<String> _nodeLogTail = <String>[];

  /// 节点进程最近日志（失败时贴进报告）。
  String get nodeLog => _nodeLogTail.join('\n');

  /// 调一个节点 action，返回整包响应（不抛异常，由调用方断言 success）。
  ///
  /// 语义：`{"success": true, "data": {...}}` / `{"success": false, "error": "..."}`
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> params = const <String, dynamic>{},
  ]) async {
    final resp = await _dio.post<dynamic>(
      '$baseUrl/node/call',
      data: jsonEncode(<String, dynamic>{'action': action, 'params': params}),
      options: Options(contentType: Headers.jsonContentType),
    );
    final body = resp.data is Map
        ? Map<String, dynamic>.from(resp.data as Map)
        : <String, dynamic>{'raw': resp.data};
    callLog.add(
      '[${DateTime.now().toIso8601String()}] $action ${jsonEncode(params)} '
      '→ ${jsonEncode(body)}',
    );
    return body;
  }

  /// 调 action 并断言成功，返回 `data`。
  Future<dynamic> callOk(
    String action, [
    Map<String, dynamic> params = const <String, dynamic>{},
  ]) async {
    final body = await call(action, params);
    if (body['success'] != true) {
      throw StateError('节点 action "$action" 失败：${body['error']}\n'
          '请求参数：${jsonEncode(params)}');
    }
    return body['data'];
  }

  /// 当前节点上的集合列表（真话来源，用来回查客户端写操作有没有落地）。
  Future<List<Map<String, dynamic>>> listCollections() async {
    final data = await callOk('list_media_collections');
    return _asMapList(data);
  }

  /// 当前节点上的媒体文件夹列表。
  Future<List<Map<String, dynamic>>> listFolders() async {
    final data = await callOk('list_media_folders');
    return _asMapList(data);
  }

  /// 某个集合下的条目列表。
  Future<List<Map<String, dynamic>>> listItems(String collectionId) async {
    final data = await callOk('get_media_collection_items', <String, dynamic>{
      'collection_id': collectionId,
    });
    return _asMapList(data);
  }

  static List<Map<String, dynamic>> _asMapList(dynamic data) {
    if (data is List) {
      return data.whereType<Map>().map(Map<String, dynamic>.from).toList();
    }
    // 有些 action 把列表包在 {items: [...]} / {folders: [...]} 里
    if (data is Map) {
      for (final key in <String>['items', 'folders', 'collections', 'list']) {
        final v = data[key];
        if (v is List) {
          return v.whereType<Map>().map(Map<String, dynamic>.from).toList();
        }
      }
    }
    return const <Map<String, dynamic>>[];
  }

  /// 收尾：先 SIGTERM 让节点正常关库，兜底 SIGKILL，再清数据目录。
  Future<void> dispose() async {
    try {
      _process.kill(ProcessSignal.sigterm);
      await _process.exitCode.timeout(const Duration(seconds: 5));
    } catch (_) {
      try {
        _process.kill(ProcessSignal.sigkill);
      } catch (_) {}
    }
    try {
      final dir = Directory(dataDir);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {}
  }

  /// 挑一个空闲端口：绑 0 让系统分配，再立刻释放。
  static Future<int> _pickFreePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }
}

/// 在 [parentDir] 下建一个装着 [count] 个 wav 的目录，返回该目录。
///
/// 用 wav 是因为音频导入最快（不需要解码视频/生成封面），
/// 且节点侧的扫描、聚合、删除路径与图片完全同一条代码。
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
    frames
      ..add(value & 0xFF)
      ..add((value >> 8) & 0xFF);
  }
  final dataSize = frames.length;
  final header = <int>[
    ...ascii.encode('RIFF'),
    ..._le32(36 + dataSize),
    ...ascii.encode('WAVE'),
    ...ascii.encode('fmt '),
    ..._le32(16),
    ..._le16(1), // PCM
    ..._le16(1), // 单声道
    ..._le32(sampleRate),
    ..._le32(sampleRate * 2),
    ..._le16(2),
    ..._le16(16),
    ...ascii.encode('data'),
    ..._le32(dataSize),
  ];
  file.writeAsBytesSync(<int>[...header, ...frames]);
}

List<int> _le32(int v) =>
    <int>[v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];
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
