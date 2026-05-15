import 'package:flutter_test/flutter_test.dart';
import 'package:slime_works/core/services/ollama/ollama_models.dart';

void main() {
  // ── OllamaServer ──────────────────────────────────────────────────────────

  group('OllamaServer', () {
    test('构造函数正确赋值', () {
      final now = DateTime(2025, 1, 15, 10, 30);
      final server = OllamaServer(
        url: 'http://localhost:11434',
        apiKey: 'test-key',
        isAvailable: true,
        lastChecked: now,
      );
      expect(server.url, 'http://localhost:11434');
      expect(server.apiKey, 'test-key');
      expect(server.isAvailable, isTrue);
      expect(server.lastChecked, now);
    });

    test('默认值合理', () {
      final server = OllamaServer(url: 'http://localhost:11434');
      expect(server.apiKey, isNull);
      expect(server.isAvailable, isFalse);
      expect(server.lastChecked, isNull);
    });

    test('toJson/fromJson 往返一致', () {
      final now = DateTime(2025, 6, 1, 12, 0);
      final server = OllamaServer(
        url: 'http://192.168.1.100:11434',
        apiKey: 'sk-abc',
        isAvailable: true,
        lastChecked: now,
      );
      final json = server.toJson();
      final restored = OllamaServer.fromJson(json);

      expect(restored.url, server.url);
      expect(restored.apiKey, server.apiKey);
      expect(restored.isAvailable, server.isAvailable);
      expect(restored.lastChecked?.toIso8601String(), server.lastChecked?.toIso8601String());
    });

    test('fromJson 缺省字段使用默认值', () {
      final json = <String, dynamic>{
        'url': 'http://localhost:11434',
      };
      final server = OllamaServer.fromJson(json);
      expect(server.apiKey, isNull);
      expect(server.isAvailable, isFalse);
      expect(server.lastChecked, isNull);
    });

    test('lastChecked 为 null 时 toJson 不包含非空值', () {
      final server = OllamaServer(url: 'http://localhost:11434');
      final json = server.toJson();
      expect(json['lastChecked'], isNull);
    });

    test('copyWith 不传参数时返回等值副本', () {
      final server = OllamaServer(
        url: 'http://localhost:11434',
        apiKey: 'key',
        isAvailable: true,
      );
      final copy = server.copyWith();
      expect(copy.url, server.url);
      expect(copy.apiKey, server.apiKey);
      expect(copy.isAvailable, server.isAvailable);
    });

    test('copyWith 替换指定字段', () {
      final server = OllamaServer(url: 'http://localhost:11434');
      final updated = server.copyWith(isAvailable: true, apiKey: 'new-key');
      expect(updated.url, 'http://localhost:11434');
      expect(updated.isAvailable, isTrue);
      expect(updated.apiKey, 'new-key');
    });
  });

  // ── OllamaModel ──────────────────────────────────────────────────────────

  group('OllamaModel', () {
    test('构造函数正确赋值', () {
      final modified = DateTime(2025, 3, 1);
      final model = OllamaModel(
        name: 'llama3',
        description: 'A large language model',
        size: 4661224676,
        modifiedAt: modified,
      );
      expect(model.name, 'llama3');
      expect(model.description, 'A large language model');
      expect(model.size, 4661224676);
      expect(model.modifiedAt, modified);
    });

    test('可选字段默认为 null', () {
      final model = OllamaModel(name: 'test');
      expect(model.description, isNull);
      expect(model.size, isNull);
      expect(model.modifiedAt, isNull);
    });

    test('toJson/fromJson 往返一致', () {
      final model = OllamaModel(
        name: 'qwen2.5',
        description: 'Qwen 2.5',
        size: 1024,
        modifiedAt: DateTime(2025, 1, 1),
      );
      final json = model.toJson();
      final restored = OllamaModel.fromJson(json);

      expect(restored.name, model.name);
      expect(restored.description, model.description);
      expect(restored.size, model.size);
    });

    test('fromJson 可处理缺省可选字段', () {
      final json = <String, dynamic>{'name': 'minimal'};
      final model = OllamaModel.fromJson(json);
      expect(model.name, 'minimal');
      expect(model.description, isNull);
      expect(model.size, isNull);
      expect(model.modifiedAt, isNull);
    });
  });

  // ── TranslationLanguagePair ──────────────────────────────────────────────

  group('TranslationLanguagePair', () {
    test('presets 包含 5 种语言对', () {
      expect(TranslationLanguagePair.presets.length, 5);
    });

    test('presets 包含日文→中文', () {
      final jpToCn = TranslationLanguagePair.presets.where(
        (p) => p.from == '日文' && p.to == '中文',
      );
      expect(jpToCn, isNotEmpty);
    });

    test('presets 包含英文→中文', () {
      final enToCn = TranslationLanguagePair.presets.where(
        (p) => p.from == '英文' && p.to == '中文',
      );
      expect(enToCn, isNotEmpty);
    });

    test('displayName 格式正确', () {
      for (final p in TranslationLanguagePair.presets) {
        expect(p.displayName, contains('→'));
        expect(p.displayName, contains(p.from));
        expect(p.displayName, contains(p.to));
      }
    });

    test('相等性基于 from 和 to', () {
      const a = TranslationLanguagePair(from: '日文', to: '中文', displayName: 'A');
      const b = TranslationLanguagePair(from: '日文', to: '中文', displayName: 'B');
      expect(a, equals(b));
    });

    test('不同 from/to 不相等', () {
      const a = TranslationLanguagePair(from: '日文', to: '中文', displayName: '');
      const b = TranslationLanguagePair(from: '英文', to: '中文', displayName: '');
      expect(a, isNot(equals(b)));
    });

    test('hashCode 与 equals 一致', () {
      const a = TranslationLanguagePair(from: '日文', to: '中文', displayName: 'X');
      const b = TranslationLanguagePair(from: '日文', to: '中文', displayName: 'Y');
      expect(a.hashCode, b.hashCode);
    });
  });

  // ── OllamaResponse ───────────────────────────────────────────────────────

  group('OllamaResponse', () {
    test('从完整 JSON 解析', () {
      final json = <String, dynamic>{
        'message': {'content': '你好世界'},
        'done': true,
        'model': 'llama3',
      };
      final response = OllamaResponse.fromJson(json);
      expect(response.content, '你好世界');
      expect(response.done, isTrue);
      expect(response.model, 'llama3');
    });

    test('message 为 null 时 content 为空字符串', () {
      final json = <String, dynamic>{'done': false};
      final response = OllamaResponse.fromJson(json);
      expect(response.content, '');
      expect(response.done, isFalse);
    });

    test('message.content 为 null 时 content 为空字符串', () {
      final json = <String, dynamic>{
        'message': <String, dynamic>{},
        'done': true,
      };
      final response = OllamaResponse.fromJson(json);
      expect(response.content, '');
    });

    test('done 缺省时默认为 false', () {
      final json = <String, dynamic>{'message': {'content': 'hi'}};
      final response = OllamaResponse.fromJson(json);
      expect(response.done, isFalse);
    });

    test('model 缺省时默认为 null', () {
      final json = <String, dynamic>{
        'message': {'content': 'test'},
        'done': true,
      };
      final response = OllamaResponse.fromJson(json);
      expect(response.model, isNull);
    });
  });
}
