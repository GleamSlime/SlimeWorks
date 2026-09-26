import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 15. Error state shake — 报错时横向抖一下，边框和文案各自淡
///
/// 整格只有一条 0→1 的主时钟（[Case15ErrorStateShake] 里的 `_clock`）：
/// 抖 280ms → 停 3000ms → 280ms 淡回中性，因为参考稿的抖动本来就是
/// 一条 linear 动画 + 每段各自套一次 shake-ease，报错态的存活期又挂在
/// 同一个 hold 定时器上。拆成几条时间线的话，中途再点一次就没法干净地重播。
///
/// 抖动关键帧的累计停靠点是 28.57 / 57.14 / 78.57 / 100%（= 80、60、80、60ms
/// 除以总长 280ms），前三段各带自己的 `--p12-shake-ease`，最后一段沿用动画
/// 自身的 linear——所以收尾是匀速回位，不是再弹一下。
const _durA = 80.0; // --p12-shake-dur-a（= --duration-micro）
const _durB = 60.0; // --p12-shake-dur-b
const _shakeMs = _durA * 2 + _durB * 2; // 280
const _holdMs = 3000.0; // --revert-hold
const _revertMs = 280.0; // --p12-revert-dur
const _totalMs = _shakeMs + _holdMs + _revertMs;

const _distance = 6.0; // --shake-distance
const _overshoot = 4.0; // --shake-overshoot

/// 关键帧累计位置（占抖动总长的比）
const _stops = [0.0, 0.2857, 0.5714, 0.7857, 1.0];

/// 各停靠点的位移；末段是动画自带的 linear
const _offsets = [0.0, _distance, -_distance, _overshoot, 0.0];

/// CSS 的 `ease-out` 关键字（边框色/文案淡入淡出用的是它，不是全站那条顺出）
const _easeOut = Cubic(0, 0, 0.58, 1);

/// `.p12-input` 的默认边框
const _idleBorder = Color(0xFFDCDCDC);

/// 文案行盒：font-size 13 × line-height 1.4
const _msgH = 18.2;

/// `.p12-input-wrap` 宽
const _wrapW = 220.0;

class Case15ErrorStateShake extends StatefulWidget {
  const Case15ErrorStateShake({super.key});

  @override
  State<Case15ErrorStateShake> createState() => _Case15ErrorStateShakeState();
}

class _Case15ErrorStateShakeState extends State<Case15ErrorStateShake>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    // 一轮完整时间线：抖 280 + 停 3000 + 回位 280
    duration: const Duration(milliseconds: 3560),
  );

  @override
  void initState() {
    super.initState();
    _clock.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  /// 再点一次 = 把 class 摘掉再挂回去：整条时钟从头重播
  void _animate() => _clock.forward(from: 0);

  /// 抖动位移：按主时钟落在哪一段，段内再各自套一次曲线
  double _shakeX(double elapsedMs) {
    if (elapsedMs >= _shakeMs) return 0;
    final t = elapsedMs / _shakeMs;
    for (var i = 0; i < _stops.length - 1; i++) {
      if (t <= _stops[i + 1] || i == _stops.length - 2) {
        final span = _stops[i + 1] - _stops[i];
        final p = ((t - _stops[i]) / span).clamp(0.0, 1.0);
        // 末段（78.57% → 100%）没有自带 timing-function，走动画的 linear
        final eased = i == _stops.length - 2
            ? p
            : LabEase.smoothOut.transform(p);
        return _offsets[i] + (_offsets[i + 1] - _offsets[i]) * eased;
      }
    }
    return 0;
  }

  /// 报错强度 0→1→0：淡入和抖动同时起步，hold 期满后按同一时长淡回中性
  double _errorLevel(double elapsedMs) {
    if (elapsedMs < _shakeMs) {
      return _easeOut.transform((elapsedMs / _revertMs).clamp(0.0, 1.0));
    }
    if (elapsedMs < _shakeMs + _holdMs) return 1;
    final back = _easeOut.transform(
      ((elapsedMs - _shakeMs - _holdMs) / _revertMs).clamp(0.0, 1.0),
    );
    return 1 - back;
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = _clock.value * _totalMs;
    final error = _errorLevel(elapsed);
    return LabStage(
      child: Stack(
        children: [
          // 文案槽位常驻（CSS 的 visibility: hidden 照样占位），所以报错时输入框不跳位
          Center(
            child: SizedBox(
              width: 220,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Transform.translate(
                    offset: Offset(_shakeX(elapsed), 0),
                    child: _InputBox(level: error),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: _msgH,
                    child: Opacity(
                      opacity: error.clamp(0.0, 1.0),
                      child: Text(
                        'Please enter a valid email.',
                        style: LabText.body.copyWith(
                          height: 1.4,
                          color: LabColor.danger,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          LabStageFooter(
            children: [LabAnimateButton(label: 'Animate', onTap: _animate)],
          ),
        ],
      ),
    );
  }
}

/// `.p12-input` + 里面的输入框：220×36、圆角 8
///
/// 边框宽度恒定 1px（参考稿特意强调这点），换色只换 color，所以抖动和报错
/// 都不会把里面的文字推位。
class _InputBox extends StatelessWidget {
  const _InputBox({required this.level});

  /// 报错强度 0→1，用来插值边框色
  final double level;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _wrapW,
      height: 36,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: LabColor.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            width: 1,
            color: Color.lerp(_idleBorder, LabColor.danger, level)!,
          ),
        ),
        child: const Padding(
          padding: EdgeInsets.fromLTRB(12, 4, 4, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('John', style: LabText.body),
          ),
        ),
      ),
    );
  }
}
