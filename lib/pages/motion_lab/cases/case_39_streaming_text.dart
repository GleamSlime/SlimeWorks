import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 39. Streaming text — 词一个接一个从模糊里定下来
///
/// 段落静止时是全可见的，点一次按钮就是把所有词抹掉重来一遍：每隔 60ms 放行下一个词，
/// 每个词自己走 350ms 顺出，走的是 opacity 0→1 加 1px 模糊→0 这一组属性——
/// 两个属性同时到 0 才算落定，停在半模糊就不是转场而是没加载完。
/// 一条补间 + `i * gap` 的相位差推出每个词的进度，几十个词就是几十个 i，
/// 不逐词开 controller；重绘只圈在 Wrap 这一小块。
/// 已经定下来的词返回裸 Text，还没轮到的词只占一个等宽等高的空位：
/// 这两种状态都不该挂着模糊层，43 格同屏时一层 blur 就是一层离屏。
class Case39StreamingText extends StatefulWidget {
  const Case39StreamingText({super.key});

  @override
  State<Case39StreamingText> createState() => _Case39StreamingTextState();
}

/// `--stream-*`：词间隔 60ms、每个词 350ms、模糊 1px
const _gapMs = 60;
const _fadeMs = 350;
const _blurSigma = 1.0;

/// 参考稿的 `.p30-block`：224 宽、13px / line-height 1.4
const _blockW = 224.0;
const _ink = Color(0xFF2D2D2D);
final _style = LabText.body.copyWith(height: 1.4, color: _ink);

const _text =
    'Animating mask-position never composites — it repaints the element. And the '
    'element being repainted sits inside a displacement chain, so the whole filter '
    're-executes on the CPU each frame. That compounds: it isn’t one cost, it’s the '
    'repaint feeding the filter.';

final _words = _split();
final _streamMs = _gapMs * (_words.length - 1) + _fadeMs;

/// 一个词：文本 + 它自己量出来的盒子，占位时用的是同一套数
class _Word {
  const _Word(this.text, this.width, this.height);

  final String text;
  final double width;
  final double height;
}

List<_Word> _split() {
  final out = <_Word>[];
  for (final w in _text.split(' ')) {
    final tp = TextPainter(
      text: TextSpan(text: w, style: _style),
      textDirection: TextDirection.ltr,
    )..layout();
    out.add(_Word(w, tp.width, tp.height));
    tp.dispose();
  }
  return out;
}

/// 词间那个空格按同一套字体量（拿 'n n' 减 'nn'，单量一个空格会被折行规则吃掉），
/// Wrap 的档距就是它——写死一个数会在行尾露馅
final double _spaceW = _measureSpace();

double _measureSpace() {
  double width(String s) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: _style),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = tp.width;
    tp.dispose();
    return w;
  }

  return width('n n') - width('nn');
}

class _Case39StreamingTextState extends State<Case39StreamingText> with SingleTickerProviderStateMixin {
  /// value 停在 1 = 全部已定，这条补间只管"重放一次"
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: _streamMs),
    value: 1,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _toggle() => _c.forward(from: 0);

  @override
  Widget build(BuildContext context) {
    return LabStage(
      child: Stack(
        children: [
          // 参考稿的 stage-inner 底部让出 56 给按钮，段落在剩下的空间里居中
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: 56,
            child: Center(
              child: ListenableBuilder(
                listenable: _c,
                builder: (context, _) {
                  final t = _c.value * _streamMs;
                  return SizedBox(
                    width: _blockW,
                    child: Wrap(
                      spacing: _spaceW,
                      children: [for (var i = 0; i < _words.length; i++) _word(i, t)],
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

  Widget _word(int i, double t) {
    final w = _words[i];
    final p = LabEase.smoothOut.transform(((t - i * _gapMs) / _fadeMs).clamp(0.0, 1.0));
    if (p >= 1) return Text(w.text, style: _style);
    if (p <= 0) return SizedBox(width: w.width, height: w.height);
    return Opacity(
      opacity: p,
      child: LabBlur(sigma: _blurSigma * (1 - p), child: Text(w.text, style: _style)),
    );
  }
}
