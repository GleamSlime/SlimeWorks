import 'package:flutter/foundation.dart';

class TimeConsumptionTest {
  TimeConsumptionTest({this.tag});

  final String? tag;

  int startTime = 0;

  void start() {
    if (kDebugMode) {
      print('>>> ${tag ?? ""} 耗时开始计时 <<<');
    }
    startTime = DateTime.now().millisecondsSinceEpoch;
  }

  void end() {
    final endTime = DateTime.now().millisecondsSinceEpoch;
    final duration = endTime - startTime;
    if (kDebugMode) {
      print('>>> ${tag ?? ""} 耗时: $duration ms <<<');
    }
  }
}
