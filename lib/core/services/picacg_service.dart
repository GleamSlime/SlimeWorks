/// PicACG 服务层
///
/// 封装 Rust FFI 调用，提供高层业务 API
/// 使用 GetIt 注入，全局单例

import 'dart:convert';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/src/rust/api/picacg.dart' as rust;
import 'package:slime_works/pages/picacg/models/picacg_models.dart';
import 'package:slime_works/core/utils/logger.dart';

/// PicACG Token 持久化 Key
const String _kPicacgTokenKey = 'picacg_token';
const String _kPicacgProxyKey = 'picacg_proxy';
const String _kPicacgChannelKey = 'picacg_channel';
const String _kPicacgChannelCustomKey = 'picacg_channel_custom';
const String _kPicacgImageServerKey = 'picacg_image_server';
const String _kPicacgLoginEmailKey = 'picacg_login_email';
const String _kPicacgLoginPasswordKey = 'picacg_login_password';
const String _kPicacgDefaultCdnIp = '104.18.227.172';

/// 分流模式（与原项目 radioButton 对应）
///
/// 原项目分流编号：1=直连, 2=分流2, 3=分流3, 4=CDN分流(自定义IP), 5=JP反代, 6=US反代
enum PicacgChannelMode {
  /// 0/1 — 标准直连（分流1）
  direct(0, '分流1（直连）'),

  /// 2 — 分流2 (IP: 104.21.91.145)
  channel2(2, '分流2'),

  /// 3 — 分流3 (IP: 188.114.98.153)
  channel3(3, '分流3'),

  /// 4 — CDN分流（用户自定义IP）
  cdnIp(4, 'CDN分流'),

  /// 5 — JP 反代（bika-api.jpacg.cc）
  jpProxy(5, 'JP反代分流'),

  /// 6 — US 反代（bika2-api.jpacg.cc）
  usProxy(6, 'US反代分流');

  const PicacgChannelMode(this.value, this.label);
  final int value;
  final String label;

  static PicacgChannelMode fromValue(int v) => PicacgChannelMode.values.firstWhere(
    (e) => e.value == v,
    orElse: () => PicacgChannelMode.direct,
  );
}

/// PicACG 服务
class PicacgService {
  PicacgService._();

  static final PicacgService _instance = PicacgService._();

  factory PicacgService() => _instance;

  /// 是否已登录
  bool _isLoggedIn = false;

  bool get isLoggedIn => _isLoggedIn;

  /// 当前用户信息（登录后缓存）
  PicacgUser? _currentUser;

  PicacgUser? get currentUser => _currentUser;

  final Map<String, Uint8List> _imageCache = {};

  /// 初始化服务（从持久化存储恢复 Token、代理和分流配置）
  Future<void> init() async {
    logger.info('PicACG Service 初始化');
    rust.picacgInit();

    try {
      final prefs = await SharedPreferences.getInstance();

      // 恢复代理配置
      final savedProxy = prefs.getString(_kPicacgProxyKey) ?? '';
      if (savedProxy.isNotEmpty) {
        rust.picacgSetProxy(proxyUrl: savedProxy);
        logger.info('PicACG 恢复代理配置: $savedProxy');
      }

      // 恢复分流配置
      final channelVal = prefs.getInt(_kPicacgChannelKey) ?? 0;
      final channelMode = PicacgChannelMode.fromValue(channelVal);
      final channelCustomRaw = prefs.getString(_kPicacgChannelCustomKey) ?? '';
      final channelCustom = _effectiveCustomIp(channelMode, channelCustomRaw);
      rust.picacgSetChannel(mode: channelVal, custom: channelCustom);
      logger.info('PicACG 恢复分流模式: $channelVal custom=$channelCustom');

      // 恢复图片服务器
      final imageServer = prefs.getString(_kPicacgImageServerKey) ?? '';
      rust.picacgSetImageServer(server: imageServer);

      // 恢复 Token
      final savedToken = prefs.getString(_kPicacgTokenKey) ?? '';
      if (savedToken.isNotEmpty) {
        rust.picacgSetToken(token: savedToken);
        try {
          _currentUser = await getUserProfile();
          _isLoggedIn = true;
          logger.info('PicACG 恢复登录 Token 并加载用户信息成功');
        } catch (e) {
          logger.error('PicACG 恢复登录失败，已清除失效 Token: $e');
          rust.picacgLogout();
          _isLoggedIn = false;
          _currentUser = null;
          await prefs.remove(_kPicacgTokenKey);
        }
      }
    } catch (e) {
      logger.error('PicACG 初始化失败: $e');
    }
  }

  // ==================== 认证 ====================

  /// 登录
  Future<PicacgUser> login(String email, String password) async {
    logger.info('PicACG 登录: $email');

    await saveLoginCredentials(email: email, password: password);

    try {
      // 登录前强制同步一次网络配置，避免 init 未触发时 Rust 侧仍是默认直连。
      await _syncNetworkConfigToRust();
      await rust.picacgLogin(email: email, password: password);
      return _finalizeLoginSuccess();
    } catch (e) {
      logger.error('PicACG 登录失败: $e');
      rethrow;
    }
  }

  /// 登出
  Future<void> logout() async {
    logger.info('PicACG 登出');
    rust.picacgLogout();
    _isLoggedIn = false;
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPicacgTokenKey);
  }

  /// 获取用户信息
  Future<PicacgUser> getUserProfile() async {
    final json = await rust.picacgGetUserProfile();
    final data = jsonDecode(json) as Map<String, dynamic>;
    return PicacgUser.fromJson(data);
  }

  /// 每日签到
  Future<void> punchIn() async {
    logger.info('PicACG 签到');
    await rust.picacgPunchIn();
  }

  // ==================== 配置 ====================

  /// 设置代理
  Future<void> setProxy(String proxyUrl) async {
    rust.picacgSetProxy(proxyUrl: proxyUrl);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPicacgProxyKey, proxyUrl);
    logger.info('PicACG 代理已更新: $proxyUrl');
  }

  /// 保存登录账号密码（无论是否登录成功）
  Future<void> saveLoginCredentials({required String email, required String password}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPicacgLoginEmailKey, email.trim());
    await prefs.setString(_kPicacgLoginPasswordKey, password);
    logger.info('PicACG 已保存登录凭据: email=${email.trim()}');
  }

  /// 获取上次输入的账号密码
  Future<Map<String, String>> getSavedLoginCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'email': prefs.getString(_kPicacgLoginEmailKey) ?? '',
      'password': prefs.getString(_kPicacgLoginPasswordKey) ?? '',
    };
  }

  /// 获取已保存的代理配置
  Future<String> getSavedProxy() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kPicacgProxyKey) ?? '';
  }

  /// 设置分流模式并持久化
  Future<void> setChannel(PicacgChannelMode mode, {String customIp = ''}) async {
    final effectiveCustomIp = _effectiveCustomIp(mode, customIp);
    rust.picacgSetChannel(mode: mode.value, custom: effectiveCustomIp);
    _imageCache.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPicacgChannelKey, mode.value);
    await prefs.setString(_kPicacgChannelCustomKey, effectiveCustomIp);
    logger.info('PicACG 分流模式已更新: ${mode.label}, custom=$effectiveCustomIp');
  }

  /// 获取已保存的分流模式
  Future<PicacgChannelMode> getSavedChannel() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getInt(_kPicacgChannelKey) ?? 0;
    return PicacgChannelMode.fromValue(val);
  }

  /// 获取已保存的自定义 IP
  Future<String> getSavedCustomIp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kPicacgChannelCustomKey) ?? '';
  }

  /// 设置图片服务器并持久化
  Future<void> setImageServer(String server) async {
    rust.picacgSetImageServer(server: server);
    _imageCache.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPicacgImageServerKey, server);
    logger.info('PicACG 图片服务器已更新: $server');
  }

  String buildImageUrl(PicacgImage image) {
    return rust.picacgBuildImageUrl(fileServer: image.fileServer, path: image.path);
  }

  Future<Uint8List> fetchImageBytes(PicacgImage image) async {
    final key = buildImageUrl(image);
    final cached = _imageCache[key];
    if (cached != null) {
      return cached;
    }
    final bytes = await rust.picacgFetchImage(fileServer: image.fileServer, path: image.path);
    _imageCache[key] = bytes;
    return bytes;
  }

  /// 获取已保存的图片服务器
  Future<String> getSavedImageServer() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kPicacgImageServerKey) ?? 'storage1.picacomic.com';
  }

  /// 测试指定分流节点的连通性，返回延迟（毫秒）
  Future<int> testChannel(PicacgChannelMode mode, {String customIp = ''}) async {
    final effectiveCustomIp = _effectiveCustomIp(mode, customIp);
    logger.info('PicACG 测速开始: ${mode.label} customIp=$effectiveCustomIp');
    try {
      final ms = await rust.picacgTestChannel(mode: mode.value, custom: effectiveCustomIp);
      logger.info('PicACG 测速结果: ${mode.label} = ${ms}ms');
      return ms.toInt();
    } catch (e) {
      logger.info('PicACG 测速失败: ${mode.label} err=$e');
      rethrow;
    }
  }

  /// 并行测试所有节点，返回 {mode: latencyMs} Map（失败节点值为 -1）
  Future<Map<PicacgChannelMode, int>> testAllChannels({String customIp = ''}) async {
    logger.info('PicACG 开始并行测速所有节点...');
    final futures = PicacgChannelMode.values.map((mode) async {
      try {
        final ms = await testChannel(mode, customIp: customIp);
        return MapEntry(mode, ms);
      } catch (_) {
        return MapEntry(mode, -1);
      }
    });
    final entries = await Future.wait(futures);
    final result = Map.fromEntries(entries);
    logger.info('PicACG 测速完成: $result');
    return result;
  }

  String _effectiveCustomIp(PicacgChannelMode mode, String customIp) {
    final value = customIp.trim();
    if (mode == PicacgChannelMode.cdnIp) {
      return value.isEmpty ? _kPicacgDefaultCdnIp : value;
    }
    return value;
  }

  Future<void> _syncNetworkConfigToRust() async {
    final prefs = await SharedPreferences.getInstance();
    final channelVal = prefs.getInt(_kPicacgChannelKey) ?? 0;
    final mode = PicacgChannelMode.fromValue(channelVal);
    final rawCustom = prefs.getString(_kPicacgChannelCustomKey) ?? '';
    final custom = _effectiveCustomIp(mode, rawCustom);
    final proxy = prefs.getString(_kPicacgProxyKey) ?? '';
    final imageServer = prefs.getString(_kPicacgImageServerKey) ?? '';

    rust.picacgSetProxy(proxyUrl: proxy);
    rust.picacgSetChannel(mode: mode.value, custom: custom);
    rust.picacgSetImageServer(server: imageServer);
    _imageCache.clear();
    logger.info('PicACG 登录前同步网络配置: mode=${mode.label}, custom=$custom, proxy=$proxy');
  }

  Future<PicacgUser> _finalizeLoginSuccess() async {
    _isLoggedIn = true;

    final token = rust.picacgGetToken();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPicacgTokenKey, token);

    final user = await getUserProfile();
    _currentUser = user;
    logger.info('PicACG 登录成功: ${user.name}');
    return user;
  }

  // ==================== 首页 ====================

  /// 获取首页推荐集合（神魔精选）
  Future<List<PicacgCollection>> getCollections() async {
    logger.info('PicACG 获取首页推荐');
    final json = await rust.picacgGetCollections();
    final data = jsonDecode(json) as Map<String, dynamic>;
    final collections = data['collections'] as List? ?? [];
    return collections.map((e) => PicacgCollection.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取随机漫画
  Future<List<PicacgComic>> getRandomComics() async {
    final json = await rust.picacgGetRandomComics();
    final data = jsonDecode(json) as List? ?? [];
    return data.map((e) => PicacgComic.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ==================== 分类 ====================

  /// 获取所有分类
  Future<List<PicacgCategory>> getCategories() async {
    logger.info('PicACG 获取分类列表');
    final json = await rust.picacgGetCategories();
    final data = jsonDecode(json) as Map<String, dynamic>;
    final list = data['categories'] as List? ?? [];
    return list.map((e) => PicacgCategory.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 按分类浏览漫画
  Future<PicacgComicList> getComicsByCategory({
    required String category,
    int page = 1,
    PicacgSortOrder sort = PicacgSortOrder.dateDescending,
  }) async {
    logger.info('PicACG 按分类: $category, 第${page}页');
    final json = await rust.picacgGetComicsByCategory(
      category: category,
      page: page,
      sort: sort.value,
    );
    final data = jsonDecode(json) as Map<String, dynamic>;
    return PicacgComicList.fromJson(data);
  }

  // ==================== 搜索 ====================

  /// 高级搜索
  Future<PicacgComicList> searchComics({
    required String keyword,
    List<String> categories = const [],
    int page = 1,
    PicacgSortOrder sort = PicacgSortOrder.dateDescending,
  }) async {
    logger.info('PicACG 搜索: "$keyword", 第${page}页');
    final json = await rust.picacgSearchComics(
      keyword: keyword,
      categories: categories,
      page: page,
      sort: sort.value,
    );
    final data = jsonDecode(json) as Map<String, dynamic>;
    return PicacgComicList.fromJson(data);
  }

  /// 获取热门搜索关键词
  Future<List<String>> getKeywords() async {
    final json = await rust.picacgGetKeywords();
    final data = jsonDecode(json) as Map<String, dynamic>;
    final list = data['keywords'] as List? ?? [];
    return list.map((e) => e.toString()).toList();
  }

  // ==================== 排行榜 ====================

  /// 获取排行榜
  ///
  /// - `timeType`: "H24" / "D7" / "D30"
  Future<List<PicacgComic>> getRankings(String timeType) async {
    logger.info('PicACG 排行榜: $timeType');
    final json = await rust.picacgGetRankings(timeType: timeType);
    final data = jsonDecode(json) as Map<String, dynamic>;
    final list = data['comics'] as List? ?? [];
    return list.map((e) => PicacgComic.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ==================== 漫画详情 ====================

  /// 获取漫画详情
  Future<PicacgComic> getComicDetail(String comicId) async {
    logger.info('PicACG 漫画详情: $comicId');
    final json = await rust.picacgGetComicDetail(comicId: comicId);
    final data = jsonDecode(json) as Map<String, dynamic>;
    final comic = data['comic'] as Map<String, dynamic>? ?? data;
    return PicacgComic.fromJson(comic);
  }

  /// 获取漫画推荐
  Future<List<PicacgComic>> getComicRecommendations(String comicId) async {
    final json = await rust.picacgGetComicRecommendations(comicId: comicId);
    final data = jsonDecode(json) as Map<String, dynamic>;
    final list = data['comics'] as List? ?? [];
    return list.map((e) => PicacgComic.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取章节列表
  Future<PicacgEpsList> getComicEps(String comicId, {int page = 1}) async {
    logger.info('PicACG 章节列表: $comicId, 第${page}页');
    final json = await rust.picacgGetComicEps(comicId: comicId, page: page);
    final data = jsonDecode(json) as Map<String, dynamic>;
    return PicacgEpsList.fromJson(data);
  }

  /// 获取章节图片
  Future<PicacgPageList> getEpsPages(String comicId, int epsOrder, {int page = 1}) async {
    logger.info('PicACG 章节图片: $comicId, 第${epsOrder}集, 第${page}页');
    final json = await rust.picacgGetEpsPages(comicId: comicId, epsOrder: epsOrder, page: page);
    final data = jsonDecode(json) as Map<String, dynamic>;
    return PicacgPageList.fromJson(data);
  }

  // ==================== 收藏 ====================

  /// 获取收藏列表
  Future<PicacgComicList> getFavourites({
    int page = 1,
    PicacgSortOrder sort = PicacgSortOrder.dateDescending,
  }) async {
    logger.info('PicACG 收藏列表: 第${page}页');
    final json = await rust.picacgGetFavourites(page: page, sort: sort.value);
    final data = jsonDecode(json) as Map<String, dynamic>;
    return PicacgComicList.fromJson(data);
  }

  /// 切换收藏状态
  Future<String> toggleFavourite(String comicId) async {
    final json = await rust.picacgToggleFavourite(comicId: comicId);
    final data = jsonDecode(json) as Map<String, dynamic>;
    return data['action'] as String? ?? '';
  }

  /// 切换点赞状态
  Future<String> toggleLike(String comicId) async {
    final json = await rust.picacgToggleLike(comicId: comicId);
    final data = jsonDecode(json) as Map<String, dynamic>;
    return data['action'] as String? ?? '';
  }

  // ==================== 评论 ====================

  /// 获取评论列表
  Future<List<PicacgComment>> getComments(String comicId, {int page = 1}) async {
    final json = await rust.picacgGetComments(comicId: comicId, page: page);
    final data = jsonDecode(json) as Map<String, dynamic>;
    final commentData = data['comments'] as Map<String, dynamic>? ?? {};
    final docs = commentData['docs'] as List? ?? [];
    return docs.map((e) => PicacgComment.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 发送评论
  Future<void> sendComment(String comicId, String content) async {
    await rust.picacgSendComment(comicId: comicId, content: content);
  }
}
