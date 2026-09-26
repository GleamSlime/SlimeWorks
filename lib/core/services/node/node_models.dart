class NodeEndpoint {
  final String id;
  final String name;
  final String apiBaseUrl;
  final String? lanApiBaseUrl;
  final bool enabled;
  final bool supportsMove;
  final bool supportsCoverUpdate;

  /// 连接该节点使用的授权码明文；请求时以 sha256 摘要放入 `X-SW-Auth` 请求头。
  final String authCode;

  const NodeEndpoint({
    required this.id,
    required this.name,
    required this.apiBaseUrl,
    this.lanApiBaseUrl,
    this.enabled = true,
    this.supportsMove = true,
    this.supportsCoverUpdate = true,
    this.authCode = '',
  });

  String get effectiveApiBaseUrl => lanApiBaseUrl?.isNotEmpty == true ? lanApiBaseUrl! : apiBaseUrl;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'apiBaseUrl': apiBaseUrl,
      if (lanApiBaseUrl != null && lanApiBaseUrl!.isNotEmpty) 'lanApiBaseUrl': lanApiBaseUrl,
      'enabled': enabled,
      'supportsMove': supportsMove,
      'supportsCoverUpdate': supportsCoverUpdate,
      if (authCode.isNotEmpty) 'authCode': authCode,
    };
  }

  factory NodeEndpoint.fromJson(Map<String, dynamic> json) {
    final lan = (json['lanApiBaseUrl'] ?? '').toString();
    return NodeEndpoint(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      apiBaseUrl: (json['apiBaseUrl'] ?? '').toString(),
      lanApiBaseUrl: lan.isEmpty ? null : lan,
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      supportsMove: json['supportsMove'] is bool ? json['supportsMove'] as bool : true,
      supportsCoverUpdate:
          json['supportsCoverUpdate'] is bool ? json['supportsCoverUpdate'] as bool : true,
      authCode: (json['authCode'] ?? '').toString().trim(),
    );
  }

  NodeEndpoint copyWith({
    String? id,
    String? name,
    String? apiBaseUrl,
    String? lanApiBaseUrl,
    bool? enabled,
    bool? supportsMove,
    bool? supportsCoverUpdate,
    String? authCode,
    bool clearLanApiBaseUrl = false,
  }) {
    return NodeEndpoint(
      id: id ?? this.id,
      name: name ?? this.name,
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      lanApiBaseUrl: clearLanApiBaseUrl ? null : (lanApiBaseUrl ?? this.lanApiBaseUrl),
      enabled: enabled ?? this.enabled,
      supportsMove: supportsMove ?? this.supportsMove,
      supportsCoverUpdate: supportsCoverUpdate ?? this.supportsCoverUpdate,
      authCode: authCode ?? this.authCode,
    );
  }
}

/// 单个远程节点的媒体元数据快照（文件夹 / 集合 / 智能文件夹的原始 payload）。
///
/// 首屏取数由 [NodeSettingsService.fetchNodeMediaMetadata] 一次并发拉齐三路，
/// 命中启动预热时可直接复用，省掉「进页面才开始问节点」的那段空等。
class NodeMediaMetadata {
  const NodeMediaMetadata({
    required this.folders,
    required this.collections,
    required this.smartFolders,
    required this.takenAt,
    this.complete = true,
  });

  final List<Map<String, dynamic>> folders;
  final List<Map<String, dynamic>> collections;
  final List<Map<String, dynamic>> smartFolders;
  final DateTime takenAt;

  /// 三路是否全部取到。为 false 时列表为空可能只是「那一路失败了」，
  /// 不能当成「该节点没有这类数据」渲染给用户。
  final bool complete;
}
