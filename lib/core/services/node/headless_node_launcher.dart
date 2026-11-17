import 'dart:async';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'node_settings_service.dart';

/// 切换无头模式的结果。
class HeadlessSwitchResult {
  const HeadlessSwitchResult._(this.ok, this.message);

  /// 已在目标端口就绪，调用方可以退出界面
  const HeadlessSwitchResult.success(String message) : this._(true, message);

  /// 失败（已回滚为内置节点服务）
  const HeadlessSwitchResult.failure(String message) : this._(false, message);

  final bool ok;
  final String message;
}

/// 把本机节点从「Flutter 内置服务」切成「slime_node 独立进程」。
///
/// NAS / 常驻小主机上跑完整客户端只为开节点并不划算：这里停掉内置监听，
/// 用当前的本机节点配置（端口/名称/授权码）拉起独立的 `slime_node`，
/// 确认端口真的在应答后再让界面退出，之后只剩节点进程常驻。
///
/// 数据目录刻意不传：子进程继承客户端的环境变量，各模块推导出的数据库路径
/// 与界面里完全一致，客户端连过来看到的还是同一份数据。
class HeadlessNodeLauncher {
  HeadlessNodeLauncher(this._nodeService);

  final NodeSettingsService _nodeService;

  static const String _keyBinaryPath = 'node_headless_binary';

  /// 可执行文件名：Windows 需要 .exe 后缀
  static String get executableName => Platform.isWindows ? 'slime_node.exe' : 'slime_node';

  /// 端口就绪的最长等待时间。首次启动要初始化日志与各模块，8 秒偏紧，给 15 秒。
  static const Duration _readyTimeout = Duration(seconds: 15);

  /// 读取上次保存的可执行文件路径；文件已不存在时返回 null。
  Future<String?> loadSavedBinary() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_keyBinaryPath) ?? '';
    if (path.isEmpty || !await File(path).exists()) {
      return null;
    }
    return path;
  }

  Future<void> saveBinary(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBinaryPath, path.trim());
  }

  /// 常见安装位置逐个探测，找到第一个存在的返回。
  ///
  /// 顺序按「离应用越近越优先」：打包附带的二进制、用户级 bin、系统 PATH。
  /// 应用同目录优先，是为了让「解包后和主程序放一起」这种最省事的用法直接可用。
  Future<String?> detectBinary() async {
    final name = executableName;
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    final separator = Platform.isWindows ? ';' : ':';

    final candidates = <String>[
      '$exeDir/$name',
      // macOS .app：Contents/MacOS/ 的上一级是 Contents，资源放 Resources
      '$exeDir/../Resources/$name',
      if (home.isNotEmpty) '$home/.local/bin/$name',
      if (home.isNotEmpty) '$home/bin/$name',
      if (home.isNotEmpty) '$home/$name',
      if (Platform.isMacOS) '/opt/homebrew/bin/$name',
      if (!Platform.isWindows) '/usr/local/bin/$name',
      if (!Platform.isWindows) '/usr/bin/$name',
      for (final dir in (Platform.environment['PATH'] ?? '').split(separator))
        if (dir.trim().isNotEmpty) '${dir.trim()}/$name',
    ];

    for (final path in candidates) {
      final file = File(path);
      if (await file.exists()) {
        return file.absolute.path;
      }
    }
    return null;
  }

  /// 组装命令行参数。
  ///
  /// 走命令行而不是 JSON 配置文件：这些值本来就是设置页里的当前状态，
  /// 临时文件还要考虑权限与清理，命令行最直接。
  static List<String> buildArguments({
    required int port,
    required String name,
    required String authCode,
    String? dataDir,
    String? logDir,
  }) {
    return <String>[
      '--host',
      '0.0.0.0',
      '--port',
      '$port',
      '--name',
      name.trim().isEmpty ? '本机节点' : name.trim(),
      if (authCode.trim().isNotEmpty) ...<String>['--auth', authCode.trim()],
      if (dataDir != null && dataDir.trim().isNotEmpty) ...<String>['--data-dir', dataDir.trim()],
      if (logDir != null && logDir.trim().isNotEmpty) ...<String>['--log-dir', logDir.trim()],
    ];
  }

  /// 切换并等待就绪。失败时会把内置节点服务重新拉起来，界面保持可用。
  Future<HeadlessSwitchResult> switchToHeadless({
    required String binaryPath,
    String? dataDir,
    String? logDir,
  }) async {
    final binary = binaryPath.trim();
    if (binary.isEmpty) {
      return const HeadlessSwitchResult.failure('请先指定 slime_node 可执行文件路径');
    }
    if (!await File(binary).exists()) {
      return HeadlessSwitchResult.failure('找不到可执行文件：$binary');
    }

    final port = _nodeService.localNodePort.value;
    final args = buildArguments(
      port: port,
      name: _nodeService.localNodeName.value,
      authCode: _nodeService.localNodeAuthCode.value,
      dataDir: dataDir,
      logDir: logDir,
    );

    // 先放开端口：内置服务不停，独立进程会因 bind 失败直接退出
    await _nodeService.stopLocalNodeServer();

    Process process;
    try {
      process = await Process.start(
        binary,
        args,
        mode: ProcessStartMode.detached,
        workingDirectory: File(binary).parent.path,
      );
    } catch (e) {
      await _restoreEmbeddedServer();
      return HeadlessSwitchResult.failure('启动 slime_node 失败：$e');
    }

    if (!await _waitHealthy(port)) {
      try {
        process.kill();
      } catch (_) {}
      await _restoreEmbeddedServer();
      return HeadlessSwitchResult.failure(
        'slime_node 未能在 $port 端口就绪（进程 ${process.pid}）。'
        '请确认可执行文件可用、端口未被占用，并查看其日志。',
      );
    }

    await saveBinary(binary);
    return HeadlessSwitchResult.success('已切换到无头模式（端口 $port，进程 ${process.pid}）');
  }

  /// 回滚：把内置节点服务重新拉起来。失败只记日志，不影响上层展示原始错误。
  Future<void> _restoreEmbeddedServer() async {
    try {
      await _nodeService.startLocalNodeServer();
    } catch (_) {
      // 端口可能还没被系统释放，这里不掩盖真正的失败原因
    }
  }

  /// 轮询 /health：只有节点真的应答了才认为切换成功，
  /// 否则界面一退就成了「两边都没有服务」。
  Future<bool> _waitHealthy(int port) async {
    final deadline = DateTime.now().add(_readyTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 600);
      try {
        final request = await client.getUrl(Uri.parse('http://127.0.0.1:$port/health'));
        final response = await request.close().timeout(const Duration(seconds: 1));
        final healthy = response.statusCode == 200;
        await response.drain<void>();
        if (healthy) {
          return true;
        }
      } catch (_) {
        // 进程还在启动或端口未监听，继续等
      } finally {
        client.close(force: true);
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return false;
  }
}
