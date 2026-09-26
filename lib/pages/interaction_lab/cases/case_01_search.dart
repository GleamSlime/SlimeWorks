import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../kit.dart';

/// 1. Search — 胶囊搜索框：先压一下，再弹簧展开
///
/// 参考稿这里没有"时长"这个概念：宽度是一条隐式弹簧（k=0.16 / d=0.72，
/// 收敛阈值 0.02px），文案淡入、放大镜变色全挂在弹簧进度上——
/// `E = (当前宽 - 64) / 256`，`--say = clamp((E - .55) / .45, 0, 1)`，
/// 也就是走完 55% 才开始露字。按下先给 90ms 的 0.93 压缩，松手才展开。
/// 收起态还有一条磁吸：指针 110px 以内，整颗胶囊朝指针偏最多 4.5px。
class Case01Search extends StatefulWidget {
  const Case01Search({super.key});

  @override
  State<Case01Search> createState() => _Case01SearchState();
}

class _Case01SearchState extends State<Case01Search> {
  /// `Ex=64` 收起宽也是高、`Dx=28` 放大镜、`Ox=18` 内缩、`kx=32` 圆角
  static const _shut = 64.0;
  static const _openW = 320.0;
  static const _lens = 28.0;
  static const _inset = 18.0;
  static const _corner = 32.0;

  /// `--frame = max(64,width)+26`，`--frameh` 固定 104
  static const _frameW = 346.0;
  static const _frameH = 104.0;

  /// `.sek-field`：left = inset + lens + 11，right = 14
  static const _fieldLeft = _inset + _lens + 11;
  static const _fieldRight = 14.0;

  /// `--give=50` → 磁吸最大 4.5px，超出 110px 归零
  static const _leanMax = 4.5;
  static const _leanRadius = 110.0;

  /// `spring=50` → k = .08 + .5*.16，d = .62 + .5*.2
  final IlSpring _w = IlSpring(k: 0.16, d: 0.72, from: _shut);

  final FocusNode _focus = FocusNode(debugLabel: 'interaction-lab.search');

  bool _open = false;
  bool _press = false;
  bool _hoverSkin = false;
  bool _busy = false;
  bool _focusVisible = false;
  String _text = '';
  Offset _lean = Offset.zero;

  Timer? _pressTimer;
  Timer? _busyTimer;

  @override
  void dispose() {
    _pressTimer?.cancel();
    _busyTimer?.cancel();
    _w.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _tap() {
    if (_open) return;
    // data-press 只有 90ms：压一下再松手，松手那刻才真正展开
    setState(() => _press = true);
    _pressTimer?.cancel();
    _pressTimer = Timer(const Duration(milliseconds: 90), () {
      if (!mounted) return;
      setState(() {
        _press = false;
        _open = true;
        _lean = Offset.zero;
      });
      _w.aim(_openW);
      _focus.requestFocus();
    });
  }

  void _close() {
    if (!_open) return;
    setState(() => _open = false);
    _w.aim(_shut);
  }

  /// 每次按键让放大镜进入 busy 340ms
  void _keystroke() {
    setState(() => _busy = true);
    _busyTimer?.cancel();
    _busyTimer = Timer(const Duration(milliseconds: 340), () {
      if (mounted) setState(() => _busy = false);
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    // ring 只在 :focus-visible 那档出：键盘 Tab 进来的算，鼠标点进来的不算
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      if (!_focusVisible) setState(() => _focusVisible = true);
      return KeyEventResult.ignored;
    }
    if (!_open) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      // Esc 连文本一起清掉再收
      setState(() => _text = '');
      _close();
      _focus.unfocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace) {
      if (_text.isNotEmpty) {
        setState(() => _text = _text.substring(0, _text.length - 1));
        _keystroke();
      }
      return KeyEventResult.handled;
    }
    final label = key.keyLabel;
    if (label.length == 1 && label.codeUnitAt(0) >= 0x20) {
      // 长度封顶在展开宽里：参考稿是真 input 会自己截，这里手动收着
      if (_text.length < 22) {
        setState(() => _text += label);
        _keystroke();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// 磁吸：以 `.sek` 外框中心为参考系，110px 内按 (1-d/110)^1.4 拉过去
  void _onPointer(PointerEvent e) {
    if (_open) return;
    final dx = e.localPosition.dx - IlSize.stageW / 2;
    final dy = e.localPosition.dy - IlSize.stageH / 2;
    final d = math.sqrt(dx * dx + dy * dy);
    final Offset next;
    if (d > _leanRadius) {
      next = Offset.zero;
    } else {
      final pull = math.pow(1 - d / _leanRadius, 1.4) * _leanMax;
      next = d == 0 ? Offset.zero : Offset(dx / d, dy / d) * pull;
    }
    if (next != _lean) setState(() => _lean = next);
  }

  @override
  Widget build(BuildContext context) {
    return IlStage(
      center: false,
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _onKey,
        child: Stack(
          children: [
            Center(
              // 弹簧得有人发帧：只读 `_w.value` 不挂监听，宽度就永远停在挂载
              // 那一帧——出图看着"点了没反应"其实是没有钟在推
              child: IlSpringDrive(
                spring: _w,
                builder: (context) {
                  final e = ((_w.value - _shut) / (_openW - _shut)).clamp(0.0, 1.0);
                  final say = ((e - 0.55) / 0.45).clamp(0.0, 1.0);
                  return _frame(say);
                },
              ),
            ),
            // 磁吸的监听区是整块舞台（110px 半径比外框高还大），
            // translucent 才不挡住下面那颗胶囊的点击
            Positioned.fill(
              child: MouseRegion(
                hitTestBehavior: HitTestBehavior.translucent,
                cursor: _open ? SystemMouseCursors.text : SystemMouseCursors.click,
                onHover: _onPointer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _frame(double say) {
    final sk = _press ? 0.93 : (_hoverSkin && !_open ? 1.045 : 1.0);
    // CSS 的 translate(lx,ly) scale(s) 以中心为原点，Flutter 的 transform
    // 以左上角为原点：p' = s·(p−O) + O + l，直接写成仿射矩阵
    final m = Matrix4.identity()
      ..setEntry(0, 0, sk)
      ..setEntry(1, 1, sk)
      ..setEntry(0, 3, _lean.dx + _frameW / 2 * (1 - sk))
      ..setEntry(1, 3, _lean.dy + _frameH / 2 * (1 - sk));

    return AnimatedContainer(
      duration: _press ? const Duration(milliseconds: 90) : const Duration(milliseconds: 260),
      // 压缩走 (.4,0,.6,1)，其余形变走基础那条 (.22,.9,.28,1)
      curve: _press ? const Cubic(0.4, 0, 0.6, 1) : IlEase.morph,
      transform: m,
      transformAlignment: Alignment.topLeft,
      width: _frameW,
      height: _frameH,
      // 外框只有 346 宽，弹簧峰值却到得了 375：这里必须用 OverflowBox 让
      // 胶囊探出去。用 Center 的话父约束会把宽度悄悄夹回 346，过冲看着
      // 像"到 346 就停住"，弹簧的量级就验不出来了
      child: OverflowBox(
        alignment: Alignment.center,
        minWidth: 0,
        maxWidth: double.infinity,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _tap,
          child: MouseRegion(
            onEnter: (_) => setState(() => _hoverSkin = true),
            onExit: (_) => setState(() => _hoverSkin = false),
            child: Container(
              width: _w.value,
              height: _shut,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: IlColor.pane,
                borderRadius: BorderRadius.circular(_corner),
                // `:focus-visible` 的双层 ring：2px 底色 + 2px 四成墨
                boxShadow: _focusVisible && _open
                    ? const [
                        BoxShadow(color: IlColor.pane, blurRadius: 0, spreadRadius: 2),
                        BoxShadow(color: Color(0x6617181A), blurRadius: 0, spreadRadius: 4),
                      ]
                    : null,
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: _inset,
                    top: (_shut - _lens) / 2,
                    child: _Lens(hover: _hoverSkin && !_open, open: _open, busy: _busy),
                  ),
                  Positioned(
                    left: _fieldLeft,
                    right: _fieldRight,
                    top: 0,
                    bottom: 0,
                    child: Opacity(
                      opacity: say,
                      child: Transform.translate(
                        offset: Offset((1 - say) * -6, 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _Field(text: _text, caret: _open && _focus.hasFocus),
                        ),
                      ),
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
}

/// 放大镜：常态 ink-3，hover 转 ink，展开转 ink-4，打字时 ink-2 且描边加到 1.8
///
/// 四条都是 200ms `ease`，所以颜色和描边宽各挂一条自己的补间，
/// 换目标时从当前显示值接着走。
class _Lens extends StatefulWidget {
  const _Lens({required this.hover, required this.open, required this.busy});

  final bool hover;
  final bool open;
  final bool busy;

  @override
  State<_Lens> createState() => _LensState();
}

class _LensState extends State<_Lens> with SingleTickerProviderStateMixin {
  static const _base = Color(0xFF5C5B56); // --ink-3
  static const _hoverC = Color(0xFF17181A); // --ink
  static const _openC = Color(0xFF6F6E68); // --ink-4
  static const _busyC = Color(0xFF3C3B37); // --ink-2

  late Color _shown = _target;
  late double _sw = _targetWidth;
  Color _from = _base;
  double _fromW = 1.5;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: 1.0,
  );

  Color get _target =>
      widget.busy ? _busyC : (widget.open ? _openC : (widget.hover ? _hoverC : _base));
  double get _targetWidth => widget.busy ? 1.8 : 1.5;

  @override
  void initState() {
    super.initState();
    _from = _shown = _target;
    _fromW = _sw = _targetWidth;
    _c.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(_Lens old) {
    super.didUpdateWidget(old);
    if (old.busy == widget.busy && old.open == widget.open && old.hover == widget.hover) return;
    _from = _shown;
    _fromW = _sw;
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Curves.ease.transform(_c.value);
    _shown = Color.lerp(_from, _target, t)!;
    _sw = _fromW + (_targetWidth - _fromW) * t;
    return IlIcon(
      // viewBox 0 0 18 18：一个圆加一撇柄
      paths: const ['M13 7.6A5.4 5.4 0 1 1 2.2 7.6A5.4 5.4 0 0 1 13 7.6Z', 'M11.6 11.6L15.4 15.4'],
      size: 28,
      viewBox: 18,
      strokeWidth: _sw,
      color: _shown,
    );
  }
}

/// 文案 + 光标：placeholder 用 ink-5，打字用 ink，18px 字距 -.005em
class _Field extends StatefulWidget {
  const _Field({required this.text, required this.caret});

  final String text;
  final bool caret;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );

  @override
  void initState() {
    // 钟在 initState 里建、不在 late 的懒初始化里建：光标只在展开态才画，
    // 收起态从没读过 `_blink`，dispose 里那句 `_blink.dispose()` 就会在
    // 卸载途中把控制器补建出来——createTicker 找祖先直接炸
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_Field old) {
    super.didUpdateWidget(old);
    if (old.caret != widget.caret) _sync();
  }

  /// 光标不在的时候把钟停回 0，省得留一条常驻的 60Hz 心跳
  void _sync() {
    if (widget.caret) {
      _blink.repeat();
    } else {
      _blink
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontFamily: IlFont.family,
      fontFamilyFallback: IlFont.fallback,
      fontSize: 18,
      fontWeight: FontWeight.w400,
      height: 1.5,
      letterSpacing: -0.09,
      color: IlColor.ink,
    );
    // 光标始终停在"插入点"上：空输入时在最左、placeholder 排它后面；打了字
    // 就挪到字尾。光标画在 placeholder 尾巴上会读成"已经打了字"
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.text.isNotEmpty) Text(widget.text, style: style),
        if (widget.caret)
          AnimatedBuilder(
            animation: _blink,
            builder: (context, _) => Opacity(
              // 1 秒一周期，后半拍灭
              opacity: _blink.value < 0.5 ? 1 : 0,
              child: Container(width: 1, height: 22, color: IlColor.ink),
            ),
          ),
        if (widget.text.isEmpty)
          Text('Search', style: style.copyWith(color: const Color(0xFF85847E))),
      ],
    );
  }
}
