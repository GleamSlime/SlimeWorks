import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 4. Text states swap — 旧字收上去、换字、新字从下面回位
///
/// 一次点击被切成三段，中间那次"换字"是**瞬移**：
/// 收（150ms 渐入渐出）把旧字往上 4px、糊 4px、淡到 0；
/// 换完字必须不带过渡地跳到**下方** 4px，再走同样的 150ms 回到 0。
/// 要是把两段合成一条补间，新字会倒着从上方滑回来，读起来就是"同一行在抖"。
class Case04TextStatesSwap extends StatefulWidget {
  const Case04TextStatesSwap({super.key});

  @override
  State<Case04TextStatesSwap> createState() => _Case04TextStatesSwapState();
}

enum _Phase {
  /// 停在原位（opacity 1 / 无位移 / 无模糊）
  rest,

  /// 旧字往上收
  exit,

  /// 新字从下方回到位
  enter,
}

class _Case04TextStatesSwapState extends State<Case04TextStatesSwap>
    with SingleTickerProviderStateMixin {
  /// `--p6-dur: var(--duration-quick)`
  static const _dur = Duration(milliseconds: 150);

  /// `--p6-translate-y: var(--distance-micro)`
  static const _dy = 4.0;

  /// `--p6-blur`
  static const _blur = 4.0;

  /// `--p6-ease: var(--ease-in-out)`
  static const _ease = LabEase.inOut;

  static const _messages = [
    'Transaction processing...',
    'Transaction completed',
  ];

  /// `.p6-text`：15/500/18，不换行
  static const _style = TextStyle(
    fontFamily: LabFont.family,
    fontFamilyFallback: LabFont.fallback,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 18 / 15,
    color: LabColor.text,
  );

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _dur,
  );

  _Phase _phase = _Phase.rest;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // 用状态回调接力而不是 await forward()：中途被 dispose 时 future 会抛取消错
    _c.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      if (_phase == _Phase.exit) {
        setState(() {
          _index = (_index + 1) % _messages.length;
          _phase = _Phase.enter;
        });
        _c.forward(from: 0);
      } else if (_phase == _Phase.enter) {
        setState(() => _phase = _Phase.rest);
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _toggle() {
    // 参考稿用 busy 标志挡住连点：两段各 150ms，中途重播会看不清换了什么
    if (_phase != _Phase.rest) return;
    setState(() => _phase = _Phase.exit);
    _c.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return LabStage(
      child: Stack(
        children: [
          Center(
            // 进度只在这条 builder 里读：不包这一层，build 只在 setState 那一次
            // 跑到，读到的永远是起点的 0——整段动效看着像"没有"
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                // 收：从 0 走到满值；进：从满值退回 0；停：直接 0（原位）
                // 位移/模糊/透明度共用同一条 ease-in-out，所以在这里统一换算一次
                final p = switch (_phase) {
                  _Phase.exit => _ease.transform(_c.value),
                  _Phase.enter => 1 - _ease.transform(_c.value),
                  _Phase.rest => 0.0,
                };
                // 位移方向是这一段唯一的区别：收向上、进从下来
                final offset = Offset(0, _phase == _Phase.enter ? _dy * p : -_dy * p);
                return Transform.translate(
                  offset: offset,
                  child: Opacity(
                    opacity: (1 - p).clamp(0.0, 1.0),
                    child: LabBlur(
                      sigma: _blur * p,
                      child: Text(_messages[_index], maxLines: 1, style: _style),
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
