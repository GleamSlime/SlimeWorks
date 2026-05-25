import 'package:flutter/foundation.dart';
import 'package:slime_works/core/utils/logger.dart';
const Loggers _logger = Loggers(name: '耗时测试');


class TimeConsumptionTest {
  TimeConsumptionTest({this.tag});

  final String? tag;

  int startTime = 0;

  void start({bool? log = true}) {
    if (kDebugMode && log == true) {
      _logger.info('>>> ${tag ?? ""} 耗时开始计时 <<<');
    }
    startTime = DateTime.now().millisecondsSinceEpoch;
  }

  int end({bool? log = true}) {
    final endTime = DateTime.now().millisecondsSinceEpoch;
    final duration = endTime - startTime;

    if (kDebugMode && log == true) {
      _logger.info('>>> ${tag ?? ""} 耗时: $duration ms <<<');
    }

    return duration;
  }
}
