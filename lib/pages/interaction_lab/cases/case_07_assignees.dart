import 'dart:math' as math;

import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/material.dart';

import '../kit.dart';

/// 7. Assignees — 头像条自己变宽，选人浮层从左上角"长"出来
///
/// 这一格的看点是**四套互不同步的运动挂在同一个状态上**：
/// - 头像条（rail）的宽度是**定时补间**（300ms `cubic-bezier(.33,.55,.2,1)`，无过冲），
///   pill 是 `inline-flex`，宽度被 rail 顶开——所以"选人"这件事唯一的反馈就是药丸变宽。
/// - 每张脸是**四路弹簧**：x/y/scale 走 `{660,34,.7}`，rotate 走 `{600,21,.8}`，
///   透明度是 120ms 补间。进场从 scale .2、上方 10px、−22° 弹进来；退场往下 6px、
///   +14°、缩回 .2。移除一张脸时**留下的那几张要横向并过来**（x 目标变了），
///   于是同一帧里既有退场又有让位。
/// - 浮层本体走 `{460,23,.9}` 的 x/y/scaleX/scaleY，`transform-origin:0 0`
///   → 从左上角长出来，不是居中放大。
/// - 浮层里 4 行**逐个进场**：同一套弹簧，delay 依次 30/70/110/150ms。
///
/// 两条容易做错的：
/// 1. **脸之间的 2px 白环是 `box-shadow:0 0 0 2px`，在盒子外面**。用 `Border.all`
///    会画进 28 里、把脸挤成 24；`BoxShadow(spreadRadius:2, blurRadius:0)` 才是同一件事。
///    环色取卡片底而不是写死白，深色档才不会发光。
/// 2. **靠前者压靠后者**（`zIndex = 总数 − 序号`）。Flutter 的 Stack 是"后画的在上面"，
///    所以喂给 Stack 的顺序要按 z 升序排，跟选中顺序正好相反。
///
/// 参考稿还有 `Row`/`Grid` 两档排布和 `corner`/`overlap` 两个旋钮，那是演示站的设备，
/// 不是组件的一部分——这里按默认值钉死：Row、corner 22、overlap 10。
/// 头像在参考稿是 4 张内联 base64 照片；组件规格里只有"28/32 的圆 + 2px 环 + 叠放"，
/// 所以这里换成同一颗圆上的首字母，几何、层级、动效一个没少。
class Case07Assignees extends StatefulWidget {
  const Case07Assignees({super.key});

  @override
  State<Case07Assignees> createState() => _Case07AssigneesState();
}

class _Case07AssigneesState extends State<Case07Assignees> with SingleTickerProviderStateMixin {
  // ---------------------------------------------------------------- 量出来的尺寸

  static const _rootW = 264.0;
  static const _rootH = 268.0;
  static const _stageH = 280.0;

  /// `corner` 旋钮默认 22；行圆角是 `max(0, corner − 6)`
  static const _corner = 22.0;
  static const _rowR = 16.0;

  static const _pillH = 44.0;
  static const _padL = 8.0;
  static const _padR = 12.0;

  /// `.pik-pill{gap:10px}`；chevron 的 `margin-left:-2` 和 say 的 `-6`
  /// 都在 gap 后面，等价于把那一段 gap 缩短——按这个口径摆，药丸总宽才对得上
  static const _gap = 10.0;
  static const _chevGap = _gap - 2.0;
  static const _sayGap = _gap - 6.0;

  static const _face = 28.0;

  /// `overlap` 旋钮默认 10 → Row 步进 `28 − 10`
  static const _step = 18.0;

  static const _cardTop = 54.0;
  static const _cardPad = 6.0;
  static const _rowH = 48.0;
  static const _rowW = _rootW - _cardPad * 2; // 252
  static const _cardH = _cardPad * 2 + _rowH * 4; // 204

  static const _av = 32.0;
  static const _mark = 18.0;
  static const _markR = 5.5;
  static const _markB = 1.5;
  static const _chevSize = 16.0;

  // ---------------------------------------------------------------- 颜色档

  static const _slab = IlColor.pane; // `--fill-slab`：浅档就是白
  static const _on = IlColor.ink; // `--fill-on`
  static const _edge = IlColor.paneEdge; // `--pane-edge`：rgba(23,24,26,.08)

  static const _chevron2 = ['M6 9l6 6 6-6'];
  static const _check2 = ['M20 6L9 17l-5-5'];

  // ---------------------------------------------------------------- 状态

  /// 参考稿 `useState(true)` / `useState(['kai','mara'])`：默认展开、默认选中前两条
  bool _open = true;
  final List<String> _picked = [_people[0].id, _people[1].id];

  /// 在场和正在退场的脸都在这儿；退场走完才摘掉
  final List<_Face> _faces = [];

  /// 浮层：null = 已经退完、真的不在树上了
  _Panel? _panel;

  /// 4 行的常驻运动（悬停底、勾选框填色、勾的进出），跟浮层同生命周期之外也要活着
  late final List<_RowMot> _rows = [for (var i = 0; i < 4; i++) _RowMot(on: _picked.contains(_people[i].id))];

  /// rail 宽度和 chevron 转角是定时补间，不是弹簧
  late final _Twn _rail = _Twn(from: _railTarget, dur: 300, curve: _railEase);
  late final _Twn _chevRot = _Twn(from: 180, dur: 240, curve: _railEase);
  late final _Twn _chevInk = _Twn(from: 0.4, dur: 150, curve: _cssEase);

  Ticker? _ticker;
  Duration _last = Duration.zero;

  /// `f = picked.length ? 28 + (n-1)*18 : 0`
  double get _railTarget => _picked.isEmpty ? 0 : _face + (_picked.length - 1) * _step;

  @override
  void initState() {
    super.initState();
    // `AnimatePresence initial={false}`：首屏那两张脸是"已经在那儿"的，不弹进来
    for (final id in _picked) {
      _faces.add(_Face(_person(id), x: _picked.indexOf(id) * _step));
    }
    _relayout();
    // 浮层这一层没关 initial：首屏就从 y −10、scale .86/.72 弹开，行按 delay 逐个进
    _panel = _Panel();
    _aimPanel(open: true);
    _kick();
  }

  @override
  void dispose() {
    _ticker?.stop();
    super.dispose();
  }

  // ---------------------------------------------------------------- 动作

  void _toggleOpen() {
    _open = !_open;
    _panel ??= _Panel();
    _aimPanel(open: _open);
    _chevRot.aim(_open ? 180 : 0);
    _kick();
  }

  /// 开：弹簧回到位、行重新走一遍 stagger；关：整块往上退 8、缩到 .92/.86、淡 120ms
  void _aimPanel({required bool open}) {
    final p = _panel!;
    p.closing = !open;
    p.y.aim(open ? 0 : -8);
    p.wx.aim(open ? 1 : 0.92);
    p.wy.aim(open ? 1 : 0.86);
    p.o.aim(open ? 1 : 0);
    if (open) {
      for (final r in p.rows) {
        r.aim();
      }
    }
  }

  /// row 点击：已选 → 摘掉；未选 → 追加。顺序就是点选顺序，不是列表顺序
  void _togglePerson(int i) {
    final id = _people[i].id;
    if (_picked.contains(id)) {
      _picked.remove(id);
      _faces.firstWhere((f) => f.id == id && !f.leaving).leave();
    } else {
      _picked.add(id);
      final leaving = _faces.where((f) => f.id == id && f.leaving);
      if (leaving.isEmpty) {
        _faces.add(_Face(_people[i], x: (_picked.length - 1) * _step, born: true));
      } else {
        // 上一张还在退场就把它捞回来重播进场：再建一张会让两张脸共用同一个 key
        leaving.first.revive();
      }
    }
    // 摘掉的让位、新加的落位、压叠关系重排，都只看 `_picked` 现在的顺序
    _relayout();
    _rows[i].toggle();
    _rail.aim(_railTarget);
    _kick();
  }

  /// 摘掉一张脸之后，留下的那几张要并过来；退场那张钉在原来的 x 上不动
  void _relayout() {
    for (final f in _faces) {
      if (f.leaving) continue;
      final idx = _picked.indexOf(f.id);
      f.z = _people.length - idx;
      f.aimTo(idx * _step);
    }
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
    live |= _rail.step(dt);
    live |= _chevRot.step(dt);
    live |= _chevInk.step(dt);
    for (final f in _faces) {
      live |= f.step(dt);
    }
    _faces.removeWhere((f) => f.leaving && f.done);
    if (_panel != null) {
      live |= _panel!.step(dt);
      // 退完就真的从树上摘掉：留一层 Opacity(0) 会隔着半张卡吞点击
      if (_panel!.closing && _panel!.done) _panel = null;
    }
    for (final r in _rows) {
      live |= r.step(dt);
    }
    live |= _hoverFade(dt);
    setState(() {});
    if (!live) _ticker!.stop();
  }

  /// 悬停底是每行一条 140ms 补间，收在这儿走
  bool _hoverFade(double dt) {
    var live = false;
    for (var i = 0; i < 4; i++) {
      live |= _rows[i].wash.aim(_hover == i ? 0.05 : 0).step(dt);
    }
    return live;
  }

  // ---------------------------------------------------------------- 树

  @override
  Widget build(BuildContext context) {
    return IlStage(
      height: _stageH,
      child: SizedBox(
        width: _rootW,
        height: _rootH,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // pill 是 z-index 2、card 是 1 → 先画浮层
            if (_panel != null) _panelBox(),
            _pill(),
          ],
        ),
      ),
    );
  }

  /// `.pik-pill`：宽 = 8 + rail + 8 + 16 + 12，rail 一动整颗药丸跟着变
  Widget _pill() {
    final empty = _picked.isEmpty;
    return Positioned(
      left: 0,
      top: 0,
      height: _pillH,
      child: MouseRegion(
        key: const ValueKey('pill'),
        cursor: SystemMouseCursors.click,
        // 悬停只动 chevron 的色（`.pik-pill:hover .pik-chev{color:...75}`），药丸本身没反馈
        onEnter: (_) => setState(() {
          _chevInk.aim(0.75);
          _kick();
        }),
        onExit: (_) => setState(() {
          _chevInk.aim(0.4);
          _kick();
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleOpen,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: _slab,
              borderRadius: BorderRadius.all(Radius.circular(_corner)),
              // `[data-stroke=on] .pik-pill{box-shadow:0 0 0 1px var(--pane-edge)}`
              boxShadow: [BoxShadow(color: _edge, spreadRadius: 1)],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(_padL, 0, _padR, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _railBox(),
                  if (empty) ...[
                    const SizedBox(width: _sayGap),
                    const Text('Unassigned', style: _sayStyle),
                  ],
                  const SizedBox(width: _chevGap),
                  _chev(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// `.pik-rail`：宽度是被补间驱动的那个数，脸用 transform 摆在里面
  Widget _railBox() => SizedBox(
        key: const ValueKey('rail'),
        width: _rail.v,
        height: _face,
        child: Stack(
          clipBehavior: Clip.none,
          // 靠前者压靠后者 → z 升序喂给 Stack
          children: [
            for (final f in [..._faces]..sort((a, b) => a.z.compareTo(b.z))) _faceBox(f),
          ],
        ),
      );

  Widget _faceBox(_Face f) => Positioned(
        left: 0,
        top: 0,
        width: _face,
        height: _face,
        child: Transform.translate(
          // CSS 的合成顺序是 translate → scale → rotate，对点而言是反过来的：
          // 先转、再缩、最后平移，所以这三层嵌套也得这么排
          offset: Offset(f.x.v, f.y.v),
          child: Transform.scale(
            scale: f.s.v,
            child: Transform.rotate(
              angle: f.r.v * math.pi / 180,
              // 这颗 key 挂在 transform 的**内侧**：RenderTransform 自己的坐标系
              // 是不带这道位移的，测试要在外面读"这张脸被摆到了哪"只能往下取
              child: Opacity(
                key: ValueKey('face-${f.id}'),
                opacity: f.o.v.clamp(0.0, 1.0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: f.person.tint,
                    shape: BoxShape.circle,
                    // 2px 环在盒子**外面**：spreadRadius 才是 box-shadow 的口径
                    boxShadow: const [BoxShadow(color: _slab, spreadRadius: 2)],
                  ),
                  child: Center(
                    child: Text(
                      f.person.initials,
                      style: TextStyle(
                        fontFamily: IlFont.family,
                        fontFamilyFallback: IlFont.fallback,
                        fontSize: _face * 0.36,
                        fontWeight: FontWeight.w500,
                        height: 1,
                        color: f.person.fg,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Widget _chev() => Transform.rotate(
        angle: _chevRot.v * math.pi / 180,
        child: IlIcon(
          key: const ValueKey('chev'),
          paths: _chevron2,
          size: _chevSize,
          viewBox: 24,
          strokeWidth: 2.2,
          color: _on.withValues(alpha: _chevInk.v),
        ),
      );

  /// `.pik-card`：退完真的从树上摘掉；退场途中不让它吞点击
  Widget _panelBox() {
    final p = _panel!;
    return Positioned(
      key: const ValueKey('card'),
      left: 0,
      top: _cardTop,
      width: _rootW,
      height: _cardH,
      child: IgnorePointer(
        ignoring: p.closing,
        child: Transform.translate(
          offset: Offset(0, p.y.v),
          child: Transform.scale(
            scaleX: p.wx.v,
            scaleY: p.wy.v,
            alignment: Alignment.topLeft,
            child: Opacity(
              opacity: p.o.v.clamp(0.0, 1.0),
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: _slab,
                  borderRadius: BorderRadius.all(Radius.circular(_corner)),
                  boxShadow: [BoxShadow(color: _edge, spreadRadius: 1)],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(_cardPad),
                  child: Column(
                    children: [
                      for (var i = 0; i < 4; i++) //
                        _row(i, p.rows[i]),
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

  Widget _row(int i, _RowIn in_) {
    final person = _people[i];
    final m = _rows[i];
    return Transform.translate(
      offset: Offset(0, in_.y.v),
      child: Opacity(
        key: ValueKey('rowfade$i'),
        opacity: in_.o.v.clamp(0.0, 1.0),
        child: SizedBox(
          key: ValueKey('row$i'),
          width: _rowW,
          height: _rowH,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() {
              _hover = i;
              _kick();
            }),
            onExit: (_) => setState(() {
              if (_hover == i) _hover = null;
              _kick();
            }),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _togglePerson(i),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _on.withValues(alpha: m.wash.v),
                  borderRadius: BorderRadius.all(Radius.circular(_rowR)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      _avBox(person),
                      const SizedBox(width: _gap),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(person.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _nameStyle),
                            const SizedBox(height: 1),
                            Text(person.role, maxLines: 1, overflow: TextOverflow.ellipsis, style: _roleStyle),
                          ],
                        ),
                      ),
                      const SizedBox(width: _gap),
                      _markBox(i, m),
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

  Widget _avBox(_Person p) => DecoratedBox(
        decoration: BoxDecoration(color: p.tint, shape: BoxShape.circle),
        child: SizedBox(
          width: _av,
          height: _av,
          child: Center(
            child: Text(
              p.initials,
              style: TextStyle(
                fontFamily: IlFont.family,
                fontFamilyFallback: IlFont.fallback,
                fontSize: _av * 0.36,
                fontWeight: FontWeight.w500,
                height: 1,
                color: p.fg,
              ),
            ),
          ),
        ),
      );

  /// `.pik-mark`：底色和描边一起 160ms `ease`；勾是弹簧进、弹簧出
  Widget _markBox(int i, _RowMot m) => SizedBox(
        key: ValueKey('mark$i'),
        width: _mark,
        height: _mark,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _on.withValues(alpha: m.fill.v),
            borderRadius: BorderRadius.all(Radius.circular(_markR)),
            border: Border.all(
              color: Color.lerp(_on.withValues(alpha: 0.22), _on, m.fill.v)!,
              width: _markB,
            ),
          ),
          child: m.tick.v <= 0.001
              ? null
              : Center(
                  child: Transform.scale(
                    scale: m.tick.v,
                    child: Opacity(
                      opacity: m.tickO.v.clamp(0.0, 1.0),
                      child: IlIcon(
                        paths: _check2,
                        size: 12,
                        viewBox: 24,
                        strokeWidth: 3,
                        color: _slab,
                      ),
                    ),
                  ),
                ),
        ),
      );

  int? _hover;

  static const _sayStyle = TextStyle(
    fontFamily: IlFont.family,
    fontFamilyFallback: IlFont.fallback,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1,
    color: _on,
  );

  static const _nameStyle = TextStyle(
    fontFamily: IlFont.family,
    fontFamilyFallback: IlFont.fallback,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: _on,
  );

  static const _roleStyle = TextStyle(
    fontFamily: IlFont.family,
    fontFamilyFallback: IlFont.fallback,
    fontSize: 11.5,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: Color(0x7317181A), // rgba(23,24,26,.45)
  );
}

// ---------------------------------------------------------------- 数据

/// CSS 不写曲线就是 `ease`
const _cssEase = Cubic(0.25, 0.1, 0.25, 1);

/// framer 只写 duration 不写 ease 时用的是它自己的 easeOut 表
const _framerOut = Cubic(0, 0.58, 1, 1);

/// `.33,.55,.2,1`——rail 和 chevron 共用，全程无过冲
const _railEase = Cubic(0.33, 0.55, 0.2, 1);

@immutable
class _Person {
  const _Person(this.id, this.name, this.role, this.tint, this.fg);

  final String id;
  final String name;
  final String role;

  /// 参考稿是 4 张内联照片；这里换成同一颗圆上的首字母，圆径/环/叠放完全照抄
  final Color tint;
  final Color fg;

  String get initials {
    final w = name.split(' ');
    return '${w.first[0]}${w.length > 1 ? w.last[0] : ''}';
  }
}

const _people = <_Person>[
  _Person('kai', 'Adam Marsh', 'Design', Color(0xFFE4DFD7), Color(0xFF6C6459)),
  _Person('mara', 'Priya Raman', 'Research', Color(0xFFD9E2E9), Color(0xFF5A6B79)),
  _Person('sofia', 'Nora Wilder', 'Engineering', Color(0xFFDFE5DA), Color(0xFF61705A)),
  _Person('ines', 'Marco Bellini', 'Product', Color(0xFFEBE0E1), Color(0xFF7B6266)),
];

_Person _person(String id) => _people.firstWhere((p) => p.id == id);

// ---------------------------------------------------------------- 运动值

/// 弹簧：包一层 `IlSpring.phys`，加上 framer 的 `delay` 语义（delay 内一步都不走）
class _Spr {
  _Spr({required double s, required double d, double m = 1, required double from, this.delay = 0})
      : _sp = IlSpring.phys(stiffness: s, damping: d, mass: m, from: from);

  final IlSpring _sp;
  final double delay;
  double _e = 0;
  bool _armed = false;

  double get v => _sp.value;
  bool get done => !_armed || _sp.atRest;

  void aim(double target) {
    _e = 0;
    _armed = true;
    _sp.aim(target);
  }

  /// 直接落位：不进场的初始态、以及"退场中途被捞回来重播进场"那一类
  void jumpTo(double x) {
    _armed = false;
    _e = 0;
    _sp.jumpTo(x);
  }

  bool step(double dt) {
    if (!_armed || _sp.atRest) return false;
    _e += dt;
    if (_e < delay) return true;
    _sp.step(dt);
    return !_sp.atRest;
  }
}

/// 定时补间：CSS `transition` 那一族——换目标从**当前显示值**接着走，不跳变
class _Twn {
  _Twn({required double from, required this.dur, this.curve = _cssEase})
      : _v = from,
        _from = from,
        _to = from;

  final double dur;
  final Curve curve;
  double _from;
  double _to;
  double _v;
  double _e = 0;
  bool _running = false;

  double get v => _v;
  bool get done => !_running;

  /// 目标没变就**不要**重起：每帧都 aim 同一个值会把 `_e` 清零，钟永远停不下来
  _Twn aim(double target) {
    if (_to == target) return this;
    _from = _v;
    _to = target;
    _e = 0;
    _running = true;
    return this;
  }

  bool step(double dt) {
    if (!_running) return false;
    _e += dt;
    final p = (_e / dur).clamp(0.0, 1.0);
    _v = _from + (_to - _from) * curve.transform(p);
    if (p >= 1) _running = false;
    return _running;
  }

  void jumpTo(double x) {
    _v = x;
    _from = x;
    _to = x;
    _e = 0;
    _running = false;
  }
}

/// 一张脸：x/y/scale 一路弹簧，rotate 另一路，透明度是 120ms 补间
class _Face {
  _Face(this.person, {required double x, bool born = false})
      : id = person.id,
        z = 0,
        x = _Spr(s: 660, d: 34, m: 0.7, from: x),
        y = _Spr(s: 660, d: 34, m: 0.7, from: born ? -10 : 0),
        s = _Spr(s: 660, d: 34, m: 0.7, from: born ? 0.2 : 1),
        r = _Spr(s: 600, d: 21, m: 0.8, from: born ? -22 : 0),
        o = _Twn(from: born ? 0 : 1, dur: 120, curve: _framerOut) {
    _lastX = x;
  }

  final String id;
  final _Person person;

  /// `zIndex = 总数 − 序号`：靠前者压靠后者，退场那张钉在退场前的层级
  int z;
  bool leaving = false;

  final _Spr x;
  final _Spr y;
  final _Spr s;
  final _Spr r;
  final _Twn o;
  late double _lastX;

  bool get done => x.done && y.done && s.done && r.done && o.done;

  /// 进场/让位：目标就是这一行的摆位
  void aimTo([double? tx]) {
    final t = tx ?? _lastX;
    _lastX = t;
    x.aim(t);
    y.aim(0);
    s.aim(1);
    r.aim(0);
    o.aim(1);
  }

  /// 退场途中被重新勾选：落回进场的起点，让 `_relayout` 那一次 `aimTo` 重播进场
  void revive() {
    leaving = false;
    y.jumpTo(-10);
    s.jumpTo(0.2);
    r.jumpTo(-22);
    o.jumpTo(0);
  }

  /// 退场：往下 6px、+14°、缩回 .2，透明度 120ms
  void leave() {
    leaving = true;
    x.aim(_lastX);
    y.aim(-6);
    s.aim(0.2);
    r.aim(14);
    o.aim(0);
  }

  bool step(double dt) {
    var live = false;
    live |= x.step(dt);
    live |= y.step(dt);
    live |= s.step(dt);
    live |= r.step(dt);
    live |= o.step(dt);
    return live;
  }
}

/// 浮层本体：y/scaleX/scaleY 共用 `{460,23,.9}`，透明度 120ms
class _Panel {
  _Panel()
      : y = _Spr(s: 460, d: 23, m: 0.9, from: -10),
        wx = _Spr(s: 460, d: 23, m: 0.9, from: 0.86),
        wy = _Spr(s: 460, d: 23, m: 0.9, from: 0.72),
        o = _Twn(from: 0, dur: 120, curve: _framerOut),
        rows = [
          for (var i = 0; i < 4; i++) //
            _RowIn(i),
        ];

  final _Spr y;
  final _Spr wx;
  final _Spr wy;
  final _Twn o;

  /// 4 行的 stagger 进场
  final List<_RowIn> rows;
  bool closing = false;

  bool get done =>
      y.done && wx.done && wy.done && o.done && rows.every((r) => r.done);

  bool step(double dt) {
    var live = false;
    live |= y.step(dt);
    live |= wx.step(dt);
    live |= wy.step(dt);
    live |= o.step(dt);
    for (final r in rows) {
      live |= r.step(dt);
    }
    return live;
  }
}

/// 一行进场：`{620,34,.7}` 的弹簧同时驱动位移和透明度，delay 依次 30/70/110/150ms
class _RowIn {
  _RowIn(int i)
      : y = _Spr(s: 620, d: 34, m: 0.7, from: -8, delay: _kDelay(i)),
        o = _Spr(s: 620, d: 34, m: 0.7, from: 0, delay: _kDelay(i));

  static double _kDelay(int i) => 30.0 * i + 30;

  final _Spr y;
  final _Spr o;

  bool get done => y.done && o.done;

  void aim() {
    y.aim(0);
    o.aim(1);
  }

  bool step(double dt) {
    // 或运算不能短路掉 step：两路都得被推进
    final a = y.step(dt);
    final b = o.step(dt);
    return a || b;
  }
}

/// 一行常驻的运动：悬停底 140ms、勾选框填色 160ms、勾的弹簧
class _RowMot {
  _RowMot({required bool on})
      : _on = on,
        fill = _Twn(from: on ? 1 : 0, dur: 160, curve: _cssEase),
        tick = _Spr(s: 600, d: 28, m: 0.6, from: on ? 1 : 0.4),
        tickO = _Spr(s: 600, d: 28, m: 0.6, from: on ? 1 : 0);

  final _Twn wash = _Twn(from: 0, dur: 140, curve: _cssEase);
  final _Twn fill;
  final _Spr tick;
  final _Spr tickO;
  bool _on;

  void toggle() {
    _on = !_on;
    fill.aim(_on ? 1 : 0);
    tick.aim(_on ? 1 : 0.4);
    tickO.aim(_on ? 1 : 0);
  }

  bool step(double dt) {
    var live = false;
    live |= wash.step(dt);
    live |= fill.step(dt);
    live |= tick.step(dt);
    live |= tickO.step(dt);
    return live;
  }
}
