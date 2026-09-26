import 'package:flutter/scheduler.dart' show Ticker;

import 'package:flutter/material.dart';

import '../kit.dart';

/// `cubic-bezier(.25,.1,.25,1)`——CSS 不写缓动名时的那条
const _cssEase = Cubic(0.25, 0.1, 0.25, 1);

/// `[data-sink=true]` 那条 `scale .12s`
const _sinkEase = Cubic(0.35, 0, 0.5, 1);

/// 8. Create menu — 一颗药丸按下去先压一下，再整块长成菜单
///
/// 四套互不同步的时钟挂在同一次点击上：
/// - **主体形变**：`width/height/borderRadius` 三个量各吃一条同参数弹簧
///   `{420,30,.5}`，同时起步（"一次展开是一个动作"）。关 `pillW×38`、圆角 19，
///   开 `212×166`、圆角 28。
/// - **按压**：按下先进 sink 态 60ms，到点自己置 false 并展开。scale 走 CSS 那条
///   transition：压到 .94 用 120ms `cubic-bezier(.35,0,.5,1)`，回到 1 用 340ms
///   `cubic-bezier(.22,1,.36,1)`——**它和尺寸弹簧是两套钟**，回弹会盖在形变上面走。
/// - **药丸淡出**：开 120ms、关 160ms（基础规则的时长），只淡不缩。
/// - **四行进场**：delay 依次 30/52/74/96ms，透明度 150ms `ease`、位移 6px→0
///   240ms `cubic-bezier(.22,1,.36,1)`。关闭时 delay 全部归零，四行一起退。
///
/// hover 点亮的是两层：文字色 `.78→1`（200ms `ease`），以及行底那层 8% 墨水 wash
/// （`:before` 的 opacity，基础规则 220ms、`:hover` 那条盖成 140ms——**进快出慢**）。
/// 水洗圆角是行圆角 17，压在图标和文字底下（`z-index:-1` + `isolation:isolate`）。
///
/// 三条容易做错的：
/// 1. **药丸宽是量出来的**：`26 + 标签实测宽 + 34`，标签宽按 `offsetWidth` 取整再 +1。
///    首帧那个兜底值 96 不是最终值，照抄会让关态宽出 50 多像素。
/// 2. **sink 的 60ms 用 Ticker 累计，不用 `Timer`**：定时器在 test 收尾时还挂着会报
///    "A Timer is still pending"，而这一段本来就和 scale 那条 120ms 补间同一条钟。
/// 3. **点击判定用面板自己的 `212×166` 矩形**，不是 244 方舞台：落在面板矩形内不收回，
///    矩形外才收回；点某一项也收回。没有关闭按钮，也没有标题栏。
///
/// 参考稿还有 `corner` 旋钮（0–40，默认 28），那是演示站的设备，不是组件的一部分：
/// 这里按默认值钉死——开态圆角 28、关态 `min(19, 28·19/28)=19`、行圆角
/// `min(17, 28−10)=17`。
class Case08CreateMenu extends StatefulWidget {
  const Case08CreateMenu({super.key});

  @override
  State<Case08CreateMenu> createState() => _Case08CreateMenuState();
}

class _Case08CreateMenuState extends State<Case08CreateMenu> with SingleTickerProviderStateMixin {
  // ---------------------------------------------------------------- 量出来的尺寸

  /// `.crt-stage`：244 见方，组件坐在正中（`inset:0;margin:auto`）
  static const _rootSide = 244.0;

  /// 这格舞台只要比 244 高一点就够
  static const _stageH = 256.0;

  static const _panelW = 212.0;
  static const _panelH = 166.0;
  static const _pillH = 38.0;

  /// corner=28 代入的三个圆角：开态 28、关态 `min(19, 28·19/28)=19`、行 `min(17, 28−10)=17`
  static const _rOpen = 28.0;
  static const _rShut = 19.0;
  static const _rowR = 17.0;

  /// `.crt-item button:before` 的那层水洗：`rgba(on-slab, .08)`
  static const _washA = 0.08;

  /// `.crt-panel{padding:11px 10px}` → 行宽 = 212 − 20
  static const _padV = 11.0;
  static const _padH = 10.0;
  static const _rowW = _panelW - _padH * 2; // 192
  static const _rowH = 34.0;
  static const _rowGap = 2.0;

  /// 行内：左右 14、图标 15、图标与文字 gap 10
  static const _rowPadH = 14.0;
  static const _icon = 15.0;
  static const _rowIconGap = 10.0;

  /// 药丸：`26 + 标签 + 34`，里面是 16 的加号 + 8 的 gap + 标签盒
  static const _pillPadL = 26.0;
  static const _pillPadR = 34.0;
  static const _glyph = 16.0;
  static const _glyphGap = 8.0;
  static const _sayFont = 13.5;
  static const _rowFont = 13.0;

  /// sink 态持续多久才换成展开
  static const _sinkMs = 60.0;

  // ---------------------------------------------------------------- 颜色档

  static const _slab = IlColor.pane; // `--fill-slab`：浅档就是白
  static const _on = IlColor.ink; // `--fill-on`
  static const _edge = IlColor.paneEdge; // `[data-stroke=on]{box-shadow:0 0 0 1px}`

  // ---------------------------------------------------------------- 图标（内联 svg 的 path）

  static const _plus = ['M5 12h14', 'M12 5v14'];
  static const _fileText = [
    'M6 22a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h8a2.4 2.4 0 0 1 1.704.706l3.588 3.588A2.4 2.4 0 0 1 20 8v12a2 2 0 0 1-2 2z',
    'M14 2v5a1 1 0 0 0 1 1h5',
    'M10 9H8',
    'M16 13H8',
    'M16 17H8',
  ];
  static const _table2 = [
    'M9 3H5a2 2 0 0 0-2 2v4m6-6h10a2 2 0 0 1 2 2v4M9 3v18m0 0h10a2 2 0 0 0 2-2V9M9 21H5a2 2 0 0 1-2-2V9m0 0h18',
  ];

  /// grid-2x2 原来是 `<rect x=3 y=3 width=18 height=18 rx=2>`，换成等价的描边 path
  static const _grid2x2 = [
    'M12 3v18',
    'M3 12h18',
    'M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z',
  ];
  static const _folder = [
    'M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2z',
  ];

  static const _items = [
    ('Document', _fileText),
    ('Spreadsheet', _table2),
    ('Board', _grid2x2),
    ('Folder', _folder),
  ];

  // ---------------------------------------------------------------- 标签宽度

  static const _sayStyle = TextStyle(
    fontFamily: IlFont.family,
    fontFamilyFallback: IlFont.fallback,
    fontSize: _sayFont,
    fontWeight: FontWeight.w400,
    color: _on,
  );

  /// `span.offsetWidth + 1`：浏览器给的是取整的盒宽，参考稿再补 1
  static final double _labelW = () {
    final tp = TextPainter(textDirection: TextDirection.ltr, text: const TextSpan(text: 'Create', style: _sayStyle))
      ..layout();
    return tp.width.roundToDouble() + 1;
  }();

  static double get _pillW => _pillPadL + _labelW + _pillPadR;

  /// 面板的可视矩形（根盒局部坐标）——"点在外面才收"就按它判
  static const _panelRect = Rect.fromLTRB(
    (_rootSide - _panelW) / 2,
    (_rootSide - _panelH) / 2,
    (_rootSide + _panelW) / 2,
    (_rootSide + _panelH) / 2,
  );

  // ---------------------------------------------------------------- 状态

  bool _open = false;
  bool _sinking = false;

  /// sink 态已走的毫秒数（走满 [_sinkMs] 就换成展开）
  double _sinkWait = 0;

  /// 展开时指针落在第几行（-1 = 不在任何行上）
  int _hover = -1;

  /// 主体三条同参数弹簧
  late final IlSpring _w = IlSpring.phys(stiffness: 420, damping: 30, mass: 0.5, from: _pillW);
  late final IlSpring _h = IlSpring.phys(stiffness: 420, damping: 30, mass: 0.5, from: _pillH);
  late final IlSpring _r = IlSpring.phys(stiffness: 420, damping: 30, mass: 0.5, from: _rShut);

  late final _Twn _scale = _Twn(1, dur: 120, curve: _sinkEase);
  late final _Twn _pillO = _Twn(1, dur: 160, curve: _cssEase);
  late final List<_Item> _rows = [for (var i = 0; i < _items.length; i++) _Item(i)];
  late final List<_Twn> _rowInk = [
    for (var i = 0; i < _items.length; i++) _Twn(0, dur: 200, curve: _cssEase),
  ];

  /// 行底水洗：基础规则 220ms，`:hover` 那条盖成 140ms → 进快出慢
  late final List<_Twn> _rowWash = [
    for (var i = 0; i < _items.length; i++) _Twn(0, dur: 220, curve: _cssEase),
  ];

  Ticker? _ticker;
  Duration _last = Duration.zero;

  // ---------------------------------------------------------------- 动作

  /// 按下：先进 sink，[_sinkMs] 之后自己换成展开
  void _press() {
    // 连点按参考稿的 `clearTimeout` 口径：把这段重新计一遍，不叠加
    _sinking = true;
    _sinkWait = 0;
    _scale.aim(0.94, dur: 120, curve: _sinkEase);
    _kick();
  }

  void _expand() {
    _sinking = false;
    _open = true;
    _w.aim(_panelW);
    _h.aim(_panelH);
    _r.aim(_rOpen);
    _scale.aim(1, dur: 340, curve: IlEase.smoothOut);
    _pillO.aim(0, dur: 120, curve: _cssEase);
    for (final it in _rows) {
      it.aim(open: true);
    }
  }

  /// 收回：点面板矩形外、或点某一项，两条路径
  void _close() {
    if (!_open) return;
    _open = false;
    _w.aim(_pillW);
    _h.aim(_pillH);
    _r.aim(_rShut);
    _pillO.aim(1, dur: 160, curve: _cssEase);
    for (final it in _rows) {
      it.aim(open: false);
    }
    _kick();
  }

  void _hoverRow(int i) {
    if (_hover == i) return;
    _hover = i;
    for (var j = 0; j < _rowInk.length; j++) {
      final on = j == i;
      // 文字色 `transition:color .2s`；水洗那条是 140ms（进）/ 220ms（出）
      _rowInk[j].aim(on ? 1 : 0);
      _rowWash[j].aim(on ? 1 : 0, dur: on ? 140 : 220);
    }
    _kick();
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

    for (final s in [_w, _h, _r]) {
      s.step(dt);
      live |= !s.atRest;
    }
    live |= _scale.step(dt);
    live |= _pillO.step(dt);
    for (final it in _rows) {
      live |= it.step(dt);
    }
    for (final t in _rowInk) {
      live |= t.step(dt);
    }
    for (final t in _rowWash) {
      live |= t.step(dt);
    }

    if (_sinking) {
      _sinkWait += dt;
      live = true;
      if (_sinkWait >= _sinkMs) _expand();
    }

    setState(() {});
    if (!live) _ticker!.stop();
  }

  // ---------------------------------------------------------------- 树

  @override
  void dispose() {
    _ticker?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IlStage(
      height: _stageH,
      child: SizedBox(
        width: _rootSide,
        height: _rootSide,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // 参考稿挂在 document 上的 pointerdown：落在面板矩形外就收回。
            // 压在面板/行下面，靠"上面的 absorbing 命中就不轮到自己"来放行内点击
            Positioned.fill(
              child: Listener(
                key: const ValueKey('outside'),
                behavior: HitTestBehavior.translucent,
                onPointerDown: (ev) {
                  if (_open && !_panelRect.contains(ev.localPosition)) _close();
                },
              ),
            ),
            // sink 只压药丸那一簇：面板不吃这道 scale
            Transform.scale(
              key: const ValueKey('sink'),
              scale: _scale.v,
              child: SizedBox(
                width: _rootSide,
                height: _rootSide,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [_body(), _pillBox()],
                ),
              ),
            ),
            _panelBox(),
          ],
        ),
      ),
    );
  }

  /// `.crt-body`：白块本体，宽/高/圆角同一帧各读各的弹簧
  Widget _body() {
    final radius = _r.value.clamp(0.0, 40.0);
    return SizedBox(
      key: const ValueKey('body'),
      width: _w.value,
      height: _h.value,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _slab,
          borderRadius: BorderRadius.all(Radius.circular(radius)),
          // `box-shadow:0 0 0 1px` 在盒子外面，不是 Border
          boxShadow: const [BoxShadow(color: _edge, spreadRadius: 1, blurRadius: 0)],
        ),
      ),
    );
  }

  Widget _pillBox() {
    return Opacity(
      key: const ValueKey('pillfade'),
      opacity: _pillO.v.clamp(0.0, 1.0),
      // `[data-open=true] .crt-pill{pointer-events:none}`
      child: IgnorePointer(
        ignoring: _open,
        child: SizedBox(
          width: _pillW,
          height: _pillH,
          child: MouseRegion(
            key: const ValueKey('pill'),
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _press,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IlIcon(paths: _plus, size: _glyph, viewBox: 24, strokeWidth: 2, color: _on),
                  const SizedBox(width: _glyphGap),
                  // `.crt-say` 是定宽 + overflow:hidden 的盒，文字左对齐
                  SizedBox(
                    width: _labelW,
                    child: const Text('Create', style: _sayStyle, maxLines: 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _panelBox() {
    return IgnorePointer(
      ignoring: !_open,
      child: SizedBox(
        width: _panelW,
        height: _panelH,
        key: const ValueKey('panel'),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // 落在面板矩形里（行与行之间那 2px 也算）不收回
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: _padV, horizontal: _padH),
            child: Column(
              // `align-content:start`：4×34 + 3×2 = 142，比 144 少的那 2px 留在下面
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                for (var i = 0; i < _items.length; i++) ...[
                  if (i > 0) const SizedBox(height: _rowGap),
                  _rowBox(i),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _rowBox(int i) {
    final it = _rows[i];
    final label = _items[i].$1;
    final paths = _items[i].$2;
    // 文字色是 `rgba(23,24,26,.78) → 1`，图标的 currentColor 跟着走
    final ink = IlColor.ink.withValues(alpha: 0.78 + 0.22 * _rowInk[i].v.clamp(0.0, 1.0));
    return SizedBox(
      width: _rowW,
      height: _rowH,
      child: Transform.translate(
        offset: Offset(0, it.y.v),
        // key 挂在 Transform 的**内侧**：RenderTransform 自己的坐标系不含这道位移
        child: Opacity(
          key: ValueKey('row-$i'),
          opacity: it.o.v.clamp(0.0, 1.0),
          child: MouseRegion(
            onEnter: (_) => _hoverRow(i),
            onExit: (_) => _hoverRow(_hover == i ? -1 : _hover),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
              child: DecoratedBox(
                key: ValueKey('wash-$i'),
                // `:before{inset:0;z-index:-1}`：整行 192×34、圆角 17 的一层 8% 墨水，压在内容底下
                decoration: BoxDecoration(
                  color: IlColor.ink.withValues(alpha: _washA * _rowWash[i].v.clamp(0.0, 1.0)),
                  borderRadius: BorderRadius.circular(_rowR),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _rowPadH),
                  child: Row(
                    children: [
                      IlIcon(paths: paths, size: _icon, viewBox: 24, strokeWidth: 2, color: ink),
                      const SizedBox(width: _rowIconGap),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          style: TextStyle(
                            fontFamily: IlFont.family,
                            fontFamilyFallback: IlFont.fallback,
                            fontSize: _rowFont,
                            fontWeight: FontWeight.w400,
                            color: ink,
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
      ),
    );
  }
}

/// 一行进场：透明度 150ms、位移 240ms，两条各带同一个 delay
class _Item {
  _Item(this.i)
      : o = _Twn(0, dur: 150, curve: _cssEase),
        y = _Twn(6, dur: 240, curve: IlEase.smoothOut);

  final int i;
  final _Twn o;
  final _Twn y;

  /// 开：delay `30 + i*22`；关：delay 归零，四行一起退
  void aim({required bool open}) {
    final delay = open ? 30.0 + 22 * i : 0.0;
    o.aim(open ? 1 : 0, delay: delay);
    y.aim(open ? 0 : 6, delay: delay);
  }

  bool step(double dt) => o.step(dt) | y.step(dt);
}

/// 值到值的定时补间，带 CSS 那段 delay
class _Twn {
  _Twn(double from, {required double dur, required Curve curve})
      : _v = from,
        _from = from,
        _to = from,
        _dur = dur,
        _curve = curve;

  double _v;
  double _from;
  double _to;
  double _e = 0;
  double _delay = 0;
  double _dur;
  Curve _curve;
  bool _running = false;

  double get v => _v;

  /// 目标没变就别重起：每帧 aim 同一个值会把 `_e` 清零，钟永远停不下来
  void aim(double target, {double? delay, double? dur, Curve? curve}) {
    if (_to == target) return;
    _from = _v;
    _to = target;
    _e = 0;
    _delay = delay ?? 0;
    if (dur != null) _dur = dur;
    if (curve != null) _curve = curve;
    _running = true;
  }

  bool step(double dt) {
    if (!_running) return false;
    _e += dt;
    if (_e <= _delay) {
      _v = _from;
      return true;
    }
    final p = ((_e - _delay) / _dur).clamp(0.0, 1.0);
    _v = _from + (_to - _from) * _curve.transform(p);
    if (p >= 1.0) {
      _v = _to;
      _running = false;
    }
    return true;
  }
}
