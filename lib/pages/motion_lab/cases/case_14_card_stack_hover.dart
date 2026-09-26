import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 14. Card stack hover — 悬停把三张叠牌弹开成扇形
///
/// 参考稿把"开"和"回"设成两条不同的时间线：
/// 开 410ms `--pvn`(0.31,1.84,0.64,1)——弹性明显过冲；
/// 回 360ms `--pvg`(0.34,1.5,0.64,1)——过冲收敛一档。
/// 单卡放大是另一条独立的 610ms 顺出（`--pvo`/`--pvh`），叠在扇形之上，
/// 所以这里位移/旋转/透明度走一条 LabTween，scale 单独再套一条。
///
/// 位移量是 CSS 变量直译：展开位置 = (cx + dx*1.42, cy + dy)，
/// 1.42（`--pv1d`）让左右两张飞得比声明的 ±34 更远一点。
const _fanOpenDur = Duration(milliseconds: 410); // `--pv10`
const _fanCloseDur = Duration(milliseconds: 360); // `--pvm`
const _scaleDur = Duration(milliseconds: 610); // `--pvo`
const _fanOpenEase = Cubic(0.31, 1.84, 0.64, 1); // `--pvn`
const _fanCloseEase = Cubic(0.34, 1.5, 0.64, 1); // `--pvg`

/// `--pv1d` / `--pv11` / `--pv1q`
const _dxGain = 1.42;
const _drotGain = 1.0;
const _hoverScale = 1.04;

/// 单卡 `.pv24`：78×78、圆角 12、白底
const _cardSize = 78.0;
const _cardRadius = 12.0;

/// 参考稿卡内是截图位图，离屏出图会成豆腐块：按纯色占位画
const _shotBg = Color(0xFFE9EAEE);
const _shotBar = Color(0xFFD9DADF);

/// 三张牌的静态参数，照抄舞台内联 style（--cx/--cy/--rot/--dx/--dy/--drot/--card-op/z）
const _specs = [
  _CardSpec(10.87, 19.77, -8, -34, 0, -6, 0.5, 1),
  _CardSpec(29.47, 18.37, 4, 34, 0, 6, 0.5, 0),
  _CardSpec(21, 21, 0, 0, 0, 0, 1, 2),
];

/// `.pro-surface-shadow`（浅色盘）
const _cardShadow = <BoxShadow>[
  BoxShadow(color: LabColor.border, blurRadius: 0, spreadRadius: 1),
  BoxShadow(color: Color(0x0D000000), blurRadius: 6, offset: Offset(0, 2)),
  BoxShadow(color: Color(0x0F000000), blurRadius: 42, offset: Offset(0, 4)),
];

class _CardSpec {
  const _CardSpec(this.cx, this.cy, this.rot, this.dx, this.dy, this.drot,
      this.opacity, this.z);

  final double cx;
  final double cy;
  final double rot;
  final double dx;
  final double dy;
  final double drot;
  final double opacity;
  final int z;
}

class Case14CardStackHover extends StatefulWidget {
  const Case14CardStackHover({super.key});

  @override
  State<Case14CardStackHover> createState() => _Case14CardStackHoverState();
}

class _Case14CardStackHoverState extends State<Case14CardStackHover> {
  bool _stackHovered = false;
  int? _cardHovered;

  /// 鼠标指针是否落在整摞的 120 框内：只有它才有权"离开整摞"
  bool _pointerInStack = false;

  @override
  Widget build(BuildContext context) {
    // 绘制序 = z 序；被单指的那张抬到最顶（CSS z-index:30）
    final order = [0, 1, 2]
      ..sort((a, b) {
        final za = a == _cardHovered ? 30 : _specs[a].z;
        final zb = b == _cardHovered ? 30 : _specs[b].z;
        return za.compareTo(zb);
      });
    return LabStage(
      child: Center(
        child: MouseRegion(
          onEnter: (_) => setState(() {
            _pointerInStack = true;
            _stackHovered = true;
          }),
          onExit: (_) => setState(() {
            _pointerInStack = false;
            _stackHovered = false;
            _cardHovered = null;
          }),
          child: SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (final i in order)
                  Positioned(
                    left: 0,
                    top: 0,
                    child: _StackCard(
                      spec: _specs[i],
                      // 进出各用一条曲线，curve 跟着 target 一起换
                      fanned: _stackHovered,
                      hovered: _cardHovered == i,
                      onCardEnter: () => setState(() {
                        _stackHovered = true;
                        _cardHovered = i;
                      }),
                      // 触屏没有"移出整摞"这一步：再点同一颗就把扇形也收回
                      onCardExit: () => setState(() {
                        if (_cardHovered != i) return;
                        _cardHovered = null;
                        if (!_pointerInStack) _stackHovered = false;
                      }),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 一张牌：外层 LabTween 管扇形位移/旋转/透明度，内层管单指 scale
class _StackCard extends StatelessWidget {
  const _StackCard({
    required this.spec,
    required this.fanned,
    required this.hovered,
    required this.onCardEnter,
    required this.onCardExit,
  });

  final _CardSpec spec;
  final bool fanned;
  final bool hovered;
  final VoidCallback onCardEnter;
  final VoidCallback onCardExit;

  @override
  Widget build(BuildContext context) {
    return LabTween(
      target: fanned ? 1 : 0,
      duration: fanned ? _fanOpenDur : _fanCloseDur,
      curve: fanned ? _fanOpenEase : _fanCloseEase,
      builder: (context, t) => LabTween(
        target: hovered ? 1 : 0,
        duration: _scaleDur,
        curve: LabEase.smoothOut,
        builder: (context, s) => Transform.translate(
          offset: Offset(
            spec.cx + spec.dx * _dxGain * t,
            spec.cy + spec.dy * t,
          ),
          // CSS 独立变换按 translate→rotate→scale 复合，嵌套序与之等价
          child: Transform.rotate(
            angle: (spec.rot + spec.drot * _drotGain * t) * math.pi / 180,
            child: Transform.scale(
              scale: 1 + (_hoverScale - 1) * s,
              child: Opacity(
                opacity: spec.opacity + (1 - spec.opacity) * t,
                child: LabHoverRegion(
                  group: 'c14',
                  onEnter: onCardEnter,
                  onExit: onCardExit,
                  child: const _CardFace(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 牌面：白底圆角 + 三层投影 + 截图占位
class _CardFace extends StatelessWidget {
  const _CardFace();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_cardRadius),
      child: Container(
        width: _cardSize,
        height: _cardSize,
        decoration: const BoxDecoration(
          color: LabColor.card,
          boxShadow: _cardShadow,
        ),
        // 占位"截图"：一条顶栏 + 两块内容条
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_shotBg, Color(0xFFF3F4F7)],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              right: 0,
              height: 14,
              child: ColoredBox(color: _shotBar),
            ),
            Positioned(
              left: 10,
              top: 26,
              width: 42,
              height: 8,
              child: ColoredBox(
                color: _shotBar,
              ),
            ),
            Positioned(
              left: 10,
              top: 40,
              width: 58,
              height: 26,
              child: ColoredBox(
                color: _shotBar.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
