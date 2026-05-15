import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/pages/backup/capture_screen/models/recording_task.dart';

void main() {
  group('RecordingTask', () {
    test('构造函数默认值', () {
      final task = RecordingTask(id: 'r-001', name: 'Test', url: 'rtmp://x');
      expect(task.thumbnail, '');
      expect(task.resolution, '1920x1080');
      expect(task.frameRate, '30fps');
      expect(task.bitrate, '2000kbps');
      expect(task.status, RecordingStatus.idle);
      expect(task.progress, 0.0);
      expect(task.isSelected, isFalse);
      expect(task.startTime, isNull);
      expect(task.endTime, isNull);
      expect(task.fileSize, isNull);
      expect(task.errorMessage, isNull);
    });

    test('displayStatus 各状态', () {
      expect(
        RecordingTask(id: '', name: '', url: '', status: RecordingStatus.idle).displayStatus,
        '待录制',
      );
      expect(
        RecordingTask(id: '', name: '', url: '', status: RecordingStatus.recording).displayStatus,
        '录制中',
      );
      expect(
        RecordingTask(id: '', name: '', url: '', status: RecordingStatus.completed).displayStatus,
        '已完成',
      );
      expect(
        RecordingTask(id: '', name: '', url: '', status: RecordingStatus.error).displayStatus,
        '录制异常',
      );
    });

    test('duration 有起止时间时格式化', () {
      final task = RecordingTask(
        id: '',
        name: '',
        url: '',
        startTime: DateTime(2024, 1, 1, 10, 0, 0),
        endTime: DateTime(2024, 1, 1, 10, 5, 30),
      );
      expect(task.duration, '5:30');
    });

    test('duration 整分钟时秒数补零', () {
      final task = RecordingTask(
        id: '',
        name: '',
        url: '',
        startTime: DateTime(2024, 1, 1, 10, 0, 0),
        endTime: DateTime(2024, 1, 1, 10, 3, 5),
      );
      expect(task.duration, '3:05');
    });

    test('duration 无起止时间时返回占位符', () {
      final task = RecordingTask(id: '', name: '', url: '');
      expect(task.duration, '--:--');
    });

    test('duration 仅有开始时间时返回占位符', () {
      final task = RecordingTask(
        id: '',
        name: '',
        url: '',
        startTime: DateTime(2024, 1, 1),
      );
      expect(task.duration, '--:--');
    });

    test('fileSizeStr 有值时格式化 MB', () {
      final task = RecordingTask(id: '', name: '', url: '', fileSize: 1572864);
      expect(task.fileSizeStr, '1.50 MB');
    });

    test('fileSizeStr 为 null 时返回占位符', () {
      final task = RecordingTask(id: '', name: '', url: '');
      expect(task.fileSizeStr, '--');
    });

    test('copyWith 不传参时字段不变', () {
      final task = RecordingTask(
        id: 'r-001',
        name: 'Original',
        url: 'rtmp://x',
        status: RecordingStatus.recording,
        progress: 0.5,
      );
      final copy = task.copyWith();
      expect(copy.id, 'r-001');
      expect(copy.name, 'Original');
      expect(copy.status, RecordingStatus.recording);
      expect(copy.progress, 0.5);
    });

    test('copyWith 仅覆盖指定字段', () {
      final task = RecordingTask(id: 'r-001', name: 'Old', url: 'rtmp://x');
      final copy = task.copyWith(name: 'New', status: RecordingStatus.completed);
      expect(copy.id, 'r-001');
      expect(copy.name, 'New');
      expect(copy.status, RecordingStatus.completed);
    });

    test('RecordingStatus 枚举完整性', () {
      expect(RecordingStatus.values.length, 4);
      expect(RecordingStatus.values, contains(RecordingStatus.idle));
      expect(RecordingStatus.values, contains(RecordingStatus.recording));
      expect(RecordingStatus.values, contains(RecordingStatus.completed));
      expect(RecordingStatus.values, contains(RecordingStatus.error));
    });
  });
}
