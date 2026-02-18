import 'package:flutter/foundation.dart';

class TimeConsumptionTest {
  TimeConsumptionTest({this.tag});

  final String? tag;

  int startTime = 0;

  void start({bool? log = true}) {
    if (kDebugMode && log == true) {
      debugPrint('>>> ${tag ?? ""} 耗时开始计时 <<<');
    }
    startTime = DateTime.now().millisecondsSinceEpoch;
  }

  int end({bool? log = true}) {
    final endTime = DateTime.now().millisecondsSinceEpoch;
    final duration = endTime - startTime;

    if (kDebugMode && log == true) {
      debugPrint('>>> ${tag ?? ""} 耗时: $duration ms <<<');
    }

    return duration;
  }
}
