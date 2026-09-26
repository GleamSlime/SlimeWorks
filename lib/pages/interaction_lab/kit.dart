/// 交互实验室的本地底座
///
/// 和动效实验室同一定位：**看的东西，不是用的东西**。这一页复刻一组交互组件
/// （按住拖拽、下拉刷新、滑动确认、验证码融合……），它们自带一整套量出来的
/// 字面像素、时长和弹簧参数，所以颜色/圆角/字号/曲线全部在这份文件里自带一份。
/// 不读 `AppTheme` / `AppSemantic` / `AppMotion`，也不往主题里写任何东西。
///
/// 尺寸一律字面 px，不吃 `scaleW`：参考稿的量是逻辑像素 1:1，乘上窗口缩放
/// 就不是还原了。这条例外只圈在 `lib/pages/interaction_lab/**`。
library;

import 'dart:math' as math;
import 'dart:typed_data' show Float64List;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:path_drawing/path_drawing.dart';

import 'package:flutter/material.dart';

/// 参考稿的浅色盘（`:root` 的 `--*` 原值，`[data-theme=light]` 生效档）
abstract final class IlColor {
  /// `--ink`
  static const ink = Color(0xFF17181A);
  static const ink2 = Color(0xFF3C3B37);
  static const ink3 = Color(0xFF5C5B56);
  static const ink4 = Color(0xFF6F6E68);
  static const ink5 = Color(0xFF85847E);

  /// `--board` / `--pane`（flat 档解析为纯白）
  static const pane = Color(0xFFFFFFFF);
  /// `--card`
  static const card = Color(0xFFF7F7F6);
  /// `--pane-edge`：rgba(23,24,26,.08)
  static const paneEdge = Color(0x1417181A);
  /// 舞台底 `.dtl-block`：rgba(23,24,26,.06)
  static const stage = Color(0x0F17181A);

  static const page = Color(0xFFFFFFFF);
  static const text = ink;
  static const textMuted = ink3;
  static const textSubtle = ink4;

  /// 语义线色（`--*-line`）
  static const green = Color(0xFF12B055);
  static const orange = Color(0xFFE8552A);
  static const blue = Color(0xFF3B6EF6);
}

abstract final class IlFont {
  static const family = 'Inter';

  /// Inter 里没有中文字形：真机靠系统兜底，离屏出图直接是豆腐块。
  /// 显式挂一档中文，两边看到的是同一套字。
  static const fallback = <String>['PingFang SC'];

  static const tabular = <FontFeature>[FontFeature.tabularFigures()];
}

/// 参考稿用到的曲线
abstract final class IlEase {
  /// `cubic-bezier(.22,1,.36,1)`——默认的"顺出"
  static const smoothOut = Cubic(0.22, 1, 0.36, 1);

  /// `cubic-bezier(.22,.9,.28,1)`——形变/换尺寸那条
  static const morph = Cubic(0.22, 0.9, 0.28, 1);

  static const standard = Cubic(0.4, 0, 0.2, 1);
  static const linear = Cubic(0, 0, 1, 1);
}

/// 卡片外壳：舞台四周留 12，标题块压在舞台下面
abstract final class IlSize {
  static const gutter = 12.0;
  static const cardRadius = 24.0;
  static const stageRadius = 28.0;

  /// 整页统一一档舞台尺寸：最宽的那格（搜索展开 346）决定宽度，
  /// 高度给到能容下拉刷新和列表两格，卡片就不会参差不齐
  static const stageW = 372.0;
  static const stageH = 232.0;

  /// 标题 + 副标题那一块的高度（含与舞台的 12 间距）
  static const headH = 62.0;

  static double cardW([double w = stageW]) => w + gutter * 2;
  static double cardH([double h = stageH]) => h + gutter * 2 + headH;
}

abstract final class IlShadow {
  /// 浮层/菜单的三层投影
  static const material = <BoxShadow>[
    BoxShadow(color: Color(0x0F000000), blurRadius: 42, offset: Offset(0, 4)),
    BoxShadow(color: Color(0x0D000000), blurRadius: 6, offset: Offset(0, 2)),
    BoxShadow(color: IlColor.paneEdge, blurRadius: 0, spreadRadius: 1),
  ];

  static const card = <BoxShadow>[
    BoxShadow(color: Color(0x0A000000), blurRadius: 3, offset: Offset(0, 1)),
    BoxShadow(color: IlColor.paneEdge, blurRadius: 0, spreadRadius: 1),
  ];
}

/// 参考稿的文字档位（正文 18px / 行高 1.5 / 字距 -.005em 是页面级，组件里各档另给）
abstract final class IlText {
  static const body = TextStyle(
    fontFamily: IlFont.family,
    fontFamilyFallback: IlFont.fallback,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 18 / 13,
    letterSpacing: -0.005 * 13,
    color: IlColor.text,
  );

  static const title = TextStyle(
    fontFamily: IlFont.family,
    fontFamilyFallback: IlFont.fallback,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 18 / 13,
    letterSpacing: -0.005 * 13,
    color: IlColor.text,
  );

  static const subtitle = TextStyle(
    fontFamily: IlFont.family,
    fontFamilyFallback: IlFont.fallback,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1,
    color: IlColor.ink4,
  );

  static const muted = TextStyle(
    fontFamily: IlFont.family,
    fontFamilyFallback: IlFont.fallback,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 18 / 13,
    color: IlColor.ink3,
  );

  static const number = TextStyle(
    fontFamily: IlFont.family,
    fontFamilyFallback: IlFont.fallback,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: IlColor.text,
    fontFeatures: IlFont.tabular,
  );
}

/// 舞台：尺寸由格子自己报，圆角 28、`rgba(23,24,26,.06)` 底，内容裁在里面
class IlStage extends StatelessWidget {
  const IlStage({
    super.key,
    required this.child,
    this.width = IlSize.stageW,
    this.height = IlSize.stageH,
    this.center = true,
    this.clip = true,
  });

  final Widget child;
  final double width;
  final double height;

  /// 参考稿的组件一律坐在舞台正中（`.dtl-scale` 就是 translate(-50%,-50%)），
  /// 所以格子默认不用自己定位；浮层要探出舞台的格子改成 false 自己摆
  final bool center;

  /// 少数格子的浮层要探出舞台（参考稿 `.dtl-block` 是 overflow:hidden，
  /// 但组件级 demo 里画在舞台外的阴影/气泡得留着）
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final body = center ? Center(child: child) : child;
    final stage = Container(
      width: width,
      height: height,
      decoration: const BoxDecoration(
        color: IlColor.stage,
        borderRadius: BorderRadius.all(Radius.circular(IlSize.stageRadius)),
      ),
      // 必须自己钉一层默认字样式：舞台外面没有 Material，`Text` 会去接
      // MaterialApp 那份兜底样式——黄色双下划线，专门提醒"把文字放进 Material"
      child: DefaultTextStyle(style: IlText.body, child: body),
    );
    return clip
        ? ClipRRect(borderRadius: BorderRadius.circular(IlSize.stageRadius), child: stage)
        : stage;
  }
}

/// 案例卡片：舞台 + 标题/副标题
///
/// 尺寸跟着这一格的舞台走：下拉刷新那种量出来的卡片比 372×232 更高，硬塞进
/// 统一档位只能整体缩放，而缩放会把 2.1px 的曲线描边和刻度文字一起毁掉。
/// 不传就是 [IlSize.stageW]×[IlSize.stageH]，其余格子一点没变。
class IlCard extends StatelessWidget {
  const IlCard({
    super.key,
    required this.seq,
    required this.title,
    required this.subtitle,
    required this.stage,
    this.onEnlarge,
    this.stageW = IlSize.stageW,
    this.stageH = IlSize.stageH,
  });

  final int seq;
  final String title;
  final String subtitle;
  final Widget stage;
  final VoidCallback? onEnlarge;
  final double stageW;
  final double stageH;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: IlSize.cardW(stageW),
      height: IlSize.cardH(stageH),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: IlColor.pane,
          borderRadius: BorderRadius.all(Radius.circular(IlSize.cardRadius)),
          boxShadow: IlShadow.card,
        ),
        // 同 IlStage：卡片自己的标题也不该接到 MaterialApp 那份兜底样式上
        child: DefaultTextStyle(
          style: IlText.body,
          child: Stack(
            children: [
              Positioned(left: IlSize.gutter, top: IlSize.gutter, child: stage),
              Positioned(
                left: IlSize.gutter + 4,
                top: IlSize.gutter + stageH + 12,
                right: IlSize.gutter + 44,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$seq. $title',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: IlText.title,
                    ),
                    const SizedBox(height: 6),
                    Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: IlText.subtitle),
                  ],
                ),
              ),
              if (onEnlarge != null)
                Positioned(
                  right: IlSize.gutter + 4,
                  bottom: IlSize.gutter + 4,
                  child: IlIconButton(onTap: onEnlarge!, icon: Icons.open_in_full_rounded),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 卡片右下角的放大钮：36 圆，150ms 换底色
class IlIconButton extends StatefulWidget {
  const IlIconButton({super.key, required this.onTap, required this.icon});

  final VoidCallback onTap;
  final IconData icon;

  @override
  State<IlIconButton> createState() => _IlIconButtonState();
}

class _IlIconButtonState extends State<IlIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.ease,
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFFF1F1F1) : const Color(0xFFF4F4F4),
            shape: BoxShape.circle,
          ),
          child: Icon(
            widget.icon,
            size: 16,
            color: _hovered ? IlColor.text : IlColor.text.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

/// 半透明水洗：参考稿满屏都是 `rgba(23,24,26,.0x)`，直接给 alpha 十进制值
Color ilWash(double alpha, {Color over = IlColor.ink}) => over.withValues(alpha: alpha);

/// 弹簧：`v += (target - x) * k * dt; v *= d ** dt; x += v * dt`
///
/// 参考稿有两族弹簧，这里两条构造分别对应：
/// - 默认那条是**逐帧衰减**式（`k`/`d`）：`dt = 帧时长 / 16.67`，夹在 0..2.5；
///   **首帧固定 dt=1**（原稿 `last` 为空那一支）。收敛判据
///   `|target-x| < .02 且 |v| < .02` 时吸附并停钟。
/// - [IlSpring.phys] 是**物理**式（stiffness/damping/mass，单位 px、px/s、s）：
///   `a = (-stiffness·(x-target) - damping·v) / mass`。这一族要按秒积分，
///   而 stiffness=900 一档在 16ms 整步下会发散，所以内部固定 4ms 子步。
///
/// 做成 `ChangeNotifier` 是为了让出图可复现：假异步里每帧 `pump(16ms)` 喂进来一个
/// 确定的 dt，弹簧轨迹就是一定的，不依赖真实时间。
class IlSpring extends ChangeNotifier {
  IlSpring({required this.k, required this.d, double from = 0, this.rest = 0.02})
      : _x = from,
        _stiffness = 0,
        _damping = 0,
        _mass = 1;

  /// 物理弹簧：数值直接抄参考稿的 `{stiffness, damping, mass}`
  ///
  /// `rest` 在这里是**位置**阈值（px），速度阈值按 1/60 换算过去——
  /// 位置收敛时速度也该收敛，两族用同一个"停钟"口径。
  IlSpring.phys({
    required double stiffness,
    required double damping,
    double mass = 1,
    double from = 0,
    this.rest = 0.02,
  })  : _stiffness = stiffness,
        _damping = damping,
        _mass = mass,
        k = 0,
        d = 0,
        _x = from;

  final double k;
  final double d;
  double _stiffness;
  double _damping;
  double _mass;

  /// 收敛阈值（位移；物理弹簧还兼着换算速度阈值）
  final double rest;

  /// 换弹簧参数
  ///
  /// 参考稿里同一个量在不同动作下会换阻尼——滑到确认用 `2√(S·.9)`，
  /// 没到阈值弹回用它的 `.62` 倍（更弹）。只有一套 k/d 的弹簧表达不了这个。
  void retune({required double stiffness, required double damping, double mass = 1}) {
    _stiffness = stiffness;
    _damping = damping;
    _mass = mass;
  }

  bool get _isPhys => _stiffness > 0;

  double _x;
  double _v = 0;
  double _target = 0;
  bool _first = true;

  double get value => _x;

  /// 速度。逐帧式是 px/帧，物理式是 px/s
  double get velocity => _v;
  double get target => _target;
  bool get atRest => _atRest;
  bool _atRest = true;

  /// 换个目标；已经在收敛判据里就什么都不做
  void aim(double target) {
    _target = target;
    _atRest = _settled(target);
    _first = true;
    if (_atRest) {
      _x = target;
      _v = 0;
      notifyListeners();
      return;
    }
    notifyListeners();
  }

  bool _settled(double target) =>
      (target - _x).abs() < rest && _v.abs() < (rest * 60);

  /// 推进一帧，`elapsedMs` 是这一帧的真实时长
  void step(double elapsedMs) {
    if (_atRest) return;
    if (_isPhys) {
      _stepPhys(elapsedMs);
    } else {
      _stepFrame(elapsedMs);
    }
    if (_settled(_target)) {
      _x = _target;
      _v = 0;
      _atRest = true;
    }
    notifyListeners();
  }

  void _stepFrame(double elapsedMs) {
    final dt = _first ? 1.0 : (elapsedMs / 16.67).clamp(0.0, 2.5);
    _first = false;
    _v += (_target - _x) * k * dt;
    _v *= math.pow(d, dt);
    _x += _v * dt;
    if ((_target - _x).abs() < rest && _v.abs() < rest) {
      _x = _target;
      _v = 0;
      _atRest = true;
    }
    notifyListeners();
  }

  /// 物理弹簧按 4ms 子步积分：整帧 16ms 一步在 stiffness=900 那档会发散
  void _stepPhys(double elapsedMs) {
    _first = false;
    var left = elapsedMs;
    while (left > 0) {
      final h = (left > 4 ? 4.0 : left) / 1000.0;
      left -= h * 1000;
      final a = (-_stiffness * (_x - _target) - _damping * _v) / _mass;
      _v += a * h;
      _x += _v * h;
    }
  }

  /// 直接落位（初始态、或参考稿里"瞬移不补间"的那些时刻）
  void jumpTo(double x) {
    _x = x;
    _v = 0;
    _target = x;
    _atRest = true;
    _first = true;
    notifyListeners();
  }
}

/// 挂着弹簧发帧的外壳：`spring` 一动就重建，收敛了自动停钟
class IlSpringDrive extends StatefulWidget {
  const IlSpringDrive({super.key, required this.spring, required this.builder});

  final IlSpring spring;
  final Widget Function(BuildContext context) builder;

  @override
  State<IlSpringDrive> createState() => _IlSpringDriveState();
}

class _IlSpringDriveState extends State<IlSpringDrive> with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    widget.spring.addListener(_onSpring);
  }

  @override
  void didUpdateWidget(IlSpringDrive old) {
    super.didUpdateWidget(old);
    if (!identical(old.spring, widget.spring)) {
      old.spring.removeListener(_onSpring);
      widget.spring.addListener(_onSpring);
    }
  }

  void _onSpring() {
    setState(() {});
    if (widget.spring.atRest) {
      _ticker?.stop();
      return;
    }
    // 必须显式再 start：`??=` 只在第一回建表，之后表是停着的，
    // 不重启弹簧就永远停在第二次动作的起点（收起/返回那一下会整个不动）
    _ticker ??= createTicker(_tick);
    if (!_ticker!.isActive) {
      // 停过再起的 Ticker，喂给回调的 elapsed 从零重算，对表值得跟着归零，
      // 不然第一帧拿到的是"距上次起跑"的整个时长，弹簧一步就到底
      _last = Duration.zero;
      _ticker!.start();
    }
  }

  void _tick(Duration elapsed) {
    final dt = elapsed - _last;
    _last = elapsed;
    widget.spring.step(dt.inMilliseconds.toDouble());
  }

  @override
  void dispose() {
    _ticker?.stop();
    _ticker = null;
    widget.spring.removeListener(_onSpring);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

/// CSS `filter: blur(σ) contrast(c)` 的融合层——黏性/液滴效果的地基
///
/// 顺序不能换：先把形状糊开（`ImageFiltered`），再拉 alpha 斜坡
/// （`ColorFiltered`），临界带里两处 alpha 相加越过 0.5 就"接上"了。
/// 最后把原样形状补在上面，等价于 svg 的 `feComposite in=SourceGraphic atop`，
/// 否则内部会留下一片 0.5 alpha 的灰。
class IlGoo extends StatelessWidget {
  const IlGoo({
    super.key,
    required this.sigma,
    required this.contrast,
    required this.child,
    this.keepSource = true,
  });

  final double sigma;
  final double contrast;
  final Widget child;
  final bool keepSource;

  /// alpha' = contrast * (alpha - 0.5) + 0.5，**只动 alpha**。
  /// 颜色三行必须是单位阵：把 R/G/B 也乘成 0 的话，整层会变成纯黑剪影
  /// （色块层一旦有色差，比如药丸的暖白/抬起灰，就全丢了）。
  /// 注意矩阵的 alpha 平移列是 **0..255 未归一**，所以常数项要乘 255。
  static Float64List ramp(double contrast) {
    final b = ((1 - contrast) * 0.5) * 255;
    return Float64List.fromList([
      1, 0, 0, 0, 0, //
      0, 1, 0, 0, 0, //
      0, 0, 1, 0, 0, //
      0, 0, 0, contrast, b, //
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (sigma <= 0.01) return child;
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        ColorFiltered(
          colorFilter: ColorFilter.matrix(ramp(contrast)),
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal),
            child: child,
          ),
        ),
        if (keepSource) child,
      ],
    );
  }
}

/// 值到值的补间（0→1 进度、透明度、模糊半径都走它）
///
/// 不能用 `TweenAnimationBuilder`：它只在 `begin != end` 时才起钟，首帧两个值
/// 常常都是 0，等下一帧把目标换成 1，钟已经不会再转了。
class IlTween extends StatefulWidget {
  const IlTween({
    super.key,
    required this.target,
    required this.duration,
    required this.builder,
    this.curve = IlEase.smoothOut,
    this.fromCurrent = true,
  });

  final double target;
  final Duration duration;
  final Curve curve;

  /// true = 从当前显示值接着走（中途改目标不跳变）；
  /// false = 每次改目标都从 0 起（一次性入场/退场）
  final bool fromCurrent;

  final Widget Function(BuildContext context, double value) builder;

  @override
  State<IlTween> createState() => _IlTweenState();
}

class _IlTweenState extends State<IlTween> with SingleTickerProviderStateMixin {
  late double _from = widget.target;
  late double _shown = widget.target;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1.0,
  );

  @override
  void initState() {
    super.initState();
    _c.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(IlTween old) {
    super.didUpdateWidget(old);
    if (old.duration != widget.duration) _c.duration = widget.duration;
    if (old.target == widget.target) return;
    _from = widget.fromCurrent ? _shown : old.target;
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _shown = _from + (widget.target - _from) * widget.curve.transform(_c.value);
    return widget.builder(context, _shown);
  }
}

/// 参考稿的图标就是内联 svg：`viewBox` + `stroke-width` + `currentColor`。
/// 这里用同样的画法（描边 path），不引第二套图标资产，
/// 这样每一格的图标粗细、端点都和参考稿对得上。
class IlIcon extends StatelessWidget {
  const IlIcon({
    super.key,
    required this.paths,
    this.size = 16,
    this.viewBox = 16,
    this.strokeWidth = 1.5,
    this.color = IlColor.text,
    this.filled = false,
  });

  /// svg 的 `d` 字符串，按原顺序画
  final List<String> paths;
  final double size;
  final double viewBox;
  final double strokeWidth;
  final Color color;

  /// true = 实心填充，false = 描边（对应 svg 的 fill:none / stroke:currentColor）
  final bool filled;

  static final Map<String, Path> _cache = {};

  static Path _parse(String d) => _cache.putIfAbsent(d, () => parseSvgPathData(d));

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _IlIconPainter(
        paths: [for (final d in paths) _parse(d)],
        scale: size / viewBox,
        strokeWidth: strokeWidth,
        color: color,
        filled: filled,
      ),
    );
  }
}

class _IlIconPainter extends CustomPainter {
  const _IlIconPainter({
    required this.paths,
    required this.scale,
    required this.strokeWidth,
    required this.color,
    required this.filled,
  });

  final List<Path> paths;
  final double scale;
  final double strokeWidth;
  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(scale);
    final paint = Paint()
      ..color = color
      ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final p in paths) {
      canvas.drawPath(p, paint);
    }
  }

  @override
  bool shouldRepaint(_IlIconPainter old) =>
      old.scale != scale ||
      old.strokeWidth != strokeWidth ||
      old.color != color ||
      old.filled != filled ||
      !listEquals(old.paths, paths);
}
