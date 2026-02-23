/// Ollama 服务配置
class OllamaServer {
  final String url;
  final String? apiKey;
  bool isAvailable;
  DateTime? lastChecked;

  OllamaServer({required this.url, this.apiKey, this.isAvailable = false, this.lastChecked});

  Map<String, dynamic> toJson() => {
    'url': url,
    'apiKey': apiKey,
    'isAvailable': isAvailable,
    'lastChecked': lastChecked?.toIso8601String(),
  };

  factory OllamaServer.fromJson(Map<String, dynamic> json) => OllamaServer(
    url: json['url'] as String,
    apiKey: json['apiKey'] as String?,
    isAvailable: json['isAvailable'] as bool? ?? false,
    lastChecked: json['lastChecked'] != null ? DateTime.parse(json['lastChecked'] as String) : null,
  );

  OllamaServer copyWith({String? url, String? apiKey, bool? isAvailable, DateTime? lastChecked}) {
    return OllamaServer(
      url: url ?? this.url,
      apiKey: apiKey ?? this.apiKey,
      isAvailable: isAvailable ?? this.isAvailable,
      lastChecked: lastChecked ?? this.lastChecked,
    );
  }
}

/// Ollama 模型信息
class OllamaModel {
  final String name;
  final String? description;
  final int? size;
  final DateTime? modifiedAt;

  OllamaModel({required this.name, this.description, this.size, this.modifiedAt});

  factory OllamaModel.fromJson(Map<String, dynamic> json) => OllamaModel(
    name: json['name'] as String,
    description: json['description'] as String?,
    size: json['size'] as int?,
    modifiedAt: json['modified_at'] != null ? DateTime.parse(json['modified_at'] as String) : null,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'size': size,
    'modified_at': modifiedAt?.toIso8601String(),
  };
}

/// 翻译语言对
class TranslationLanguagePair {
  final String from;
  final String to;
  final String displayName;

  const TranslationLanguagePair({required this.from, required this.to, required this.displayName});

  static const List<TranslationLanguagePair> presets = [
    TranslationLanguagePair(from: '日文', to: '中文', displayName: '日文 → 中文'),
    TranslationLanguagePair(from: '英文', to: '中文', displayName: '英文 → 中文'),
    TranslationLanguagePair(from: '韩文', to: '中文', displayName: '韩文 → 中文'),
    TranslationLanguagePair(from: '中文', to: '英文', displayName: '中文 → 英文'),
    TranslationLanguagePair(from: '中文', to: '日文', displayName: '中文 → 日文'),
  ];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TranslationLanguagePair &&
          runtimeType == other.runtimeType &&
          from == other.from &&
          to == other.to;

  @override
  int get hashCode => from.hashCode ^ to.hashCode;
}

/// Ollama 请求响应
class OllamaResponse {
  final String content;
  final bool done;
  final String? model;

  OllamaResponse({required this.content, required this.done, this.model});

  factory OllamaResponse.fromJson(Map<String, dynamic> json) {
    final message = json['message'] as Map<String, dynamic>?;
    return OllamaResponse(
      content: message?['content'] as String? ?? '',
      done: json['done'] as bool? ?? false,
      model: json['model'] as String?,
    );
  }
}
