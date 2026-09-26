import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 2. Number pop-in — 换数字时整组带模糊从下方弹入，末两位错峰跟进
///
/// 参考稿 `--p9-*`：时长 500ms（very-slow）、曲线 cubic-bezier(0.34, 1.45, 0.64, 1)、
/// 位移 8px、模糊 3.5px、错峰 70ms。五个字符里只有倒数第 1、2 位挂 data-stagger，
/// 所以前三位是齐刷刷进场、小数部分晚一拍——比逐位全错峰更强调"换了一个数"。
/// 旧数字不直接销毁，而是快照成 ghost 层沿同一条时间线**向上**弹出（pop-out 是
/// pop-in 的反方向），和新数字的弹入并行，这样替换读起来是一次交换而不是刷新。
class Case02NumberPopIn extends StatefulWidget {
  const Case02NumberPopIn({super.key});

  @override
  State<Case02NumberPopIn> createState() => _Case02NumberPopInState();
}

class _Case02NumberPopInState extends State<Case02NumberPopIn> with SingleTickerProviderStateMixin {
  // `--p9-dur: var(--duration-very-slow)` = 500ms
  static const _durMs = 500.0;
  static const _staggerMs = 70.0; // `--p9-stagger`
  static const _distance = 8.0; // `--p9-distance: var(--distance-base)`
  static const _blur = 3.5; // `--p9-blur`
  // 比 LabEase.pop 的过冲更狠一档（1.45 vs 1.36），单独定义
  static const _ease = Cubic(0.34, 1.45, 0.64, 1);

  /// 末两位各延迟一档，整条时间线 = 500 + 70×2
  static const _totalMs = _durMs + _staggerMs * 2;

  static final _digitStyle = LabText.number.copyWith(fontSize: 24, height: 1); // `.p9-number`

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 640), // 500 + 70×2
    value: 1.0, // 静止态：数字完整在场
  );

  // 固定种子：出图要能逐像素复现，取值的"随机"只是每档不同
  final math.Random _rng = math.Random(2);
  String _value = '65.78';
  String? _ghost; // 上一次点击被换下的数字，正在播 pop-out

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _ghost = _value;
      _value = _randomValue();
    });
    _c.forward(from: 0);
  }

  /// 两位整数 + "." + 两位小数，和参考稿的取值方式一致
  String _randomValue() {
    final intPart = 10 + _rng.nextInt(90);
    final decPart = _rng.nextInt(100).toString().padLeft(2, '0');
    return '$intPart.$decPart';
  }

  /// 只有倒数第 2、1 位挂 data-stagger=1/2，其余同拍进场
  double _delay(int i, int len) => i >= len - 2 ? (i - len + 3) * _staggerMs : 0;

  @override
  Widget build(BuildContext context) {
    return LabStage(
      child: Stack(
        children: [
          Center(
            child: ListenableBuilder(
              listenable: _c,
              builder: (context, _) {
                final t = _c.value;
                final ghost = _ghost;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // ghost 层 inset:0 叠在原位，所以先画、不占布局
                    if (ghost != null) _charRow(ghost, t, entering: false),
                    _charRow(_value, t, entering: true),
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

  Widget _charRow(String s, double t, {required bool entering}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < s.length; i++) _char(s[i], _local(t, _delay(i, s.length)), entering),
      ],
    );
  }

  Widget _char(String ch, double p, bool entering) {
    final e = _ease.transform(p);
    // 曲线过冲只该作用在位移上；透明度和模糊跟着 e 越过 1 会闪
    final k = e.clamp(0.0, 1.0);
    final dy = entering ? _distance * (1 - e) : -_distance * e; // dir-y=1，pop-out 反向
    return Opacity(
      opacity: entering ? k : 1 - k,
      child: LabBlur(
        sigma: entering ? (_blur * (1 - e)).clamp(0.0, _blur) : _blur * k,
        child: Transform.translate(
          offset: Offset(0, dy),
          child: Text(ch, style: _digitStyle),
        ),
      ),
    );
  }

  double _local(double t, double delayMs) =>
      ((t * _totalMs - delayMs) / _durMs).clamp(0.0, 1.0);
}
