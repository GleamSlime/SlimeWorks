import 'dart:async';
import 'dart:io';

/// Whisper 模型的磁盘路径口径 + 下载进度探测器。
///
/// 为什么单独成文件：模型下载改成了「先写 `.ggml-{preset}.bin.part`，成功后
/// rename 成最终名」（Rust `whisper_module::model::part_path_of`）。下载期间
/// 最终文件名**完全不存在**，只盯最终名的进度条会恒为 0、结束时才跳 100。
/// 这套路径/进度逻辑要有单测，页面里那个私有 class 测不到，故抽出来。
class WhisperModelPaths {
  WhisperModelPaths._();

  /// 应用数据根目录，**逐条对齐 Rust `db_module::paths::resolve_app_data_base`**。
  ///
  /// 历史坑：旧实现写成 `APPDATA ?? '$HOME/Library/Application Support'`，
  /// Windows 上 APPDATA 缺失时会拿 macOS 目录、Linux 上完全不认 XDG。
  /// 口径必须和 Rust 侧一致，否则进度条读的目录根本不是模型落地的目录。
  static String dataBase({
    Map<String, String>? environment,
    String? operatingSystem,
  }) {
    final env = environment ?? Platform.environment;
    final os = (operatingSystem ?? Platform.operatingSystem).toLowerCase();
    if (os == 'windows') {
      final appdata = env['APPDATA'] ?? '';
      // 与 Rust 一致：缺失时回落 "."（宁可当前目录，也不要空串）
      return appdata.isEmpty ? '.' : appdata;
    }
    if (os == 'macos') {
      final home = env['HOME'] ?? '';
      return home.isEmpty ? '.' : '$home/Library/Application Support';
    }
    final xdg = env['XDG_DATA_HOME'] ?? '';
    if (xdg.isNotEmpty) return xdg;
    final home = env['HOME'] ?? '';
    return home.isEmpty ? '.' : '$home/.local/share';
  }

  /// 路径分隔符：跟随**目标平台**而不是宿主平台，否则单测里模拟 Windows
  /// 会拼出 "/" 分隔的路径，断言就成了「测宿主」而不是「测逻辑」。
  static String separator({String? operatingSystem}) {
    final os = (operatingSystem ?? Platform.operatingSystem).toLowerCase();
    // 用码点写反斜杠，避免 r'\' 这种「裸字符串末尾反斜杠」在阅读时歧义
    return os == 'windows' ? String.fromCharCode(0x5C) : '/';
  }

  /// 模型目录（Rust 侧 `app_data_dir("SlimeWorks").join("whisper_models")`）。
  static String modelDir({
    Map<String, String>? environment,
    String? operatingSystem,
  }) {
    final sep = separator(operatingSystem: operatingSystem);
    final base = dataBase(environment: environment, operatingSystem: operatingSystem);
    return '$base${sep}SlimeWorks${sep}whisper_models';
  }

  /// 最终文件名（下载完成后 rename 到这里）。
  static String fileName(String presetName) => 'ggml-$presetName.bin';

  /// 下载中的临时文件名：**与最终名同目录**，且带前导点（隐藏文件）。
  /// 必须与 Rust `part_path_of` 逐字一致，否则进度条还是读错文件。
  static String partFileName(String presetName) => '.${fileName(presetName)}.part';

  static String filePath(
    String presetName, {
    Map<String, String>? environment,
    String? operatingSystem,
  }) {
    final sep = separator(operatingSystem: operatingSystem);
    return '${modelDir(environment: environment, operatingSystem: operatingSystem)}$sep${fileName(presetName)}';
  }

  static String partPath(
    String presetName, {
    Map<String, String>? environment,
    String? operatingSystem,
  }) {
    final sep = separator(operatingSystem: operatingSystem);
    return '${modelDir(environment: environment, operatingSystem: operatingSystem)}$sep${partFileName(presetName)}';
  }
}

/// 通过轮询文件大小估算下载进度（下载期间读 `.part`，完成后读最终名）。
///
/// 状态语义：
/// - 两个文件都不存在 → [pollOnce] 返回 null，**保持上一次进度不回退**。
///   下载失败/取消时 Rust 会删掉 `.part`，此时进度条不该先跳回 0 再等页面
///   自己收尾（页面在 finally 里会清掉整个下载态）。
/// - `.part` 存在 → 按比例推进，封顶 0.99（还没 rename，不能说完成）。
/// - 只剩最终名 → 1.0（rename 是原子的，文件出现即完成）。
class WhisperModelDownloadTracker {
  WhisperModelDownloadTracker({
    required this.presetName,
    required this.totalBytes,
    required this.onProgress,
    Map<String, String>? environment,
    String? operatingSystem,
    int? Function(String path)? fileSizeReader,
    this.pollInterval = const Duration(milliseconds: 500),
  })  : _environment = environment,
        _operatingSystem = operatingSystem,
        _fileSizeReader = fileSizeReader;

  final String presetName;
  final int totalBytes;
  final void Function(double progress) onProgress;
  final Duration pollInterval;

  final Map<String, String>? _environment;
  final String? _operatingSystem;
  final int? Function(String path)? _fileSizeReader;

  Timer? _timer;
  double _lastProgress = 0;

  /// 上一次上报的进度（未上报过为 0）。
  double get lastProgress => _lastProgress;

  String get partPath => WhisperModelPaths.partPath(
        presetName,
        environment: _environment,
        operatingSystem: _operatingSystem,
      );

  String get finalPath => WhisperModelPaths.filePath(
        presetName,
        environment: _environment,
        operatingSystem: _operatingSystem,
      );

  void start() {
    _timer ??= Timer.periodic(pollInterval, (_) => pollOnce());
    pollOnce();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// 采样一次；返回本次算出的进度（文件都还没出现时返回 null）。
  double? pollOnce() {
    final progress = _computeProgress();
    if (progress == null) return null;
    if (progress != _lastProgress) {
      _lastProgress = progress;
      onProgress(progress);
    }
    return progress;
  }

  double? _computeProgress() {
    // 先读 .part：下载期间只有它存在，读到它才说明真的在下载
    final partSize = _sizeOf(partPath);
    if (partSize != null) {
      if (totalBytes <= 0) return 0;
      return (partSize / totalBytes).clamp(0.0, 0.99).toDouble();
    }
    final finalSize = _sizeOf(finalPath);
    if (finalSize != null) return 1.0;
    // 两个都没有：可能是下载刚开始（还没落盘），也可能失败了 .part 已被删
    return null;
  }

  int? _sizeOf(String path) {
    try {
      final reader = _fileSizeReader;
      if (reader != null) return reader(path);
      final file = File(path);
      if (!file.existsSync()) return null;
      return file.lengthSync();
    } catch (_) {
      return null;
    }
  }
}
