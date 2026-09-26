import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 30. Learn more hover — 箭头右移一档，两条臂同时绕尖端张开
///
/// 原稿这里只有两个量：整颗箭头 `translateX(2px)`，和两条臂各自
/// `rotate(±8deg)`——支点写在 svg 的 view-box 坐标 (10, 8)，也就是箭头尖端，
/// 所以看到的是"张角变大"而不是整颗歪掉。
/// 进出两个方向的时长/曲线是同一套（`--p24-in-dur` / `--p24-out-dur` 都是 350ms
/// 顺出），因此一条 LabTween 就够，三个属性都由它算：
/// 位移 = shift·t，张角 = spread·t，两臂各取正负。
/// 支点是"图标本地 16 网格"里的坐标，先平移到支点、旋转、再平移回来，
/// 用 Transform.rotate + alignment 的话支点会落在盒子的相对位置上，
/// 一旦箭头整体右移，张开的轴心就跟着飘。
const _btnH = 40.0;

/// `.p24-btn`：左内衬 16、右 10，文字与箭头之间 8
const _padLeft = 16.0;
const _padRight = 10.0;
const _gap = 8.0;

const _dur = Duration(milliseconds: 350); // `--p24-in-dur` / `--p24-out-dur`

/// `--p24-shift` / `--p24-spread`（度）
const _shift = 2.0;
const _spread = 8.0;

/// 两臂的支点：svg view-box 里的 (10, 8)
const _pivot = Offset(10, 8);

const _armTop = 'M6 4L10 8';
const _armBot = 'M10 8L6 12';

/// `.p24-chevron` 的灰：浅色盘下取图标弱色档
const _chevronColor = LabColor.iconMuted;

const _labelStyle = TextStyle(
  fontFamily: LabFont.family,
  fontFamilyFallback: LabFont.fallback,
  fontSize: 13,
  fontWeight: FontWeight.w500,
  height: 1.4,
  color: LabColor.text,
);

class Case30LearnMoreHover extends StatefulWidget {
  const Case30LearnMoreHover({super.key});

  @override
  State<Case30LearnMoreHover> createState() => _Case30LearnMoreHoverState();
}

class _Case30LearnMoreHoverState extends State<Case30LearnMoreHover> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return LabStage(
      child: Stack(
        children: [
          Center(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: Container(
                height: _btnH,
                // 右内衬比左内衬小 6：箭头的右移量就吃在这一档里
                padding: const EdgeInsets.fromLTRB(_padLeft, 8, _padRight, 8),
                decoration: BoxDecoration(
                  color: LabColor.card,
                  borderRadius: BorderRadius.circular(50),
                  boxShadow: LabShadow.material,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Learn more', style: _labelStyle),
                    const SizedBox(width: _gap),
                    LabTween(
                      target: _hovered ? 1 : 0,
                      duration: _dur,
                      curve: LabEase.smoothOut,
                      builder: (context, t) => _Chevron(t: t),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 箭头：先整体右移，再让两臂绕尖端张开
class _Chevron extends StatelessWidget {
  const _Chevron({required this.t});

  /// 0 = 静止，1 = 悬停到位
  final double t;

  @override
  Widget build(BuildContext context) {
    final spread = _spread * t * math.pi / 180;
    return Transform.translate(
      offset: Offset(_shift * t, 0),
      child: SizedBox(
        width: 16,
        height: 16,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 张开的两臂会越出 16 的盒子，所以不裁
            _Arm(path: _armTop, angle: spread),
            _Arm(path: _armBot, angle: -spread),
          ],
        ),
      ),
    );
  }
}

/// 一条臂：绕支点旋转，笔宽固定（对应 svg 的 non-scaling-stroke）
class _Arm extends StatelessWidget {
  const _Arm({required this.path, required this.angle});

  final String path;

  /// 弧度，正 = 顺时针（和 CSS 的 rotate 同向）
  final double angle;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Transform(
        transform: Matrix4.identity()
          ..translateByDouble(_pivot.dx, _pivot.dy, 0, 1)
          ..rotateZ(angle)
          ..translateByDouble(-_pivot.dx, -_pivot.dy, 0, 1),
        child: LabIcon(
          paths: [path],
          size: 16,
          strokeWidth: 1.5,
          color: _chevronColor,
        ),
      ),
    );
  }
}
