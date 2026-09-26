/// 动效实验室的本地底座
///
/// 这一页是**外部参考稿的复刻**，不是产品界面，所以它故意不带全局属性：
/// 颜色、圆角、字号、时长、曲线全部在这份文件里各存一份，取自参考稿的原始值。
/// 不读 `AppTheme` / `AppSemantic` / `AppMotion`，也不往主题里写任何东西——
/// 全站换肤、字号比例、磨砂档位都不该改变这张页面上"参考稿长什么样"这件事。
///
/// 尺寸同理：参考稿的量是**逻辑像素 1:1**，这里直接写字面量，不吃窗口缩放。
/// 一旦乘上 `scaleW`，1440 窗口下整套尺寸会缩到 75%，那就不是像素级还原了。
library;

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:path_drawing/path_drawing.dart';

import 'package:flutter/material.dart';

/// 参考稿的浅色盘（`--*` 变量原值）
abstract final class LabColor {
  static const page = Color(0xFFFDFDFD);
  static const card = Color(0xFFFFFFFF);
  static const stage = Color(0xFFF9F9F9);
  static const text = Color(0xFF0D0D0D);
  static const textMuted = Color(0xFF6C6C6C);
  static const textSubtle = Color(0xFF767676);
  static const textFaint = Color(0xFF8F8F8F);
  static const animateText = Color(0xFF17181C);
  static const chip = Color(0xFFF4F4F4);
  static const chipHover = Color(0xFFF1F1F1);
  static const chipPressed = Color(0xFFEAE9E9);
  static const skeleton = Color(0xFFEEEEEF);
  static const slate = Color(0xFF5E6073); // --muted / --label-mono
  static const border = Color(0x0F000000); // rgba(0,0,0,.06)
  static const stageBorder = Color(0x0A000000); // rgba(0,0,0,.04)
  static const iconMuted = Color(0x990D0D0D); // rgba(13,13,13,.6)
  static const danger = Color(0xFFE5484D);
  static const success = Color(0xFF30A46C);
  static const accent = Color(0xFF3B6EF6);
}

abstract final class LabFont {
  static const family = 'Inter';

  /// Inter 里没有中文字形：真机靠系统兜底，离屏出图直接是豆腐块。
  /// 显式挂一档中文，两边看到的是同一套字。
  static const fallback = <String>['PingFang SC'];

  /// 参考稿的数字用等宽字形（Roboto Mono）；这里用 Inter 的 tabular figures 顶，
  /// 目的是**滚动时每一位不跳宽**，而不是换字形观感。
  static const tabular = <FontFeature>[FontFeature.tabularFigures()];
}

/// 参考稿用到的曲线，名字沿用它的叫法
abstract final class LabEase {
  /// `--*-ease: cubic-bezier(0.22, 1, 0.36, 1)`——全站默认的"顺出"
  static const smoothOut = Cubic(0.22, 1, 0.36, 1);

  /// 带一点过冲的弹（`cubic-bezier(0.34, 1.36, 0.64, 1)`）
  static const pop = Cubic(0.34, 1.36, 0.64, 1);

  /// 材料标准曲线（`cubic-bezier(0.4, 0, 0.2, 1)`），多用于**退场**
  static const standard = Cubic(0.4, 0, 0.2, 1);

  static const inOut = Cubic(0.42, 0, 0.58, 1);
  static const linear = Cubic(0, 0, 1, 1);
}

/// 卡片外壳的固定尺寸（参考稿 `.card` / `.card-stage` 原值）
abstract final class LabSize {
  static const cardW = 320.0;
  static const cardH = 344.0;
  static const cardRadius = 24.0;
  static const cardPadX = 20.0;

  /// 舞台：案例自己的画布，左上角在卡片内 (12, 12)
  static const stageW = 296.0;
  static const stageH = 260.0;
  static const stageRadius = 14.0;

  static const animateBtnH = 36.0;
}

abstract final class LabShadow {
  /// `.card`：一层极淡投影 + 1px 内描边
  static const card = <BoxShadow>[
    BoxShadow(color: Color(0x0A000000), blurRadius: 3, offset: Offset(0, 1)),
    BoxShadow(color: border, blurRadius: 0, spreadRadius: 1),
  ];

  /// `--material-shadow`：浮层/菜单/面板用的三层
  static const material = <BoxShadow>[
    BoxShadow(color: Color(0x0F000000), blurRadius: 42, offset: Offset(0, 4)),
    BoxShadow(color: Color(0x0D000000), blurRadius: 6, offset: Offset(0, 2)),
    BoxShadow(color: border, blurRadius: 0, spreadRadius: 1),
  ];

  static const border = LabColor.border;
}

/// 参考稿的文字档位
abstract final class LabText {
  static const title = TextStyle(
    fontFamily: LabFont.family,
    fontFamilyFallback: LabFont.fallback,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 18 / 13,
    color: LabColor.text,
  );

  static const subtitle = TextStyle(
    fontFamily: LabFont.family,
    fontFamilyFallback: LabFont.fallback,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1,
    color: LabColor.textSubtle,
  );

  static const body = TextStyle(
    fontFamily: LabFont.family,
    fontFamilyFallback: LabFont.fallback,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 18 / 13,
    color: LabColor.text,
  );

  static const muted = TextStyle(
    fontFamily: LabFont.family,
    fontFamilyFallback: LabFont.fallback,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 18 / 13,
    color: LabColor.slate,
  );

  static const label = TextStyle(
    fontFamily: LabFont.family,
    fontFamilyFallback: LabFont.fallback,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 14 / 11,
    color: LabColor.textSubtle,
  );

  static const number = TextStyle(
    fontFamily: LabFont.family,
    fontFamilyFallback: LabFont.fallback,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: LabColor.text,
    fontFeatures: LabFont.tabular,
  );
}

/// 舞台：固定 296×260、圆角 14、`#f9f9f9` 底 + 1px 内描边，内容裁在里面
class LabStage extends StatelessWidget {
  const LabStage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(LabSize.stageRadius),
      child: Container(
        width: LabSize.stageW,
        height: LabSize.stageH,
        decoration: const BoxDecoration(
          color: LabColor.stage,
          borderRadius: BorderRadius.all(Radius.circular(LabSize.stageRadius)),
        ),
        child: child,
      ),
    );
  }
}

/// 案例卡片：舞台 + 标题/副标题（参考稿 `.card` 的版式）
class LabCard extends StatelessWidget {
  const LabCard({
    super.key,
    required this.seq,
    required this.title,
    required this.subtitle,
    required this.stage,
    this.pro = false,
    this.onEnlarge,
  });

  final int seq;
  final String title;
  final String subtitle;
  final Widget stage;
  final bool pro;

  /// 右下角那颗圆钮：把这一格放大单看
  final VoidCallback? onEnlarge;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: LabSize.cardW,
      height: LabSize.cardH,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: LabColor.card,
          borderRadius: BorderRadius.all(Radius.circular(LabSize.cardRadius)),
          boxShadow: LabShadow.card,
        ),
        child: Stack(
          children: [
            Positioned(
              left: 12,
              top: 12,
              child: stage,
            ),
            Positioned(
              left: LabSize.cardPadX,
              bottom: 20,
              // 右边给圆钮让出 44
              right: LabSize.cardPadX + 44,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$seq. $title${pro ? '  ·  Pro' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LabText.title,
                  ),
                  const SizedBox(height: 6),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: LabText.subtitle),
                ],
              ),
            ),
            if (onEnlarge != null)
              Positioned(
                right: LabSize.cardPadX,
                bottom: 16,
                child: LabIconButton(onTap: onEnlarge!, icon: Icons.open_in_full_rounded),
              ),
          ],
        ),
      ),
    );
  }
}

/// 参考稿的 `.btn-animate`：36 高药丸，150ms 换底色
class LabAnimateButton extends StatefulWidget {
  const LabAnimateButton({
    super.key,
    required this.label,
    required this.onTap,
    this.dark = false,
  });

  final String label;
  final VoidCallback onTap;

  /// 深色底（如实心黑按钮）上换成浅底深字的对色
  final bool dark;

  @override
  State<LabAnimateButton> createState() => _LabAnimateButtonState();
}

class _LabAnimateButtonState extends State<LabAnimateButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bg = _pressed
        ? LabColor.chipPressed
        : _hovered
              ? LabColor.chipHover
              : LabColor.chip;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.ease,
          height: LabSize.animateBtnH,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: widget.dark ? LabColor.card : bg,
            borderRadius: BorderRadius.circular(40),
          ),
          child: Center(
            child: Text(
              widget.label,
              style: LabText.title.copyWith(
                fontWeight: FontWeight.w500,
                height: 16 / 13,
                color: widget.dark ? LabColor.text : LabColor.animateText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 卡片右下角那枚 36 圆钮（参考稿 `.card-copy` 的位置和尺寸）
class LabIconButton extends StatefulWidget {
  const LabIconButton({super.key, required this.onTap, required this.icon});

  final VoidCallback onTap;
  final IconData icon;

  @override
  State<LabIconButton> createState() => _LabIconButtonState();
}

class _LabIconButtonState extends State<LabIconButton> {
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
            color: _hovered ? LabColor.chipHover : LabColor.chip,
            shape: BoxShape.circle,
          ),
          child: Icon(
            widget.icon,
            size: 16,
            color: _hovered ? LabColor.text : LabColor.iconMuted,
          ),
        ),
      ),
    );
  }
}

/// 舞台底部居中的控制条（参考稿把 `.btn-animate` 钉在 stage 内 bottom:20）
class LabStageFooter extends StatelessWidget {
  const LabStageFooter({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 20,
      child: Center(
        child: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: children,
        ),
      ),
    );
  }
}

/// 内容模糊：对应 CSS 的 `filter: blur(Npx)`
///
/// 参考稿里"换内容"的动作几乎都带一下模糊（2px 起），且**必须落到 0**，
/// 停在半模糊状态就不是转场而是没加载完。
class LabBlur extends StatelessWidget {
  const LabBlur({super.key, required this.sigma, required this.child});

  final double sigma;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (sigma <= 0.01) return child;
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal),
      child: child,
    );
  }
}

/// 一个跟着 `target` 走的 0→1 进度
///
/// 案例里最常见的形状就是"状态一翻，几个属性各自补间"。这里把发帧统一掉，
/// 时长/曲线由调用方按参考稿的 token 给；开和收时长不同就分两次传。
class LabTween extends StatefulWidget {
  const LabTween({
    super.key,
    required this.target,
    required this.duration,
    required this.builder,
    this.curve = LabEase.smoothOut,
  });

  /// 0 或 1（也可以停在中间值做步进）
  final double target;
  final Duration duration;
  final Curve curve;
  final Widget Function(BuildContext context, double t) builder;

  @override
  State<LabTween> createState() => _LabTweenState();
}

class _LabTweenState extends State<LabTween> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: widget.target,
  );

  @override
  void initState() {
    super.initState();
    _c.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(LabTween old) {
    super.didUpdateWidget(old);
    if (old.duration != widget.duration) _c.duration = widget.duration;
    if (old.target != widget.target) {
      _c.animateTo(widget.target.clamp(0.0, 1.0), curve: widget.curve);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _c.value);
}

/// 参考稿的图标就是内联 svg：`viewBox` + `stroke-width` + `currentColor`。
/// 这里用同样的画法（描边 path），不引第二套图标资产，
/// 这样每一格的图标粗细、端点都和参考稿对得上。
class LabIcon extends StatelessWidget {
  const LabIcon({
    super.key,
    required this.paths,
    this.size = 16,
    this.viewBox = 16,
    this.strokeWidth = 1.5,
    this.color = LabColor.text,
    this.filled = false,
  });

  /// svg 的 `d` 字符串，按原顺序画
  final List<String> paths;
  final double size;

  /// svg 的 viewBox 边长（参考稿只有 16/24 两档，等比缩放）
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
      painter: _LabIconPainter(
        paths: [for (final d in paths) _parse(d)],
        scale: size / viewBox,
        strokeWidth: strokeWidth,
        color: color,
        filled: filled,
      ),
    );
  }
}

class _LabIconPainter extends CustomPainter {
  const _LabIconPainter({
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
  bool shouldRepaint(_LabIconPainter old) =>
      old.scale != scale ||
      old.strokeWidth != strokeWidth ||
      old.color != color ||
      old.filled != filled ||
      old.paths != paths;
}

/// CSS `linear-gradient(<angle>deg, ...)` → Flutter 渐变
///
/// CSS 的 0deg 朝上、顺时针为正，Flutter 用的是 Alignment 坐标，两者差一次换算；
/// 参考稿的红色徽标写的是 -51.52deg，换算错一位底色就会往反方向压过去。
LinearGradient labLinearGradient(
  double cssAngleDeg,
  List<Color> colors, {
  List<double>? stops,
}) {
  final a = cssAngleDeg * math.pi / 180;
  final dx = math.sin(a);
  final dy = -math.cos(a);
  return LinearGradient(
    begin: Alignment(-dx, -dy),
    end: Alignment(dx, dy),
    colors: colors,
    stops: stops,
  );
}
