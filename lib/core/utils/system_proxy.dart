import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'package:slime_works/core/utils/logger.dart';

/// 系统代理自适应检测（供需要访问境外服务、又不能依赖用户手动配置的链路使用，
/// 如应用自动更新访问 GitHub）。
///
/// Dart 的 HttpClient 默认**不读**操作系统代理设置（只认 HTTP_PROXY 环境变量），
/// 所以"系统里开了代理"不等于"Dio 请求会走代理"。本工具按以下优先级探测：
///
/// 1. 环境变量 HTTPS_PROXY / HTTP_PROXY / ALL_PROXY（大小写均查）；
/// 2. macOS：`scutil --proxy` 读系统网络偏好（HTTPS → HTTP → SOCKS）；
/// 3. Windows：注册表 Internet Settings 的 ProxyEnable / ProxyServer；
///
/// 探测失败一律返回 null（直连），绝不抛错；结果带 TTL 缓存——自动更新可能
/// 长期挂后台，用户在两次检查之间开关代理，缓存过期后要能自适应跟上。
class SystemProxy {
  SystemProxy._();

  static const Loggers _logger = Loggers(name: '系统代理');

  /// 缓存有效期：过短会频繁起子进程，过长跟不上代理开关切换
  static const Duration cacheTtl = Duration(minutes: 5);

  static String? _cached;
  static DateTime? _cachedAt;

  /// 探测当前生效的代理，返回可直接交给 `HttpClient.findProxy` 的规则串
  /// （如 `PROXY 127.0.0.1:7890` / `SOCKS 127.0.0.1:7891`）；无代理返回 null。
  ///
  /// [environment] 注入后**只查环境变量**（跳过平台探测与缓存），供单测使用。
  static String? detect({Map<String, String>? environment, bool useCache = true}) {
    if (environment != null) {
      return _detectUncached(environment, platformProbe: false);
    }
    if (useCache &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < cacheTtl) {
      return _cached;
    }
    final proxy = _detectUncached(Platform.environment);
    _cached = proxy;
    _cachedAt = DateTime.now();
    _logger.info('[系统代理] 探测结果: ${proxy ?? '无（直连）'}');
    return proxy;
  }

  /// 清空缓存（测试或代理配置变更后强制重探）
  static void invalidateCache() {
    _cached = null;
    _cachedAt = null;
  }

  /// 给现成的 [Dio] 挂上系统代理适配器；返回探测到的规则串（无代理返回 null）。
  ///
  /// 只替换 httpClientAdapter，不动 BaseOptions/拦截器。无代理时**恢复默认
  /// 适配器**：Dart HttpClient 默认会读 HTTP_PROXY 环境变量，若上一次探测
  /// 注入过代理、这一次代理已关，必须换回默认行为，否则旧代理会一直挂着。
  static String? applyToDio(Dio dio, {Map<String, String>? environment}) {
    final rule = detect(environment: environment);
    if (rule == null) {
      dio.httpClientAdapter = IOHttpClientAdapter();
      return null;
    }
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.findProxy = (uri) => bypassed(uri) ? 'DIRECT' : rule;
        return client;
      },
    );
    return rule;
  }

  /// 环回/本地地址不走代理（与系统代理"绕过本机"惯例一致）
  static bool bypassed(Uri uri) {
    final host = uri.host.toLowerCase();
    return host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1' ||
        host.endsWith('.local');
  }

  // ───────────────────────── 探测实现 ─────────────────────────

  static String? _detectUncached(Map<String, String> env,
      {bool platformProbe = true}) {
    final fromEnv = proxyRuleFromEnv(env);
    if (fromEnv != null) return fromEnv;
    if (!platformProbe) return null;
    try {
      if (Platform.isMacOS) {
        final result = Process.runSync('scutil', ['--proxy']);
        if (result.exitCode == 0) {
          return parseScutilProxy(result.stdout as String);
        }
      } else if (Platform.isWindows) {
        return _detectWindowsRegistry();
      }
    } catch (e) {
      _logger.error('[系统代理] 平台探测失败（回退直连）: $e');
    }
    return null;
  }

  /// 从环境变量解析代理规则。优先级：HTTPS_PROXY > HTTP_PROXY > ALL_PROXY。
  /// 值可以是裸 `host:port`，也可以带 `http://` / `socks5://` 等 scheme。
  static String? proxyRuleFromEnv(Map<String, String> env) {
    for (final key in const [
      'HTTPS_PROXY', 'https_proxy',
      'HTTP_PROXY', 'http_proxy',
      'ALL_PROXY', 'all_proxy',
    ]) {
      final value = env[key]?.trim();
      if (value == null || value.isEmpty) continue;
      final rule = proxyUrlToRule(value);
      if (rule != null) return rule;
    }
    return null;
  }

  /// 把代理 URL（`http://host:port`、`socks5://host:port`、裸 `host:port`）
  /// 转成 HttpClient.findProxy 规则串；无法解析返回 null。
  /// 注意：dart:io 只支持 HTTP CONNECT 与 SOCKS5，SOCKS4 归为不支持。
  static String? proxyUrlToRule(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return null;
    String scheme = 'http';
    final schemeMatch = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*)://').firstMatch(value);
    if (schemeMatch != null) {
      scheme = schemeMatch.group(1)!.toLowerCase();
      value = value.substring(schemeMatch.end);
    }
    // 去掉可能的用户信息与路径尾巴，只留 host:port
    final at = value.lastIndexOf('@');
    if (at >= 0) value = value.substring(at + 1);
    final slash = value.indexOf('/');
    if (slash >= 0) value = value.substring(0, slash);
    final hostPort = RegExp(r'^(\[[0-9a-fA-F:]+\]|[^\s:]+)(?::(\d{1,5}))?$')
        .firstMatch(value);
    if (hostPort == null) return null;
    final host = hostPort.group(1)!;
    final port = hostPort.group(2);
    // 无端口时按 scheme 给默认端口
    final effectivePort = port ?? (scheme.startsWith('socks') ? '1080' : '80');
    final address = '$host:$effectivePort';
    if (scheme == 'socks5' || scheme == 'socks5h' || scheme == 'socks') {
      return 'SOCKS $address';
    }
    if (scheme == 'http' || scheme == 'https') {
      return 'PROXY $address';
    }
    return null; // socks4 等 dart:io 不支持的协议
  }

  /// 解析 `scutil --proxy` 输出（纯文本解析独立成 static 便于单测）。
  /// 优先级 HTTPS → HTTP → SOCKS，且必须对应 Enable 位为 1。
  static String? parseScutilProxy(String output) {
    int? enabled(String key) => int.tryParse(
        RegExp('$key\\s*:\\s*(\\d+)').firstMatch(output)?.group(1) ?? '');
    String? host(String key) =>
        RegExp('$key\\s*:\\s*(\\S+)').firstMatch(output)?.group(1);

    if (enabled('HTTPSEnable') == 1) {
      final h = host('HTTPSProxy');
      final p = host('HTTPSPort');
      if (h != null && p != null) return 'PROXY $h:$p';
    }
    if (enabled('HTTPEnable') == 1) {
      final h = host('HTTPProxy');
      final p = host('HTTPPort');
      if (h != null && p != null) return 'PROXY $h:$p';
    }
    if (enabled('SOCKSEnable') == 1) {
      final h = host('SOCKSProxy');
      final p = host('SOCKSPort');
      if (h != null && p != null) return 'SOCKS $h:$p';
    }
    return null;
  }

  /// Windows：读 HKCU 的 Internet Settings（IE/系统代理，Clash 等 GUI
  /// "系统代理"开关写的就是这里）。reg.exe 在所有 Windows 上都有。
  static String? _detectWindowsRegistry() {
    const key =
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
    final enableResult = Process.runSync(
        'reg', ['query', key, '/v', 'ProxyEnable']);
    if (enableResult.exitCode != 0) return null;
    final enableOut = enableResult.stdout as String;
    if (!RegExp(r'ProxyEnable\s+REG_DWORD\s+0x1\b').hasMatch(enableOut)) {
      return null;
    }
    final serverResult = Process.runSync(
        'reg', ['query', key, '/v', 'ProxyServer']);
    if (serverResult.exitCode != 0) return null;
    return parseWindowsProxyServer(serverResult.stdout as String);
  }

  /// 解析 `reg query ... /v ProxyServer` 的输出。
  /// ProxyServer 可能是 `host:port`，也可能是
  /// `http=h:p;https=h:p;socks=h:p` 的分协议形式（优先 https 项）。
  static String? parseWindowsProxyServer(String regOutput) {
    final match = RegExp(r'ProxyServer\s+REG_SZ\s+(.+)').firstMatch(regOutput);
    final value = match?.group(1)?.trim();
    if (value == null || value.isEmpty) return null;
    if (!value.contains('=')) {
      return proxyUrlToRule(value);
    }
    final entries = <String, String>{};
    for (final part in value.split(';')) {
      final eq = part.indexOf('=');
      if (eq <= 0) continue;
      entries[part.substring(0, eq).trim().toLowerCase()] =
          part.substring(eq + 1).trim();
    }
    final https = entries['https'] ?? entries['http'];
    if (https != null) return proxyUrlToRule(https);
    final socks = entries['socks'];
    if (socks != null) return proxyUrlToRule('socks5://$socks');
    return null;
  }
}