/// PicACG 服务层
///
/// 封装 Rust FFI 调用，提供高层业务 API
/// 使用 GetIt 注入，全局单例

import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/src/rust/api/picacg.dart' as rust;
import 'package:slime_works/pages/picacg/models/picacg_models.dart';
import 'package:slime_works/core/utils/logger.dart';

/// PicACG Token 持久化 Key
const String _kPicAcgTokenKey = 'picacg_token';
const String _kPicAcgProxyKey = 'picacg_proxy';
const String _kPicAcgChannelKey = 'picacg_channel';
const String _kPicAcgChannelCustomKey = 'picacg_channel_custom';
const String _kPicAcgImageServerKey = 'picacg_image_server';
const String _kPicAcgLoginEmailKey = 'picacg_login_email';
const String _kPicAcgLoginPasswordKey = 'picacg_login_password';
const String _kPicAcgDefaultCdnIp = '104.18.227.172';

/// 分流模式（与原项目 radioButton 对应）
///
/// 原项目分流编号：1=直连, 2=分流2, 3=分流3, 4=CDN分流(自定义IP), 5=JP反代, 6=US反代
enum PicAcgChannelMode {
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
  usProxy(6, 'US反代分流'),

  /// 7 — PC 中转（经由局域网 PC端节点服务器中转）
  lanRelay(7, 'PC中转');

  const PicAcgChannelMode(this.value, this.label);
  final int value;
  final String label;

  static PicAcgChannelMode fromValue(int v) => PicAcgChannelMode.values.firstWhere(
    (e) => e.value == v,
    orElse: () => PicAcgChannelMode.direct,
  );
}

/// PicACG 服务
class PicAcgService {
  PicAcgService._();

  static final PicAcgService _instance = PicAcgService._();

  factory PicAcgService() => _instance;

  /// 是否已登录
  bool _isLoggedIn = false;

  bool get isLoggedIn => _isLoggedIn;

  /// 当前用户信息（登录后缓存）
  PicAcgUser? _currentUser;

  PicAcgUser? get currentUser => _currentUser;

  /// 图片字节 LRU 缓存，最多保留 [_kImageCacheMaxSize] 条
  /// 使用 LinkedHashMap 保留访问顺序，容量超限时淘汰最久未用的条目
  /// 显示大量漫画图片时内存占用较高，缩小缓存上限防止 OOM
  static const int _kImageCacheMaxSize = 60;
  final LinkedHashMap<String, Uint8List> _imageCache = LinkedHashMap<String, Uint8List>();

  /// 初始化服务（从持久化存储恢复 Token、代理和分流配置）
  Future<void> init() async {
    logger.info('PicACG Service 初始化');
    rust.picacgInit();

    // 初始化历史记录本地数据库（Rust redb）
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final dbPath = '${appDocDir.path}/slime_picacg.redb';
      rust.picacgInitHistory(dbPath: dbPath);
      logger.info('PicACG 历史记录数据库初始化: $dbPath');
    } catch (e) {
      logger.error('PicACG 历史记录数据库初始化失败: $e');
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      // 恢复代理配置
      final savedProxy = prefs.getString(_kPicAcgProxyKey) ?? '';
      if (savedProxy.isNotEmpty) {
        rust.picacgSetProxy(proxyUrl: savedProxy);
        logger.info('PicACG 恢复代理配置: $savedProxy');
      }

      // 恢复分流配置
      final channelVal = prefs.getInt(_kPicAcgChannelKey) ?? 0;
      final channelMode = PicAcgChannelMode.fromValue(channelVal);
      final channelCustomRaw = prefs.getString(_kPicAcgChannelCustomKey) ?? '';
      final channelCustom = _effectiveCustomIp(channelMode, channelCustomRaw);
      rust.picacgSetChannel(mode: channelVal, custom: channelCustom);
      logger.info('PicACG 恢复分流模式: $channelVal custom=$channelCustom');

      // 恢复图片服务器
      final imageServer = prefs.getString(_kPicAcgImageServerKey) ?? '';
      rust.picacgSetImageServer(server: imageServer);

      // 恢复 Token
      final savedToken = prefs.getString(_kPicAcgTokenKey) ?? '';
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
          await prefs.remove(_kPicAcgTokenKey);
        }
      }
    } catch (e) {
      logger.error('PicACG 初始化失败: $e');
    }
  }

  // ==================== 认证 ====================

  /// 登录
  Future<PicAcgUser> login(String email, String password) async {
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
    await prefs.remove(_kPicAcgTokenKey);
  }

  /// 获取用户信息
  Future<PicAcgUser> getUserProfile() async {
    final json = await rust.picacgGetUserProfile();
    final data = jsonDecode(json) as Map<String, dynamic>;
    return PicAcgUser.fromJson(data);
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
    await prefs.setString(_kPicAcgProxyKey, proxyUrl);
    logger.info('PicACG 代理已更新: $proxyUrl');
  }

  /// 保存登录账号密码（无论是否登录成功）
  Future<void> saveLoginCredentials({required String email, required String password}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPicAcgLoginEmailKey, email.trim());
    await prefs.setString(_kPicAcgLoginPasswordKey, password);
    logger.info('PicACG 已保存登录凭据: email=${email.trim()}');
  }

  /// 获取上次输入的账号密码
  Future<Map<String, String>> getSavedLoginCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'email': prefs.getString(_kPicAcgLoginEmailKey) ?? '',
      'password': prefs.getString(_kPicAcgLoginPasswordKey) ?? '',
    };
  }

  /// 获取已保存的代理配置
  Future<String> getSavedProxy() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kPicAcgProxyKey) ?? '';
  }

  /// 设置分流模式并持久化
  Future<void> setChannel(PicAcgChannelMode mode, {String customIp = ''}) async {
    final effectiveCustomIp = _effectiveCustomIp(mode, customIp);
    rust.picacgSetChannel(mode: mode.value, custom: effectiveCustomIp);
    _imageCache.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPicAcgChannelKey, mode.value);
    await prefs.setString(_kPicAcgChannelCustomKey, effectiveCustomIp);
    logger.info('PicACG 分流模式已更新: ${mode.label}, custom=$effectiveCustomIp');
  }

  /// 获取已保存的分流模式
  Future<PicAcgChannelMode> getSavedChannel() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getInt(_kPicAcgChannelKey) ?? 0;
    return PicAcgChannelMode.fromValue(val);
  }

  /// 获取已保存的自定义 IP
  Future<String> getSavedCustomIp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kPicAcgChannelCustomKey) ?? '';
  }

  /// 设置图片服务器并持久化
  Future<void> setImageServer(String server) async {
    rust.picacgSetImageServer(server: server);
    _imageCache.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPicAcgImageServerKey, server);
    logger.info('PicACG 图片服务器已更新: $server');
  }

  String buildImageUrl(PicAcgImage image) {
    return rust.picacgBuildImageUrl(fileServer: image.fileServer, path: image.path);
  }

  Future<Uint8List> fetchImageBytes(PicAcgImage image) async {
    final key = buildImageUrl(image);
    // LRU: remove-then-re-insert marks as most recently used
    final cached = _imageCache.remove(key);
    if (cached != null) {
      _imageCache[key] = cached;
      return cached;
    }
    final bytes = await rust.picacgFetchImage(fileServer: image.fileServer, path: image.path);
    // Evict oldest entry when cache is full
    if (_imageCache.length >= _kImageCacheMaxSize) {
      _imageCache.remove(_imageCache.keys.first);
    }
    _imageCache[key] = bytes;
    return bytes;
  }

  /// 后台静默预取图片列表（不抛异常，不重复拉取已缓存图片）
  void prefetchImages(List<PicAcgImage> images) {
    for (final image in images) {
      final key = buildImageUrl(image);
      if (!_imageCache.containsKey(key)) {
        fetchImageBytes(image).ignore();
      }
    }
  }

  /// 获取已保存的图片服务器
  Future<String> getSavedImageServer() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kPicAcgImageServerKey) ?? 'storage1.picacomic.com';
  }

  /// 测试指定分流节点的连通性，返回延迟（毫秒）
  Future<int> testChannel(PicAcgChannelMode mode, {String customIp = ''}) async {
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
  Future<Map<PicAcgChannelMode, int>> testAllChannels({String customIp = ''}) async {
    logger.info('PicACG 开始并行测速所有节点...');
    final futures = PicAcgChannelMode.values.map((mode) async {
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

  String _effectiveCustomIp(PicAcgChannelMode mode, String customIp) {
    final value = customIp.trim();
    if (mode == PicAcgChannelMode.cdnIp) {
      return value.isEmpty ? _kPicAcgDefaultCdnIp : value;
    }
    if (mode == PicAcgChannelMode.lanRelay) {
      // 中转地址直接作为 custom 传入 Rust
      return value;
    }
    return value;
  }

  Future<void> _syncNetworkConfigToRust() async {
    final prefs = await SharedPreferences.getInstance();
    final channelVal = prefs.getInt(_kPicAcgChannelKey) ?? 0;
    final mode = PicAcgChannelMode.fromValue(channelVal);
    final rawCustom = prefs.getString(_kPicAcgChannelCustomKey) ?? '';
    final custom = _effectiveCustomIp(mode, rawCustom);
    final proxy = prefs.getString(_kPicAcgProxyKey) ?? '';
    final imageServer = prefs.getString(_kPicAcgImageServerKey) ?? '';

    rust.picacgSetProxy(proxyUrl: proxy);
    rust.picacgSetChannel(mode: mode.value, custom: custom);
    rust.picacgSetImageServer(server: imageServer);
    _imageCache.clear();
    logger.info('PicACG 登录前同步网络配置: mode=${mode.label}, custom=$custom, proxy=$proxy');
  }

  Future<PicAcgUser> _finalizeLoginSuccess() async {
    _isLoggedIn = true;

    final token = rust.picacgGetToken();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPicAcgTokenKey, token);

    final user = await getUserProfile();
    _currentUser = user;
    logger.info('PicACG 登录成功: ${user.name}');
    return user;
  }

  // ==================== 首页 ====================

  /// 获取首页推荐集合（神魔精选）
  Future<List<PicAcgCollection>> getCollections() async {
    logger.info('PicACG 获取首页推荐');
    final json = await rust.picacgGetCollections();
    final data = jsonDecode(json) as Map<String, dynamic>;
    final collections = data['collections'] as List? ?? [];
    return collections.map((e) => PicAcgCollection.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取随机漫画
  Future<List<PicAcgComic>> getRandomComics() async {
    final json = await rust.picacgGetRandomComics();
    final data = jsonDecode(json) as List? ?? [];
    return data.map((e) => PicAcgComic.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ==================== 分类 ====================

  /// 获取所有分类
  Future<List<PicAcgCategory>> getCategories() async {
    logger.info('PicACG 获取分类列表');
    final json = await rust.picacgGetCategories();
    final data = jsonDecode(json) as Map<String, dynamic>;
    final list = data['categories'] as List? ?? [];
    return list.map((e) => PicAcgCategory.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 按分类浏览漫画
  Future<PicAcgComicList> getComicsByCategory({
    required String category,
    int page = 1,
    PicAcgSortOrder sort = PicAcgSortOrder.dateDescending,
  }) async {
    logger.info('PicACG 按分类: $category, 第${page}页');
    final json = await rust.picacgGetComicsByCategory(
      category: category,
      page: page,
      sort: sort.value,
    );
    final data = jsonDecode(json) as Map<String, dynamic>;
    return PicAcgComicList.fromJson(data);
  }

  // ==================== 搜索 ====================

  /// 高级搜索
  Future<PicAcgComicList> searchComics({
    required String keyword,
    List<String> categories = const [],
    int page = 1,
    PicAcgSortOrder sort = PicAcgSortOrder.dateDescending,
  }) async {
    logger.info('PicACG 搜索: "$keyword", 第${page}页');
    final json = await rust.picacgSearchComics(
      keyword: keyword,
      categories: categories,
      page: page,
      sort: sort.value,
    );
    final data = jsonDecode(json) as Map<String, dynamic>;
    return PicAcgComicList.fromJson(data);
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
  Future<List<PicAcgComic>> getRankings(String timeType) async {
    logger.info('PicACG 排行榜: $timeType');
    final json = await rust.picacgGetRankings(timeType: timeType);
    final data = jsonDecode(json) as Map<String, dynamic>;
    final list = data['comics'] as List? ?? [];
    return list.map((e) => PicAcgComic.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ==================== 漫画详情 ====================

  /// 漫画元数据内存缓存（title + thumbUrl），供历史记录保存使用
  final Map<String, ({String title, String thumbUrl})> _comicMetaCache = {};

  /// 缓存漫画元数据（由调用方主动写入，例如详情页加载后）
  void cacheComicMeta(String comicId, String title, String thumbUrl) {
    _comicMetaCache[comicId] = (title: title, thumbUrl: thumbUrl);
  }

  /// 读取漫画元数据缓存（读取此前缓存的信息）
  ({String title, String thumbUrl})? getComicMeta(String comicId) {
    return _comicMetaCache[comicId];
  }

  /// 获取漫画详情（结果自动写入元数据缓存）
  Future<PicAcgComic> getComicDetail(String comicId) async {
    logger.info('PicACG 漫画详情: $comicId');
    final json = await rust.picacgGetComicDetail(comicId: comicId);
    final data = jsonDecode(json) as Map<String, dynamic>;
    final comic = data['comic'] as Map<String, dynamic>? ?? data;
    final result = PicAcgComic.fromJson(comic);

    /// 缓存漫画元数据，方便阅读器保存历史时读取
    _comicMetaCache[comicId] = (title: result.title, thumbUrl: result.thumb.fullUrl);
    return result;
  }

  /// 获取漫画推荐
  Future<List<PicAcgComic>> getComicRecommendations(String comicId) async {
    final json = await rust.picacgGetComicRecommendations(comicId: comicId);
    final data = jsonDecode(json) as Map<String, dynamic>;
    final list = data['comics'] as List? ?? [];
    return list.map((e) => PicAcgComic.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取章节列表
  Future<PicAcgEpsList> getComicEps(String comicId, {int page = 1}) async {
    logger.info('PicACG 章节列表: $comicId, 第${page}页');
    final json = await rust.picacgGetComicEps(comicId: comicId, page: page);
    final data = jsonDecode(json) as Map<String, dynamic>;
    return PicAcgEpsList.fromJson(data);
  }

  /// 获取章节图片
  Future<PicAcgPageList> getEpsPages(String comicId, int epsOrder, {int page = 1}) async {
    logger.info('PicACG 章节图片: $comicId, 第${epsOrder}集, 第${page}页');
    final json = await rust.picacgGetEpsPages(comicId: comicId, epsOrder: epsOrder, page: page);
    final data = jsonDecode(json) as Map<String, dynamic>;
    return PicAcgPageList.fromJson(data);
  }

  // ==================== 收藏 ====================

  /// 获取收藏列表
  Future<PicAcgComicList> getFavourites({
    int page = 1,
    PicAcgSortOrder sort = PicAcgSortOrder.dateDescending,
  }) async {
    logger.info('PicACG 收藏列表: 第${page}页');
    final json = await rust.picacgGetFavourites(page: page, sort: sort.value);
    final data = jsonDecode(json) as Map<String, dynamic>;
    return PicAcgComicList.fromJson(data);
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

  /// 获取评论列表（同时返回总页数）
  Future<(List<PicAcgComment>, int)> getComments(String comicId, {int page = 1}) async {
    final json = await rust.picacgGetComments(comicId: comicId, page: page);
    final data = jsonDecode(json) as Map<String, dynamic>;
    final commentData = data['comments'] as Map<String, dynamic>? ?? {};
    final docs = commentData['docs'] as List? ?? [];
    final totalPages = commentData['pages'] as int? ?? 1;
    final list = docs.map((e) => PicAcgComment.fromJson(e as Map<String, dynamic>)).toList();
    return (list, totalPages);
  }

  /// 发送评论
  Future<void> sendComment(String comicId, String content) async {
    await rust.picacgSendComment(comicId: comicId, content: content);
  }
}
