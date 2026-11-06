import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mock 演示模式总开关。
///
/// 编译期 `--dart-define=MOCK_MODE=true` 强制开启；否则读 debug 下的运行时开关。
/// 各接缝每次调用都读 [enabled]，切换后刷新列表即可生效。
class MockMode {
  MockMode._();

  static const String _prefsKey = 'mock_mode_enabled';

  static const bool compileTime = bool.fromEnvironment(
    'MOCK_MODE',
    defaultValue: false,
  );

  static bool _runtime = false;

  /// 是否启用演示数据
  static bool get enabled => compileTime || _runtime;

  /// debug 运行时开关当前值
  static bool get runtimeEnabled => _runtime;

  /// 编译期强制开启（设置页只读展示）
  static bool get forcedByBuild => compileTime;

  static Future<void> load() async {
    if (compileTime) return;
    final prefs = await SharedPreferences.getInstance();
    _runtime = prefs.getBool(_prefsKey) ?? false;
  }

  /// 仅 debug 可写，重启后仍然保留
  static Future<void> setRuntimeEnabled(bool value) async {
    if (!kDebugMode || compileTime) return;
    _runtime = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);
  }
}
