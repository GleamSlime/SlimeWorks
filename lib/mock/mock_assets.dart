import 'dart:io';
import 'dart:typed_data';

/// 本地生成的占位图片，不依赖网络与真实媒体文件。
class MockAssets {
  MockAssets._();

  static final Map<String, String> _pathCache = <String, String>{};

  /// 生成（或复用）一张占位图，返回本地绝对路径。
  ///
  /// [style] 0=媒体封面，1=书封，2=漫画页。
  static String imagePath(
    String seed, {
    int width = 480,
    int height = 320,
    int style = 0,
  }) {
    final key = '$seed|$width|$height|$style';
    final cached = _pathCache[key];
    if (cached != null && File(cached).existsSync()) return cached;

    final dir = Directory('${Directory.systemTemp.path}/slime_mock_assets');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File('${dir.path}/${key.hashCode.toRadixString(16)}.png');
    if (!file.existsSync()) {
      file.writeAsBytesSync(
        pngBytes(seed, width: width, height: height, style: style),
      );
    }
    _pathCache[key] = file.path;
    return file.path;
  }

  /// 直接返回 PNG 字节（Manga 阅读器走 Image.memory）
  static Uint8List pngBytes(
    String seed, {
    int width = 480,
    int height = 320,
    int style = 0,
  }) {
    final rgb = Uint8List(width * height * 3);
    final hash = seed.hashCode;
    final hue = hash.abs() % 360;
    final c1 = _hsl(hue.toDouble(), 0.55, 0.66);
    final c2 = _hsl(((hue + 52) % 360).toDouble(), 0.62, 0.34);

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final t = ((x / width) * 0.55 + (y / height) * 0.45).clamp(0.0, 1.0);
        var r = _mix(c1[0], c2[0], t);
        var g = _mix(c1[1], c2[1], t);
        var b = _mix(c1[2], c2[2], t);
        if (style == 2) {
          // 漫画页：浅底 + 分格
          r = 246;
          g = 244;
          b = 238;
        }
        final i = (y * width + x) * 3;
        rgb[i] = r;
        rgb[i + 1] = g;
        rgb[i + 2] = b;
      }
    }

    if (style == 2) {
      _drawPanels(rgb, width, height, hue);
    } else {
      // 封面加一条斜向高光，避免看起来像纯色块
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final d = ((x - y * 0.6) % 150);
          if (d > 0 && d < 26) {
            final i = (y * width + x) * 3;
            rgb[i] = (rgb[i] + 28).clamp(0, 255);
            rgb[i + 1] = (rgb[i + 1] + 28).clamp(0, 255);
            rgb[i + 2] = (rgb[i + 2] + 28).clamp(0, 255);
          }
        }
      }
    }
    return _encodePng(width, height, rgb);
  }

  static void _drawPanels(Uint8List rgb, int w, int h, int hue) {
    final panels = <List<int>>[
      [24, 20, w - 48, (h * 0.3).round()],
      [24, (h * 0.34).round(), (w * 0.46).round(), (h * 0.28).round()],
      [(w * 0.52).round(), (h * 0.34).round(), (w * 0.44).round(), (h * 0.28).round()],
      [24, (h * 0.66).round(), w - 48, (h * 0.28).round()],
    ];
    for (var p = 0; p < panels.length; p++) {
      final rect = panels[p];
      final color = _hsl(((hue + p * 36) % 360).toDouble(), 0.5, 0.62);
      for (var y = rect[1]; y < rect[1] + rect[3] && y < h; y++) {
        for (var x = rect[0]; x < rect[0] + rect[2] && x < w; x++) {
          // 描边
          final edge =
              x < rect[0] + 4 ||
              x >= rect[0] + rect[2] - 4 ||
              y < rect[1] + 4 ||
              y >= rect[1] + rect[3] - 4;
          final i = (y * w + x) * 3;
          if (edge) {
            rgb[i] = 32;
            rgb[i + 1] = 32;
            rgb[i + 2] = 36;
          } else {
            rgb[i] = color[0];
            rgb[i + 1] = color[1];
            rgb[i + 2] = color[2];
          }
        }
      }
    }
  }

  static int _mix(int a, int b, double t) => (a + (b - a) * t).round();

  static List<int> _hsl(double h, double s, double l) {
    final c = (1 - (2 * l - 1).abs()) * s;
    final x = c * (1 - ((h / 60) % 2 - 1).abs());
    final m = l - c / 2;
    double r = 0, g = 0, b = 0;
    if (h < 60) {
      r = c;
      g = x;
    } else if (h < 120) {
      r = x;
      g = c;
    } else if (h < 180) {
      g = c;
      b = x;
    } else if (h < 240) {
      g = x;
      b = c;
    } else if (h < 300) {
      r = x;
      b = c;
    } else {
      r = c;
      b = x;
    }
    return [
      ((r + m) * 255).round().clamp(0, 255),
      ((g + m) * 255).round().clamp(0, 255),
      ((b + m) * 255).round().clamp(0, 255),
    ];
  }

  static Uint8List _encodePng(int width, int height, Uint8List rgb) {
    final stride = width * 3;
    final raw = BytesBuilder();
    for (var y = 0; y < height; y++) {
      raw.addByte(0); // filter: none
      raw.add(Uint8List.sublistView(rgb, y * stride, (y + 1) * stride));
    }
    final compressed = ZLibCodec(level: 4).encode(raw.toBytes());

    final out = BytesBuilder();
    out.add(const [137, 80, 78, 71, 13, 10, 26, 10]);

    void chunk(String type, List<int> data) {
      final typeBytes = type.codeUnits;
      final len = ByteData(4)..setUint32(0, data.length);
      out.add(len.buffer.asUint8List());
      out.add(typeBytes);
      out.add(data);
      final crc = ByteData(4)..setUint32(0, _crc32([...typeBytes, ...data]));
      out.add(crc.buffer.asUint8List());
    }

    final ihdr = ByteData(13)
      ..setUint32(0, width)
      ..setUint32(4, height)
      ..setUint8(8, 8)
      ..setUint8(9, 2)
      ..setUint8(10, 0)
      ..setUint8(11, 0)
      ..setUint8(12, 0);
    chunk('IHDR', ihdr.buffer.asUint8List());
    chunk('IDAT', compressed);
    chunk('IEND', const []);
    return out.toBytes();
  }

  static int _crc32(List<int> data) {
    var crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc ^= byte;
      for (var i = 0; i < 8; i++) {
        crc = (crc & 1) != 0 ? 0xEDB88320 ^ (crc >> 1) : crc >> 1;
      }
    }
    return crc ^ 0xFFFFFFFF;
  }
}
