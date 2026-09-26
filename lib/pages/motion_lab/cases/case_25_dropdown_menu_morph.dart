import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 25. Dropdown menu morph — 圆钮长成菜单面板，加号转成×滑走、菜单从右边推进来
///
/// 三组属性各有各的表：面板尺寸/圆角开 350ms 走带过冲的弹（宽度会先顶过头再坐回
/// 183），位移/缩放/旋转 350ms 顺出，透明度和模糊只给 200ms。
/// 所以只留一条 linear 主时钟、三组各自换算一次：走 `animateTo(curve:)` 的话
/// AnimationController 会把过冲截平，那一下弹就直接没了。
const _wClosed = 40.0; // --p20-w-closed
const _hClosed = 40.0; // --p20-h-closed
const _wOpen = 183.0; // --p20-w-open
const _hOpen = 172.0; // --p20-h-open
const _rClosed = 40.0; // --p20-r-closed
const _rOpen = 20.0; // --p20-r-open

const _openMs =
    350.0; // --p20-open-dur / --p20-slide-in-dur / --p20-slide-out-dur
const _closeMs = 250.0; // --p20-close-dur
const _fadeMs = 200.0; // --p20-fade-dur

const _slide = 40.0; // --p20-slide-in-shift / --p20-slide-out-shift
const _scale = 0.97; // --p20-scale
const _rotate = 45.0 * math.pi / 180.0; // --p20-rotate
const _blur = 2.0; // --p20-blur

/// --p20-ease：开面板那条弹（比通用 pop 的 1.36 低一档，单独存）
const _morphEase = Cubic(0.34, 1.25, 0.64, 1);

/// 锚块在舞台里横向居中、底部留 (296 - 183) / 2
const _inset = (296.0 - _wOpen) / 2;

/// `.p20-plus:hover::before` 的圆底水洗
const _hoverWash = Color(0x0A000000);

const _plusPath = 'M10 4V16M4 10H16';

/// `.p20-bar`：14 高 / 圆角 4，纵向间隔 20
const _barH = 14.0;
const _barWidths = [77.0, 95.0, 68.0, 95.0];

class Case25DropdownMenuMorph extends StatefulWidget {
  const Case25DropdownMenuMorph({super.key});

  @override
  State<Case25DropdownMenuMorph> createState() =>
      _Case25DropdownMenuMorphState();
}

class _Case25DropdownMenuMorphState extends State<Case25DropdownMenuMorph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
    value: 0,
  );

  bool _open = false;
  bool _hovered = false;

  /// 这趟跑的是开（350）还是收（250）：淡入淡出得按当趟总长换算自己的 200
  double _spanMs = _openMs;

  @override
  void initState() {
    super.initState();
    _clock.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  void _toggle() {
    final next = !_open;
    setState(() {
      _open = next;
      _spanMs = next ? _openMs : _closeMs;
    });
    _clock.animateTo(
      next ? 1 : 0,
      duration: Duration(milliseconds: _spanMs.round()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _clock.value;
    final morphP = (_open ? _morphEase : LabEase.smoothOut).transform(t);
    final slideP = LabEase.smoothOut.transform(t);
    final fadeP = LabEase.smoothOut.transform(
      (t * _spanMs / _fadeMs).clamp(0.0, 1.0),
    );

    final w = _wClosed + (_wOpen - _wClosed) * morphP;
    final h = _hClosed + (_hOpen - _hClosed) * morphP;
    final radius = BorderRadius.circular(
      _rClosed + (_rOpen - _rClosed) * morphP,
    );

    return LabStage(
      child: Stack(
        children: [
          // 锚的是右下角：开的时候往左上长，收的时候缩回同一颗钮
          Positioned(
            right: _inset,
            bottom: _inset,
            width: w,
            height: h,
            // 整个面板都吃点击：开态下加号自己 pointer-events: none，靠外层收回去
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggle,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: LabColor.card,
                  borderRadius: radius,
                  boxShadow: LabShadow.material,
                ),
                child: ClipRRect(
                  borderRadius: radius,
                  child: Stack(
                    children: [
                      // 菜单先画，压在加号底下（DOM 里 .p20-menu 也在前）
                      Positioned(
                        // 菜单永远按展开尺寸排版：面板还在 morph 的时候由外层
                        // ClipRRect 裁掉多出来的部分，等价于 CSS 的 overflow hidden
                        left: 0,
                        top: 0,
                        width: _wOpen,
                        height: _hOpen,
                        child: IgnorePointer(
                          ignoring: fadeP < 1,
                          child: Opacity(
                            opacity: fadeP.clamp(0.0, 1.0),
                            child: Transform.translate(
                              offset: Offset(_slide * (1 - slideP), 0),
                              child: Transform.scale(
                                scale: _scale + (1 - _scale) * slideP,
                                child: LabBlur(
                                  sigma: _blur * (1 - fadeP),
                                  child: const Padding(
                                    padding: EdgeInsets.fromLTRB(23, 20, 0, 0),
                                    child: _MenuBars(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Opacity(
                          opacity: (1 - fadeP).clamp(0.0, 1.0),
                          child: Transform.translate(
                            offset: Offset(-_slide * slideP, 0),
                            child: LabBlur(
                              sigma: _blur * fadeP,
                              child: _plus(slideP),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 40 圆钮：水洗底只有悬停才出现，图标跟着 slideP 缩到 0.97 并转 45 度
  Widget _plus(double slideP) {
    return IgnorePointer(
      // 开态下加号 pointer-events: none，连悬停水洗一起停
      ignoring: _open,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: SizedBox(
          width: _wClosed,
          height: _hClosed,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: LabEase.smoothOut,
                width: _wClosed,
                height: _hClosed,
                decoration: BoxDecoration(
                  color: _hovered ? _hoverWash : Colors.transparent,
                  shape: BoxShape.circle,
                ),
              ),
              Transform.rotate(
                angle: _rotate * slideP,
                child: Transform.scale(
                  scale: _scale + (1 - _scale) * slideP,
                  child: const LabIcon(
                    paths: [_plusPath],
                    size: 20,
                    viewBox: 20,
                    strokeWidth: 1.75,
                    color: LabColor.text,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 四条骨架条，纵向间隔 20
class _MenuBars extends StatelessWidget {
  const _MenuBars();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _barWidths.length; i++)
          Padding(
            padding: EdgeInsets.only(
              bottom: i == _barWidths.length - 1 ? 0 : 20,
            ),
            child: Container(
              width: _barWidths[i],
              height: _barH,
              decoration: const BoxDecoration(
                color: LabColor.skeleton,
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
            ),
          ),
      ],
    );
  }
}
