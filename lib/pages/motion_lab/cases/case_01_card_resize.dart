import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 1. Card resize — 宽高一起补间，骨架跟着宽度重新量
///
/// 参考稿只给 width/height 挂了一条 transition（300ms 顺出），
/// 里面的骨架写的是 `calc((100% - 28px) * 0.526)` 这种相对宽度的长度，
/// 所以长短行是**被动**跟着卡片一起收的，没有自己的补间。
/// 这里把进度只留一份、宽和高都由它算，骨架宽度也从当帧的宽推出来——
/// 两条补间各跑各的话，中途会出现"框到位了、骨架还没到位"的错位。
const _dur = Duration(milliseconds: 300); // `--p4-dur`，曲线 `--p4-ease: var(--ease-smooth-out)`

/// `.p4-card` 原尺寸 / `.p4-card.is-small` 目标尺寸
const _startW = 220.0;
const _startH = 112.0;
const _smallW = 154.0;
const _smallH = 128.0;

/// 骨架左右各内缩 14（`.p4-card .sk { left: 14px; right: 14px }`）
const _skInsetX = 14.0;

/// `.stage-inner` 底部让给按钮的 56
const _footerLift = 56.0;

/// 一条骨架：top / height / 相对内宽的占比（省略 = 占满内宽）
class _Sk {
  const _Sk(this.top, this.height, [this.fraction]);

  final double top;
  final double height;
  final double? fraction;
}

/// `.p4-card .sk-1…6`
const _lines = <_Sk>[
  _Sk(14, 10, 0.526),
  _Sk(28, 7),
  _Sk(39, 7),
  _Sk(50, 7, 0.734),
  _Sk(78, 7),
  _Sk(89, 7),
];

double _mix(double a, double b, double t) => a + (b - a) * t;

class Case01CardResize extends StatefulWidget {
  const Case01CardResize({super.key});

  @override
  State<Case01CardResize> createState() => _Case01CardResizeState();
}

class _Case01CardResizeState extends State<Case01CardResize> {
  bool _small = false;

  void _toggle() => setState(() => _small = !_small);

  @override
  Widget build(BuildContext context) {
    return LabStage(
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              // 按钮占掉底部 56，所以卡片落在剩下空间的中心
              padding: const EdgeInsets.only(bottom: _footerLift),
              child: Center(
                child: LabTween(
                  target: _small ? 1 : 0,
                  duration: _dur,
                  curve: LabEase.smoothOut,
                  builder: (context, t) => _Card(
                    width: _mix(_startW, _smallW, t),
                    height: _mix(_startH, _smallH, t),
                  ),
                ),
              ),
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

/// `.p4-card`：12 圆角 + 浮层投影，内容全是被动的骨架
class _Card extends StatelessWidget {
  const _Card({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    // 骨架可用宽度 = 卡宽 - 左右内缩，短行再按占比切
    final inner = width - _skInsetX * 2;
    return Container(
      width: width,
      height: height,
      decoration: const BoxDecoration(
        color: LabColor.card,
        borderRadius: BorderRadius.all(Radius.circular(12)),
        boxShadow: LabShadow.material,
      ),
      child: Stack(
        children: [
          for (final line in _lines)
            Positioned(
              left: _skInsetX,
              top: line.top,
              child: Container(
                width: line.fraction == null ? inner : inner * line.fraction!,
                height: line.height,
                decoration: const BoxDecoration(
                  color: LabColor.skeleton,
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
