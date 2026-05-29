import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/pages/manga/models/manga_models.dart';
import 'package:slime_works/pages/manga/models/manga_download_model.dart';

void main() {
  group('MangaImage', () {
    test('fromJson 正常解析', () {
      final img = MangaImage.fromJson({
        'originalName': '001.jpg',
        'path': '/static/001.jpg',
        'fileServer': 'https://cdn.example.com',
      });
      expect(img.originalName, '001.jpg');
      expect(img.path, '/static/001.jpg');
      expect(img.fileServer, 'https://cdn.example.com');
    });

    test('fromJson 缺省字段降级为空字符串', () {
      final img = MangaImage.fromJson({});
      expect(img.originalName, '');
      expect(img.path, '');
      expect(img.fileServer, '');
    });

    test('fullUrl 拼接正确', () {
      final img = MangaImage(
        originalName: 'a.jpg',
        path: 'abc/001.jpg',
        fileServer: 'https://cdn.example.com',
      );
      expect(img.fullUrl, 'https://cdn.example.com/static/abc/001.jpg');
    });

    test('fullUrl fileServer 尾部有斜杠时产生双斜杠', () {
      final img = MangaImage(originalName: '', path: 'x.png', fileServer: 'https://host/');
      expect(img.fullUrl, 'https://host//static/x.png');
    });
  });

  group('MangaComic', () {
    test('fromJson 正常解析', () {
      final json =
          jsonDecode(
                '{"_id":"c-001","title":"测试漫画","author":"作者A",'
                '"thumb":{"originalName":"thumb.jpg","path":"/thumb.jpg","fileServer":"https://cdn.example.com"},'
                '"categories":["冒险"],"tags":["热血"],"epsCount":10,"pagesCount":200,'
                '"totalLikes":50,"finished":true}',
              )
              as Map<String, dynamic>;
      final comic = MangaComic.fromJson(json);
      expect(comic.id, 'c-001');
      expect(comic.title, '测试漫画');
      expect(comic.author, '作者A');
      expect(comic.likesCount, 50);
      expect(comic.finished, isTrue);
      expect(comic.categories, ['冒险']);
    });

    test('fromJson 缺省字段使用默认值', () {
      final json =
          jsonDecode(
                '{"_id":"c-002","title":"简略","thumb":{},'
                '"categories":[],"tags":[],"epsCount":0,"pagesCount":0,'
                '"likesCount":0,"finished":false}',
              )
              as Map<String, dynamic>;
      final comic = MangaComic.fromJson(json);
      expect(comic.author, isNull);
      expect(comic.viewsCount, 0);
      expect(comic.isLiked, isNull);
    });

    test('fromJson likesCount 兼容 totalLikes 字段', () {
      final json =
          jsonDecode(
                '{"_id":"c-003","title":"T","thumb":{},'
                '"categories":[],"tags":[],"epsCount":0,"pagesCount":0,'
                '"totalLikes":99,"finished":false}',
              )
              as Map<String, dynamic>;
      final comic = MangaComic.fromJson(json);
      expect(comic.likesCount, 99);
    });
  });

  group('MangaEps', () {
    test('fromJson 正常解析', () {
      final eps = MangaEps.fromJson({
        '_id': 'eps-001',
        'title': '第1话',
        'order': 1,
        'updatedAt': '2024-01-01',
      });
      expect(eps.id, 'eps-001');
      expect(eps.title, '第1话');
      expect(eps.order, 1);
    });

    test('fromJson 缺省字段降级', () {
      final eps = MangaEps.fromJson({});
      expect(eps.id, '');
      expect(eps.order, 1);
    });
  });

  group('MangaPagination', () {
    test('fromJson 正常解析', () {
      final p = MangaPagination.fromJson({'total': 100, 'limit': 20, 'page': 3, 'pages': 5});
      expect(p.total, 100);
      expect(p.limit, 20);
      expect(p.page, 3);
      expect(p.pages, 5);
    });

    test('fromJson 缺省字段使用默认值', () {
      final p = MangaPagination.fromJson({});
      expect(p.total, 0);
      expect(p.limit, 20);
      expect(p.page, 1);
      expect(p.pages, 1);
    });
  });

  group('MangaComicList', () {
    test('fromJson 嵌套 comics.docs 格式', () {
      final json =
          jsonDecode(
                '{"comics":{"docs":[{"_id":"c-1","title":"A",'
                '"thumb":{},"categories":[],"tags":[],"epsCount":0,"pagesCount":0,'
                '"likesCount":0,"finished":false}],"total":1,"limit":20,"page":1,"pages":1}}',
              )
              as Map<String, dynamic>;
      final list = MangaComicList.fromJson(json);
      expect(list.comics.length, 1);
      expect(list.comics[0].id, 'c-1');
      expect(list.pagination.total, 1);
    });

    test('fromJson 空列表', () {
      final json =
          jsonDecode('{"comics":{"docs":[],"total":0,"limit":20,"page":1,"pages":0}}')
              as Map<String, dynamic>;
      final list = MangaComicList.fromJson(json);
      expect(list.comics, isEmpty);
      expect(list.pagination.total, 0);
    });
  });

  group('MangaUser', () {
    test('fromJson 嵌套 user 字段', () {
      final user = MangaUser.fromJson({
        'user': {
          '_id': 'u-001',
          'email': 'test@test.com',
          'name': 'Tester',
          'title': 'member',
          'status': 'active',
          'level': 3,
          'exp': 100,
          'isPunched': true,
        },
      });
      expect(user.id, 'u-001');
      expect(user.name, 'Tester');
      expect(user.isPunched, isTrue);
    });

    test('fromJson 扁平格式', () {
      final user = MangaUser.fromJson({
        '_id': 'u-002',
        'email': '',
        'name': 'Flat',
        'title': '',
        'status': '',
        'level': 0,
        'exp': 0,
        'isPunched': false,
      });
      expect(user.id, 'u-002');
      expect(user.isPunched, isFalse);
    });
  });

  group('MangaSortOrder', () {
    test('枚举值正确', () {
      expect(MangaSortOrder.dateDescending.value, 'dd');
      expect(MangaSortOrder.dateAscending.value, 'da');
      expect(MangaSortOrder.likeDescending.value, 'ld');
      expect(MangaSortOrder.viewDescending.value, 'vd');
    });
  });

  group('MangaCategory', () {
    test('fromJson 正常解析', () {
      final cat = MangaCategory.fromJson({'title': '冒险', 'active': true});
      expect(cat.title, '冒险');
      expect(cat.active, isTrue);
      expect(cat.thumb, isNull);
    });

    test('fromJson 缺省 active 默认 true', () {
      final cat = MangaCategory.fromJson({'title': '日常'});
      expect(cat.active, isTrue);
    });
  });

  group('MangaComment', () {
    test('fromJson 正常解析', () {
      final comment = MangaComment.fromJson({
        '_id': 'cm-001',
        'content': '好看！',
        'totalComments': 0,
        'likesCount': 5,
        'createdAt': '2024-01-01',
        '_user': {'_id': 'u-001', 'name': 'User1'},
      });
      expect(comment.id, 'cm-001');
      expect(comment.content, '好看！');
      expect(comment.user.name, 'User1');
    });
  });

  group('MangaDownloadEpsInfo', () {
    test('toJson/fromJson 往返一致', () {
      final eps = MangaDownloadEpsInfo(
        epsOrder: 1,
        epsTitle: '第1话',
        totalPages: 20,
        downloadedPages: 10,
        status: MangaDownloadStatus.downloading,
      );
      final json = eps.toJson();
      final restored = MangaDownloadEpsInfo.fromJson(json);
      expect(restored.epsOrder, 1);
      expect(restored.epsTitle, '第1话');
      expect(restored.totalPages, 20);
      expect(restored.downloadedPages, 10);
      expect(restored.status, MangaDownloadStatus.downloading);
    });

    test('progress 计算正确', () {
      final eps = MangaDownloadEpsInfo(
        epsOrder: 1,
        epsTitle: '',
        totalPages: 20,
        downloadedPages: 5,
      );
      expect(eps.progress, closeTo(0.25, 0.001));
    });

    test('progress totalPages 为 0 时返回 0', () {
      final eps = MangaDownloadEpsInfo(epsOrder: 1, epsTitle: '', totalPages: 0);
      expect(eps.progress, 0.0);
    });

    test('isCompleted 仅在 completed 状态时为 true', () {
      final waiting = MangaDownloadEpsInfo(epsOrder: 1, epsTitle: '');
      expect(waiting.isCompleted, isFalse);
      final done = MangaDownloadEpsInfo(
        epsOrder: 1,
        epsTitle: '',
        status: MangaDownloadStatus.completed,
      );
      expect(done.isCompleted, isTrue);
    });

    test('fromJson 未知 status 降级为 waiting', () {
      final eps = MangaDownloadEpsInfo.fromJson({
        'epsOrder': 1,
        'epsTitle': '',
        'status': '__unknown__',
      });
      expect(eps.status, MangaDownloadStatus.waiting);
    });
  });

  group('MangaDownloadEntry', () {
    test('toJson/fromJson 往返一致', () {
      final entry = MangaDownloadEntry(
        comicId: 'c-001',
        comicTitle: '测试漫画',
        episodes: {
          1: MangaDownloadEpsInfo(
            epsOrder: 1,
            epsTitle: '第1话',
            totalPages: 10,
            downloadedPages: 10,
            status: MangaDownloadStatus.completed,
          ),
          2: MangaDownloadEpsInfo(
            epsOrder: 2,
            epsTitle: '第2话',
            status: MangaDownloadStatus.waiting,
          ),
        },
        createdAt: DateTime(2024, 1, 1),
      );
      final json = entry.toJson();
      final restored = MangaDownloadEntry.fromJson(json);
      expect(restored.comicId, 'c-001');
      expect(restored.comicTitle, '测试漫画');
      expect(restored.episodes.length, 2);
      expect(restored.episodes[1]!.status, MangaDownloadStatus.completed);
    });

    test('isFullyComplete 全部完成时为 true', () {
      final entry = MangaDownloadEntry(
        comicId: 'c-002',
        comicTitle: '完成',
        episodes: {
          1: MangaDownloadEpsInfo(
            epsOrder: 1,
            epsTitle: '',
            status: MangaDownloadStatus.completed,
          ),
        },
      );
      expect(entry.isFullyComplete, isTrue);
    });

    test('isFullyComplete 部分完成时为 false', () {
      final entry = MangaDownloadEntry(
        comicId: 'c-003',
        comicTitle: '未完成',
        episodes: {
          1: MangaDownloadEpsInfo(
            epsOrder: 1,
            epsTitle: '',
            status: MangaDownloadStatus.completed,
          ),
          2: MangaDownloadEpsInfo(epsOrder: 2, epsTitle: '', status: MangaDownloadStatus.waiting),
        },
      );
      expect(entry.isFullyComplete, isFalse);
    });

    test('isFullyComplete 无章节时为 false', () {
      final entry = MangaDownloadEntry(comicId: 'c-004', comicTitle: '空');
      expect(entry.isFullyComplete, isFalse);
    });

    test('completedEps 计算正确', () {
      final entry = MangaDownloadEntry(
        comicId: 'c-005',
        comicTitle: '',
        episodes: {
          1: MangaDownloadEpsInfo(
            epsOrder: 1,
            epsTitle: '',
            status: MangaDownloadStatus.completed,
          ),
          2: MangaDownloadEpsInfo(
            epsOrder: 2,
            epsTitle: '',
            status: MangaDownloadStatus.downloading,
          ),
          3: MangaDownloadEpsInfo(
            epsOrder: 3,
            epsTitle: '',
            status: MangaDownloadStatus.completed,
          ),
        },
      );
      expect(entry.completedEps, 2);
      expect(entry.totalEps, 3);
    });

    test('encodeAll/decodeAll 往返一致', () {
      final entries = {
        'c-001': MangaDownloadEntry(
          comicId: 'c-001',
          comicTitle: '漫画A',
          createdAt: DateTime(2024, 6, 15),
        ),
      };
      final jsonStr = MangaDownloadEntry.encodeAll(entries);
      final restored = MangaDownloadEntry.decodeAll(jsonStr);
      expect(restored.length, 1);
      expect(restored['c-001']!.comicTitle, '漫画A');
    });
  });
}
