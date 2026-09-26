import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 37. Thinking states — 状态行先被扫光刷过，再整行换成下一条
///
/// 这里是两条互不相干的时间线：扫光是常驻的 2000ms 循环（渐变带按 400% 宽从字
/// 左边推到右边，只作用在字形上），换行只在每轮末尾那 200ms 里发生——出场 150ms
/// 往上飘 8px 并糊 2px，入场延后 50ms 再从下方 8px 顶回来。
/// 所以用一条 3×2200ms 的主循环把"当前第几条 + 换行进度"一次算清（一条补间管三个
/// 属性，不分家），扫光另开一条循环；两条都圈在 ListenableBuilder 里，
/// 43 格同屏时只有这一行字在重绘。
/// 看不见的那条文案直接不建，免得每格白挂一层 ShaderMask。
/// 换行 2200ms 一轮、扫光 2000ms 一轮，两条不同相，光带每轮停在字上不同的位置——
/// 参考稿那两条 CSS 动画本来就是各走各的。
class Case37ThinkingStates extends StatefulWidget {
  const Case37ThinkingStates({super.key});

  @override
  State<Case37ThinkingStates> createState() => _Case37ThinkingStatesState();
}

/// `--p28-*`：一条状态停 2000ms，换行本身 150ms，入场比出场晚 50ms
const _holdMs = 2000;
const _swapMs = 150;
const _gapMs = 50;
const _roundMs = _holdMs + _gapMs + _swapMs;
const _distance = 8.0;
const _blurSigma = 2.0;
const _shimmerMs = 2000;

/// `--think-base` / `--think-highlight`：浅底舞台上亮档取正文黑
const _base = Color(0xFF7C7C7C);
const _highlight = LabColor.text;

/// 13 号中衬、18 行高，就是参考稿 sizer/text 那两档
final _lineStyle = LabText.title.copyWith(color: _base);
const _lineH = 18.0;

/// 三条走完一轮，最后一条取 sizer 那句
const _states = <String>['Thinking…', 'Reading the diff…', 'Setting up a workplace'];
const _loopMs = _roundMs * 3;

/// 隐藏 sizer 报的就是最宽那句的宽度：换行时盒子不变，文字始终在原处居中
final double _boxW = _measureBox();

double _measureBox() {
  var w = 0.0;
  for (final s in _states) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: _lineStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    if (tp.width > w) w = tp.width;
    tp.dispose();
  }
  return w;
}

class _Case37ThinkingStatesState extends State<Case37ThinkingStates> with TickerProviderStateMixin {
  late final AnimationController _round = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _loopMs),
  )..repeat();
  late final AnimationController _shine = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _shimmerMs),
  )..repeat();

  bool _playing = true;

  @override
  void dispose() {
    _round.dispose();
    _shine.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _playing = !_playing);
    if (_playing) {
      _round.repeat();
      _shine.repeat();
      return;
    }
    _shine.stop();
    // 停在半换行的那一帧会挂出两条半透明的字，所以先把这一轮走完
    final t = _round.value * _loopMs;
    final end = (t / _roundMs).ceilToDouble() * _roundMs;
    _round.animateTo(
      end / _loopMs,
      duration: Duration(milliseconds: (end - t).round()),
      curve: Curves.linear,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LabStage(
      child: Stack(
        children: [
          // 参考稿的 stage-inner 底部让出 56 给按钮，文案在剩下的空间里居中
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: 56,
            child: Center(
              child: ListenableBuilder(
                listenable: Listenable.merge([_round, _shine]),
                builder: (context, _) {
                  final t = _round.value * _loopMs;
                  // 回绕处正好是"上一条已经完全退场、下一条已经完全进场"
                  final k = (t / _roundMs).floor().clamp(0, _states.length - 1).toInt();
                  final local = t - k * _roundMs;
                  final out = _ease((local - _holdMs) / _swapMs);
                  final enter = _ease((local - _holdMs - _gapMs) / _swapMs);
                  final shine = _shine.value;
                  return SizedBox(
                    width: _boxW,
                    height: _lineH,
                    child: Stack(
                      children: [
                        if (out < 1) _line(_states[k], 1 - out, -1, shine),
                        if (enter > 0) _line(_states[(k + 1) % _states.length], enter, 1, shine),
                      ],
                    ),
                  );
                },
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

  double _ease(double x) => LabEase.inOut.transform(x.clamp(0.0, 1.0));

  /// 一行状态：正文色打底，亮档副本只让渐变带扫到（对应 background-clip: text）
  Widget _line(String text, double v, double sign, double shine) {
    return Transform.translate(
      offset: Offset(0, sign * _distance * (1 - v)),
      child: LabBlur(
        sigma: _blurSigma * (1 - v),
        child: Opacity(
          opacity: v,
          child: SizedBox(
            width: _boxW,
            height: _lineH,
            child: Stack(
              children: [
                Positioned.fill(child: Text(text, style: _lineStyle, textAlign: TextAlign.center)),
                Positioned.fill(
                  child: ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (rect) {
                      // background-size: 400% 100%，位置从 100% 推到 0%
                      final span = rect.width * 4;
                      final left = rect.width * (3 * shine - 3);
                      return const LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Color(0x00000000),
                          Color(0x00000000),
                          _highlight,
                          Color(0x00000000),
                          Color(0x00000000),
                        ],
                        stops: [0, .4, .5, .6, 1],
                      ).createShader(Rect.fromLTWH(left, 0, span, rect.height));
                    },
                    child: Text(text, style: _lineStyle, textAlign: TextAlign.center),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
