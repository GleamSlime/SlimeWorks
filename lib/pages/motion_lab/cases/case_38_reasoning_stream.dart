import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 38. Reasoning stream — 推理稿每停一下往上走两行
///
/// 舞台里那张卡是固定高度的窗口，稿子本体比它高得多：每停 840ms 就把稿子往上推
/// 两行（36.4px），推的过程走 500ms 顺出，推完接着推下一档。
/// 稿子被复制一份接在下面，位移满一份的高度就整体回绕 —— 两份内容一模一样，
/// 所以回绕那一帧看不出接缝，循环可以一直跑。
/// 上下各 28px 的渐隐是遮罩（dstIn）而不是压在字上的渐变，卡片底色换成什么都不影响。
/// 步数取整到能整除一份高度，单步因此和 36.4px 差不到 1px；
/// 不取整的话循环收尾会剩个零头，接缝就露出来了。
class Case38ReasoningStream extends StatefulWidget {
  const Case38ReasoningStream({super.key});

  @override
  State<Case38ReasoningStream> createState() => _Case38ReasoningStreamState();
}

/// 参考稿这一格的量：卡 256×144 圆角 12，内缩 16，稿子从 14px 起排
const _cardW = 256.0;
const _cardH = 144.0;
const _radius = 12.0;
const _padX = 16.0;
const _scrollTop = 14.0;
const _fade = 28.0;

/// `--reason-*`：停 840ms、走 500ms、一次两行；曲线就是全站那根顺出
const _holdMs = 840;
const _stepMs = 500;
const _roundMs = _holdMs + _stepMs;
const _linesPerStep = 2;

const _textW = _cardW - _padX * 2;
const _lineH = 18.2; // 13px × line-height 1.4
const _paraGap = 18.2; // 段底间距

const _ink = Color(0xFF2D2D2D);
final _textStyle = LabText.body.copyWith(height: 1.4, color: _ink);

const _paras = <String>[
  'Two things could explain the lag: the blur is re-running every frame, or the mask is forcing a repaint. Worth separating them before picking a fix.',
  'Animating mask-position never composites — it repaints the element. And the element being repainted sits inside a displacement chain, so the whole filter re-executes on the CPU each frame. That compounds: it isn’t one cost, it’s the repaint feeding the filter.',
  'So the fix isn’t tuning the blur radius. The animated property has to leave the paint path entirely. If the field is painted statically and covered by a same-coloured curtain, translating the curtain is visually identical to masking — and transform composites.',
  'One trade-off: the waves travel with the band instead of rippling through noise fixed in space. In motion, near-indistinguishable.',
];

/// 一份稿子的高度：用和渲染同一套量测出来，回绕才对得上接缝
final double _copyH = _measureCopy();
final int _steps = (_copyH / (_lineH * _linesPerStep)).round().clamp(1, 99).toInt();
final double _stepPx = _copyH / _steps;

double _measureCopy() {
  var h = 0.0;
  for (final p in _paras) {
    final tp = TextPainter(
      text: TextSpan(text: p, style: _textStyle),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: _textW);
    h += tp.height + _paraGap;
    tp.dispose();
  }
  return h;
}

class _Case38ReasoningStreamState extends State<Case38ReasoningStream> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: _roundMs * _steps),
  );

  bool _playing = true;

  @override
  void initState() {
    super.initState();
    _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _playing = !_playing);
    if (_playing) {
      _c.repeat();
      return;
    }
    // 停在半途等于停在两行字中间，所以先把这一档走完
    final t = _c.value * _roundMs * _steps;
    final end = (t / _roundMs).ceilToDouble() * _roundMs;
    _c.animateTo(
      end / (_roundMs * _steps),
      duration: Duration(milliseconds: (end - t).round()),
      curve: Curves.linear,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LabStage(
      child: Stack(
        children: [
          // 参考稿的 stage-inner 底部让出 56 给按钮，卡片在剩下的空间里居中
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: 56,
            child: Center(
              child: ListenableBuilder(
                listenable: _c,
                builder: (context, _) {
                  final t = _c.value * _roundMs * _steps;
                  final k = (t / _roundMs).floorToDouble().clamp(0.0, (_steps - 1).toDouble());
                  final local = t - k * _roundMs;
                  final p = LabEase.smoothOut.transform(((local - _holdMs) / _stepMs).clamp(0.0, 1.0));
                  return _Card(offset: ((k + p) * _stepPx) % _copyH);
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
}

/// 卡片：裁掉溢出，视口里的稿子整体往上走，上下用遮罩渐隐
class _Card extends StatelessWidget {
  const _Card({required this.offset});

  final double offset;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _cardW,
      height: _cardH,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: LabColor.card,
          borderRadius: BorderRadius.all(Radius.circular(_radius)),
          boxShadow: [BoxShadow(color: LabColor.border, spreadRadius: 1)],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(_radius)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: _padX),
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) {
                final f = _fade / rect.height;
                return LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: const [Color(0x00000000), Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
                  // 上下各 28px 渐隐，中间是实心
                  stops: [0, f, 1 - f, 1],
                ).createShader(rect);
              },
              child: Transform.translate(
                offset: Offset(0, _scrollTop - offset),
                // 稿子比视口高得多，这里故意不受视口高度约束
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  maxHeight: double.infinity,
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Transcript(),
                      // 克隆一份：位移满一份高度就回绕，接缝看不出来
                      _Transcript(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 一份完整稿子（含段底间距），和测量用的量一一对应
class _Transcript extends StatelessWidget {
  const _Transcript();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _textW,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final p in _paras) ...[
            Text(p, style: _textStyle),
            const SizedBox(height: _paraGap),
          ],
        ],
      ),
    );
  }
}
