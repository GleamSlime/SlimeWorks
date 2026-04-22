import 'dart:io';

import 'package:dio/dio.dart';

import 'package:slime_works/core/utils/logger.dart';

final Loggers _metadataApiLogger = Loggers(name: '游戏库元数据API');

class GameLibraryMetadataApi {
  GameLibraryMetadataApi()
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 60),
          sendTimeout: const Duration(seconds: 60),
          headers: <String, dynamic>{'User-Agent': 'SlimeWorks/1.0', 'Accept': 'application/json'},
        ),
      ) {
    // 检测系统代理
    final String? proxyUrl = _detectSystemProxy();
    if (proxyUrl != null) {
      (_dio.httpClientAdapter as dynamic).onHttpClientCreate = (HttpClient client) {
        client.findProxy = (Uri uri) => 'PROXY $proxyUrl';
        client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
        return client;
      };
    }
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          _metadataApiLogger.info('[REQ] ${options.method} ${options.uri}');
          handler.next(options);
        },
        onResponse: (Response<dynamic> response, ResponseInterceptorHandler handler) {
          _metadataApiLogger.info('[RES] ${response.statusCode} ${response.requestOptions.uri}');
          handler.next(response);
        },
        onError: (DioException error, ErrorInterceptorHandler handler) {
          _metadataApiLogger.info(
            '[ERR] ${error.requestOptions.method} ${error.requestOptions.uri} -> ${error.message}',
          );
          handler.next(error);
        },
      ),
    );
  }

  final Dio _dio;

  Future<Map<String, dynamic>> searchSteam(String query) async {
    final Response<dynamic> searchResp = await _dio.get<dynamic>(
      'https://store.steampowered.com/api/storesearch/',
      queryParameters: <String, dynamic>{'term': query, 'l': 'schinese', 'cc': 'cn'},
      options: Options(
        headers: <String, dynamic>{
          'Referer': 'https://store.steampowered.com/',
          'Origin': 'https://store.steampowered.com',
        },
      ),
    );

    return _asMap(searchResp.data);
  }

  Future<Map<String, dynamic>> getSteamAppDetails(String appId) async {
    final Response<dynamic> detailResp = await _dio.get<dynamic>(
      'https://store.steampowered.com/api/appdetails',
      queryParameters: <String, dynamic>{'appids': appId, 'l': 'schinese', 'cc': 'cn'},
      options: Options(
        headers: <String, dynamic>{
          'Referer': 'https://store.steampowered.com/app/$appId/',
          'Origin': 'https://store.steampowered.com',
        },
      ),
    );

    return _asMap(detailResp.data);
  }

  Future<Map<String, dynamic>> searchVndb(String query) async {
    final Response<dynamic> resp = await _dio.post<dynamic>(
      'https://api.vndb.org/kana/vn',
      data: <String, dynamic>{
        'filters': <dynamic>['search', '=', query],
        'fields':
            'id,title,image.url,description,rating,released,developers.name,titles.lang,titles.title,titles.latin,titles.main,titles.official',
      },
      options: Options(headers: <String, dynamic>{'Content-Type': 'application/json'}),
    );

    return _asMap(resp.data);
  }

  Future<Map<String, dynamic>> searchBangumi(String query) async {
    final String encodedQuery = Uri.encodeComponent(query);
    final Response<dynamic> searchResp = await _dio.get<dynamic>(
      'https://api.bgm.tv/search/subject/$encodedQuery',
      queryParameters: <String, dynamic>{'type': 4, 'responseGroup': 'medium'},
    );

    return _asMap(searchResp.data);
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return <String, dynamic>{};
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 高层搜索接口（供 GameLibraryService 调用）
  // ───────────────────────────────────────────────────────────────────────────

  /// 用游戏名在 Steam/VNDB/Bangumi 中搜索元数据，返回第一个命中结果。
  Future<GameSearchMetadata?> searchByName(String rawName) async {
    final List<String> queries = _buildSearchCandidates(rawName);
    if (queries.isEmpty) return null;

    final List<Future<GameSearchMetadata?> Function(String)> searchers =
        <Future<GameSearchMetadata?> Function(String)>[_searchSteam, _searchVndb, _searchBangumi];

    for (final String query in queries) {
      for (final Future<GameSearchMetadata?> Function(String) searcher in searchers) {
        try {
          final GameSearchMetadata? result = await searcher(query);
          if (result != null) return result;
        } catch (e) {
          _metadataApiLogger.info('元数据搜索失败(query=$query): $e');
        }
      }
    }
    return null;
  }

  Future<GameSearchMetadata?> _searchVndb(String query) async {
    final Map<String, dynamic> root = await searchVndb(query);
    final List<dynamic> results = _asList(root['results']);
    if (results.isEmpty) return null;

    final Map<String, dynamic> first = _asMap(results.first);
    final String title = _pickVndbTitle(first);
    if (title.isEmpty) return null;

    final List<dynamic> developers = _asList(first['developers']);
    final String company = developers
        .map((dynamic e) => _asStr(_asMap(e)['name']))
        .where((String e) => e.isNotEmpty)
        .join(', ');

    return GameSearchMetadata(
      name: title,
      coverUrl: _asStr(_asMap(first['image'])['url']),
      company: company,
      summary: _asStr(first['description']),
      rating: _normalizeTen(_asDouble(first['rating'])),
      releaseDate: _asStr(first['released']),
      source: 'vndb',
      sourceId: _asStr(first['id']),
    );
  }

  Future<GameSearchMetadata?> _searchSteam(String query) async {
    final Map<String, dynamic> searchRoot = await searchSteam(query);
    final List<dynamic> items = _asList(searchRoot['items']);
    if (items.isEmpty) return null;

    final Map<String, dynamic> firstItem = _asMap(items.first);
    final String appId = _asStr(firstItem['id']);
    if (appId.isEmpty) return null;

    final Map<String, dynamic> detailRoot = await getSteamAppDetails(appId);
    final Map<String, dynamic> appRoot = _asMap(detailRoot[appId]);
    if (appRoot['success'] != true) return null;

    final Map<String, dynamic> data = _asMap(appRoot['data']);
    final List<dynamic> developers = _asList(data['developers']);
    final String company = developers
        .map((dynamic e) => e.toString().trim())
        .where((String e) => e.isNotEmpty)
        .join(', ');

    double rating = _asDouble(_asMap(data['metacritic'])['score']);
    if (rating > 0) rating = rating / 10.0;

    final String title = _asStr(data['name']).isEmpty
        ? _asStr(firstItem['name'])
        : _asStr(data['name']);
    if (title.isEmpty) return null;

    final String cover = _asStr(data['header_image']).isEmpty
        ? _asStr(firstItem['tiny_image'])
        : _asStr(data['header_image']);

    return GameSearchMetadata(
      name: title,
      coverUrl: cover,
      company: company,
      summary: _asStr(data['short_description']),
      rating: _normalizeTen(rating),
      releaseDate: _asStr(_asMap(data['release_date'])['date']),
      source: 'steam',
      sourceId: appId,
    );
  }

  Future<GameSearchMetadata?> _searchBangumi(String query) async {
    final Map<String, dynamic> root = await searchBangumi(query);
    final List<dynamic> list = _asList(root['list']);
    if (list.isEmpty) return null;

    final Map<String, dynamic> first = _asMap(list.first);
    final String nameCn = _asStr(first['name_cn']);
    final String name = nameCn.isEmpty ? _asStr(first['name']) : nameCn;
    if (name.isEmpty) return null;

    final Map<String, dynamic> images = _asMap(first['images']);
    final String cover = _asStr(images['large']).isEmpty
        ? _asStr(images['common'])
        : _asStr(images['large']);

    return GameSearchMetadata(
      name: name,
      coverUrl: cover,
      company: _extractBangumiCompany(_asList(first['infobox'])),
      summary: _asStr(first['summary']),
      rating: _normalizeTen(_asDouble(first['score'])),
      releaseDate: _asStr(first['air_date']),
      source: 'bangumi',
      sourceId: _asStr(first['id']),
    );
  }

  String _pickVndbTitle(Map<String, dynamic> result) {
    final List<dynamic> titles = _asList(result['titles']);
    if (titles.isNotEmpty) {
      final List<Map<String, dynamic>> list = titles.map(_asMap).toList(growable: false);
      list.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
        int score(Map<String, dynamic> item) {
          int v = 0;
          if (item['main'] == true) v += 2;
          if (item['official'] == true) v += 1;
          return v;
        }

        return score(b).compareTo(score(a));
      });
      for (final Map<String, dynamic> t in list) {
        final String title = _asStr(t['title']);
        if (title.isNotEmpty) return title;
        final String latin = _asStr(t['latin']);
        if (latin.isNotEmpty) return latin;
      }
    }
    return _asStr(result['title']);
  }

  String _extractBangumiCompany(List<dynamic> infobox) {
    for (final dynamic raw in infobox) {
      final Map<String, dynamic> item = _asMap(raw);
      final String key = _asStr(item['key']).toLowerCase();
      if (key.contains('开发') ||
          key.contains('制作') ||
          key.contains('厂商') ||
          key.contains('company')) {
        final dynamic value = item['value'];
        if (value is String && value.trim().isNotEmpty) return value.trim();
        if (value is List<dynamic>) {
          final String joined = value
              .map((dynamic e) => _asStr(_asMap(e)['v']))
              .where((String e) => e.isNotEmpty)
              .join(', ');
          if (joined.isNotEmpty) return joined;
        }
      }
    }
    return '';
  }

  List<String> _buildSearchCandidates(String rawName) {
    final Set<String> set = <String>{};
    void add(String v) {
      final String t = v.trim();
      if (t.isNotEmpty) set.add(t);
    }

    final String normalized = _normalize(rawName);
    add(normalized);
    add(rawName);
    add(normalized.replaceAll('-', ' '));
    add(normalized.replaceAll(' ', '-'));
    final List<String> list = set.toList(growable: false);
    list.sort((String a, String b) => b.length.compareTo(a.length));
    return list;
  }

  String _normalize(String rawName) {
    String v = rawName.trim();
    if (v.isEmpty) return '';
    v = v
        .replaceAll(RegExp(r'[\[\(【（].*?[\]\)】）]'), ' ')
        .replaceAll(RegExp(r'[_\.-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (v.length > 80) v = v.substring(0, 80).trim();
    return v;
  }

  List<dynamic> _asList(dynamic value) {
    if (value is List<dynamic>) return value;
    if (value is List) return List<dynamic>.from(value);
    return <dynamic>[];
  }

  String _asStr(dynamic value) {
    if (value == null) return '';
    if (value is String) return value.trim();
    return value.toString().trim();
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(_asStr(value)) ?? 0;
  }

  double _normalizeTen(double score) {
    if (score.isNaN || score.isInfinite || score < 0) return 0;
    if (score > 10) return 10;
    return score;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 系统代理检测
  // ───────────────────────────────────────────────────────────────────────────

  static String? _detectSystemProxy() {
    for (final String key in <String>[
      'HTTPS_PROXY',
      'https_proxy',
      'HTTP_PROXY',
      'http_proxy',
      'ALL_PROXY',
      'all_proxy',
    ]) {
      final String? v = Platform.environment[key];
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }
}

/// 游戏元数据搜索结果
class GameSearchMetadata {
  const GameSearchMetadata({
    required this.name,
    required this.coverUrl,
    required this.company,
    required this.summary,
    required this.rating,
    required this.releaseDate,
    required this.source,
    required this.sourceId,
  });

  final String name;
  final String coverUrl;
  final String company;
  final String summary;
  final double rating;
  final String releaseDate;
  final String source;
  final String sourceId;
}

/// 2DFan 下载页解析结果
class TwodfanDownloadInfo {
  const TwodfanDownloadInfo({required this.fileUrl, required this.description});

  /// 直接下载链接（null 表示未找到）
  final String? fileUrl;

  /// 简介/存档路径说明文本
  final String description;
}
