import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 18. Texts reveal — 两行文字错峰上浮进场，收的时候只原地淡出
///
/// 参考稿 `--p18-*`：进场 500ms 顺出、位移 12px、模糊 5px（舞台上的值比配方里的 3px 重）、
/// 第二行晚 40ms。收场刻意和进场解耦：`is-hiding` 下 Y/模糊直接钉在终值，
/// 只有透明度走 200ms ease 一起淡掉——淡出不是"倒放的进场"，不该再抖一次。
class Case18TextsReveal extends StatefulWidget {
  const Case18TextsReveal({super.key});

  @override
  State<Case18TextsReveal> createState() => _Case18TextsRevealState();
}

class _Case18TextsRevealState extends State<Case18TextsReveal> with TickerProviderStateMixin {
  static const _durMs = 500.0; // `--p18-dur` = var(--duration-very-slow)
  static const _staggerMs = 40.0; // `--p18-stagger` = var(--duration-stagger)
  static const _distance = 12.0; // `--p18-distance` = var(--distance-medium)
  static const _blur = 5.0; // `--p18-blur`
  static const _enterDur = Duration(milliseconds: 540); // 500 + 40，一条钟带两行错峰
  static const _exitDur = Duration(milliseconds: 200); // `.is-hiding` 的淡出
  static const _ease = LabEase.smoothOut; // `--p18-ease` = var(--ease-smooth-out)
  static const _cssEase = Cubic(0.25, 0.1, 0.25, 1); // 收场 transition 里裸写的 ease

  static const _primaryStyle = TextStyle(
    fontFamily: LabFont.family,
    fontFamilyFallback: LabFont.fallback,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 22 / 16, // `.p18-line--primary`
    color: LabColor.text,
  );
  static const _secondaryStyle = TextStyle(
    fontFamily: LabFont.family,
    fontFamilyFallback: LabFont.fallback,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 18 / 13, // `.p18-line--secondary`
    color: LabColor.textSubtle, // --muted #767676
  );

  late final AnimationController _enterC = AnimationController(vsync: this, duration: _enterDur);
  late final AnimationController _exitC = AnimationController(vsync: this, duration: _exitDur);

  bool _visible = false; // 对应 is-shown
  bool _hiding = false; // 对应 is-hiding
  List<double> _fadeFrom = const [1, 1]; // 淡出起点：进场半路被收时不是满显

  @override
  void dispose() {
    _enterC.dispose();
    _exitC.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_visible) {
      // 先记下每行当前透明度再收：淡出从"现在"开始，不是从满显开始
      _fadeFrom = [_opacity(0), _opacity(1)];
      setState(() {
        _hiding = true;
        _visible = false;
      });
      _exitC.animateTo(1, curve: _cssEase);
      return;
    }
    // 重播进场：淡出直接掐掉回基态，等价于移除 is-hiding 再挂 is-shown
    _exitC.stop();
    _exitC.value = 0;
    setState(() {
      _hiding = false;
      _visible = true;
    });
    _enterC.forward(from: 0);
  }

  double _lineP(int i) =>
      ((_enterC.value * _enterDur.inMilliseconds - i * _staggerMs) / _durMs).clamp(0.0, 1.0);

  double _opacity(int i) => _ease.transform(_lineP(i)).clamp(0.0, 1.0);

  /// 一行的三个量：进场走 Y+模糊+透明度，收场只走透明度
  Widget _line(int i, Widget text) {
    double opacity;
    double dy;
    double sigma;
    if (_hiding) {
      opacity = _fadeFrom[i] * (1 - _cssEase.transform(_exitC.value));
      dy = 0;
      sigma = 0; // transform/filter 0s 钉死在终值，不收着落回去
    } else {
      final e = _ease.transform(_lineP(i));
      opacity = e.clamp(0.0, 1.0);
      dy = _distance * (1 - e);
      sigma = (_blur * (1 - e)).clamp(0.0, _blur);
    }
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, dy),
        child: LabBlur(sigma: sigma, child: text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LabStage(
      child: Stack(
        children: [
          Center(
            child: ListenableBuilder(
              listenable: Listenable.merge([_enterC, _exitC]),
              builder: (context, _) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _line(0, const Text('Pull request opened', style: _primaryStyle)),
                    const SizedBox(height: 4), // `.p18-text` gap
                    _line(1, const Text('Review requested from 3 teammates', style: _secondaryStyle)),
                  ],
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
