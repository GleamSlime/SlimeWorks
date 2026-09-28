import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind, TapUpDetails;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/material.dart';

import '../kit.dart';

/// 13 号 Action node（参考稿这一条本身就是暗色档）
///
/// 一句话：四个圆钮平时**藏在卡片右上角底下** —— 不是淡出，是靠层叠压住
/// （`.nod-card{z-index:1}` 盖 `.nod-fan{z-index:0}`，全程没有透明度通道）。
/// 指针一进整块，钮就沿"贴着圆角外侧 30px"的那条倒角线滑出来，
/// 每钮一根弹簧，起跳时刻按 49.5ms 错开，离开再按倒序收回去。
///
/// 触屏给不出 enter/exit，所以另接一条点按：点卡片当"指针进来并停在原地"、再点
/// 当离开，判据还是 `_zone` 那套几何（`_tapZone`）。
///
/// 参考稿三条值得单独记的口径：
/// 1. **一根弹簧同时管位移和缩放，但上限分开**：位移允许冲到 1.4 倍（沿
///    "停靠位→目标"那条射线往外冲再落回），缩放只到 1.0 —— 过冲那几帧
///    看着是"甩过头"而不是"变大"。
/// 2. 错拍改的是**起跳时刻**，不是到位时刻：四条弹簧曲线形状一模一样，只是平移。
///    计时器只负责翻转那一位布尔，真正把值从 0 拉到 100 的是弹簧。
/// 3. 相邻两钮之间隔的是**弧长** 48px（不是角度），而钮径 36 —— 所以弧上必然留
///    12px 缝，那条缝就是 `.nod-reach` 存在的理由（把悬停命中区撑到钮与钮之间、
///    并且切掉卡片自己占的那块）。
///
/// 和参考稿的两处有意偏差：
/// - 头像原稿走 `vh[id] ? <img/> : 首字母`，三个 id 都有内联 JPEG → 参考稿是照片。
///   这里落回同一条 CSS 的另一支（首字母圆），版式一分不差，只是圆里是 `MQ/TO/LA`；
/// - 卡片高度是内容撑出来的（参考稿同样如此），舞台高度按实测行数给。
class Case13ActionNode extends StatefulWidget {
  const Case13ActionNode({super.key});

  @override
  State<Case13ActionNode> createState() => _Case13ActionNodeState();
}

/// 参考稿那套"绕着圆角走"的取点公式
///
/// 独立出来是为了让测试能自己复算一遍，而不是从组件渲染结果里反推 ——
/// 这套数就是全部还原的依据。
abstract final class IlNodeFan {
  /// `iy`：钮径
  static const btn = 36.0;

  /// `ay`：钮半径，也就是"圆心落在锚点上"那对 margin
  static const half = btn / 2;

  /// `oy`：相邻两钮之间隔的弧长（px，不是角度）
  static const arcStep = 48.0;

  /// `uy`：根节点上下各留的扇出带
  static const band = 52.0;

  /// `ly(reach) + ay` —— 倒角线离卡片角的距离
  static double inset(double reach) => 6 + reach.clamp(20.0, 40.0) / 100 * 24 + half;

  /// `cy(m)/√2` 换算出的停靠位：塞在卡片角底下的那一点
  static Offset home(double corner) {
    final m = corner.clamp(0.0, 32.0);
    final d = m >= 20 ? m * _sqrt2 : math.max(half * _sqrt2 + 2, m * _sqrt2 + m + 2);
    return Offset(-d / _sqrt2, d / _sqrt2);
  }

  /// `sy(s, m, h)`：沿倒角线按弧长取点。原点在卡片右上角，x 向左为负、y 向上为负
  ///
  /// 先沿上边平走，再绕 1/4 圆弧（半径 `m+h`、圆心 `(-m, m)`），再沿右边平走 ——
  /// 钮坐在角的**外面一圈**，而不是站在角的点上。
  static Offset along(double s, double corner, double insetPx) {
    final m = corner.clamp(0.0, 32.0);
    final r = math.max(0.001, m + insetPx);
    final arc = r * math.pi / 2;
    if (s <= 0) return Offset(-m + s, -insetPx);
    if (s >= arc) return Offset(insetPx, m + (s - arc));
    final a = math.pi / 2 - s / r;
    return Offset(-m + r * math.cos(a), m - r * math.sin(a));
  }

  /// 第 `t` 个钮的圆心：`g + (t-(n-1)/2)*oy`，整排对称地压在角平分线两侧
  static Offset target(int t, int count, double corner, double insetPx) {
    final m = corner.clamp(0.0, 32.0);
    final g = (m + insetPx) * math.pi / 4;
    return along(g + (t - (count - 1) / 2) * arcStep, m, insetPx);
  }

  /// `.nod-reach`：全部钮的包围盒（每边再外扩 24）切掉卡片自己占的那块
  ///
  /// 返回的是**扇出原点坐标系**里的矩形；切掉的左下角矩形用 [reachNotch] 量。
  static Rect reachBox(List<Offset> targets) {
    final pad = half + 6;
    var l = double.infinity, r = double.negativeInfinity;
    var t = double.infinity, b = double.negativeInfinity;
    for (final p in targets) {
      l = math.min(l, p.dx - pad);
      r = math.max(r, p.dx + pad);
      t = math.min(t, p.dy - pad);
      b = math.max(b, p.dy + pad);
    }
    return Rect.fromLTRB(l, t, r, b);
  }

  /// 切口的两条边：`T = max(0, -left - m)`、`E = min(height, -top + m)`
  static (double, double) reachNotch(Rect box, double corner) {
    final m = corner.clamp(0.0, 32.0);
    return (
      math.max(0, -box.left - m),
      math.min(box.height, -box.top + m),
    );
  }

  /// `clip-path: polygon(0 0, W 0, W H, T H, T E, 0 E)` —— 矩形切掉左下角卡片自己占的那块
  static Path reachPath(Rect box, double notchX, double notchY) {
    final w = box.width;
    final h = box.height;
    return Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h)
      ..lineTo(notchX, h)
      ..lineTo(notchX, notchY)
      ..lineTo(0, notchY)
      ..close();
  }

  static const _sqrt2 = 1.4142135623730951;
}

/// 由旋钮算出来的全部量（这一格没有会动的旋钮，所以整块是常量）
class _Fan {
  _Fan.build(double corner, double reach, int count, double cardW)
      : inset = IlNodeFan.inset(reach),
        home = IlNodeFan.home(corner),
        targets = <Offset>[
          for (var i = 0; i < count; i++) IlNodeFan.target(i, count, corner, IlNodeFan.inset(reach)),
        ] {
    box = IlNodeFan.reachBox(targets);
    final (t, e) = IlNodeFan.reachNotch(box, corner);
    notchX = t;
    notchY = e;
    // 悬停盒比"卡片根盒"向右/向上多出的量：reach 相对扇出原点平移 (cardW, band)，
    // 根盒顶在 -band 而 reach 顶在 box.top —— 高出来的那截就是 -(|box.top| - band)
    overX = math.max(0.0, box.right);
    overY = math.max(0.0, -(IlNodeFan.band + box.top));
    assert(math.max(0.0, -(cardW + box.left)) == 0, 'reach 不能探到卡片左边外');
    fanAt = Offset(cardW, IlNodeFan.band);
  }

  final double inset;
  final Offset home;
  final List<Offset> targets;
  late final Rect box;
  late final double notchX;
  late final double notchY;
  late final double overX;
  late final double overY;

  /// 扇出原点（卡片右上角）在 Stack 坐标里的位置
  late final Offset fanAt;
}

class _Case13ActionNodeState extends State<Case13ActionNode> with SingleTickerProviderStateMixin {
  // ---------------------------------------------------------------- 旋钮（钉死在参考稿默认档）

  /// `corner`：圆角，同时决定这一排钮绕着多大的角走
  static const _corner = 20.0;

  /// `reach` 没有旋钮，恒 25
  static const _reach = 25.0;

  /// `count`：钮的个数，2..4
  static const _count = 4;

  /// `Rf(bounce)`：弹簧的 k/d 都从 Bounce 旋钮（默认 20）来
  static const _k = 0.08 + 20 / 100 * 0.16;
  static const _d = 0.62 + 20 / 100 * 0.2;

  /// `stagger/100*dy`，dy=90 —— 相邻两钮的**起跳**时差
  static const _stepMs = 55 / 100 * 90;

  // ---------------------------------------------------------------- 卡片自身的量

  static const _cardW = 272.0;
  static const _pad = 18.0;
  static const _markS = 30.0;
  static const _markR = 9.4; // min(15, corner*.47)
  static const _linkS = 24.0;
  static const _linkGap = -6.0;
  static const _topGap = 9.0;
  static const _sayTop = 13.0;
  static const _sayFont = 13.5;
  static const _sayLh = 20.25; // 13.5 × 1.5
  static const _chainTop = 16.0;
  static const _moreLeft = 8.0;

  /// 位移允许冲到 1.4 倍，缩放只到 1.0
  static const _over = 1.4;
  static const _pop0 = 0.82;

  static const _say = 'Reads the thread, writes a summary, and posts it back to the channel it came from.';
  static const _name = 'Node 07';

  static const _liftCurve = Cubic(0.3, 1.1, 0.4, 1);

  /// 全部几何都由上面那几个常量算出来，一次算好
  late final _Fan _fan = _Fan.build(_corner, _reach, _count, _cardW);

  // ---------------------------------------------------------------- 状态

  final GlobalKey _hitKey = GlobalKey(debugLabel: 'action-node-hover');
  bool _open = false;
  final List<bool> _flags = List<bool>.filled(4, false);
  late final List<IlSpring> _springs = <IlSpring>[
    for (var i = 0; i < 4; i++) IlSpring(k: _k, d: _d),
  ];
  final List<_Tw> _zoom = <_Tw>[
    for (var i = 0; i < 4; i++) _Tw(dur: 180, curve: _liftCurve),
  ];
  final _Tw _lift = _Tw(dur: 260, curve: _liftCurve);
  final List<Timer?> _timers = List<Timer?>.filled(4, null);
  Ticker? _ticker;
  Duration _last = Duration.zero;

  @override
  void dispose() {
    for (final t in _timers) {
      t?.cancel();
    }
    _ticker?.stop();
    _ticker = null;
    super.dispose();
  }

  // ---------------------------------------------------------------- 悬停

  /// 这一帧指针算不算"在整块里"
  ///
  /// 参考稿把悬停判定挂在根节点上（`onPointerOut` 只在 relatedTarget 跑出自己子树时才关），
  /// 伸出盒子外那 54px 靠一个绝对定位的 `i.nod-reach`（带切口的 L，`pointer-events`
  /// 只在展开态打开）接住。这套抄不过来：`RenderMouseRegion.hitTest` 的第一道门是
  /// `size.contains(自己那个盒)`，画在盒外的子孙**根本进不到**这个祖先的命中路径里 ——
  /// 指针一走到钮上就当离开，扇出立刻收回，而"走到钮上还算不算悬停"恰恰是这块的全部难点。
  ///
  /// 所以这里只挂一个悬停盒（罩住受理区的包围盒），"算不算在块里"按那条多边形的几何自己判：
  /// 判据和 `clip-path` 一分不差，收起态也只有卡片根盒那一块算命中（`.nod-reach` 当时是死的）。
  void _syncHover(Offset global) {
    final ro = _hitKey.currentContext?.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize) return;
    _setOpen(_zone(ro.size).contains(ro.globalToLocal(global)));
  }

  /// 受理区 = 卡片根盒 ∪（展开时的）`.nod-reach`；坐标是悬停盒的局部坐标
  Path _zone(Size hoverBox) {
    final g = _fan;
    // 悬停盒的底就是根盒的底：上下只有顶部多出 overY
    final path = Path()..addRect(_cardRect(hoverBox));
    if (_open) {
      path.addPath(
        // reach 在参考稿里就是绝对定位在扇出原点上的一组 left/top，平移量照着抄。
        // fanAt 是 Stack 坐标，悬停盒比 Stack 高出 overY，所以要把那一截加回来
        IlNodeFan.reachPath(g.box, g.notchX, g.notchY),
        Offset(0, g.overY) + g.fanAt + Offset(g.box.left, g.box.top),
      );
    }
    return path;
  }

  /// 触屏的点法：这一格的开合原本只有鼠标悬停那一条路
  ///
  /// 触屏给不出 enter/hover/exit，所以指尖点一下卡片当作"指针进来并停在原地"、
  /// 再点一下当作离开。判据仍走 `_zone` 那套几何：点在钮与钮之间那块 reach 里算
  /// "指针还留在块内"（跟悬停一样不收），出了整块才收。只有 touch 指针走这条路，
  /// 桌面上鼠标点击不改变悬停语义。
  void _tapZone(TapUpDetails d) {
    if (d.kind != PointerDeviceKind.touch) return;
    final ro = _hitKey.currentContext?.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize) return;
    final p = ro.globalToLocal(d.globalPosition);
    if (_cardRect(ro.size).contains(p)) {
      _setOpen(!_open);
    } else if (!_zone(ro.size).contains(p)) {
      _setOpen(false);
    }
  }

  /// 卡片根盒在悬停盒坐标里占的那块 —— 也就是收起态的受理区
  Rect _cardRect(Size hoverBox) => Rect.fromLTRB(0, _fan.overY, _cardW, hoverBox.height);

  /// 进/出整块：先把旧计时器全部作废再按新方向重建，连点两下不会叠出两层错拍
  void _setOpen(bool v) {
    if (v == _open) return;
    _open = v;
    for (var i = 0; i < _timers.length; i++) {
      _timers[i]?.cancel();
      _timers[i] = null;
    }
    for (var i = 0; i < 4; i++) {
      // 开：0 号先出；收：3 号先进（倒序）
      final delay = _stepMs * (v ? i : _count - 1 - i);
      if (delay <= 0) {
        _aim(i, v);
      } else {
        _timers[i] = Timer(Duration(milliseconds: delay.round()), () => _aim(i, v));
      }
    }
    _lift.aim(v ? 1 : 0);
    _kick();
    setState(() {});
  }

  /// 计时器只做一件事：翻那一位的布尔，然后让弹簧自己走
  void _aim(int i, bool on) {
    if (_flags[i] == on) return;
    _flags[i] = on;
    _springs[i].aim(on ? 100 : 0);
    _kick();
    setState(() {});
  }

  void _aimZoom(int i, double to) {
    _zoom[i].aim(to);
    _kick();
    setState(() {});
  }

  // ---------------------------------------------------------------- 一帧只走一根钟

  void _kick() {
    _ticker ??= createTicker(_tick);
    if (!_ticker!.isActive) {
      _last = Duration.zero;
      _ticker!.start();
    }
  }

  void _tick(Duration e) {
    final dt = (e - _last).inMilliseconds.toDouble();
    _last = e;
    var live = false;
    for (final s in _springs) {
      if (!s.atRest) {
        // 四根弹簧共用一根钟：它们本来就是同一条 rAF 时间轴上的同一族积分
        s.step(dt);
        live = true;
      }
    }
    for (final z in _zoom) {
      live |= z.step(dt);
    }
    live |= _lift.step(dt);
    setState(() {});
    if (!live) _ticker!.stop();
  }

  // ---------------------------------------------------------------- 树

  @override
  Widget build(BuildContext context) {
    final g = _fan;

    return IlStage(
      dark: true,
      height: _stageH,
      // 参考稿把 `.nod` 那个 272 宽的根盒坐在舞台正中；悬停盒比它宽 54、高 2，
      // 多出来的量全在右上，所以整体挪回去
      child: Transform.translate(
        offset: Offset(g.overX / 2, -g.overY / 2),
        child: MouseRegion(
          key: _hitKey,
          onEnter: (e) => _syncHover(e.position),
          onHover: (e) => _syncHover(e.position),
          onExit: (_) => _setOpen(false),
          child: Listener(
            onPointerCancel: (_) => _setOpen(false),
            child: GestureDetector(
              // translucent：判定要覆盖整颗悬停盒，而 `deferToChild` 只在盒里有
              // 孩子被命中时才收下这一笔 —— 卡片右侧那块空白没有孩子，点它本来该
              // 读成"指针出了整块"，却会连 onTapUp 都收不到。MouseRegion 那道门是
              // `size.contains`，所以悬停在那块有反应、点按没有，两边得对齐。
              behavior: HitTestBehavior.translucent,
              onTapUp: _tapZone,
              child: SizedBox(
                width: _cardW + g.overX,
                child: Padding(
                  padding: EdgeInsets.only(top: g.overY),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // 扇出层先画：卡片压在它上面，收起态的钮就是被这么藏住的
                      // （参考稿没有透明度通道，`.nod-card{z-index:1}` 盖 `.nod-fan{z-index:0}`）
                      for (var i = 0; i < _count; i++)
                        Positioned(
                          left: g.fanAt.dx + _lerp(g.home.dx, g.targets[i].dx, i) - IlNodeFan.half,
                          top: g.fanAt.dy + _lerp(g.home.dy, g.targets[i].dy, i) - IlNodeFan.half,
                          child: _btn(i),
                        ),
                      // 卡片：z-index 1 那一层
                      Transform.translate(
                        // `[data-on]` 那 1px 抬起是卡片自己的事，扇出不跟着动
                        offset: Offset(0, -_lift.value),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: IlNodeFan.band),
                          child: _card(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// `pos = lerp(home, target, n)`，`n = clamp(spring/100, 0, 1.4)`
  double _lerp(double from, double to, int i) {
    final n = _n(i);
    return from + (to - from) * n;
  }

  double _n(int i) => (_springs[i].value / 100).clamp(0.0, _over);

  Widget _card() {
    return Container(
      key: _cardKey,
      width: _cardW,
      padding: const EdgeInsets.all(_pad),
      decoration: BoxDecoration(
        color: _slab,
        borderRadius: BorderRadius.circular(_corner),
      ),
      child: Column(
        // 卡片高是内容撑出来的（参考稿同样如此）：少了 min，Column 会去接
        // 悬停盒那层的松约束，把卡片拉到多出一截空白
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                key: _markKey,
                width: _markS,
                height: _markS,
                decoration: BoxDecoration(
                  color: const Color(0x0FECEAE5), // rgba(ink-rgb,.06)
                  borderRadius: BorderRadius.circular(_markR),
                ),
                child: Center(
                  child: IlIcon(
                    paths: _kCommit,
                    size: 18,
                    viewBox: 24,
                    strokeWidth: 2,
                    color: _slabInk,
                  ),
                ),
              ),
              const SizedBox(width: _topGap),
              Text(_name, style: _nameStyle),
            ],
          ),
          const SizedBox(height: _sayTop),
          // 行高 20.25 在这里落成了 20.0：Flutter 的文本行盒会被摊成整像素，
          // `style.height` 和 `strutStyle.forceStrutHeight` 两条路都一样，
          // 于是三行少 0.75px、整张卡 179.0 而不是参考稿的 179.75。
          // 这条差是引擎的，不拿 SizedBox 去补 —— 补了换一行文案就露馅。
          Text(_say, key: _sayKey, style: _sayStyle),
          const SizedBox(height: _chainTop),
          Row(
            key: _chainKey,
            children: [
              // `.nod-link + .nod-link{margin-left:-6}` —— Flutter 的 Padding 不许为负，
              // 所以这一排改成自己摆：整排宽 = 首颗 + (n-1)*(24-6)
              SizedBox(
                width: _linkS + (_chain.length - 1) * (_linkS + _linkGap),
                height: _linkS,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (var i = 0; i < _chain.length; i++)
                      Positioned(
                        left: i * (_linkS + _linkGap),
                        child: Container(
                          key: _linkKeys[i],
                          width: _linkS,
                          height: _linkS,
                          decoration: BoxDecoration(
                            color: const Color(0x1AECEAE5), // rgba(ink-rgb,.10)
                            shape: BoxShape.circle,
                            // 0 0 0 2px fill-slab：后一个把前一个抠开一圈同色缝
                            boxShadow: const [
                              BoxShadow(color: _slab, blurRadius: 0, spreadRadius: 2),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            _chain[i],
                            style: _linkStyle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: _moreLeft),
              Text('+3', style: _moreStyle),
            ],
          ),
        ],
      ),
    );
  }

  Widget _btn(int i) {
    final pop = _pop0 + (1 - _pop0) * math.min(_n(i), 1);
    final zoom = 1 + 0.12 * _zoom[i].value;
    final spec = _acts[i];
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _aimZoom(i, 1),
      onExit: (_) => _aimZoom(i, 0),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 参考稿的钮没有点击行为 —— 这一块的注册类别就是 Hover。这里留一个空 onTap
        // 把点击吞掉：不吞的话这一笔会穿到悬停盒那层，点钮变成"再点一下卡片"把扇出收了
        onTap: () {},
        child: Transform.scale(
          // 挂个 key：测试要读这一格矩阵，而树上还有悬停盒那层 translate 的 Transform
          key: ValueKey<String>('act-xf-${spec.id}'),
          // CSS 的 scale 绕盒中心：`Transform.scale` 默认 `alignment: center` 已经把支点
          // 摆到盒中心了，再叠一个 origin 会把两次的量加起来推到右下角（实测 1.12 倍时偏 −2.16）
          scale: pop * zoom,
          child: Container(
            key: ValueKey<String>('act-${spec.id}'),
            width: IlNodeFan.btn,
            height: IlNodeFan.btn,
            decoration: const BoxDecoration(color: _slab, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: IlIcon(
              paths: spec.paths,
              size: 16,
              viewBox: 24,
              strokeWidth: 2,
              color: _slabInk,
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 排版与颜色

  static const _slab = Color(0xFF2C2D31); // --fill-slab（暗主题 = --slab-dark）
  static const _slabInk = Color(0xFFF4F3F1); // --fill-on

  static const _stageH = 328.0;

  static const _nameStyle = TextStyle(
    fontFamily: IlFont.family,
    fontFamilyFallback: IlFont.fallback,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.004 * 15,
    color: _slabInk,
  );

  static const _sayStyle = TextStyle(
    fontFamily: IlFont.family,
    fontFamilyFallback: IlFont.fallback,
    fontSize: _sayFont,
    fontWeight: FontWeight.w400,
    height: _sayLh / _sayFont,
    color: Color(0xFF9D9C96), // --ink-3
  );

  static const _linkStyle = TextStyle(
    fontFamily: IlFont.family,
    fontFamilyFallback: IlFont.fallback,
    fontSize: 9.5,
    fontWeight: FontWeight.w700,
    color: Color(0xFF86857F), // --ink-4
  );

  static const _moreStyle = TextStyle(
    fontFamily: IlFont.family,
    fontFamilyFallback: IlFont.fallback,
    fontSize: 11.5,
    fontWeight: FontWeight.w500,
    color: Color(0xFF86857F),
  );

  static const _chain = <String>['MQ', 'TO', 'LA'];

  static final List<Key> _linkKeys = <Key>[
    const ValueKey<String>('link-0'),
    const ValueKey<String>('link-1'),
    const ValueKey<String>('link-2'),
  ];

  static const _cardKey = ValueKey<String>('card');
  static const _markKey = ValueKey<String>('mark');
  static const _sayKey = ValueKey<String>('say');
  static const _chainKey = ValueKey<String>('chain');

  // lucide `git-commit-horizontal`：circle(12,12,r3) + 两条横线
  static const _kCommit = <String>[
    'M15 12A3 3 0 1 1 9 12A3 3 0 1 1 15 12Z',
    'M3 12H9',
    'M15 12H21',
  ];

  static const _acts = <_Act>[
    // link-2
    _Act(
      'connect',
      <String>[
        'M9 17H7A5 5 0 0 1 7 7h2',
        'M15 7h2a5 5 0 1 1 0 10h-2',
        'M8 12H16',
      ],
    ),
    // plus
    _Act('add', <String>['M5 12h14', 'M12 5v14']),
    // copy：rect(8,8,14,14,rx2) 写成 path，端点行为一致
    _Act(
      'duplicate',
      <String>[
        'M10 8H20A2 2 0 0 1 22 10V20A2 2 0 0 1 20 22H10A2 2 0 0 1 8 20V10A2 2 0 0 1 10 8Z',
        'M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2',
      ],
    ),
    // settings-2
    _Act(
      'settings',
      <String>[
        'M14 17H5',
        'M19 7h-9',
        'M20 17A3 3 0 1 1 14 17A3 3 0 1 1 20 17Z',
        'M10 7A3 3 0 1 1 4 7A3 3 0 1 1 10 7Z',
      ],
    ),
  ];
}

class _Act {
  const _Act(this.id, this.paths);
  final String id;
  final List<String> paths;
}

/// 一条按时长推进的补间；`step` 返回"这一帧还在走"
class _Tw {
  _Tw({required this.dur, required this.curve});

  final double dur;
  final Curve curve;
  double _from = 0;
  double _to = 0;
  double _p = 1;
  double _value = 0;

  double get value => _value;

  /// 换目标时从当前显示值接着走（中途反复进出不会跳变）
  void aim(double to) {
    if (to == _to) return;
    _from = _value;
    _to = to;
    _p = 0;
  }

  bool step(double dt) {
    if (_p >= 1) return false;
    _p = (_p + dt / dur).clamp(0.0, 1.0);
    _value = _from + (_to - _from) * curve.transform(_p);
    return _p < 1;
  }
}
