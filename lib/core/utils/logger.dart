import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path_provider/path_provider.dart';
import 'package:flustars/flustars.dart';
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../src/rust/api/capture.dart' show writeLogLines;

// Loggers log = Loggers();
Loggers logger = const Loggers();

String deviceCode = '';

class Loggers {
  static final List<String> _logs = [];
  /// 内存日志环形上限：桌面端常驻数天 + 流式日志会无限累积（纯内存泄漏）。
  /// 文件日志已由 Rust slime_logger 按天滚动，这份副本只用于界面查看。
  static const int _maxLogEntries = 5000;
  static List<String> get allLogs => List.unmodifiable(_logs);

  // ── 落文件（第 3 项：让 Dart 日志也能在 release 版日志里看到）────────────
  //
  // 背景：`log()` 原本只 debugPrint + 内存环形缓冲，**完全不写文件**。
  // release 版里 [[Queue]] 入队、[VideoThumb] 封面进度这些关键信息在
  // slime_works_<日期>.log 里一片空白，排查性能问题时会被误判成
  // "队列没生效/功能没跑"。所以这里把 Dart 日志接到 Rust 的 slime_logger，
  // 与 Rust 侧日志同一文件、同一天滚动。
  //
  // 为什么要攒批 + 定时 flush：Rust 的 write_log_info 是 sync FFI，
  // 内部要「取 Mutex + write + flush」；而 Rust 侧自身也在高频写同一个文件。
  // 每行都同步调用会把 UI 线程堵在文件锁上（实测生成封面时 Rust 日志极密）。
  // 因此：平时只入队，攒够 _logFlushBatch 行或每 _logFlushInterval 毫秒才
  // 跨一次 FFI，把 N 行压成 1 次调用。
  static final List<String> _pendingLogs = <String>[];
  static Timer? _logFlushTimer;
  static bool _logFlushScheduled = false;
  static const int _logFlushBatch = 100;
  static const Duration _logFlushInterval = Duration(milliseconds: 2000);
  /// Rust logger 是否已初始化。未初始化时写进去会静默丢（LOG_FILE 是 None），
  /// 与其空转不如先攒在内存里，等初始化完再放行。
  static bool _fileLoggingReady = false;

  /// 由 main() 在 Rust logger 初始化完成后调用，开启文件落盘。
  ///
  /// 不开也能跑：日志只在内存里（界面可见），不会因为漏调这个而崩。
  static void enableFileLogging() {
    _fileLoggingReady = true;
    _scheduleFlush();
  }

  /// 把一条日志排进待写队列（不含时间戳，Rust 侧统一补）。
  static void _enqueueForFile(String levelTag, String message) {
    if (!_fileLoggingReady) return;
    // 日志里的换行会把多行拆散成"没有前缀"的碎片，压成一行更易读
    final oneLine = message.replaceAll('\r', ' ').replaceAll('\n', ' ⏎ ');
    _pendingLogs.add('$levelTag $oneLine');
    if (_pendingLogs.length >= _logFlushBatch) {
      _flushLogs();
    } else {
      _scheduleFlush();
    }
  }

  static void _scheduleFlush() {
    if (_logFlushScheduled || _pendingLogs.isEmpty) return;
    _logFlushScheduled = true;
    _logFlushTimer?.cancel();
    _logFlushTimer = Timer(_logFlushInterval, () {
      _logFlushScheduled = false;
      _flushLogs();
    });
  }

  /// 把待写队列一次性交给 Rust 写盘。失败只吞掉这批，不影响业务。
  static void _flushLogs() {
    if (_pendingLogs.isEmpty) return;
    // 先摘出再调用：FFI 期间新产生的日志留在新队列里，不会被这次清空带走
    final batch = List<String>.from(_pendingLogs);
    _pendingLogs.clear();
    try {
      writeLogLines(lines: batch);
    } catch (_) {
      // 落盘失败不能影响业务；重启后无非少一段 Dart 日志
    }
    if (_pendingLogs.isNotEmpty) _scheduleFlush();
  }

  /// 进程退出前调用，把残留日志刷出去（不调最多丢最后 2 秒）。
  static void flushLogsNow() {
    _logFlushTimer?.cancel();
    _logFlushScheduled = false;
    _flushLogs();
  }

  /// 追加一条内存日志，超出上限时丢弃最旧的（避免无限增长）
  static void _appendLog(String entry) {
    _logs.add(entry);
    if (_logs.length > _maxLogEntries) {
      _logs.removeRange(0, _logs.length - _maxLogEntries);
    }
  }
  static String? _deviceId;
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  static String? get _lokiUrl => dotenv.env['LOKI_URL'];

  final String? name;

  const Loggers({this.name});

  // 网络状态和重试机制
  // static bool _networkAvailable = true;
  static DateTime? _lastFailTime;
  static const Duration _backoffDuration = Duration(minutes: 5); // 5分钟退避

  /// 获取设备唯一标识
  static Future<String> getDeviceId() async {
    if (_deviceId != null) return _deviceId!;

    try {
      if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        _deviceId = iosInfo.identifierForVendor ?? 'unknown-ios-device';
      } else if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        _deviceId = androidInfo.id.isNotEmpty ? androidInfo.id : 'unknown-android-device';
      } else {
        _deviceId = 'unknown-device';
      }
    } catch (e) {
      _deviceId = 'device-error-${DateTime.now().millisecondsSinceEpoch}';
    }

    return _deviceId!;
  }

  /// 生成日志定位码（设备码+时间戳+随机字符串）
  // ignore: unused_element
  static String _generateTraceId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(999999).toString().padLeft(6, '0');

    // 安全地处理设备ID截取
    String deviceIdCleaned = (_deviceId ?? 'unknown').replaceAll('-', '');
    String deviceIdShort;

    if (deviceIdCleaned.length >= 8) {
      deviceIdShort = deviceIdCleaned.substring(0, 8);
    } else if (deviceIdCleaned.isNotEmpty) {
      // 如果长度不足8位，用0填充到8位
      deviceIdShort = deviceIdCleaned.padRight(8, '0');
    } else {
      // 如果为空，使用默认值
      deviceIdShort = 'unknown00';
    }

    return '$deviceIdShort-$timestamp-$random';
  }

  /// 检查是否应该尝试上报（退避机制）
  static bool _shouldAttemptReport() {
    if (_lastFailTime == null) return true;

    final now = DateTime.now();
    final timeSinceLastFail = now.difference(_lastFailTime!);

    return timeSinceLastFail > _backoffDuration;
  }

  /// 上报日志到Loki
  // ignore: unused_element
  static Future<void> _reportToLoki({
    required String message,
    required String level,
    required String name,
    String? traceId,
  }) async {
    // 检查 Loki URL 是否配置
    final lokiUrl = _lokiUrl;
    if (lokiUrl == null || lokiUrl.isEmpty) {
      return;
    }

    // 如果在退避期内，跳过上报
    if (!_shouldAttemptReport()) {
      return;
    }

    try {
      final deviceId = await getDeviceId();
      final timestamp = (DateTime.now().microsecondsSinceEpoch * 1000).toString(); // 纳秒时间戳

      final body = {
        "streams": [
          {
            "stream": {
              "job": "slime-works",
              "level": level.toLowerCase(),
              "deviceId": deviceId,
              "name": name,
              // ignore: use_null_aware_elements
              if (traceId != null) "traceId": traceId,
            },
            "values": [
              [timestamp, message],
            ],
          },
        ],
      };

      final dio = Dio();

      // 配置更宽松的网络参数
      dio.options = BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'Slime-Works/1.0',
          'Connection': 'close', // 避免连接复用问题
        },
      );

      await dio.post(lokiUrl, data: body);

      // 上报成功，重置网络状态
      // _networkAvailable = true;
      _lastFailTime = null;
    } catch (e) {
      // 记录失败时间，启动退避机制
      _lastFailTime = DateTime.now();
      // _networkAvailable = false;

      // 只有在非常见网络连接问题时才输出错误日志，减少噪音
      if (!(e is DioException &&
          (e.message?.contains('Connection closed') == true ||
              e.message?.contains('HttpException') == true ||
              e.message?.contains('SocketException') == true))) {
        debugPrint('Loki report failed (unusual error): $e');
      }
      // 常见网络问题静默处理，避免日志噪音
    }
  }

  String log(
    String message, {
    DateTime? time,
    int? sequenceNumber,
    int level = 0,
    String name = 'LOG',
    Zone? zone,
    Object? error,
    StackTrace? stackTrace,
    bool reportToLoki = false, // 默认关闭上报，避免初始化问题
  }) {
    final currentTime = time ?? DateTime.now();
    final timeStr = DateUtil.formatDate(currentTime, format: 'yyyy-MM-dd HH:mm:ss:SSS');

    // 先记录基础日志，避免在设备ID未初始化时出错
    final basicLogEntry = "$timeStr [$name] $message";
    debugPrint(basicLogEntry);
    _appendLog(basicLogEntry);
    _enqueueForFile('[$name]', message);

    // 异步处理上报逻辑（不阻塞日志记录）
    if (reportToLoki) {
      // _handleAsyncReport(message, 'info', name, basicLogEntry);
    }

    return basicLogEntry;
  }

  /// 信息级别日志（同步），便于兼容现有调用 `logger.info(...)`
  String info(
    String message, {
    DateTime? time,
    int? sequenceNumber,
    int level = 0,
    String name = 'INFO',
    Zone? zone,
    Object? error,
    StackTrace? stackTrace,
    bool reportToLoki = false,
  }) {
    return log(
      message,
      time: time,
      sequenceNumber: sequenceNumber,
      level: level,
      name: name,
      zone: zone,
      error: error,
      stackTrace: stackTrace,
      reportToLoki: reportToLoki,
    );
  }

  /// 异步处理日志上报，确保设备ID初始化后再生成TraceId
  // static Future<String> _handleAsyncReport(
  //   String message,
  //   String level,
  //   String name,
  //   String basicLogEntry,
  // ) async {
  //   try {
  //     // 确保设备ID已初始化
  //     await getDeviceId();
  //     final traceId = _generateTraceId();

  //     // 更新日志条目包含TraceId
  //     final enhancedLogEntry =
  //         "[$name] ${DateUtil.formatDate(DateTime.now(), format: 'HH:mm:ss:SSS')} [$traceId] $message";

  //     // 替换基础日志条目
  //     final index = _logs.lastIndexOf(basicLogEntry);
  //     if (index != -1) {
  //       _logs[index] = enhancedLogEntry;
  //     }

  //     // 上报到Loki
  //     _reportToLoki(message: message, level: level, name: name, traceId: traceId);
  //     return traceId;
  //   } catch (e) {
  //     debugPrint('Failed to handle async report: $e');
  //   }

  //   return "";
  // }

  Future<String> error(
    String message, {
    DateTime? time,
    int? sequenceNumber,
    int level = 0,
    Zone? zone,
    Object? error,
    StackTrace? stackTrace,
    bool reportToLoki = true, // 错误默认上报
  }) async {
    final currentTime = time ?? DateTime.now();
    final timeStr = DateUtil.formatDate(currentTime, format: 'HH:mm:ss:SSS');

    String fullMessage = message;
    if (error != null) {
      fullMessage += ' | Error: $error';
    }
    if (stackTrace != null) {
      fullMessage += ' | StackTrace: ${stackTrace.toString().split('\n').take(3).join(' -> ')}';
    }

    // 先记录基础错误日志
    final basicLogEntry = "[$name] $timeStr $fullMessage";
    debugPrint(basicLogEntry);
    _appendLog(basicLogEntry);
    // 错误要立刻落盘：崩在这一刻就再也刷不出去了
    _enqueueForFile('[$name]', fullMessage);
    _flushLogs();

    // 异步处理上报逻辑
    if (reportToLoki) {
      // return await _handleAsyncReport(fullMessage, 'error', name, basicLogEntry);
    }

    return "";
  }

  /// 调试信息简写 (debug)
  String d(String message) {
    return log(message, name: 'DEBUG');
  }

  /// 信息简写 (info)
  String i(String message) {
    return info(message);
  }

  /// 错误简写 (error)
  Future<String> e(String message, [Object? error]) {
    return this.error(message, error: error);
  }

  /// 保存日志到文件（Base64 编码）
  static Future<String> saveLogsToFile(bool? encrypt) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(
      '${directory.path}/史莱姆工坊日志${DateUtil.formatDate(DateTime.now(), format: 'HH:mm:ss:SSS')}.log',
    );

    String originText = _logs.join("\n");

    await file.writeAsString(
      encrypt == true ? 's${base64Encode(utf8.encode(originText))}' : originText,
    );

    return file.path;
  }

  /// 解码 Base64 日志内容
  static String decodeLogs(String base64Content) {
    return utf8.decode(base64Decode(base64Content));
  }
}
