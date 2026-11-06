import 'dart:convert';

/// Sentry 日志演示数据：多级别、多项目、可分页过滤。
class MockSentryData {
  MockSentryData._() {
    _seed();
  }

  static final MockSentryData instance = MockSentryData._();

  final List<Map<String, dynamic>> events = <Map<String, dynamic>>[];
  final Set<String> deleted = <String>{};

  static const List<String> _levels = [
    'fatal',
    'error',
    'warning',
    'info',
    'debug',
  ];

  static const List<String> _projects = ['slime-works-desktop', 'slime-works-mobile'];

  static const List<String> _messages = [
    'Null check operator used on a null value',
    'Connection closed before full header was received',
    '无法在节点上找到媒体文件',
    'Database is locked',
    'Flutter engine detached',
    'Rust FFI call timed out after 30s',
    'Failed to decode response body',
    '路由参数缺失，已回退首页',
  ];

  void _seed() {
    final now = DateTime.now();
    for (var i = 0; i < 64; i++) {
      final level = _levels[i % _levels.length];
      final project = _projects[i % _projects.length];
      final ts = now.subtract(Duration(minutes: i * 37)).toIso8601String();
      final id = 'event-${(i + 1).toString().padLeft(3, '0')}';
      events.add({
        'event_id': id,
        'project_id': project,
        'project_name': project,
        'level': level,
        'message': _messages[i % _messages.length],
        'culprit': i.isEven ? 'media_library.vm' : 'node_server.handler',
        'transaction': i.isEven ? 'GET /node/media' : 'POST /node/call',
        'timestamp': ts,
        'environment': i % 3 == 0 ? 'production' : 'staging',
        'release': '1.8.${i % 4}',
        'server_name': 'demo-mac',
        'platform': 'dart',
        'logger': 'slime_works',
        'tags': {
          'device': 'macOS',
          'route': i.isEven ? 'media' : 'node',
        },
        'user': {
          'username': 'demo',
          'email': 'demo@slime.local',
        },
        'request': {
          'url': 'http://127.0.0.1:8620/node/call',
          'method': i.isEven ? 'GET' : 'POST',
          'headers': {'user-agent': 'SlimeWorks/1.8'},
        },
        'exception': {
          'values': [
            {
              'type': level == 'fatal' ? 'StateError' : 'Exception',
              'value': _messages[i % _messages.length],
              'stacktrace': {
                'frames': [
                  {'filename': 'media_library_vm.dart', 'lineno': 120 + i},
                  {'filename': 'node_router.rs', 'lineno': 88},
                ],
              },
            },
          ],
        },
        'contexts': {
          'device': {'name': 'MacBook Pro', 'os': 'macOS 15.1'},
        },
        'extra': {'sample_index': i},
        'breadcrumbs': [
          {'message': '打开媒体库', 'level': 'info', 'timestamp': ts},
        ],
      });
    }
  }

  String query({
    String? projectId,
    String? level,
    String? query,
    String? environment,
    required int offset,
    required int limit,
  }) {
    var list = events.where((e) => !deleted.contains(e['event_id'])).toList();
    if (projectId != null && projectId.isNotEmpty) {
      list = list.where((e) => e['project_id'] == projectId).toList();
    }
    if (level != null && level.isNotEmpty) {
      list = list.where((e) => e['level'] == level).toList();
    }
    if (environment != null && environment.isNotEmpty) {
      list = list.where((e) => e['environment'] == environment).toList();
    }
    final q = (query ?? '').trim();
    if (q.isNotEmpty) {
      list = list
          .where(
            (e) =>
                (e['message'] as String).contains(q) ||
                (e['culprit'] as String).contains(q),
          )
          .toList();
    }
    final total = list.length;
    final start = offset.clamp(0, total);
    final end = (start + limit).clamp(0, total);
    return jsonEncode({
      'events': list.sublist(start, end),
      'total': total,
    });
  }

  String getEvent(String id) => jsonEncode(
    events.firstWhere(
      (e) => e['event_id'] == id,
      orElse: () => <String, dynamic>{},
    ),
  );

  bool deleteEvent(String id) => deleted.add(id);

  int deleteEvents(List<String> ids) {
    deleted.addAll(ids);
    return ids.length;
  }

  String projectsJson() => jsonEncode([
    for (final p in _projects)
      {
        'id': p,
        'name': p,
        'count': events.where((e) => e['project_id'] == p).length,
        'last_event_at': events.first['timestamp'],
      },
  ]);

  void renameProject(String id, String name) {
    for (final e in events) {
      if (e['project_id'] == id) e['project_name'] = name;
    }
  }

  int clearProject(String projectId) {
    final before = events.length;
    events.removeWhere((e) => e['project_id'] == projectId);
    return before - events.length;
  }

  String statsJson() {
    final counts = <String, int>{};
    for (final e in events) {
      if (deleted.contains(e['event_id'])) continue;
      final level = e['level'] as String;
      counts[level] = (counts[level] ?? 0) + 1;
    }
    return jsonEncode({
      'total_events': events.length - deleted.length,
      'level_counts': counts,
      'projects': _projects,
    });
  }

  String exportJson() => jsonEncode({'events': events});
}
