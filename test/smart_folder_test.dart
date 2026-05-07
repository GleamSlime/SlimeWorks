import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/pages/collection/picture/components/smart_folder.dart';

void main() {
  group('SmartFolder', () {
    // ── 序列化 ──────────────────────────────────────────────────────────────

    group('序列化', () {
      test('toJson/fromJson 往返一致', () {
        const folder = SmartFolder(
          id: 'sf-001',
          name: '测试文件夹',
          regexPattern: r'^\d{4}-',
          regexTarget: SmartFolderRegexTarget.collectionName,
          fileTypeFilter: SmartFolderFileType.all,
          targetFolderIds: ['folder-1', 'folder-2'],
        );
        final json = folder.toJson();
        final restored = SmartFolder.fromJson(json);

        expect(restored.id, folder.id);
        expect(restored.name, folder.name);
        expect(restored.regexPattern, folder.regexPattern);
        expect(restored.regexTarget, folder.regexTarget);
        expect(restored.fileTypeFilter, folder.fileTypeFilter);
        expect(restored.targetFolderIds, folder.targetFolderIds);
      });

      test('listToJson/listFromJson 往返一致', () {
        final folders = [
          const SmartFolder(id: 'a', name: 'A', regexPattern: ''),
          const SmartFolder(id: 'b', name: 'B', regexPattern: r'\d+'),
        ];
        final json = SmartFolder.listToJson(folders);
        final restored = SmartFolder.listFromJson(json);

        expect(restored.length, 2);
        expect(restored[0].id, 'a');
        expect(restored[1].id, 'b');
      });

      test('fromJson 可迁移旧版 targetFolderId 字段', () {
        final json = <String, dynamic>{
          'id': 'sf-old',
          'name': '旧版',
          'regexPattern': '',
          'regexTarget': 'collectionName',
          'fileTypeFilter': 'all',
          'targetFolderId': 'folder-old',
          // 没有 targetFolderIds key
        };
        final folder = SmartFolder.fromJson(json);
        expect(folder.targetFolderIds, ['folder-old']);
      });

      test('fromJson 缺少 targetFolderId → 空列表', () {
        final json = <String, dynamic>{
          'id': 'sf-new',
          'name': '新版',
          'regexPattern': '',
          'regexTarget': 'collectionName',
          'fileTypeFilter': 'all',
        };
        final folder = SmartFolder.fromJson(json);
        expect(folder.targetFolderIds, isEmpty);
      });

      test('fromJson 对未知 regexTarget 值降级为 collectionName', () {
        final json = <String, dynamic>{
          'id': 'sf-x',
          'name': 'X',
          'regexPattern': '',
          'regexTarget': '__unknown__',
          'fileTypeFilter': 'all',
        };
        final folder = SmartFolder.fromJson(json);
        expect(folder.regexTarget, SmartFolderRegexTarget.collectionName);
      });

      test('fromJson 对未知 fileTypeFilter 值降级为 all', () {
        final json = <String, dynamic>{
          'id': 'sf-y',
          'name': 'Y',
          'regexPattern': '',
          'regexTarget': 'collectionName',
          'fileTypeFilter': '__unknown__',
        };
        final folder = SmartFolder.fromJson(json);
        expect(folder.fileTypeFilter, SmartFolderFileType.all);
      });
    });

    // ── copyWith ────────────────────────────────────────────────────────────

    group('copyWith', () {
      const base = SmartFolder(
        id: 'id',
        name: 'name',
        regexPattern: 'pat',
        regexTarget: SmartFolderRegexTarget.fileName,
        fileTypeFilter: SmartFolderFileType.images,
        targetFolderIds: ['f1'],
      );

      test('不传参时所有字段保持不变', () {
        final copy = base.copyWith();
        expect(copy.id, base.id);
        expect(copy.name, base.name);
        expect(copy.regexPattern, base.regexPattern);
        expect(copy.regexTarget, base.regexTarget);
        expect(copy.fileTypeFilter, base.fileTypeFilter);
        expect(copy.targetFolderIds, base.targetFolderIds);
      });

      test('仅覆盖指定字段', () {
        final copy = base.copyWith(name: 'new-name', regexPattern: r'\w+');
        expect(copy.id, base.id);
        expect(copy.name, 'new-name');
        expect(copy.regexPattern, r'\w+');
        expect(copy.regexTarget, base.regexTarget);
        expect(copy.fileTypeFilter, base.fileTypeFilter);
      });
    });

    // ── matchesFileNames ────────────────────────────────────────────────────

    group('matchesFileNames', () {
      const folder = SmartFolder(
        id: 'sf',
        name: 'Test',
        regexPattern: r'IMG_\d+',
        regexTarget: SmartFolderRegexTarget.fileName,
        fileTypeFilter: SmartFolderFileType.all,
      );

      test('文件名匹配正则时返回 true', () {
        expect(folder.matchesFileNames(['/photos/IMG_1234.jpg']), isTrue);
      });

      test('文件名不匹配正则时返回 false', () {
        expect(folder.matchesFileNames(['/photos/video.mp4']), isFalse);
      });

      test('空路径列表返回 false', () {
        expect(folder.matchesFileNames([]), isFalse);
      });

      test('空 regexPattern 时任何文件名都匹配', () {
        const noPattern = SmartFolder(
          id: 'sf2',
          name: 'No pattern',
          regexPattern: '',
          regexTarget: SmartFolderRegexTarget.fileName,
          fileTypeFilter: SmartFolderFileType.all,
        );
        expect(noPattern.matchesFileNames(['/any/file.jpg']), isTrue);
      });

      test('多文件：只要存在一个匹配即返回 true', () {
        expect(folder.matchesFileNames(['/a/no_match.jpg', '/b/IMG_999.png']), isTrue);
      });

      test('fileTypeFilter=images 过滤掉视频文件', () {
        const imgOnly = SmartFolder(
          id: 'sf3',
          name: 'Images only',
          regexPattern: '',
          regexTarget: SmartFolderRegexTarget.fileName,
          fileTypeFilter: SmartFolderFileType.images,
        );
        expect(imgOnly.matchesFileNames(['/photos/pic.jpg']), isTrue);
        expect(imgOnly.matchesFileNames(['/videos/movie.mp4']), isFalse);
      });

      test('fileTypeFilter=videos 过滤掉图片文件', () {
        const vidOnly = SmartFolder(
          id: 'sf4',
          name: 'Videos only',
          regexPattern: '',
          regexTarget: SmartFolderRegexTarget.fileName,
          fileTypeFilter: SmartFolderFileType.videos,
        );
        expect(vidOnly.matchesFileNames(['/videos/clip.mp4']), isTrue);
        expect(vidOnly.matchesFileNames(['/photos/pic.png']), isFalse);
      });

      test('大小写不敏感匹配', () {
        const caseFolder = SmartFolder(
          id: 'sf5',
          name: 'Case',
          regexPattern: 'img_',
          regexTarget: SmartFolderRegexTarget.fileName,
          fileTypeFilter: SmartFolderFileType.all,
        );
        // regex uses caseSensitive: false
        expect(caseFolder.matchesFileNames(['/IMG_001.jpg']), isTrue);
        expect(caseFolder.matchesFileNames(['/img_002.JPG']), isTrue);
      });
    });

    // ── Enum labels ─────────────────────────────────────────────────────────

    group('SmartFolderRegexTarget.label', () {
      test('collectionName → 集合名称', () {
        expect(SmartFolderRegexTarget.collectionName.label, '集合名称');
      });

      test('fileName → 文件名称', () {
        expect(SmartFolderRegexTarget.fileName.label, '文件名称');
      });
    });

    group('SmartFolderFileType.label', () {
      test('all → 全部', () {
        expect(SmartFolderFileType.all.label, '全部');
      });

      test('images → 仅图片', () {
        expect(SmartFolderFileType.images.label, '仅图片');
      });

      test('videos → 仅视频', () {
        expect(SmartFolderFileType.videos.label, '仅视频');
      });
    });
  });

  // ── 无效正则容错 ────────────────────────────────────────────────────────

  group('无效正则容错', () {
    test('matchesFileNames 遇到无效正则时不抛出异常，返回 true（容错）', () {
      const folder = SmartFolder(
        id: 'sf-bad',
        name: 'Invalid Regex',
        regexPattern: r'[invalid regex (unclosed bracket',
        regexTarget: SmartFolderRegexTarget.fileName,
        fileTypeFilter: SmartFolderFileType.all,
      );
      // 容错逻辑：catch (_) { return true; }
      expect(() => folder.matchesFileNames(['/photos/IMG_001.jpg']), returnsNormally);
      expect(folder.matchesFileNames(['/photos/IMG_001.jpg']), isTrue);
    });

    test('空文件路径列表时 matchesFileNames 始终返回 false', () {
      const folder = SmartFolder(
        id: 'sf-empty',
        name: 'EmptyList',
        regexPattern: '.*',
        regexTarget: SmartFolderRegexTarget.fileName,
        fileTypeFilter: SmartFolderFileType.all,
      );
      expect(folder.matchesFileNames([]), isFalse);
    });
  });

  // ── targetFolderIds 范围过滤 ─────────────────────────────────────────────

  group('targetFolderIds 序列化与空值语义', () {
    test('targetFolderIds 非空时正确序列化', () {
      const folder = SmartFolder(
        id: 'sf-scope',
        name: 'Scoped',
        regexPattern: '',
        targetFolderIds: ['folder-1', 'folder-2', 'folder-3'],
      );
      final json = folder.toJson();
      final restored = SmartFolder.fromJson(json);
      expect(restored.targetFolderIds, ['folder-1', 'folder-2', 'folder-3']);
    });

    test('targetFolderIds 为空列表时序列化后仍为空', () {
      const folder = SmartFolder(
        id: 'sf-all',
        name: 'All Folders',
        regexPattern: '',
        targetFolderIds: [],
      );
      final json = folder.toJson();
      final restored = SmartFolder.fromJson(json);
      expect(restored.targetFolderIds, isEmpty);
    });
  });

  // ── Unicode 正则匹配 ────────────────────────────────────────────────────

  group('Unicode 正则匹配', () {
    test('中文文件名可正确匹配', () {
      const folder = SmartFolder(
        id: 'sf-zh',
        name: 'Chinese',
        regexPattern: '风景',
        regexTarget: SmartFolderRegexTarget.fileName,
        fileTypeFilter: SmartFolderFileType.all,
      );
      expect(folder.matchesFileNames(['/photos/风景照片.jpg']), isTrue);
      expect(folder.matchesFileNames(['/photos/portrait.jpg']), isFalse);
    });

    test('日文/韩文文件名可正确匹配', () {
      const folder = SmartFolder(
        id: 'sf-jp',
        name: 'Japanese',
        regexPattern: r'写真',
        regexTarget: SmartFolderRegexTarget.fileName,
        fileTypeFilter: SmartFolderFileType.all,
      );
      expect(folder.matchesFileNames(['/gallery/写真001.png']), isTrue);
    });
  });
}
