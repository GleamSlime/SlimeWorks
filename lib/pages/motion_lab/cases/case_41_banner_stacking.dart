import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 41. Banner stacking — 吐司式堆叠，最多三层
///
/// 参考稿每条横幅只有一个"深度"目标：新来的从下方 80px 带着 0.97 缩放
/// 和 2px 模糊升起入场（350ms 顺出），老的一层层往后退——每退一层
/// 上移 12px（peek）、缩 0.06、按 0.4 的步长变暗；被挤出第三层的
/// 用另一只 250ms 的钟往深处淡没。悬停在堆叠上时全部摊开：
/// 老横幅按"自身高 + 8px 间隙"整层上移、回到全亮全实。
class Case41BannerStacking extends StatefulWidget {
  const Case41BannerStacking({super.key});

  @override
  State<Case41BannerStacking> createState() => _Case41BannerStackingState();
}

/// 一条横幅的堆叠状态：depth -1 = 还没开始入场，>=3 或被挤走 = 退场中
class _BannerItem {
  _BannerItem({required this.seq, required this.depth});

  final int seq;
  int depth;
  bool leaving = false;

  /// 堆叠的远近次序：越深越先画（压在下面），退场的最底
  int get z => leaving ? 0 : 3 - depth;
}

class _Case41BannerStackingState extends State<Case41BannerStacking> {
  /// `--stack-open / --stack-close`
  static const _openDur = Duration(milliseconds: 350);
  static const _closeDur = Duration(milliseconds: 250);

  static const _bannerW = 261.0;
  static const _bannerH = 46.0;

  final List<_BannerItem> _items = [];
  int _seq = 0;
  bool _spread = false;

  void _add() {
    setState(() {
      for (final b in _items) {
        if (b.leaving) continue;
        b.depth += 1;
        // 第四层没有位置：被挤出 2 深的退到幕后
        if (b.depth > 2) {
          b.leaving = true;
          Future.delayed(_closeDur, () {
            if (mounted) setState(() => _items.remove(b));
          });
        }
      }
      _items.add(_BannerItem(seq: _seq++, depth: -1));
    });
    // 新横幅先以入场位渲染一帧，下一帧才给目标——和参考稿
    // "先挂 .is-enter 再同帧摘掉"是同一件事，保证入场真的补间起来
    final newcomer = _items.last;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => newcomer.depth = 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ordered = [..._items]..sort((a, b) => a.z != b.z ? a.z - b.z : a.seq - b.seq);

    return LabStage(
      child: Stack(
        children: [
          Positioned(
            left: (LabSize.stageW - _bannerW) / 2,
            // `.p34-stage-inner` 底衬 78：堆叠底缘离舞台 78px
            bottom: 78,
            child: MouseRegion(
              // 命中区按摊开后的整列来算：缝隙不属于任何一条横幅
              child: SizedBox(
                width: _bannerW,
                height: _bannerH + (_bannerH + 8) * 2,
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  clipBehavior: Clip.none,
                  children: [
                    for (final b in ordered)
                      _StackedBanner(
                        key: ValueKey(b.seq),
                        item: b,
                        spread: _spread,
                      ),
                  ],
                ),
              ),
              onEnter: (_) => setState(() => _spread = true),
              onExit: (_) => setState(() => _spread = false),
            ),
          ),
          LabStageFooter(
            children: [LabAnimateButton(label: 'Animate', onTap: _add)],
          ),
        ],
      ),
    );
  }
}

/// 单条横幅：位移走 bottom，缩放/透明度/模糊各挂一条独立补间，
/// 全部共用同一只钟（入场与层间 350ms，退场 250ms）
class _StackedBanner extends StatelessWidget {
  const _StackedBanner({
    super.key,
    required this.item,
    required this.spread,
  });

  final _BannerItem item;
  final bool spread;

  bool get _entering => item.depth < 0;

  /// translateY 全部翻成 bottom 偏移（translateY(-12) ≡ 上移 12）
  double get _bottom {
    if (item.leaving) return 36; // --stack-peek * -3
    switch (item.depth) {
      case -1:
        return -80; // --stack-rise
      case 0:
        return 0;
      case 1:
        return spread ? 54 : 12; // 摊开 = (46 + 8)，否则 = peek
      default:
        return spread ? 108 : 24;
    }
  }

  double get _scale {
    if (item.leaving) return 1 - 0.06 * 3; // --stack-depth-scale * 3
    if (item.depth <= 0) return _entering ? 0.97 : 1;
    return spread ? 1 : 1 - 0.06 * item.depth;
  }

  double get _opacity {
    if (item.leaving || _entering) return 0;
    if (item.depth == 0 || spread) return 1;
    // 深度 1 收 0.4、深度 2 只按 1.6 步长收（参考稿原样）
    return item.depth == 1 ? 1 - 0.4 : 1 - 0.4 * 1.6;
  }

  double get _blur => item.leaving || _entering ? 2 : 0; // --stack-blur

  Duration get _dur => item.leaving ? _Case41BannerStackingState._closeDur : _Case41BannerStackingState._openDur;

  /// 入场时锚点在中心（像吐司），往后退的深度锚点换到底边；
  /// 参考稿特意在恒等状态处换锚点，这样互换不产生视觉跳变
  Alignment get _origin =>
      (item.leaving || item.depth >= 1) ? Alignment.bottomCenter : Alignment.center;

  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned(
      duration: _dur,
      curve: LabEase.smoothOut,
      left: 0,
      bottom: _bottom,
      width: 261,
      height: 46,
      child: _ValueTween(
        duration: _dur,
        value: _scale,
        builder: (context, scale, child) => Transform.scale(
          scale: scale,
          alignment: _origin,
          child: child,
        ),
        child: _ValueTween(
          duration: _dur,
          value: _opacity.clamp(0.0, 1.0),
          builder: (context, opacity, child) => Opacity(
            opacity: opacity,
            child: child,
          ),
          child: _ValueTween(
            duration: _dur,
            value: _blur,
            builder: (context, blur, child) => LabBlur(sigma: blur, child: child!),
            child: const _BannerSurface(),
          ),
        ),
      ),
    );
  }
}

/// 值到值的补间。
///
/// 不能用 TweenAnimationBuilder：它只在 begin != end 时才起钟，而横幅首帧
/// 两个值都是 0，等下一帧把目标换成 1，钟已经不会再转了。
class _ValueTween extends StatefulWidget {
  const _ValueTween({
    required this.value,
    required this.duration,
    required this.builder,
    this.child,
  });

  final double value;
  final Duration duration;
  final Widget? child;
  final Widget Function(BuildContext, double, Widget?) builder;

  @override
  State<_ValueTween> createState() => _ValueTweenState();
}

class _ValueTweenState extends State<_ValueTween>
    with SingleTickerProviderStateMixin {
  late double _from;
  late double _current;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1.0, // 首帧直接落在目标上，入场那一帧由外层下一帧改目标来驱动
  );

  @override
  void initState() {
    super.initState();
    _from = widget.value;
    _current = widget.value;
    _c.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(_ValueTween old) {
    super.didUpdateWidget(old);
    if (old.duration != widget.duration) _c.duration = widget.duration;
    if (old.value == widget.value) return;
    _from = _current;
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _current = _from +
        (widget.value - _from) * LabEase.smoothOut.transform(_c.value);
    return widget.builder(context, _current, widget.child);
  }
}

/// 261×46 药丸横幅：与吐司同款骨架内容（头像圆 + 文案条）
class _BannerSurface extends StatelessWidget {
  const _BannerSurface();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: LabColor.card,
        borderRadius: BorderRadius.all(Radius.circular(52)),
        boxShadow: LabShadow.material,
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: LabColor.skeleton,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 10),
          const SizedBox(
            width: 178,
            height: 14,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: LabColor.skeleton,
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
