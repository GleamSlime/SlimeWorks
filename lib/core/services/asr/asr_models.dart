/// 内网语音识别服务配置（OpenAI 兼容 /v1/audio/transcriptions 协议）
class AsrServer {
  /// 展示名，如 "公司 4090 转写节点"
  final String name;

  /// 服务基地址，不含 /v1 后缀，如 http://192.168.1.20:8000
  final String url;

  /// 部分网关需要 Bearer Token，内网自建一般留空
  final String? apiKey;

  /// 转写模型名（服务端 --served-model-name / whisper 服务通常为 whisper）
  final String model;

  /// 是否启用该服务（关闭后不参与路由）
  final bool enabled;

  /// 最近一次连通性探测结果
  final bool isAvailable;

  final DateTime? lastChecked;

  const AsrServer({
    required this.name,
    required this.url,
    this.apiKey,
    this.model = 'whisper-1',
    this.enabled = true,
    this.isAvailable = false,
    this.lastChecked,
  });

  /// 转写接口完整地址
  String get transcribeUrl => '$normalizedUrl/v1/audio/transcriptions';

  /// 模型列表接口（用于连通性探测）
  String get modelsUrl => '$normalizedUrl/v1/models';

  /// 去掉尾部斜杠，避免拼出 //v1
  String get normalizedUrl => url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  AsrServer copyWith({
    String? name,
    String? url,
    String? apiKey,
    String? model,
    bool? enabled,
    bool? isAvailable,
    DateTime? lastChecked,
  }) {
    return AsrServer(
      name: name ?? this.name,
      url: url ?? this.url,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      enabled: enabled ?? this.enabled,
      isAvailable: isAvailable ?? this.isAvailable,
      lastChecked: lastChecked ?? this.lastChecked,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'url': url,
    'apiKey': apiKey,
    'model': model,
    'enabled': enabled,
    'isAvailable': isAvailable,
    'lastChecked': lastChecked?.toIso8601String(),
  };

  factory AsrServer.fromJson(Map<String, dynamic> json) => AsrServer(
    name: json['name'] as String? ?? '内网服务',
    url: json['url'] as String? ?? '',
    apiKey: json['apiKey'] as String?,
    model: json['model'] as String? ?? 'whisper-1',
    enabled: json['enabled'] as bool? ?? true,
    isAvailable: json['isAvailable'] as bool? ?? false,
    lastChecked: json['lastChecked'] != null
        ? DateTime.tryParse(json['lastChecked'] as String)
        : null,
  );
}

/// 转写片段（时间单位为毫秒），远程与本地统一用它表达
class AsrSegmentData {
  final int startMs;
  final int endMs;
  final String text;

  const AsrSegmentData({
    required this.startMs,
    required this.endMs,
    required this.text,
  });
}

/// 远程转写结果
class RemoteTranscription {
  final List<AsrSegmentData> segments;
  final String? language;

  /// 服务端返回的整段文本（无时间轴时用于兜底）
  final String text;

  const RemoteTranscription({
    required this.segments,
    this.language,
    this.text = '',
  });
}

/// 字幕任务的执行引擎
enum AsrEngine {
  /// 内网大模型（OpenAI 兼容接口）
  remote,

  /// 本机 SenseVoice sidecar
  local,
}

/// 识别语言选项
///
/// code 同时是 sidecar 的 --sense-voice-language 取值和 OpenAI 接口的 language 参数。
/// auto 对日韩语音频经常会误判（韩语被判成中文或日文），所以菜单里允许显式指定。
class AsrLanguageOption {
  final String code;
  final String label;

  const AsrLanguageOption(this.code, this.label);
}

const List<AsrLanguageOption> kAsrLanguages = [
  AsrLanguageOption('auto', '自动检测'),
  AsrLanguageOption('ko', '韩语'),
  AsrLanguageOption('ja', '日语'),
  AsrLanguageOption('zh', '中文'),
  AsrLanguageOption('yue', '粤语'),
  AsrLanguageOption('en', '英语'),
];

String asrLanguageLabel(String code) =>
    kAsrLanguages.firstWhere((o) => o.code == code, orElse: () => kAsrLanguages.first).label;

/// 字幕翻译服务配置（LibreTranslate 兼容的纯 NMT 接口）
///
/// 之所以要求 NMT 而不是聊天大模型：审核流程要靠关键词命中涉黄内容，
/// 对话模型会把露骨表述"美化"成委婉说法，关键词就全丢了；
/// NMT 只做直译，原文多露骨译文就多露骨。
class TranslateServer {
  /// 展示名，如 "内网 5090D LibreTranslate"
  final String name;

  /// 服务基地址，不含 /translate 后缀，如 http://192.168.1.20:5000
  final String url;

  /// LibreTranslate 用请求体里的 api_key，网关则用 Bearer，两个都会带上
  final String? apiKey;

  /// 是否启用该服务（关闭后不参与路由）
  final bool enabled;

  /// 最近一次连通性探测结果
  final bool isAvailable;

  final DateTime? lastChecked;

  const TranslateServer({
    required this.name,
    required this.url,
    this.apiKey,
    this.enabled = true,
    this.isAvailable = false,
    this.lastChecked,
  });

  /// 翻译接口完整地址
  String get translateUrl => '$normalizedUrl/translate';

  /// 去掉尾部斜杠，避免拼出 //translate
  String get normalizedUrl => url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  TranslateServer copyWith({
    String? name,
    String? url,
    String? apiKey,
    bool? enabled,
    bool? isAvailable,
    DateTime? lastChecked,
  }) {
    return TranslateServer(
      name: name ?? this.name,
      url: url ?? this.url,
      apiKey: apiKey ?? this.apiKey,
      enabled: enabled ?? this.enabled,
      isAvailable: isAvailable ?? this.isAvailable,
      lastChecked: lastChecked ?? this.lastChecked,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'url': url,
    'apiKey': apiKey,
    'enabled': enabled,
    'isAvailable': isAvailable,
    'lastChecked': lastChecked?.toIso8601String(),
  };

  factory TranslateServer.fromJson(Map<String, dynamic> json) => TranslateServer(
    name: json['name'] as String? ?? '内网翻译',
    url: json['url'] as String? ?? '',
    apiKey: json['apiKey'] as String?,
    enabled: json['enabled'] as bool? ?? true,
    isAvailable: json['isAvailable'] as bool? ?? false,
    lastChecked: json['lastChecked'] != null
        ? DateTime.tryParse(json['lastChecked'] as String)
        : null,
  );
}

/// 翻译结果
class TranslateResult {
  /// 与输入一一对应的译文（失败的条目保留原文，保证时间轴不丢行）
  final List<String> texts;

  /// 未能翻译的条目数，>0 时 UI 需要提示客服抽检
  final int untranslatedCount;

  const TranslateResult({required this.texts, this.untranslatedCount = 0});
}
