import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:path_drawing/path_drawing.dart';

import '../kit.dart';

/// 10. Selection list — 多人名单：勾是**描边画进去**的，CTA 是一条被裁住的抽屉
///
/// 组件 268 宽、盒子 224 高（`10+46+4+46+4+46+4+10+44+10`），但没选中时
/// `clip-path: inset(0 0 54 round 20)` 把底部 54px 连 CTA 一起裁掉，**只留 170 可见**。
/// 裁切不改布局：名单占位一直是 224，这也是它能"从盒子里长出来"的前提。
///
/// 抽屉只有一根弹簧：`{stiffness:230, damping:26, mass:1}` 驱动 `p: 54 → 0`，
/// clip 的下边距、CTA 的透明度/位移/缩放**全部从 p 派生**（ζ=0.857，54px 行程
/// 只过冲 0.3px，肉眼就是"到位时轻轻顶一下"）。三条映射都夹在 p∈[0,54]：
/// - opacity 走分段 `[54,27,0] → [0,.15,1]`：前半程几乎不出现，后半程急升；
/// - y `54→0` 映射 `-14→0`；scale 映射 `.96→1`。
///
/// 勾选那一下是这一格的骨头：
/// - 圆环 `r=10.9` 淡出 **100ms**（`[data-on=true]` 把 160ms 覆盖成 100ms）；
/// - 勾是 `stroke-dasharray:14 / dashoffset:14→0`，**260ms `cubic-bezier(.32,.9,.3,1)`
///   再加 60ms delay**。注意路径实测长只有 10.75，比 dash 周期短：**画满只发生在
///   行程的 76.8%**（`14t` 撞上路长之后那一段行程什么都不再变）；
/// - 反方向不一样：`delay:60ms` 和 `duration:.1s` 都挂在 `[data-on=true]` 那条规则上，
///   取消勾选时规则失效，所以**没有延迟、环要 160ms 才淡回来**；
/// - 底下那颗墨点是 goo 层画出来的：`fill` 在选中瞬间从 transparent 翻成 ink，圆点
///   **不跟着 scale 弹簧走**（portal 进滤镜的是 item 的外框 19×19）。阈值线
///   `16a-6.17` 落在 α≈0.386，直边上该外扩 1.4px/边，但 R=9.5 只有 2.4σ，
///   曲率把边缘的 alpha 峰压回 0.5 以下——golden 里量回来是**正好 19**，不放大。
///
/// 参考稿的 Corner（0–40 step2）和 Rows（2/3）是演示站的旋钮，这一格钉默认档
/// 20/3；`Corner` 只驱动盒子/药丸/CTA 三处圆角，**行的 13px 圆角是写死的**。
/// 头像原稿是 4 张内联 JPEG 照片，这里和 7 号同一口径换成同尺寸的首字母圆；
/// `:focus-visible` 那圈内描边没有对应的真焦点控件，一并省略。
class Case10Roster extends StatefulWidget {
  const Case10Roster({super.key});

  @override
  State<Case10Roster> createState() => _Case10RosterState();
}

// ---------------------------------------------------------------- 时间线与弹簧

const _checkMs = 260.0;
const _checkDelayMs = 60.0;
const _ringMs = 160.0; // 淡回：默认时长
const _ringOnMs = 100.0; // 淡出：`[data-on=true]` 覆盖的时长
const _tickColorMs = 180.0;
const _pillInMs = 140.0;
const _pillOutMs = 220.0;
const _ctaSkinMs = 200.0; // `transition:background .2s,color .2s`
const _labelMs = 140.0; // `AnimatePresence mode=wait`
const _checkEase = Cubic(0.32, 0.9, 0.3, 1);

/// CSS 不写缓动名时的那条
const _cssEase = Cubic(0.25, 0.1, 0.25, 1);

/// `stroke-dasharray` 的周期，和路径实长之比决定"什么时候就已经画完了"
const _dash = 14.0;

class _Case10RosterState extends State<Case10Roster> with SingleTickerProviderStateMixin {
  // ---------------------------------------------------------------- 量出来的尺寸

  static const _w = 268.0; // `.rst`
  static const _pad = 10.0; // `.rst-box` padding
  static const _rowH = 46.0; // `Eh`
  static const _rowGap = 4.0; // `Dh`
  static const _ctaH = 44.0;
  static const _ctaMt = 10.0;
  static const _reserve = 54.0; // `kh`：CTA 连同上边距被裁掉的那 54px
  static const _corner = 20.0; // Corner 默认档
  static const _pillR = 10.0; // `min(23, corner-10)`
  static const _ctaR = 10.0; // `corner-10`
  static const _rowPx = 9.0; // row `padding:0 9px`
  static const _colGap = 11.0; // row `gap:11px`
  static const _av = 32.0;
  static const _tickSize = 19.0;
  static const _rows = 3;

  /// 4 个子元素（3 行 + CTA）之间共 3 条 4px gap，CTA 另带 10 的上边距
  static const _boxH = _pad * 2 + _rowH * _rows + _rowGap * _rows + _ctaMt + _ctaH; // 224

  /// goo 的滤镜区原稿给的是 `ceil(3σ + 24)` = 36；这里留 24 就够，但**必须留**：
  /// 模糊要往外吃 3σ，贴着圆盘裁的话拉丝的那一段就没有地方长（单看这一格只是不放大，
  /// 两枚挨在一起时才看得出差别）
  static const _gooPad = 24.0;

  // ---------------------------------------------------------------- 颜色与字

  static const _slab = IlColor.pane; // `--fill-slab`
  static const _on = IlColor.ink; // `--fill-on` / `--ink`
  static const _onInk = IlColor.pane; // `--on-ink`

  /// `color-mix(in srgb, --fill-on N%, --fill-slab)`：CSS 就是 8bit 线性插值，
  /// `Color.lerp` 是同一件事，比抄下来的近似 hex 更贴
  static final _tickOff = Color.lerp(_slab, _on, 0.26)!;
  static final _tickHover = Color.lerp(_slab, _on, 0.48)!;
  static final _pillWash = Color.lerp(_slab, _on, 0.06)!;
  static final _handleInk = ilWash(0.45); // `rgba(23,24,26,.45)`
  static final _ctaOffBg = ilWash(0.07); // `rgba(23,24,26,.07)`

  static const _nameStyle = TextStyle(
    fontFamily: IlFont.family,
    fontFamilyFallback: IlFont.fallback,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.5, // html 那条 `line-height:1.5`，被 `font:inherit` 带进来了
    color: _on,
  );

  static final _handleStyle = TextStyle(
    fontFamily: IlFont.family,
    fontFamilyFallback: IlFont.fallback,
    fontSize: 11.5,
    fontWeight: FontWeight.w400,
    height: 1.5,
    letterSpacing: 0, // `.rst-at{letter-spacing:0}`：把页面级的负字距顶掉
    color: _handleInk,
  );

  static const _ctaStyle = TextStyle(
    fontFamily: IlFont.family,
    fontFamilyFallback: IlFont.fallback,
    fontSize: 13.5,
    fontWeight: FontWeight.w400,
    height: 1.5,
    letterSpacing: -0.005 * 13.5,
  );

  static const _avStyle = TextStyle(
    fontFamily: IlFont.family,
    fontFamilyFallback: IlFont.fallback,
    fontSize: _av * 0.36,
    fontWeight: FontWeight.w500,
    height: 1,
  );

  // ---------------------------------------------------------------- 状态

  /// 选中集合：渲染顺序**永远按名单顺序**，所以先点第 3 行再点第 1 行，行序不变
  final Set<String> _sel = {};
  bool _sent = false;

  final List<_RowMot> _mot = [for (var i = 0; i < _rows; i++) _RowMot()];

  /// 抽屉唯一的那根弹簧；`useSpring(f?0:54)` 初值就是目标 → 首帧不弹
  late final IlSpring _p = IlSpring.phys(stiffness: 230, damping: 26, from: _reserve);

  /// `whileTap` 那一下：原稿没给参数（走库默认），取一条 ~120ms 量级的近似
  late final IlSpring _pressSp = IlSpring.phys(
    stiffness: 500,
    damping: 30,
    from: 1,
    rest: 0.0002,
  );

  final _Twn _skin = _Twn(0); // CTA 的 disabled ↔ enabled 皮

  /// `initial={false}` + `animate:{opacity:+!!f}` → 首帧就钉在 0，不入场动画
  final _Twn _labelA = _Twn(0);

  /// 当前挂在 CTA 上的文案键，以及正在等的那次切换（`mode:'wait'` 先淡出再淡入）
  String _labelKey = '0';
  String? _labelNext;

  Ticker? _ticker;
  Duration _last = Duration.zero;

  @override
  void dispose() {
    _ticker?.stop();
    super.dispose();
  }

  // ---------------------------------------------------------------- 交互

  bool get _open => _sel.isNotEmpty || _sent;

  /// 行的 toggle：每次都要先把"已发送"清掉（原稿 `a(!1)` 是无条件执行的）
  void _toggle(String id) {
    _sent = false;
    _setRow(id, !_sel.contains(id));
    _syncDrawer();
    _kick();
  }

  /// CTA：发送后清空勾选，但 `f = 有选中 || 已发送` 仍为真 → **抽屉不收回**
  void _send() {
    if (!_open) return;
    _sent = true;
    for (final p in _people.take(_rows)) {
      _setRow(p.id, false);
    }
    _syncDrawer();
    _kick();
  }

  void _setRow(String id, bool on) {
    if (on) {
      _sel.add(id);
    } else {
      _sel.remove(id);
    }
    final i = _people.indexWhere((e) => e.id == id);
    if (i >= 0) _mot[i].toggle(on);
  }

  void _syncDrawer() {
    final open = _open;
    _p.aim(open ? 0 : _reserve);
    _skin.aim(open ? 1 : 0, dur: _ctaSkinMs);
  }

  void _onPressChanged(bool down) {
    _pressSp.aim(down ? 0.975 : 1);
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
    var live = !_p.atRest || !_pressSp.atRest;

    _p.step(dt);
    _pressSp.step(dt);
    live |= _skin.step(dt);
    live |= _labelA.step(dt);
    for (final m in _mot) {
      live |= m.step(dt);
    }
    _syncLabel();

    setState(() {});
    if (!live) _ticker!.stop();
  }

  /// `key = sent ? 'sent' : count`：键变了先淡出，淡出走完才换文案、才淡入
  void _syncLabel() {
    final want = _sent ? 'sent' : '${_sel.length}';
    if (want == _labelKey) {
      // 待换的文案又变回当前这个（1→2→1 敲得比 140ms 还快）：撤掉排队，
      // 并把已经在淡出的这一路拉回来，不然文案会停在透明上再也回不来
      if (_labelNext != null) {
        _labelNext = null;
        _labelA.aim(_open ? 1 : 0, dur: _labelMs);
      }
    } else {
      _labelNext ??= want;
      _labelA.aim(0, dur: _labelMs);
    }
    if (_labelNext != null && _labelA.v <= 0) {
      _labelKey = _labelNext!;
      _labelNext = null;
      _labelA.aim(_open ? 1 : 0, dur: _labelMs);
    }
  }

  // ---------------------------------------------------------------- 派生量

  static double _mix(double a, double b, double t) => a + (b - a) * t;

  /// `useTransform(p, [54,27,0], [0,.15,1])`，输入夹在 [0,54]
  static double _ctaAlpha(double p) {
    if (p >= _reserve) return 0;
    final half = _reserve / 2;
    if (p > half) return (_reserve - p) / half * 0.15;
    return 0.15 + (half - p) / half * 0.85;
  }

  /// 勾的可见比例：`14t` 撞上实长就停（画满只发生在行程 76.8% 处）
  static double _checkFrac(double t) => math.min(1, _dash * t / _checkLen);

  // ---------------------------------------------------------------- 树

  @override
  Widget build(BuildContext context) {
    final q = _p.value.clamp(0.0, _reserve);
    final u = 1 - q / _reserve; // 0 = 收起，1 = 全开
    final label = switch (_labelKey) {
      'sent' => 'Requests sent',
      '1' => 'Send request',
      _ => 'Send $_labelKey requests',
    };
    final skin = _skin.v.clamp(0.0, 1.0);
    final bg = Color.lerp(_ctaOffBg, _on, skin)!;
    final fg = Color.lerp(IlColor.ink5, _onInk, skin)!;
    final s = _mix(0.96, 1, u) * _pressSp.value;

    return IlStage(
      child: SizedBox(
        width: _w,
        height: _boxH,
        child: ClipPath(
          key: const ValueKey('clip'),
          clipper: _InsetBottom(_p.value, _corner),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: _slab,
              borderRadius: BorderRadius.all(Radius.circular(_corner)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(_pad),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < _rows; i++) ...[
                    _row(i),
                    const SizedBox(height: _rowGap),
                  ],
                  const SizedBox(height: _ctaMt),
                  Opacity(
                    key: const ValueKey('cta-a'),
                    opacity: _ctaAlpha(q),
                    child: Transform(
                      key: const ValueKey('cta-xf'),
                      alignment: Alignment.center,
                      // `translateY(y) scale(s)`：先缩再平移，和 CSS 从右往左读一样
                      transform: Matrix4.identity()
                        ..setEntry(1, 3, -14 * (1 - u))
                        ..setEntry(0, 0, s)
                        ..setEntry(1, 1, s),
                      child: _cta(bg, fg, label),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// `.rst-row`：药丸在内容**底下**（CSS 是 `:before` + `z-index:-1`）
  Widget _row(int i) {
    final p = _people[i];
    final m = _mot[i];
    final on = _sel.contains(p.id);
    return MouseRegion(
      key: ValueKey('row-$i'),
      cursor: SystemMouseCursors.click,
      hitTestBehavior: HitTestBehavior.opaque,
      onEnter: (_) {
        m.hover.aim(1, dur: _pillInMs);
        m.tint.aim(1, dur: _tickColorMs);
        _kick();
      },
      onExit: (_) {
        m.hover.aim(0, dur: _pillOutMs);
        m.tint.aim(0, dur: _tickColorMs);
        _kick();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _toggle(p.id),
        child: SizedBox(
          height: _rowH,
          child: Stack(
            children: [
              Positioned.fill(
                child: Opacity(
                  key: ValueKey('pill-$i'),
                  opacity: m.hover.v.clamp(0.0, 1.0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _pillWash,
                      borderRadius: BorderRadius.all(Radius.circular(_pillR)),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: _rowPx),
                child: Row(
                  children: [
                    _avatar(p),
                    const SizedBox(width: _colGap),
                    Expanded(
                      child: Column(
                        key: ValueKey('who-$i'),
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _nameStyle,
                          ),
                          const SizedBox(height: 1),
                          Text(p.handle, maxLines: 1, style: _handleStyle),
                        ],
                      ),
                    ),
                    const SizedBox(width: _colGap),
                    _tickBox(i, m, on),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatar(_Person p) => DecoratedBox(
    key: ValueKey('av-${p.id}'),
    decoration: BoxDecoration(color: p.tint, shape: BoxShape.circle),
    child: SizedBox(
      width: _av,
      height: _av,
      child: Center(child: Text(p.initials, style: _avStyle.copyWith(color: p.fg))),
    ),
  );

  /// `.rst-tickgoo`：滤镜里只有那颗墨点，勾和环是压在它上面的原样描边
  Widget _tickBox(int i, _RowMot m, bool on) => SizedBox(
    key: ValueKey('tick-$i'),
    width: _tickSize,
    height: _tickSize,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: -_gooPad,
          top: -_gooPad,
          width: _tickSize + _gooPad * 2,
          height: _tickSize + _gooPad * 2,
          child: IlGoo(
            sigma: 4,
            contrast: 16,
            child: on
                ? Center(
                    child: Container(
                      key: ValueKey('dot-$i'),
                      width: _tickSize,
                      height: _tickSize,
                      decoration: const BoxDecoration(color: _on, shape: BoxShape.circle),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
        Transform(
          key: ValueKey('tick-xf-$i'),
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(0, 0, m.scale.value)
            ..setEntry(1, 1, m.scale.value),
          child: CustomPaint(
            size: const Size.square(_tickSize),
            painter: _TickPainter(
              color: Color.lerp(
                Color.lerp(_tickOff, _tickHover, m.tint.v.clamp(0.0, 1.0))!,
                _onInk,
                m.sel.v.clamp(0.0, 1.0),
              )!,
              ringA: m.ring.v.clamp(0.0, 1.0),
              checkFrac: _checkFrac(m.check.v.clamp(0.0, 1.0)),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _cta(Color bg, Color fg, String label) => Listener(
    key: const ValueKey('cta'),
    behavior: HitTestBehavior.opaque,
    onPointerDown: (_) {
      if (_open) _onPressChanged(true);
    },
    onPointerUp: (_) => _onPressChanged(false),
    onPointerCancel: (_) => _onPressChanged(false),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _send,
      child: MouseRegion(
        cursor: _open ? SystemMouseCursors.click : MouseCursor.defer,
        child: Container(
          height: _ctaH,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.all(Radius.circular(_ctaR)),
          ),
          child: Opacity(
            key: const ValueKey('label'),
            opacity: _labelA.v.clamp(0.0, 1.0),
            child: Text(label, style: _ctaStyle.copyWith(color: fg)),
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------- 每行的四条时间线

class _RowMot {
  /// `:before` 药丸：进 140ms、出 220ms（hover 规则只覆盖时长，不覆盖曲线）
  final _Twn hover = _Twn(0);

  /// tick 颜色 26% ↔ 48% 那一档，180ms
  final _Twn tint = _Twn(0);

  /// 选中：整枚刷白，180ms
  final _Twn sel = _Twn(0);

  /// 圆环透明度：淡出 100ms / 淡回 160ms
  final _Twn ring = _Twn(1);

  /// 勾的画入行程（真实比例还要过 `_checkFrac` 那道钳位）
  final _Twn check = _Twn(0);

  /// `animate:{scale:1.1}`，`Af = {220, 14, .5}`
  final IlSpring scale = IlSpring.phys(
    stiffness: 220,
    damping: 14,
    mass: 0.5,
    from: 1,
    rest: 0.0005,
  );

  void toggle(bool on) {
    sel.aim(on ? 1 : 0, dur: _tickColorMs);
    // 取消勾选时 `[data-on=true]` 那条规则失效，所以 delay 和 100ms 都回到默认值
    ring.aim(on ? 0 : 1, dur: on ? _ringOnMs : _ringMs);
    check.aim(
      on ? 1 : 0,
      dur: _checkMs,
      curve: _checkEase,
      delay: on ? _checkDelayMs : 0,
    );
    scale.aim(on ? 1.1 : 1);
  }

  bool step(double dt) {
    var live = !scale.atRest;
    scale.step(dt);
    live |= hover.step(dt);
    live |= tint.step(dt);
    live |= sel.step(dt);
    live |= ring.step(dt);
    live |= check.step(dt);
    return live;
  }
}

// ---------------------------------------------------------------- 勾的画法

/// lucide 那两个图元：viewBox 24、stroke-width 1.75、round cap/join、fill:none
const _checkD = 'M8.26 12.31l2.57 2.57 4.91-5.15';

final Path _checkPath = parseSvgPathData(_checkD);

/// 路径实长：`stroke-dasharray:14` 比它长，所以勾会在行程后段"空转"
final double _checkLen = () {
  var sum = 0.0;
  for (final m in _checkPath.computeMetrics()) {
    sum += m.length;
  }
  return sum;
}();

class _TickPainter extends CustomPainter {
  _TickPainter({required this.color, required this.ringA, required this.checkFrac});

  final Color color;

  /// 环的透明度（元素级 opacity，等价于整条描边乘 alpha）
  final double ringA;

  /// 已画长度 / 路径实长
  final double checkFrac;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    if (ringA > 0.001) {
      canvas.drawCircle(
        const Offset(12, 12),
        10.9,
        Paint()
          ..color = color.withValues(alpha: color.a * ringA)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.75,
      );
    }
    if (checkFrac > 0.001) {
      // 从尾巴上剪掉 `1-frac`，留下的就是开头那一段
      final body = trimPath(_checkPath, 1 - checkFrac, origin: PathTrimOrigin.end);
      canvas.drawPath(
        body,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.75
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(_TickPainter old) =>
      old.color != color || old.ringA != ringA || old.checkFrac != checkFrac;
}

// ---------------------------------------------------------------- 抽屉的裁切

/// `clip-path: inset(0 0 p 0 round r)` —— 下边往里收 p，四角跟着圆起来
class _InsetBottom extends CustomClipper<Path> {
  _InsetBottom(this.p, this.r);

  final double p;
  final double r;

  @override
  Path getClip(Size size) => Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(0, 0, size.width, size.height - p),
        Radius.circular(r),
      ),
    );

  @override
  bool shouldReclip(_InsetBottom oldClipper) => oldClipper.p != p || oldClipper.r != r;
}

// ---------------------------------------------------------------- 名单

@immutable
class _Person {
  const _Person(this.id, this.name, this.handle, this.tint, this.fg);

  final String id;
  final String name;
  final String handle;
  final Color tint;
  final Color fg;

  String get initials {
    final w = name.split(' ');
    return '${w.first[0]}${w.length > 1 ? w.last[0] : ''}';
  }
}

/// 顺序就是渲染顺序：Rows 旋钮最大 3，第 4 条进不了这一格
const _people = <_Person>[
  _Person('mara', 'Nadia Okonkwo', '@nadia', Color(0xFFE4DFD7), Color(0xFF6C6459)),
  _Person('ines', 'Tomas Cardoso', '@tomas', Color(0xFFD9E2E9), Color(0xFF5A6B79)),
  _Person('kai', 'Kai Brenner', '@kai', Color(0xFFDFE5DA), Color(0xFF61705A)),
  _Person('sofia', 'Lukas Lindqvist', '@lukas', Color(0xFFEBE0E1), Color(0xFF7B6266)),
];

// ---------------------------------------------------------------- 补间

/// 值到值的定时补间，对应 CSS 那条 `transition`
///
/// 比常规补间多带一个 `delay`：勾的 60ms 延迟只在选中那一支生效，
/// 所以时长和延迟都得跟着方向走，不能做成常量。
class _Twn {
  _Twn(this._v);

  double _v;
  double _from = 0;
  double _to = 0;
  double _e = 0;
  double _dur = 0;
  Curve _curve = _cssEase;
  bool _running = false;

  double get v => _v;

  /// 目标没变就别重起：反复 aim 同一个值会把 `_e` 清零，钟停不下来
  void aim(double target, {double dur = 0, Curve curve = _cssEase, double delay = 0}) {
    if (_to == target) return;
    _from = _v;
    _to = target;
    _dur = dur;
    _curve = curve;
    _e = -delay;
    _running = true;
  }

  bool step(double dt) {
    if (!_running) return false;
    _e += dt;
    if (_e < 0) return true;
    final p = _dur <= 0 ? 1.0 : (_e / _dur).clamp(0.0, 1.0);
    _v = _from + (_to - _from) * _curve.transform(p);
    if (p >= 1.0) {
      _v = _to;
      _running = false;
    }
    return true;
  }
}
