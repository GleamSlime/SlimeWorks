import 'package:flutter_test/flutter_test.dart';

// 媒体类型识别辅助函数（镜像 Rust media_collection::types::MediaKind）
String? _mediaKind(String ext) {
  switch (ext.toLowerCase()) {
    case 'jpg':
    case 'jpeg':
    case 'jfif':
    case 'png':
    case 'gif':
    case 'webp':
    case 'bmp':
    case 'avif':
    case 'heic':
    case 'heif':
    case 'tif':
    case 'tiff':
      return 'image';
    case 'mp4':
    case 'mov':
    case 'm4v':
    case 'mkv':
    case 'avi':
    case 'webm':
    case 'wmv':
    case 'flv':
    case 'ts':
      return 'video';
    case 'mp3':
    case 'flac':
    case 'aac':
    case 'm4a':
    case 'ogg':
    case 'opus':
    case 'wav':
    case 'wma':
    case 'ape':
    case 'aiff':
    case 'alac':
      return 'audio';
    default:
      return null;
  }
}

/// 速度格式化（镜像 DashboardScreen._formatSpeed）
String _formatSpeed(double kbps) {
  if (kbps >= 1024) {
    return '${(kbps / 1024).toStringAsFixed(2)} MB/s';
  }
  return '${kbps.toStringAsFixed(0)} KB/s';
}

void main() {
  // ── 媒体类型识别 ───────────────────────────────────────────────────────────

  group('媒体类型识别', () {
    test('图片扩展名映射正确', () {
      for (final ext in ['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'avif']) {
        expect(_mediaKind(ext), 'image', reason: '扩展名 $ext 应识别为图片');
      }
    });

    test('视频扩展名映射正确', () {
      for (final ext in ['mp4', 'mov', 'mkv', 'avi', 'webm']) {
        expect(_mediaKind(ext), 'video', reason: '扩展名 $ext 应识别为视频');
      }
    });

    test('音频扩展名映射正确', () {
      for (final ext in ['mp3', 'flac', 'aac', 'm4a', 'ogg', 'wav']) {
        expect(_mediaKind(ext), 'audio', reason: '扩展名 $ext 应识别为音频');
      }
    });

    test('大写扩展名与小写等价', () {
      expect(_mediaKind('JPG'), 'image');
      expect(_mediaKind('MP4'), 'video');
      expect(_mediaKind('FLAC'), 'audio');
    });

    test('未知扩展名返回 null', () {
      expect(_mediaKind('txt'), isNull);
      expect(_mediaKind('pdf'), isNull);
      expect(_mediaKind('exe'), isNull);
      expect(_mediaKind(''), isNull);
    });
  });

  // ── 速度格式化 ────────────────────────────────────────────────────────────

  group('速度格式化', () {
    test('小于 1024 KB/s 显示 KB/s', () {
      expect(_formatSpeed(0), '0 KB/s');
      expect(_formatSpeed(512), '512 KB/s');
      expect(_formatSpeed(1023), '1023 KB/s');
    });

    test('大于等于 1024 KB/s 转换为 MB/s', () {
      expect(_formatSpeed(1024), '1.00 MB/s');
      expect(_formatSpeed(2048), '2.00 MB/s');
      expect(_formatSpeed(10240), '10.00 MB/s');
    });
  });

  // ── Sparkline 历史缓冲区边界 ──────────────────────────────────────────────

  group('历史缓冲区', () {
    const kHistoryLength = 60;

    List<double> appendHistory(List<double> buf, double value) {
      buf.add(value);
      if (buf.length > kHistoryLength) buf.removeAt(0);
      return buf;
    }

    test('不足 60 条时正常追加', () {
      final buf = <double>[];
      for (int i = 0; i < 30; i++) {
        appendHistory(buf, i.toDouble());
      }
      expect(buf.length, 30);
      expect(buf.last, 29.0);
    });

    test('超过 60 条时移除最旧数据', () {
      final buf = <double>[];
      for (int i = 0; i < 80; i++) {
        appendHistory(buf, i.toDouble());
      }
      expect(buf.length, kHistoryLength);
      expect(buf.first, 20.0);
      expect(buf.last, 79.0);
    });

    test('全零时长度依然受限', () {
      final buf = <double>[];
      for (int i = 0; i < 100; i++) {
        appendHistory(buf, 0);
      }
      expect(buf.length, kHistoryLength);
      expect(buf.every((v) => v == 0.0), isTrue);
    });
  });
}
