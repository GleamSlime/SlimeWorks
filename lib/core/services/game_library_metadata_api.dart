import 'package:dio/dio.dart';

import 'package:slime_works/core/utils/logger.dart';

final Loggers _metadataApiLogger = Loggers(name: '游戏库元数据API');

class GameLibraryMetadataApi {
  GameLibraryMetadataApi()
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
          sendTimeout: const Duration(seconds: 5),
          headers: <String, dynamic>{'User-Agent': 'SlimeWorks/1.0', 'Accept': 'application/json'},
        ),
      ) {
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
}
