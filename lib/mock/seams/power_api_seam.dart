import 'package:slime_works/mock/data/power_mock_data.dart';
import 'package:slime_works/mock/mock_mode.dart';
import 'package:slime_works/src/rust/api/power_stats.dart' as rust;

MockPowerData get _m => MockPowerData.instance;

String powerStatsInit({required String configJson}) {
  if (MockMode.enabled) return configJson;
  return rust.powerStatsInit(configJson: configJson);
}

void powerStatsUpdateConfig({required String configJson}) {
  if (MockMode.enabled) return;
  rust.powerStatsUpdateConfig(configJson: configJson);
}

void powerStatsSetEnabled({required bool enabled}) {
  if (MockMode.enabled) return;
  rust.powerStatsSetEnabled(enabled: enabled);
}

Future<String> powerStatsFetchOnce() async {
  if (MockMode.enabled) return _m.fetchOnce();
  return rust.powerStatsFetchOnce();
}

Future<void> powerStatsStartPolling() async {
  if (MockMode.enabled) return;
  await rust.powerStatsStartPolling();
}

Future<void> powerStatsStopPolling() async {
  if (MockMode.enabled) return;
  await rust.powerStatsStopPolling();
}

String powerStatsGetStatus() {
  if (MockMode.enabled) return _m.getStatusJson();
  return rust.powerStatsGetStatus();
}

String powerStatsGetSummary() {
  if (MockMode.enabled) return _m.getSummaryJson();
  return rust.powerStatsGetSummary();
}

String powerStatsGetAggregated({required String range}) {
  if (MockMode.enabled) return _m.getAggregatedJson(range);
  return rust.powerStatsGetAggregated(range: range);
}

String powerStatsGetLogs() {
  if (MockMode.enabled) return _m.getLogsJson();
  return rust.powerStatsGetLogs();
}

void powerStatsClearLogs() {
  if (MockMode.enabled) return;
  rust.powerStatsClearLogs();
}
