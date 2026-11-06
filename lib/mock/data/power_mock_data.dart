import 'dart:convert';

/// 电力统计演示数据：连续采样点、聚合桶、汇总与日志。
class MockPowerData {
  MockPowerData._();

  static final MockPowerData instance = MockPowerData._();

  static const double _price = 0.62;

  String getStatusJson() {
    final now = DateTime.now();
    return jsonEncode({
      'meter_name': '演示电表 · 客厅',
      'current_kwh': 128.46,
      'current_yuan': 79.65,
      'price': _price,
      'last_fetch': _fmt(now),
      'last_result': '采集成功',
      'sample_count': 168,
      'polling': true,
    });
  }

  String getSummaryJson() {
    var consumption = 0.0;
    for (final b in _buckets('7d')) {
      consumption += (b['consumption_kwh'] as num).toDouble();
    }
    return jsonEncode({
      'total_consumption': consumption,
      'total_cost': consumption * _price,
      'balance_kwh': 128.46,
      'balance_yuan': 79.65,
      'avg_balance': 121.3,
      'sample_count': 168,
    });
  }

  String getAggregatedJson(String range) {
    final buckets = _buckets(range);
    var consumption = 0.0;
    for (final b in buckets) {
      consumption += (b['consumption_kwh'] as num).toDouble();
    }
    return jsonEncode({
      'buckets': buckets,
      'total_consumption': consumption,
      'total_cost': consumption * _price,
      'avg_balance': 121.3,
      'sample_count': 168,
    });
  }

  List<Map<String, dynamic>> _buckets(String range) {
    final now = DateTime.now();
    final hourly = range == '24h';
    final days = switch (range) {
      '24h' => 24,
      '7d' => 7,
      '30d' => 30,
      _ => 30,
    };
    return List<Map<String, dynamic>>.generate(days, (i) {
      final t = hourly
          ? now.subtract(Duration(hours: days - 1 - i))
          : now.subtract(Duration(days: days - 1 - i));
      final kwh = hourly
          ? 0.28 + (i % 7) * 0.06
          : 4.2 + (i % 6) * 0.75;
      return {
        'label': hourly
            ? '${t.hour.toString().padLeft(2, '0')}:00'
            : '${t.month}/${t.day}',
        'timestamp': t.millisecondsSinceEpoch,
        'consumption_kwh': double.parse(kwh.toStringAsFixed(2)),
        'cost_yuan': double.parse((kwh * _price).toStringAsFixed(2)),
        'balance_yuan': double.parse((79.65 + (days - i) * 2.4).toStringAsFixed(2)),
        'balance_kwh': double.parse((128.46 + (days - i) * 3.8).toStringAsFixed(2)),
      };
    });
  }

  String getLogsJson() {
    final now = DateTime.now();
    return jsonEncode([
      for (var i = 0; i < 12; i++)
        {
          'timestamp': _fmt(now.subtract(Duration(minutes: i * 15))),
          'message': i % 4 == 3 ? '读数未变化，跳过本次写入' : '采集成功：128.${46 - i} kWh',
          'success': i % 4 != 0,
        },
    ]);
  }

  String fetchOnce() => '采集成功：128.46 kWh（演示）';

  static String _fmt(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';
}
