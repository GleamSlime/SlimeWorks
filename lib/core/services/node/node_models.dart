class NodeEndpoint {
  final String id;
  final String name;
  final String apiBaseUrl;
  final String? lanApiBaseUrl;
  final bool enabled;
  final bool supportsMove;
  final bool supportsCoverUpdate;

  const NodeEndpoint({
    required this.id,
    required this.name,
    required this.apiBaseUrl,
    this.lanApiBaseUrl,
    this.enabled = true,
    this.supportsMove = true,
    this.supportsCoverUpdate = true,
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
    );
  }
}
