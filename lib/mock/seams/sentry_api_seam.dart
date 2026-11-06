import 'package:slime_works/mock/data/sentry_mock_data.dart';
import 'package:slime_works/mock/mock_mode.dart';
import 'package:slime_works/src/rust/api/sentry_log.dart' as rust;

MockSentryData get _m => MockSentryData.instance;

String sentryLogInit({required String dbPath}) {
  if (MockMode.enabled) return dbPath;
  return rust.sentryLogInit(dbPath: dbPath);
}

Future<String> sentryLogQuery({
  String? projectId,
  String? level,
  String? query,
  String? environment,
  String? startTime,
  String? endTime,
  required BigInt offset,
  required BigInt limit,
}) async {
  if (MockMode.enabled) {
    return _m.query(
      projectId: projectId,
      level: level,
      query: query,
      environment: environment,
      offset: offset.toInt(),
      limit: limit.toInt(),
    );
  }
  return rust.sentryLogQuery(
    projectId: projectId,
    level: level,
    query: query,
    environment: environment,
    startTime: startTime,
    endTime: endTime,
    offset: offset,
    limit: limit,
  );
}

Future<String> sentryLogGetEvent({required String eventId}) async {
  if (MockMode.enabled) return _m.getEvent(eventId);
  return rust.sentryLogGetEvent(eventId: eventId);
}

Future<bool> sentryLogDeleteEvent({required String eventId}) async {
  if (MockMode.enabled) return _m.deleteEvent(eventId);
  return rust.sentryLogDeleteEvent(eventId: eventId);
}

Future<BigInt> sentryLogDeleteEvents({required List<String> eventIds}) async {
  if (MockMode.enabled) return BigInt.from(_m.deleteEvents(eventIds));
  return rust.sentryLogDeleteEvents(eventIds: eventIds);
}

Future<String> sentryLogGetProjects() async {
  if (MockMode.enabled) return _m.projectsJson();
  return rust.sentryLogGetProjects();
}

Future<void> sentryLogUpdateProjectName({
  required String projectId,
  required String name,
}) async {
  if (MockMode.enabled) {
    _m.renameProject(projectId, name);
    return;
  }
  await rust.sentryLogUpdateProjectName(projectId: projectId, name: name);
}

Future<String> sentryLogGetStats() async {
  if (MockMode.enabled) return _m.statsJson();
  return rust.sentryLogGetStats();
}

Future<String> sentryLogExportJson({
  String? projectId,
  String? level,
  String? query,
  String? environment,
  String? startTime,
  String? endTime,
}) async {
  if (MockMode.enabled) return _m.exportJson();
  return rust.sentryLogExportJson(
    projectId: projectId,
    level: level,
    query: query,
    environment: environment,
    startTime: startTime,
    endTime: endTime,
  );
}

Future<BigInt> sentryLogClearProjectEvents({required String projectId}) async {
  if (MockMode.enabled) return BigInt.from(_m.clearProject(projectId));
  return rust.sentryLogClearProjectEvents(projectId: projectId);
}
