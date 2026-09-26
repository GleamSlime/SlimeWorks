import 'dart:ui' show ImageFilter;

import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';

import '../kit.dart';

// ===== 参考稿量出来的那一套（字面 px，见 §12.3 的例外）=====

/// 按钮：`h-9` + demo 覆写的 `px-4`，圆角 8
const _btnH = 36.0;
const _btnPadX = 16.0;
const _btnRadius = 8.0;

/// 面板：`w-64` = 256，圆角 12，挂在按钮下缘再往下 8（`top: rect.bottom + 8`）
const _panelW = 256.0;
const _radius = 12.0;
const _gap = 8.0;

/// 面板要和按钮左缘对齐，整块往右挪到居中位：(372 − 256) / 2
const _btnX = 58.0;
const _btnY = 8.0;
const _origin = Offset(_btnX, _btnY);

/// 1px 描边占的那一格要自己钉进布局（§12.8：`DecoratedBox` 只画不让）
const _bw = 1.0;
const _contentW = _panelW - _bw * 2;

/// 标题行：`px-4 py-2` + 14/20
const _lineH = 20.0;
const _pad = 16.0;
const _titlePadY = 8.0;
const _titleH = _lineH + _titlePadY * 2;

/// 正文：`p-4` 里三列 `gap-2` 的 48 圆点，两行
const _sw = 48.0;
const _colGap = 8.0;
const _gridW = _contentW - _pad * 2;
const _track = (_gridW - _colGap * 2) / 3;
const _bodyH = _sw * 2 + _colGap + _pad * 2;

/// 页脚：`px-4 py-3` 里只有一颗 16 的返回箭头
const _arrow = 16.0;
const _footPadY = 12.0;
const _footH = _arrow + _footPadY * 2;

/// 面板高度是内容撑出来的（组件里没有 `h-[…]`）
const _panelH = _titleH + _bodyH + _footH + _bw * 2;
const _panelTop = _btnY + _btnH + _gap;

/// 那行字的两个落点：按钮里垂直居中，面板里是 `px-4 py-2` 的内容原点。
/// 两者 x 相同（面板左缘钉在按钮左缘上），所以这一飞是**纯竖直**的。
const _textX = _btnX + _bw + _btnPadX;
const _textFromY = _btnY + _bw + (_btnH - _bw * 2 - _lineH) / 2;
const _textToY = _panelTop + _bw + _titlePadY;

/// 面板 enter 档：`{opacity:0, scale:.9, y:10}`，`transformOrigin: top left`
const _rise = 10.0;
const _shrink = 0.9;
const _blur = 4.0;

/// 分段入场的两个延迟（`transition:{delay:.2/.3}`）
const _bodyDelay = 200.0;
const _footDelay = 300.0;

const _triggerText = 'Choose Color';

/// 六个色号是参考稿 demo 里写死的那一串
const _swatches = <Color>[
  Color(0xFFFF5733), //
  Color(0xFF33FF57), //
  Color(0xFF3357FF), //
  Color(0xFFFF33F1), //
  Color(0xFF33FFF1), //
  Color(0xFFF1FF33), //
];

/// demo 用设计令牌重刷了这颗触发器：`bg-secondary` / `text-secondary-foreground`
const _edge = Color(0x1A09090B);
const _btnBg = Color(0xFFF4F4F5);
const _ink = Color(0xFF18181B); // text-zinc-900

/// 按钮和面板标题都是 `text-sm font-semibold`，而且两档字色恰好同一号
/// （`--secondary-foreground` 与 `text-zinc-900` 都是 #18181b），
/// 所以飞过去的那一行字前后是同一个样式 —— 交接才看不出来
const _label = TextStyle(
  fontFamily: SvFont.family,
  fontFamilyFallback: SvFont.fallback,
  fontSize: 14,
  height: _lineH / 14,
  fontWeight: FontWeight.w600,
  color: _ink,
);

/// 参考稿的 `MotionConfig`：`{type:'spring', bounce:.1, duration:.4}` → ζ = 1−.1 = .9。
/// 假时钟（4ms 子步）扫过：行程 10px、0.02px 收口，S=260 那档落定 392ms。
/// 这一档几乎没有过冲（ζ=.9 的理论过冲只有行程的 0.15%，落在收口阈值以下），
/// 所以"弹"是听说的、不是看见的 —— 参考稿要的就是这个手感。
const _stiffness = 260.0;
const _damping = 29.02;

/// 色块自己那条 `transition:{duration:.2}`：type/bounce 仍跟着 `MotionConfig`
const _swStiffness = 1300.0;
const _swDamping = 64.9;

/// 2 号悬浮面板：面板不是从按钮里长出来的，它是**落**在按钮下面，
/// 只有那一行字从按钮飞进面板的标题行
///
/// 和 1 号的分别就在 `layoutId` 怎么挂：1 号按钮和面板共用一个 id，所以是一块
/// 表面在形变；这一格按钮挂 `…-trigger-`、面板挂 `…-`，两个不同的 id 之间不发生
/// 形变 —— 面板走 enter/exit 档（透明度 0→1、绕左上角缩 .9→1、上抬 10），共享的
/// 只有标题那一行字。于是这一格要同时演三件事：面板落位、背景整片糊掉、
/// 内容按 .1/.2/.3 的分段延迟依次进来。
class Case02FloatingPanel extends StatefulWidget {
  const Case02FloatingPanel({super.key});

  /// 测试要读的那几个落点/尺寸
  static const btnKey = ValueKey<String>('sv-c02-btn');
  static const panelKey = ValueKey<String>('sv-c02-panel');
  static const titleKey = ValueKey<String>('sv-c02-title');
  static const bodyKey = ValueKey<String>('sv-c02-body');
  static const footerKey = ValueKey<String>('sv-c02-footer');
  static const arrowKey = ValueKey<String>('sv-c02-arrow');
  static const blurKey = ValueKey<String>('sv-c02-blur');
  static ValueKey<String> swatchKey(int i) => ValueKey<String>('sv-c02-sw$i');

  static const panelW = _panelW;
  static const panelH = _panelH;
  static const btnH = _btnH;
  static const gap = _gap;
  static const origin = _origin;
  static const textX = _textX;
  static const textFromY = _textFromY;
  static const textToY = _textToY;
  static const track = _track;
  static const sw = _sw;
  static const bodyH = _bodyH;
  static const footH = _footH;
  static const titleH = _titleH;
  static const panelTop = _panelTop;

  @override
  State<Case02FloatingPanel> createState() => _Case02FloatingPanelState();
}

class _Case02FloatingPanelState extends State<Case02FloatingPanel>
    with SingleTickerProviderStateMixin {
  final FocusNode _focus = FocusNode(debugLabel: 'surface-lab.floating-panel');

  /// 面板落位：吃的是"还差多少像素没抬起来"，10 → 0
  final SvSpring _u = SvSpring.phys(stiffness: _stiffness, damping: _damping, from: _rise);

  /// 正文/页脚各自一条同参数弹簧，只是晚 200/300ms 起跳
  final SvSpring _b = SvSpring.phys(stiffness: _stiffness, damping: _damping, from: _rise);
  final SvSpring _f = SvSpring.phys(stiffness: _stiffness, damping: _damping, from: _rise);

  /// 色块的入场缩放：按"这一颗有多高"驱动（48 的 .8 倍起）
  final SvSpring _s =
      SvSpring.phys(stiffness: _swStiffness, damping: _swDamping, from: _sw * _shrink);

  /// 触发器的 hover/tap：同样按高度驱动，静止 36
  final SvSpring _t = SvSpring.phys(stiffness: _stiffness, damping: _damping, from: _btnH);

  /// 每颗色块自己的 hover/tap 弹簧：合用一条会在"从 A 移到 B"的那几帧里让 A 跟着
  /// B 一起变大，所以一颗一条
  late final List<SvSpring> _h = [
    for (var i = 0; i < _swatches.length; i++)
      SvSpring.phys(stiffness: _stiffness, damping: _damping, from: _sw),
  ];

  /// 全部弹簧共用一张表：任何一条在动就发帧，全停了自动收表
  late final List<SvSpring> _all = [_u, _b, _f, _s, _t, ..._h];

  /// 必须在 initState 里建（§12.8：`late final` 的表拖到 dispose 才碰就是崩）
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  bool _open = false;
  double _elapsed = 0;
  bool _bAimed = false;
  bool _fAimed = false;
  bool _hovBtn = false;
  bool _prsBtn = false;
  int? _hovSw;
  int? _prsSw;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    for (final s in _all) {
      s.addListener(_onChange);
    }
  }

  @override
  void dispose() {
    for (final s in _all) {
      s.removeListener(_onChange);
    }
    _ticker.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChange() {
    setState(() {});
    if (_all.every((SvSpring s) => s.atRest)) {
      _ticker.stop();
      return;
    }
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMilliseconds.toDouble();
    _last = elapsed;
    _elapsed += dt;
    // 分段入场是"晚一点起跳"，不是"慢一点走"：到点才 aim，走的还是同一条弹簧
    if (!_bAimed && _elapsed >= _bodyDelay) {
      _bAimed = true;
      _b.aim(0);
    }
    if (!_fAimed && _elapsed >= _footDelay) {
      _fAimed = true;
      _f.aim(0);
    }
    for (final s in _all) {
      s.step(dt);
    }
  }

  /// 面板这一落的进度：0 = 还贴在按钮上，1 = 落定
  double get _p => 1 - _u.value / _rise;

  /// 面板此刻的缩放倍率：`transformOrigin: top left`，屏幕落点 ÷ 它就是局部落点
  double get _sc => _shrink + (1 - _shrink) * _p;

  bool get _show => _open || !_u.atRest;

  void _openIt() {
    if (_open) return;
    setState(() => _open = true);
    _focus.requestFocus();
    // 参考稿每次打开都是重新挂载（`AnimatePresence`），所以延时的那几段要退回起点
    // 重来；此刻面板透明度还是 0，跳这一格看不见
    _elapsed = 0;
    _bAimed = _fAimed = false;
    _b.jumpTo(_rise);
    _f.jumpTo(_rise);
    _s.jumpTo(_sw * _shrink);
    _u.aim(0);
    _s.aim(_sw);
  }

  void _close() {
    if (!_open) return;
    setState(() => _open = false);
    // 收起只有面板自己在退（正文/页脚没有 exit 档），它们停在原位跟着淡掉
    _u.aim(_rise);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_open) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.escape) return KeyEventResult.ignored;
    _close();
    return KeyEventResult.handled;
  }

  /// 参考稿的 outside-click 挂在 document 的 mousedown 上：面板之外一律收
  void _onPointerDown(PointerDownEvent e) {
    if (!_open) return;
    final box = Rect.fromLTWH(_origin.dx, _panelTop, _panelW, _panelH);
    if (box.contains(e.localPosition)) return;
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return SvStage(
      center: false,
      height: 288,
      child: Listener(
        // 兜底命中要铺满：`Listener` 默认 `deferToChild`，空白处不落事件（§12.8）
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onPointerDown,
        child: Focus(
          focusNode: _focus,
          onKeyEvent: _onKey,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              _trigger(),
              // 背景糊掉：`fixed inset-0` + `backdropFilter: blur(0→4)`
              if (_show && _blur * p > 0.01)
                Positioned.fill(
                  key: Case02FloatingPanel.blurKey,
                  child: IgnorePointer(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: _blur * p, sigmaY: _blur * p),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              if (_show) _panel(p),
            ],
          ),
        ),
      ),
    );
  }

  Widget _trigger() {
    return Positioned(
      left: _origin.dx,
      top: _origin.dy,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          setState(() => _hovBtn = true);
          _t.aim(_btnH * 1.05);
        },
        onExit: (_) {
          setState(() => _hovBtn = false);
          if (!_prsBtn) _t.aim(_btnH);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _openIt,
          // `whileTap` 要的是 mousedown 那一刻（§12.8：`onTapDown` 拖到松手才响）
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) {
              setState(() => _prsBtn = true);
              _t.aim(_btnH * 0.95);
            },
            onPointerUp: (_) {
              setState(() => _prsBtn = false);
              _t.aim(_hovBtn ? _btnH * 1.05 : _btnH);
            },
            onPointerCancel: (_) {
              setState(() => _prsBtn = false);
              _t.aim(_hovBtn ? _btnH * 1.05 : _btnH);
            },
            child: Transform.scale(
              scale: _t.value / _btnH,
              child: DecoratedBox(
                key: Case02FloatingPanel.btnKey,
                decoration: BoxDecoration(
                  color: _btnBg,
                  borderRadius: BorderRadius.circular(_btnRadius),
                  border: Border.all(color: _edge, width: _bw),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(_bw),
                  child: SizedBox(
                    height: _btnH - _bw * 2,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: _btnPadX),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        // 字飞进面板之后这颗就空了：`layoutId` 的交接把原元素按
                        // opacity 0 藏起来，但格子还占着位，按钮不会缩成一小条
                        child: Opacity(opacity: _open ? 0 : 1, child: Text(_triggerText, style: _label)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _panel(double p) {
    return Positioned(
      left: _origin.dx,
      top: _panelTop,
      width: _panelW,
      height: _panelH,
      child: Transform.translate(
        // 顺序照参考稿：motion 写出来的是 `translateY(…) scale(…)`，先抬再缩
        offset: Offset(0, _u.value),
        child: Transform.scale(
          scale: _shrink + (1 - _shrink) * p,
          alignment: Alignment.topLeft,
          child: Opacity(
            opacity: p.clamp(0.0, 1.0),
            child: DecoratedBox(
              key: Case02FloatingPanel.panelKey,
              decoration: BoxDecoration(
                color: SvColor.pane,
                borderRadius: BorderRadius.circular(_radius),
                border: Border.all(color: _edge, width: _bw),
                boxShadow: const [
                  // `shadow-lg` 那两层
                  BoxShadow(
                    color: Color(0x1A000000),
                    blurRadius: 15,
                    offset: Offset(0, 10),
                    spreadRadius: -3,
                  ),
                  BoxShadow(
                    color: Color(0x1A000000),
                    blurRadius: 6,
                    offset: Offset(0, 4),
                    spreadRadius: -4,
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(_bw),
                child: ClipRRect(
                  // `overflow:hidden` 是真的：那行字飞到面板上方时就是被这一圈裁掉的
                  borderRadius: BorderRadius.circular(_radius - _bw),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [_title(), _body(), _footer()],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _title() {
    return SizedBox(
      height: _titleH,
      width: double.infinity,
      child: ColoredBox(
        color: SvColor.pane,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(_pad, _titlePadY, _pad, _titlePadY),
          child: Transform.translate(
            // 共享元素是在**屏幕上**从按钮那一条插值到面板那一条的，而它此刻住在
            // 一块还在缩放的表面里：不把这趟行程换算回面板的局部坐标，字就会被面板
            // 的 .9 倍一起缩走（起跳那一帧屏幕上是 29.6，而参考稿是 16）
            offset: Offset(
              (_textX - _origin.dx) / _sc - (_bw + _pad),
              (_textFromY + (_textToY - _textFromY) * _p - _panelTop - _u.value) / _sc -
                  (_bw + _titlePadY),
            ),
            child: Text(_triggerText, key: Case02FloatingPanel.titleKey, style: _label),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    return Transform.translate(
      offset: Offset(0, _b.value),
      child: Opacity(
        opacity: (1 - _b.value / _rise).clamp(0.0, 1.0),
        child: SizedBox(
          key: Case02FloatingPanel.bodyKey,
          height: _bodyH,
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.all(_pad),
            child: Column(
              children: [
                for (var r = 0; r < 2; r++) ...[
                  SizedBox(
                    height: _sw,
                    child: Row(
                      children: [
                        for (var c = 0; c < 3; c++) ...[
                          // `grid-cols-3 gap-2`：轨道等宽 68.67、轨道之间夹 8，
                          // gap 只出现在两列之间（首尾不留），所以是 c<2 补一格
                          SizedBox(
                            width: _track,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _swatch(r * 3 + c),
                            ),
                          ),
                          if (c < 2) const SizedBox(width: _colGap),
                        ],
                      ],
                    ),
                  ),
                  if (r == 0) const SizedBox(height: _colGap),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _footer() {
    return Transform.translate(
      offset: Offset(0, _f.value),
      child: Opacity(
        opacity: (1 - _f.value / _rise).clamp(0.0, 1.0),
        child: SizedBox(
          key: Case02FloatingPanel.footerKey,
          height: _footH,
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(_pad, _footPadY, _pad, _footPadY),
            child: Row(
              children: [
                // 收起用的是 ArrowLeft，不是 X（这颗按钮的语义是"回到上一层"）
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _close,
                    child: SizedBox(
                      key: Case02FloatingPanel.arrowKey,
                      width: _arrow,
                      height: _arrow,
                      child: SvIcon(
                        paths: const ['m12 19-7-7 7-7', 'M19 12H5'],
                        size: _arrow,
                        color: _ink,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _swatch(int i) {
    final hov = _h[i];
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _hovSw = i);
        hov.aim(_sw * 1.1);
      },
      onExit: (_) {
        setState(() => _hovSw = null);
        if (_prsSw != i) hov.aim(_sw);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 参考稿的 onClick 只往 console 打了一行，没有任何选中态
        onTap: () {},
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) {
            setState(() => _prsSw = i);
            hov.aim(_sw * 0.9);
          },
          onPointerUp: (_) {
            setState(() => _prsSw = null);
            hov.aim(_hovSw == i ? _sw * 1.1 : _sw);
          },
          onPointerCancel: (_) {
            setState(() => _prsSw = null);
            hov.aim(_hovSw == i ? _sw * 1.1 : _sw);
          },
          child: Opacity(
            // 色块自己是 `{opacity:0, scale:.8} → {1, 1}`：透明和缩放共用同一条进度
            opacity: ((_s.value / _sw - _shrink) / (1 - _shrink)).clamp(0.0, 1.0),
            child: Transform.scale(
              // 入场缩放和 hover 缩放是两条独立的 transform，相乘才是参考稿的叠加
              scale: (_s.value / _sw) * (hov.value / _sw),
              child: Container(
                key: Case02FloatingPanel.swatchKey(i),
                width: _sw,
                height: _sw,
                decoration: BoxDecoration(color: _swatches[i], shape: BoxShape.circle),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
