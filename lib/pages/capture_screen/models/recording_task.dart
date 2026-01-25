/// 录制状态枚举
enum RecordingStatus { idle, recording, completed, error }

/// 录制任务模型
class RecordingTask {
  final String id;
  String name;
  final String url;
  final String thumbnail;
  final String resolution;
  final String frameRate;
  final String bitrate;
  final RecordingStatus status;
  final DateTime? startTime;
  final DateTime? endTime;
  final int? fileSize;
  final String? errorMessage;
  final double progress;
  bool isSelected;

  RecordingTask({
    required this.id,
    required this.name,
    required this.url,
    this.thumbnail = '',
    this.resolution = '1920x1080',
    this.frameRate = '30fps',
    this.bitrate = '2000kbps',
    this.status = RecordingStatus.idle,
    this.startTime,
    this.endTime,
    this.fileSize,
    this.errorMessage,
    this.progress = 0.0,
    this.isSelected = false,
  });

  String get displayStatus {
    switch (status) {
      case RecordingStatus.idle:
        return '待录制';
      case RecordingStatus.recording:
        return '录制中';
      case RecordingStatus.completed:
        return '已完成';
      case RecordingStatus.error:
        return '录制异常';
    }
  }

  String get duration {
    if (startTime != null && endTime != null) {
      final diff = endTime!.difference(startTime!);
      return '${diff.inMinutes}:${(diff.inSeconds % 60).toString().padLeft(2, '0')}';
    }
    return '--:--';
  }

  String get fileSizeStr {
    if (fileSize == null) return '--';
    final mb = fileSize! / (1024 * 1024);
    return '${mb.toStringAsFixed(2)} MB';
  }

  RecordingTask copyWith({
    String? id,
    String? name,
    String? url,
    String? thumbnail,
    String? resolution,
    String? frameRate,
    String? bitrate,
    RecordingStatus? status,
    DateTime? startTime,
    DateTime? endTime,
    int? fileSize,
    String? errorMessage,
    double? progress,
    bool? isSelected,
  }) {
    return RecordingTask(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      thumbnail: thumbnail ?? this.thumbnail,
      resolution: resolution ?? this.resolution,
      frameRate: frameRate ?? this.frameRate,
      bitrate: bitrate ?? this.bitrate,
      status: status ?? this.status,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      fileSize: fileSize ?? this.fileSize,
      errorMessage: errorMessage ?? this.errorMessage,
      progress: progress ?? this.progress,
      isSelected: isSelected ?? this.isSelected,
    );
  }
}
