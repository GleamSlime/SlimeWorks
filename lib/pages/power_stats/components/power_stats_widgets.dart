import 'package:flutter/material.dart';

import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/core/widgets/glass_surface.dart';
import 'package:slime_works/pages/power_stats/power_stats_theme.dart';

/// 1,234,567
String psGroupThousands(String digits) {
  final buf = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return buf.toString();
}

String _majorDefault(double v) {
  final s = psGroupThousands(v.abs().toStringAsFixed(0));
  return v < 0 ? '-$s' : s;
}

String _minorDefault(double v) {
  final s = v.abs().toStringAsFixed(2);
  final dot = s.indexOf('.');
  return dot < 0 ? '.00' : s.substring(dot);
}

/// 数值刷新时的补间滚动数字
///
/// 电表 30 秒才回一次真值，所以这里是**拿到新值才动**：从旧值缓动滚到新值，
/// 滚完静止，不造"数据一直在涨"的假象。闪烁同理，只在真的变大那一刻亮一下。
///
/// 自己拿 AnimationController 而不用 TweenAnimationBuilder：后者只在
/// `begin != end` 时起钟，首帧两值都是 0 的场合它永远不动。
class PsRollingNumber extends StatefulWidget {
  const PsRollingNumber({
    super.key,
    required this.value,
    required this.majorStyle,
    this.minorStyle,
    this.flashColor,
    this.duration = const Duration(milliseconds: 720),
    this.formatMajor,
    this.formatMinor,
    this.prefix = '',
    this.suffix = '',
    this.onRolled,
  });

  final double value;
  final TextStyle majorStyle;

  /// 小数位单独一档字号：整数与小数分两处给样式，没有 minorStyle 就不出小数
  final TextStyle? minorStyle;

  /// 滚动期间整数用的色，滚完回到 [majorStyle] 自己的色；null 则全程不变
  final Color? flashColor;

  final Duration duration;
  final String Function(double)? formatMajor;
  final String Function(double)? formatMinor;
  final String prefix;
  final String suffix;
  final VoidCallback? onRolled;

  @override
  State<PsRollingNumber> createState() => _PsRollingNumberState();
}

class _PsRollingNumberState extends State<PsRollingNumber>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);
  late final CurvedAnimation _curve =
      CurvedAnimation(parent: _c, curve: AppMotion.decelerate);
  Tween<double> _tween = Tween<double>(begin: 0, end: 0);
  late double _shown = widget.value;

  @override
  void initState() {
    super.initState();
    _c
      ..addListener(_onTick)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onRolled?.call();
      });
  }

  void _onTick() {
    if (!mounted) return;
    setState(() => _shown = _tween.evaluate(_curve));
  }

  @override
  void didUpdateWidget(PsRollingNumber old) {
    super.didUpdateWidget(old);
    if (widget.duration != old.duration) _c.duration = widget.duration;
    if (old.value == widget.value) {
      // 单位/格式换了但值没换：直接跟到新终值，免得停在半路
      _shown = widget.value;
      return;
    }
    _tween = Tween<double>(begin: _shown, end: widget.value);
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c
      ..removeListener(_onTick)
      ..dispose();
    _curve.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _c.isAnimating ? _shown : widget.value;
    final major = (widget.formatMajor ?? _majorDefault)(v);
    final minor = widget.minorStyle == null
        ? ''
        : (widget.formatMinor ?? _minorDefault)(v);
    final flash = widget.flashColor;
    final baseColor = widget.majorStyle.color ?? Colors.black;
    final color = (_c.isAnimating && flash != null)
        ? Color.lerp(flash, baseColor, Curves.easeOut.transform(_c.value))
        : baseColor;
    final minorStyle = widget.minorStyle;
    // 单位尾巴和 ¥ 前缀是同一档"配角"字号。调用点常常只给 majorStyle
    // （TOP5 那个合计就是），这时 suffix 不能落到 DefaultTextStyle 上——
    // 那会继承父级正文的颜色与字号，在同一行里明显比数字粗一圈。
    final suffixStyle = minorStyle ??
        widget.majorStyle.copyWith(
          color: (widget.majorStyle.color ?? Colors.black).withAlpha(160),
          fontSize: (widget.majorStyle.fontSize ?? 0) * 0.62,
          fontWeight: FontWeight.w600,
        );

    return Text.rich(
      TextSpan(
        children: [
          if (widget.prefix.isNotEmpty)
            TextSpan(
              text: widget.prefix,
              style: widget.majorStyle.copyWith(
                color: color?.withAlpha(190),
                fontSize: (widget.majorStyle.fontSize ?? 0) * 0.62,
              ),
            ),
          TextSpan(text: major, style: widget.majorStyle.copyWith(color: color)),
          if (minor.isNotEmpty) TextSpan(text: minor, style: minorStyle),
          if (widget.suffix.isNotEmpty)
            TextSpan(text: widget.suffix, style: suffixStyle),
        ],
      ),
      maxLines: 1,
      softWrap: false,
    );
  }
}

/// 本页的玻璃卡：公共 [GlassSurface] + 顶缘高光 + 事件驱动的外发光
///
/// 磨砂那层不另写一份实现，[GlassSurface] 已经是全站收敛后的那一份；
/// 这里只补它没有的两样：上沿一道比下沿亮的高光（去掉"塑料贴片"感），
/// 以及可动画的外发光——发光走阴影而不是加粗描边，粗描边会吃掉卡内可用宽度。
class PsGlassCard extends StatelessWidget {
  const PsGlassCard({
    super.key,
    required this.child,
    this.padding,
    this.radius,
    this.glow = 0.0,
    this.glowColor,
    this.tint,
    this.borderColor,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? radius;

  /// 0~1，事件驱动：抓取成功那一刻推到 1 再回落
  final double glow;
  final Color? glowColor;
  final Color? tint;
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = PowerStatsPalette.of(context);
    final m = AppTheme.metrics;
    final r = radius ?? m.radius16;
    final g = glow.clamp(0.0, 1.0);
    final gc = glowColor ?? p.accent;

    Widget card = GlassSurface(
      tint: tint ?? p.glassTint,
      borderColor:
          borderColor ?? (g > 0.01 ? Color.lerp(p.glassBorder, gc, g) : null),
      borderRadius: r,
      elevated: true,
      padding: padding ?? EdgeInsets.all(m.kSpace16),
      child: child,
    );

    card = Stack(
      children: [
        card,
        Positioned(
          left: r.topLeft.x * 0.6,
          right: r.topRight.x * 0.6,
          top: 0,
          child: IgnorePointer(
            child: Container(
              height: m.strokeUltraThin,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(r.topLeft.x),
                ),
                gradient: LinearGradient(
                  colors: [
                    p.glassHighlight.withAlpha(0),
                    p.glassHighlight,
                    p.glassHighlight.withAlpha(0),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );

    if (g > 0.01) {
      card = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: r,
          boxShadow: [
            BoxShadow(
              color: gc.withAlpha((110 * g).round().clamp(0, 255)),
              blurRadius: scaleW(30) * g,
              spreadRadius: scaleW(1) * g,
            ),
          ],
        ),
        child: card,
      );
    }

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: r, onTap: onTap, child: card),
    );
  }
}

/// 区块小标签（EQUITY / TRADE TAPE 那种带字距的）
class PsSectionLabel extends StatelessWidget {
  const PsSectionLabel(this.text, {super.key, this.color, this.trailing});

  final String text;
  final Color? color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = PowerStatsPalette.of(context);
    final m = AppTheme.metrics;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: m.fontSize11,
            fontWeight: FontWeight.w600,
            letterSpacing: scaleW(1.2),
            color: color ?? p.ink.withAlpha(140),
          ),
        ),
        if (trailing != null) ...[SizedBox(width: m.kSpace8), trailing!],
      ],
    );
  }
}

/// 胶囊徽标（LIVE 计时、空头标记、W/L 计数那一类）
class PsPill extends StatelessWidget {
  const PsPill({
    super.key,
    required this.label,
    this.color,
    this.filled = false,
    this.leading,
    this.dense = false,
  });

  final String label;
  final Color? color;

  /// filled=true 实心（选中档、峰值计数），否则水洗底
  final bool filled;
  final Widget? leading;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final p = PowerStatsPalette.of(context);
    final m = AppTheme.metrics;
    final c = color ?? p.accent;
    return AnimatedContainer(
      duration: AppMotion.fast,
      curve: AppMotion.standardCurve,
      padding: EdgeInsets.symmetric(
        horizontal: dense ? m.kSpace6 : m.kSpace10,
        vertical: dense ? m.kSpace2 : m.kSpace4,
      ),
      decoration: BoxDecoration(
        color: filled ? c : c.withAlpha(p.isDark ? 46 : 34),
        borderRadius: m.radiusPill,
        border: Border.all(
          color: filled ? c : c.withAlpha(p.isDark ? 90 : 70),
          width: m.strokeUltraThin,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, SizedBox(width: m.kSpace6)],
          Text(
            label,
            style: TextStyle(
              fontSize: dense ? m.fontSize10 : m.fontSize11,
              fontWeight: FontWeight.w700,
              color: filled ? Colors.white : c,
              fontFeatures: const [FontFeature.tabularFigures()],
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// 渐变填充进度条：值变了才推进，推完静止
class PsGradientBar extends StatelessWidget {
  const PsGradientBar({
    super.key,
    required this.value,
    required this.gradient,
    this.track,
    this.height,
    this.duration = AppMotion.slow,
  });

  /// 0~1
  final double value;
  final Gradient gradient;
  final Color? track;
  final double? height;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final p = PowerStatsPalette.of(context);
    final h = height ?? scaleW(6);
    return SizedBox(
      height: h,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: duration,
        curve: AppMotion.decelerate,
        builder: (context, t, _) => Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: track ?? p.trackRest,
                borderRadius: BorderRadius.circular(h / 2),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              // 宽度为 0 时不给 gradient：零宽盒上画渐变会撞 shader 断言
              child: FractionallySizedBox(
                widthFactor: t,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: t <= 0.001 ? null : gradient,
                    borderRadius: BorderRadius.circular(h / 2),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 按索引错峰的入场：柱状带与 TOP5 槽位共用
///
/// 时长比单卡入场慢半拍（[AppMotion.emphasis]），批量才看得出是一批而不是一屏。
class PsStagger extends StatefulWidget {
  const PsStagger({
    super.key,
    required this.index,
    required this.child,
    this.interval = AppMotion.stagger,
    this.duration = AppMotion.emphasis,
    this.rise = 14,
    this.fromScale = 0.9,
    this.trigger,
  });

  final int index;
  final Widget child;
  final Duration interval;
  final Duration duration;

  /// 上浮距离（逻辑像素，内部按 scaleW 折算）
  final double rise;
  final double fromScale;

  /// 变了就重播一次；null 表示只在挂载时播
  final Object? trigger;

  @override
  State<PsStagger> createState() => _PsStaggerState();
}

class _PsStaggerState extends State<PsStagger>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final CurvedAnimation _curve =
      CurvedAnimation(parent: _c, curve: AppMotion.decelerate);
  Object? _lastTrigger;

  @override
  void initState() {
    super.initState();
    _lastTrigger = widget.trigger;
    _schedule();
  }

  void _schedule() {
    final delay = widget.interval * widget.index;
    Future.delayed(delay, () {
      if (mounted) _c.forward(from: 0);
    });
  }

  @override
  void didUpdateWidget(PsStagger old) {
    super.didUpdateWidget(old);
    if (widget.duration != old.duration) _c.duration = widget.duration;
    if (widget.trigger != _lastTrigger) {
      _lastTrigger = widget.trigger;
      _schedule();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _curve.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) => Opacity(
        opacity: _curve.value,
        child: Transform.translate(
          offset: Offset(0, scaleW(widget.rise) * (1 - _curve.value)),
          child: Transform.scale(
            scale: widget.fromScale + (1 - widget.fromScale) * _curve.value,
            child: child,
          ),
        ),
      ),
      child: widget.child,
    );
  }
}
