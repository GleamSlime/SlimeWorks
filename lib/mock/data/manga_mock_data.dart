import 'dart:convert';
import 'dart:typed_data';

import 'package:slime_works/mock/mock_assets.dart';

/// Manga 演示数据：列表、详情、章节、图片、评论、收藏与历史。
class MockMangaData {
  MockMangaData._() {
    _seed();
  }

  static final MockMangaData instance = MockMangaData._();

  final Set<String> favourites = <String>{'mc-1', 'mc-4', 'mc-9'};
  final Set<String> likes = <String>{'mc-2'};
  bool _loggedIn = false;
  String _historyJson = '[]';

  static const List<String> _titles = [
    '星海旅人',
    '异世界食堂',
    '雨巷侦探',
    '机械之心',
    '竹林剑客',
    '末日花园',
    '猫与旧书店',
    '深海列车',
    '月下棋局',
    '夏日回声',
    '雾中灯塔',
    '纸鸢计划',
    '北境邮差',
    '玻璃温室',
    '午夜电台',
    '云端牧场',
    '无声剧场',
    '第七封信',
    '荒原骑士',
    '潮汐之间',
    '银盐时代',
    '飞鸟集',
    '雪国来客',
    '浮岛纪年',
    '长街灯火',
    '海上钢琴师',
    '森林议会',
    '时区之外',
    '拾光者',
    '远方来信',
  ];

  static const List<String> _authors = ['青木', '白川', '南野', '三浦', '杉田'];

  static const List<String> _categories = [
    '全部',
    '热血',
    '恋爱',
    '科幻',
    '奇幻',
    '悬疑',
    '日常',
    '治愈',
    '历史',
    '校园',
  ];

  void _seed() {
    // 收藏集合稳含前三本
    favourites.addAll(['mc-1', 'mc-4', 'mc-9']);
  }

  bool get loggedIn => _loggedIn;

  void login() => _loggedIn = true;
  void logout() => _loggedIn = false;

  String get userJson => jsonEncode({
    'user': {
      '_id': 'mock-user-1',
      'email': 'demo@slime.local',
      'name': '演示用户',
      'title': '路过的旅人',
      'status': 'active',
      'level': 12,
      'exp': 3200,
      'isPunched': false,
      'avatar': {'originalName': 'a.png', 'path': 'avatar.png', 'fileServer': ''},
    },
  });

  String comicJson(int i) {
    final id = 'mc-${i + 1}';
    final title = _titles[i % _titles.length];
    final category = _categories[1 + i % 9];
    return jsonEncode({
      '_id': id,
      'title': title,
      'author': _authors[i % _authors.length],
      'chineseTeam': '演示汉化组',
      'description': '《$title》是一部围绕日常与冒险展开的演示漫画，用于离线展示完整阅读流程。',
      'thumb': {
        'originalName': 'cover.jpg',
        'path': 'mock/$id.jpg',
        'fileServer': '',
      },
      'categories': [category],
      'tags': ['演示', category, i.isEven ? '连载中' : '已完结'],
      'epsCount': epsCount(i),
      'pagesCount': epsCount(i) * 9,
      'totalLikes': 120 + i * 37,
      'totalViews': 3200 + i * 512,
      'commentsCount': 24 + i,
      'finished': i % 3 == 0,
      'isLiked': likes.contains(id),
      'isFavourite': favourites.contains(id),
      'updated_at': '2025-0${1 + i % 9}-1${i % 9}',
      'created_at': '2024-0${1 + i % 9}-0${1 + i % 9}',
      '_creator': {
        '_id': 'creator-${i % 5}',
        'name': _authors[i % _authors.length],
        'avatar': {
          'originalName': 'avatar.png',
          'path': 'mock/avatar.png',
          'fileServer': '',
        },
      },
    });
  }

  int epsCount(int i) => 14 + (i % 5) * 8;

  Map<String, dynamic> comicMap(int i) =>
      jsonDecode(comicJson(i)) as Map<String, dynamic>;

  String collectionsJson() => jsonEncode({
    'collections': [
      {
        'title': '编辑精选',
        'comics': List.generate(6, comicJson),
      },
      {
        'title': '本周热门',
        'comics': List.generate(6, (i) => comicJson(6 + i)),
      },
      {
        'title': '新作上架',
        'comics': List.generate(6, (i) => comicJson(12 + i)),
      },
    ],
  });

  String randomJson() => jsonEncode(List.generate(10, (i) => comicMap(20 + i)));

  String categoriesJson() => jsonEncode({
    'categories': [
      for (final c in _categories)
        {
          'title': c,
          'active': true,
          'thumb': {
            'originalName': 'cat.png',
            'path': 'mock/cat.png',
            'fileServer': '',
          },
        },
    ],
  });

  String keywordsJson() => jsonEncode({
    'keywords': ['星海', '食堂', '侦探', '机械', '治愈', '校园', '悬疑'],
  });

  String categoryComicsJson(String category, int page) {
    var list = List<int>.generate(30, (i) => i);
    if (category != '全部') {
      list = list.where((i) => _categories[1 + i % 9] == category).toList();
    }
    return _pagedComics(list, page, limit: 20);
  }

  String searchJson(String keyword, int page) {
    final key = keyword.trim();
    final list = List<int>.generate(30, (i) => i).where((i) {
      final title = _titles[i % _titles.length];
      return key.isEmpty || title.contains(key);
    }).toList();
    return _pagedComics(list, page, limit: 20);
  }

  String _pagedComics(List<int> indexes, int page, {required int limit}) {
    final safePage = page < 1 ? 1 : page;
    final start = (safePage - 1) * limit;
    final slice = indexes.skip(start).take(limit).toList();
    final total = indexes.length;
    return jsonEncode({
      'comics': {
        'docs': slice.map(comicMap).toList(),
        'total': total,
        'limit': limit,
        'page': safePage,
        'pages': (total / limit).ceil().clamp(1, 999),
      },
    });
  }

  String rankingsJson(String timeType) {
    final list = List<int>.generate(20, (i) => i)
      ..sort((a, b) => (b * 31 % 97).compareTo(a * 31 % 97));
    return jsonEncode({'comics': list.map(comicMap).toList()});
  }

  String detailJson(String comicId) {
    final i = _indexOf(comicId);
    return jsonEncode({'comic': comicMap(i)});
  }

  String recommendationsJson(String comicId) {
    final i = _indexOf(comicId);
    return jsonEncode({
      'comics': List.generate(6, (k) => comicMap((i + k + 5) % 30)),
    });
  }

  String epsJson(String comicId, int page) {
    final i = _indexOf(comicId);
    return jsonEncode({
      'eps': {
        'docs': epsDocs(i, page),
        'total': epsCount(i),
        'limit': 20,
        'page': page,
        'pages': (epsCount(i) / 20).ceil(),
      },
    });
  }

  List<Map<String, dynamic>> epsDocs(int i, int page) {
    final total = epsCount(i);
    final start = (page - 1) * 20;
    final end = (start + 20).clamp(0, total);
    return [
      for (var k = start; k < end; k++)
        {
          '_id': 'eps-${i + 1}-$k',
          'title': '第 ${k + 1} 话',
          'order': k + 1,
          'updatedAt': '2025-03-${(k % 27 + 1).toString().padLeft(2, '0')}',
        },
    ];
  }

  String pagesJson(String comicId, int epsOrder, int page) {
    const limit = 20;
    const total = 9;
    final start = (page - 1) * limit;
    final end = (start + limit).clamp(0, total);
    return jsonEncode({
      'pages': {
        'docs': [
          for (var k = start; k < end; k++)
            {
              '_id': 'page-$comicId-$epsOrder-$k',
              'media': {
                'originalName': 'p${k + 1}.jpg',
                'path': 'mock/$comicId/$epsOrder/$k.jpg',
                'fileServer': '',
              },
            },
        ],
        'total': total,
        'limit': limit,
        'page': page,
        'pages': 1,
      },
    });
  }

  String favouritesJson(int page) {
    final ids = favourites.toList()..sort();
    final list = ids.map((id) => _indexOf(id)).toList();
    return _pagedComics(list, page, limit: 20);
  }

  String toggleFavourite(String comicId) {
    final added = favourites.add(comicId);
    if (!added) favourites.remove(comicId);
    return jsonEncode({'action': added ? 'favourite' : 'unfavourite'});
  }

  String toggleLike(String comicId) {
    final added = likes.add(comicId);
    if (!added) likes.remove(comicId);
    return jsonEncode({'action': added ? 'like' : 'unlike'});
  }

  String commentsJson(String comicId, int page) {
    const total = 23;
    const limit = 10;
    final start = (page - 1) * limit;
    final end = (start + limit).clamp(0, total);
    return jsonEncode({
      'comments': {
        'docs': [
          for (var k = start; k < end; k++)
            {
              '_id': 'comment-$comicId-$k',
              'content': k == 0
                  ? '画风和分镜都很舒服，追了！'
                  : '第 ${k + 1} 条演示评论：剧情推进自然，期待下一话。',
              'totalComments': k % 4,
              'likesCount': 3 + k,
              'isLiked': false,
              'createdAt': '2025-03-${(k % 27 + 1).toString().padLeft(2, '0')}T12:00:00Z',
              '_user': {
                '_id': 'u-$k',
                'name': '读者${k + 1}',
                'title': k.isEven ? 'lv.${3 + k % 8}' : null,
                'level': 1 + k % 9,
                'avatar': {
                  'originalName': 'u.png',
                  'path': 'mock/u.png',
                  'fileServer': '',
                },
              },
            },
        ],
        'total': total,
        'limit': limit,
        'page': page,
        'pages': (total / limit).ceil(),
      },
    });
  }

  String commentChildrenJson(String commentId, int page) => jsonEncode({
    'comments': {
      'docs': [
        {
          '_id': 'child-$commentId-1',
          'content': '同感，尤其是夜景那几格。',
          'totalComments': 0,
          'likesCount': 2,
          'isLiked': false,
          'createdAt': '2025-03-21T08:30:00Z',
          '_user': {'_id': 'u-child', 'name': '楼中小伙伴', 'level': 5},
        },
      ],
      'total': 1,
      'limit': 10,
      'page': page,
      'pages': 1,
    },
  });

  int _indexOf(String comicId) {
    final raw = int.tryParse(comicId.replaceAll('mc-', '')) ?? 1;
    return (raw - 1).clamp(0, 29);
  }

  Uint8List imageBytes(String url, {int width = 720, int height = 1080}) =>
      MockAssets.pngBytes(
        url.isEmpty ? 'manga-page' : url,
        width: width,
        height: height,
        style: 2,
      );

  String loadHistory() => _historyJson;

  void saveHistory(String json) => _historyJson = json;

  void clearHistory() => _historyJson = '[]';
}
