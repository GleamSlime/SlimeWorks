import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 17. Skeleton loader and reveal — 骨架屏脉冲后交叉淡入正文
///
/// 参考稿把两层压在同一个坐标系上（骨架 z 低、正文 z 高），换内容时**不动布局**：
/// 骨架淡出 + 糊开，正文淡入 + 收糊，两条走同一个 400ms 的 ease-in-out，
/// 所以读起来是一次动作而不是两次。
/// 脉冲只作用在骨架的几根条上（`opacity 1 → 0.5 → 1`），
/// 刻意不碰骨架层自己——那层的 opacity / blur 是留给换内容用的，
/// 挂上去就会互相覆盖。
/// 重播时反向是"瞬间归位"而不是倒放：所以这里直接给揭示进度赋 0，不走补间。
class Case17SkeletonLoaderAndReveal extends StatefulWidget {
  const Case17SkeletonLoaderAndReveal({super.key});

  @override
  State<Case17SkeletonLoaderAndReveal> createState() => _Case17SkeletonLoaderAndRevealState();
}

class _Case17SkeletonLoaderAndRevealState extends State<Case17SkeletonLoaderAndReveal>
    // 脉冲和揭示两条时间线各要一个 ticker
    with TickerProviderStateMixin {
  /// `--p14-pulse-dur` / `--pulse-count`：脉冲走满一轮（1000ms）就换内容
  static const _pulseDur = Duration(milliseconds: 1000);
  static const _pulseMin = 0.5;

  /// `--p14-reveal-dur` / `--p14-reveal-blur`，曲线取 `--p14-reveal-ease`
  static const _revealDur = Duration(milliseconds: 400);
  static const _revealBlur = 3.5;

  /// `.p14-card`：256×56、圆角 12，1px 描边 + 一层极淡投影
  static const _cardW = 256.0;
  static const _cardH = 56.0;
  static const _cardRadius = 12.0;

  /// 参考稿写的是 `padding: 12px 16px`，这里纵向那 12 交给居中来表达：
  /// 两行文字本身 34 高，比 56-24 的内容盒还高，照写会溢出，而参考稿本来就没裁到它
  static const _padX = 16.0;
  static const _avatar = 32.0;

  static const _skGap = 6.0; // 骨架层：头像与线条之间
  static const _skLinesGap = 6.0;
  static const _skLinesMarginLeft = 4.0;
  static const _skBarH = 12.0;
  static const _skBarRadius = 4.0;
  static const _skNameW = 100.0;
  static const _skEmailW = 131.0;
  static const _contentGap = 12.0;
  static const _textGap = 2.0;

  static const _cardShadow = <BoxShadow>[
    BoxShadow(color: Color(0x08000000), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: LabColor.border, blurRadius: 0, spreadRadius: 1),
  ];

  static const _name = 'Jane Cooper';
  static const _email = 'jane.cooper@example.com';

  static const _nameStyle = TextStyle(
    fontFamily: LabFont.family,
    fontFamilyFallback: LabFont.fallback,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 16 / 13,
    color: LabColor.text,
  );

  static const _emailStyle = TextStyle(
    fontFamily: LabFont.family,
    fontFamilyFallback: LabFont.fallback,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 16 / 12,
    color: LabColor.textSubtle,
  );

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: _pulseDur,
  );
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: _revealDur,
  );

  /// 脉冲是否还在跑：跑满一轮的那一刻才把内容揭示出来
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // 一轮脉冲 = 一次 completed，用它当"数据到了"的信号，省掉另行计时。
    // 注意不能用 repeat()：循环播放时状态一直是 forward，永远不发 completed，
    // 这条监听就永不触发，正文层停在 opacity 0（看着就是"动画完了却没字"）
    _pulse.addStatusListener(_onPulseCycle);
    // 挂载即处于脉冲态：_loading 初值为 true、揭示进度初值为 0，所以不必 setState
    _pulse.forward(from: 0);
  }

  @override
  void dispose() {
    _pulse.dispose();
    _reveal.dispose();
    super.dispose();
  }

  void _onPulseCycle(AnimationStatus status) {
    if (status != AnimationStatus.completed || !_loading) return;
    setState(() => _loading = false);
    _pulse.stop();
    _reveal.animateTo(1, curve: LabEase.inOut);
  }

  /// 重播：先瞬时回到骨架态（等价于那一帧把 transition 关掉），再脉冲
  void _start() {
    setState(() {
      _loading = true;
      _reveal.value = 0;
    });
    _pulse.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return LabStage(
      child: Stack(
        children: [
          Center(child: _card()),
          LabStageFooter(
            children: [LabAnimateButton(label: 'Animate', onTap: _start)],
          ),
        ],
      ),
    );
  }

  Widget _card() {
    // 描边和投影画在裁切之外：CSS 的外阴影不会被自己的 overflow 裁掉
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: LabColor.card,
        borderRadius: BorderRadius.all(Radius.circular(_cardRadius)),
        boxShadow: _cardShadow,
      ),
      child: SizedBox(
        width: _cardW,
        height: _cardH,
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(_cardRadius)),
          child: Stack(
            children: [
              Positioned.fill(child: _skeletonLayer()),
              Positioned.fill(child: _contentLayer()),
            ],
          ),
        ),
      ),
    );
  }

  /// 骨架层：外层跟着揭示进度淡出糊开，内层只有几根条跟着脉冲呼吸
  Widget _skeletonLayer() {
    return ListenableBuilder(
      listenable: _reveal,
      builder: (context, child) {
        final v = _reveal.value;
        return Opacity(
          opacity: 1 - v,
          child: LabBlur(sigma: v * _revealBlur, child: child!),
        );
      },
      // 脉冲只在 loading 期间发帧，之后这条时间线停着，不会白重画骨架
      child: ListenableBuilder(
        listenable: _pulse,
        builder: (context, _) => _skeleton(_barOpacity(_pulse.value)),
      ),
    );
  }

  Widget _contentLayer() {
    return ListenableBuilder(
      listenable: _reveal,
      builder: (context, child) {
        final v = _reveal.value;
        return Opacity(
          opacity: v,
          child: LabBlur(sigma: _revealBlur - v * _revealBlur, child: child!),
        );
      },
      child: _content(),
    );
  }

  /// `t-skel-pulse`：0%/100% 不透明，50% 落到 --pulse-min，两侧各走 ease-in-out
  double _barOpacity(double v) {
    final k = v < 0.5
        ? LabEase.inOut.transform(v * 2)
        : LabEase.inOut.transform((1 - v) * 2);
    return 1 - (1 - _pulseMin) * k;
  }

  Widget _skeleton(double barOpacity) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _padX),
      child: Row(
        children: [
          _bar(
            width: _avatar,
            height: _avatar,
            radius: _avatar / 2,
            opacity: barOpacity,
          ),
          const SizedBox(width: _skGap),
          Padding(
            padding: const EdgeInsets.only(left: _skLinesMarginLeft),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _bar(width: _skNameW, height: _skBarH, radius: _skBarRadius, opacity: barOpacity),
                const SizedBox(height: _skLinesGap),
                _bar(width: _skEmailW, height: _skBarH, radius: _skBarRadius, opacity: barOpacity),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar({
    required double width,
    required double height,
    required double radius,
    required double opacity,
  }) {
    return Opacity(
      opacity: opacity,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: LabColor.skeleton,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }

  Widget _content() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _padX),
      child: Row(
        children: [
          const _Avatar(),
          const SizedBox(width: _contentGap),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(_name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _nameStyle),
                SizedBox(height: _textGap),
                Text(_email, maxLines: 1, overflow: TextOverflow.ellipsis, style: _emailStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 位图头像在离线出图里是豆腐块，按参考稿的位置画纯色底 + 字母占位
class _Avatar extends StatelessWidget {
  const _Avatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _Case17SkeletonLoaderAndRevealState._avatar,
      height: _Case17SkeletonLoaderAndRevealState._avatar,
      decoration: const BoxDecoration(
        color: LabColor.skeleton,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: const Text(
        'JC',
        style: TextStyle(
          fontFamily: LabFont.family,
          fontFamilyFallback: LabFont.fallback,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          height: 1,
          color: LabColor.textFaint,
        ),
      ),
    );
  }
}
