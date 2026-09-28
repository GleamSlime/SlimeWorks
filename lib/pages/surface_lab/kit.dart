/// 表面实验室的本地底座
///
/// 第三块参考页，和动效实验室 / 交互实验室同一定位：**看的东西，不是用的东西**。
/// 这一页复刻一组"表面怎么动"的组件——浮层、悬浮面板、金属钮、灵动岛、折叠区、
/// 形变面板、镂空卡、文字入场。颜色/圆角/字号/曲线全部在这份文件里自带一份，
/// 不读 `AppTheme` / `AppSemantic` / `AppMotion`，也不往主题里写任何东西。
///
/// 尺寸一律字面 px，不吃 `scaleW`：参考稿的量是逻辑像素 1:1，乘上窗口缩放
/// 就不是还原了。这条例外只圈在 `lib/pages/surface_lab/**`。
library;

import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:typed_data' show Float64List;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart' show PointerDeviceKind, TapUpDetails;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:path_drawing/path_drawing.dart';

import 'package:flutter/material.dart';

/// 参考稿的浅色盘（`:root` 的 `--*` 原值，站点是 shadcn 那一套灰阶）
abstract final class SvColor {
  /// `--foreground`
  static const fg = Color(0xFF0A0A0A);

  /// `--primary`：实心钮的底
  static const primary = Color(0xFF171717);
  static const onPrimary = Color(0xFFFAFAFA);

  /// `--muted` / `--muted-foreground`
  static const muted = Color(0xFFF5F5F5);
  static const mutedFg = Color(0xFF737373);

  /// `--border` / `--input` / `--ring`
  static const border = Color(0xFFE5E5E5);
  static const ring = Color(0xFFA1A1A1);

  /// `--background` / `--card` / `--popover`：站点这三档都是纯白
  static const pane = Color(0xFFFFFFFF);
  static const text = fg;
  static const textMuted = mutedFg;

  /// `--destructive`
  static const destructive = Color(0xFFE40014);

  /// 舞台底：参考稿的 preview 区是**透明**的（组件直接坐在白页上靠投影分层），
  /// 所以这一档不是量出来的，是我们自己的铺垫 —— 用 `--muted` 那一档灰，
  /// 好让白色的浮层在这页上至少有一层边界可读。
  static const stage = muted;
}

/// 参考稿的暗色档（`.dark`）：只有个别格子是暗的，单开一份、不去动 [SvColor]
abstract final class SvDarkColor {
  static const bg = Color(0xFF0A0A0A);
  static const fg = Color(0xFFFAFAFA);
  static const surface = Color(0xFF171717);
  static const muted = Color(0xFF262626);
  static const mutedFg = Color(0xFFA1A1A1);

  /// `--border` = `#ffffff1a`：白描边压在深底上
  static const border = Color(0x1AFFFFFF);
  static const text = fg;
  static const textMuted = mutedFg;
}

abstract final class SvFont {
  /// 参考稿正文是 GeistSans，仓库里没有这份字面；沿用交互实验室那档 Inter，
  /// 三块参考页至少彼此是同一套字，量像素时也不会多出字形差
  static const family = 'Inter';

  /// Inter 里没有中文字形：真机靠系统兜底，离屏出图直接是豆腐块。
  /// 显式挂一档中文，两边看到的是同一套字。
  static const fallback = <String>['PingFang SC'];

  static const tabular = <FontFeature>[FontFeature.tabularFigures()];
}

/// 参考稿用到的曲线
abstract final class SvEase {
  /// shadcn 那套 `cubic-bezier(.4,0,.2,1)`
  static const standard = Cubic(0.4, 0, 0.2, 1);

  /// `cubic-bezier(0.23, 1, 0.32, 1)`：浮层/面板的"顺出"
  static const smoothOut = Cubic(0.23, 1, 0.32, 1);

  /// `cubic-bezier(.16,1,.3,1)`：更陡的 expo-out
  static const expoOut = Cubic(0.16, 1, 0.3, 1);

  static const inOut = Cubic(0.45, 0, 0.55, 1);

  static const linear = Cubic(0, 0, 1, 1);
}

/// 卡片外壳：舞台四周留 12，标题块压在舞台下面（和交互实验室同一套铺垫尺寸）
abstract final class SvSize {
  static const gutter = 12.0;
  static const cardRadius = 24.0;
  static const stageRadius = 28.0;

  /// 整页统一一档舞台尺寸；量出来更宽/更高的格子自己报
  static const stageW = 372.0;
  static const stageH = 232.0;

  /// 标题 + 副标题那一块的高度（含与舞台的 12 间距）
  static const headH = 62.0;

  /// `--radius` = .625rem：参考稿的 `rounded-lg/md/sm` 都从这一档派生
  static const radius = 10.0;

  static double cardW([double w = stageW]) => w + gutter * 2;
  static double cardH([double h = stageH]) => h + gutter * 2 + headH;
}

abstract final class SvShadow {
  /// 1px 边框环（`--border`）：参考稿的白色表面全靠这一圈在灰舞台上分层
  static const ring = BoxShadow(color: SvColor.border, blurRadius: 0, spreadRadius: 1);

  /// 浮层（`--popover`）那档投影：站点用的是 shadcn 的两层
  static const material = <BoxShadow>[
    BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 4)),
    BoxShadow(color: Color(0x0F000000), blurRadius: 3, offset: Offset(0, 1)),
    ring,
  ];

  static const card = <BoxShadow>[
    BoxShadow(color: Color(0x0A000000), blurRadius: 3, offset: Offset(0, 1)),
    ring,
  ];
}

/// 参考稿的文字档位（16px 根字号，组件里各档另给）
abstract final class SvText {
  static const body = TextStyle(
    fontFamily: SvFont.family,
    fontFamilyFallback: SvFont.fallback,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 20 / 14,
    color: SvColor.text,
  );

  static const title = TextStyle(
    fontFamily: SvFont.family,
    fontFamilyFallback: SvFont.fallback,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 20 / 14,
    color: SvColor.text,
  );

  static const subtitle = TextStyle(
    fontFamily: SvFont.family,
    fontFamilyFallback: SvFont.fallback,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1,
    color: SvColor.mutedFg,
  );

  static const muted = TextStyle(
    fontFamily: SvFont.family,
    fontFamilyFallback: SvFont.fallback,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 18 / 13,
    color: SvColor.mutedFg,
  );
}

/// 触屏手势抢滚动的临时锁
///
/// 跟手拖的格子用的是 `Listener`（要 CSS `setPointerCapture` 那种"按住就是我的"
/// 语义），而 `Listener` 不进手势竞技场 —— 触屏上位移一过 slop，页面外层那颗
/// `SingleChildScrollView` 照样把整页一起拖走。于是接管手指的格子在按住期间给
/// 这里 +1、松手 -1；页面读到非零就把滚动物理换成 `NeverScrollableScrollPhysics`。
/// 桌面端鼠标走滚轮，计数挂着也不改变手感。
abstract final class SvTouchLock {
  static final ValueNotifier<int> held = ValueNotifier<int>(0);

  static void acquire() => held.value = held.value + 1;

  static void release() => held.value = math.max(0, held.value - 1);
}

/// 这一格要不要挂软键盘那套真输入
///
/// 靠 `Focus.onKeyEvent` 自己收键的假输入只吃物理键盘：触屏上 `requestFocus()`
/// 什么也不弹，得压一颗全透明 `TextField` 接管焦点，让系统把键盘弹出来。
/// 只在安卓/iOS 挂，桌面不挂 —— 桌面走原来那条 `Focus` 路径，golden 一像素不动。
abstract final class SvTouch {
  static final bool softKeyboard = Platform.isAndroid || Platform.isIOS;
}

/// 指尖那一格的下限（Material 那条 44）
const svTapMinSide = 44.0;

EdgeInsets _tapPadGrow(Rect face, EdgeInsets? grow, double minSide) {
  return grow ??
      EdgeInsets.fromLTRB(
        math.max(0.0, (minSide - face.width) / 2),
        math.max(0.0, (minSide - face.height) / 2),
        math.max(0.0, (minSide - face.width) / 2),
        math.max(0.0, (minSide - face.height) / 2),
      );
}

/// 把脸那一格凑到指尖下限：短边不足 [minSide] 就四边对半分探出去
///
/// 给了 [grow] 就照 [grow] 探（邻居挤在一起时用它收着扩，别越过圆心距）。
Rect svTapPadOf(Rect face, {EdgeInsets? grow, double minSide = svTapMinSide}) {
  final g = _tapPadGrow(face, grow, minSide);
  return Rect.fromLTWH(
    face.left - g.left,
    face.top - g.top,
    face.width + g.left + g.right,
    face.height + g.top + g.bottom,
  );
}

/// 一圈拆成四条互不重叠的带子：[pad] 是整格（脸加外扩）、[face] 是脸，两者都在
/// 宿主那一层里量，四条拼起来正好是整格减去那张脸
///
/// 带子不能压在脸上：受理区多一个抢 tap 的识别器，脸自己的按下就得等竞技场
/// 分出胜负才响（松手那一刻），按住的高亮慢半拍。各占各的点才谁也不抢谁。
List<Positioned> svTapBands(Rect pad, Rect face, VoidCallback onTap, {String tag = 'pad'}) {
  Positioned band(String id, Rect r) => Positioned(
    key: ValueKey<String>('sv-tap-$tag-$id'),
    left: r.left,
    top: r.top,
    width: r.width,
    height: r.height,
    // `opaque`：带子里没有孩子，`deferToChild` 的话整块都是空的、一笔也收不到
    child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap),
  );

  final above = face.top - pad.top;
  final below = pad.bottom - face.bottom;
  final left = face.left - pad.left;
  final right = pad.right - face.right;
  return [
    if (above > 0) band('top', Rect.fromLTWH(pad.left, pad.top, pad.width, above)),
    if (below > 0) band('bottom', Rect.fromLTWH(pad.left, face.bottom, pad.width, below)),
    if (left > 0) band('left', Rect.fromLTWH(pad.left, face.top, left, face.height)),
    if (right > 0) band('right', Rect.fromLTWH(face.right, face.top, right, face.height)),
  ];
}

/// 压在脸底下的透明受理区：跟脸同一个 Stack、排在脸前面
///
/// 指尖按不准 16×32 那一格，而参考稿的观感一动就废，所以受理区只能另起一层，
/// 不去碰脸自己的盒子。[face] 是脸在宿主这一层里的坐标，探出去的量见 [svTapPadOf]。
///
/// 为什么不能用 `Stack(clipBehavior: Clip.none)` + `Positioned`（负 inset）把命中盒
/// 从脸外面探出去：`RenderBox.hitTest` 第一句就是拿自己的 `size` 判这个点在不在
/// 框里，祖先链上只要有一环没把这个点框住，事件压根走不到探出去
/// 那一层 —— 探出去的盒子只画不收，看着挺对、点上去是死的。所以受理区必须占一格
/// 真实布局，也就必须落在一个本来就这么大的宿主里。
///
/// 带子跟脸各占各的点：脸上那一下仍由脸自己接，落在脸外那一圈才归带子。
List<Widget> svTapPads({
  required Rect face,
  required VoidCallback onTap,
  EdgeInsets? grow,
  double minSide = svTapMinSide,
  String tag = 'pad',
}) {
  final pad = svTapPadOf(face, grow: grow, minSide: minSide);
  return svTapBands(pad, face, onTap, tag: tag);
}

/// 没有现成大宿主可借时的另一条路：让受理区当脸的外套，把这一格撑到 [grow] 那么大
///
/// 撑大的量要在旁边的空隙里如数扣回来（`gap`、行距都是现成的账），扣少了脸挪位、
/// 扣多了整块跟着长 —— 两边都得填一样的数，观感才一格不动。圆心距是上限：一张脸
/// 能探多远，由它跟邻脸之间那点缝决定，探过中线就变成抢邻脸的点。
///
/// 外扩那一圈拆成四条互不重叠的带子，而不是在脸外面再套一层 `GestureDetector`：
/// 多一个抢 tap 的识别器，脸自己的按下就要等仲裁分出胜负才发，按下的高慢半拍。
/// 带子跟脸各占各的点，谁也不抢谁。
class SvTapGrow extends StatelessWidget {
  const SvTapGrow({
    super.key,
    required this.grow,
    required this.onTap,
    required this.child,
  });

  final EdgeInsets grow;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 上下两条通铺（连两个角一起收），左右两条只占中段：四条拼起来正好是那圈，
    // 一格也不压在脸上。`opaque`：带子里没有孩子，`deferToChild` 就一笔也收不到。
    Widget band(String id, {double? top, double? bottom, double? left, double? right, double? width, double? height}) =>
        Positioned(
          key: ValueKey('sv-tap-band-$id'),
          top: top,
          bottom: bottom,
          left: left,
          right: right,
          width: width,
          height: height,
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap),
        );

    final double t = grow.top, b = grow.bottom, l = grow.left, r = grow.right;
    return Stack(
      children: [
        Padding(padding: grow, child: child),
        if (t > 0) band('top', top: 0, left: 0, right: 0, height: t),
        if (b > 0) band('bottom', bottom: 0, left: 0, right: 0, height: b),
        if (l > 0) band('left', left: 0, top: t, bottom: b, width: l),
        if (r > 0) band('right', right: 0, top: t, bottom: b, width: r),
      ],
    );
  }
}

/// 触屏兼容的悬停区：只认 hover 的格子也给指尖一条路
///
/// 触屏没有 enter/exit，纯悬停驱动的格子在手机上等于点不动。鼠标一侧照旧走
/// `MouseRegion`，指尖点一下当作"指针进来并停在原地"、再点一下当作"离开"。
/// 只有触屏指针走这条路 —— 桌面上鼠标点击不改变悬停语义。
/// 传 [group] 时同组互斥：点第二块会先让占着的那块退场，不会两格同时悬停。
class SvHoverRegion extends StatefulWidget {
  const SvHoverRegion({
    super.key,
    required this.child,
    this.group,
    this.cursor = SystemMouseCursors.click,
    this.onEnter,
    this.onExit,
  });

  final Widget child;

  /// 互斥组的标识（同一格里共用一个字符串即可）
  final Object? group;
  final MouseCursor cursor;
  final VoidCallback? onEnter;
  final VoidCallback? onExit;

  @override
  State<SvHoverRegion> createState() => _SvHoverRegionState();
}

class _SvHoverRegionState extends State<SvHoverRegion> {
  /// 每组当前被指尖按住的实例（没给 group 就以自身为组）
  static final Map<Object, _SvHoverRegionState> _held = {};

  Object get _key => widget.group ?? this;

  void _tapUp(TapUpDetails d) {
    if (d.kind != PointerDeviceKind.touch) return;
    if (_held[_key] == this) {
      _held.remove(_key);
      widget.onExit?.call();
      return;
    }
    final previous = _held.remove(_key);
    if (previous != null && previous.mounted) previous.widget.onExit?.call();
    _held[_key] = this;
    widget.onEnter?.call();
  }

  @override
  void dispose() {
    if (_held[_key] == this) _held.remove(_key);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => widget.onEnter?.call(),
      onExit: (_) => widget.onExit?.call(),
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTapUp: _tapUp, child: widget.child),
    );
  }
}

/// 舞台：尺寸由格子自己报，圆角 28，内容默认裁在里面
class SvStage extends StatelessWidget {
  const SvStage({
    super.key,
    required this.child,
    this.width = SvSize.stageW,
    this.height = SvSize.stageH,
    this.center = true,
    this.clip = true,
    this.dark = false,
    this.color,
    this.padding,
  });

  final Widget child;
  final double width;
  final double height;

  /// 参考稿的组件一律坐在 preview 正中，格子默认不用自己定位；
  /// 浮层要探出舞台的格子改成 false 自己摆
  final bool center;

  /// 浮层/阴影要探出舞台的格子把这档关掉，否则拍到的是切了一半的气泡
  final bool clip;

  /// 暗色档：只换舞台底色，组件自己的颜色各格自带
  final bool dark;

  /// 换舞台底色：组件自己就带一档 `--muted` 灰的格子，舞台再灰一档那圈框就没了
  final Color? color;

  /// preview 区自带 padding（参考稿是 `p-8` = 32），格子按量出来的值给
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: padding ?? EdgeInsets.zero,
      child: center ? Center(child: child) : child,
    );
    final stage = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color ?? (dark ? SvDarkColor.bg : SvColor.stage),
        borderRadius: const BorderRadius.all(Radius.circular(SvSize.stageRadius)),
      ),
      // 必须自己钉一层默认字样式：舞台外面没有 Material，`Text` 会去接
      // MaterialApp 那份兜底样式——黄色双下划线，专门提醒"把文字放进 Material"
      child: DefaultTextStyle(style: SvText.body, child: body),
    );
    return clip
        ? ClipRRect(borderRadius: BorderRadius.circular(SvSize.stageRadius), child: stage)
        : stage;
  }
}

/// 案例卡片：舞台 + 标题/副标题 + 右下角放大钮
class SvCard extends StatelessWidget {
  const SvCard({
    super.key,
    required this.seq,
    required this.title,
    required this.subtitle,
    required this.stage,
    this.onEnlarge,
    this.stageW = SvSize.stageW,
    this.stageH = SvSize.stageH,
    this.dark = false,
  });

  final int seq;
  final String title;
  final String subtitle;
  final Widget stage;
  final VoidCallback? onEnlarge;
  final double stageW;
  final double stageH;

  /// 这一格是不是暗色档（外壳跟着翻，不影响别的格子）
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final text = dark ? SvDarkColor.text : SvColor.text;
    final subtle = dark ? SvDarkColor.textMuted : SvColor.mutedFg;
    return SizedBox(
      width: SvSize.cardW(stageW),
      height: SvSize.cardH(stageH),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: dark ? SvDarkColor.surface : SvColor.pane,
          borderRadius: const BorderRadius.all(Radius.circular(SvSize.cardRadius)),
          boxShadow: const [SvShadow.ring],
        ),
        child: DefaultTextStyle(
          style: SvText.body,
          child: Stack(
            children: [
              Positioned(left: SvSize.gutter, top: SvSize.gutter, child: stage),
              Positioned(
                left: SvSize.gutter + 4,
                top: SvSize.gutter + stageH + 12,
                right: SvSize.gutter + 44,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$seq. $title',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SvText.title.copyWith(color: text),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SvText.subtitle.copyWith(color: subtle),
                    ),
                  ],
                ),
              ),
              if (onEnlarge != null)
                Positioned(
                  right: SvSize.gutter + 4,
                  bottom: SvSize.gutter + 4,
                  child: SvIconButton(onTap: onEnlarge!, dark: dark),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 卡片右下角的放大钮：36 圆，150ms 换底色
class SvIconButton extends StatefulWidget {
  const SvIconButton({super.key, required this.onTap, this.dark = false});

  final VoidCallback onTap;
  final bool dark;

  @override
  State<SvIconButton> createState() => _SvIconButtonState();
}

class _SvIconButtonState extends State<SvIconButton> {
  bool _hov = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: SvEase.standard,
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _hov
                ? (widget.dark ? SvDarkColor.muted : const Color(0xFFEDEDED))
                : (widget.dark ? SvDarkColor.bg : SvColor.pane),
            shape: BoxShape.circle,
            boxShadow: const [SvShadow.ring],
          ),
          child: Icon(
            Icons.open_in_full_rounded,
            size: 16,
            color: widget.dark ? SvDarkColor.text : SvColor.text,
          ),
        ),
      ),
    );
  }
}

/// 逐帧弹簧：和交互实验室同一套两条积分路（帧模式 k/d、物理模式 stiffness/damping）
///
/// 做成 `ChangeNotifier` 是为了让出图可复现：假异步里每帧 `pump(16ms)` 喂进来一个
/// 确定的 dt，弹簧轨迹就是一定的，不依赖真实时间。
class SvSpring extends ChangeNotifier {
  SvSpring({required this.k, required this.d, double from = 0, this.rest = 0.02})
      : _x = from,
        _stiffness = 0,
        _damping = 0,
        _mass = 1;

  /// 物理弹簧：数值直接抄参考稿的 `{stiffness, damping, mass}`
  ///
  /// `rest` 在这里是**位置**阈值（px），速度阈值按 1/60 换算过去。
  SvSpring.phys({
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

  /// 换弹簧参数：同一个量在不同动作下会换阻尼
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

  bool _settled(double target) => (target - _x).abs() < rest && _v.abs() < (rest * 60);

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
class SvSpringDrive extends StatefulWidget {
  const SvSpringDrive({super.key, required this.spring, required this.builder});

  final SvSpring spring;
  final Widget Function(BuildContext context) builder;

  @override
  State<SvSpringDrive> createState() => _SvSpringDriveState();
}

class _SvSpringDriveState extends State<SvSpringDrive> with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    widget.spring.addListener(_onSpring);
  }

  @override
  void didUpdateWidget(SvSpringDrive old) {
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
    // 不重启弹簧就永远停在第二次动作的起点
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

/// 值到值的补间（0→1 进度、透明度、模糊半径都走它）
///
/// 不能用 `TweenAnimationBuilder`：它只在 `begin != end` 时才起钟，首帧两个值
/// 常常都是 0，等下一帧把目标换成 1，钟已经不会再转了。
class SvTween extends StatefulWidget {
  const SvTween({
    super.key,
    required this.target,
    required this.duration,
    required this.builder,
    this.curve = SvEase.smoothOut,
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
  State<SvTween> createState() => _SvTweenState();
}

class _SvTweenState extends State<SvTween> with SingleTickerProviderStateMixin {
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
  void didUpdateWidget(SvTween old) {
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

/// CSS `filter: blur(σ) contrast(c)` 的融合层（形变/拉丝那一类要用）
class SvGoo extends StatelessWidget {
  const SvGoo({
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

/// 参考稿的图标就是内联 svg：`viewBox` + `stroke-width` + `currentColor`
class SvIcon extends StatelessWidget {
  const SvIcon({
    super.key,
    required this.paths,
    this.size = 16,
    this.viewBox = 24,
    this.strokeWidth = 2,
    this.color = SvColor.text,
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
      painter: _SvIconPainter(
        paths: [for (final d in paths) _parse(d)],
        scale: size / viewBox,
        strokeWidth: strokeWidth,
        color: color,
        filled: filled,
      ),
    );
  }
}

class _SvIconPainter extends CustomPainter {
  const _SvIconPainter({
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
  bool shouldRepaint(_SvIconPainter old) =>
      old.scale != scale ||
      old.strokeWidth != strokeWidth ||
      old.color != color ||
      old.filled != filled ||
      !listEquals(old.paths, paths);
}
