import 'dart:ui' show ImageFilter, TileMode;

import 'package:flutter/scheduler.dart' show Ticker;

import 'package:flutter/material.dart';

import '../kit.dart';

/// 岛的五档形状。参考稿把 `width × aspectRatio` 摊成一张预设表，这里直接落终值
///
/// `large` 和 `long` 几何完全一样（371×84 r42），换的是内容不是形状；
/// `tall` 和 `medium` 也一样（371×210），差的是圆角 42 / 22。
enum SvIsle {
  /// 开场前那一档：参考稿的 `previousSize` 初值，宽高全 0
  empty(0, 0, 0, 'empty'),

  /// 挂上来的第一档，也是"没有匹配到内容"时的那一档
  def(150, 44, 46, 'default'),
  compact(235, 44, 46, 'compact'),
  large(371, 84, 42, 'large'),
  tall(371, 210, 42, 'tall'),
  long(371, 84, 42, 'long'),
  medium(371, 210, 22, 'medium');

  const SvIsle(this.w, this.h, this.r, this.label);

  final double w;
  final double h;
  final double r;

  /// 角标上要显示的就是参考稿那串预设名
  final String label;
}

/// 5 号灵动岛：一块黑盒子的宽、高、圆角各挂一条弹簧，换档时旧内容糊掉退场、新内容落进来
///
/// 参考稿的三个关键点：
/// 1. 形状是 `motion` 的弹簧 `{stiffness:400, damping:30}`（ζ=.75，末端有一点过冲），
///    宽/高/圆角是**三条独立的弹簧**同时起步 —— 线性系统下这跟"一条进度各自插值"
///    等价，但独立弹簧在飞行途中改目标能保住速度，所以照它写三条；
/// 2. 岛是**贴住 preview 下沿**的（容器 `items-end justify-center`），不是居中；
/// 3. 内容换档走 `AnimatePresence`：旧的往下 20、糊 10px、缩到 .95 淡掉，
///    新的从 opacity0 / scale.9 / y5 落进来。
///
/// 开场那串自动播放（1000/2200/3800/5600/7800ms 五档）是参考稿 `useScheduledAnimations`
/// 的队列延时累加；播放期间那颗 cycle 按钮是 disabled 的。
class Case05DynamicIsland extends StatefulWidget {
  const Case05DynamicIsland({super.key});

  static const islandKey = ValueKey<String>('sv-c05-island');
  static const cycleKey = ValueKey<String>('sv-c05-cycle');
  static const prevKey = ValueKey<String>('sv-c05-prev');
  static const curKey = ValueKey<String>('sv-c05-cur');
  static const spinnerKey = ValueKey<String>('sv-c05-spinner');
  static const titleKey = ValueKey<String>('sv-c05-title');

  /// 岛最大 371×210，舞台宽 372 正好容得下；底下让开 28 才不会被舞台圆角切到
  static const stageW = 372.0;
  static const stageH = 344.0;
  static const bottomInset = 28.0;

  /// 控制带：参考稿的按钮是 `absolute top-12 left-12` 再叠 `mt-4`（= 48,64），
  /// 两枚角标是 `absolute top-1 right-2`（= 4,8）—— 各占一行，谁也不压谁。
  /// 按钮落在 64 就得让最高那挡岛从 106 起，所以舞台给到 344。
  static const btnLeft = 48.0;
  static const btnTop = 64.0;
  static const badgeTop = 4.0;
  static const badgeRight = 8.0;

  static Key faceKey(SvIsle s) => ValueKey<String>('sv-c05-face-${s.label}');

  /// 参考稿 `cycleBlobStates` 的那一圈
  static const cycleOrder = <SvIsle>[SvIsle.compact, SvIsle.large, SvIsle.tall, SvIsle.long, SvIsle.medium];

  @override
  State<Case05DynamicIsland> createState() => _Case05DynamicIslandState();
}

class _Case05DynamicIslandState extends State<Case05DynamicIsland> with SingleTickerProviderStateMixin {
  // ===== 参考稿量出来的那一套（字面 px，见 §12.3 的例外）=====

  /// 弹簧：`stiffness 400 / damping 30 / mass 1`
  static const _k = 400.0;
  static const _d = 30.0;

  /// 岛的黑底 + `border-black/10` 那一圈（压在黑底上看不见，但它是 border-box，会把内容顶进去 1px）
  static const _islandBg = Color(0xFF000000);
  static const _islandBorder = Color(0x1A000000);

  // Tailwind 的那几档色
  static const _white = Color(0xFFFFFFFF);
  static const _cyan100 = Color(0xFFCFFAFE);
  static const _cyan300 = Color(0xFF67E8F9);
  static const _cyan400 = Color(0xFF22D3EE);
  static const _yellow300 = Color(0xFFFDE047);
  static const _n500 = Color(0xFF737373);
  static const _n700 = Color(0xFF404040);
  static const _n900 = Color(0xFF171717);
  static const _onPrimary = Color(0xFFFAFAFA);

  /// 开场队列：参考稿是"每步之前 await delay"，所以绝对时刻是累加
  static const _intro = <(SvIsle, int)>[
    (SvIsle.compact, 1000),
    (SvIsle.large, 2200),
    (SvIsle.tall, 3800),
    (SvIsle.long, 5600),
    (SvIsle.medium, 7800),
  ];

  late final SvSpring _sw = SvSpring.phys(stiffness: _k, damping: _d, from: SvIsle.def.w);
  late final SvSpring _sh = SvSpring.phys(stiffness: _k, damping: _d, from: SvIsle.def.h);
  late final SvSpring _sr = SvSpring.phys(stiffness: _k, damping: _d, from: SvIsle.def.r);

  /// 进场/退场那两路：1 = 完全显形
  final _cin = SvSpring.phys(stiffness: _k, damping: _d, from: 1);
  final _cout = SvSpring.phys(stiffness: _k, damping: _d, from: 1);

  SvIsle _size = SvIsle.def;
  SvIsle _prev = SvIsle.empty;
  SvIsle? _outgoing;

  Ticker? _ticker;
  Duration _last = Duration.zero;
  double _ms = 0;
  int _introStep = 0;

  /// 参考稿的 `isAnimating`：开场队列还没放完
  bool get _animating => _introStep < _intro.length;

  /// `animate-spin`：1s 一圈，跟着同一条时钟走
  double get spinnerTurn => _reduced ? 0 : (_ms % 1000) / 1000;

  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    // 参考稿挂载时 previousSize = empty，内容那一路按"换档"处理：从 0 起
    _cin.jumpTo(0);
    _cin.aim(1);
    _ticker = createTicker(_tick)..start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final off = MediaQuery.disableAnimationsOf(context);
    if (off == _reduced) return;
    setState(() {
      _reduced = off;
      if (off) {
        // 减弱动效：开场队列整段跳过，形状直接落位
        _introStep = _intro.length;
        _aim(_size, instant: true);
      }
    });
  }

  void _tick(Duration elapsed) {
    final dt = elapsed - _last;
    _last = elapsed;
    _ms += dt.inMicroseconds / 1000.0;
    var hit = false;
    if (!_reduced) {
      // 队列到点就换档：一次 tick 里可能同时到期好几步，全部吃掉
      while (_introStep < _intro.length && _ms >= _intro[_introStep].$2) {
        _setSize(_intro[_introStep].$1);
        _introStep++;
        hit = true;
      }
    }
    for (final s in [_sw, _sh, _sr, _cin, _cout]) {
      if (!s.atRest) {
        s.step(dt.inMilliseconds.toDouble());
        hit = true;
      }
    }
    if (!_cout.atRest && _cout.value <= 0.02) {
      _outgoing = null;
      _cout.jumpTo(1);
      hit = true;
    }
    if (hit || _size == SvIsle.large) setState(() {});
  }

  void _setSize(SvIsle next) {
    if (next == _size) return;
    setState(() {
      _outgoing = _size;
      _prev = _size;
      _size = next;
      _aim(next, instant: _reduced);
      _cin.jumpTo(0);
      _cin.aim(1);
      _cout.jumpTo(1);
      _cout.aim(0);
    });
  }

  void _aim(SvIsle next, {bool instant = false}) {
    if (instant) {
      _sw.jumpTo(next.w);
      _sh.jumpTo(next.h);
      _sr.jumpTo(next.r);
      return;
    }
    _sw.aim(next.w);
    _sh.aim(next.h);
    _sr.aim(next.r);
  }

  void _cycle() {
    if (_animating) return;
    final i = Case05DynamicIsland.cycleOrder.indexOf(_size);
    final next = Case05DynamicIsland.cycleOrder[(i + 1) % Case05DynamicIsland.cycleOrder.length];
    _setSize(next);
  }

  @override
  void dispose() {
    _ticker?.stop();
    super.dispose();
  }

  // ===== 外壳 =====

  @override
  Widget build(BuildContext context) {
    final w = _sw.value, h = _sh.value;
    return SvStage(
      width: Case05DynamicIsland.stageW,
      height: Case05DynamicIsland.stageH,
      center: false,
      child: Stack(
        children: [
          Positioned(
            left: Case05DynamicIsland.btnLeft,
            top: Case05DynamicIsland.btnTop,
            child: _cycleBtn(),
          ),
          Positioned(
            right: Case05DynamicIsland.badgeRight,
            top: Case05DynamicIsland.badgeTop,
            child: Row(children: [_badge(Case05DynamicIsland.prevKey, 'prev - '), _badge(Case05DynamicIsland.curKey, 'cur - ')]),
          ),
          // 参考稿的容器是 `items-end justify-center`：岛贴下沿、水平居中
          Positioned(
            left: (Case05DynamicIsland.stageW - w) / 2,
            bottom: Case05DynamicIsland.bottomInset,
            child: KeyedSubtree(
              key: Case05DynamicIsland.islandKey,
              child: Container(
                width: w,
                height: h,
                decoration: BoxDecoration(
                  color: _islandBg,
                  borderRadius: BorderRadius.circular(_sr.value),
                  border: Border.all(color: _islandBorder),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.none,
                  children: [
                    if (_outgoing != null) _face(_outgoing!, entering: false),
                    _face(_size, entering: true),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 一挡内容的进出场：`entering` 那一路 opacity/scale/y 从 0→1，退场那一路再叠一层糊
  ///
  /// 内容一律按**该档的终态尺寸**排版，岛那块黑盒子只是在外面裁 —— 参考稿途中
  /// `clipPath:none`、落定才套 squircle，内容跟着盒子边长边缩；我们要是让内容吃
  /// 当前尺寸，弹簧走到一半 `Column` 就装不下直接抛溢出。落定那一帧两种做法一模一样。
  Widget _face(SvIsle s, {required bool entering}) {
    final t = (entering ? _cin.value : _cout.value).clamp(0.0, 1.5);
    final child = OverflowBox(
      minWidth: 0,
      minHeight: 0,
      // 参考稿是 border-box：1px 描边把内容往里顶一格
      maxWidth: s.w - 2,
      maxHeight: s.h - 2,
      alignment: Alignment.center,
      child: _buildContent(s),
    );
    if (_reduced) {
      return entering
          ? KeyedSubtree(key: Case05DynamicIsland.faceKey(s), child: child)
          : const SizedBox.shrink();
    }
    if (!entering) {
      final blur = 10 * (1 - t.clamp(0.0, 1.0));
      return Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 20 * (1 - t)),
          child: Transform.scale(
            scale: 0.95 + 0.05 * t,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur, tileMode: TileMode.decal),
              child: KeyedSubtree(key: Case05DynamicIsland.faceKey(s), child: child),
            ),
          ),
        ),
      );
    }
    return Opacity(
      opacity: t.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, 5 * (1 - t)),
        child: Transform.scale(scale: 0.9 + 0.1 * t, child: KeyedSubtree(key: Case05DynamicIsland.faceKey(s), child: child)),
      ),
    );
  }

  Widget _buildContent(SvIsle s) {
    switch (s) {
      case SvIsle.compact:
        return _compact();
      case SvIsle.large:
        return _large();
      case SvIsle.tall:
        return _tall();
      case SvIsle.long:
        return _long();
      case SvIsle.medium:
        return _medium();
      default:
        return _placeholder();
    }
  }

  // ===== 控制带 =====

  Widget _cycleBtn() {
    final label = _text(14, weight: 500, color: _onPrimary);
    return MouseRegion(
      cursor: _animating ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _animating ? null : _cycle,
        child: Container(
          key: Case05DynamicIsland.cycleKey,
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _animating ? _n900.withValues(alpha: 0.5) : _n900,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _onPrimary.withValues(alpha: 0.1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SvIcon(paths: _mouseClick, size: 16, color: _onPrimary),
              const SizedBox(width: 4),
              Text('Click to cycle states', style: label),
            ],
          ),
        ),
      ),
    );
  }

  /// 参考稿的两枚 `Badge variant="outline"`：inline-flex 挨着排，中间没有缝
  Widget _badge(Key key, String head) {
    final s = _text(12, weight: 600, color: SvColor.fg);
    final name = head == 'prev - ' ? _prev.label : _size.label;
    return Container(
      key: key,
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: SvColor.pane,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: SvColor.border),
      ),
      alignment: Alignment.center,
      child: Text('$head$name', style: s),
    );
  }

  // ===== 五挡内容 =====

  Widget _placeholder() {
    return const Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvIcon(paths: _arrowBox, size: 24, color: _white),
          Text('cycle states', style: TextStyle(color: _white, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _compact() {
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        const Positioned(
          left: 16,
          top: 0,
          bottom: 0,
          child: Center(child: SvIcon(paths: _chat, size: 20, color: _cyan400, filled: true)),
        ),
        Positioned(
          right: 16,
          top: 0,
          bottom: 0,
          child: Center(child: Text('newcult.co', style: _text(18, weight: 700, color: _white, em: -0.05))),
        ),
      ],
    );
  }

  Widget _large() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          KeyedSubtree(
            key: Case05DynamicIsland.spinnerKey,
            child: Transform.rotate(angle: spinnerTurn * 2 * 3.141592653589793, child: const SvIcon(paths: _loader, size: 48, color: _yellow300)),
          ),
          KeyedSubtree(key: Case05DynamicIsland.titleKey, child: Text('loading', style: _text(24, weight: 900, color: _white, em: -0.05))),
        ],
      ),
    );
  }

  Widget _long() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const SvIcon(paths: _waves, size: 32, color: _cyan400),
          KeyedSubtree(
            key: Case05DynamicIsland.titleKey,
            child: Text('Supercalifragilisticexpialid', style: _text(20, weight: 900, color: _white, em: -0.05)),
          ),
        ],
      ),
    );
  }

  Widget _tall() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _chip('The Cult of Pythagoras'),
          const SizedBox(height: 4),
          _chip('Music of the Spheres, an idea that celestial bodies produce a form of music through their movements'),
          const SizedBox(height: 4),
          KeyedSubtree(
            key: Case05DynamicIsland.titleKey,
            child: Text('any cool cults?', style: _text(36, weight: 900, color: _cyan100, em: -0.05, leading: 40)),
          ),
        ],
      ),
    );
  }

  Widget _chip(String s) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(color: _cyan300, borderRadius: BorderRadius.all(Radius.circular(16))),
      child: Text(s, style: _text(14, weight: 600, color: Color(0xFF000000), em: -0.025, leading: 20)),
    );
  }

  Widget _medium() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: KeyedSubtree(
              key: Case05DynamicIsland.titleKey,
              child: Text('Reincarnation, welcome back', style: _text(24, weight: 900, color: _white, em: -0.05)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text('Good for small tasks or call outs', style: _text(14, color: _n500, leading: 20)),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: _n700,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Column(
                children: [
                  _islandBtn(_mail, _n900, 'Login with email'),
                  const SizedBox(height: 4),
                  _islandBtn(_user, _n900, 'Join the cult now'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _islandBtn(List<String> paths, Color bg, String label) {
    return Container(
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 参考稿是 `fill-cyan-400` + 描边另一色：两层叠出来才是那个双色图标
          Stack(
            children: [
              SvIcon(paths: paths, size: 16, color: _cyan400, filled: true),
              SvIcon(paths: paths, size: 16, color: _cyan400),
            ],
          ),
          const SizedBox(width: 8),
          Text(label, style: _text(14, weight: 500, color: _onPrimary)),
        ],
      ),
    );
  }

  // ===== 文字 =====

  /// Tailwind 的 `tracking-*` 是 em：`-0.05em` 要乘字号
  TextStyle _text(
    double size, {
    int weight = 400,
    Color color = _white,
    double em = 0,
    double? leading,
  }) =>
      TextStyle(
        fontFamily: SvFont.family,
        // 字族只到 Bold：`font-black`(900) 在 Flutter 里会兜到 700，
        // 真机和出图拿到的是同一份字面，所以这里照写 900 不改
        fontFamilyFallback: SvFont.fallback,
        fontSize: size,
        fontWeight: FontWeight.values[weight ~/ 100 - 1],
        color: color,
        letterSpacing: em * size,
        height: leading == null ? null : leading / size,
      );
}

// ===== lucide 的 path（viewBox 24、stroke-width 2，照原样搬）=====

const _chat = [
  'M2.992 16.342a2 2 0 0 1 .094 1.167l-1.065 3.29a1 1 0 0 0 1.236 1.168l3.413-.998a2 2 0 0 1 1.099.092 10 10 0 1 0-4.777-4.719',
];

const _loader = [
  'M12 2v4',
  'm16.2 7.8 2.9-2.9',
  'M18 12h4',
  'm16.2 16.2 2.9 2.9',
  'M12 18v4',
  'm4.9 19.1 2.9-2.9',
  'M2 12h4',
  'm4.9 4.9 2.9 2.9',
];

const _waves = [
  'M2 12q2.5 2 5 0t5 0 5 0 5 0',
  'M2 19q2.5 2 5 0t5 0 5 0 5 0',
  'M2 5q2.5 2 5 0t5 0 5 0 5 0',
];

const _mail = [
  'm22 7-8.991 5.727a2 2 0 0 1-2.009 0L2 7',
  'M4 4h16a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z',
];

const _user = [
  'M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2',
  'M16 7a4 4 0 1 1-8 0 4 4 0 1 1 8 0',
];

const _mouseClick = [
  'M14 4.1 12 6',
  'm5.1 8-2.9-.8',
  'm6 12-1.9 2',
  'M7.2 2.2 8 5.1',
  'M9.037 9.69a.498.498 0 0 1 .653-.653l11 4.5a.5.5 0 0 1-.074.949l-4.349 1.041a1 1 0 0 0-.74.739l-1.04 4.35a.5.5 0 0 1-.95.074z',
];

const _arrowBox = [
  'M15 15 9 9',
  'M9 15V9h6',
  'M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z',
];
