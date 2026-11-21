import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:dio/dio.dart';
import 'package:dio/io.dart' show IOHttpClientAdapter;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:get/get.dart' hide FormData, MultipartFile;
import 'package:get_it/get_it.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/mock/mock_mode.dart';
import 'package:slime_works/core/services/media_prefs_service.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/core/utils/timing_trace.dart';
import 'package:slime_works/src/rust/api/http_bridge.dart' as http_bridge_api;
import 'package:slime_works/src/rust/api/media_collection.dart' as media_api;
import 'package:slime_works/src/rust/api/novel_reader.dart' as rust_api;

import 'node_models.dart';

part 'node_http_handler.dart';
part 'node_media_handler.dart';

class NodeSettingsService extends GetxService {
  static const String _keyRemoteNodes = 'node_remote_nodes';
  static const String _keyActiveNodeId = 'node_active_node_id';
  static const String _keyWakeDevices = 'node_wake_devices';
  static const String _keyLocalEnabled = 'node_local_enabled';
  static const String _keyLocalName = 'node_local_name';
  static const String _keyLocalPort = 'node_local_port';
  /// 本机节点授权码（明文存本地偏好，只把 sha256 摘要发给节点）
  static const String _keyLocalAuthCode = 'node_local_auth_code';
  static const int _defaultRemoteNodePort = 17888;

  final Loggers _logger = Loggers(name: 'NodeSettings');

  final RxList<NodeEndpoint> remoteNodes = <NodeEndpoint>[].obs;
  final RxMap<String, bool> nodeConnectivity = <String, bool>{}.obs;
  final RxMap<String, String> nodeConnectivityError = <String, String>{}.obs;
  final RxList<WakeDevice> wakeDevices = <WakeDevice>[].obs;
  final RxMap<String, WakeStatus> wakeStatus = <String, WakeStatus>{}.obs;
  final RxDouble appRxKbps = 0.0.obs;
  final RxDouble appTxKbps = 0.0.obs;
  final RxInt nodeRequestCount = 0.obs;
  final RxInt libraryMutationTick = 0.obs;
  final RxBool localNodeEnabled = false.obs;
  final RxString localNodeName = '本机节点'.obs;
  final RxInt localNodePort = 17888.obs;
  final RxList<String> localNodeApiList = <String>[].obs;

  /// 全局生效的节点：空串表示本机。选中后应用内所有数据功能只走该节点。
  final RxString activeNodeId = ''.obs;

  SharedPreferences? _prefs;
  // 服务器实例已迁移到 Rust 管理，不再需要 Dart 端的 HttpServer
  final Dio _dio = _createNodeDio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 12),
      sendTimeout: const Duration(seconds: 12),
    ),
  );

  final Dio _probeDio = _createNodeDio(
    BaseOptions(
      connectTimeout: _probeFastTimeout,
      receiveTimeout: _probeFastTimeout,
      sendTimeout: _probeFastTimeout,
    ),
  );

  /// 节点专用 Dio：绕过系统代理直连。iOS/Android 设备上的代理（如 MITM）会
  /// 掐断 keep-alive 长连接，导致 "Connection closed while receiving data"。
  static Dio _createNodeDio(BaseOptions options) =>
      Dio(options)..httpClientAdapter = IOHttpClientAdapter(
            createHttpClient: () {
              final client = HttpClient();
              client.findProxy = (_) => 'DIRECT';
              return client;
            },
          );

  /// 常规连通性探测的超时档：图快，启动阶段多个节点并发探测也不拖慢页面。
  static const Duration _probeFastTimeout = Duration(milliseconds: 200);

  /// 熔断前确认用的超时档。200ms 是给"空闲节点"用的：节点正在批量生成缩略图
  /// 或解压刚上传的归档时，ping 完全可能压线超时，据此熔断会把健康节点判死。
  ///
  /// 业务服务层的单发能力探测（电力统计/阿里云/Sentry 的 checkNodeXxxAvailable）
  /// 也用它：那种探测同样只允许"慢"，不许把慢误报成"该节点不支持此功能"。
  static const Duration probeConfirmTimeout = Duration(milliseconds: 1500);

  /// 节点回「并发已满」(503/429) 时的重试次数：连接是通的，只是服务端在背压。
  static const int _nodeBusyRetries = 2;

  /// 授权码摘要的请求头名（需与 Rust `node_server::AUTH_HEADER` 一致）。
  static const String _authHeaderName = 'X-SW-Auth';

  /// 媒体流 URL 携带摘要的查询参数名（需与 Rust `node_server::AUTH_QUERY_PARAM` 一致）。
  static const String _authQueryParamName = 'sw_auth';

  /// 本机节点授权码明文；空串表示不启用校验。
  final RxString localNodeAuthCode = ''.obs;

  void _attachAuthInterceptor() {
    _dio.interceptors.add(_authInterceptor);
    _probeDio.interceptors.add(_authInterceptor);
  }

  /// 授权摘要拦截器单例：本服务的两条 Dio 和业务服务层向 [createNodeDio]
  /// 要的那些共用同一份，按 URL 找节点补头。
  late final _NodeAuthInterceptor _authInterceptor = _NodeAuthInterceptor(
    _authDigestForUrl,
  );

  /// 业务服务层访问远程节点用的 Dio：既带 `X-SW-Auth` 摘要，也绕开系统代理直连。
  ///
  /// 电力统计/阿里云/Sentry 原先各自 `Dio(BaseOptions(...))`，两条都缺：
  /// 没有授权头时，节点一设授权码就统一 401——连"该节点支持不支持这个功能"的
  /// 探测也被误判成不支持，端侧就是一句「该节点不支持此功能」；没有 DIRECT 时，
  /// 移动端上的系统代理/抓包代理还会掐断 keep-alive 长连接。
  /// 节点请求一律从这里取，别再造裸 Dio。
  Dio createNodeDio(BaseOptions options) =>
      _createNodeDio(options)..interceptors.add(_authInterceptor);

  /// 按请求 URL 找到对应节点，返回其授权码摘要；无授权码时返回 null。
  String? _authDigestForUrl(String url) {
    final code = authCodeForUrl(url);
    if (code == null || code.isEmpty) {
      return null;
    }
    return authCodeDigest(code);
  }

  /// 授权码明文 → sha256 十六进制摘要（与节点侧存储/比对的形态一致）。
  static String authCodeDigest(String authCode) {
    return sha256.convert(utf8.encode(authCode.trim())).toString();
  }

  /// 找出 [url] 归属的节点并取其授权码（内网地址优先，取最长匹配）。
  String? authCodeForUrl(String url) {
    String? best;
    int bestLength = 0;
    for (final node in remoteNodes) {
      if (!node.enabled || node.authCode.isEmpty) {
        continue;
      }
      for (final base in <String>{
        _normalizeBaseUrl(node.effectiveApiBaseUrl),
        _normalizeBaseUrl(node.apiBaseUrl),
        _normalizeBaseUrl(node.lanApiBaseUrl ?? ''),
      }) {
        if (base.isEmpty || !url.startsWith(base)) {
          continue;
        }
        if (base.length > bestLength) {
          bestLength = base.length;
          best = node.authCode;
        }
      }
    }
    return best;
  }

  /// 供无法注入请求头的调用方（图片/视频 URL）使用的请求头集合。
  Map<String, String> nodeAuthHeaders(String nodeId) {
    final code = getNodeById(nodeId)?.authCode ?? '';
    if (code.isEmpty) {
      return const <String, String>{};
    }
    return <String, String>{_authHeaderName: authCodeDigest(code)};
  }

  /// 是否为节点返回的 401（授权码缺失/错误）。
  static bool _isUnauthorizedError(Object error) =>
      error is DioException && error.response?.statusCode == 401;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  DateTime? _trafficWindowStartAt;
  DateTime? _lastTrafficAt;
  int _trafficWindowRxBytes = 0;
  int _trafficWindowTxBytes = 0;
  final Map<String, Future<Map<String, dynamic>>> _inFlightNodeCalls =
      <String, Future<Map<String, dynamic>>>{};

  /// 熔断节点集合：本次运行期间验证失败的节点，不再自动请求。
  final Set<String> _circuitBreakedNodes = <String>{};

  /// 熔断解除复探的进行中Future（按节点去重），避免一屏请求各自打一次 ping。
  final Map<String, Future<_ProbeResult>> _nodeBreakChecks = <String, Future<_ProbeResult>>{};

  /// nodeId → 最近一次真正应答过的 base。
  ///
  /// 同时配了内网/外网地址时，`effectiveApiBaseUrl` 永远选内网那一个；内网常年不通
  /// （换过网段、对端不在同一 LAN）就会让取数每次都先付一遍连接超时，图片 URL 更是
  /// 直接指向死地址。这里记下应答过的那一路，后续调用与 URL 构造都以它为先。
  final Map<String, String> _nodeAnsweredBase = <String, String>{};

  /// 该节点当前该用的 base：有应答记录用记录，没有就按 LAN 优先的默认口径。
  String _baseUrlFor(NodeEndpoint node) => _nodeAnsweredBase[node.id] ?? node.effectiveApiBaseUrl;

  /// 调用候选地址：先应答过的那一路，再 LAN、再 WAN（去重保序）。
  /// 只给一个地址时，`_shouldTryFallbackUrl` 想回退也没有下一个地址可换。
  List<String> _nodeCallCandidateUrls(NodeEndpoint node) {
    final bases = <String>{
      _baseUrlFor(node),
      node.effectiveApiBaseUrl,
      node.lanApiBaseUrl ?? '',
      node.apiBaseUrl,
    }.where((b) => b.isNotEmpty).toList(growable: false);
    return <String>[
      for (final base in bases) ..._candidateNodeCallUrls(base),
    ];
  }

  /// 已缩放图片的内存缓存（key = cacheKey，LRU 淘汰，总字节上限 80MB）。
  final Map<String, Uint8List> _resizedBytesCache = {};

  /// 当前缓存总字节数，用于 LRU 淘汰判断。
  int _resizedBytesCacheSize = 0;

  /// 缓存总字节上限：80MB，防止大量远程封面导致内存飙升。
  static const int _kBytesCacheMaxBytes = 80 * 1024 * 1024;

  Future<void> init() async {
    if (_isInitialized) {
      return;
    }

    _prefs = await SharedPreferences.getInstance();
    _attachAuthInterceptor();
    await _load();
    await _refreshLocalApiList();

    if (localNodeEnabled.value) {
      await startLocalNodeServer();
    }

    _isInitialized = true;
    // 远程节点的连通确认与取数预热放在应用初始化完成后由 warmUpAfterLaunch 统一发起：
    // 放在这里会在 runApp 之前抢占启动窗口，且一次跑完就不会再有第二次机会。
  }

  // ── 启动预热与离线复探 ─────────────────────────────────────────────────

  /// 预热快照的有效期：超过就直接重拉，宁慢不旧。
  static const Duration _remoteMetaMaxAge = Duration(seconds: 60);

  /// 每个节点的远程元数据预热结果（含在途的 Future，取用一次即失效）。
  final Map<String, Future<NodeMediaMetadata?>> _remoteMetaWarmups =
      <String, Future<NodeMediaMetadata?>>{};

  /// 应用初始化完毕后调用：确认节点连通 + 预取远程媒体元数据。
  Future<void> warmUpAfterLaunch() async {
    if (MockMode.enabled) return;
    if (!isInitialized) {
      await init();
    }
    final trace = TimingTrace('应用启动节点预热');
    await refreshNodeConnectivity();
    trace.lap('连通确认 ${remoteNodes.where((n) => n.enabled).length}个节点');
    // 预热不等网络：先返回，让首屏按需取快照
    for (final node in enabledRemoteNodes) {
      requestNodeMediaMetadataWarmup(node.id);
    }
    trace.end();
  }

  /// 复探「当前判为离线或已熔断」的启用节点，全在线时这一轮零流量。
  ///
  /// 只在真正要用远程数据时调用（媒体库进页面 / 点刷新），没有后台定时轮询：
  /// 节点长时间不可达时，定时复探会变成每 20 秒一串无意义的超时日志。
  /// 节点回来了就补预热并通知已打开的媒体库重取远程数据。
  Future<void> recheckOfflineNodes() async {
    final stale = dataRemoteNodes
        .where(
          (n) =>
              n.enabled &&
              (_circuitBreakedNodes.contains(n.id) || nodeConnectivity[n.id] != true),
        )
        .toList(growable: false);
    if (stale.isEmpty) {
      return;
    }
    final trace = TimingTrace('离线节点复探', scope: '${stale.length}个');
    await Future.wait(stale.map((n) => checkNodeConnectivity(n.id)));
    trace.end();
    for (final node in stale) {
      if (nodeConnectivity[node.id] != true) {
        continue;
      }
      _logger.info('节点已恢复连接: ${node.name}');
      // 先清掉上次失败留下的空快照条目，否则幂等判断会跳过这次补热。
      invalidateNodeMediaMetadataCache(nodeId: node.id);
      requestNodeMediaMetadataWarmup(node.id);
      libraryMutationTick.value++;
    }
  }

  /// 发起某节点远程媒体元数据的后台预热（幂等：已在途或已备好则跳过）。
  void requestNodeMediaMetadataWarmup(String nodeId) {
    final node = getNodeById(nodeId);
    if (node == null || !node.enabled || _remoteMetaWarmups.containsKey(nodeId)) {
      return;
    }
    // 预热失败不能留下没人 await 的 error Future：就地吞掉，把「没预热上」表达为 null。
    // 三路只要有一路没取到就不进缓存：残缺快照一旦被首屏复用，用户看到的就是
    // 「远程一个集合都没有」这种假象（实测过一次 list_media_collections 超时导致集合=0）。
    // 不落缓存≠丢弃数据：没有快照时 fetchNodeMediaMetadata 会现拉一次，
    // 现拉仍然按「能取到几路算几路」的宽容口径返回，老节点缺 action 也不会白屏。
    final future = _fetchNodeMediaMetadata(node).then<NodeMediaMetadata?>(
      (metadata) => metadata.complete ? metadata : null,
      onError: (Object error, StackTrace _) {
        _logger.info('远程元数据预热失败: ${node.name} -> $error');
        return null;
      },
    );
    _remoteMetaWarmups[nodeId] = future;
  }

  /// 取某节点的远程媒体元数据：命中预热快照则直接用（并作废快照，后续按实时拉取），
  /// 没有快照时现拉一次。媒体库首屏因此不必等三轮串行往返。
  Future<NodeMediaMetadata> fetchNodeMediaMetadata(String nodeId) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }
    // 熔断节点不在首屏路径上付那 1.5s 复探：媒体库在拉远程数据前已经整体复探过一轮，
    // 这里再探一次只是把同一件事付两遍。
    if (isNodeCircuitBreaked(nodeId)) {
      throw StateError('节点已熔断: ${node.name}，点刷新或重新进入页面会重新探测');
    }
    final warmup = _remoteMetaWarmups.remove(nodeId);
    if (warmup != null) {
      final trace = TimingTrace('复用远程元数据预热', scope: node.name);
      final result = await warmup;
      // 预热结果只在很短的时间内算新鲜：放久了再复用，等于把首屏换成一份过期快照。
      final fresh = result != null &&
          DateTime.now().difference(result.takenAt) <= _remoteMetaMaxAge;
      trace.end(note: fresh ? null : '未命中，改为实时拉取');
      if (result != null && fresh) {
        return result;
      }
    }
    return _fetchNodeMediaMetadata(node);
  }

  /// 丢弃所有预热快照（节点增删改、集合结构变化后调用，避免复用过期数据）。
  void invalidateNodeMediaMetadataCache({String? nodeId}) {
    if (nodeId == null) {
      _remoteMetaWarmups.clear();
      return;
    }
    _remoteMetaWarmups.remove(nodeId);
  }

  Future<NodeMediaMetadata> _fetchNodeMediaMetadata(NodeEndpoint node) async {
    final trace = TimingTrace('拉取远程媒体元数据', scope: node.name);
    // 三路并发，但各自独立吞错：某一路失败（老节点没有该 action）不该连带清空另外两路。
    Future<Object?> settle(Future<List<Map<String, dynamic>>> future) =>
        future.then<Object?>((v) => v).catchError((Object e) => e);
    final results = await Future.wait(<Future<Object?>>[
      settle(fetchNodeMediaFolders(node)),
      settle(fetchNodeMediaCollections(node)),
      settle(fetchNodeSmartFolders(node)),
    ]);
    if (results.every((r) => r is! List)) {
      // 三路全挂 = 节点确实没应答，抛出让调用方按「该节点离线」处理
      trace.end(note: '三路全失败');
      throw results.firstWhere((r) => r is! List) as Object;
    }
    final failed = <String>[];
    final ok = <int>{};
    List<Map<String, dynamic>> pick(int index, String name) {
      final r = results[index];
      if (r is List) {
        ok.add(index);
        return r.map((e) => Map<String, dynamic>.from(e as Map)).toList(growable: false);
      }
      failed.add('$name: $r');
      return const <Map<String, dynamic>>[];
    }

    final meta = NodeMediaMetadata(
      folders: pick(0, '文件夹'),
      collections: pick(1, '集合'),
      smartFolders: pick(2, '智能文件夹'),
      takenAt: DateTime.now(),
      foldersOk: ok.contains(0),
      collectionsOk: ok.contains(1),
      smartFoldersOk: ok.contains(2),
    );
    trace.end(
      note: '文件夹=${meta.folders.length} 集合=${meta.collections.length}'
          ' 智能文件夹=${meta.smartFolders.length}'
          '${failed.isEmpty ? '' : ' 失败: ${failed.join(' | ')}'}',
    );
    return meta;
  }

  /// 是否已熔断（本次运行期间不再自动请求）
  bool isNodeCircuitBreaked(String nodeId) => _circuitBreakedNodes.contains(nodeId);

  /// 重置熔断状态，供用户在设置页面手动重试。
  void resetNodeCircuitBreaker(String nodeId) {
    _circuitBreakedNodes.remove(nodeId);
    nodeConnectivityError[nodeId] = '';
  }

  List<NodeEndpoint> get enabledRemoteNodes {
    return remoteNodes.where((n) => n.enabled).toList();
  }

  /// 当前全局节点；null 表示本机。
  NodeEndpoint? get activeNode {
    final id = activeNodeId.value;
    if (id.isEmpty) {
      return null;
    }
    return getNodeById(id);
  }

  /// 当前是否运行在没有本机数据源的移动端（iOS/Android）。
  ///
  /// 做成可覆盖的字段而不是到处直接写 `Platform.isIOS || Platform.isAndroid`：
  /// 移动端专属的节点语义（不允许切「本机」、失效节点自动落到另一个节点）
  /// 否则只能靠真机验证，单测跑在 macOS 上永远测不到那条分支。
  @visibleForTesting
  bool Function() mobilePlatformProbe =
      () => Platform.isIOS || Platform.isAndroid;

  /// 移动端判据（走可覆盖探针）
  bool get isMobilePlatform => mobilePlatformProbe();

  /// 是否处于全局远程节点模式。
  bool get isRemoteMode => activeNode != null;

  /// 数据层应访问的节点集合：远程模式只有当前节点，本机模式是全部启用节点。
  List<NodeEndpoint> get dataRemoteNodes {
    final node = activeNode;
    if (node != null) {
      return <NodeEndpoint>[node];
    }
    return enabledRemoteNodes;
  }

  /// 切换全局节点；[nodeId] 为空表示本机。切换后通知所有数据面板刷新。
  Future<void> selectActiveNode(String nodeId) async {
    if (nodeId.isNotEmpty && getNodeById(nodeId) == null) {
      return;
    }
    // 移动端没有本机数据源，不允许切到「本机」——选它只会得到一个全空界面。
    // UI 已经不提供这个入口，这里再兜一层（深链/旧逻辑/程序化调用都可能绕过 UI）。
    if (nodeId.isEmpty && isMobilePlatform) {
      return;
    }
    if (activeNodeId.value == nodeId) {
      return;
    }
    activeNodeId.value = nodeId;
    await _save();
    // 数据源整体换了一个，已打开的资源库/概览需重新取数
    _emitLibraryMutation();
  }

  /// 当前节点被删除或禁用时回落到本机，避免所有数据请求指向不存在的节点。
  void _validateActiveNode() {
    final mobile = isMobilePlatform;
    final id = activeNodeId.value;
    if (id.isEmpty) {
      // 移动端没有本机数据源：停在「本机」等于所有页面全空。
      // 常见于两种情况——旧版本把 activeNodeId 存成空串、或当前节点被删后
      // 回落到本机。这里自动落到第一个启用节点，别让用户看到一片空白
      // 还以为功能坏了。
      if (mobile) {
        final fallback = enabledRemoteNodes.firstOrNull;
        if (fallback != null) {
          activeNodeId.value = fallback.id;
          _emitLibraryMutation();
        }
      }
      return;
    }
    final node = getNodeById(id);
    if (node == null || !node.enabled) {
      // 节点失效：桌面端回落到本机（仍有本机数据）；移动端落到另一个启用节点
      final fallback = mobile ? enabledRemoteNodes.firstOrNull : null;
      activeNodeId.value = fallback?.id ?? '';
      _emitLibraryMutation();
    }
  }

  /// 页面级节点选择的最终口径：远程模式下强制跟随全局节点，
  /// 本机模式保留各页自己记住的选择。
  String resolveNodeSelection(String localSelection) =>
      isRemoteMode ? activeNodeId.value : localSelection;

  NodeEndpoint? getNodeById(String nodeId) {
    return remoteNodes.firstWhereOrNull((n) => n.id == nodeId);
  }

  String getNodeEffectiveBaseUrl(String nodeId) {
    final node = getNodeById(nodeId);
    return node == null ? '' : _baseUrlFor(node);
  }

  Future<void> addRemoteNode({
    required String name,
    required String apiBaseUrl,
    String? lanApiBaseUrl,
    String? authCode,
  }) async {
    final normalized = _normalizeBaseUrl(apiBaseUrl);
    final normalizedLan = lanApiBaseUrl != null && lanApiBaseUrl.trim().isNotEmpty
        ? _normalizeBaseUrl(lanApiBaseUrl)
        : null;
    final endpoint = NodeEndpoint(
      id: _createNodeId(),
      name: name.trim().isEmpty ? '未命名节点' : name.trim(),
      apiBaseUrl: normalized,
      lanApiBaseUrl: normalizedLan,
      enabled: true,
      supportsMove: true,
      supportsCoverUpdate: true,
      authCode: authCode?.trim() ?? '',
    );
    remoteNodes.add(endpoint);
    await _save();
    await checkNodeConnectivity(endpoint.id);
    requestNodeMediaMetadataWarmup(endpoint.id);
  }

  Future<void> updateRemoteNode(NodeEndpoint endpoint) async {
    final index = remoteNodes.indexWhere((n) => n.id == endpoint.id);
    if (index == -1) {
      return;
    }

    final normalizedLan =
        endpoint.lanApiBaseUrl != null && endpoint.lanApiBaseUrl!.trim().isNotEmpty
        ? _normalizeBaseUrl(endpoint.lanApiBaseUrl!)
        : null;
    remoteNodes[index] = endpoint.copyWith(
      apiBaseUrl: _normalizeBaseUrl(endpoint.apiBaseUrl),
      lanApiBaseUrl: normalizedLan,
    );
    remoteNodes.refresh();
    await _save();
    _validateActiveNode();
    // 地址/授权码/开关都可能变，旧快照不再可信
    invalidateNodeMediaMetadataCache(nodeId: endpoint.id);
    _nodeAnsweredBase.remove(endpoint.id);
    await checkNodeConnectivity(endpoint.id);
    if (endpoint.enabled) {
      requestNodeMediaMetadataWarmup(endpoint.id);
    }
  }

  Future<void> removeRemoteNode(String nodeId) async {
    remoteNodes.removeWhere((n) => n.id == nodeId);
    nodeConnectivity.remove(nodeId);
    nodeConnectivityError.remove(nodeId);
    invalidateNodeMediaMetadataCache(nodeId: nodeId);
    _nodeAnsweredBase.remove(nodeId);
    _validateActiveNode();
    await _save();
  }

  Future<void> setRemoteNodeEnabled(String nodeId, bool enabled) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      return;
    }

    await updateRemoteNode(node.copyWith(enabled: enabled));
    if (!enabled) {
      nodeConnectivity[nodeId] = false;
      nodeConnectivityError[nodeId] = '节点已禁用';
    }
  }

  // ── 设备唤醒 ──────────────────────────────────────────────────────────────

  WakeDevice? getWakeDeviceById(String id) =>
      wakeDevices.firstWhereOrNull((d) => d.id == id);

  Future<WakeDevice> addWakeDevice({
    required String name,
    required String mac,
    String target = '',
    int port = 9,
    WakeMode mode = WakeMode.auto,
    String relayNodeId = '',
    String probeNodeId = '',
    int count = 3,
  }) async {
    final device = WakeDevice(
      id: _createNodeId(),
      name: name.trim().isEmpty ? '未命名设备' : name.trim(),
      mac: mac.trim(),
      target: target.trim(),
      port: port,
      mode: mode,
      relayNodeId: relayNodeId,
      probeNodeId: probeNodeId,
      count: count,
    );
    wakeDevices.add(device);
    wakeStatus[device.id] = WakeStatus.idle;
    await _save();
    return device;
  }

  Future<void> updateWakeDevice(WakeDevice device) async {
    final index = wakeDevices.indexWhere((d) => d.id == device.id);
    if (index == -1) {
      return;
    }
    wakeDevices[index] = device;
    wakeDevices.refresh();
    await _save();
  }

  Future<void> removeWakeDevice(String id) async {
    wakeDevices.removeWhere((d) => d.id == id);
    wakeStatus.remove(id);
    await _save();
  }

  /// 发送唤醒包；配置了检测节点时再轮询它的上线状态
  Future<WakeReport> wakeDevice(String id) async {
    final device = getWakeDeviceById(id);
    if (device == null) {
      return const WakeReport(targets: [], errors: ['设备不存在']);
    }

    wakeStatus[id] = WakeStatus.waking;
    // Mock 模式不发真实网络包，也不探测节点
    if (MockMode.enabled) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      wakeStatus[id] = device.probeNodeId.isEmpty ? WakeStatus.sent : WakeStatus.online;
      return WakeReport(targets: ['${device.target.isEmpty ? '255.255.255.255' : device.target}:${device.port}']);
    }

    WakeReport report;
    try {
      report = await _dispatchWake(device);
      wakeStatus[id] = report.delivered ? WakeStatus.sent : WakeStatus.failed;
    } catch (e, st) {
      wakeStatus[id] = WakeStatus.failed;
      _logger.error('唤醒失败: ${device.name}', error: e, stackTrace: st);
      rethrow;
    }

    if (report.delivered && device.probeNodeId.isNotEmpty) {
      unawaited(_pollWakeOnline(device));
    }
    return report;
  }

  Future<WakeReport> _dispatchWake(WakeDevice device) {
    switch (device.mode) {
      case WakeMode.direct:
        return _sendMagicPacketDirect(device);
      case WakeMode.relay:
        final relay = getNodeById(device.relayNodeId);
        if (relay == null) {
          throw StateError('请先选择中继节点');
        }
        return _sendViaRelay(device, relay);
      case WakeMode.auto:
        return _sendAuto(device);
    }
  }

  /// 自动模式：本机与中继节点同处一个局域网时两路并发，否则只走中继
  ///
  /// 魔术包没有应答，直发成功只代表包出去了，判断不了设备收没收到。
  /// 因此用「中继节点的内网地址是否可达」来判断本机在不在那个局域网：
  /// 在局域网内就直发＋中继一起发（多一个包无害，成功率最高），
  /// 不在就只走中继，避免把一个注定到不了的广播当成发送成功。
  Future<WakeReport> _sendAuto(WakeDevice device) async {
    final relay = getNodeById(device.relayNodeId);
    if (relay == null) {
      return _sendMagicPacketDirect(device);
    }

    final sameLan = await isNodeLanReachable(relay.id);
    _logger.info('自动唤醒: ${device.name} | 中继=${relay.name} | 同局域网=$sameLan');
    if (!sameLan) {
      return _sendViaRelay(device, relay);
    }

    final results = await Future.wait<WakeReport>([
      _sendMagicPacketDirect(device).catchError(
        (Object e) => WakeReport(targets: const [], errors: ['直发 $e']),
      ),
      _sendViaRelay(device, relay).catchError(
        (Object e) => WakeReport(targets: const [], errors: ['中继 $e']),
      ),
    ]);
    return WakeReport(
      targets: [for (final r in results) ...r.targets],
      errors: [for (final r in results) ...r.errors],
    );
  }

  Future<WakeReport> _sendViaRelay(WakeDevice device, NodeEndpoint relay) async {
    final data = await callNodeAction(
      nodeId: relay.id,
      action: 'wake_host',
      params: {
        'mac': device.mac,
        'target': device.target,
        'port': device.port,
        'count': device.count,
      },
    );
    final target = (data['target'] ?? '').toString();
    return WakeReport(
      targets: ['${target.isEmpty ? '广播' : target}:${device.port}（经 ${relay.name}）'],
    );
  }

  /// 中继节点的内网地址是否可达：可达说明本机与它同处一个局域网
  Future<bool> isNodeLanReachable(String nodeId) async {
    final node = getNodeById(nodeId);
    final lan = (node?.lanApiBaseUrl ?? '').trim();
    if (node == null || !node.enabled || lan.isEmpty) {
      return false;
    }
    final result = await _probeNodeUrl(lan, timeout: probeConfirmTimeout);
    // 401 也说明这个地址通了，只是授权码不对
    return result != _ProbeResult.unreachable;
  }

  /// 本机直发：逐个子网广播地址发送，单个地址失败不影响其余地址
  ///
  /// 只发 255.255.255.255 在多数家用 AP 上会被丢掉（受限广播不出无线侧，
  /// 部分 AP 还默认隔离客户端广播），因此同时按本机网段补一份定向广播。
  ///
  /// 套接字绑定到本机私有地址而不是 0.0.0.0：手机同时开着移动数据时，
  /// 受限广播会按默认路由走蜂窝口，绑到 Wi-Fi 地址才能保证从无线网卡发出。
  Future<WakeReport> _sendMagicPacketDirect(WakeDevice device) async {
    final mac = _parseMacBytes(device.mac);
    final port = device.port <= 0 ? 9 : device.port;
    final count = device.count <= 0 ? 3 : device.count.clamp(1, 5);
    final configured = device.target.trim();

    final packet = Uint8List(102)
      ..fillRange(0, 6, 0xFF)
      ..setRange(6, 102, List<int>.generate(96, (i) => mac[i % 6]));

    final locals = await _localIpv4Addresses();
    final sources = locals.isEmpty
        ? <InternetAddress>[InternetAddress.anyIPv4]
        : locals;

    final sent = <String>[];
    final errors = <String>[];

    Future<void> dispatch(InternetAddress source) async {
      final socket = await RawDatagramSocket.bind(source, 0, reuseAddress: true);
      try {
        socket.broadcastEnabled = true;
        for (final address in _wakeTargets(configured, source)) {
          final label = '${address.address}:$port';
          try {
            for (int index = 0; index < count; index++) {
              socket.send(packet, address, port);
              if (index + 1 < count) {
                await Future<void>.delayed(const Duration(milliseconds: 80));
              }
            }
            if (!sent.contains(label)) {
              sent.add(label);
            }
          } catch (e) {
            final message = '$label $e';
            if (!errors.contains(message)) {
              errors.add(message);
            }
          }
        }
      } finally {
        socket.close();
      }
    }

    for (final source in sources) {
      try {
        await dispatch(source);
      } catch (e) {
        errors.add('绑定 $source 失败: $e');
      }
    }
    // 绑定具体网卡一个都没发出去时退回 0.0.0.0，至少保留"不绑定网卡"的老行为
    if (sent.isEmpty && !sources.contains(InternetAddress.anyIPv4)) {
      try {
        await dispatch(InternetAddress.anyIPv4);
      } catch (e) {
        errors.add('绑定 0.0.0.0 失败: $e');
      }
    }

    if (sent.isNotEmpty) {
      _logger.info(
        '唤醒包已发送: ${device.name} → ${sent.join(', ')} | 源地址 ${sources.join(', ')}',
      );
    } else {
      _logger.error('唤醒包全部发送失败: ${device.name} | ${errors.join(' ; ')}');
    }
    return WakeReport(targets: sent, errors: errors);
  }

  /// 蜂窝网卡常见命名，开移动数据时绑上去只会让广播走错网卡
  static const List<String> _cellularIfacePrefixes = <String>[
    'pdp_ip',
    'pdp',
    'rmnet',
    'ccmni',
    'wwan',
    'clat',
  ];

  /// 局域网网卡命名（Wi-Fi / 有线），命中则优先作为发包源
  static const List<String> _lanIfacePrefixes = <String>[
    'en',
    'wlan',
    'eth',
    'wl',
    'swlan',
  ];

  /// 虚拟网卡命名：VPN / 回环 / 虚拟机桥，发广播没有意义
  static const List<String> _virtualIfacePrefixes = <String>[
    'utun',
    'tun',
    'tap',
    'ppp',
    'ipsec',
    'awdl',
    'llw',
    'bridge',
    'vmnet',
    'docker',
    'veth',
    'br-',
    'virbr',
  ];

  /// 本机私有 IPv4 地址（Wi-Fi / 有线），用于枚举待发网段与绑定发包网卡
  ///
  /// 必须排除蜂窝网卡：移动数据的地址同样是内网段，绑上去发包会直接走蜂窝出口。
  Future<List<InternetAddress>> _localIpv4Addresses() async {
    final lan = <InternetAddress>[];
    final others = <InternetAddress>[];

    bool skip(String name) =>
        _cellularIfacePrefixes.any(name.startsWith) ||
        _virtualIfacePrefixes.any(name.startsWith);

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        final name = interface.name.toLowerCase();
        if (skip(name)) {
          continue;
        }
        final preferLan = _lanIfacePrefixes.any(name.startsWith);
        for (final address in interface.addresses) {
          if (!_isPrivateIpv4(address.rawAddress)) {
            continue;
          }
          final bucket = preferLan ? lan : others;
          if (!bucket.contains(address)) {
            bucket.add(address);
          }
        }
      }
    } catch (e, st) {
      _logger.error('枚举本机网段失败', error: e, stackTrace: st);
    }
    return lan.isNotEmpty ? lan : others;
  }

  /// 收集下发地址：显式配置的地址优先，另外必须带上本机网段的定向广播
  List<InternetAddress> _wakeTargets(String configured, InternetAddress source) {
    final targets = <String>[];
    void add(String value) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty && !targets.contains(trimmed)) {
        targets.add(trimmed);
      }
    }

    add(configured);
    // 按 /24 推算网段广播：家用网络基本都是这个掩码，误判也只是多发一个包
    final raw = source.rawAddress;
    if (raw.length == 4 && _isPrivateIpv4(raw)) {
      add('${raw[0]}.${raw[1]}.${raw[2]}.255');
    }
    add('255.255.255.255');

    final result = <InternetAddress>[];
    for (final target in targets) {
      final address = InternetAddress.tryParse(target);
      if (address == null) {
        throw FormatException('唤醒地址格式不正确: $target');
      }
      if (address.type != InternetAddressType.IPv4) {
        throw const FormatException('暂不支持 IPv6 唤醒地址');
      }
      result.add(address);
    }
    return result;
  }

  bool _isPrivateIpv4(List<int> raw) {
    return raw[0] == 10 ||
        (raw[0] == 172 && raw[1] >= 16 && raw[1] <= 31) ||
        (raw[0] == 192 && raw[1] == 168);
  }

  Uint8List _parseMacBytes(String input) {
    final cleaned = input.replaceAll(RegExp(r'[:\-.\s]'), '');
    if (cleaned.length != 12 || !RegExp(r'^[0-9a-fA-F]{12}$').hasMatch(cleaned)) {
      throw FormatException('MAC 地址格式不正确: $input');
    }
    return Uint8List.fromList(
      List<int>.generate(
        6,
        (i) => int.parse(cleaned.substring(i * 2, i * 2 + 2), radix: 16),
      ),
    );
  }

  /// 唤醒后按 2 秒间隔探测最多 60 秒
  Future<void> _pollWakeOnline(WakeDevice device) async {
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (wakeStatus[device.id] != WakeStatus.sent) {
        return;
      }
      await checkNodeConnectivity(device.probeNodeId);
      if (nodeConnectivity[device.probeNodeId] == true) {
        wakeStatus[device.id] = WakeStatus.online;
        return;
      }
    }
    if (wakeStatus[device.id] == WakeStatus.sent) {
      wakeStatus[device.id] = WakeStatus.timeout;
    }
  }

  Future<void> refreshNodeConnectivity() async {
    if (MockMode.enabled) return;
    final trace = TimingTrace('节点连通性全量确认');
    final enabledNodes = remoteNodes.where((n) => n.enabled).toList();
    final disabledNodes = remoteNodes.where((n) => !n.enabled).toList();
    for (final node in disabledNodes) {
      nodeConnectivity[node.id] = false;
      nodeConnectivityError[node.id] = '节点已禁用';
    }
    // 并发探：串行时 N 个节点的超时是累加的
    await Future.wait(enabledNodes.map((node) => checkNodeConnectivity(node.id)));
    trace.end(note: '节点数=${enabledNodes.length}');
  }

  Future<void> checkNodeConnectivity(String nodeId) async {
    if (MockMode.enabled) return;
    final node = getNodeById(nodeId);
    if (node == null) {
      return;
    }
    if (!node.enabled) {
      nodeConnectivity[nodeId] = false;
      nodeConnectivityError[nodeId] = '节点已禁用';
      return;
    }
    _circuitBreakedNodes.remove(nodeId);
    final trace = TimingTrace('节点探测', scope: node.name);

    // LAN 与 WAN 并发探：串行时「LAN 地址已失效」这一最常见的场景要把快速档超时
    // 完整付一遍才轮到 WAN，节点看起来就是慢半拍。
    final bases = <String>{
      if (node.lanApiBaseUrl != null && node.lanApiBaseUrl!.isNotEmpty) node.lanApiBaseUrl!,
      node.apiBaseUrl,
    }.toList(growable: false);
    final results = await Future.wait(
      bases.map((base) => _probeNodeUrl(base, timeout: _probeFastTimeout)),
    );
    trace.lap('快速档(${results.length}路并发)');

    // 任一路通了就算在线；没通的那一路不表态，不当失败证据。
    if (results.contains(_ProbeResult.ok)) {
      // bases 是 LAN 先、WAN 后，取第一个应答的就是「LAN 能用就用 LAN」。
      _nodeAnsweredBase[nodeId] = bases[results.indexOf(_ProbeResult.ok)];
      nodeConnectivity[nodeId] = true;
      nodeConnectivityError[nodeId] = '';
      trace.end();
      return;
    }

    // 401 说明节点在线、只是码不对：不熔断，改完授权码刷新即可恢复
    if (results.contains(_ProbeResult.unauthorized)) {
      nodeConnectivity[nodeId] = false;
      nodeConnectivityError[nodeId] = '授权码错误，请核对节点授权码';
      trace.end();
      return;
    }

    // 两个地址在快速档都没回：先别判死。节点可能只是忙（正在解压刚上传的归档、
    // 批量生成缩略图），也可能只是 Wi-Fi 抖了一下——一次抖动就熔断要用户手动重试，代价太不对称。
    // 确认档只放宽到 1.5s 并只跑一轮，避免把启动/保存路径拖成秒级阻塞。
    final confirmed = await _reprobeNode(node);
    trace.lap('确认档');
    if (confirmed == _ProbeResult.ok) {
      nodeConnectivity[nodeId] = true;
      nodeConnectivityError[nodeId] = '';
      trace.end();
      return;
    }
    if (confirmed == _ProbeResult.unauthorized) {
      nodeConnectivity[nodeId] = false;
      nodeConnectivityError[nodeId] = '授权码错误，请核对节点授权码';
      trace.end();
      return;
    }

    nodeConnectivity[nodeId] = false;
    nodeConnectivityError[nodeId] = '节点不可达';
    _circuitBreakedNodes.add(nodeId);
    trace.end(note: '判定熔断');
    _logger.info(
      '节点已熔断: ${node.name}（快速档+确认档均无响应 | LAN=${node.lanApiBaseUrl} WAN=${node.apiBaseUrl}）',
    );
  }

  Future<_ProbeResult> _probeNodeUrl(String? baseUrl, {required Duration timeout}) async {
    if (baseUrl == null || baseUrl.isEmpty) return _ProbeResult.unreachable;
    final urls = _candidateNodeCallUrls(baseUrl);
    for (final url in urls) {
      // 【临时埋点】把每一次候选地址尝试的 Dio 异常类型打出来：
      // 实测快速档标称 200ms 却付了 1.2s，需要区分「超时本身没生效」和
      // 「启动期主 isolate 忙，超时回调被排后」这两种可能。
      final probeTrace = TimingTrace('探测', scope: url);
      try {
        await _probeDio.post<dynamic>(
          url,
          data: <String, dynamic>{'action': 'ping', 'params': <String, dynamic>{}},
          options: Options(
            connectTimeout: timeout,
            receiveTimeout: timeout,
            sendTimeout: timeout,
          ),
        );
        probeTrace.end(note: 'ok');
        return _ProbeResult.ok;
      } on DioException catch (e) {
        probeTrace.end(note: 'type=${e.type} status=${e.response?.statusCode}');
        final status = e.response?.statusCode;
        if (status == 401) {
          return _ProbeResult.unauthorized;
        }
        // 拿到 HTTP 状态码就说明进程在线：熔断判的是「可达性」，
        // 节点忙到回 429/503 也绝不能算死节点。
        if (status != null) {
          if (status == 503 || status == 429) {
            _logger.info('节点在线但繁忙(HTTP $status): $baseUrl');
          }
          return _ProbeResult.ok;
        }
        continue;
      } catch (e) {
        probeTrace.end(note: '非Dio异常=${e.runtimeType}');
        continue;
      }
    }
    return _ProbeResult.unreachable;
  }

  /// 确认档复探：把节点已知的所有地址（生效/LAN/WAN）并发问一遍，
  /// 只要不是全部无响应就给出结论。串行会让「一个地址已失效」的节点
  /// 把每个候选地址的超时都付一遍。
  Future<_ProbeResult> _reprobeNode(NodeEndpoint node) async {
    final bases = <String>{node.effectiveApiBaseUrl, node.lanApiBaseUrl ?? '', node.apiBaseUrl}
        .where((b) => b.isNotEmpty)
        .toList(growable: false);
    final results = await Future.wait(
      bases.map((base) => _probeNodeUrl(base, timeout: probeConfirmTimeout)),
    );
    if (results.contains(_ProbeResult.ok)) {
      _nodeAnsweredBase[node.id] = bases[results.indexOf(_ProbeResult.ok)];
      return _ProbeResult.ok;
    }
    if (results.contains(_ProbeResult.unauthorized)) return _ProbeResult.unauthorized;
    return _ProbeResult.unreachable;
  }

  /// 熔断位只是探测留下的缓存，真实业务请求值得一次确认档的复探：
  /// 节点活着就当场解除，不必让用户跑去设置页手动重试。
  /// 同节点的并发请求共用这一次复探，避免一屏封面刷出十几个 ping。
  Future<void> _ensureNodeReachable(NodeEndpoint node) async {
    if (!_circuitBreakedNodes.contains(node.id)) return;
    // 复探已经单飞，打点不能再单飞：跟着等的请求各自 end 一次，
    // 同一条判定会在同一毫秒刷出 N 行（N = 本屏并发请求数）。
    final isOwner = _nodeBreakChecks[node.id] == null;
    final trace = isOwner
        ? TimingTrace('熔断节点业务请求前复探', scope: node.name)
        : null;
    final alive = await (_nodeBreakChecks[node.id] ??= _reprobeNode(node).whenComplete(() {
      // 必须用块体：箭头写法会把 remove() 返回的那个 Future（正是本 Future）
      // 当成 whenComplete 的后续去等，自锁后永不完成。
      _nodeBreakChecks.remove(node.id);
    }));
    trace?.end(note: '结果=$alive');
    if (alive == _ProbeResult.ok) {
      _circuitBreakedNodes.remove(node.id);
      nodeConnectivity[node.id] = true;
      nodeConnectivityError[node.id] = '';
      _logger.info('节点复探成功，已自动解除熔断: ${node.name}');
      return;
    }
    if (alive == _ProbeResult.unauthorized) {
      nodeConnectivityError[node.id] = '授权码错误，请核对节点授权码';
    }
    throw StateError('节点已熔断: ${node.name}，请在设置中手动重试');
  }

  Future<void> updateLocalSettings({
    required bool enabled,
    required String nodeName,
    required int port,
  }) async {
    localNodeEnabled.value = enabled;
    localNodeName.value = nodeName.trim().isEmpty ? '本机节点' : nodeName.trim();
    localNodePort.value = port;
    // 授权码只由生成/重置产生：为空时补一个，保证设置页总有可分享的码
    if (localNodeAuthCode.value.isEmpty) {
      localNodeAuthCode.value = generateLocalAuthCode();
    }

    await _save();

    if (enabled) {
      // 端口/授权码变更必须重建监听，否则旧进程仍按老配置校验
      await restartLocalNodeServer();
    } else {
      await stopLocalNodeServer();
    }

    await _refreshLocalApiList();
  }

  /// 生成随机授权码：16 位十六进制，分段只影响观感、不影响比对。
  String generateLocalAuthCode() {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (int i = 0; i < 16; i++) {
      buffer.write(random.nextInt(16).toRadixString(16).toUpperCase());
    }
    final hex = buffer.toString();
    return '${hex.substring(0, 4)}-${hex.substring(4, 8)}-${hex.substring(8, 12)}-${hex.substring(12)}';
  }

  /// 换发新的授权码并让节点立即按新码校验（旧码即刻失效）。
  Future<void> regenerateLocalAuthCode() async {
    localNodeAuthCode.value = generateLocalAuthCode();
    await _save();
    if (localNodeEnabled.value) {
      await restartLocalNodeServer();
    }
    _logger.info('本机节点授权码已重置');
  }

  Future<void> restartLocalNodeServer() async {
    await stopLocalNodeServer();
    await startLocalNodeServer();
  }

  Future<void> startLocalNodeServer() async {
    if (Platform.isAndroid || Platform.isIOS) {
      _logger.info('移动端不支持启动本地节点服务，已跳过');
      return;
    }
    // 演示模式不启动真实节点服务
    if (MockMode.enabled) return;

    if (localNodeAuthCode.value.isEmpty) {
      localNodeAuthCode.value = generateLocalAuthCode();
      await _save();
    }

    // 检查 Rust 服务器是否已在运行
    if (http_bridge_api.isNodeServerRunning()) {
      _logger.info('节点服务已在运行');
      return;
    }

    // 已用无头模式切出去过：端口被独立 slime_node 占着，内置服务再起只会 bind 失败。
    // 端口上有节点应答就当本机节点已就绪，避免重新打开界面时刷一条错误日志。
    if (await _isPortServingNode(localNodePort.value)) {
      _logger.info('端口 ${localNodePort.value} 已有节点进程在运行，跳过内置服务');
      return;
    }

    try {
      // 调用 Rust 启动节点服务器（授权码明文交给 Rust，Rust 只保存其 sha256 摘要）
      http_bridge_api.startNodeServer(
        host: '0.0.0.0',
        port: localNodePort.value,
        name: localNodeName.value,
        authCode: localNodeAuthCode.value,
      );
      _logger.info('节点服务已启动 (Rust): ${localNodePort.value}');
    } catch (e, st) {
      _logger.error('启动节点服务失败', error: e, stackTrace: st);
      rethrow;
    }
  }

  Future<void> stopLocalNodeServer() async {
    if (!http_bridge_api.isNodeServerRunning()) {
      return;
    }

    try {
      http_bridge_api.stopNodeServer();
      _logger.info('节点服务已停止');
    } catch (e, st) {
      _logger.error('停止节点服务失败', error: e, stackTrace: st);
    }
  }

  bool get isLocalServerRunning => http_bridge_api.isNodeServerRunning();

  /// 本机端口上是否已有节点在应答（通常是无头模式的独立进程）。
  ///
  /// 只探测 127.0.0.1：判断的是"这个端口还能不能给内置服务用"，不需要外网可达性。
  Future<bool> _isPortServingNode(int port) async {
    final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 300);
    try {
      final request = await client.getUrl(Uri.parse('http://127.0.0.1:$port/health'));
      final response = await request.close().timeout(const Duration(milliseconds: 600));
      await response.drain<void>();
      return response.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<List<Map<String, dynamic>>> fetchNodeNovels(NodeEndpoint node) async {
    // with_cover=false：列表只取元数据，跳过节点侧逐本封面读盘 + base64
    //（500 本 ≈ 20~40MB JSON 是远程书架首屏卡顿主因）。封面改由
    // buildNodeNovelCoverUrl 按需流式取。旧节点不认识该参数会忽略之，
    // 仍回内嵌 base64——客户端两条来源都兼容。
    final response = await _callNode(
      node: node,
      action: 'list_novels',
      params: const <String, dynamic>{'with_cover': false},
    );

    final data = response['data'];
    if (data is! List) {
      return <Map<String, dynamic>>[];
    }

    return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// 构造远程小说封面的按需 URL（GET /node/novel_cover）。
  ///
  /// 与 buildNodeMediaUrl 同一授权口径：Image.network 注不了自定义请求头，
  /// 摘要放 `?sw_auth=<sha256>` 查询参数；节点侧按 novel_id 反查库内封面路径，
  /// 不接受任意文件路径。节点不存在时返回 null（调用方显示占位）。
  String? buildNodeNovelCoverUrl({
    required String nodeId,
    required String novelId,
    int? width,
    int? cacheBuster,
  }) {
    final node = getNodeById(nodeId);
    if (node == null) return null;
    final normalized = _normalizeBaseUrl(_baseUrlFor(node));
    final params = <String, String>{'novel_id': novelId};
    if (width != null && width > 0) {
      params['width'] = width.toString();
    }
    // 封面被替换后节点按 id 覆盖写同名文件，URL 不变会导致客户端缓存旧图；
    // 用书籍 modified_at 作为缓存版本号拼进 URL
    if (cacheBuster != null && cacheBuster > 0) {
      params['v'] = cacheBuster.toString();
    }
    final digest = _authDigestForUrl(normalized);
    if (digest != null) {
      params[_authQueryParamName] = digest;
    }
    final uri = Uri.parse('$normalized/node/novel_cover').replace(queryParameters: params);
    return uri.toString();
  }

  Future<List<Map<String, dynamic>>> fetchNodeMediaCollections(NodeEndpoint node) async {
    final response = await _callNode(
      node: node,
      action: 'list_media_collections',
      params: const <String, dynamic>{},
    );

    final data = response['data'];
    if (data is! List) {
      return <Map<String, dynamic>>[];
    }
    return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<List<Map<String, dynamic>>> fetchNodeMediaFolders(NodeEndpoint node) async {
    final response = await _callNode(
      node: node,
      action: 'list_media_folders',
      params: const <String, dynamic>{},
    );

    final data = response['data'];
    if (data is! List) {
      return <Map<String, dynamic>>[];
    }
    return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<List<Map<String, dynamic>>> fetchNodeSmartFolders(NodeEndpoint node) async {
    final response = await _callNode(
      node: node,
      action: 'list_smart_folders',
      params: const <String, dynamic>{},
    );

    final data = response['data'];
    if (data is! List) {
      return <Map<String, dynamic>>[];
    }
    return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<List<Map<String, dynamic>>> fetchNodeMediaCollectionItems({
    required String nodeId,
    required String collectionId,
    ProgressCallback? onReceiveProgress,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }

    final Map<String, dynamic> response;
    if (onReceiveProgress != null) {
      // 需要报告进度时直接走 _performNodeCall，绕过去重缓存
      final payload = <String, dynamic>{
        'action': 'get_media_collection_items',
        'params': _sanitizeJsonMap(<String, dynamic>{'collection_id': collectionId}),
      };
      response = await _performNodeCall(
        node: node,
        action: 'get_media_collection_items',
        requestPayload: payload,
        onReceiveProgress: onReceiveProgress,
      );
    } else {
      response = await _callNode(
        node: node,
        action: 'get_media_collection_items',
        params: <String, dynamic>{'collection_id': collectionId},
      );
    }

    final data = response['data'];
    if (data is! List) {
      return <Map<String, dynamic>>[];
    }
    return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<List<Map<String, dynamic>>> scanNodeMediaFolders({
    required String nodeId,
    required String folderPath,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }

    final response = await _callNode(
      node: node,
      action: 'scan_media_folders',
      params: <String, dynamic>{'folder_path': folderPath},
    );

    final data = response['data'];
    if (data is! List) {
      return <Map<String, dynamic>>[];
    }
    return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// 让节点重新扫描**已被导入过**的媒体目录，返回与导入同形状的集合 JSON。
  ///
  /// 与 [importNodeMediaFolder] 的区别只有一条：绕开「该文件夹已导入」拦截，
  /// 对同一 folder_path 做 upsert 覆盖。节点的盘上文件被外部增删（NAS 上直接
  /// 拷文件、别的设备删了几张图）之后，这是唯一能让库同步回来的入口。
  ///
  /// [generateThumbnails] = true 时节点会给重扫出来的文件预生成缩略图：
  /// 盘上新增的文件必然没有旁路缓存，不预热的话客户端点进去才开始出图。
  /// [coverWidth] 必须与客户端封面请求宽度一致（缓存 key 含宽度），
  /// 0 表示原图档（客户端不带宽度请求），节点据此跳过预生成。
  ///
  /// 返回 null = 节点没给 data（异常形状），调用方按「无信息」处理。
  /// 节点出错（路径不存在等）照常抛异常，错误原文由调用方展示，不吞。
  Future<Map<String, dynamic>?> rescanNodeMediaFolder({
    required String nodeId,
    required String folderPath,
    bool generateThumbnails = false,
    int? coverWidth,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }

    final response = await _callNode(
      node: node,
      action: 'rescan_media_folder',
      params: <String, dynamic>{
        'folder_path': folderPath,
        'generate_thumbnails': generateThumbnails,
        'cover_width': ?coverWidth,
      },
    );

    final data = response['data'];
    if (data is! Map) {
      return null;
    }
    return Map<String, dynamic>.from(data);
  }

  /// 列举节点上 [path] 目录下的一级子目录路径列表。
  Future<List<String>> listNodeDirectories({required String nodeId, required String path}) async {
    final node = getNodeById(nodeId);
    if (node == null) throw StateError('节点不存在: $nodeId');
    final response = await _callNode(
      node: node,
      action: 'list_directories',
      params: <String, dynamic>{'path': path},
    );
    final data = response['data'];
    if (data is! List) return <String>[];
    return data.whereType<String>().toList();
  }

  /// 在节点 [path] 创建物理目录，成功返回 true。
  Future<bool> createNodeDirectory({required String nodeId, required String path}) async {
    final node = getNodeById(nodeId);
    if (node == null) throw StateError('节点不存在: $nodeId');
    final response = await _callNode(
      node: node,
      action: 'create_directory',
      params: <String, dynamic>{'path': path},
    );
    return response['data'] == true;
  }

  /// 重命名节点上物理目录（[oldPath] 与 [newPath] 均为完整路径），成功返回 true。
  Future<bool> renameNodeDirectory({
    required String nodeId,
    required String oldPath,
    required String newPath,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) throw StateError('节点不存在: $nodeId');
    final response = await _callNode(
      node: node,
      action: 'rename_directory',
      params: <String, dynamic>{'old_path': oldPath, 'new_path': newPath},
    );
    return response['data'] == true;
  }

  Future<Map<String, dynamic>?> importNodeMediaFolder({
    required String nodeId,
    required String folderPath,
    bool generateThumbnails = false,
    bool preserveStructure = false,
    String? baseFolderId,
    int? coverWidth,
    String? displayName,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }

    final response = await _callNode(
      node: node,
      action: 'import_media_folder',
      params: <String, dynamic>{
        'folder_path': folderPath,
        'generate_thumbnails': generateThumbnails,
        'preserve_structure': preserveStructure,
        'base_folder_id': baseFolderId,
        // 预生成缩略图的宽度必须与客户端封面请求宽度一致，
        // 否则节点内存缓存 key（含 width）不同，导入预热等于白跑。
        // 0 = 原图档（客户端请求不带宽度），节点据此跳过预生成。
        'cover_width': ?coverWidth,
        // 库内显示名：上传时磁盘目录可能被唯一化（照片 → 照片 (2)），
        // 传原目录名让节点侧的文件夹/集合标题保持原样（同名允许共存）。
        // 旧节点不认识该字段会忽略，行为退回磁盘目录名。
        'display_name': ?displayName,
      },
    );

    final data = response['data'];
    if (data is! Map) {
      return null;
    }
    return Map<String, dynamic>.from(data);
  }

  /// 从节点媒体直链反查「哪个节点 + 节点上的绝对路径」。
  ///
  /// 用途：预览页手里只有播放 URL（Image.network / 播放器只吃 URL），
  /// 但取振幅必须回到节点侧算，需要还原出 nodeId 与 filePath。
  /// 匹配依据是 base url 前缀；非节点链接（本地文件、外链）返回 null。
  ({String nodeId, String filePath})? resolveNodeFromMediaUrl(String url) {
    if (!url.startsWith('http://') && !url.startsWith('https://')) return null;
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final path = uri.queryParameters['path'];
    if (path == null || path.isEmpty) return null;
    // 去掉查询串后按 base url 前缀匹配节点
    final origin = '${uri.scheme}://${uri.authority}';
    for (final node in remoteNodes) {
      final base = _normalizeBaseUrl(_baseUrlFor(node));
      if (base.startsWith(origin)) {
        return (nodeId: node.id, filePath: path);
      }
    }
    return null;
  }

  /// 取远程节点上某个媒体文件的振幅波形（0~1，长度 = bins）。
  ///
  /// [ensure] = false 只读节点已有缓存（没有则返回 null，不触发计算）；
  /// true 表示让节点现算并落盘。**解码永远在节点侧做**，客户端只收几 KB
  /// 的 JSON —— 移动端走远程节点时绝不能把整段视频拉到本地跑 ffmpeg。
  ///
  /// [filePath] 是节点上的绝对路径（不是客户端路径）。
  Future<List<double>?> fetchNodeMediaWaveform({
    required String nodeId,
    required String filePath,
    int bins = 1200,
    bool ensure = false,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) throw StateError('节点不存在: $nodeId');
    final response = await _callNode(
      node: node,
      action: ensure ? 'ensure_media_waveform' : 'read_media_waveform',
      params: <String, dynamic>{'file_path': filePath, 'bins': bins},
    );
    final data = response['data'];
    if (data is! Map) return null;
    final arr = data['data'];
    if (arr is! List || arr.isEmpty) return null;
    return arr.map((e) => (e as num).toDouble()).toList(growable: false);
  }

  /// 让节点重新检查指定范围内的集合封面，缺失的由节点后台补生成。
  ///
  /// [folderId]：节点原始文件夹 ID，扫描其整棵子树（含所有层级）；
  /// [collectionIds]：节点原始集合 ID 列表；
  /// 两者都不传表示节点上的全部集合。
  /// [force] = true 为覆盖模式：节点先清掉这些集合已有的缩略图缓存再重新生成。
  /// 返回本次纳入扫描的集合数（生成进度由 `get_thumb_progress` 上报）。
  Future<int> rescanNodeMediaCovers({
    required String nodeId,
    String? folderId,
    List<String>? collectionIds,
    int? width,
    bool force = false,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }

    final response = await _callNode(
      node: node,
      action: 'rescan_media_covers',
      params: <String, dynamic>{
        // 两种范围互斥：传了集合列表就按列表，否则按文件夹子树
        'folder_id': ?folderId,
        'collection_ids': ?collectionIds,
        // 生成宽度必须与客户端封面请求一致，否则节点缓存 key 不同、等于白生成
        'width': ?width,
        if (force) 'force': true,
      },
    );

    final data = response['data'];
    if (data is! Map) return 0;
    return int.tryParse('${data['count']}') ?? 0;
  }

  Future<void> renameNodeMediaCollection({
    required String nodeId,
    required String collectionId,
    required String title,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }

    await _callNode(
      node: node,
      action: 'rename_media_collection',
      params: <String, dynamic>{'collection_id': collectionId, 'title': title},
    );
  }

  Future<void> deleteNodeMediaCollection({
    required String nodeId,
    required String collectionId,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }

    await _callNode(
      node: node,
      action: 'delete_media_collection',
      params: <String, dynamic>{'collection_id': collectionId},
    );
  }

  Future<void> moveNodeMediaCollectionToFolder({
    required String nodeId,
    required String collectionId,
    String? folderId,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }

    await _callNode(
      node: node,
      action: 'move_media_collection_to_folder',
      params: <String, dynamic>{'collection_id': collectionId, 'folder_id': folderId},
    );
  }

  Future<Map<String, dynamic>> createNodeMediaFolder({
    required String nodeId,
    required String name,
    String? parentId,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }

    final response = await _callNode(
      node: node,
      action: parentId == null ? 'create_media_folder' : 'create_child_media_folder',
      params: <String, dynamic>{'name': name, 'parent_id': ?parentId},
    );
    return Map<String, dynamic>.from(response['data'] as Map<dynamic, dynamic>);
  }

  Future<void> renameNodeMediaFolder({
    required String nodeId,
    required String folderId,
    required String name,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }

    await _callNode(
      node: node,
      action: 'rename_media_folder',
      params: <String, dynamic>{'folder_id': folderId, 'name': name},
    );
  }

  Future<void> deleteNodeMediaFolder({required String nodeId, required String folderId}) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }

    await _callNode(
      node: node,
      action: 'delete_media_folder',
      params: <String, dynamic>{'folder_id': folderId},
    );
  }

  String buildNodeMediaUrl({
    required String nodeId,
    required String filePath,
    int? thumbnailWidth,
    bool isCover = false,
    int? cacheVersion,
  }) {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }
    final normalized = _normalizeBaseUrl(_baseUrlFor(node));
    final params = <String, String>{'path': filePath};
    if (thumbnailWidth != null && thumbnailWidth > 0) {
      params['width'] = thumbnailWidth.toString();
    }
    if (isCover) {
      params['mode'] = 'cover';
    }
    // 覆盖重建后换一个 URL，绕开客户端按 URL 缓存的旧解码结果
    if (cacheVersion != null && cacheVersion > 0) {
      params['v'] = cacheVersion.toString();
    }
    // 图片/视频 URL 直接交给 Image.network 与播放器，拿不到自定义请求头，
    // 因此这里把摘要放进查询参数（节点侧 sw_auth 与 X-SW-Auth 等价放行）。
    final digest = _authDigestForUrl(normalized);
    if (digest != null) {
      params[_authQueryParamName] = digest;
    }
    final uri = Uri.parse('$normalized/node/media').replace(queryParameters: params);
    return uri.toString();
  }

  String buildNodeUploadUrl(String nodeId) {
    final node = getNodeById(nodeId);
    if (node == null) throw StateError('节点不存在: $nodeId');
    final normalized = _normalizeBaseUrl(_baseUrlFor(node));
    return '$normalized/node/upload';
  }

  /// 反推「把本地目录拖进远程文件夹」时，该文件夹在节点磁盘上的落点。
  ///
  /// 节点的 `MediaFolder` 只有库内 ID、没有磁盘路径，因此由节点侧从该文件夹下
  /// 已有集合的目录反推。返回 `(targetDir, candidates)`：
  /// - `targetDir` 非空 = 唯一确定，可直接上传；
  /// - `targetDir` 为空 = 文件夹还没集合或跨多个目录，`candidates` 供目录浏览器兜底。
  Future<({String targetDir, List<String> candidates})> resolveNodeUploadTarget({
    required String nodeId,
    required String folderId,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) throw StateError('节点不存在: $nodeId');
    final response = await _callNode(
      node: node,
      action: 'resolve_folder_upload_target',
      params: <String, dynamic>{'folder_id': folderId},
    );
    final data = response['data'];
    if (data is! Map) {
      return (targetDir: '', candidates: const <String>[]);
    }
    final candidates = (data['candidates'] as List?)?.map((e) => e.toString()).toList() ??
        const <String>[];
    return (targetDir: (data['target_dir'] ?? '').toString(), candidates: candidates);
  }

  /// 把本地 zip 归档上传到节点的 [destDir] 并在节点侧解压。
  ///
  /// 走的是原始字节流（非 multipart）：节点端 `upload_handler` 用 `io::copy` 流式落盘，
  /// 所以必须显式给 Content-Length，且请求体不能进 Dart 内存。
  Future<void> uploadArchiveToNode({
    required String nodeId,
    required String zipPath,
    required String destDir,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) throw StateError('节点不存在: $nodeId');
    await _ensureNodeReachable(node);
    final normalized = _normalizeBaseUrl(_baseUrlFor(node));
    final url =
        '$normalized/node/upload/archive?dest=${Uri.encodeComponent(destDir)}';
    final file = File(zipPath);
    final length = await file.length();
    final txBytes = length;
    try {
      final resp = await _dio.post<dynamic>(
        url,
        data: file.openRead(),
        options: Options(
          contentType: 'application/octet-stream',
          headers: <String, dynamic>{Headers.contentLengthHeader: length},
          // 大目录在家庭宽带上是分钟级操作，超时按最坏情况给
          sendTimeout: const Duration(minutes: 30),
          receiveTimeout: const Duration(minutes: 5),
        ),
      );
      final body = resp.data is Map ? Map<String, dynamic>.from(resp.data as Map) : <String, dynamic>{};
      _recordAppTraffic(txBytes: txBytes, rxBytes: 256);
      if (body['success'] != true) {
        throw Exception((body['error'] ?? '归档上传失败').toString());
      }
      // 一次完整的归档上传是最硬的存活证明：清掉熔断位，否则大文件传输期间
      // 一次抖动的 ping 就会让紧随其后的 import_media_folder 被直接拒掉。
      _circuitBreakedNodes.remove(nodeId);
      nodeConnectivity[nodeId] = true;
      nodeConnectivityError[nodeId] = '';
    } on DioException catch (e) {
      final business = _nodeBusinessError(e);
      _logger.error('归档上传失败: $nodeId | $zipPath', error: business ?? e);
      throw business ?? e;
    }
  }

  /// 上传本地文件到远程节点的媒体库。
  /// [localPath] 本地文件路径，[collectionId] 可选目标集合（null 则扫描创建）。
  Future<Map<String, dynamic>> uploadMediaToNode({
    required String nodeId,
    required String localPath,
    String? collectionId,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) throw StateError('节点不存在: $nodeId');
    await _ensureNodeReachable(node);
    final uploadUrl = buildNodeUploadUrl(nodeId);
    final file = File(localPath);
    final filename = localPath.split('/').last;
    final txBytes = await file.length();
    try {
      // 单文件上传走**原始字节流**，不用 multipart：
      // 节点侧是一条流式落盘通道（`handle_file_upload`，理由同归档上传——
      // 通用 body 读取是 vec![0u8; content_length]，大媒体文件会打爆内存）。
      // multipart 会让节点还得在内存里攒边界帧，对几百 MB 的文件毫无意义。
      // 目标目录与文件名都放 query：客户端已明确知道落哪个集合、叫什么名字。
      final destDir = await _resolveNodeUploadDir(nodeId, uploadUrl, collectionId);
      // dest 必须是明确的目标目录：节点侧 `handle_file_upload` 只往已存在的
      // 绝对目录落盘（刻意不接受「猜一个暂存目录」，否则用户不知道文件去哪了）。
      // 所以「没指定集合」或「集合反查不到目录」都是真错误，必须拦下并说清原因。
      if (destDir == null || destDir.isEmpty) {
        throw Exception(
          collectionId == null || collectionId.isEmpty
              ? '上传需要指定目标集合（未给出 collection_id，无法确定节点落盘目录）'
              : '无法确定节点落盘目录（集合 $collectionId 不存在或缺少文件夹路径）',
        );
      }
      final query = <String, String>{
        'dest': destDir,
        'filename': filename,
        if (collectionId != null && collectionId.isNotEmpty) 'collection_id': collectionId,
      };
      final uri = Uri.parse(
        uploadUrl,
      ).replace(queryParameters: query);
      final resp = await _dio.post<Map<String, dynamic>>(
        uri.toString(),
        data: file.openRead(),
        options: Options(
          headers: <String, Object>{
            Headers.contentLengthHeader: txBytes,
            Headers.contentTypeHeader: 'application/octet-stream',
          },
          sendTimeout: const Duration(seconds: 300),
          receiveTimeout: const Duration(seconds: 120),
        ),
      );
      final body = resp.data ?? <String, dynamic>{};
      _recordAppTraffic(txBytes: txBytes, rxBytes: 256);
      if (body['success'] == true) {
        return Map<String, dynamic>.from(body['data'] as Map? ?? <String, dynamic>{});
      }
      throw Exception((body['error'] ?? '上传失败').toString());
    } on DioException catch (e) {
      final business = _nodeBusinessError(e);
      _logger.error('媒体上传失败: $nodeId | $filename', error: business ?? e);
      throw business ?? e;
    }
  }

  /// 反推单文件上传该落到节点上的哪个目录。
  ///
  /// [collectionId] 是节点原始集合 ID：优先用它反查该集合的 `folder_path`
  /// （集合目录就是它的媒体文件所在目录）。集合没有 folder_path 时返回 null，
  /// 让调用方明确失败——绝不猜一个目录把文件丢进去。
  Future<String?> _resolveNodeUploadDir(
    String nodeId,
    String uploadUrl,
    String? collectionId,
  ) async {
    if (collectionId == null || collectionId.isEmpty) {
      return null;
    }
    try {
      final raw = await _callNode(
        node: getNodeById(nodeId)!,
        action: 'list_media_collections',
        params: const <String, dynamic>{},
      );
      final data = raw['data'];
      if (data is! List) return null;
      for (final item in data) {
        if (item is! Map) continue;
        if ((item['id'] ?? '').toString() != collectionId) continue;
        final folderPath = (item['folder_path'] ?? '').toString().trim();
        return folderPath.isEmpty ? null : folderPath;
      }
    } catch (e) {
      _logger.error('反查节点集合目录失败: $collectionId -> $e');
    }
    return null;
  }

  /// 删除节点上某个集合的本地物理文件（不删除数据库记录）。
  Future<int> deleteNodeCollectionLocalFiles({
    required String nodeId,
    required String rawCollectionId,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) throw StateError('节点不存在: $nodeId');
    final response = await _callNode(
      node: node,
      action: 'delete_collection_local_files',
      params: <String, dynamic>{'collection_id': rawCollectionId},
    );
    final data = response['data'];
    if (data is Map) {
      return (data['deleted'] as num?)?.toInt() ?? 0;
    }
    return 0;
  }

  /// 从节点下载单个文件到本地指定路径。
  Future<void> downloadNodeFileTo({
    required String nodeId,
    required String filePath,
    required String savePath,
  }) async {
    final url = buildNodeMediaUrl(nodeId: nodeId, filePath: filePath);
    await _dio.download(
      url,
      savePath,
      options: Options(receiveTimeout: const Duration(minutes: 10)),
    );
  }

  Future<List<Map<String, dynamic>>> searchNodeNovels(NodeEndpoint node, String keyword) async {
    final response = await _callNode(
      node: node,
      action: 'search_all_novels',
      params: <String, dynamic>{'keyword': keyword},
    );

    final data = response['data'];
    if (data is! List) {
      return <Map<String, dynamic>>[];
    }

    return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> deleteNodeNovel({required String nodeId, required String novelId}) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }

    await _callNode(
      node: node,
      action: 'delete_novel',
      params: <String, dynamic>{'novel_id': novelId},
    );
  }

  /// 列出节点上的小说文件夹（JSON 原样返回，字段见 `list_novel_folders`）。
  Future<List<Map<String, dynamic>>> fetchNodeNovelFolders(NodeEndpoint node) async {
    final response = await _callNode(
      node: node,
      action: 'list_novel_folders',
      params: const <String, dynamic>{},
    );
    final data = response['data'];
    if (data is! List) return <Map<String, dynamic>>[];
    return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// 在节点上新建小说文件夹；[parentId] 非空时建成该夹的子夹。
  /// 返回节点回的文件夹 JSON（含 id）；节点侧对空名 / 父夹不存在一律报错。
  Future<Map<String, dynamic>> createNodeNovelFolder({
    required String nodeId,
    required String name,
    String? parentId,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) throw StateError('节点不存在: $nodeId');
    final response = await _callNode(
      node: node,
      action: 'create_novel_folder',
      params: <String, dynamic>{
        'name': name,
        'parent_id': ?parentId,
      },
    );
    final data = response['data'];
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  /// 重命名节点上的小说文件夹。
  Future<void> renameNodeNovelFolder({
    required String nodeId,
    required String folderId,
    required String name,
  }) => callNodeAction(
    nodeId: nodeId,
    action: 'rename_novel_folder',
    params: <String, dynamic>{'folder_id': folderId, 'name': name},
  );

  /// 删除节点上的小说文件夹（夹内书籍移回根目录，不删书）。
  Future<void> deleteNodeNovelFolder({
    required String nodeId,
    required String folderId,
  }) => callNodeAction(
    nodeId: nodeId,
    action: 'delete_novel_folder',
    params: <String, dynamic>{'folder_id': folderId},
  );

  /// 删除节点上的小说文件夹 **及其中的所有书籍**。
  Future<void> deleteNodeNovelFolderWithNovels({
    required String nodeId,
    required String folderId,
  }) => callNodeAction(
    nodeId: nodeId,
    action: 'delete_novel_folder_with_novels',
    params: <String, dynamic>{'folder_id': folderId},
  );

  /// 批量设置节点上小说文件夹的排序（[folderIds] 按新顺序排列，必须是 rawId）。
  Future<void> reorderNodeNovelFolders({
    required String nodeId,
    required List<String> folderIds,
  }) => callNodeAction(
    nodeId: nodeId,
    action: 'reorder_novel_folders',
    params: <String, dynamic>{'folder_ids': folderIds},
  );

  Future<void> updateNodeNovelInfo({
    required String nodeId,
    required String novelId,
    String? title,
    String? author,
    String? notes,
    List<String>? tags,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }

    await _callNode(
      node: node,
      action: 'update_novel_info',
      params: <String, dynamic>{
        'novel_id': novelId,
        // ignore: use_null_aware_elements
        if (title != null) 'title': title,
        // ignore: use_null_aware_elements
        if (author != null) 'author': author,
        // ignore: use_null_aware_elements
        if (notes != null) 'notes': notes,
        // ignore: use_null_aware_elements
        if (tags != null) 'tags': tags,
      },
    );
  }

  Future<void> setNodeNovelFavorite({
    required String nodeId,
    required String novelId,
    required bool isFavorite,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }

    try {
      await _callNode(
        node: node,
        action: 'set_novel_favorite',
        params: <String, dynamic>{'novel_id': novelId, 'is_favorite': isFavorite},
      );
    } catch (_) {
      await _callNode(
        node: node,
        action: 'update_novel_info',
        params: <String, dynamic>{'novel_id': novelId, 'is_favorite': isFavorite},
      );
    }
  }

  /// 把远程书的阅读进度写回节点（0.0~1.0 归一化）。
  ///
  /// 之前这条链路完全不存在：客户端远程阅读路径从不保存进度，节点侧也没有
  /// 写 action，于是「读到第 20 章 → 关掉 → 再打开还是第 1 章」且无任何提示。
  Future<void> updateNodeNovelProgress({
    required String nodeId,
    required String novelId,
    required double progress,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }
    await _callNode(
      node: node,
      action: 'update_reading_progress',
      params: <String, dynamic>{'novel_id': novelId, 'progress': progress},
    );
  }

  Future<List<Map<String, dynamic>>> fetchNodeNovelContent({
    required String nodeId,
    required String filePath,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }

    final response = await _callNode(
      node: node,
      action: 'get_novel_content',
      params: <String, dynamic>{'file_path': filePath},
    );

    final data = response['data'];
    if (data is! Map) {
      return <Map<String, dynamic>>[];
    }

    final mapData = Map<String, dynamic>.from(data);
    final chapters = mapData['chapters'];
    if (chapters is! List) {
      return <Map<String, dynamic>>[];
    }
    return chapters.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<String> fetchNodeChapterContent({
    required String nodeId,
    required String filePath,
    required int chapterIndex,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }

    final response = await _callNode(
      node: node,
      action: 'get_chapter_content',
      params: <String, dynamic>{'file_path': filePath, 'chapter_index': chapterIndex},
    );

    final data = response['data'];
    return (data ?? '').toString();
  }

  Future<void> moveNodeNovelToFolder({
    required String nodeId,
    required String novelId,
    String? folderId,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }

    await _callNode(
      node: node,
      action: 'move_novel_to_folder',
      params: <String, dynamic>{'novel_id': novelId, 'folder_id': folderId},
    );
  }

  Future<void> updateNodeNovelCover({
    required String nodeId,
    required String novelId,
    required String imagePath,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }

    final bytes = await File(imagePath).readAsBytes();
    final ext = _extractImageExt(imagePath);
    final encoded = base64Encode(bytes);

    await _callNode(
      node: node,
      action: 'update_novel_cover_base64',
      params: <String, dynamic>{'novel_id': novelId, 'image_base64': encoded, 'image_ext': ext},
    );
  }

  // ── 通用节点调用（供 ViewModel 直接使用） ────────────────────────────────

  /// 向指定节点发起任意 action 调用，返回 response data。
  Future<Map<String, dynamic>> callNodeAction({
    required String nodeId,
    required String action,
    Map<String, dynamic> params = const {},
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }
    return _callNode(node: node, action: action, params: params);
  }

  Future<Map<String, dynamic>> _callNode({
    required NodeEndpoint node,
    required String action,
    required Map<String, dynamic> params,
  }) async {
    // 熔断检查：本次运行期间不再自动请求已熔断节点
    await _ensureNodeReachable(node);
    final sanitizedParams = _sanitizeJsonMap(params);
    final requestPayload = <String, dynamic>{'action': action, 'params': sanitizedParams};
    final callKey = _buildNodeCallKey(node.id, action, sanitizedParams);
    final inFlight = _inFlightNodeCalls[callKey];
    if (inFlight != null) {
      return inFlight;
    }

    final future = _performNodeCall(node: node, action: action, requestPayload: requestPayload);
    _inFlightNodeCalls[callKey] = future;
    future.whenComplete(() {
      if (identical(_inFlightNodeCalls[callKey], future)) {
        _inFlightNodeCalls.remove(callKey);
      }
    }).ignore();
    return future;
  }

  Future<Map<String, dynamic>> _performNodeCall({
    required NodeEndpoint node,
    required String action,
    required Map<String, dynamic> requestPayload,
    ProgressCallback? onReceiveProgress,
  }) async {
    final candidateUrls = _nodeCallCandidateUrls(node);
    final txBytes = _estimatePayloadBytes(requestPayload);
    // 【临时埋点】整次调用（含换地址重试、忙重试）的墙钟耗时
    final trace = TimingTrace('节点调用', scope: '${node.name} $action');
    Object? lastError;
    StackTrace? lastStackTrace;
    int busyRetries = 0;
    // 是否拿到过 HTTP 应答：业务失败、4xx/5xx 也说明节点在线，不应改在线位
    bool nodeAnswered = false;

    for (int index = 0; index < candidateUrls.length; index++) {
      final url = candidateUrls[index];
      final attemptTrace = TimingTrace('POST', scope: url);
      final isLast = index == candidateUrls.length - 1;
      try {
        final response = await _dio.post<Map<String, dynamic>>(
          url,
          data: requestPayload,
          options: _nodeCallOptionsForAction(action),
          onReceiveProgress: onReceiveProgress,
        );
        attemptTrace.end(note: 'HTTP ${response.statusCode}');
        nodeAnswered = true;
        // 有 HTTP 应答就说明这一路是通的（业务失败也一样），后续调用不必再试别的地址。
        _nodeAnsweredBase[node.id] = _baseUrlFromNodeCallUrl(url);
        final body = response.data ?? <String, dynamic>{};
        // 同一份响应体只估一次：这条链原来对 body 调了两次 _estimatePayloadBytes
        // （一次给流量统计、一次给埋点），每次都深拷贝 + jsonEncode（见方法注释）
        final rxBytes = _estimatePayloadBytes(body);
        _recordAppTraffic(txBytes: txBytes, rxBytes: rxBytes);
        if (body['success'] == true) {
          nodeConnectivity[node.id] = true;
          nodeConnectivityError[node.id] = '';
          await _persistResolvedNodeBaseUrl(node, _baseUrlFromNodeCallUrl(url));
          trace.end(note: 'bytes=$rxBytes');
          return body;
        }
        throw Exception((body['error'] ?? '节点返回失败').toString());
      } catch (e, st) {
        attemptTrace.end(note: '失败=${e.runtimeType}');
        // 4xx/5xx 在 Dio 里是异常，但已带回 HTTP 应答，节点本身是在线的
        if (e is DioException && e.response != null) nodeAnswered = true;
        // 节点回「并发已满」（503/429）说明连接是通的，只是服务端在背压：
        // 等一小会儿重来一次，否则一次偶发的并发峰值就变成用户可见的失败。
        if (e is DioException && _isNodeBusyError(e) && busyRetries < _nodeBusyRetries) {
          busyRetries++;
          _logger.info('节点繁忙(HTTP ${e.response?.statusCode})，第 $busyRetries 次重试: ${node.name} $action');
          await Future<void>.delayed(Duration(milliseconds: 150 * busyRetries));
          index--; // 重试同一地址
          continue;
        }
        lastError = e;
        lastStackTrace = st;
        if (isLast || !_shouldTryFallbackUrl(e)) {
          break;
        }
      }
    }

    final rawError = lastError ?? Exception('节点请求失败');
    // 5xx 业务失败在传输层只是 DioException：出口处换成节点原文，日志与提示才能说清原因
    final error = rawError is DioException
        ? (_nodeBusinessError(rawError) ?? rawError)
        : rawError;
    nodeConnectivityError[node.id] = _isUnauthorizedError(rawError) ? '授权码错误，请核对节点授权码' : error.toString();
    _logger.error(
      '节点请求失败: ${node.name} $action | URLs=${candidateUrls.join(' , ')}',
      error: error,
      stackTrace: lastStackTrace,
    );

    // 如果是网络超时/断开，做一次快速探测；探测也失败才熔断并标离线。
    // 单个 action 超时不等于节点不可用：一上来就把整节点标成离线，会让下一次离线复探
    // 把它当成待恢复节点多刷一轮全库（实测在启动预热那一轮就这么白刷了一次）。
    final isNetworkTimeout =
        rawError is DioException &&
        (rawError.type == DioExceptionType.connectionTimeout ||
            rawError.type == DioExceptionType.connectionError ||
            rawError.type == DioExceptionType.receiveTimeout ||
            rawError.type == DioExceptionType.sendTimeout);
    if (isNetworkTimeout && !_circuitBreakedNodes.contains(node.id)) {
      final probeTrace = TimingTrace('失败后快速探测', scope: node.name);
      final probeOk = await _quickProbeNode(node);
      probeTrace.end(note: 'probeOk=$probeOk');
      if (!probeOk) {
        nodeConnectivity[node.id] = false;
        _circuitBreakedNodes.add(node.id);
        nodeConnectivityError[node.id] = '节点已熔断（多次超时），请在设置中手动重试';
      }
    } else if (nodeAnswered) {
      // 业务失败、401、4xx/5xx 都已拿到 HTTP 应答，节点在线；
      // 只保留错误文案，否则切换器会按"不可达"把节点灰掉并拦下选择。
      nodeConnectivity[node.id] = true;
    } else if (!isNetworkTimeout) {
      // 只有确实没拿到任何 HTTP 应答的传输层失败才判离线
      nodeConnectivity[node.id] = false;
    }

    trace.end(note: '最终失败=${error.runtimeType}');
    throw error;
  }

  /// 快速探测节点是否可达（bypass 熔断检查，用于验证重试）。
  /// 返回 true 表示节点有响应（无论业务是否成功），并把应答的那一路记成后续首选地址。
  Future<bool> _quickProbeNode(NodeEndpoint node) async {
    final bases = <String>{
      if (node.lanApiBaseUrl != null && node.lanApiBaseUrl!.isNotEmpty) node.lanApiBaseUrl!,
      node.apiBaseUrl,
    };
    final probeUrls = <String, List<String>>{
      for (final base in bases) base: _candidateNodeCallUrls(base),
    };
    final total = probeUrls.values.map((l) => l.length).fold(0, (a, b) => a + b);
    if (total == 0) return false;
    const timeout = probeConfirmTimeout;
    for (final entry in probeUrls.entries) {
      for (final url in entry.value) {
        try {
          await _probeDio.post<dynamic>(
            url,
            data: <String, dynamic>{'action': 'ping', 'params': <String, dynamic>{}},
            options: Options(
              connectTimeout: timeout,
              receiveTimeout: timeout,
              sendTimeout: timeout,
            ),
          );
          _nodeAnsweredBase[node.id] = _baseUrlFromNodeCallUrl(url);
          return true;
        } on DioException catch (e) {
          // 只有连接层失败才算这个地址不可达，HTTP 层错误说明节点还活着
          if (e.type != DioExceptionType.connectionTimeout &&
              e.type != DioExceptionType.connectionError &&
              e.type != DioExceptionType.receiveTimeout &&
              e.type != DioExceptionType.sendTimeout) {
            _nodeAnsweredBase[node.id] = _baseUrlFromNodeCallUrl(url);
            return true;
          }
        } catch (_) {
          // 换下一个候选地址继续探
        }
      }
    }
    _logger.info('节点已熔断: ${node.name}（请求超时且 $total 个候选地址均无响应）');
    return false;
  }

  String _buildNodeCallKey(String nodeId, String action, Map<String, dynamic> params) {
    return '$nodeId|$action|${jsonEncode(params)}';
  }

  List<String> _candidateNodeCallUrls(String baseUrl) {
    final normalized = _normalizeBaseUrl(baseUrl);
    if (normalized.isEmpty) {
      return const <String>[];
    }

    final uri = Uri.tryParse(normalized);
    if (uri == null) {
      return <String>[_nodeCallUrl(normalized)];
    }

    final candidates = <String>{_nodeCallUrl(uri.toString())};
    if (!uri.hasPort) {
      candidates.add(_nodeCallUrl(uri.replace(port: _defaultRemoteNodePort).toString()));
    }
    return candidates.toList(growable: false);
  }

  bool _shouldTryFallbackUrl(Object error) {
    if (error is! DioException) {
      return false;
    }
    return error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout;
  }

  /// 节点在说「我忙」（并发打满时回 503，限流回 429）：连接是通的，节点也是活的。
  bool _isNodeBusyError(DioException error) {
    final status = error.response?.statusCode;
    return status == 503 || status == 429;
  }

  /// 从 HTTP 失败的响应体里还原节点写给用户的 error 文案；不是这种形状返回 null。
  ///
  /// 节点把业务失败写成 HTTP 5xx + `{"success":false,"error":"…"}`，而 Dio 默认的
  /// validateStatus 会先把这类响应抛成 DioException，文案就丢在响应体里没人看：
  /// 日志只剩一句「status code of 500」，调用方按节点文案做的判断（比如远程导入
  /// 时认「该文件夹已导入」做去重）也永远不会命中，用户只能看到「请检查磁盘」。
  ///
  /// 只处理 5xx：401 的授权码判定、503/429 的「节点忙」背压重试与熔断判定读的都是
  /// DioException 的状态码语义，那些路径保持原样。
  Exception? _nodeBusinessError(DioException e) {
    final response = e.response;
    final status = response?.statusCode;
    if (status == null || status < 500 || status == HttpStatus.serviceUnavailable) {
      return null;
    }
    final data = response!.data;
    if (data is! Map) return null;
    final message = data['error']?.toString().trim();
    if (message == null || message.isEmpty) return null;
    return NodeBusinessException(status, message);
  }

  String _baseUrlFromNodeCallUrl(String url) {
    return url.endsWith('/node/call') ? url.substring(0, url.length - '/node/call'.length) : url;
  }

  /// 把「应答成功的那一路地址」回写到节点配置。
  ///
  /// 只允许修正 **同一个 host** 上的端口/格式差异（例如用户只填了 `192.168.1.5`，
  /// 实际节点在 `192.168.1.5:17888`）。候选地址里 LAN 优先，如果连 host 不同也回写，
  /// 在家时 LAN 先应答就会把用户配置的外网地址永久覆盖成内网地址，
  /// 之后出门两路都是内网地址、节点彻底失联，只能手工重填。
  Future<void> _persistResolvedNodeBaseUrl(NodeEndpoint node, String resolvedBaseUrl) async {
    final normalizedResolved = _normalizeBaseUrl(resolvedBaseUrl);
    final normalizedConfigured = _normalizeBaseUrl(node.apiBaseUrl);
    if (normalizedResolved.isEmpty ||
        normalizedResolved == normalizedConfigured) {
      return;
    }
    // host 不同一律不回写：这只说明「这一路当前可达」，不代表配置写错了
    if (_hostOf(normalizedResolved) != _hostOf(normalizedConfigured)) {
      return;
    }

    final index = remoteNodes.indexWhere((item) => item.id == node.id);
    if (index == -1) {
      return;
    }

    remoteNodes[index] = remoteNodes[index].copyWith(apiBaseUrl: normalizedResolved);
    remoteNodes.refresh();
    await _save();
    _logger.info('节点地址已自动修正: ${node.name} -> $normalizedResolved');
  }

  /// 取 baseUrl 的 host（不含端口/scheme），解析失败返回空串。
  String _hostOf(String baseUrl) => Uri.tryParse(baseUrl)?.host ?? '';

  Map<String, dynamic> _sanitizeJsonMap(Map<String, dynamic> source) {
    final output = <String, dynamic>{};
    source.forEach((key, value) {
      output[key] = _sanitizeJsonValue(value);
    });
    return output;
  }

  dynamic _sanitizeJsonValue(dynamic value) {
    if (value == null) return null;
    if (value is BigInt) return value.toString();
    if (value is DateTime) return value.toIso8601String();
    if (value is Uint8List) return base64Encode(value);
    if (value is Map) {
      final map = <String, dynamic>{};
      value.forEach((key, innerValue) {
        map[key.toString()] = _sanitizeJsonValue(innerValue);
      });
      return map;
    }
    if (value is Iterable) {
      return value.map(_sanitizeJsonValue).toList(growable: false);
    }
    if (value is num || value is bool || value is String) return value;
    return value.toString();
  }

  /// 估算一份 JSON payload 的字节数（流量统计口径）。
  ///
  /// 口径已改廉价：**不再 sanitize 深拷贝、不再 jsonEncode、不再 utf8.encode**，
  /// 直接遍历原始结构按「字符串 UTF-16 码元数 × 平均字节系数」累加。
  /// 旧实现每调一次都要深拷贝整棵参数树（Map/List 全新建、BigInt/DateTime/
  /// Uint8List 逐个转换）再序列化两遍，节点调用一频繁就是主 isolate 上的
  /// 纯浪费——而这个数字本来就只是给仪表盘看的速度近似值。
  ///
  /// 误差说明：ASCII 平均 1.0 字节/码元、中文按 UTF-8 三字节估 2.4（含少量
  /// ASCII 混排折中）。整数按十进制位数、布尔按 4/5 字节、容器按每项 2 字节
  /// 开销（引号/冒号/逗号）计入。整份估算只与 payload 规模成正比，不做任何分配。
  int _estimatePayloadBytes(dynamic payload) {
    try {
      return _estimateValueBytes(payload);
    } catch (_) {
      return 0;
    }
  }

  /// 单测入口：直接量估算口径（生产方法是私有的）。
  @visibleForTesting
  int estimatePayloadBytesForTest(dynamic payload) => _estimatePayloadBytes(payload);

  int _estimateValueBytes(dynamic value) {
    if (value == null) return 4; // null
    if (value is String) return _estimateStringBytes(value) + 2; // + 两侧引号
    if (value is bool) return value ? 4 : 5;
    if (value is num) return value.toString().length;
    if (value is BigInt) return value.toString().length;
    if (value is DateTime) return 26; // ISO8601 定长（含微秒与 Z）
    if (value is Uint8List) {
      // 二进制会被 sanitize 成 base64 上送：3 字节 → 4 个 ASCII 字符。
      // 只认 Uint8List：普通 List<int> 是 JSON 数字数组，按数字位数算才对
      return (value.length + 2) ~/ 3 * 4 + 2;
    }
    if (value is Map) {
      var total = 2; // {} 或 []
      value.forEach((key, inner) {
        total += _estimateStringBytes(key.toString()) + 2 + 1; // key + 引号 + 冒号
        total += _estimateValueBytes(inner) + 1; // 值 + 逗号
      });
      return total;
    }
    if (value is Iterable) {
      var total = 2;
      for (final inner in value) {
        total += _estimateValueBytes(inner) + 1;
      }
      return total;
    }
    // Duration / 自定义对象等：上游请求体里不存在，按 toString 估
    return _estimateStringBytes(value.toString()) + 2;
  }

  /// 字符串字节估算：非 ASCII 码元按 UTF-8 三字节算（中文 CJK 正是 3 字节）。
  int _estimateStringBytes(String text) {
    var ascii = 0;
    var wide = 0;
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) < 0x80) {
        ascii++;
      } else {
        wide++;
      }
    }
    // 宽字符按 2.4 字节/码元折中：UTF-8 下 BMP 汉字是 3 字节，但混合标点/数字
    // 平均下来落在 2.4 附近；用整数运算避免浮点（×12/5）
    return ascii + wide * 12 ~/ 5;
  }

  void _recordAppTraffic({required int txBytes, required int rxBytes}) {
    final now = DateTime.now();
    _lastTrafficAt = now;
    final windowStart = _trafficWindowStartAt;
    if (windowStart == null) {
      _trafficWindowStartAt = now;
      _trafficWindowTxBytes = txBytes;
      _trafficWindowRxBytes = rxBytes;
      appTxKbps.value = txBytes / 1024.0;
      appRxKbps.value = rxBytes / 1024.0;
      return;
    }

    _trafficWindowTxBytes += txBytes;
    _trafficWindowRxBytes += rxBytes;

    final elapsedSeconds = now.difference(windowStart).inMilliseconds / 1000.0;
    if (elapsedSeconds < 0.5) {
      final safeElapsed = elapsedSeconds <= 0 ? 0.1 : elapsedSeconds;
      appTxKbps.value = (_trafficWindowTxBytes / 1024.0) / safeElapsed;
      appRxKbps.value = (_trafficWindowRxBytes / 1024.0) / safeElapsed;
      return;
    }

    appTxKbps.value = (_trafficWindowTxBytes / 1024.0) / elapsedSeconds;
    appRxKbps.value = (_trafficWindowRxBytes / 1024.0) / elapsedSeconds;

    _trafficWindowStartAt = now;
    _trafficWindowTxBytes = 0;
    _trafficWindowRxBytes = 0;
  }

  void syncTrafficDisplayNow() {
    final lastTrafficAt = _lastTrafficAt;
    if (lastTrafficAt == null) {
      appTxKbps.value = 0;
      appRxKbps.value = 0;
      return;
    }

    final idleSeconds = DateTime.now().difference(lastTrafficAt).inMilliseconds / 1000.0;
    if (idleSeconds >= 1.5) {
      appTxKbps.value = 0;
      appRxKbps.value = 0;
      _lastTrafficAt = null;
      _trafficWindowStartAt = DateTime.now();
      _trafficWindowTxBytes = 0;
      _trafficWindowRxBytes = 0;
    }
  }

  void _emitLibraryMutation() {
    libraryMutationTick.value++;
  }

  Future<void> _load() async {
    // 演示模式不读取真实节点，避免离线时发起探测
    if (MockMode.enabled) {
      remoteNodes.clear();
      nodeConnectivity.clear();
      localNodeEnabled.value = true;
      localNodeName.value = '演示本机节点';
      localNodePort.value = 17888;
      localNodeAuthCode.value = 'DEMO-2026';
      return;
    }
    final prefs = _prefs;
    if (prefs == null) {
      return;
    }

    localNodeEnabled.value = prefs.getBool(_keyLocalEnabled) ?? false;
    localNodeName.value = prefs.getString(_keyLocalName) ?? '本机节点';
    localNodePort.value = prefs.getInt(_keyLocalPort) ?? 17888;
    // 首次使用（或历史版本升级）时自动生成授权码，保证设置页总有一个可分享的码
    final storedCode = prefs.getString(_keyLocalAuthCode) ?? '';
    if (storedCode.isEmpty) {
      localNodeAuthCode.value = generateLocalAuthCode();
      await prefs.setString(_keyLocalAuthCode, localNodeAuthCode.value);
    } else {
      localNodeAuthCode.value = storedCode;
    }

    activeNodeId.value = prefs.getString(_keyActiveNodeId) ?? '';

    final raw = prefs.getString(_keyRemoteNodes);
    _loadWakeDevices(prefs);
    if (raw == null || raw.isEmpty) {
      remoteNodes.clear();
      _validateActiveNode();
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        remoteNodes.clear();
        return;
      }

      final nodes = decoded
          .whereType<Map>()
          .map((e) => NodeEndpoint.fromJson(Map<String, dynamic>.from(e)))
          .map((n) => n.copyWith(apiBaseUrl: _normalizeBaseUrl(n.apiBaseUrl)))
          .where((n) => n.id.isNotEmpty && n.apiBaseUrl.isNotEmpty)
          .toList();
      remoteNodes.assignAll(nodes);
      _validateActiveNode();
    } catch (e, st) {
      _logger.error('读取节点设置失败', error: e, stackTrace: st);
      remoteNodes.clear();
    }
  }

  Future<void> _save() async {
    final prefs = _prefs;
    if (prefs == null) {
      return;
    }

    await prefs.setBool(_keyLocalEnabled, localNodeEnabled.value);
    await prefs.setString(_keyLocalName, localNodeName.value);
    await prefs.setInt(_keyLocalPort, localNodePort.value);
    await prefs.setString(_keyLocalAuthCode, localNodeAuthCode.value);
    await prefs.setString(_keyActiveNodeId, activeNodeId.value);
    await prefs.setString(_keyRemoteNodes, jsonEncode(remoteNodes.map((n) => n.toJson()).toList()));
    await prefs.setString(
      _keyWakeDevices,
      jsonEncode(wakeDevices.map((d) => d.toJson()).toList()),
    );
  }

  void _loadWakeDevices(SharedPreferences prefs) {
    final raw = prefs.getString(_keyWakeDevices);
    if (raw == null || raw.isEmpty) {
      wakeDevices.clear();
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        wakeDevices.clear();
        return;
      }
      wakeDevices.assignAll(
        decoded
            .whereType<Map>()
            .map((e) => WakeDevice.fromJson(Map<String, dynamic>.from(e)))
            .where((d) => d.id.isNotEmpty && d.mac.isNotEmpty),
      );
    } catch (e, st) {
      _logger.error('读取唤醒设备失败', error: e, stackTrace: st);
      wakeDevices.clear();
    }
  }

  String _normalizeBaseUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    String withScheme = trimmed.startsWith('http://') || trimmed.startsWith('https://')
        ? trimmed
        : 'http://$trimmed';
    if (withScheme.endsWith('/node/call')) {
      withScheme = withScheme.substring(0, withScheme.length - '/node/call'.length);
    }
    if (withScheme.endsWith('/health')) {
      withScheme = withScheme.substring(0, withScheme.length - '/health'.length);
    }
    if (withScheme.endsWith('/node')) {
      withScheme = withScheme.substring(0, withScheme.length - '/node'.length);
    }
    return withScheme.endsWith('/') ? withScheme.substring(0, withScheme.length - 1) : withScheme;
  }

  String _nodeCallUrl(String baseUrl) {
    final normalized = _normalizeBaseUrl(baseUrl);
    return '$normalized/node/call';
  }

  String _createNodeId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final rand = now % 1000000;
    return 'node_${now}_$rand';
  }

  Future<void> _refreshLocalApiList() async {
    if (MockMode.enabled) {
      localNodeApiList.assignAll([
        'http://192.168.1.20:${localNodePort.value}/node/call',
      ]);
      return;
    }
    final values = <String>[];

    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final ip = address.address;
          if (ip.startsWith('127.') || ip.startsWith('169.254.')) {
            continue;
          }
          values.add('http://$ip:${localNodePort.value}/node/call');
        }
      }
    } catch (e) {
      _logger.log('读取本机网卡地址失败: $e', name: 'NodeSettings');
    }

    values.add('http://127.0.0.1:${localNodePort.value}/node/call');
    localNodeApiList.assignAll(values.toSet().toList()..sort());
  }

  Options? _nodeCallOptionsForAction(String action) {
    if (action == 'list_novels') {
      return Options(
        sendTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 45),
      );
    }
    if (action.startsWith('manga_')) {
      return Options(
        sendTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
      );
    }
    // 远程拖拽导入：节点要遍历整棵目录并逐条入库，大目录远超默认 12s，
    // 按默认超时会让客户端先放弃（节点其实还在导）。
    if (action == 'import_media_folder') {
      return Options(
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 10),
      );
    }
    // 重扫同一次导入同等量级：节点要重新遍历整棵目录、逐条 stat 入库，
    // 几万文件的集合远超默认 12s。超时档与导入对齐（同一个遍历代价）。
    if (action == 'rescan_media_folder') {
      return Options(
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 10),
      );
    }
    return null;
  }
}

/// 节点业务失败异常：HTTP 状态是 5xx/4xx，但响应体里带着节点写给用户的错误文案。
///
/// 之所以不复用 DioException：Dio 的默认 validateStatus 会在读到业务文案之前先抛出
/// 一大段「status code of 500 …」的样板文本，调用方想按文案判断（例如远程导入时认
/// 「该文件夹已导入」做去重）根本无从下手。这个类型只带节点原文与状态码。
class NodeBusinessException implements Exception {
  const NodeBusinessException(this.statusCode, this.message);

  /// 节点回应的 HTTP 状态码。
  final int statusCode;

  /// 节点响应体里的 error 字段原文。
  final String message;

  @override
  String toString() => '节点返回失败(HTTP $statusCode): $message';
}

/// 节点连通性探测结果：区分"不在线"和"在线但授权码不对"。
enum _ProbeResult { ok, unauthorized, unreachable }

/// 给所有发往已配置节点的请求补上 `X-SW-Auth: sha256(授权码)`。
class _NodeAuthInterceptor extends Interceptor {
  _NodeAuthInterceptor(this._digestForUrl);

  final String? Function(String url) _digestForUrl;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final digest = _digestForUrl(options.uri.toString());
    final alreadySet = options.headers.keys.any((k) => k.toLowerCase() == 'x-sw-auth');
    if (digest != null && !alreadySet) {
      options.headers[NodeSettingsService._authHeaderName] = digest;
    }
    handler.next(options);
  }
}

