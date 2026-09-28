import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart' show PointerExitEvent;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../kit.dart';

/// 4 号：液态金属描边钮
///
/// 参考稿的金属不是贴图，是一段 GLSL 加一次 `destination-out` 挖洞：先把整块盒子
/// 画满，再挖掉 `ringCssPx` 以内的部分，留下的就是贴着外缘那一圈 —— 胶囊 1px、
/// 圆钮 2px。所以这份"还原"分两半：
/// **形状是精确的**（两道圆角矩形的差集 + 逐像素覆盖度），
/// **颜色是移植的**（`liquidMetal` 的 `u_isImage==false / shape<1` 那一条分支逐式
/// 翻成 Dart 采样：`direction` 条纹、`bump`、色散、color-burn 染色、8bit dither）。
/// 降级掉的两处写在这里，不藏：
/// 1. 挖洞留下的 1px 里着色器自己的 `edge` 几乎是常数（`opacity` 恒为 1，本来就
///    不参与形状），所以环带的明暗主要由水平条纹给出 —— 与参考页同源同因；
/// 2. 光环那一层（z=3 的 SVG）参考稿只量到明暗档（暗 .7 / 浅 .2746 + multiply）
///    和 `disableGlow`，走一圈的周期、路径量不出来，`_haloPeriod` 那两档是本地定的。
/// 参考稿的行为倒是全照搬：15fps 抽帧（时间按拍取整）、暂停冻在最后一帧但按钮照旧
/// 能点、预设三档换染色、强度同时喂金属和光环、指针位置压暗条纹
/// （`cursorStrength 3.35 / cursorDiffuse 1.4 / cursorFalloff 37 / fadeMs 200`）、
/// 减弱动效时一直保持静止。
class Case04MetalButton extends StatefulWidget {
  const Case04MetalButton({super.key});

  static const pillKey = ValueKey<String>('sv-c04-pill');
  static const iconKey = ValueKey<String>('sv-c04-icon');
  static const noGlowKey = ValueKey<String>('sv-c04-noglow');
  static const pauseKey = ValueKey<String>('sv-c04-pause');
  static const swatchKey = ValueKey<String>('sv-c04-swatch');
  static const darkPillKey = ValueKey<String>('sv-c04-dark-pill');
  static const darkIconKey = ValueKey<String>('sv-c04-dark-icon');
  static const hintKey = ValueKey<String>('sv-c04-hint');
  static const presetPrefix = 'sv-c04-preset-';
  static const strengthPrefix = 'sv-c04-strength-';

  /// 某个金属面的画层：逐帧断言从它读量化时钟、强度、色散
  static Key ringKey(Key host) => ValueKey<String>('${(host as ValueKey<String>).value}-ring');

  @override
  State<Case04MetalButton> createState() => _Case04MetalButtonState();
}

class _Case04MetalButtonState extends State<Case04MetalButton> with SingleTickerProviderStateMixin {
  // ===== 参考稿量出来的那一套（字面 px，例外只圈在这一页）=====

  /// 胶囊：134×40、`--mfx-radius` 20、环 1px、`shaderScale` 1.6、内衬 `inset:3px`
  static const pillW = 134.0;
  static const pillH = 40.0;
  static const pillRadius = 20.0;
  static const pillRing = 1.0;
  static const pillScale = 1.6;
  static const pillInner = 3.0;

  /// 圆钮：32×32、radius 16、环 2px、`shaderScale` 1.3、内衬 0
  static const iconSize = 32.0;
  static const iconRadius = 16.0;
  static const iconRing = 2.0;
  static const iconScale = 1.3;

  /// `gap-3` = 12
  static const gap = 12.0;

  /// 暗色预览块：`rounded-xl`(14) + `bg-neutral-950`
  static const swatchW = 340.0;
  static const swatchH = 64.0;

  /// 参考页 15fps 抽帧：66.667ms 一拍
  static const frameMs = 1000.0 / 15.0;

  /// 指尖那一格要 44，这一页的空隙刚好够
  ///
  /// 透明受理区得占一格真实布局（探出宿主盒子的那部分收不到命中，见 `svTapPads`
  /// 的说明），所以这里不是往外探，是把脸包在里面撑大、再让相邻的空隙跟着缩 ——
  /// 圆心距就是硬顶：左右各让半个 `gap`，上下各让半段行距，谁也不能压到邻脸。
  /// 三行条（28 高）横向有 `px-2` 那 20 内衬，短边只剩高度，左右各探 4 就是圆心距。
  /// 一行要探就得整行一起探：脸撑开 12、旁边的空隙让出 12，整块还是原来那么大。
  /// 胶囊横向本来就不缺那点地方，可它也得跟着往左探 6 —— 一行里只有一颗不动的话，
  /// 居中的那一排全跟着它平移，观感就废了；它右边不留带子，那 6 留给第一段 `gap`。
  /// 纵向四张脸分三段 12 的行距：胶囊只缺 4、圆钮缺 12，剩下的 12+12 正好给两行条
  /// 8+8 和 4+12 —— 每一格都凑满 44，行距一格不剩，脸也一格没挪。
  static const pillGrow = EdgeInsets.fromLTRB(6, 0, 0, 4);
  static const iconGrow = EdgeInsets.fromLTRB(6, 4, 6, 8);
  static const chipGrow = EdgeInsets.fromLTRB(4, 8, 4, 8);
  static const chipGrowLow = EdgeInsets.fromLTRB(4, 4, 4, 12);

  /// 撑开一格就得让出一格：横向从 `gap` 里扣，扣完剩下 `gap - 前后两张脸探出的量`
  static double gapAfter(EdgeInsets before, EdgeInsets after, {double lead = gap}) =>
      lead - before.right - after.left;

  /// 行距同理：上面那张脸往下探的加上下面那张往上探的，都从这一条里扣
  static double rowGapAfter(EdgeInsets above, EdgeInsets below, {double lead = 12}) =>
      lead - above.bottom - below.top;

  /// 预设表里没有、每一档共用的底料
  static const distortion = 0.1;
  static const contour = 0.4;
  static const angle = 90.0;

  SvMetalPreset _preset = SvMetalPreset.chromatic;
  double _strength = 0.9;
  bool _paused = false;
  bool _reduced = false;

  /// 共享时钟：整组面吃同一个 `u_time`（参考稿就一个 GL 上下文）
  double _rawMs = 0;
  double _timeMs = 0;
  int _tick = 0;
  Duration _last = Duration.zero;
  Ticker? _ticker;

  bool get _stopped => _paused || _reduced;

  @override
  void initState() {
    super.initState();
    // 起钟前已经把 _timeMs 钉在 0：静止出图的落点是确定的
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final dt = elapsed - _last;
    _last = elapsed;
    if (_stopped) {
      // 暂停 = 保留最后一帧：时基跟着停，面还在、按钮照旧能点
      return;
    }
    // 余数留在累加器里：真机 60fps 每拍只有 16.7ms，拿单拍去取整会永远凑不满一拍
    _rawMs += dt.inMicroseconds / 1000.0;
    final next = (_rawMs / frameMs).floor();
    if (next == _tick) return;
    setState(() {
      _tick = next;
      _timeMs = next * frameMs;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void dispose() {
    _ticker?.stop();
    _ticker = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stopped = _stopped;
    return SvStage(
      // 参考稿的 preview 就是白页：金属环是暗色 hairline，压在一档灰上就没边界了
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _metal(
                Case04MetalButton.pillKey,
                w: pillW,
                h: pillH,
                radius: pillRadius,
                ringPx: pillRing,
                scale: pillScale,
                inner: pillInner,
                grow: pillGrow,
                child: const Text('Continue'),
              ),
              SizedBox(width: gapAfter(pillGrow, iconGrow)),
              _metal(
                Case04MetalButton.iconKey,
                w: iconSize,
                h: iconSize,
                radius: iconRadius,
                ringPx: iconRing,
                scale: iconScale,
                grow: iconGrow,
                child: const Icon(Icons.bolt_outlined, size: 14),
              ),
              SizedBox(width: gapAfter(iconGrow, iconGrow)),
              _metal(
                Case04MetalButton.noGlowKey,
                w: iconSize,
                h: iconSize,
                radius: iconRadius,
                ringPx: iconRing,
                scale: iconScale,
                grow: iconGrow,
                glow: false,
                child: const Icon(Icons.auto_awesome_outlined, size: 14),
              ),
              SizedBox(width: gapAfter(iconGrow, iconGrow)),
              _metal(
                Case04MetalButton.pauseKey,
                w: iconSize,
                h: iconSize,
                radius: iconRadius,
                ringPx: iconRing,
                scale: iconScale,
                grow: iconGrow,
                onTap: () => setState(() => _paused = !_paused),
                child: Icon(stopped ? Icons.play_arrow_rounded : Icons.pause_rounded, size: 14),
              ),
            ],
          ),
          SizedBox(height: rowGapAfter(pillGrow, chipGrow)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final p in SvMetalPreset.values)
                Padding(
                  padding: EdgeInsets.only(
                    left: p == SvMetalPreset.chromatic ? 0 : gapAfter(chipGrow, chipGrow, lead: 8),
                  ),
                  child: SvChip(
                    key: ValueKey<String>('${Case04MetalButton.presetPrefix}${p.name}'),
                    label: p.label,
                    grow: chipGrow,
                    on: _preset == p,
                    onTap: () => setState(() => _preset = p),
                  ),
                ),
            ],
          ),
          SizedBox(height: rowGapAfter(chipGrow, chipGrowLow)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final s in kSvStrengths)
                Padding(
                  padding: EdgeInsets.only(
                    left: s == kSvStrengths.first ? 0 : gapAfter(chipGrowLow, chipGrowLow, lead: 8),
                  ),
                  child: SvChip(
                    key: ValueKey<String>('${Case04MetalButton.strengthPrefix}$s'),
                    label: '${(s * 100).round()}%',
                    tabular: true,
                    grow: chipGrowLow,
                    on: _strength == s,
                    onTap: () => setState(() => _strength = s),
                  ),
                ),
            ],
          ),
          SizedBox(height: rowGapAfter(chipGrowLow, EdgeInsets.zero)),
          SizedBox(
            width: swatchW,
            height: swatchH,
            child: DecoratedBox(
              key: Case04MetalButton.swatchKey,
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A0A),
                borderRadius: const BorderRadius.all(Radius.circular(14)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _metal(
                    Case04MetalButton.darkPillKey,
                    w: pillW,
                    h: pillH,
                    radius: pillRadius,
                    ringPx: pillRing,
                    scale: pillScale,
                    inner: pillInner,
                    dark: true,
                    child: const Text('Continue'),
                  ),
                  const SizedBox(width: gap),
                  _metal(
                    Case04MetalButton.darkIconKey,
                    w: iconSize,
                    h: iconSize,
                    radius: iconRadius,
                    ringPx: iconRing,
                    scale: iconScale,
                    dark: true,
                    child: const Icon(Icons.tonality_outlined, size: 14),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _reduced ? '已开减弱动效 —— 金属环一直保持静止。' : '提示：暂停会把光环冻在最后一帧，按钮照样能点。',
            key: Case04MetalButton.hintKey,
            style: TextStyle(
              fontFamily: SvFont.family,
              fontFamilyFallback: SvFont.fallback,
              fontSize: 12,
              height: 16 / 12,
              color: _reduced ? const Color(0xFFD97706) : const Color(0xFF737373),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metal(
    Key key, {
    required double w,
    required double h,
    required double radius,
    required double ringPx,
    required double scale,
    required Widget child,
    bool dark = false,
    bool glow = true,
    double inner = 0,
    EdgeInsets? grow,
    VoidCallback? onTap,
  }) {
    final tap = onTap ?? () {};
    final face = SvMetal(
      key: key,
      ringKey: Case04MetalButton.ringKey(key),
      width: w,
      height: h,
      radius: radius,
      ringPx: ringPx,
      shaderScale: scale,
      innerInset: inner,
      preset: _preset,
      dark: dark,
      strength: _strength,
      timeMs: _timeMs,
      glow: glow,
      onTap: tap,
      child: child,
    );
    // 暗色预览块里那两张脸点了什么也不做，就不必占布局；上面三行是真按得着的
    return grow == null ? face : SvTapGrow(grow: grow, onTap: tap, child: face);
  }
}

/// 切换用的小钮：不是金属面，就是参考稿那颗普通按钮（`size-2` 档）
class SvChip extends StatefulWidget {
  const SvChip({
    super.key,
    required this.label,
    required this.on,
    required this.onTap,
    this.grow = EdgeInsets.zero,
    this.tabular = false,
  });

  final String label;
  final bool on;
  final VoidCallback onTap;

  /// 透明受理区往外探的量，由放它的那一行按 `gap` 定（见 `SvTapGrow`）
  final EdgeInsets grow;
  final bool tabular;

  @override
  State<SvChip> createState() => _SvChipState();
}

class _SvChipState extends State<SvChip> {
  bool _hov = false;

  @override
  Widget build(BuildContext context) {
    // 28 高对指尖太窄：上下左右探多少由放它的那一行定（那一行同时把 `gap` 让出来）
    return SvTapGrow(
      grow: widget.grow,
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hov = true),
        onExit: (_) => setState(() => _hov = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: SvEase.standard,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: widget.on
                  ? const Color(0xFF171717)
                  : (_hov ? const Color(0xFFF5F5F5) : const Color(0xFFFFFFFF)),
              borderRadius: const BorderRadius.all(Radius.circular(10)),
              boxShadow: widget.on
                  ? const []
                  : const [BoxShadow(color: Color(0xFFE5E5E5), spreadRadius: 1)],
            ),
            child: SizedBox(
              height: 28,
              child: Center(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontFamily: SvFont.family,
                    fontFamilyFallback: SvFont.fallback,
                    fontSize: 12.8,
                    fontWeight: FontWeight.w500,
                    height: 1,
                    fontFeatures: widget.tabular ? SvFont.tabular : const <FontFeature>[],
                    color: widget.on ? const Color(0xFFFAFAFA) : const Color(0xFF0A0A0A),
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

/// 金属材质档：参数照参考页的预设表
enum SvMetalPreset {
  chromatic(
    'Chromatic',
    tintDark: Color(0xFF88CCFF),
    alphaDark: 0x2e / 255,
    tintLight: Color(0xFF66B0FF),
    alphaLight: 0x99 / 255,
    opDark: 1,
    opLight: 1,
    repetition: 2,
    softness: 0.09,
    shiftDark: 0.75,
    shiftLight: 0.6,
    speed: 1,
  ),
  silver(
    'Silver',
    tintDark: Color(0xFFFFFFFF),
    alphaDark: 0x66 / 255,
    tintLight: Color(0xFFFFFFFF),
    alphaLight: 0x40 / 255,
    opDark: 0.88,
    opLight: 1,
    repetition: 1.5,
    softness: 0.05,
    shiftDark: 0.3,
    shiftLight: 0.3,
    speed: 1,
  ),
  gold(
    'Gold',
    tintDark: Color(0xFFFFCC55),
    alphaDark: 0xcc / 255,
    tintLight: Color(0xFFF7D488),
    alphaLight: 0xaa / 255,
    opDark: 0.92,
    opLight: 1,
    repetition: 1.5,
    softness: 0.05,
    shiftDark: 0.3,
    shiftLight: 0.3,
    speed: 0.85,
  );

  const SvMetalPreset(
    this.label, {
    required this.tintDark,
    required this.alphaDark,
    required this.tintLight,
    required this.alphaLight,
    required this.opDark,
    required this.opLight,
    required this.repetition,
    required this.softness,
    required this.shiftDark,
    required this.shiftLight,
    required this.speed,
  });

  final String label;

  /// `colorTint`：走 color-burn，alpha 是那一档染色的权重
  final Color tintDark;
  final double alphaDark;
  final Color tintLight;
  final double alphaLight;
  final double opDark;
  final double opLight;
  final double repetition;
  final double softness;
  final double shiftDark;
  final double shiftLight;
  final double speed;

  /// 参考页每一档的 shiftRed 和 shiftBlue 都是同一个值
  double shift(bool dark) => dark ? shiftDark : shiftLight;

  double tintAlpha(bool dark) => dark ? alphaDark : alphaLight;

  Color tint(bool dark) => dark ? tintDark : tintLight;

  double shaderOpacity(bool dark) => dark ? opDark : opLight;
}

/// 强度档：参考页给的就是这四档
const List<double> kSvStrengths = <double>[0.5, 0.75, 0.9, 1];

/// 一个金属面：挖好洞的那一圈 + 光环 + 压印 + 内容
class SvMetal extends StatefulWidget {
  const SvMetal({
    super.key,
    required this.ringKey,
    required this.width,
    required this.height,
    required this.radius,
    required this.ringPx,
    required this.shaderScale,
    required this.preset,
    required this.dark,
    required this.strength,
    required this.timeMs,
    required this.onTap,
    required this.child,
    this.innerInset = 0,
    this.glow = true,
  });

  /// 画层单独挂一个 key：测试要读它身上那一份量化后的时钟
  final Key ringKey;
  final double width;
  final double height;
  final double radius;

  /// 环宽：胶囊 1、圆钮 2（`ringCssPx`）
  final double ringPx;

  /// 条纹的缩放（`shaderScale`）
  final double shaderScale;

  /// 内衬：胶囊 `inset:3px`，圆钮 0（暗档在那圈边界上留 1px 发丝）
  final double innerInset;

  final SvMetalPreset preset;
  final bool dark;

  /// `opacityMul = clamp(strength,0,1)`：同时喂给金属和光环
  final double strength;
  final double timeMs;

  /// false = `disableGlow`：只留金属，不留光环
  final bool glow;
  final VoidCallback onTap;
  final Widget child;

  static const cursorStrength = 3.35;
  static const cursorDiffuse = 1.4;
  static const cursorFalloff = 37.0;
  static const cursorFadeMs = 200;

  @override
  State<SvMetal> createState() => _SvMetalState();
}

class _SvMetalState extends State<SvMetal> with TickerProviderStateMixin {
  Offset? _hot;
  double _amt = 0;
  bool _down = false;
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

  @override
  void initState() {
    super.initState();
    // 离开时冻住最后那个位置，只把亮度淡掉（参考稿 fadeMs 200）
    _fade.addListener(() => setState(() => _amt = _fade.value));
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  void _enter(Offset at) {
    _fade.stop();
    setState(() {
      _hot = at;
      _amt = 1;
    });
  }

  void _exit(PointerExitEvent e) {
    setState(() => _hot = e.localPosition);
    _fade.reverse(from: _amt);
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (e) => _enter(e.localPosition),
      onHover: (e) {
        if (_hot != e.localPosition) setState(() => _hot = e.localPosition);
      },
      onExit: _exit,
      child: GestureDetector(
        onTapDown: (d) => setState(() => _down = true),
        onTap: () {
          setState(() => _down = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _down = false),
        child: SvTween(
          // `active:` 那一档：整块面压一点、缩一点
          target: _down ? 1 : 0,
          duration: const Duration(milliseconds: 110),
          curve: SvEase.standard,
          builder: (context, q) => Transform.scale(
            scale: 1 - 0.015 * q,
            child: Opacity(
              opacity: 1 - 0.18 * q,
              child: SizedBox(
                width: widget.width,
                height: widget.height,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CustomPaint(
                      key: widget.ringKey,
                      painter: SvMetalPainter(
                        size: Size(widget.width, widget.height),
                        radius: widget.radius,
                        ringPx: widget.ringPx,
                        innerInset: widget.innerInset,
                        shaderScale: widget.shaderScale,
                        preset: widget.preset,
                        dark: widget.dark,
                        strength: widget.strength,
                        timeMs: widget.timeMs,
                        glow: widget.glow,
                        hot: _amt > 0.001 ? _hot : null,
                        hotAmt: _amt,
                        dpr: dpr,
                      ),
                    ),
                    IgnorePointer(
                      child: Center(
                        child: DefaultTextStyle(
                          style: TextStyle(
                            fontFamily: SvFont.family,
                            fontFamilyFallback: SvFont.fallback,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            height: 20 / 14,
                            color: widget.dark ? const Color(0xFFF8F8F8) : const Color(0xFF1D1D1D),
                          ),
                          child: widget.child,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 金属面画层：几何精确 + 条纹逐式移植
class SvMetalPainter extends CustomPainter {
  SvMetalPainter({
    required this.size,
    required this.radius,
    required this.ringPx,
    required this.innerInset,
    required this.shaderScale,
    required this.preset,
    required this.dark,
    required this.strength,
    required this.timeMs,
    required this.glow,
    required this.hot,
    required this.hotAmt,
    required this.dpr,
  });

  final Size size;
  final double radius;
  final double ringPx;
  final double innerInset;
  final double shaderScale;
  final SvMetalPreset preset;
  final bool dark;
  final double strength;
  final double timeMs;
  final bool glow;
  final Offset? hot;
  final double hotAmt;
  final double dpr;

  // 参考页 chrome 的两档（root 的 background/color 加四层描边）
  static const surfaceDark = Color(0xFF272727);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const rimDark = Color(0x1AFFFFFF); // inset 0 0 0 1px rgba(255,255,255,.1)
  static const rimLight = Color(0x0F000000); // 浅档是 .06 的黑
  static const veilDark = Color(0x05FFFFFF); // inset 0 0 50px rgba(255,255,255,.02)
  static const veilLight = Color(0x05000000);
  static const hairlineDark = Color(0x73000000); // 圆钮内衬 rgba(0,0,0,.45)
  static const stable70 = Color(0xB3E5E5E5); // ring-1 ring-border/70
  static const stable80 = Color(0xCCE5E5E5);

  /// 参考页的 15fps 抽帧：亮出去的拍号 = 时间按 66.667ms 取整
  int get frame => (timeMs / _Case04MetalButtonState.frameMs).floor();

  /// 环带那一圈的最终 alpha：强度 × 预设的 `shaderOpacity`
  double get opacityMul => strength.clamp(0.0, 1.0) * preset.shaderOpacity(dark);

  /// 光环那一层的明暗档（`#btnGlowSvg`：暗 .7 / 浅 .2746）
  double get glowOpacity => (dark ? 0.7 : 0.2746) * strength.clamp(0.0, 1.0);

  Color get surfaceColor => dark ? surfaceDark : surfaceLight;

  /// 光环走一圈的周期：参考稿只量到明暗和 blend-mode，这两个数是本地定的
  static const haloPeriodMs = 6000.0;
  static const catchPeriodMs = 4500.0;

  /// 光环画层：内缩 1.5、光点半长 7.8（沿周长 px），四档糊光 (宽, 糊, 明暗)
  ///
  /// 那四档是参考稿 SVG 自己的用户单位，照搬成 px 会糊到钮外面去（26.4 宽压在
  /// 40 高的胶囊上就是一条横跨预览块的白带），所以按短边等比缩：`bloomScale`
  /// 是本地定的，落点让最宽那档 ≈10px。extra 那颗小火花本来就是 px 量级，不缩。
  static const _haloInset = 1.5;
  static const _haloHalfLen = 7.8;
  static const _bloomScale = 0.4;
  static const _extraHalfLen = 9.13952 / 3;

  /// 光环允许往盒子外爬的绝对上限：见 `_paintHalo` 里那段裁剪
  static const _haloMaxSpread = 4.0;
  static const _haloTiers = <(double, double, double)>[
    (26.4, 8.4, 0.385),
    (15.6, 4.8, 0.595),
    (7.2, 2.1, 0.7),
    (3.0, 0.9, 0.7),
  ];
  static const _extraTiers = <(double, double, double)>[
    (4 / 3, 2 / 3, 0.85),
    (2 / 3, 1.35 / 3, 1),
  ];

  @override
  void paint(Canvas canvas, Size s) {
    final w = size.width, h = size.height;
    final rr = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), Radius.circular(radius));

    // z0 底：参考页是 root 的 background
    canvas.drawRRect(rr, Paint()..color = surfaceColor);
    // `metalStableEdge`：1px 内描边，白底那颗钮全靠它才有一圈边界
    _insetStroke(canvas, w, h, radius, 0, 1, dark ? stable80 : stable70);

    _paintBand(canvas, w, h);

    // z1 内衬：圆钮那颗在暗档留一圈 1px 发丝（浅档参考页里压成 0）
    if (innerInset <= 0 && dark) _insetStroke(canvas, w, h, radius, 0, 1, hairlineDark);

    // z2 `::before`：inset 0 0 50px 那一层，近似成沿内缘的一条糊光
    canvas.save();
    canvas.clipRRect(rr);
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 26
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 13)
        ..color = dark ? veilDark : veilLight,
    );
    canvas.restore();

    if (glow) _paintHalo(canvas, w, h);

    // z4 `::after`：1px（圆钮 2px）内描边
    _insetStroke(canvas, w, h, radius, 0, ringPx, dark ? rimDark : rimLight);
  }

  /// 贴内缘的一条描边：`strokeWidth` 宽、中心线往里让半个线宽
  void _insetStroke(Canvas canvas, double w, double h, double r, double inset, double sw, Color c) {
    final o = inset + sw / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(o, o, w - 2 * o, h - 2 * o),
        Radius.circular(math.max(0.0, r - o)),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw
        ..color = c,
    );
  }

  /// 环带逐像素：两道圆角矩形的差集 + 移植过来的条纹场
  void _paintBand(Canvas canvas, double w, double h) {
    final e = ringPx;
    final iw = w - 2 * e, ih = h - 2 * e;
    final ir = math.max(0.0, radius - e);
    final t = 0.3 * (timeMs / 1000.0 * preset.speed + 2.8);
    final ang = (-_Case04MetalButtonState.angle + 70.0) * math.pi / 180.0;
    final ca = math.cos(ang), sa = math.sin(ang);
    final tint = preset.tint(dark);
    final tintA = preset.tintAlpha(dark);
    // 非图像那一条分支：`softness/15 + .3*contour`，contour 项占大头
    final blurBase = preset.softness / 15.0 + 0.3 * _Case04MetalButtonState.contour;
    final alpha = opacityMul;
    final cx = w / 2, cy = h / 2;
    final hot0 = hot;
    final amt = hotAmt;

    final cols = (w * dpr).ceil();
    final rows = (h * dpr).ceil();
    final step = 1.0 / dpr;
    final dirRow = Float64List(cols + 1);
    final paint = Paint()..isAntiAlias = false;
    final o = _Field();

    var runX = 0.0;
    var runEnd = 0.0;
    var runColor = 0;
    var runRow = -1;
    void flush() {
      if (runRow < 0) return;
      paint.color = Color(runColor);
      canvas.drawRect(Rect.fromLTWH(runX, runRow * step, runEnd - runX, step), paint);
      runRow = -1;
    }

    for (var gy = 0; gy < rows; gy++) {
      final py = (gy + 0.5) * step;
      double? dirLeft;
      for (var gx = 0; gx < cols; gx++) {
        final px = (gx + 0.5) * step;
        final so = _sdfRR(px, py, w, h, radius);
        if (so > step) {
          flush();
          continue;
        }
        // 内孔：挖掉 `ringCssPx` 以内的部分（参考页的 destination-out）
        final si = _sdfRR(px - e, py - e, iw, ih, ir);
        if (si < -step) {
          flush();
          continue;
        }
        final cover = (0.5 - so * dpr).clamp(0.0, 1.0) * (0.5 + si * dpr).clamp(0.0, 1.0);
        if (cover <= 0.002) {
          flush();
          continue;
        }
        _eval(o, px - cx, py - cy, w, h, t, ca, sa, px, py);
        // `fwidth(stripe)`：着色器里是 `|dFdx| + |dFdy|`，这里用同一条带上的
        // 左邻/上邻差分出来。它比 `softness/15 + .3*contour` 大得多，
        // 条纹的软硬几乎全由它给
        final fw = (dirLeft == null ? 0 : (o.dir - dirLeft).abs()) +
            (gy == 0 ? 0 : (o.dir - dirRow[gx]).abs());
        dirLeft = o.dir;
        dirRow[gx] = o.dir;

        final blur = blurBase + fw;
        _channel(o, 0, o.stripeR, blur, tintA, tint.r);
        _channel(o, 1, o.stripeG, blur, tintA, tint.g);
        _channel(o, 2, o.stripeB, blur, tintA, tint.b);
        var r = o.c0, g = o.c1, b = o.c2;
        final lum = (r + g + b) / 3.0;

        // 指针压暗（cursorStrength/falloff）：靠近指针那一头的对比度拉下来
        if (hot0 != null && amt > 0.001) {
          final ddx = px - hot0.dx, ddy = py - hot0.dy;
          final d = math.sqrt(ddx * ddx + ddy * ddy);
          final q = d / SvMetal.cursorFalloff;
          final y = 1 / (1 + q * q) * amt;
          final k = SvMetal.cursorStrength * y * 0.055;
          r -= k * (r - lum);
          g -= k * (g - lum);
          b -= k * (b - lum);
          final lift = SvMetal.cursorDiffuse * y * 0.02 * (0.5 + 0.5 * math.min(1, lum / 0.5));
          r += lift;
          g += lift;
          b += lift;
        }

        final argb = ((cover * alpha * 255).round().clamp(0, 255) << 24) |
            ((r * 255).round().clamp(0, 255) << 16) |
            ((g * 255).round().clamp(0, 255) << 8) |
            ((b * 255).round().clamp(0, 255));
        if (runRow >= 0 && argb == runColor) {
          runEnd = px + step / 2;
        } else {
          flush();
          runRow = gy;
          runX = px - step / 2;
          runEnd = px + step / 2;
          runColor = argb;
        }
      }
      flush();
    }
  }

  /// `liquidMetal` 的 `u_isImage==false / shape<1` 分支：条纹场
  ///
  /// 三套 uv 各管各的，别混：
  /// - `mx/my` 只喂 `edge` 那个遮罩，横纵各按自己的边长归一（`v_responsiveUV`）；
  /// - `ux/uy` 是着色空间的 uv：`ratio>1` 时 y 再除 ratio，于是两轴都按长边归一，
  ///   末尾那次 `uv.y = 1. - uv.y` 把它翻成"往下为正"；
  /// - 两条对角线吃的是物体 uv（短边归一，同样翻成正向朝下）。
  /// 参考页 `contour:.4` 落在 `smoothstep(.5,1,.4)=0` 那一档，所以 `direction` 上
  /// 那两条乘 contour 的项恒为 0（连 `edge` 那行 mix 也取的是原值），这里直接不写。
  void _eval(_Field o, double dx, double dy, double bw, double bh, double t, double ca, double sa,
      double px, double py) {
    final maxSide = math.max(bw, bh);
    // 遮罩：min(u,1-u) 对翻不翻 y 不敏感，归一化才敏感
    final mx = 0.5 + dx / (shaderScale * bw);
    final my = 0.5 + dy / (shaderScale * bh);
    final ux = 0.5 + dx / (shaderScale * maxSide);
    final uy = 0.5 + dy / (shaderScale * maxSide);
    // 物体 uv：短边归一，再翻成往下为正 —— 两条对角线由它给出
    final ox = dx / (shaderScale * math.min(bw, bh));
    final oy = dy / (shaderScale * math.min(bw, bh));
    final rx = ox * ca - oy * sa;
    final ry = ox * sa + oy * ca;
    final diagBL = rx - ry;
    final diagTL = rx + ry;

    var edge = 1 -
        _pow(_ss(0, 0.5, math.min(mx, 1 - mx)), 0.25) * _pow(_ss(0, 0.5, math.min(my, 1 - my)), 0.25);
    edge = edge.clamp(0.0, 1.0) * 1.2;

    final gx = ux - 0.5, gy = uy - 0.5;
    final qy = gy + 0.2 * diagBL;
    final dist = math.sqrt(gx * gx + qy * qy);
    final ra = math.cos((0.25 - 0.2 * diagBL) * math.pi);
    final rb = math.sin((0.25 - 0.2 * diagBL) * math.pi);
    var dir = gx * ra - gy * rb;

    var bump = 1 - _pow(1.8 * dist, 1.2);
    bump *= _pow(uy, 0.3);

    final noise = _snoise(ux - t, uy - t);
    edge += (1 - edge) * _Case04MetalButtonState.distortion * noise;
    final ssE = _ss(0, 1, edge);

    dir += diagBL;
    dir -= 2 * noise * diagBL * ssE * (1 - ssE);
    dir += 0.2 * _pow(_Case04MetalButtonState.contour, 4) * (1 - ssE);
    // 上下各一条窄带把条纹往两边推：这两条跟 contour 无关，是常数项
    dir += 0.18 * (_ss(0.1, 0.2, uy) * (1 - _ss(0.2, 0.4, uy)));
    dir += 0.03 * (_ss(0.1, 0.2, 1 - uy) * (1 - _ss(0.2, 0.4, 1 - uy)));
    bump *= _clampD(_pow(uy, 0.1), 0.3, 1);
    dir *= 0.1 + (1.1 - edge) * bump;
    dir *= 0.4 + 0.6 * (1 - _ss(0.5, 1, edge));
    dir *= 0.5 + 0.5 * uy * uy;
    final cw = preset.repetition * 2; // `cycleWidth *= 2`
    dir *= cw;
    dir -= t;

    final shift = preset.shift(dark) / 20.0;
    final cd = (1 - bump).clamp(0.0, 1.0);
    var dR = cd +
        0.03 * bump * noise +
        5 *
            (_ss(-0.1, 0.2, uy) * (1 - _ss(0.1, 0.5, uy))) *
            (_ss(0.4, 0.6, bump) * (1 - _ss(0.4, 1, bump)));
    dR = (dR - diagBL) * shift;
    var dB = cd * 1.3 +
        (_ss(0, 0.4, uy) * (1 - _ss(0.1, 0.8, uy))) *
            (_ss(0.4, 0.6, bump) * (1 - _ss(0.4, 0.8, bump)));
    dB = (dB - 0.2 * edge) * shift;

    // 三条带的宽度：窄带随 bump 一收一放
    final r1 = 0.12 / cw * (1 - 0.4 * bump);
    final r2 = 0.07 / cw * (1 + 0.4 * bump);
    o.w0 = cw * r1;
    o.w1 = cw * r2 - 0.02 * _ss(0, 1, edge + bump);
    o.w2 = 1 - r1 - r2;

    o.dir = dir;
    o.bump = bump;
    o.edge = edge;
    o.diagTL = diagTL;
    o.stripeR = _fract(dir + dR);
    o.stripeG = _fract(dir);
    o.stripeB = _fract(dir - dB);
    o.px = px * dpr;
    o.py = py * dpr;
  }

  /// 一个通道：五条 smoothstep + color-burn 染色 + dither
  void _channel(_Field o, int i, double p, double blur, double tintA, double tc) {
    final c1 = i == 2 ? 1.0 : 0.98;
    final c2 = i == 2 ? 0.1 + 0.1 * _ss(0.7, 1.3, o.diagTL) : 0.1;
    final b2 = 2 * blur;
    var ch = _mix(c2, c1, _ss(0, b2, p));
    var border = o.w0;
    ch = _mix(ch, c2, _ss(border, border + b2, p));
    border = o.w0 + 0.4 * (1 - o.bump) * o.w1;
    ch = _mix(ch, c1, _ss(border, border + b2, p));
    border = o.w0 + 0.5 * (1 - o.bump) * o.w1;
    ch = _mix(ch, c2, _ss(border, border + b2, p));
    border = o.w0 + o.w1;
    ch = _mix(ch, c1, _ss(border, border + b2, p));
    final grad = _mix(c1, c2, _ss(0, 1, (p - o.w0 - o.w1) / o.w2));
    ch = _mix(ch, grad, _ss(border, border + 0.5 * blur, p));
    // `mix(ch, 1 - min(1,(1-ch)/tint), u_colorTint.a)`
    ch = _mix(ch, 1 - math.min(1, (1 - ch) / math.max(tc, 0.0001)), tintA);
    final d = o.px * 0.014 * 12.9898 + o.py * 0.014 * 78.233;
    ch += (1 / 256) * (_fract(math.sin(d) * 43758.5453123) - 0.5);
    if (i == 0) {
      o.c0 = ch.clamp(0.0, 1.0);
    } else if (i == 1) {
      o.c1 = ch.clamp(0.0, 1.0);
    } else {
      o.c2 = ch.clamp(0.0, 1.0);
    }
  }

  /// 光环：沿周长走的光点，画层本身是四档描边叠出来的多尺度糊光
  ///
  /// `haloStroke/Blur/Op` 那三张表（xl/lg/md/sm）照参考页原样搬，`inset` 也是；
  /// 只有"光点怎么走"是本地定的 —— 参考页是一个会停留、会跳位的游走点
  /// （`wanderRange/minDwellMs/wanderLerp`），量不出周期，这里退成匀速绕一圈。
  void _paintHalo(Canvas canvas, double w, double h) {
    final tSec = timeMs / 1000.0 * preset.speed;
    final center = Offset(w / 2, h / 2);
    final o = _haloInset;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(o, o, w - o * 2, h - o * 2),
          Radius.circular(math.max(0.0, radius - o)),
        ),
      );
    final a = glowOpacity;
    // 暗档 screen 提亮，浅档 multiply 压色
    final blend = dark ? BlendMode.screen : BlendMode.multiply;
    final peak = dark ? const Color(0xFFFFFFFF) : preset.tint(dark).withValues(alpha: 0.78);
    // 光点的半长是沿周长量的 px，换算成绕一圈的弧度
    final perim = 2 * (w - 2 * radius) + 2 * math.pi * radius;
    final unit = perim <= 0 ? 0.0 : 2 * math.pi / perim;

    void lobe(double angle, double halfLen, List<(double, double, double)> tiers, double scale) {
      final sw = (halfLen * unit).clamp(0.02, math.pi);
      const n = 10;
      final stops = List<double>.generate(n + 1, (int i) => i / n);
      final colors = <Color>[];
      for (var i = 0; i <= n; i++) {
        final k = math.cos(math.pi * (i / n - 0.5));
        colors.add(peak.withValues(alpha: k * k));
      }
      final shader = SweepGradient(
        startAngle: angle - sw,
        endAngle: angle + sw,
        colors: colors,
        stops: stops,
        tileMode: TileMode.clamp,
      ).createShader(Rect.fromCenter(center: center, width: w, height: h));
      for (final (stroke, sigma, op) in tiers) {
        final alpha = a * op;
        if (alpha <= 0.003) continue;
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke * scale
            ..shader = shader
            ..color = Color.fromARGB((alpha * 255).round().clamp(0, 255), 255, 255, 255)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma * scale)
            ..blendMode = blend,
        );
      }
    }

    final twoPi = 2 * math.pi;
    final bloom = math.min(w, h) / 100 * _bloomScale;
    final spread = haloSpread(w, h);
    canvas
      ..save()
      ..clipRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(-spread, -spread, w + spread * 2, h + spread * 2),
          Radius.circular(radius + spread),
        ),
      );
    lobe((tSec / (haloPeriodMs / 1000.0) * twoPi) % twoPi, _haloHalfLen, _haloTiers, bloom);
    lobe(((tSec / (catchPeriodMs / 1000.0) * twoPi) % twoPi) + 2.4, _extraHalfLen, _extraTiers, 1);
    canvas.restore();
  }

  /// 光环允许往盒子外爬的距离：各档"半线宽 + 2σ"取最大，再钉绝对上限
  ///
  /// 上限是必须的：`MaskFilter.blur` 在真机上的实际扩散比离屏 Skia 宽得多，
  /// 光靠档位自己收不住，糊光会爬进钮与钮那 12px 的缝里，看着就是漏光。
  /// 裁剪只往盒子外扩，框内的画层一点不动。
  static double haloSpread(double w, double h) {
    double reach(List<(double, double, double)> tiers, double sc) =>
        tiers.map((t) => (t.$1 / 2 + 2 * t.$2) * sc).reduce((a, b) => a > b ? a : b);
    final bloom = math.min(w, h) / 100 * _bloomScale;
    return math.min(math.max(reach(_haloTiers, bloom), reach(_extraTiers, 1)), _haloMaxSpread);
  }

  // ===== 工具 =====

  /// 圆角矩形的带符号距离：负=在内、正=在外
  ///
  /// 不能只按"直边段/圆角段"分支写：直边段里另一个分量是负的，
  /// 直接取模长会把距离算大，于是整段弧上的环带都被判成"盒子外"漏画。
  double _sdfRR(double x, double y, double w, double h, double r) {
    final hw = w / 2, hh = h / 2;
    final f = math.min(r, math.min(hw, hh));
    final qx = (x - hw).abs() - (hw - f);
    final qy = (y - hh).abs() - (hh - f);
    final ox = math.max(qx, 0.0), oy = math.max(qy, 0.0);
    return math.sqrt(ox * ox + oy * oy) + math.min(math.max(qx, qy), 0.0) - f;
  }

  double _ss(double e0, double e1, double x) {
    final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  double _mix(double a, double b, double t) => a + (b - a) * t;

  double _clampD(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

  double _pow(double base, double e) => base <= 0 ? 0 : math.pow(base, e).toDouble();

  double _fract(double v) => v - v.floorToDouble();

  double _mod289(double x) => x - 289.0 * (x / 289.0).floorToDouble();

  double _permute(double x) => _mod289(((x * 34.0) + 1.0) * x);

  /// Ashima 的 2D simplex：参考页 `snoise(vec2)` 逐式照搬
  double _snoise(double vx, double vy) {
    const cX = 0.211324865405187, cY = 0.366025403784439;
    const cZ = -0.577350269189626, cW = 0.024390243902439;
    final sk = (vx + vy) * cY;
    final ix = (vx + sk).floorToDouble(), iy = (vy + sk).floorToDouble();
    final t = (ix + iy) * cX;
    final x0x = vx - ix + t, x0y = vy - iy + t;
    final i1x = x0x > x0y ? 1.0 : 0.0;
    final i1y = x0x > x0y ? 0.0 : 1.0;
    final x1x = x0x - i1x + cZ, x1y = x0y - i1y + cZ;
    final x2x = x0x + cZ, x2y = x0y + cZ;
    final mx = _mod289(ix), my = _mod289(iy);
    final g0 = _hash(_permute(_permute(my) + mx), x0x, x0y, cW);
    final g1 = _hash(_permute(_permute(my + i1y) + mx + i1x), x1x, x1y, cW);
    final g2 = _hash(_permute(_permute(my + 1) + mx + 1), x2x, x2y, cW);
    final m0 = math.max(0.5 - (x0x * x0x + x0y * x0y), 0.0);
    final m1 = math.max(0.5 - (x1x * x1x + x1y * x1y), 0.0);
    final m2 = math.max(0.5 - (x2x * x2x + x2y * x2y), 0.0);
    return 130.0 * (m0 * m0 * m0 * m0 * g0 + m1 * m1 * m1 * m1 * g1 + m2 * m2 * m2 * m2 * g2);
  }

  double _hash(double p, double x, double y, double cW) {
    final gx = 2 * _fract(p * cW) - 1;
    final hx = gx.abs() - 0.5;
    final a0 = gx - gx.roundToDouble();
    return (a0 * x + hx * y) * (1.79284291400159 - 0.85373472095314 * (a0 * a0 + hx * hx));
  }

  @override
  bool shouldRepaint(SvMetalPainter old) =>
      old.timeMs != timeMs ||
      old.strength != strength ||
      old.preset != preset ||
      old.dark != dark ||
      old.hot != hot ||
      old.hotAmt != hotAmt ||
      old.dpr != dpr ||
      old.glow != glow;
}

/// 一个像素一份中间量：复用同一个实例，免得逐像素建对象
class _Field {
  double dir = 0;
  double bump = 0;
  double edge = 0;
  double diagTL = 0;
  double stripeR = 0;
  double stripeG = 0;
  double stripeB = 0;
  double w0 = 0;
  double w1 = 0;
  double w2 = 1;
  double px = 0;
  double py = 0;
  double c0 = 0;
  double c1 = 0;
  double c2 = 0;
}
