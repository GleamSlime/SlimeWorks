import 'package:flutter_test/flutter_test.dart';
import 'package:slime_works/pages/collection/picture/components/smart_folder.dart';
import 'package:slime_works/src/rust/api/media_collection.dart' show MediaCollection;

/// 说明：
/// MediaCollection 是 FRB 生成的纯数据类（const 构造函数，不触碰 RustLib），
/// 因此可直接在单测中构造，无需 Rust 运行时。
MediaCollection makeCollection({
  String id = 'c1',
  required String title,
  String folderPath = '/library/default',
  String? folderId,
}) {
  return MediaCollection(
    id: id,
    title: title,
    folderPath: folderPath,
    folderId: folderId,
    itemCount: BigInt.from(3),
    createdAt: 0,
    updatedAt: 0,
  );
}

void main() {
  // ── effectivePattern：关键词经 RegExp.escape 合并进 pattern ──────────────

  group('effectivePattern 关键词合并', () {
    test('特殊字符关键词被转义为字面量', () {
      const folder = SmartFolder(
        id: 'sf1',
        name: '转义测试',
        regexPattern: '',
        keywords: ['a.b', '(x)'],
      );
      // '.' 与 '(' ')' 应被反斜杠转义，多个关键词用 | 连接
      expect(folder.effectivePattern, r'a\.b|\(x\)');
    });

    test('关键词与手动正则合并：关键词在前、原正则在后', () {
      const folder = SmartFolder(
        id: 'sf2',
        name: '合并测试',
        regexPattern: r'\d+集',
        keywords: ['汉化'],
      );
      expect(folder.effectivePattern, r'汉化|\d+集');
    });

    test('无关键词时原样返回 regexPattern；两者皆空返回空串', () {
      const onlyRegex = SmartFolder(id: 'sf3', name: 'N', regexPattern: r'^\d{4}-');
      expect(onlyRegex.effectivePattern, r'^\d{4}-');

      const empty = SmartFolder(id: 'sf4', name: 'N', regexPattern: '');
      expect(empty.effectivePattern, isEmpty);
    });

    test('含正则元字符的关键词按字面匹配（不误伤）', () {
      const folder = SmartFolder(
        id: 'sf5',
        name: '字面点号',
        regexPattern: '',
        keywords: ['a.b'],
      );
      // 构造出的正则可正常编译
      expect(() => RegExp(folder.effectivePattern), returnsNormally);

      final re = RegExp(folder.effectivePattern, caseSensitive: false);
      expect(re.hasMatch('我的a.b相册'), isTrue); // 字面 'a.b'
      expect(re.hasMatch('我的axb相册'), isFalse); // '.' 不再是通配符
    });
  });

  // ── matchesCollection：范围过滤 / 大小写 / 非法正则容错 ──────────────────

  group('matchesCollection', () {
    test('空 pattern 且无关键词 → 全部匹配', () {
      const folder = SmartFolder(id: 'sf', name: 'N', regexPattern: '');
      expect(folder.matchesCollection(makeCollection(title: '任意集合')), isTrue);
    });

    test('targetFolderIds 范围过滤：不在列表中的文件夹被排除', () {
      const folder = SmartFolder(
        id: 'sf',
        name: 'N',
        regexPattern: '',
        targetFolderIds: ['f1'],
      );
      expect(folder.matchesCollection(makeCollection(title: 'T', folderId: 'f1')), isTrue);
      expect(folder.matchesCollection(makeCollection(title: 'T', folderId: 'f2')), isFalse);
      // folderId 为 null 也不在范围列表内
      expect(folder.matchesCollection(makeCollection(title: 'T')), isFalse);
    });

    test('targetFolderIds 为空表示不限制文件夹', () {
      const folder = SmartFolder(
        id: 'sf',
        name: 'N',
        regexPattern: r'风景',
        targetFolderIds: [],
      );
      expect(folder.matchesCollection(makeCollection(title: '风景图', folderId: 'any')), isTrue);
    });

    test('关键词/正则匹配对大小写不敏感', () {
      const folder = SmartFolder(
        id: 'sf',
        name: 'N',
        regexPattern: '',
        keywords: ['Hero'],
      );
      expect(folder.matchesCollection(makeCollection(title: 'SUPER HERO 合集')), isTrue); // 忽略大小写
      expect(folder.matchesCollection(makeCollection(title: '完全不相关')), isFalse);
    });

    test('匹配同时作用于 title 与 folderPath', () {
      const folder = SmartFolder(id: 'sf', name: 'N', regexPattern: '漫展');
      expect(
        folder.matchesCollection(makeCollection(title: '照片', folderPath: '/data/漫展2024')),
        isTrue,
      );
      expect(
        folder.matchesCollection(makeCollection(title: '漫展现场', folderPath: '/data')),
        isTrue,
      );
    });

    test('非法正则不抛异常，容错返回 true（视为全部匹配）', () {
      const folder = SmartFolder(id: 'sf', name: 'N', regexPattern: r'(['); // 未闭合字符类
      expect(() => folder.matchesCollection(makeCollection(title: 'T')), returnsNormally);
      expect(folder.matchesCollection(makeCollection(title: 'T')), isTrue);
    });

    test('fileName 模式下集合级检查只验证文件夹范围', () {
      const folder = SmartFolder(
        id: 'sf',
        name: 'N',
        regexPattern: r'\d{4}',
        regexTarget: SmartFolderRegexTarget.fileName,
        targetFolderIds: ['f1'],
      );
      // 即使 title 不含 4 位数字，集合级也放行（具体文件过滤在 matchesFileNames）
      expect(folder.matchesCollection(makeCollection(title: '纯文字', folderId: 'f1')), isTrue);
      expect(folder.matchesCollection(makeCollection(title: '纯文字', folderId: 'f9')), isFalse);
    });

    test('关键词经 matchesCollection 全链路：字面点号关键词命中集合名', () {
      const folder = SmartFolder(
        id: 'sf',
        name: 'N',
        regexPattern: '',
        keywords: ['v2.0'],
      );
      expect(folder.matchesCollection(makeCollection(title: '工具 v2.0 截图')), isTrue);
      expect(folder.matchesCollection(makeCollection(title: '工具 v2x0 截图')), isFalse);
    });
  });

  // ── toJson/fromJson 保留 keywords（回归保障 effectivePattern 不丢数据） ──

  group('keywords 序列化往返', () {
    test('toJson/fromJson 保留 keywords 与 effectivePattern', () {
      const original = SmartFolder(
        id: 'sf',
        name: 'N',
        regexPattern: r'\d+',
        keywords: ['a.b', '写真'],
        targetFolderIds: ['f1'],
      );
      final restored = SmartFolder.fromJson(original.toJson());
      expect(restored.keywords, ['a.b', '写真']);
      expect(restored.effectivePattern, original.effectivePattern);
    });

    test('fromJson 缺 keywords 字段 → 空列表', () {
      final restored = SmartFolder.fromJson(<String, dynamic>{
        'id': 'sf-old',
        'name': '旧数据',
        'regexPattern': '',
      });
      expect(restored.keywords, isEmpty);
      expect(restored.effectivePattern, isEmpty);
    });
  });
}
