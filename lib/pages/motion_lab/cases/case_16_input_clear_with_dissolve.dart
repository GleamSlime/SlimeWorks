import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 16. Input clear with dissolve — 清空时逐词消散
///
/// 这条动作是三条时间线叠在一起，各自有各自的时长，合成一条补间会互相盖掉：
/// 旧值走"退场"（400ms：下移 12、淡出、糊到 2px），假占位走"进场"
/// （400ms：从 -12 落回原位、0.9→1.0 提亮、2px→0 收糊），两条共用同一条顺出曲线；
/// 第三条是词底的微光，挂在整条 1000ms 时间线上，50ms 之后才起，
/// 在 15% 处冲到峰值 0.42 再退到 0——峰形起快落慢，静态关键帧表达不了，
/// 所以跟着同一条时间线按毫秒自己算包络。
/// 微光按词逐个画：每词四片错开的椭圆，宽度由该词的实测字宽推出来，
/// 这样文案变长变短，光斑仍然盖在字上。
class Case16InputClearWithDissolve extends StatefulWidget {
  const Case16InputClearWithDissolve({super.key});

  @override
  State<Case16InputClearWithDissolve> createState() => _Case16InputClearWithDissolveState();
}

/// 有值 / 正在清空 / 空态：三态只管按钮和清空叉的可见性，
/// 位移、透明度、模糊全部由时间线的毫秒数推出
enum _Phase { value, clearing, empty }

class _Case16InputClearWithDissolveState extends State<Case16InputClearWithDissolve>
    with SingleTickerProviderStateMixin {
  /// `--clear-dur` / `--clear-out-dur` / `--clear-in-dur`
  static const _totalMs = 1000.0;
  static const _outMs = 400.0;
  static const _inMs = 400.0;

  /// `--clear-out-fly` / `--clear-in-fly` / `--clear-blur`
  static const _fly = 12.0;
  static const _blur = 2.0;

  /// `--glow-delay` / `--glow-peak-at` / `--glow-opacity` / `--glow-spread`
  static const _glowDelayMs = 50.0;
  static const _glowPeakAt = 0.15;
  static const _glowOpacity = 0.42;
  static const _glowSpread = 1.5;

  /// `.p13-search`：256×36、圆角 48、`#eeeeee` 底 + 1px 内描边，
  /// 文字左 32（让开图标）右 40（让开清空叉）
  static const _fieldW = 256.0;
  static const _fieldH = 36.0;
  static const _fieldRadius = 48.0;
  static const _padLeft = 32.0;
  static const _padRight = 40.0;

  static const _fieldBg = Color(0xFFEEEEEE);
  static const _hairline = Color(0x08000000); // rgba(0,0,0,.032)
  static const _valueColor = Color(0xFF2F2F2F);

  /// rgba(123,123,123,.7)
  static const _placeholderColor = Color(0xB37B7B7B);

  /// rgba(15,15,15,.35) / `:hover` 时的 #2f2f2f
  static const _clearColor = Color(0x590F0F0F);

  static const _text = 'How do transitions work?';
  static const _placeholder = 'Search';

  static const _textStyle = TextStyle(
    fontFamily: LabFont.family,
    fontFamilyFallback: LabFont.fallback,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 18 / 13,
  );

  static const _searchIconPath =
      'M14 14L11.1 11.1M12.6667 7.33333C12.6667 10.2789 10.2789 12.6667 '
      '7.33333 12.6667C4.38781 12.6667 2 10.2789 2 7.33333C2 4.38781 4.38781 '
      '2 7.33333 2C10.2789 2 12.6667 4.38781 12.6667 7.33333Z';

  /// 参考稿这枚叉是实心圆底 + 镂空叉，一个 path 画完
  static const _clearIconPath =
      'M10 20C15.5228 20 20 15.5228 20 10C20 4.47715 15.5228 0 10 '
      '0C4.47715 0 0 4.47715 0 10C0 15.5228 4.47715 20 10 '
      '20ZM13.3701 6.62994C13.7253 6.98512 13.7253 7.56072 13.3701 '
      '7.91591L11.2856 10.0004L13.3701 12.0848C13.7253 12.44 13.7253 13.0156 '
      '13.3701 13.3708C13.0149 13.726 12.4393 13.726 12.0841 13.3708L9.99962 '
      '11.2864L7.91515 13.3708C7.55997 13.726 6.98437 13.726 6.62919 '
      '13.3708C6.27401 13.0156 6.27401 12.44 6.62919 12.0848L8.71366 '
      '10.0004L6.62919 7.91591C6.27401 7.56072 6.27401 6.98512 6.62919 '
      '6.62994C6.98437 6.27476 7.55997 6.27476 7.91515 6.62994L9.99962 '
      '8.71441L12.0841 6.62994C12.4393 6.27476 13.0149 6.27476 13.3701 6.62994Z';

  late final AnimationController _timeline = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );

  _Phase _phase = _Phase.value;
  bool _clearHovered = false;

  /// 光斑位置只取决于文案和字体，量一次就够，别跟着发帧重量
  late final List<_Streak> _streaks = _measureStreaks();

  @override
  void dispose() {
    _timeline.dispose();
    super.dispose();
  }

  void _clear() {
    if (_phase != _Phase.value) return;
    setState(() => _phase = _Phase.clearing);
    _timeline.forward(from: 0).then((_) {
      if (mounted) setState(() => _phase = _Phase.empty);
    });
  }

  /// 复位就是把值放回去：参考稿这里没有反向动画，直接归零重画
  void _reset() {
    _timeline.value = 0;
    setState(() => _phase = _Phase.value);
  }

  /// 逐词量出中心 x 和半宽，公式和参考稿量字宽那一段一致
  List<_Streak> _measureStreaks() {
    final words = _text.split(' ');
    final spaceW = _measure(' ');
    final out = <_Streak>[];
    var x = 0.0;
    for (var i = 0; i < words.length; i++) {
      final w = _measure(words[i]);
      out.add(_Streak(cx: _padLeft + x + w / 2, hw: math.max(w * 0.45, 8) * _glowSpread));
      x += w + (i == words.length - 1 ? 0 : spaceW);
    }
    return out;
  }

  double _measure(String s) {
    final p = TextPainter(
      text: TextSpan(text: s, style: _textStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final w = p.width;
    p.dispose();
    return w;
  }

  @override
  Widget build(BuildContext context) {
    return LabStage(
      child: Stack(
        children: [
          Center(child: _field()),
          // 参考稿：输入框有值/正在清空时这颗按钮既看不见也点不着，清空完才浮出来
          LabStageFooter(
            children: [
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                curve: Curves.ease,
                opacity: _phase == _Phase.empty ? 1 : 0,
                child: IgnorePointer(
                  ignoring: _phase != _Phase.empty,
                  child: LabAnimateButton(label: 'Reset text', onTap: _reset),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _field() {
    return SizedBox(
      width: _fieldW,
      height: _fieldH,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _fieldBg,
          borderRadius: BorderRadius.circular(_fieldRadius),
          border: Border.all(color: _hairline),
        ),
        // 文本层飘出药丸外要被裁掉，微光也得跟着圆角走
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_fieldRadius),
          child: Stack(
            children: [
              Positioned(
                left: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: LabIcon(
                    paths: const [_searchIconPath],
                    size: 14,
                    strokeWidth: 1.5,
                    color: LabColor.iconMuted,
                  ),
                ),
              ),
              _animatedText(),
              Positioned(
                right: 8,
                top: 0,
                bottom: 0,
                child: Center(child: _clearButton()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 文本 + 微光这一坨才跟着时间线重画，药丸底色和图标不动
  Widget _animatedText() {
    return ListenableBuilder(
      listenable: _timeline,
      builder: (context, _) {
        final elapsed = switch (_phase) {
          _Phase.value => 0.0,
          _Phase.clearing => _timeline.value * _totalMs,
          _Phase.empty => _totalMs,
        };
        final out = LabEase.smoothOut.transform((elapsed / _outMs).clamp(0.0, 1.0));
        final fall = LabEase.smoothOut.transform((elapsed / _inMs).clamp(0.0, 1.0));

        return Stack(
          children: [
            // 旧值：往下飘 12，同时淡掉并糊开
            Positioned.fill(
              child: Transform.translate(
                offset: Offset(0, out * _fly),
                child: Opacity(
                  opacity: _phase == _Phase.value ? 1.0 : (1 - out).clamp(0.0, 1.0),
                  child: LabBlur(sigma: out * _blur, child: _line(_text, _valueColor)),
                ),
              ),
            ),
            // 假占位：从 -12 落到原位，同时把模糊收干净
            Positioned.fill(
              child: Transform.translate(
                offset: Offset(0, -_fly + fall * _fly),
                child: Opacity(
                  opacity: _phase == _Phase.value ? 0.0 : (0.9 + fall * 0.1).clamp(0.0, 1.0),
                  child: LabBlur(sigma: _blur - fall * _blur, child: _line(_placeholder, _placeholderColor)),
                ),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                size: Size.infinite,
                painter: _GlowPainter(streaks: _streaks, opacity: _glowEnvelope(elapsed)),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 50ms 之后才起，15% 处到峰，剩下的时间退光
  double _glowEnvelope(double elapsed) {
    if (elapsed <= _glowDelayMs) return 0;
    final gp = ((elapsed - _glowDelayMs) / (_totalMs - _glowDelayMs)).clamp(0.0, 1.0);
    final shape = gp < _glowPeakAt ? gp / _glowPeakAt : (1 - gp) / (1 - _glowPeakAt);
    return shape * _glowOpacity;
  }

  Widget _line(String s, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: _padLeft, right: _padRight),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          s,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: _textStyle.copyWith(color: color),
        ),
      ),
    );
  }

  Widget _clearButton() {
    return IgnorePointer(
      // 看不见的时候也不该点得着（参考稿的 pointer-events 跟着 has-value 走）
      ignoring: _phase != _Phase.value,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _clearHovered = true),
        onExit: (_) => setState(() => _clearHovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _clear,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            curve: Curves.ease,
            opacity: _phase == _Phase.value ? 1 : 0,
            child: SizedBox(
              width: 20,
              height: 20,
              child: LabIcon(
                paths: const [_clearIconPath],
                size: 20,
                viewBox: 20,
                filled: true,
                color: _clearHovered ? _valueColor : _clearColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 一个词的光斑：中心 x + 由字宽推出来的半宽
@immutable
class _Streak {
  const _Streak({required this.cx, required this.hw});

  final double cx;
  final double hw;

  @override
  bool operator ==(Object other) =>
      other is _Streak && other.cx == cx && other.hw == hw;

  @override
  int get hashCode => Object.hash(cx, hw);
}

/// 词底的微光
///
/// 参考稿用 `mix-blend-mode: multiply` 压暗输入框，而"乘以黑"和"按 alpha 叠黑"
/// 在数学上是同一件事（结果都是 bg × (1-a)），所以这里不必真开混合模式。
/// 整层那道 0→0.42→0 的包络走 saveLayer 的组透明度：几片椭圆互相重叠时
/// 才不会越叠越黑，峰形也只由那一个数决定。
class _GlowPainter extends CustomPainter {
  const _GlowPainter({required this.streaks, required this.opacity});

  final List<_Streak> streaks;
  final double opacity;

  /// 每词四片：中心一片 + 三片横向错开，读起来才像被拖出来的一道
  static const _dxFactor = [0.0, 0.45, -0.4, 0.15];
  static const _rwFactor = [0.8, 0.55, 0.65, 0.9];
  static const _rh = [7.0, 8.0, 6.0, 5.0];
  static const _a = [0.22, 0.18, 0.16, 0.14];

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0.001) return;
    canvas.saveLayer(Offset.zero & size, Paint()..color = Color.fromRGBO(0, 0, 0, opacity));
    final paint = Paint();
    for (final s in streaks) {
      for (var i = 0; i < _dxFactor.length; i++) {
        final rw = math.max(s.hw * _rwFactor[i], 2.0);
        final rect = Rect.fromCenter(
          center: Offset(s.cx + s.hw * _dxFactor[i], size.height),
          width: rw * 2,
          height: _rh[i] * 2,
        );
        // 每片自己的 alpha 由内往外压到 0，包络留给上层的组透明度
        paint.shader = RadialGradient(
          colors: [Color.fromRGBO(0, 0, 0, _a[i]), const Color(0x00000000)],
        ).createShader(rect);
        canvas.drawRect(rect, paint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.opacity != opacity || old.streaks != streaks;
}
