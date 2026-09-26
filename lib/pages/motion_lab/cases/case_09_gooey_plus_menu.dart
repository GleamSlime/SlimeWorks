import 'dart:math' as math;
import 'dart:typed_data' show Float64List;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 9. Gooey plus menu — 液滴从中心炸开成扇形三个动作
///
/// 参考稿是一层 SVG 液体 + 一层清晰按钮：四个 r=20 的圆共用
/// `feGaussianBlur(stdDeviation 6)` → `feColorMatrix(18A-7)` 把糊边重新拉成硬边，
/// 相邻两团的糊边在重叠处就粘成一座"桥"；再 `feComposite atop SourceGraphic`
/// 把原始图形叠回上方，所以图标始终是清晰的、只有边缘是液体的。
/// Flutter 这边是同一套：`ImageFiltered(blur)` 外面再包一层 `ColorFiltered(阈值矩阵)`，
/// 阈值矩阵的偏移量按 0–255 口径换算（-7 的 0–1 口径 = -7×255）。
/// 阴影打在融合后的轮廓上（对应 feDropShadow 排在 goo 之后），所以拉丝的桥也带影。
///
/// 时间线全部按语料 token：
/// 位移开 350ms `--pv3i` 过冲曲线、每颗错峰 40ms（`--pv4a`），收 250ms 顺出不错峰；
/// 图标开 180ms ease（延迟 = 错峰 + 120ms）、收 120ms；
/// 加号自转 45°（`--pv2x`）250ms ease-in-out；悬浮底色 120ms。
const _base = Offset(148, 130); // 圆心：200×140 盒在舞台居中后再上移 30

/// `stdDeviation="6"`
const _gooBlur = 6.0;

/// `values="… 0 0 0 18 -7"`：只改 alpha 那一行，RGB 原样透传。
/// 矩阵的平移列是 0–255 口径，所以 -7 要乘回 255。
final Float64List _gooAlpha = Float64List.fromList(const [
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0, //
  0, 0, 1, 0, 0, //
  0, 0, 0, 18, -7 * 255, //
]);

/// `values="… 0 0 0 60 -29.5"`：同一族阈值，只是把 alpha 硬切在 0.5
final Float64List _solid = Float64List.fromList(const [
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0, //
  0, 0, 1, 0, 0, //
  0, 0, 0, 60, -29.5 * 255, //
]);

/// 三颗液滴的飞行位移（`--fx/--fy`）
const _fan = [Offset(-54, -34), Offset(0, -64), Offset(54, -34)];
const _r = 20.0; // SVG r=20

const _moveOpenDur = Duration(milliseconds: 350); // `--pv3x`
const _moveCloseDur = Duration(milliseconds: 250); // `--pv3g`
const _stagger = Duration(milliseconds: 40); // `--pv4a`
const _iconOpenDur = Duration(milliseconds: 180);
const _iconCloseDur = Duration(milliseconds: 120);
const _iconLead = Duration(milliseconds: 120); // 图标比位移晚 120ms
const _rotDur = Duration(milliseconds: 250); // `--pv3w`

/// `--pv3i: cubic-bezier(0.34,1.56,0.64,1)`——比 LabEase.pop 过冲更狠一档
const _popHard = Cubic(0.34, 1.56, 0.64, 1);

/// CSS 关键字 `ease`
const _cssEase = Cubic(0.25, 0.1, 0.25, 1);

/// 液滴体色 = `--card-bg`（浅色盘是纯白），悬浮底 rgba(0,0,0,.04)
const _blobColor = LabColor.card;

class Case09GooeyPlusMenu extends StatefulWidget {
  const Case09GooeyPlusMenu({super.key});

  @override
  State<Case09GooeyPlusMenu> createState() => _Case09GooeyPlusMenuState();
}

class _Case09GooeyPlusMenuState extends State<Case09GooeyPlusMenu>
    with TickerProviderStateMixin {
  late final AnimationController _move = AnimationController(vsync: this);
  late final AnimationController _icon = AnimationController(vsync: this);
  late final AnimationController _rot = AnimationController(
    vsync: this,
    duration: _rotDur,
  );

  bool _open = false;
  bool _opening = false;
  int _hovered = -1;

  // 位移总时长要把错峰算进去：最后一颗 40*2ms 起步、再走 350ms
  static const int _moveTotalOpenMs = 350 + 40 * 2;
  static const int _iconTotalOpenMs = 120 + 180 + 40 * 2;

  @override
  void initState() {
    super.initState();
    _move.addListener(_rebuild);
    _icon.addListener(_rebuild);
    _rot.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _move.dispose();
    _icon.dispose();
    _rot.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    _opening = _open;
    if (_open) {
      _move.animateTo(1,
          duration: const Duration(milliseconds: _moveTotalOpenMs),
          curve: Curves.linear);
      _icon.animateTo(1,
          duration: const Duration(milliseconds: _iconTotalOpenMs),
          curve: Curves.linear);
    } else {
      _move.animateTo(0, duration: _moveCloseDur, curve: LabEase.smoothOut);
      _icon.animateTo(0, duration: _iconCloseDur, curve: _cssEase);
    }
    _rot.animateTo(_open ? 1 : 0, curve: Curves.easeInOut);
  }

  /// 每颗液滴自己的进度：开 = 错峰 40ms + 过冲曲线；收 = 全体同步顺出
  double _piece(
      double v, int i, int totalMs, int durMs, int leadMs, Curve openCurve) {
    if (_opening) {
      final local =
          ((v * totalMs - (leadMs + i * _stagger.inMilliseconds)) / durMs)
              .clamp(0.0, 1.0);
      return openCurve.transform(local);
    }
    return v.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final positions = <Offset>[];
    final iconPs = <double>[];
    for (var i = 0; i < 3; i++) {
      final p = _piece(_move.value, i, _moveTotalOpenMs,
          _moveOpenDur.inMilliseconds, 0, _popHard);
      positions.add(_base + _fan[i] * p);
      iconPs.add(_piece(_icon.value, i, _iconTotalOpenMs,
          _iconOpenDur.inMilliseconds, _iconLead.inMilliseconds, _cssEase));
    }
    // 从下到上：两团宽影 → 1px 环 → 液体 → 清晰原图（对应 feMerge 的四层）
    // 每一层都是从同一份糊+阈值后的轮廓染出来的，所以拉丝的桥也带着影
    final liquid = _Goo(centers: positions);
    return LabStage(
      child: Stack(
        children: [
          Positioned.fill(child: liquid.tinted(dy: 4, sigma: 21, opacity: 0.06)),
          Positioned.fill(child: liquid.tinted(dy: 2, sigma: 3, opacity: 0.05)),
          Positioned.fill(child: liquid.ring(0.06)),
          Positioned.fill(child: liquid),
          for (var i = 0; i < 3; i++)
            Positioned(
              left: positions[i].dx - _r,
              top: positions[i].dy - _r,
              child: _ActionItem(
                paths: _actionPaths[i],
                progress: iconPs[i],
                enabled: _open,
                hovered: _hovered == i,
                onEnter: () => setState(() => _hovered = i),
                onExit: () => setState(() => _hovered = -1),
              ),
            ),
          Positioned(
            left: _base.dx - _r,
            top: _base.dy - _r,
            child: _PlusTrigger(
              rotation: _rot.value,
              onTap: _toggle,
            ),
          ),
        ],
      ),
    );
  }
}

/// 三个动作的描边图标（viewBox 16，stroke-width 1.4），依次是新建文件/添加图片/新建文件夹
const _actionPaths = [
  [
    'M9 1.5H4A1.5 1.5 0 0 0 2.5 3v10A1.5 1.5 0 0 0 4 14.5h8a1.5 1.5 0 0 0 1.5-1.5V6z',
    'M9 1.5V6h4.5',
  ],
  [
    'M3.5 1.5H12.5A2 2 0 0 1 14.5 3.5V12.5A2 2 0 0 1 12.5 14.5H3.5A2 2 0 0 1 1.5 12.5V3.5A2 2 0 0 1 3.5 1.5Z',
    'M6.75 5.5A1.25 1.25 0 1 1 4.25 5.5A1.25 1.25 0 1 1 6.75 5.5Z',
    'M14.5 10.5L11 7l-7.5 7.5',
  ],
  [
    'M14.5 12.5A1.5 1.5 0 0 1 13 14H3a1.5 1.5 0 0 1-1.5-1.5V3A1.5 1.5 0 0 1 3 1.5h3L7.5 4H13a1.5 1.5 0 0 1 1.5 1.5z',
  ],
];

/// 液体：一堆圆 → 糊 6 → alpha 阈值拉硬边 → 清晰原图叠回上方
///
/// 对应滤镜链里的 blur + colormatrix + composite atop 三步。相邻两团的糊边在
/// 重叠处相加后越过阈值，就粘成一座桥；桥掐断的瞬间是阈值决定的，不是算出来的宽度。
class _Goo extends StatelessWidget {
  const _Goo({required this.centers, this.r = _r});

  final List<Offset> centers;
  final double r;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColorFiltered(
          colorFilter: ColorFilter.matrix(_gooAlpha),
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: _gooBlur, sigmaY: _gooBlur),
            child: _Blobs(centers: centers, r: r),
          ),
        ),
        // 清晰层：图标和圆心始终是硬的，只有边缘是液体的
        _Blobs(centers: centers, r: r),
      ],
    );
  }

  /// 影：从融合后的轮廓染色（feFlood + composite in），σ = CSS blur 的一半
  Widget tinted({required double dy, required double sigma, required double opacity}) {
    return Transform.translate(
      offset: Offset(0, dy),
      child: ColorFiltered(
        colorFilter: ColorFilter.matrix(_tint(opacity)),
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: _Goo(centers: centers, r: r),
        ),
      ),
    );
  }

  /// 1px 外环：SVG 用 dilate，这里等效成半径 +1 的同一滩液体。
  /// 套一层 0.5 二值化是因为液体边缘本就带 ~1px 软边，直接染色会读出两根发丝线。
  Widget ring(double opacity) {
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(_tint(opacity)),
      child: ColorFiltered(
        colorFilter: ColorFilter.matrix(_solid),
        child: _Goo(centers: centers, r: r + 1),
      ),
    );
  }
}

/// 染色矩阵：RGB 归零、alpha 按比例压暗（0–255 口径，平移列在 0–255 空间）
Float64List _tint(double opacity) => Float64List.fromList([
      0, 0, 0, 0, 0, //
      0, 0, 0, 0, 0, //
      0, 0, 0, 0, 0, //
      0, 0, 0, opacity, 0, //
    ]);

/// 中心圆 + 三颗液滴的原始图形
class _Blobs extends StatelessWidget {
  const _Blobs({required this.centers, required this.r});

  final List<Offset> centers;
  final double r;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _BlobPainter(centers: centers, r: r));
  }
}

class _BlobPainter extends CustomPainter {
  const _BlobPainter({required this.centers, required this.r});

  final List<Offset> centers;
  final double r;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = _blobColor;
    canvas.drawCircle(_base, r, paint);
    for (final c in centers) {
      canvas.drawCircle(c, r, paint);
    }
  }

  @override
  bool shouldRepaint(_BlobPainter old) =>
      old.r != r || !listEquals(old.centers, centers);
}

/// 一颗动作按钮：40 圆命中区 + 悬浮底色 + 延迟淡入的图标
class _ActionItem extends StatelessWidget {
  const _ActionItem({
    required this.paths,
    required this.progress,
    required this.enabled,
    required this.hovered,
    required this.onEnter,
    required this.onExit,
  });

  final List<String> paths;

  /// 图标自己的淡入进度（0→1）
  final double progress;
  final bool enabled;
  final bool hovered;
  final VoidCallback onEnter;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      // 收起时 pointer-events:none，只留加号可点
      ignoring: !enabled,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => onEnter(),
        onExit: (_) => onExit(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.ease,
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hovered ? const Color(0x0A000000) : Colors.transparent,
          ),
          alignment: Alignment.center,
          child: Opacity(
            opacity: progress.clamp(0.0, 1.0),
            child: LabBlur(
              sigma: 2 * (1 - progress).clamp(0.0, 1.0),
              child: LabIcon(
                paths: paths,
                size: 16,
                strokeWidth: 1.4,
                color: LabColor.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 中心的加号触发器：20 描边加号，展开时整体转 45°
class _PlusTrigger extends StatelessWidget {
  const _PlusTrigger({required this.rotation, required this.onTap});

  final double rotation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Transform.rotate(
          // 展开 = 45°（`--pv2x`）
          angle: rotation * math.pi / 4,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: LabIcon(
                paths: const ['M10 4V16M4 10H16'],
                size: 20,
                viewBox: 20,
                strokeWidth: 1.75,
                color: LabColor.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
