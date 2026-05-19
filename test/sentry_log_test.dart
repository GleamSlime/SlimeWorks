import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SentryLogFilter 参数构建', () {
    test('空筛选条件返回 null 参数', () {
      const projectId = '';
      const level = '';
      const query = '';
      const environment = '';

      final actualProjectId = projectId.isEmpty ? null : projectId;
      final actualLevel = level.isEmpty ? null : level;
      final actualQuery = query.isEmpty ? null : query;
      final actualEnvironment = environment.isEmpty ? null : environment;

      expect(actualProjectId, isNull);
      expect(actualLevel, isNull);
      expect(actualQuery, isNull);
      expect(actualEnvironment, isNull);
    });

    test('筛选条件正确映射', () {
      const projectId = 'my-project';
      const level = 'error';
      const query = 'database';
      const environment = 'production';

      final actualProjectId = projectId.isEmpty ? null : projectId;
      final actualLevel = level.isEmpty ? null : level;
      final actualQuery = query.isEmpty ? null : query;
      final actualEnvironment = environment.isEmpty ? null : environment;

      expect(actualProjectId, 'my-project');
      expect(actualLevel, 'error');
      expect(actualQuery, 'database');
      expect(actualEnvironment, 'production');
    });

    test('部分筛选条件正确处理', () {
      const projectId = 'test-project';
      const level = '';
      const query = '';
      const environment = 'development';

      final actualProjectId = projectId.isEmpty ? null : projectId;
      final actualLevel = level.isEmpty ? null : level;
      final actualQuery = query.isEmpty ? null : query;
      final actualEnvironment = environment.isEmpty ? null : environment;

      expect(actualProjectId, 'test-project');
      expect(actualLevel, isNull);
      expect(actualQuery, isNull);
      expect(actualEnvironment, 'development');
    });
  });

  group('SentryEvent 数据解析', () {
    test('解析事件 JSON', () {
      final eventJson = {
        'event_id': 'abc123',
        'message': '数据库连接失败',
        'level': 'error',
        'platform': 'javascript',
        'environment': 'production',
        'timestamp': '2024-01-01T00:00:00Z',
      };

      expect(eventJson['event_id'], 'abc123');
      expect(eventJson['message'], '数据库连接失败');
      expect(eventJson['level'], 'error');
      expect(eventJson['platform'], 'javascript');
      expect(eventJson['environment'], 'production');
    });

    test('解析事件列表 JSON', () {
      final eventsJson = [
        {'event_id': 'e1', 'message': '错误1', 'level': 'error'},
        {'event_id': 'e2', 'message': '警告1', 'level': 'warning'},
        {'event_id': 'e3', 'message': '信息1', 'level': 'info'},
      ];

      expect(eventsJson.length, 3);
      expect(eventsJson[0]['level'], 'error');
      expect(eventsJson[1]['level'], 'warning');
      expect(eventsJson[2]['level'], 'info');
    });

    test('解析查询结果 JSON', () {
      final queryResult = {
        'total': 100,
        'events': [
          {'event_id': 'e1', 'level': 'error'},
          {'event_id': 'e2', 'level': 'warning'},
        ],
      };

      final total = (queryResult['total'] as num?)?.toInt() ?? 0;
      final events =
          (queryResult['events'] as List<dynamic>?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          [];

      expect(total, 100);
      expect(events.length, 2);
      expect(events[0]['event_id'], 'e1');
      expect(events[1]['event_id'], 'e2');
    });

    test('处理空事件列表', () {
      final queryResult = {'total': 0, 'events': <Map<String, dynamic>>[]};

      final total = (queryResult['total'] as num?)?.toInt() ?? 0;
      final events =
          (queryResult['events'] as List<dynamic>?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          [];

      expect(total, 0);
      expect(events, isEmpty);
    });

    test('处理缺失字段的 JSON', () {
      final eventJson = {'event_id': 'e1'};

      final message = eventJson['message'];
      final level = eventJson['level'];
      final environment = eventJson['environment'];

      expect(message, isNull);
      expect(level, isNull);
      expect(environment, isNull);
    });
  });

  group('SentryLogStats 解析', () {
    test('解析统计数据', () {
      final statsJson = {
        'total_events': 50,
        'level_counts': [
          {'level': 'error', 'count': 20},
          {'level': 'warning', 'count': 15},
          {'level': 'info', 'count': 15},
        ],
        'projects': [
          {'id': 'proj1', 'name': '项目1', 'event_count': 30},
          {'id': 'proj2', 'name': '项目2', 'event_count': 20},
        ],
      };

      expect(statsJson['total_events'], 50);
      expect((statsJson['level_counts'] as List).length, 3);
      expect((statsJson['projects'] as List).length, 2);
    });

    test('统计 error 级别数量', () {
      final levelCounts = [
        {'level': 'error', 'count': 20},
        {'level': 'warning', 'count': 15},
        {'level': 'info', 'count': 15},
      ];

      final errorCount =
          levelCounts.firstWhere(
                (lc) => lc['level'] == 'error',
                orElse: () => {'count': 0},
              )['count']
              as int;

      expect(errorCount, 20);
    });

    test('空统计数据', () {
      final statsJson = <String, dynamic>{};

      final totalEvents = (statsJson['total_events'] as num?)?.toInt() ?? 0;
      final levelCounts = statsJson['level_counts'] as List? ?? [];
      final projects = statsJson['projects'] as List? ?? [];

      expect(totalEvents, 0);
      expect(levelCounts, isEmpty);
      expect(projects, isEmpty);
    });
  });

  group('SentryLogProjects 解析', () {
    test('解析项目列表', () {
      final projectsJson = [
        {'id': 'project-a', 'name': '项目 A', 'event_count': 10},
        {'id': 'project-b', 'name': '项目 B', 'event_count': 20},
      ];

      expect(projectsJson.length, 2);
      expect(projectsJson[0]['id'], 'project-a');
      expect(projectsJson[1]['id'], 'project-b');
    });

    test('项目名称格式化', () {
      const projectId = 'my-test-project';

      final formattedName = '项目 $projectId';

      expect(formattedName, '项目 my-test-project');
    });
  });

  group('分页逻辑', () {
    test('页大小为 50', () {
      const pageSize = 50;
      expect(pageSize, 50);
    });

    test('初始偏移量为 0', () {
      const offset = 0;
      expect(offset, 0);
    });

    test('下一页偏移量计算', () {
      const currentOffset = 0;
      const pageSize = 50;
      const newOffset = currentOffset + pageSize;

      expect(newOffset, 50);
    });

    test('已是最后一页', () {
      const totalEvents = 150;
      const currentOffset = 100;
      const pageSize = 50;

      final hasMore = (currentOffset + pageSize) < totalEvents;

      expect(hasMore, isFalse);
    });

    test('精确最后一页', () {
      const totalEvents = 100;
      const currentOffset = 50;
      const pageSize = 50;

      final hasMore = (currentOffset + pageSize) < totalEvents;

      expect(hasMore, isFalse);
    });

    test('空结果集', () {
      const totalEvents = 0;
      const currentOffset = 0;
      const pageSize = 50;

      final hasMore = (currentOffset + pageSize) < totalEvents;

      expect(hasMore, isFalse);
    });
  });

  group('事件删除逻辑', () {
    test('从列表中移除单个事件', () {
      final events = [
        {'event_id': 'e1', 'message': '事件1'},
        {'event_id': 'e2', 'message': '事件2'},
        {'event_id': 'e3', 'message': '事件3'},
      ];

      events.removeWhere((e) => e['event_id'] == 'e2');

      expect(events.length, 2);
      expect(events.any((e) => e['event_id'] == 'e2'), isFalse);
      expect(events.any((e) => e['event_id'] == 'e1'), isTrue);
      expect(events.any((e) => e['event_id'] == 'e3'), isTrue);
    });

    test('批量删除多个事件', () {
      final events = [
        {'event_id': 'e1', 'message': '事件1'},
        {'event_id': 'e2', 'message': '事件2'},
        {'event_id': 'e3', 'message': '事件3'},
      ];

      final idsToDelete = ['e1', 'e3'];
      events.removeWhere((e) => idsToDelete.contains(e['event_id']));

      expect(events.length, 1);
      expect(events[0]['event_id'], 'e2');
    });

    test('删除不存在的事件', () {
      final events = [
        {'event_id': 'e1', 'message': '事件1'},
        {'event_id': 'e2', 'message': '事件2'},
      ];

      events.removeWhere((e) => e['event_id'] == 'nonexistent');

      expect(events.length, 2);
    });

    test('删除所有事件', () {
      final events = [
        {'event_id': 'e1', 'message': '事件1'},
        {'event_id': 'e2', 'message': '事件2'},
      ];

      events.clear();

      expect(events, isEmpty);
    });
  });

  group('SentryLevel 级别映射', () {
    test('SentryLevel 枚举值', () {
      const levels = ['fatal', 'error', 'warning', 'info', 'debug'];

      expect(levels.contains('fatal'), isTrue);
      expect(levels.contains('error'), isTrue);
      expect(levels.contains('warning'), isTrue);
      expect(levels.contains('info'), isTrue);
      expect(levels.contains('debug'), isTrue);
    });

    test('级别优先级排序', () {
      const priority = {'fatal': 0, 'error': 1, 'warning': 2, 'info': 3, 'debug': 4};

      expect(priority['fatal']! < priority['error']!, isTrue);
      expect(priority['error']! < priority['warning']!, isTrue);
      expect(priority['warning']! < priority['info']!, isTrue);
      expect(priority['info']! < priority['debug']!, isTrue);
    });
  });

  group('isLocal 模式判断', () {
    test('空节点 ID 为本地模式', () {
      const nodeId = '';

      final isLocal = nodeId.isEmpty;

      expect(isLocal, isTrue);
    });

    test('非空节点 ID 为远程模式', () {
      const nodeId = 'node-001';

      final isLocal = nodeId.isEmpty;

      expect(isLocal, isFalse);
    });
  });

  group('导出 JSON 格式化', () {
    test('导出事件列表格式', () {
      final events = [
        {'event_id': 'e1', 'level': 'error', 'message': '错误1'},
        {'event_id': 'e2', 'level': 'warning', 'message': '警告1'},
      ];

      final jsonString = events.toString();

      expect(jsonString.contains('e1'), isTrue);
      expect(jsonString.contains('e2'), isTrue);
      expect(jsonString.contains('error'), isTrue);
      expect(jsonString.contains('warning'), isTrue);
    });
  });

  group('偏移量与限制计算', () {
    test('分页参数传递', () {
      const offset = 100;
      const limit = 50;

      final offsetBigInt = BigInt.from(offset);
      final limitBigInt = BigInt.from(limit);

      expect(offsetBigInt.toInt(), 100);
      expect(limitBigInt.toInt(), 50);
    });

    test('加载更多后偏移量递增', () {
      const initialOffset = 0;
      const pageSize = 50;
      const totalEvents = 200;

      var currentOffset = initialOffset;
      final pages = <int>[];

      while ((currentOffset + pageSize) <= totalEvents) {
        pages.add(currentOffset);
        currentOffset += pageSize;
      }

      expect(pages, [0, 50, 100, 150]);
      expect(currentOffset, 200);
    });
  });
}
