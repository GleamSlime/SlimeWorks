import 'dart:typed_data' show Float64List;
import 'dart:ui' show ImageFilter;

import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../kit.dart';

/// 11 号 Command bar —— 一条输入框 + 一颗"从右端长出来"的发送钮
///
/// 白色形状**一个都不是画出来的**：`.cmd` 自己 `background:0 0`，条和按钮各往 goo 层
/// 投一块白剪影（`z-index:-1`），blur σ=3 之后过 `22α − 8.67` 那道硬阈值。所以这一格
/// 真正的形状只有两条读数：块与块之间**缝 ≤ 5px 就接上**、**松开就各自成胶囊**。
///
/// 静止态按钮被塞在条的右端**里面**（位移 −48，正好被 274 的条盖住），于是整块读数是
/// 一条干净的 274×56 胶囊；聚焦之后它走 `0.22,1.3,0.71,1` 那条 520ms 补间挪到 +0，
/// 同时条 274→266、按钮 38→46。缝 = `48·p − 40`，也就是说到 p=0.833 才刚分开、
/// 到 p≈0.94 才越过 5px 断开——**整段动画只有最后 30ms 在拉丝**，前面全是"从里面走出来"。
///
/// 三条独立时间线（原稿全是 CSS `transition`，这里一一对齐，不换弹簧）：
/// - 位移 520ms `cubic-bezier(.22,1.3,.71,1)`；
/// - 条宽 / 按钮宽高 340ms `cubic-bezier(.24,1.34,.38,1)`（y1=1.34 → 会过冲到 265 / 47）；
/// - 按钮透明度 160ms、麦克风 150ms、底色/图标色 220ms，都走 CSS 默认 `ease`。
///
/// 状态：`激活 = 聚焦 或 文本非空`，`armed = 文本非空`。所以敲了字又删干净（还带着焦点）
/// 时按钮**留在外面**，只是从深底白箭头翻回白底深箭头（220ms 的颜色补间）。
/// Enter 和点按钮都是"提交"：清空文本，但不抢走焦点。
///
/// 两处刻意没照抄：
/// - 输入框的光标是浏览器自己的（530ms 一闪），参考稿没给频率，这里不画；
/// - `data-surface=glass` 那套 1px 渐变描边和 `0 10px 40px` 投影属于演示站的设备档，
///   这一格钉 flat（原稿 flat 下明确无阴影）。
class Case11CommandBar extends StatefulWidget {
  const Case11CommandBar({super.key});

  @override
  State<Case11CommandBar> createState() => _Case11CommandBarState();
}

class _Case11CommandBarState extends State<Case11CommandBar> with SingleTickerProviderStateMixin {
  // ---- 尺寸：全部字面值，这一格不读全局主题
  static const _w = 320.0;
  static const _h = 56.0;
  static const _barIdle = 274.0;
  static const _barOn = 266.0;
  static const _gap = 8.0;
  static const _goIdle = 38.0;
  static const _goOn = 46.0;
  static const _travel = 48.0;
  static const _corner = 28.0;
  static const _padL = 20.0;
  static const _padR = 8.0;
  static const _inner = 6.0;
  static const _micBox = 36.0;
  static const _pressTo = 0.92;

  // ---- goo：blur 3 + `22a − 8.67`，滤镜区 `ceil(3*3 + 60)` = 69
  static const _sigma = 3.0;
  static const _slope = 22.0;
  static const _bias = -8.67;
  static const _pad = 69.0;

  /// 平移列是 **0..255 未归一**，所以 −8.67 要写成 −8.67*255
  static final Float64List _ramp = Float64List.fromList([
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, _slope, _bias * 255, //
  ]);

  static const _walkCurve = Cubic(0.22, 1.3, 0.71, 1);
  static const _sizeCurve = Cubic(0.24, 1.34, 0.38, 1);
  static const _cssEase = Cubic(0.25, 0.1, 0.25, 1);

  /// lucide `audio-lines`（不是麦克风）与 `arrow-up`，viewBox 24 / stroke 2
  static const _micPath = ['M2 10v3', 'M6 6v11', 'M10 3v18', 'M14 8v7', 'M18 5v13', 'M22 10v3'];
  static const _upPath = ['m5 12 7-7 7 7', 'M12 19V5'];

  static const _fieldStyle = TextStyle(
    fontFamily: IlFont.family,
    fontFamilyFallback: IlFont.fallback,
    fontSize: 15,
    height: 1,
    letterSpacing: -0.075,
    color: IlColor.ink,
  );

  static const _hint = 'Ask anything...';

  // ---- 状态
  String _text = '';
  bool _focused = false;
  bool _micHover = false;
  final FocusNode _focusNode = FocusNode(debugLabel: 'interaction-lab.command');

  /// 软键盘只给"带输入连接的可编辑控件"弹出，这一格的假输入走 `Focus.onKeyEvent`
  /// （物理键盘那套），触屏上 `requestFocus()` 什么也不弹。于是常驻压一颗隐形
  /// TextField 在条底下接管焦点，文字经 `onChanged` 喂回 `_text`；桌面不挂这颗，
  /// 事件仍走外层 `Focus`，golden 一像素不动。
  static final bool _softKeyboard = IlTouch.softKeyboard;
  final TextEditingController _editor = TextEditingController();
  final FocusNode _fieldNode = FocusNode(debugLabel: 'interaction-lab.command.field');
  Ticker? _ticker;
  Duration _last = Duration.zero;

  late final _Twn _walk = _Twn(-_travel, dur: 520, curve: _walkCurve);
  late final _Twn _barW = _Twn(_barIdle, dur: 340, curve: _sizeCurve);
  late final _Twn _goW = _Twn(_goIdle, dur: 340, curve: _sizeCurve);
  late final _Twn _goA = _Twn(0, dur: 160, curve: _cssEase);
  late final _Twn _micA = _Twn(1, dur: 150, curve: _cssEase);
  late final _Twn _arm = _Twn(0, dur: 220, curve: _cssEase);
  late final _Twn _press = _Twn(0, dur: 320, curve: _sizeCurve);

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocus);
    _fieldNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_onFocus)
      ..dispose();
    _fieldNode
      ..removeListener(_onFocus)
      ..dispose();
    _editor.dispose();
    _ticker?.stop();
    super.dispose();
  }

  // ---- 交互

  void _onFocus() {
    _focused = _focusNode.hasFocus || _fieldNode.hasFocus;
    _sync();
  }

  void _setText(String next) {
    if (next == _text) return;
    setState(() => _text = next);
    // 真输入框要跟着回写：清空/提交时它要是还留着旧字，下一次 onChanged 会把旧值顶回来
    if (_softKeyboard && _editor.text != next) _editor.text = next;
    _sync();
  }

  void _submit() {
    if (_focused || _text.trim().isNotEmpty) _setText('');
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) {
      if (_text.isNotEmpty) _setText(_text.substring(0, _text.length - 1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      _submit();
      return KeyEventResult.handled;
    }
    // 输入看 `character`（大小写、Shift、输入法都算进去了）；`keyLabel` 是**键名**，
    // 字母永远是大写，只留给没有 character 的场合兜底
    final label = (event.character ?? '').isNotEmpty ? event.character! : key.keyLabel;
    if (label.length != 1 || label.codeUnitAt(0) < 32) return KeyEventResult.ignored;
    _setText(_text + label);
    return KeyEventResult.handled;
  }

  void _sync() {
    final active = _focused || _text.trim().isNotEmpty;
    _walk.aim(active ? 0 : -_travel);
    _barW.aim(active ? _barOn : _barIdle);
    _goW.aim(active ? _goOn : _goIdle);
    _goA.aim(active ? 1 : 0);
    _micA.aim(active ? 0 : 1);
    _arm.aim(_text.trim().isEmpty ? 0 : 1);
    _kick();
  }

  // ---- 一帧只走一根钟

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
    live |= _walk.step(dt);
    live |= _barW.step(dt);
    live |= _goW.step(dt);
    live |= _goA.step(dt);
    live |= _micA.step(dt);
    live |= _arm.step(dt);
    live |= _press.step(dt);
    setState(() {});
    if (!live) _ticker!.stop();
  }

  // ---- 树

  @override
  Widget build(BuildContext context) {
    final barW = _barW.v;
    final goW = _goW.v;
    final goX = barW + _gap + _walk.v;
    final scale = 1 - (1 - _pressTo) * _press.v;
    final armed = _arm.v;

    return IlStage(
      center: false,
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _onKey,
        child: Stack(
          children: [
            // 原稿靠浏览器把焦点收走，这里得留一个出口：点组件外面即失焦
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey('blur'),
                behavior: HitTestBehavior.translucent,
                onTapDown: (_) {
                  _focusNode.unfocus();
                  _fieldNode.unfocus();
                },
              ),
            ),
            Align(
              child: SizedBox(
                width: _w,
                height: _h,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _goo(barW, goX, goW, scale),
                    if (_softKeyboard)
                      Positioned(
                        // 落在文字那一格里：Android 的候选词窗就贴在光标位上
                        left: _padL,
                        right: _padR + _micBox + _inner,
                        top: 0,
                        height: _h,
                        child: Opacity(
                          opacity: 0,
                          child: Material(
                            type: MaterialType.transparency,
                            child: TextField(
                              focusNode: _fieldNode,
                              controller: _editor,
                              maxLines: 1,
                              textInputAction: TextInputAction.send,
                              decoration: const InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                              ),
                              onChanged: (v) {
                                if (v != _text) _setText(v);
                              },
                              onSubmitted: (_) => _submit(),
                            ),
                          ),
                        ),
                      ),
                    _bar(barW),
                    _go(goX, goW, scale, armed),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// `.cmd-goo`：两条剪影一起过 blur 和硬阈值，白色形状全在这一层
  Widget _goo(double barW, double goX, double goW, double scale) {
    return Positioned(
      key: const ValueKey('goo'),
      left: -_pad,
      top: -_pad,
      width: _w + _pad * 2,
      height: _h + _pad * 2,
      child: ColorFiltered(
        colorFilter: ColorFilter.matrix(_ramp),
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: _sigma, sigmaY: _sigma, tileMode: TileMode.decal),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: _pad,
                top: _pad,
                width: barW,
                height: _h,
                child: const DecoratedBox(
                  key: ValueKey('slab-bar'),
                  decoration: BoxDecoration(
                    color: IlColor.pane,
                    borderRadius: BorderRadius.all(Radius.circular(_corner)),
                  ),
                ),
              ),
              Positioned(
                key: const ValueKey('slab-go-pos'),
                left: _pad + goX,
                top: _pad + (_h - goW) / 2,
                width: goW,
                height: goW,
                child: Transform(
                  key: const ValueKey('slab-go-xf'),
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..setEntry(0, 0, scale)
                    ..setEntry(1, 1, scale),
                  child: const DecoratedBox(
                    key: ValueKey('slab-go'),
                    decoration: BoxDecoration(color: IlColor.pane, shape: BoxShape.circle),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// `.cmd`：文字在左、麦克风在右，gap 6；整块受理指针
  Widget _bar(double barW) {
    return Positioned(
      left: 0,
      top: 0,
      width: barW,
      height: _h,
      child: GestureDetector(
        key: const ValueKey('hit-bar'),
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          if (_softKeyboard) {
            _editor.text = _text;
            _fieldNode.requestFocus();
          } else {
            _focusNode.requestFocus();
          }
          _kick();
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.text,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(_padL, 0, _padR, 0),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 18,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _text.isEmpty
                          ? const Text(
                              _hint,
                              key: ValueKey('placeholder'),
                              maxLines: 1,
                              style: TextStyle(
                                fontFamily: IlFont.family,
                                fontFamilyFallback: IlFont.fallback,
                                fontSize: 15,
                                height: 1,
                                letterSpacing: -0.075,
                                color: IlColor.ink5,
                              ),
                            )
                          : Text(
                              _text,
                              key: const ValueKey('text'),
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              style: _fieldStyle,
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: _inner),
                _mic(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// `.cmd-mic`：只有淡入淡出，不缩放不位移
  Widget _mic() {
    return Opacity(
      key: const ValueKey('mic-a'),
      opacity: _micA.v.clamp(0.0, 1.0),
      child: IgnorePointer(
        key: const ValueKey('mic-hit'),
        ignoring: _micA.v < 0.5,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _micHover = true),
          onExit: (_) => setState(() => _micHover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: SizedBox(
              width: _micBox,
              height: _micBox,
              child: Center(
                child: IlIcon(
                  paths: _micPath,
                  size: 18,
                  viewBox: 24,
                  strokeWidth: 2,
                  color: _micHover ? IlColor.ink : IlColor.ink4,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// `.cmd-go`：内容层跟着剪影一起位移/缩放，armed 才翻成深底白箭头
  ///
  /// 按下那 0.92 两层一起缩：原稿的 `:active` 只写在 CSS transform 上，剪影 rect 跟不跟
  /// 没验证过——不跟的话 armed 态会在深底外面露出一圈 1.85px 的白边，看着像画歪了。
  Widget _go(double goX, double goW, double scale, double armed) {
    return Positioned(
      key: const ValueKey('go-pos'),
      left: goX,
      top: (_h - goW) / 2,
      width: goW,
      height: goW,
      child: Opacity(
        key: const ValueKey('go-a'),
        opacity: _goA.v.clamp(0.0, 1.0),
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(0, 0, scale)
            ..setEntry(1, 1, scale),
          child: IgnorePointer(
            key: const ValueKey('go-hit'),
            ignoring: _goA.v < 0.5,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (_) {
                  _press.aim(1);
                  _kick();
                },
                onTapUp: (_) => _press.aim(0),
                onTapCancel: () => _press.aim(0),
                onTap: _submit,
                child: DecoratedBox(
                  key: const ValueKey('go-bg'),
                  decoration: BoxDecoration(
                    color: Color.lerp(IlColor.pane, IlColor.ink, armed)!,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox(
                    width: goW,
                    height: goW,
                    child: Center(
                      child: IlIcon(
                        paths: _upPath,
                        size: 20,
                        viewBox: 24,
                        strokeWidth: 2,
                        color: Color.lerp(IlColor.ink, IlColor.pane, armed)!,
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
}

/// 值到值的定时补间（原稿每条都是一个 `transition`）
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
  final double _dur;
  final Curve _curve;
  bool _running = false;

  double get v => _v;

  /// 目标没变就别重起：悬停这类每帧重发同值会把钟永远清零
  void aim(double target) {
    if (_to == target) return;
    _from = _v;
    _to = target;
    _e = 0;
    _running = true;
  }

  bool step(double dt) {
    if (!_running) return false;
    _e += dt;
    final p = (_e / _dur).clamp(0.0, 1.0);
    _v = _from + (_to - _from) * _curve.transform(p);
    if (p >= 1.0) {
      _v = _to;
      _running = false;
    }
    return _running;
  }
}
