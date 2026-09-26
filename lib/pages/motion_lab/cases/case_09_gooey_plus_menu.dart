import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 9. Gooey plus menu — 液滴从中心炸开成扇形三个动作
///
/// 参考稿是一层 SVG 液体 + 一层清晰按钮：四个 r=20 的圆共用 `blur(6) + 18A-7`
/// 阈值滤镜融合成液体，按钮层带着 16 描边图标跟着走。
/// Flutter 这边拿不到 `ColorFilter.matrix` 需要的 Float64List（不在允许 import 里），
/// 改用等效近似：三根"颈线"（圆头粗线）从中心圆连到飞出的圆，
/// 线宽随距离收缩到 0 —— 视觉上同样是拉丝、变细、掐断。
///
/// 时间线全部按语料 token：
/// 位移开 350ms `--pv3i` 过冲曲线、每颗错峰 40ms（`--pv4a`），收 250ms 顺出不错峰；
/// 图标开 180ms ease（延迟 = 错峰 + 120ms）、收 120ms；
/// 加号自转 45°（`--pv2x`）250ms ease-in-out；悬浮底色 120ms。
const _base = Offset(148, 130); // 圆心：200×140 盒在舞台居中后再上移 30

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
    return LabStage(
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _GooPainter(positions)),
          ),
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

/// 液体层：阴影跟着融合后的轮廓走（对应 SVG 里 feMerge 的三层）
class _GooPainter extends CustomPainter {
  const _GooPainter(this.centers);

  final List<Offset> centers;

  /// 颈线掐断的距离：圆先相切（d=2r），再被模糊"粘"开一截
  static const _fuse = 52.0;

  @override
  void paint(Canvas canvas, Size size) {
    _silhouette(canvas, const Offset(0, 4), _r,
        Paint()
          ..color = const Color(0x0F000000) // 0 4px 42px @6%
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 21));
    _silhouette(canvas, const Offset(0, 2), _r,
        Paint()
          ..color = const Color(0x0D000000) // 0 2px 6px @5%
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    _silhouette(canvas, Offset.zero, _r + 1,
        Paint()..color = const Color(0x0F000000)); // 1px 描边环 @6%
    _silhouette(canvas, Offset.zero, _r, Paint()..color = _blobColor);
  }

  /// 中心圆 + 每颗液滴 + 之间的圆头颈线，画成一整块
  void _silhouette(Canvas canvas, Offset shift, double r, Paint paint) {
    canvas.drawCircle(_base + shift, r, paint);
    for (final c in centers) {
      final p = c + shift;
      final d = (p - (_base + shift)).distance;
      if (d > 0.5) {
        final neck = _r * _clamp01(1 - d / _fuse);
        if (neck > 0.4) {
          canvas.drawLine(
            _base + shift,
            p,
            Paint()
              ..color = paint.color
              ..strokeWidth = neck * 2
              ..strokeCap = StrokeCap.round,
          );
        }
      }
      canvas.drawCircle(p, r, paint);
    }
  }

  static double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

  @override
  bool shouldRepaint(_GooPainter old) => old.centers != centers;
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
