import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path_drawing/path_drawing.dart';

/// 一条笔画：Tabler outline 里的一段 SVG path，坐标系固定 24x24。
@immutable
class StrokePath {
  const StrokePath(this.d) : solid = false;

  /// 少数图标里有实心小块（状态点、瞳孔），它们没有中心线，只能整体淡入
  const StrokePath.filled(this.d) : solid = true;

  final String d;
  final bool solid;
}

/// 一个描边图标：Tabler outline 的几何 + 笔画顺序。
///
/// 几何由 `tool/stroke_icons/generate.dart` 在构建期按映射表裁剪生成，
/// 未引用的图标不进产物——icon font 和 assets 目录都做不到这点。
@immutable
class StrokeIcon {
  const StrokeIcon({required this.name, required this.paths});

  /// Tabler 原始图标名，只用于调试与断言
  final String name;
  final List<StrokePath> paths;

  /// 视图框边长：描边宽度与动画节奏都在这个空间里定义，绘制时整体缩放
  static const double viewBox = 24;

  @override
  String toString() => 'StrokeIcon($name)';
}

/// 解析后的几何：Path + 弧长度量 + 实心块标记。
///
/// 缓存理由：`computeMetrics()` 每次都要走一遍 native，而 d 字符串是常量。
/// 度量对象与它所属的 [ui.Path] 同生命周期，所以三者一起留在缓存里。
@immutable
class StrokeGeometry {
  StrokeGeometry(this.paths, this.metrics, this.lengths, this.solid)
      : totalLength = lengths.fold<double>(0.0, (a, b) => a + b);

  final List<ui.Path> paths;
  final List<List<ui.PathMetric>> metrics;

  /// 与 [paths] 等长；空路径与实心块可能为 0
  final List<double> lengths;

  /// 该笔画是实心块还是可描的中心线
  final List<bool> solid;
  final double totalLength;
}

final Map<String, StrokeGeometry> _geometryCache = {};

/// 取图标几何（24 空间下的原图，绘制方用 `canvas.scale(size / 24)`）。
///
/// 缩放放在绘制时而不是解析时，弧长比例才与尺寸无关，缓存才能跨尺寸复用。
StrokeGeometry geometryOf(StrokeIcon icon) {
  final cached = _geometryCache[icon.name];
  if (cached != null) return cached;

  final paths = <ui.Path>[];
  final metrics = <List<ui.PathMetric>>[];
  final lengths = <double>[];
  final solid = <bool>[];
  for (final stroke in icon.paths) {
    final path = parseSvgPathData(stroke.d);
    // 空 d 没有度量，按长度 0 在绘制时跳过
    final m = path.computeMetrics().toList(growable: false);
    paths.add(path);
    metrics.add(m);
    lengths.add(m.fold<double>(0.0, (sum, e) => sum + e.length));
    solid.add(stroke.solid);
  }

  return _geometryCache[icon.name] =
      StrokeGeometry(paths, metrics, lengths, solid);
}

/// 把 0~1 的总进度按弧长**顺序**摊到各条笔画上，返回每条各自的 0~1。
///
/// 两条规则：
/// 1. 按长度而不是按条数分时间——否则"一个点的圆"和"一整圈外框"用同样时间画完，
///    观感是中间卡一下；
/// 2. 顺序画（前一条画完才轮到下一条），像一只手连续描下来；
///    等速同时长大读不出笔顺。
List<double> strokeProgressFor(StrokeGeometry geometry, double progress) {
  if (geometry.totalLength <= 0) {
    return List.filled(geometry.paths.length, progress);
  }
  final target = progress.clamp(0.0, 1.0) * geometry.totalLength;
  var walked = 0.0;
  return [
    for (final length in geometry.lengths)
      () {
        final start = walked;
        walked += length;
        if (length <= 0) return 1.0;
        return ((target - start) / length).clamp(0.0, 1.0);
      }(),
  ];
}
