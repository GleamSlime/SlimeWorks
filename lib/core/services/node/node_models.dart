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
    this.foldersOk = true,
    this.collectionsOk = true,
    this.smartFoldersOk = true,
  });

  final List<Map<String, dynamic>> folders;
  final List<Map<String, dynamic>> collections;
  final List<Map<String, dynamic>> smartFolders;
  final DateTime takenAt;

  /// 三路各自的成败。失败的那一路拿到的是**空列表**，而空列表既可能是
  /// 「节点确实没有数据」，也可能是「这一路超时/报错」——调用方必须靠这三个
  /// 标记区分：把一次超时当成「该节点的集合全没了」，界面就会被整片清空
  /// （「删除节点本地文件后列表全空、要重启才恢复」就是这条链）。
  final bool foldersOk;
  final bool collectionsOk;
  final bool smartFoldersOk;

  /// 三路是否全部取到。为 false 时列表为空可能只是「那一路失败了」，
  /// 不能当成「该节点没有这类数据」渲染给用户。
  bool get complete => foldersOk && collectionsOk && smartFoldersOk;
}

/// 唤醒方式：经局域网内节点中继、本机直接广播，或按网络环境自动选择
enum WakeMode { relay, direct, auto }

/// 唤醒任务状态
enum WakeStatus { idle, waking, sent, online, timeout, failed }

/// 唤醒包下发结果：成功送出的地址与逐条失败原因
class WakeReport {
  const WakeReport({required this.targets, this.errors = const []});

  final List<String> targets;
  final List<String> errors;

  bool get delivered => targets.isNotEmpty;

  /// 直发时地址可能有多个（本机子网广播 / 受限广播），全失败才算失败
  String get summary {
    if (delivered) {
      return '已发往 ${targets.join('、')}';
    }
    return errors.isEmpty ? '未发出任何唤醒包' : errors.first;
  }
}

/// 可远程唤醒的设备（目标主机不必运行本应用）
class WakeDevice {
  const WakeDevice({
    required this.id,
    required this.name,
    required this.mac,
    this.target = '',
    this.port = 9,
    this.mode = WakeMode.auto,
    this.relayNodeId = '',
    this.probeNodeId = '',
    this.count = 3,
  });

  final String id;
  final String name;

  /// MAC 地址，支持冒号、横线、点分隔与纯十六进制
  final String mac;

  /// 广播地址或公网地址；留空表示 255.255.255.255
  final String target;

  final int port;
  final WakeMode mode;

  /// 中继节点 ID，[WakeMode.relay] 时必填
  final String relayNodeId;

  /// 唤醒后用于检测上线的节点 ID，可为空
  final String probeNodeId;

  /// 连续发送次数
  final int count;

  WakeDevice copyWith({
    String? id,
    String? name,
    String? mac,
    String? target,
    int? port,
    WakeMode? mode,
    String? relayNodeId,
    String? probeNodeId,
    int? count,
  }) {
    return WakeDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      mac: mac ?? this.mac,
      target: target ?? this.target,
      port: port ?? this.port,
      mode: mode ?? this.mode,
      relayNodeId: relayNodeId ?? this.relayNodeId,
      probeNodeId: probeNodeId ?? this.probeNodeId,
      count: count ?? this.count,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'mac': mac,
      'target': target,
      'port': port,
      'mode': mode.name,
      'relayNodeId': relayNodeId,
      'probeNodeId': probeNodeId,
      'count': count,
    };
  }

  factory WakeDevice.fromJson(Map<String, dynamic> json) {
    return WakeDevice(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      mac: (json['mac'] ?? '').toString(),
      target: (json['target'] ?? '').toString(),
      port: (json['port'] as num?)?.toInt() ?? 9,
      // 缺省视为自动：老配置里显式存了 relay/direct 的按原样保留
      mode: WakeMode.values.firstWhere(
        (m) => m.name == (json['mode'] ?? '').toString(),
        orElse: () => WakeMode.auto,
      ),
      relayNodeId: (json['relayNodeId'] ?? '').toString(),
      probeNodeId: (json['probeNodeId'] ?? '').toString(),
      count: (json['count'] as num?)?.toInt() ?? 3,
    );
  }
}

