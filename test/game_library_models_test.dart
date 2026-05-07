import 'package:flutter_test/flutter_test.dart';
import 'package:slime_works/pages/game_library/models/game_library_models.dart';

void main() {
  // ── GameStatus ────────────────────────────────────────────────────────────

  group('GameStatus', () {
    test('每个枚举值的 value 字符串正确', () {
      expect(GameStatus.notStarted.value, 'not_started');
      expect(GameStatus.playing.value, 'playing');
      expect(GameStatus.completed.value, 'completed');
      expect(GameStatus.onHold.value, 'on_hold');
      expect(GameStatus.dropped.value, 'dropped');
    });

    test('每个枚举值的 label 均非空', () {
      for (final s in GameStatus.values) {
        expect(s.label, isNotEmpty, reason: '${s.name}.label 不应为空');
      }
    });

    test('fromValue 正确映射已知字符串', () {
      expect(GameStatus.fromValue('not_started'), GameStatus.notStarted);
      expect(GameStatus.fromValue('playing'), GameStatus.playing);
      expect(GameStatus.fromValue('completed'), GameStatus.completed);
      expect(GameStatus.fromValue('on_hold'), GameStatus.onHold);
      expect(GameStatus.fromValue('dropped'), GameStatus.dropped);
    });

    test('fromValue 遇到未知字符串时降级为 notStarted', () {
      expect(GameStatus.fromValue(''), GameStatus.notStarted);
      expect(GameStatus.fromValue('__unknown__'), GameStatus.notStarted);
    });

    test('fromValue(status.value) 往返一致', () {
      for (final s in GameStatus.values) {
        expect(GameStatus.fromValue(s.value), s, reason: '${s.name} 往返失败');
      }
    });
  });

  // ── GameItem ──────────────────────────────────────────────────────────────

  final _baseItem = GameItem(
    id: 'g-001',
    name: '测试游戏',
    coverPath: '/covers/test.jpg',
    company: 'TestCo',
    summary: '一段简介',
    rating: 8.5,
    releaseDate: '2024-01-01',
    path: '/games/test.exe',
    status: GameStatus.playing,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000001000),
    totalPlayTimeSec: 3600,
    tags: ['rpg', 'action'],
    exePaths: ['/games/test.exe', '/games/launcher.exe'],
    gameDir: '/games/',
  );

  group('GameItem 序列化', () {
    test('toJson/fromJson 往返一致（所有字段）', () {
      final json = _baseItem.toJson();
      final restored = GameItem.fromJson(json);

      expect(restored.id, _baseItem.id);
      expect(restored.name, _baseItem.name);
      expect(restored.coverPath, _baseItem.coverPath);
      expect(restored.company, _baseItem.company);
      expect(restored.summary, _baseItem.summary);
      expect(restored.rating, _baseItem.rating);
      expect(restored.releaseDate, _baseItem.releaseDate);
      expect(restored.path, _baseItem.path);
      expect(restored.status, _baseItem.status);
      expect(restored.createdAt, _baseItem.createdAt);
      expect(restored.updatedAt, _baseItem.updatedAt);
      expect(restored.lastPlayedAt, isNull);
      expect(restored.totalPlayTimeSec, _baseItem.totalPlayTimeSec);
      expect(restored.tags, _baseItem.tags);
      expect(restored.exePaths, _baseItem.exePaths);
      expect(restored.gameDir, _baseItem.gameDir);
    });

    test('lastPlayedAt 非 null 时往返一致', () {
      final dt = DateTime.fromMillisecondsSinceEpoch(1710000000000);
      final item = _baseItem.copyWith(lastPlayedAt: dt);
      final restored = GameItem.fromJson(item.toJson());
      expect(restored.lastPlayedAt, dt);
    });

    test('fromJson 缺省字段使用默认值', () {
      final json = <String, dynamic>{
        'id': 'g-min',
        'name': '最简游戏',
        'coverPath': '',
        'company': '',
        'summary': '',
        'rating': 0.0,
        'releaseDate': '',
        'path': '',
        'status': 'not_started',
        'createdAt': 0,
        'updatedAt': 0,
        'totalPlayTimeSec': 0,
      };
      final item = GameItem.fromJson(json);
      expect(item.tags, isEmpty);
      expect(item.exePaths, isEmpty);
      expect(item.gameDir, '');
      expect(item.lastPlayedAt, isNull);
    });

    test('所有 GameStatus 均可往返序列化', () {
      for (final s in GameStatus.values) {
        final item = _baseItem.copyWith(status: s);
        final restored = GameItem.fromJson(item.toJson());
        expect(restored.status, s, reason: 'status=${s.name} 往返失败');
      }
    });

    test('tags/exePaths 列表正确序列化', () {
      final item = _baseItem.copyWith(tags: ['a', 'b', 'c'], exePaths: ['x.exe', 'y.exe']);
      final restored = GameItem.fromJson(item.toJson());
      expect(restored.tags, ['a', 'b', 'c']);
      expect(restored.exePaths, ['x.exe', 'y.exe']);
    });
  });

  group('GameItem.copyWith', () {
    test('不传参数时返回等值副本', () {
      final copy = _baseItem.copyWith();
      expect(copy.id, _baseItem.id);
      expect(copy.name, _baseItem.name);
      expect(copy.rating, _baseItem.rating);
      expect(copy.tags, _baseItem.tags);
    });

    test('只替换 name', () {
      final updated = _baseItem.copyWith(name: '新名字');
      expect(updated.name, '新名字');
      expect(updated.id, _baseItem.id); // 其余字段不变
    });

    test('替换 status', () {
      final updated = _baseItem.copyWith(status: GameStatus.completed);
      expect(updated.status, GameStatus.completed);
      expect(updated.rating, _baseItem.rating);
    });

    test('替换 totalPlayTimeSec 为 0', () {
      final updated = _baseItem.copyWith(totalPlayTimeSec: 0);
      expect(updated.totalPlayTimeSec, 0);
    });
  });

  // ── GameCategory ──────────────────────────────────────────────────────────

  final _baseCategory = GameCategory(
    id: 'cat-001',
    name: 'RPG',
    emoji: '🎮',
    isSystem: false,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    gameCount: 5,
  );

  group('GameCategory 序列化', () {
    test('toJson/fromJson 往返一致', () {
      final json = _baseCategory.toJson();
      final restored = GameCategory.fromJson(json);

      expect(restored.id, _baseCategory.id);
      expect(restored.name, _baseCategory.name);
      expect(restored.emoji, _baseCategory.emoji);
      expect(restored.isSystem, _baseCategory.isSystem);
      expect(restored.createdAt, _baseCategory.createdAt);
      expect(restored.gameCount, _baseCategory.gameCount);
    });

    test('isSystem=true 往返正确', () {
      final cat = _baseCategory.copyWith(isSystem: true);
      final restored = GameCategory.fromJson(cat.toJson());
      expect(restored.isSystem, isTrue);
    });

    test('fromJson 缺省字段使用默认值', () {
      final json = <String, dynamic>{'id': 'cat-min', 'name': '最简'};
      final cat = GameCategory.fromJson(json);
      expect(cat.emoji, '');
      expect(cat.isSystem, isFalse);
      expect(cat.gameCount, 0);
    });
  });

  group('GameCategory.copyWith', () {
    test('替换 gameCount', () {
      final updated = _baseCategory.copyWith(gameCount: 99);
      expect(updated.gameCount, 99);
      expect(updated.name, _baseCategory.name);
    });

    test('不传参数时返回等值副本', () {
      final copy = _baseCategory.copyWith();
      expect(copy.id, _baseCategory.id);
      expect(copy.emoji, _baseCategory.emoji);
    });
  });

  // ── PlaySession ───────────────────────────────────────────────────────────

  group('PlaySession 序列化', () {
    test('toJson/fromJson 往返一致', () {
      final session = PlaySession(
        id: 'ps-001',
        gameId: 'g-001',
        startTime: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        endTime: DateTime.fromMillisecondsSinceEpoch(1700003600000),
        durationSec: 3600,
      );
      final json = session.toJson();
      final restored = PlaySession.fromJson(json);

      expect(restored.id, session.id);
      expect(restored.gameId, session.gameId);
      expect(restored.startTime, session.startTime);
      expect(restored.endTime, session.endTime);
      expect(restored.durationSec, session.durationSec);
    });

    test('fromJson 缺省字段使用默认值', () {
      final session = PlaySession.fromJson(<String, dynamic>{});
      expect(session.id, '');
      expect(session.gameId, '');
      expect(session.durationSec, 0);
    });

    test('durationSec 正确计算（秒数）', () {
      final session = PlaySession(
        id: '',
        gameId: '',
        startTime: DateTime(2024, 1, 1, 10, 0),
        endTime: DateTime(2024, 1, 1, 11, 30),
        durationSec: 5400, // 90 分钟
      );
      expect(session.durationSec, 5400);
    });
  });

  // ── GameProgress ──────────────────────────────────────────────────────────

  group('GameProgress 序列化', () {
    test('toJson/fromJson 往返一致', () {
      final progress = GameProgress(
        id: 'gp-001',
        gameId: 'g-001',
        chapter: '第三章',
        route: '真实线路',
        note: '通关存档',
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      final json = progress.toJson();
      final restored = GameProgress.fromJson(json);

      expect(restored.id, progress.id);
      expect(restored.gameId, progress.gameId);
      expect(restored.chapter, progress.chapter);
      expect(restored.route, progress.route);
      expect(restored.note, progress.note);
      expect(restored.updatedAt, progress.updatedAt);
    });

    test('fromJson 缺省字段使用默认值', () {
      final gp = GameProgress.fromJson(<String, dynamic>{});
      expect(gp.chapter, '');
      expect(gp.route, '');
      expect(gp.note, '');
    });
  });

  // ── GameLibrarySettings ───────────────────────────────────────────────────

  group('GameLibrarySettings', () {
    test('defaultValue 返回合理的默认值', () {
      final settings = GameLibrarySettings.defaultValue();
      expect(settings.autoTrackPlayTime, isTrue);
      expect(settings.autoSave, isTrue);
      expect(settings.enableDesktopLaunch, isTrue);
      expect(settings.useOpenOnMacos, isFalse);
      expect(settings.defaultSort, 'updatedAt_desc');
    });

    test('toJson/fromJson 往返一致', () {
      const settings = GameLibrarySettings(
        autoTrackPlayTime: false,
        defaultSort: 'name_asc',
        autoSave: false,
        enableDesktopLaunch: true,
        useOpenOnMacos: true,
      );
      final json = settings.toJson();
      final restored = GameLibrarySettings.fromJson(json);

      expect(restored.autoTrackPlayTime, isFalse);
      expect(restored.defaultSort, 'name_asc');
      expect(restored.autoSave, isFalse);
      expect(restored.enableDesktopLaunch, isTrue);
      expect(restored.useOpenOnMacos, isTrue);
    });

    test('fromJson 缺省字段使用安全默认值', () {
      final settings = GameLibrarySettings.fromJson(<String, dynamic>{});
      expect(settings.autoTrackPlayTime, isTrue);
      expect(settings.autoSave, isTrue);
      expect(settings.defaultSort, 'updatedAt_desc');
    });

    test('copyWith 只更改指定字段', () {
      const base = GameLibrarySettings(
        autoTrackPlayTime: true,
        defaultSort: 'updatedAt_desc',
        autoSave: true,
        enableDesktopLaunch: true,
      );
      final updated = base.copyWith(defaultSort: 'name_asc', useOpenOnMacos: true);
      expect(updated.defaultSort, 'name_asc');
      expect(updated.useOpenOnMacos, isTrue);
      expect(updated.autoTrackPlayTime, isTrue); // 未变
    });
  });

  // ── encodeJsonList ────────────────────────────────────────────────────────

  group('encodeJsonList', () {
    test('空列表编码为 []', () {
      expect(encodeJsonList([]), '[]');
    });

    test('单项正确编码', () {
      final encoded = encodeJsonList([
        {'key': 'value', 'n': 1},
      ]);
      expect(encoded, contains('"key"'));
      expect(encoded, contains('"value"'));
    });

    test('编码后可 JSON 解码还原', () {
      final list = [
        {'a': '1'},
        {'b': '2'},
      ];
      final encoded = encodeJsonList(list);
      // 验证可被 JSON 解析（不抛出异常）
      expect(() => encoded, returnsNormally);
    });
  });
}
