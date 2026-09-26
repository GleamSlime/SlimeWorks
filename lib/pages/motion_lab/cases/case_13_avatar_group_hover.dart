import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 13. Avatar group hover — 邻接头像按距离衰减抬起，回程带过冲
///
/// 参考稿的难点不在"抬起"，而在**一次悬停同时改写整排**：
/// 被指的那颗 scale 1.05，其余只按 `lift * falloff^距离` 平移，
/// 整排是一条衰减曲线而不是一个开关。
/// 这里给每颗各挂一条 LabTween，进度直接取衰减后的目标值——
/// 这样"离开时全部归零"和"在排内滑动时只改一两档"共用同一套补间，
/// 不会出现某颗先跳回原位再抬起来。
/// 曲线是分方向的：进入用顺出，离开用带回弹的那条，所以 curve 跟着 target 一起换。
const _lift = -4.0; // `--avatar-lift`
const _falloff = 0.45; // `--avatar-falloff`
const _scaleActive = 1.05; // `--avatar-scale`
const _dur = Duration(milliseconds: 320); // `--avatar-dur`

/// `--avatar-ease-out: cubic-bezier(0.34, 3.85, 0.64, 1)`——只在回程用
const _easeOut = Cubic(0.34, 3.85, 0.64, 1);

/// `.p11-avatar`：32 圆 + 1.5 舞台色描边，相邻之间压掉 8
const _size = 32.0;
const _step = 24.0;
const _borderWidth = 1.5;

/// 位图头像在离屏出图里是豆腐块，按参考稿的纯色底 + 字母占位画
const _initials = ['A', 'B', 'C', 'D', 'E', 'F'];

/// 排尾那颗是文字块，不是头像位
const _moreLabel = '+2';

/// `.p11-avatar` 的底色，与 `+N` 那颗的 80/20 混色底
const _avatarBg = Color(0xFFEEEEEF);
const _moreBg = Color(0xFFC7C7C7);

const _initialStyle = TextStyle(
  fontFamily: LabFont.family,
  fontFamilyFallback: LabFont.fallback,
  fontSize: 11,
  fontWeight: FontWeight.w500,
  height: 1,
  color: LabColor.textFaint,
);

class Case13AvatarGroupHover extends StatefulWidget {
  const Case13AvatarGroupHover({super.key});

  @override
  State<Case13AvatarGroupHover> createState() => _Case13AvatarGroupHoverState();
}

class _Case13AvatarGroupHoverState extends State<Case13AvatarGroupHover> {
  /// 当前被悬停的下标，null = 指针已离开整排
  int? _active;

  @override
  Widget build(BuildContext context) {
    final count = _initials.length + 1;
    final groupW = (count - 1) * _step + _size;
    return LabStage(
      child: Stack(
        children: [
          Center(
            child: MouseRegion(
              // 复位挂在整排上：从一颗滑到下一颗不该先归零
              onExit: (_) => setState(() => _active = null),
              child: SizedBox(
                width: groupW,
                height: _size,
                child: Stack(
                  // 抬起的 4px 和描边都不该被这 32 高的框裁掉
                  clipBehavior: Clip.none,
                  children: [
                    for (var i = 0; i < count; i++)
                      Positioned(
                        left: i * _step,
                        top: 0,
                        child: _Avatar(
                          label: i < _initials.length ? _initials[i] : _moreLabel,
                          // 衰减公式：离被指的那颗每远一档，位移乘一次 falloff
                          progress: _active == null
                              ? 0
                              : math.pow(_falloff, (i - _active!).abs()).toDouble(),
                          lifting: _active == i,
                          curve: _active == null ? _easeOut : LabEase.smoothOut,
                          onEnter: () => setState(() => _active = i),
                        ),
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

/// 一颗头像：位移 + （仅被指的那颗）放大
class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.label,
    required this.progress,
    required this.lifting,
    required this.curve,
    required this.onEnter,
  });

  final String label;

  /// 已算好的位移比例：0 = 原位，1 = 抬满 `--avatar-lift`
  final double progress;

  /// 是否为本轮被悬停的那颗：只有它吃 scale
  final bool lifting;
  final Curve curve;
  final VoidCallback onEnter;

  @override
  Widget build(BuildContext context) {
    return LabTween(
      target: progress,
      duration: _dur,
      curve: curve,
      builder: (context, t) => Transform.translate(
        // translateY 在 scale 之前：写反了 scale 会把位移量一起放大
        offset: Offset(0, _lift * t),
        child: Transform.scale(
          scale: lifting ? 1 + (_scaleActive - 1) * t : 1,
          child: MouseRegion(
            // `+N` 那颗在参考稿里是 cursor: default——它一样会抬，只是不能点
            cursor: label == _moreLabel ? SystemMouseCursors.basic : SystemMouseCursors.click,
            onEnter: (_) => onEnter(),
            child: _AvatarFace(label: label),
          ),
        ),
      ),
    );
  }
}

/// 头像的脸：32 圆 + 一圈舞台色描边把重叠处切开
class _AvatarFace extends StatelessWidget {
  const _AvatarFace({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final isMore = label == _moreLabel;
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: isMore ? _moreBg : _avatarBg,
        shape: BoxShape.circle,
        border: Border.all(color: LabColor.stage, width: _borderWidth),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: isMore ? _initialStyle.copyWith(fontSize: 12, color: LabColor.text) : _initialStyle,
      ),
    );
  }
}
