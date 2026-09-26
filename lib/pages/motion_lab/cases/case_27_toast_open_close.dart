import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 27. Toast open/close — 从下方升起，淡入 + 消模糊 + 微放大
///
/// 参考稿四个属性（位移 16px、缩放 0.97→1、模糊 2px→0、透明度）挂在同一条
/// 进度上，但开和收是两只钟：开 350ms 从容入场，收 250ms 干脆退场，
/// 曲线都是顺出。模糊必须一路落到 0，停在半模糊就不是转场而是没加载完。
class Case27ToastOpenClose extends StatefulWidget {
  const Case27ToastOpenClose({super.key});

  @override
  State<Case27ToastOpenClose> createState() => _Case27ToastOpenCloseState();
}

class _Case27ToastOpenCloseState extends State<Case27ToastOpenClose> {
  /// `--p22-open-dur / --p22-close-dur`
  static const _openDur = Duration(milliseconds: 350);
  static const _closeDur = Duration(milliseconds: 250);

  /// `--p22-distance / --p22-scale / --p22-blur`
  static const _distance = 16.0;
  static const _scaleFrom = 0.97;
  static const _blur = 2.0;

  bool _open = false;

  void _toggle() => setState(() => _open = !_open);

  @override
  Widget build(BuildContext context) {
    return LabStage(
      child: Stack(
        children: [
          Positioned(
            left: (LabSize.stageW - 261) / 2,
            // `bottom: 96px`，正好悬在底部按钮上方
            bottom: 96,
            child: LabTween(
              target: _open ? 1 : 0,
              duration: _open ? _openDur : _closeDur,
              curve: LabEase.smoothOut,
              builder: (context, t) {
                final rest = 1 - t;
                // CSS 的 translateY(16px) scale(0.97)：矩阵是 T·S，
                // 外层 translate 内层 scale 正好同序；锚点保持默认的中心
                return Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(0, _distance * rest),
                    child: Transform.scale(
                      scale: _scaleFrom + (1 - _scaleFrom) * t,
                      child: LabBlur(
                        sigma: _blur * rest,
                        child: const _Toast(),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          LabStageFooter(
            children: [LabAnimateButton(label: 'Animate', onTap: _toggle)],
          ),
        ],
      ),
    );
  }
}

/// 261×46 的药丸吐司：材料底 + 三层投影，内容是 20 圆头像 + 178 骨架条
class _Toast extends StatelessWidget {
  const _Toast();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 261,
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: LabColor.card,
        borderRadius: BorderRadius.all(Radius.circular(52)),
        boxShadow: LabShadow.material,
      ),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              color: LabColor.skeleton,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 178,
            height: 14,
            decoration: const BoxDecoration(
              color: LabColor.skeleton,
              borderRadius: BorderRadius.all(Radius.circular(4)),
            ),
          ),
        ],
      ),
    );
  }
}
