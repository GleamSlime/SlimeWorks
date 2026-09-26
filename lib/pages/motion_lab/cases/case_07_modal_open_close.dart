import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 7. Modal open/close — 0.96 起幅的缩放 + 淡入淡出
///
/// 参考稿把开和收写成两条 transition：开 250ms、收 150ms，曲线同一个，
/// 两端都停在 0.96（`--p7-scale` / `--p7-scale-close` 是同一个值），
/// 所以退场不是入场的倒放而是"更快地缩回去"——合成一条来回播的话，
/// 关闭会拖成 250ms，浮层给人的"随手关掉"那下就没了。
/// 这里用同一个 tween 走 0↔1，只把时长按方向换掉。
const _openDur = Duration(milliseconds: 250); // `--p7-open-dur: var(--duration-fast)`
const _closeDur = Duration(milliseconds: 150); // `--p7-close-dur: var(--duration-quick)`

/// `--p7-scale: var(--scale-large)`，起幅和收尾共用
const _scale = 0.96;

/// 对话框本体 261×172
const _dlgW = 261.0;
const _dlgH = 172.0;

/// `.stage-inner` 底部让给按钮的 56
const _footerLift = 56.0;

/// 骨架块：left / top / width / height / 圆角
class _Block {
  const _Block(this.left, this.top, this.width, this.height, this.radius);

  final double left;
  final double top;
  final double width;
  final double height;
  final double radius;
}

/// `.p7-dropdown` 内部：标题条、关闭点、三行正文、两枚药丸
const _blocks = <_Block>[
  _Block(16, 29, 167, 14, 4), // .title
  _Block(237, 8, 16, 16, 43), // .close-dot
  _Block(16, 57, 227, 10, 4), // .body-1
  _Block(16, 73, 227, 10, 4), // .body-2
  _Block(16, 89, 141, 10, 4), // .body-3
  _Block(107, 135, 66, 21, 6), // .pill-1
  _Block(179, 135, 66, 21, 6), // .pill-2
];

class Case07ModalOpenClose extends StatefulWidget {
  const Case07ModalOpenClose({super.key});

  @override
  State<Case07ModalOpenClose> createState() => _Case07ModalOpenCloseState();
}

class _Case07ModalOpenCloseState extends State<Case07ModalOpenClose> {
  /// 参考稿这一格的初始状态就是打开的（DOM 上直接挂着 `is-open`）
  bool _open = true;

  void _toggle() => setState(() => _open = !_open);

  @override
  Widget build(BuildContext context) {
    return LabStage(
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.only(bottom: _footerLift),
              child: Center(
                child: LabTween(
                  target: _open ? 1 : 0,
                  duration: _open ? _openDur : _closeDur,
                  curve: LabEase.smoothOut,
                  builder: (context, t) => Opacity(
                    // transform-origin: center —— Transform.scale 的默认锚点就是它
                    opacity: t.clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: _scale + (1 - _scale) * t,
                      child: const _Dialog(),
                    ),
                  ),
                ),
              ),
            ),
          ),
          LabStageFooter(
            children: [LabAnimateButton(label: 'Toggle modal', onTap: _toggle)],
          ),
        ],
      ),
    );
  }
}

/// `.p7-dropdown`：12 圆角浮层 + 满版骨架
class _Dialog extends StatelessWidget {
  const _Dialog();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _dlgW,
      height: _dlgH,
      decoration: const BoxDecoration(
        color: LabColor.card,
        borderRadius: BorderRadius.all(Radius.circular(12)),
        boxShadow: LabShadow.material,
      ),
      child: Stack(
        children: [
          for (final b in _blocks)
            Positioned(
              left: b.left,
              top: b.top,
              child: Container(
                width: b.width,
                height: b.height,
                decoration: BoxDecoration(
                  color: LabColor.skeleton,
                  borderRadius: BorderRadius.circular(b.radius),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
