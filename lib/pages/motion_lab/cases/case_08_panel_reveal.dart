import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 8. Panel reveal — 半张高的行程 + 同步收模糊
///
/// 参考稿给面板的是"位移/透明度/模糊"同一时长同一曲线（开 400ms、收 350ms），
/// 行程只有面板高的一半（`--p3-translate-y: calc(187px * 0.5)`），
/// 靠 blur 4 和淡出补齐"整块还在动"的错觉；到位后再整体下坐 28
/// （`--p3-open-lift`），让面板压在舞台底边上、读起来像从下面推进来。
/// 三者必须共用一条补间，分开跑的话模糊会比位移先结束，面板就像先糊后滑。
/// 这一格的控制键在参考稿里钉在舞台**顶部**（`.p3-stage-inner .btn-animate`），
/// 所以没走 `LabStageFooter` 那颗底部条。
const _openDur = Duration(milliseconds: 400); // `--p3-open-dur: var(--duration-slow)`
const _closeDur = Duration(milliseconds: 350); // `--p3-close-dur: var(--duration-medium)`

/// 面板 187 高、贴满舞台宽，静止位置离顶 54（`--p3-clip-pad-top`）
const _panelH = 187.0;
const _padTop = 54.0;

/// 到位后往下坐的 28（`--p3-open-lift: -28px`，公式里被抵消成 +28）
const _lift = 28.0;

/// 行程 = 面板高的一半（`--p3-translate-y`）
const _travel = _panelH * 0.5;

/// `--p3-blur: 4px`
const _blur = 4.0;

/// `--p3-shadow`：顶边那道 -1px 是面板与舞台之间的接缝
const _panelShadow = <BoxShadow>[
  BoxShadow(color: Color(0x0F000000), offset: Offset(0, -1)),
  BoxShadow(color: Color(0x0D000000), blurRadius: 6, offset: Offset(0, 2)),
  BoxShadow(color: Color(0x0F000000), blurRadius: 42, offset: Offset(0, 4)),
];

class Case08PanelReveal extends StatefulWidget {
  const Case08PanelReveal({super.key});

  @override
  State<Case08PanelReveal> createState() => _Case08PanelRevealState();
}

class _Case08PanelRevealState extends State<Case08PanelReveal> {
  /// 参考稿这一格初始就是展开态（DOM 上挂着 `is-open`）
  bool _open = true;

  void _toggle() => setState(() => _open = !_open);

  @override
  Widget build(BuildContext context) {
    return LabStage(
      child: Stack(
        children: [
          // `.p3-panel-clip` 就是整块舞台，越界由 LabStage 的圆角裁掉；
          // 面板静止位置由 margin-top 定，动的是 translateY
          Positioned(
            left: 0,
            right: 0,
            top: _padTop,
            child: LabTween(
              target: _open ? 1 : 0,
              duration: _open ? _openDur : _closeDur,
              curve: LabEase.smoothOut,
              // 收的时候退回"半张高以下"，同时淡到 0、糊到 4
              builder: (context, t) => Transform.translate(
                offset: Offset(0, _lift + _travel * (1 - t)),
                child: Opacity(
                  opacity: t.clamp(0.0, 1.0),
                  child: LabBlur(
                    sigma: _blur * (1 - t),
                    child: const _Panel(),
                  ),
                ),
              ),
            ),
          ),
          // 按钮的 z-index 比面板高，所以画在后面
          Positioned(
            left: 0,
            right: 0,
            top: 20,
            child: Center(
              child: LabAnimateButton(label: 'Toggle panel', onTap: _toggle),
            ),
          ),
        ],
      ),
    );
  }
}

/// `.p3-panel`：直角满宽面板，两行标题 + 2×2 磁贴
class _Panel extends StatelessWidget {
  const _Panel();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _panelH,
      decoration: const BoxDecoration(
        color: LabColor.card,
        boxShadow: _panelShadow,
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 28,
            child: Center(
              // `.lines` 是 flex column：131 那条指定了宽度，所以贴在左边
              child: SizedBox(
                width: 173,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [_SkLine(173, 10), SizedBox(height: 4), _SkLine(131, 10)],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 73,
            child: Center(
              child: Column(
                // `.tiles` 的换行间距 17、列间距 14
                children: const [
                  _TileRow(),
                  SizedBox(height: 17),
                  _TileRow(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TileRow extends StatelessWidget {
  const _TileRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [_SkLine(106, 46), SizedBox(width: 14), _SkLine(106, 46)],
    );
  }
}

/// `.skeleton`：4 圆角的灰块，磁贴也用它
class _SkLine extends StatelessWidget {
  const _SkLine(this.width, this.height);

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: const BoxDecoration(
        color: LabColor.skeleton,
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
    );
  }
}
