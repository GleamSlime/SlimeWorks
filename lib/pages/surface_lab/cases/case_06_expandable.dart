import 'dart:ui' show ImageFilter, TileMode;

import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';

import '../kit.dart';

// ===== 参考稿的字面色板与阴影：卡壳/helper 两拨控件都要用，放文件级 =====

/// `bg-white`：卡片本体和 outline 钮的底
const _white = Color(0xFFFFFFFF);

/// `ring-border/50`
const _border50 = Color(0x80E5E5E5);

/// tooltip 的黑底白字
const _tipBg = SvColor.primary;
const _tipFg = SvColor.onPrimary;

/// Tailwind `shadow-md` / `shadow-xl` 的两层（CSS 的 blur-radius 直接给 blurRadius）
const _shadowMd = <BoxShadow>[
  BoxShadow(color: Color(0x1A000000), blurRadius: 6, offset: Offset(0, 4)),
  BoxShadow(color: Color(0x1A000000), blurRadius: 4, offset: Offset(0, 2)),
];
const _shadowXl = <BoxShadow>[
  BoxShadow(color: Color(0x1A000000), blurRadius: 25, offset: Offset(0, 20)),
  BoxShadow(color: Color(0x1A000000), blurRadius: 10, offset: Offset(0, 8)),
];
const _ring = BoxShadow(color: _border50, blurRadius: 0, spreadRadius: 1);

/// 6 号折叠区：一颗盒子从 320×240 长到 420×480，里面三段内容各自从 0 长出高度
///
/// 参考稿那一格其实是**同一颗组件的三个实例**（会议卡 / 商品卡 / 天气卡），骨架、
/// 弹簧、动画档完全一样，只差内容 —— 这一格挑信息最全的会议卡，它把组件的四种
/// 动作都用上了：外壳双轴弹簧、`blur-md` 的一段、`blur-md + stagger` 的三段错位
/// 入场、`slide-up` 的页脚。
///
/// 四条要点：
/// 1. 外壳的宽高是**两条独立弹簧**（`{stiffness:200, damping:20, bounce:.2}` ——
///    damping 显式给了，bounce 就不参与，ζ = 20/(2√200) = .707，末端过冲 4.3%）；
/// 2. 三段内容的高度是**另三条**同参数弹簧，从 0 走到量出来的自然高（参考稿
///    `useMeasure` 量真实 DOM，我们铺一层不可见的量尺列去量，且只在展开态的宽度上量一次）；
/// 3. 内容本身的淡入/糊开/平移不是弹簧，是 `duration:.3s ease-in-out` 的补间，
///    stagger 那一路再按 `index × .2s` 错开；退场没有 stagger，整块一起淡掉；
/// 4. 点整颗卡切换（trigger 包着卡），Enter/Space 也切换。卡上那枚日历钮和四枚
///    头像各有 tooltip，走 portal —— 所以画在舞台顶层，不受卡的裁切。
class Case06Expandable extends StatefulWidget {
  const Case06Expandable({super.key});

  /// 测试要读的那几个落点
  static const cardKey = ValueKey<String>('sv-c06-card');
  static const triggerKey = ValueKey<String>('sv-c06-trigger');
  static const badgeKey = ValueKey<String>('sv-c06-badge');
  static const titleKey = ValueKey<String>('sv-c06-title');
  static const calKey = ValueKey<String>('sv-c06-cal');
  static const timeKey = ValueKey<String>('sv-c06-time');
  static const roomKey = ValueKey<String>('sv-c06-room');
  static const detailKey = ValueKey<String>('sv-c06-detail');
  static const attKey = ValueKey<String>('sv-c06-att');
  static const joinKey = ValueKey<String>('sv-c06-join');
  static const chatKey = ValueKey<String>('sv-c06-chat');
  static const footKey = ValueKey<String>('sv-c06-foot');
  static Key avatarKey(int i) => ValueKey<String>('sv-c06-avatar-$i');
  static const tipPrefix = 'sv-c06-tip-';

  /// 舞台：展开态 420×480 外面再让 32，`shadow-xl` 那两层糊光才不会被切
  static const stageW = 484.0;
  static const stageH = 544.0;

  static const collapsed = Size(320, 240);
  static const expanded = Size(420, 480);

  /// 外壳三层：A 只画环不占位，B 让出 8 的缝，C 是白卡本体给 16 的内边距
  static const rA = 32.0;
  static const padB = 8.0;
  static const rC = 24.0;
  static const padC = 16.0;

  /// 内容列的宽度 = 盒子宽减掉 B/C 两层内边距
  static double innerW(double w) => w - (padB + padC) * 2;

  /// `ExpandableCardContent` 是 `p-6 pt-0 px-4` → 再往里让 16
  static double bodyW(double w) => innerW(w) - 16 * 2;

  /// 页眉高：badge 22 + 下边距 8 + 大标题 28，再加自身上下各 24。
  /// 里面全是不换行的定长内容，永远量出这个数 —— 中段要用它算剩余高，
  /// 而量尺是 post-frame 才跑的，首帧拿 0 去算会让整列溢出一帧
  static const headH = 22 + 8 + 28.0 + 24 * 2;

  /// 排版一律吃展开态的宽度（弹簧途中不变），量尺和可见那一路共用这两个数
  static const layoutInner = 372.0;
  static const layoutBody = 340.0;

  @override
  State<Case06Expandable> createState() => _Case06ExpandableState();
}

class _Case06ExpandableState extends State<Case06Expandable> with SingleTickerProviderStateMixin {
  // ===== 参考稿的字面值 =====

  static const _k = 200.0;
  static const _d = 20.0;

  /// `transitionDuration = .3` + `easeType = 'easeInOut'`，stagger 每档 .2
  static const _durMs = 300.0;
  static const _staggerMs = 200.0;
  static const _blurMd = 8.0;
  static const _slideY = 20.0;

  /// 最后一段 stagger 走完的时刻
  static const _tailMs = _durMs + 2 * _staggerMs;

  static const _g800 = Color(0xFF1F2937);
  static const _g700 = Color(0xFF374151);
  static const _g600 = Color(0xFF4B5563);
  static const _red100 = Color(0xFFFEE2E2);
  static const _red600 = Color(0xFFDC2626);
  static const _red700 = Color(0xFFB91C1C);
  static const _input = SvColor.border; // --input = oklch(.922)
  static const _accent = SvColor.muted; // hover:bg-accent

  // ===== 状态 =====

  bool _open = false;
  Ticker? _ticker;
  Duration _last = Duration.zero;
  double _ms = 0;

  /// 上一次切换的时刻：三段内容的补间都以它为原点
  double _t0 = -9999;

  late final SvSpring _w = SvSpring.phys(stiffness: _k, damping: _d, from: Case06Expandable.collapsed.width);
  late final SvSpring _h = SvSpring.phys(stiffness: _k, damping: _d, from: Case06Expandable.collapsed.height);

  /// 三段内容的**高度**弹簧，目标是各自量到的自然高
  final _hm = SvSpring.phys(stiffness: _k, damping: _d);
  final _hd = SvSpring.phys(stiffness: _k, damping: _d);
  final _hf = SvSpring.phys(stiffness: _k, damping: _d);

  double _nRoom = 0, _nDetail = 0, _nFoot = 0;
  final _kRoom = GlobalKey();
  final _kDetail = GlobalKey();
  final _kFoot = GlobalKey();
  final _stageKey = GlobalKey();
  final _fn = FocusNode();

  bool _reduced = false;

  /// 悬停中的锚点（管 hover 底色），和 portal 出去的那枚 tooltip
  final Set<String> _hot = {};
  final Map<String, GlobalKey> _anchors = {};
  String? _tipId;
  String _tipText = '';
  Rect? _tipAt;
  double _tipT0 = -9999;

  /// 移出的那一瞬：非 null 就是在走淡出，走到 150ms 才从树里摘掉
  double? _tipOut;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
    // 量尺要等真实布局跑完才读得到，下一帧取
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final off = MediaQuery.disableAnimationsOf(context);
    if (off == _reduced) return;
    setState(() {
      _reduced = off;
      if (off) _aim();
    });
  }

  @override
  void dispose() {
    _ticker?.stop();
    _fn.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    final dt = elapsed - _last;
    _last = elapsed;
    _ms += dt.inMicroseconds / 1000.0;
    var hit = false;
    for (final s in [_w, _h, _hm, _hd, _hf]) {
      if (!s.atRest) {
        s.step(dt.inMilliseconds.toDouble());
        hit = true;
      }
    }
    // 补间那一路（含最后一段 stagger）还在走就得继续 repaint
    if (_ms - _t0 < _tailMs + 32) hit = true;
    // +32：末帧必须真的按 p=1（或 0）画一次。时钟只在这一句为真时才 setState，
    // 卡到 150 以内的那一帧画完就不再重建，画面会永远停在 0.997
    if (_tipAlive && _ms - _tipT0 < 150 + 32) hit = true;
    if (_tipOut != null && _ms - _tipOut! < 150 + 32) hit = true;
    if (hit) setState(() {});
  }

  /// 读那三段量尺的自然高；只在真的变了才 setState（同宽排版，读数不会来回跳）
  void _measure() {
    if (!mounted) return;
    double h(GlobalKey k) {
      final box = k.currentContext?.findRenderObject();
      return box is RenderBox ? box.size.height : 0;
    }

    var moved = false;
    for (final (key, target) in [
      (_kRoom, _nRoom),
      (_kDetail, _nDetail),
      (_kFoot, _nFoot),
    ]) {
      if ((h(key) - target).abs() > 0.5) moved = true;
    }
    if (moved) {
      setState(() {
        _nRoom = h(_kRoom);
        _nDetail = h(_kDetail);
        _nFoot = h(_kFoot);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _toggle() {
    setState(() {
      _open = !_open;
      _t0 = _ms;
      _aim();
    });
  }

  /// 五个通道一起换目标；减弱动效直接落位
  void _aim() {
    final size = _open ? Case06Expandable.expanded : Case06Expandable.collapsed;
    _go(_w, size.width);
    _go(_h, size.height);
    _go(_hm, _open ? _nRoom : 0);
    _go(_hd, _open ? _nDetail : 0);
    _go(_hf, _open ? _nFoot : 0);
  }

  void _go(SvSpring s, double t) {
    if (_reduced) {
      s.jumpTo(t);
    } else {
      s.aim(t);
    }
  }

  /// `duration:.3s ease-in-out` 那把补间；`delay` 是 stagger 的错位量
  double _prog([double delay = 0]) {
    if (_reduced) return _open ? 1 : 0;
    final u = ((_ms - _t0 - delay) / _durMs).clamp(0.0, 1.0);
    final e = SvEase.inOut.transform(u);
    return _open ? e : 1 - e;
  }

  void _enter(String id, String? tip, GlobalKey anchor) {
    final box = anchor.currentContext?.findRenderObject();
    final stage = _stageKey.currentContext?.findRenderObject();
    setState(() {
      _hot.add(id);
      if (tip == null) return;
      _tipId = id;
      _tipText = tip;
      _tipT0 = _ms;
      _tipOut = null;
      if (box is RenderBox && stage is RenderBox) _tipAt = box.localToGlobal(Offset.zero, ancestor: stage) & box.size;
    });
  }

  void _exit(String id) {
    setState(() {
      _hot.remove(id);
      // 参考稿的 tooltip 是 `animate-in` + `data-[state=closed]:animate-out`，
      // 两头各 150ms：移出不等于立刻摘掉，先记退场起点
      if (_tipId == id) _tipOut = _ms;
    });
  }

  /// tooltip 还在不在树里
  bool get _tipAlive => _tipOut == null || _ms - _tipOut! < 150;

  /// 淡入/淡出的进度：两头都是 `cubic-bezier(.4,0,.2,1)` 那把 in-out
  double _tipP() {
    var u = ((_ms - _tipT0) / 150).clamp(0.0, 1.0);
    final out = _tipOut;
    if (out != null) {
      final back = 1 - ((_ms - out) / 150).clamp(0.0, 1.0);
      if (back < u) u = back;
    }
    return _reduced ? (out == null ? 1.0 : 0.0) : SvEase.inOut.transform(u);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.space) {
      _toggle();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ===== 外壳 =====

  @override
  Widget build(BuildContext context) {
    final w = _w.value, hh = _h.value;
    return SvStage(
      width: Case06Expandable.stageW,
      height: Case06Expandable.stageH,
      child: Stack(
        key: _stageKey,
        clipBehavior: Clip.hardEdge,
        children: [
          // 量尺列：不可见，按展开态的宽度把三段内容各排一遍，post-frame 读自然高
          Positioned(
            left: 0,
            top: 0,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0,
                child: SizedBox(
                  width: Case06Expandable.layoutInner,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(key: _kRoom, width: Case06Expandable.layoutBody, child: _room()),
                      SizedBox(key: _kDetail, width: Case06Expandable.layoutBody, child: _detail(true, measure: true)),
                      SizedBox(key: _kFoot, width: Case06Expandable.layoutInner, child: _foot()),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: Focus(
              focusNode: _fn,
              onKeyEvent: _onKey,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  key: Case06Expandable.triggerKey,
                  onTap: () {
                    // 点一下把焦点收到 trigger 上，之后 Enter/Space 才接着能用
                    _fn.requestFocus();
                    _toggle();
                  },
                  child: Container(
                    // A：`ring-1 ring-border/50` 那圈是有效的 box-shadow，画。
                    // 同一条 class 上那句 inset 描边写的是 `hsl(var(--border)/.3)` ——
                    // 这套 token 在 v4 里是 oklch，套进 hsl() 是废值，浏览器直接丢掉整条
                    // declaration，所以不画
                    key: Case06Expandable.cardKey,
                    width: w,
                    height: hh,
                    decoration: const BoxDecoration(
                      borderRadius: BorderRadius.all(Radius.circular(Case06Expandable.rA)),
                      boxShadow: [_ring],
                    ),
                    child: Container(
                      // B：`p-2` + `shadow-md`
                      decoration: const BoxDecoration(
                        borderRadius: BorderRadius.all(Radius.circular(Case06Expandable.rA)),
                        boxShadow: _shadowMd,
                      ),
                      padding: const EdgeInsets.all(Case06Expandable.padB),
                      child: Container(
                        // C：白卡本体 `rounded-3xl p-4 shadow-xl ring-1`
                        decoration: const BoxDecoration(
                          color: _white,
                          borderRadius: BorderRadius.all(Radius.circular(Case06Expandable.rC)),
                          boxShadow: [_ring, ..._shadowXl],
                        ),
                        padding: const EdgeInsets.all(Case06Expandable.padC),
                        child: _body(w, hh),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_tipAt != null && _tipId != null && _tipAlive) _tipLayer(),
        ],
      ),
    );
  }

  /// 中段该高 = 白卡内容盒 − 页眉 − 页脚那一段。两头都取弹簧途中的值，
  /// 所以整段是跟着外壳一起长的
  double _midH(double hh) {
    // 页脚那一路的弹簧会先冲过 0 再荡回来：负的那一截渲染上不存在（`_block` 钳到 0），
    // 这里也不许它来膨胀中段，否则这一列比内容盒还高，RenderFlex 直接报溢出
    final foot = _hf.value < 0 ? 0.0 : _hf.value;
    final left = hh - (Case06Expandable.padB + Case06Expandable.padC) * 2 - Case06Expandable.headH - foot;
    return left < 0 ? 0 : left;
  }

  /// D + E：`overflow-hidden` 的盒子，里面一条竖排内容列（页眉 / 会长 / 页脚）
  Widget _body(double w, double hh) {
    return SizedBox(
      width: Case06Expandable.innerW(w),
      child: ClipRect(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            SizedBox(
              // 中段 = 白卡内容盒 - 页眉 - 页脚那一段。弹簧途中这个差会短暂变负
              //（页脚的高度会冲到 0 以下），钳住，别让 RenderFlex 拿到负约束
              height: _midH(hh),
              child: Padding(
                // `p-6 pt-0 px-4 overflow-hidden flex-grow`
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minHeight: 0,
                    maxHeight: double.infinity,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // `mb-4 flex flex-col items-start justify-between`
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _time(),
                              _block(
                                key: Case06Expandable.roomKey,
                                h: _hm.value,
                                natural: _nRoom,
                                layoutW: null,
                                p: _prog(),
                                blur: _blurMd,
                                child: _room(),
                              ),
                            ],
                          ),
                        ),
                        _block(
                          key: Case06Expandable.detailKey,
                          h: _hd.value,
                          natural: _nDetail,
                          layoutW: Case06Expandable.layoutBody,
                          p: _prog(),
                          blur: _blurMd,
                          child: _staggered(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _block(
              key: Case06Expandable.footKey,
              h: _hf.value,
              natural: _nFoot,
              layoutW: Case06Expandable.layoutInner,
              p: _prog(),
              y: _slideY,
              child: _foot(),
            ),
          ],
        ),
      ),
    );
  }

  /// 一段 `ExpandableContent`：外层高度是弹簧值，内层按终宽排版，只裁不压
  Widget _block({
    required Key key,
    required double h,
    required double natural,
    required double? layoutW,
    required double p,
    double blur = 0,
    double y = 0,
    required Widget child,
  }) {
    Widget inner = layoutW == null ? child : SizedBox(width: layoutW, child: child);
    if (y != 0) inner = Transform.translate(offset: Offset(0, (1 - p) * y), child: inner);
    if (blur != 0) {
      final s = (1 - p) * blur;
      inner = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: s, sigmaY: s, tileMode: TileMode.decal),
        child: inner,
      );
    }
    return ClipRect(
      child: SizedBox(
        key: key,
        // 目标 0 的那一路弹簧会冲到负一半再荡回来，`SizedBox` 拿到负高直接断言
        height: h < 0 ? 0 : h,
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: 0,
          maxWidth: double.infinity,
          minHeight: 0,
          maxHeight: natural,
          child: Opacity(opacity: p.clamp(0.0, 1.0), child: inner),
        ),
      ),
    );
  }

  /// `stagger` 那一路：三个孩子各错开 .2s。退场不错开 —— 参考稿的孩子没有 exit 变体
  Widget _staggered() {
    // `{expanded && …}`：参考稿那枚描边钮是条件渲染，不是裁掉 —— 换的是一整棵子树。
    // 量尺那一路永远按"有"来量，退场那一瞬自然高会缩，靠 `OverflowBox` 兜住
    final kids = _detailKids(_open);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < kids.length; i++) //
          _staggeredChild(i, kids[i]),
      ],
    );
  }

  Widget _staggeredChild(int i, Widget child) {
    final p = _open ? _prog(i * _staggerMs) : 1.0;
    return Opacity(
      opacity: p.clamp(0.0, 1.0),
      child: Transform.translate(offset: Offset(0, (1 - p) * _slideY), child: child),
    );
  }

  // ===== 卡里的内容 =====

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            key: Case06Expandable.titleKey,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  key: Case06Expandable.badgeKey,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: _red100,
                    borderRadius: BorderRadius.all(Radius.circular(6)),
                    // `border border-transparent`：这圈透明描边照样占 1px，
                    // 整枚 badge 是 16+4+2 = 22 高，不是 20
                    border: Border.fromBorderSide(BorderSide(color: Colors.transparent)),
                  ),
                  child: Text('In 15 mins', style: _st(12, _red600, weight: 600, leading: 16)),
                ),
              ),
              Text('Design Sync', style: _st(20, _g800, weight: 600, leading: 28)),
            ],
          ),
          _hoverable(
            'calendar',
            tip: 'Add to Calendar',
            builder: (hot) => Container(
              key: Case06Expandable.calKey,
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: hot ? _accent : _white,
                borderRadius: const BorderRadius.all(Radius.circular(6)),
                border: Border.all(color: _input),
              ),
              child: const Center(child: SvIcon(paths: _calendar, size: 16, color: SvColor.fg)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _time() {
    return Row(
      key: Case06Expandable.timeKey,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SvIcon(paths: _clock, size: 16, color: _g600),
        const SizedBox(width: 4),
        Text('1:30PM → 2:30PM', style: _st(14, _g600, leading: 20)),
      ],
    );
  }

  Widget _room() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SvIcon(paths: _mapPin, size: 16, color: _g600),
        const SizedBox(width: 4),
        Text('Conference Room A', style: _st(14, _g600, leading: 20)),
      ],
    );
  }

  /// `measure` 是给不可见量尺用的：那一路和可见那一路是同一份内容，
  /// key 重复挂会让 GlobalKey 直接报错，`find.byKey` 也会一次匹到两枚
  Widget _detail(bool withChat, {bool measure = false}) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _detailKids(withChat, measure),
      );

  /// 三段 stagger 孩子：说明、与会人、两枚钮。
  /// `withChat` 就是参考稿那句 `{isExpanded && <Button variant="outline"/>}`
  List<Widget> _detailKids(bool withChat, [bool measure = false]) {
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(
          'Weekly design sync to discuss ongoing projects, share updates, and address any design-related challenges.',
          style: _st(14, _g700, leading: 20),
        ),
      ),
      Padding(
        key: measure ? null : Case06Expandable.attKey,
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SvIcon(paths: _users, size: 16, color: _g800),
                  const SizedBox(width: 8),
                  Text('Attendees:', style: _st(14, _g800, weight: 500, leading: 20)),
                ],
              ),
            ),
            // `-space-x-2`：每枚往后让 -8，四枚 32 的圆叠成 104 宽
            SizedBox(
              width: 104,
              height: 32,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // 参考稿这 4 枚各自挂着一层 tooltip
                  for (var i = 0; i < _names.length; i++) //
                    Positioned(
                      left: i * 24.0,
                      child: _hoverable('av$i',
                          tip: _names[i],
                          measure: measure,
                          builder: (_) => _AvatarSlot(i, measure: measure)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _hoverable(
            'join',
            measure: measure,
            builder: (hot) => _button(measure ? null : Case06Expandable.joinKey, 'Join Meeting', _video,
                bg: hot ? _red700 : _red600, fg: _white),
          ),
          if (withChat) ...[
            const SizedBox(height: 8),
            _hoverable(
              'chat',
              measure: measure,
              builder: (hot) => _button(measure ? null : Case06Expandable.chatKey, 'Open Chat', _messageSquare,
                  bg: hot ? _accent : _white, fg: SvColor.fg),
            ),
          ],
        ],
      ),
    ];
  }

  Widget _button(Key? key, String label, List<String> icon, {required Color bg, required Color fg}) {
    return Container(
      key: key,
      height: 36,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.all(Radius.circular(6)),
        border: Border.all(color: _input),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 1, offset: Offset(0, 1))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SvIcon(paths: icon, size: 16, color: fg),
          const SizedBox(width: 8),
          Text(label, style: _st(14, fg, weight: 500, leading: 20)),
        ],
      ),
    );
  }

  Widget _foot() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Weekly', style: _st(14, _g600, leading: 20)),
          Text('Next: Mon, 10:00 AM', style: _st(14, _g600, leading: 20)),
        ],
      ),
    );
  }

  // ===== 悬停 / tooltip（portal：画在舞台顶层，不受卡的裁切）=====

  /// 给一枚元素套悬停：`tip` 给了才同时把锚点矩形交给顶层那枚 tooltip。
  /// `measure` 那一路整个 MouseRegion 都不套 —— 锚点用的是 GlobalKey，一份树里挂两次直接报错
  Widget _hoverable(String id, {String? tip, bool measure = false, required Widget Function(bool hot) builder}) {
    if (measure) return builder(false);
    final anchor = _anchors.putIfAbsent(id, () => GlobalKey(debugLabel: 'c06-$id'));
    return MouseRegion(
      onEnter: (_) => _enter(id, tip, anchor),
      onExit: (_) => _exit(id),
      child: SizedBox(key: anchor, child: builder(_hot.contains(id))),
    );
  }

  Widget _tipLayer() {
    final p = _tipP();
    return Positioned.fill(
      child: CustomSingleChildLayout(
        delegate: _TipAt(_tipAt!, 4),
        child: Opacity(
          opacity: p,
          // `data-[side=top]:slide-in-from-bottom-2`：挂在锚点上方，进场是从下面
          // 顶上来 8px（不是从上面掉下来）。退场那一路只有 fade-out + zoom-out，
          // 没有 slide-out
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - p)),
            // `origin-[--radix-tooltip-content-transform-origin]`：side=top 时缩放原点在底边
            child: Transform.scale(
              alignment: Alignment.bottomCenter,
              scale: 0.95 + 0.05 * p,
              child: Container(
                key: ValueKey<String>('${Case06Expandable.tipPrefix}$_tipId'),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: const BoxDecoration(
                  color: _tipBg,
                  borderRadius: BorderRadius.all(Radius.circular(6)),
                ),
                child: Text(_tipText, style: _st(12, _tipFg, leading: 16)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// tooltip 的落点：锚点正上方让开 4px（`side:top` + `sideOffset:4`）
class _TipAt extends SingleChildLayoutDelegate {
  _TipAt(this.at, this.gap);

  final Rect at;
  final double gap;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
        at.center.dx - childSize.width / 2,
        at.top - gap - childSize.height,
      );

  @override
  bool shouldRelayout(_TipAt other) => other.at != at || other.gap != gap;
}

/// 头像：参考稿那 4 张的 src 是站点自己的占位图，离线拿不到 ——
/// 画的是它本来就备着的那层 `AvatarFallback`（bg-muted + 首字母 + 2px 白描边）
class _AvatarSlot extends StatelessWidget {
  const _AvatarSlot(this.i, {this.measure = false});

  final int i;

  /// 量尺那一路不挂 key：两份树里同一个 ValueKey 会让 `find.byKey` 一次匹到两枚
  final bool measure;

  @override
  Widget build(BuildContext context) {
    final name = _names[i];
    return Container(
      key: measure ? null : Case06Expandable.avatarKey(i),
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: SvColor.muted,
        shape: BoxShape.circle,
        border: Border.fromBorderSide(BorderSide(color: _white, width: 2)),
      ),
      child: Text(name[0], style: _st(16, SvColor.text)),
    );
  }
}

const _names = ['Alice', 'Bob', 'Charlie', 'David'];

/// Tailwind 的字面字号：`text-xs` 12/16、`text-sm` 14/20、`text-xl` 20/28
TextStyle _st(double size, Color color, {int weight = 400, double? leading, double? em}) {
  return TextStyle(
    fontFamily: SvFont.family,
    fontFamilyFallback: SvFont.fallback,
    fontSize: size,
    fontWeight: FontWeight.values[weight ~/ 100 - 1],
    height: (leading ?? size * 1.5) / size,
    letterSpacing: em == null ? null : em * size,
    color: color,
  );
}

// lucide 的字面 path（circle/rect 折成等价的弧段）
const _calendar = [
  'M8 2v3',
  'M16 2v3',
  'M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z',
  'M3 9h18',
];
const _clock = ['M12 2a10 10 0 1 0 0 20 10 10 0 1 0 0-20', 'M12 6v6l4 2'];
const _mapPin = [
  'M20 10c0 4.993-5.539 10.193-7.399 11.799a1 1 0 0 1-1.202 0C9.539 20.193 4 14.993 4 10a8 8 0 0 1 16 0',
  'M12 7a3 3 0 1 0 0 6 3 3 0 1 0 0-6',
];
const _users = [
  'M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2',
  'M16 3.128a4 4 0 0 1 0 7.744',
  'M22 21v-2a4 4 0 0 0-3-3.87',
  'M9 3a4 4 0 1 0 0 8 4 4 0 1 0 0-8',
];
const _video = [
  'm16 13 5.223 3.482a.5.5 0 0 0 .777-.416V7.87a.5.5 0 0 0-.752-.432L16 10.5',
  'M4 6h10a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H4a2 2 0 0 1-2 2V8a2 2 0 0 1 2-2z',
];
const _messageSquare = [
  'M22 17a2 2 0 0 1-2 2H6.828a2 2 0 0 0-1.414.586l-2.202 2.202A.71.71 0 0 1 2 21.286V5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2z',
];
