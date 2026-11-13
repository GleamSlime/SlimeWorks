import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/page_golden.dart' show loadAppFonts;

// 字体在全局 setUpAll 加载一次，而非每个测试各加载一遍：
// 反复加载会反复触发系统字体变更通知，relayout 帧回调挂到各自销毁的树上，
// 被 Flutter 3.50 判「树销毁后仍有动画在跑」。详见 loadAppFonts 的说明。
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUpAll(() async {
    await loadAppFonts();
  });
  await testMain();
}