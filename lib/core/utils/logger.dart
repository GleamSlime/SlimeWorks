import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path_provider/path_provider.dart';
import 'package:flustars/flustars.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';

// Loggers log = Loggers();
Loggers logger = Loggers();

String deviceCode = '';

class Loggers {
  static final List<String> _logs = [];
  static String? _deviceId;
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  static const String _lokiUrl = 'http://logs.gleamslime.com:9090/back/push';

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
              "job": "paopao-market-app",
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
          'User-Agent': 'PaoPao-Market-App/1.0',
          'Connection': 'close', // 避免连接复用问题
        },
      );

      await dio.post(_lokiUrl, data: body);

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
    _logs.add(basicLogEntry);

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
    _logs.add(basicLogEntry);

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
      "${directory.path}/泡泡摩奇APP日志${DateUtil.formatDate(DateTime.now(), format: 'HH:mm:ss:SSS')}.log",
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
