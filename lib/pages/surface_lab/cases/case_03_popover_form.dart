import 'dart:async';
import 'dart:ui' show ImageFilter, TileMode;

import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';

import '../kit.dart';
import 'package:slime_works/core/widgets/app_text_field.dart';

/// 3 号表单浮层：长到 192 的面板外面再套一圈 4px 灰框，交完表整张卡换掉
///
/// 和 1 号同为 `layoutId` 形变（按钮 ⇄ 面板共用一个盒子、那行标题是同一块飞过去），
/// 但这张多三件事：
/// 1. 面板自带 `p-1` —— 外圈那 4px 是 `--muted` 的灰框，白卡只有 356×184；
/// 2. 页脚上沿是一条 352 的**虚线**，两端各咬一个 6×12 的缺口（卡边绕着缺口弯过去）；
/// 3. 提交之后不是关掉，而是 form 和 success **两块表面互相顶替**：旧的往下挪 8、
///    淡掉、糊 4px，新的从上面 32 处落下来变清楚 —— 两路吃同一条弹簧。
/// 形变那一路参考稿没挂 `MotionConfig`，走的是布局动画的默认档
/// `stiffness:300 / damping:30`（ζ=.866，行程 156 落定 608ms，末端有一点过冲）；
/// 换脸和翻面那两路是自己写的 `bounce:0`（ζ=1，没有过冲）。
class Case03PopoverForm extends StatefulWidget {
  const Case03PopoverForm({super.key});

  /// 测试要读的那几个落点/尺寸
  static const boxKey = ValueKey<String>('sv-c03-box');
  static const formKey = ValueKey<String>('sv-c03-form');
  static const footerKey = ValueKey<String>('sv-c03-footer');
  static const sepKey = ValueKey<String>('sv-c03-sep');
  static const notchKey = ValueKey<String>('sv-c03-notch');
  static const tabKey = ValueKey<String>('sv-c03-tab');
  static const labelKey = ValueKey<String>('sv-c03-label');
  static const noteKey = ValueKey<String>('sv-c03-note');
  static const caretKey = ValueKey<String>('sv-c03-caret');
  static const submitKey = ValueKey<String>('sv-c03-submit');
  static const btnLabelKey = ValueKey<String>('sv-c03-btn-label');
  static const spinnerKey = ValueKey<String>('sv-c03-spinner');
  static const successKey = ValueKey<String>('sv-c03-success');

  @override
  State<Case03PopoverForm> createState() => _Case03PopoverFormState();
}

class _Case03PopoverFormState extends State<Case03PopoverForm> with SingleTickerProviderStateMixin {
  // ===== 参考稿量出来的那一套（字面 px，见 §12.3 的例外）=====

  /// 面板：`width:364px height:192px`，`borderRadius:10`
  static const _panelW = 364.0;
  static const _panelH = 192.0;
  static const _panelRadius = 10.0;

  /// 面板自带的 4px 灰框（`p-1`）：白卡 356×184，比面板小一圈
  static const _gutter = 4.0;
  static const _cardW = _panelW - _gutter * 2;
  static const _cardH = _panelH - _gutter * 2;

  /// 按钮：`h-9` + `px-3`，`borderRadius:8`
  static const _btnH = 36.0;
  static const _btnPadX = 12.0;
  static const _btnRadius = 8.0;

  /// 面板 `absolute` 挂在按钮左上角，形变是"往右下长"（这一档是舞台坐标）
  static const _origin = Offset(4, 24);

  /// 描边占的宽度：CSS 的 border-box 把内容盒往里顶一格，`DecoratedBox` 只画不让
  static const _bw = 1.0;

  /// 白卡的内容盒
  static const _cardInW = _cardW - _bw * 2; // 354
  static const _cardInH = _cardH - _bw * 2; // 182

  /// textarea `h-32 p-3`、页脚 `h-12 px-[10px]`：两截加起来 176，卡里剩 6px 空在页脚下面
  /// （参考稿没给页脚 flex-grow，就这么空着）。于是页脚上沿在面板坐标 133 = 4+1+128
  static const _taH = 128.0;
  static const _taPad = 12.0;
  static const _footH = 48.0;
  static const _footPadX = 10.0;

  /// 标题的落点：面板里的 `left-4 top-[17px]`。起跳点是按钮的行盒
  /// （`px-3` 12 + 1 描边，20 的行盒居中在 36 的边框盒里 → 顶 8）
  static const _labelTo = Offset(16, 17);
  static const _labelFrom = Offset(_btnPadX + _bw, (_btnH - 20) / 2);

  /// 正文的文本原点：textarea 的 `p-3`（这一档是卡内容盒坐标，不是面板坐标）
  static const _noteAt = Offset(_taPad, _taPad);

  /// 正文行宽上限：卡内容 354 里左右各 12
  static const _noteMaxW = _cardInW - _taPad * 2;

  /// Submit：`h-6 w-26`（v4 的 26×4=104）、`rounded-md`、12/16 加粗
  static const _submitH = 24.0;
  static const _submitW = 104.0;
  static const _submitRadius = 8.0;
  static const _submitX = _gutter + _bw + _cardInW - _footPadX - _submitW; // 245

  /// 虚线：`width=352` 的 svg 压在页脚上沿（`top-[-1px]`，线画在第 1 行）
  static const _sepW = 352.0;

  /// 缺口：6×12 的 svg，舌头咬进卡边里，上下各拖一条 2 的小尾巴
  static const _notchW = 6.0;
  static const _notchH = 12.0;

  /// 顶部收起把手的盒子：`w-[12px] h-[26px]`，骑在面板上沿（`-top-[5px]`）
  static const _tabW = 12.0;
  static const _tabH = 26.0;
  static const _tabTop = -5.0;

  /// 把手盒（面板坐标）
  static const _tabRect = Rect.fromLTWH((_panelW - _tabW) / 2, _tabTop, _tabW, _tabH);

  /// 换脸行程：form 退 `{y:8, blur(4)}`、success 进 `{y:-32, blur(4)}`
  static const _footRise = 8.0;
  static const _headRise = 32.0;
  static const _swapBlur = 4.0;

  /// 按钮里 label⇄spinner 的行程（在 `overflow-hidden` 的 24 高盒子里飞 25）
  static const _flipRise = 25.0;

  /// 参考稿的两段等待：提交后 1500ms 出成功页，3300ms 整体收起
  static const _loadingMs = 1500;
  static const _resetMs = 3300;

  static const _ring = Color(0x14000000); // 面板那圈 `0 0 0 1px rgba(0,0,0,.08)`
  static const _edge = Color(0xFFE5E5E5); // `--border`
  static const _ink = Color(0xFF0A0A0A); // `--foreground`
  static const _primary = Color(0xFF171717); // `--primary`
  static const _mutedInk = Color(0xFF737373); // `--muted-foreground`
  static const _mi80 = Color(0xCC737373); // `text-muted-foreground/80`
  static const _frame = Color(0xFFF5F5F5); // `--muted`：那圈 4px 灰框
  static const _btnInk = Color(0xFFFAFAFA); // `--primary-foreground`
  static const _blue = Color(0xFF1A94FF); // 钮外圈那根 0.5px 蓝发丝

  /// 形变：布局动画的默认弹簧
  static const _morphS = 300.0;
  static const _morphD = 30.0;

  /// 换脸：`{duration:.4, bounce:0}` → ζ=1，行程 32 时 448ms 落定
  static const _swapS = 590.0;
  static const _swapD = 48.6;

  /// label⇄spinner：`{duration:.3, bounce:0}` → ζ=1，行程 25 时 336ms 落定
  static const _flipS = 1004.0;
  static const _flipD = 63.4;

  static const _title = 'Feedback';
  static const _submitText = 'Submit';
  static const _successTitle = 'Feedback Received';
  static const _successText = 'Thank you for supporting our project!';

  /// 形变吃的是**高度像素**（kit 里 `rest` 是位置阈值，不是比例）
  final SvSpring _u = SvSpring.phys(stiffness: _morphS, damping: _morphD, from: _btnH);

  /// 换脸：这条就是 success 自己的 y（−32 = 还没进来，0 = 落定）。
  /// form 的退场和它的入场共用同一条进度，所以退场量由同一个 `_q` 派生
  final SvSpring _x = SvSpring.phys(stiffness: _swapS, damping: _swapD, from: -_headRise);

  /// 按钮里那一次翻面：0 = 文字，1 = 转圈的 Loader（值同样是 y，−25 → 0）
  final SvSpring _f = SvSpring.phys(stiffness: _flipS, damping: _flipD, from: -_flipRise);

  final FocusNode _focus = FocusNode(debugLabel: 'surface-lab.popover-form');

  /// 软键盘只给"带输入连接的可编辑控件"弹出，这一格的假输入走 `Focus.onKeyEvent`
  /// （物理键盘那套），触屏上 `requestFocus()` 什么也不弹。于是常驻压一颗隐形
  /// TextField 在 textarea 那一格里，文字经 `onChanged` 喂回 `_note`；桌面不挂这颗，
  /// 事件仍走外层 `Focus`，golden 一像素不动。
  ///
  /// 它不能跟着 `_surface()` 那样按 `show` 挂卸：`requestFocus()` 对还没进树的节点是
  /// 空操作，`_openIt()` 那一刻正好要焦点。
  static final bool _softKeyboard = SvTouch.softKeyboard;
  final TextEditingController _editor = TextEditingController();
  final FocusNode _fieldFocus = FocusNode(debugLabel: 'surface-lab.popover-form.field');
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  bool _open = false;
  bool _loading = false; // 交完表、还没换脸的那 1500ms
  bool _success = false;

  /// 从成功页往回缩的那一段：success 还挂着，只是跟着盒子一起没掉
  bool _fromSuccess = false;
  String _note = '';
  Timer? _toSuccess;
  Timer? _toClose;

  double? _btnW;

  @override
  void initState() {
    super.initState();
    // `late final` 的 ticker 必须在 initState 建：懒初始化没人碰过它，
    // dispose 里读一次就是在"树已经拆完"的时刻去查祖先
    _ticker = createTicker(_tick);
    for (final s in <SvSpring>[_u, _x, _f]) {
      s.addListener(_onTick);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    for (final s in <SvSpring>[_u, _x, _f]) {
      s.removeListener(_onTick);
    }
    _toSuccess?.cancel();
    _toClose?.cancel();
    _focus.dispose();
    _fieldFocus.dispose();
    _editor.dispose();
    super.dispose();
  }

  void _onTick() {
    setState(() {});
    if (_u.atRest && _x.atRest && _f.atRest) {
      _ticker.stop();
      return;
    }
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final dt = elapsed - _last;
    _last = elapsed;
    final ms = dt.inMilliseconds.toDouble();
    for (final s in <SvSpring>[_u, _x, _f]) {
      s.step(ms);
    }
  }

  /// 形变进度：0 = 还是那颗按钮，1 = 面板落定
  double get _p => (_u.value - _btnH) / (_panelH - _btnH);

  /// 换脸进度：0 = form 在原位，1 = success 落定
  double get _q => 1 + _x.value / _headRise;

  /// 翻面进度：0 = 文字，1 = Loader
  double get _w => 1 + _f.value / _flipRise;

  bool get _showPanel => _open || !_u.atRest;

  Rect _box() {
    final w = _btnW ?? _btnPadX * 2;
    return Rect.fromLTWH(_origin.dx, _origin.dy, w + (_panelW - w) * _p, _u.value);
  }

  void _openIt() {
    if (_open) return;
    setState(() {
      _open = true;
      _fromSuccess = false;
    });
    // 换脸的进度要回起点：上一次可能停在成功页那一档
    _x.jumpTo(-_headRise);
    if (_softKeyboard) {
      // 焦点给真输入才弹得出键盘（这颗常驻在树里，见 [_softKeyboard]）
      _editor.text = _note;
      _fieldFocus.requestFocus();
    } else {
      _focus.requestFocus();
    }
    _u.aim(_panelH);
  }

  /// 唯一改 `_note` 的口
  ///
  /// 真输入框要跟着回写：清空/交表时它要是还留着旧字，下一次 `onChanged` 会把旧值顶回来
  void _setNote(String next) {
    if (_note != next) setState(() => _note = next);
    if (_softKeyboard && _editor.text != next) _editor.text = next;
  }

  void _close() {
    if (!_open) return;
    setState(() {
      _fromSuccess = _success;
      _open = false;
      _loading = _success = false;
    });
    _setNote('');
    _toSuccess?.cancel();
    _toClose?.cancel();
    _focus.unfocus();
    _fieldFocus.unfocus();
    _u.aim(_btnH);
    // success 没有声明 exit 档（参考稿只给了 enter）：从成功页收回去就让它原样
    // 挂着跟着盒子缩没，别在半路把 form 那张翻回来闪一下。进度跟着冻住
    if (!_fromSuccess) _x.jumpTo(-_headRise);
    _f.aim(-_flipRise);
  }

  /// 参考稿的 `submit()`：先转圈，1500ms 后换成功页，3300ms 后整体收起
  void _doSubmit() {
    if (!_open || _loading || _success) return;
    // textarea 的 `required` 加 demo 里的 `if (!feedback) return`：空的就不交
    if (_note.isEmpty) return;
    // 交表就把手指引走：转圈和成功页都不该压着一层键盘（桌面这条路焦点不在这颗上，空操作）
    _fieldFocus.unfocus();
    setState(() => _loading = true);
    _f.aim(0);
    _toSuccess = Timer(const Duration(milliseconds: _loadingMs), () {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _success = true;
      });
      // 入场要重新从 −32 起跳，先跳回起点再 aim
      _x.jumpTo(-_headRise);
      _x.aim(0);
    });
    _toClose = Timer(const Duration(milliseconds: _resetMs), _close);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_open) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    // `Cmd/Ctrl + Enter` 直接交表（参考稿挂在 window 的 keydown 上，只认 idle 档）。
    // 修饰键不在 `KeyEvent` 上，只能问键盘自己
    if (key == LogicalKeyboardKey.enter &&
        (HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed) &&
        !_loading &&
        !_success) {
      _doSubmit();
      return KeyEventResult.handled;
    }
    if (_loading || _success) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) {
      if (_note.isNotEmpty) _setNote(_note.substring(0, _note.length - 1));
      return KeyEventResult.handled;
    }
    // 输入看 `character`：`keyLabel` 是键名，字母永远大写，Shift/输入法都不算
    final ch = event.character ?? '';
    if (ch.isEmpty) return KeyEventResult.ignored;
    _setNote(_note + ch);
    return KeyEventResult.handled;
  }

  /// `useClickOutside` 挂在 mousedown 上，所以这里用不收仲裁的 `Listener`
  void _onPointerDown(PointerDownEvent e) {
    if (!_open) return;
    if (_box().contains(e.localPosition)) return;
    _close();
  }

  double _measure(String text, TextStyle style) {
    final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)
      ..layout();
    final w = tp.width;
    tp.dispose();
    return w;
  }

  TextStyle get _body => SvText.body.copyWith(fontSize: 14, height: 20 / 14, color: _ink);

  @override
  Widget build(BuildContext context) {
    // border-box：左右各 12 的内边距之外，描边那一格也占宽
    _btnW ??= _btnPadX * 2 + _bw * 2 + _measure(_title, _body);
    final box = _box();
    final p = _p;
    final show = _showPanel;
    final radius = BorderRadius.circular(_btnRadius + (_panelRadius - _btnRadius) * p);

    return SvStage(
      center: false,
      // 参考稿的 preview 区是白的，而这一格组件自己就带一档 `--muted` 灰：
      // 舞台跟着页面走灰底的话，那圈 4px 灰框正好和背景一个色，等于没有
      color: SvColor.pane,
      child: Listener(
        // 兜底命中要铺满：参考稿的 outside-click 挂在 document 上，空白处也算"点外面"
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onPointerDown,
        child: Focus(
          focusNode: _focus,
          onKeyEvent: _onKey,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: box.left,
                top: box.top,
                width: box.width,
                height: box.height,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    // 收起态整块就是那颗按钮；展开之后这块是面板本体，点击不再是开合，
                    // 而是"把收掉的键盘要回来"（textarea 那一格由真输入自己接）。
                    // 转圈和成功页那两档不抢焦点，免得键盘顶起一个没人看的脸
                    onTap: () {
                      if (!_open) {
                        _openIt();
                      } else if (_softKeyboard &&
                          !_loading &&
                          !_success &&
                          !_fieldFocus.hasFocus) {
                        _fieldFocus.requestFocus();
                      }
                    },
                    // 收起态它是那颗白底描边的按钮，展开态它是那块灰框面板：
                    // `layoutId` 换的是元素自己，样式跟着一起换，不补间
                    child: DecoratedBox(
                      key: Case03PopoverForm.boxKey,
                      decoration: BoxDecoration(
                        color: show ? _frame : SvColor.pane,
                        borderRadius: radius,
                        border: show ? null : Border.all(color: _edge, width: 1),
                        boxShadow: show
                            ? const [
                                BoxShadow(color: _ring, blurRadius: 0, spreadRadius: 1),
                                BoxShadow(
                                    color: Color(0x0A000000), blurRadius: 2, offset: Offset(0, 1)),
                              ]
                            : null,
                      ),
                      // 面板坐标和盒子坐标同一个原点（左上角钉死），所以里面这些东西
                      // 一律按 364×192 的那套数摆，盒子比它小就由这层 ClipRRect 裁
                      child: ClipRRect(
                        borderRadius: radius,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            if (show)
                              OverflowBox(
                                alignment: Alignment.topLeft,
                                minWidth: _panelW,
                                minHeight: _panelH,
                                maxWidth: _panelW,
                                maxHeight: _panelH,
                                child: _surface(),
                              ),
                            // 把手那张脸只有 12×26，指尖按不准：受理区压在它底下
                            // （左右各探 16、往上探 18；往下是正文那一片，让给真输入）
                            if (show && _open && !_success) ...[
                              ...svTapPads(
                                face: _tabRect,
                                grow: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                                onTap: _close,
                                tag: 'tab',
                              ),
                              _tab(),
                            ],
                            _label(p),
                            // 真输入：压在 textarea 那一格里（面板坐标 17,17 起），字全由
                            // 卡里那套假文本画，所以自己隐掉。挂最上层是因为 `Text` 自己
                            // 受理命中（`RenderParagraph.hitTestSelf` 恒真），压在它下面
                            // 那一笔就进不了这颗字段。收起态得靠 IgnorePointer 断掉：
                            // ClipRRect 只裁到那颗按钮的圆角盒，按钮下半截那一点正好落在
                            // 它的矩形里，不挡就是"点按钮 → 键盘弹了面板却没开"
                            if (_softKeyboard)
                              Positioned(
                                left: _gutter + _bw + _noteAt.dx,
                                top: _gutter + _bw + _noteAt.dy,
                                width: _noteMaxW,
                                height: _taH - _noteAt.dy,
                                child: IgnorePointer(
                                  ignoring: !_open,
                                  child: Opacity(
                                    opacity: 0,
                                    child: Material(
                                      type: MaterialType.transparency,
                                      child: AppTextField(
                                        focusNode: _fieldFocus,
                                        controller: _editor,
                                        maxLines: null,
                                        textAlignVertical: TextAlignVertical.top,
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          border: InputBorder.none,
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                        style: _body,
                                        onChanged: _setNote,
                                      ),
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 灰框里那一层：form ⇄ success 互相顶替（`AnimatePresence mode="popLayout"`）
  Widget _surface() {
    final q = _q;
    final succ = _success || _fromSuccess;
    return SizedBox(
      width: _panelW,
      height: _panelH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 退场那一路和入场是同一条进度：q 走到哪儿，旧的 just 淡到哪儿
          if (!succ || q < 1)
            Positioned(
              left: _gutter,
              top: _gutter,
              width: _cardW,
              height: _cardH,
              child: Opacity(
                opacity: 1 - q,
                child: Transform.translate(
                  offset: Offset(0, _footRise * q),
                  child: _blur(q * _swapBlur, _card()),
                ),
              ),
            ),
          if (_success)
            Positioned(
              left: _gutter,
              top: _gutter,
              width: _cardW,
              height: _cardH,
              child: Opacity(
                opacity: q,
                child: Transform.translate(
                  offset: Offset(0, _x.value),
                  child: _blur((1 - q) * _swapBlur, _successBody()),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 白卡：`h-full border bg-white` + `borderRadius:10`
  Widget _card() {
    return DecoratedBox(
      key: Case03PopoverForm.formKey,
      decoration: BoxDecoration(
        color: SvColor.pane,
        borderRadius: BorderRadius.circular(_panelRadius),
        border: Border.all(color: _edge, width: 1),
      ),
      child: Padding(
        // 描边不让位，内容盒自己缩一格
        padding: const EdgeInsets.all(_bw),
        child: SizedBox(
          width: _cardInW,
          height: _cardInH,
          child: Stack(
            children: [
              Positioned.fill(
                child: Column(
                  children: [
                    const SizedBox(height: _taH), // textarea：没边框，只剩一块 128 高的输入区
                    _footer(),
                  ],
                ),
              ),
              // 正文住在卡里：换脸那一路它得跟着旧的那张一起淡、糊、往下挪
              ..._text(),
            ],
          ),
        ),
      ),
    );
  }

  /// 页脚：上沿一条虚线 + 左右两个缺口 + 右对齐的 Submit
  Widget _footer() {
    return SizedBox(
      key: Case03PopoverForm.footerKey,
      width: _cardInW,
      height: _footH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            // `absolute left-0 top-[-1px]`：svg 有 2 高、线画在第 1 行 → 正好压在分界上
            left: 0,
            top: -1,
            child: CustomPaint(
              key: Case03PopoverForm.sepKey,
              size: const Size(_sepW, 2),
              painter: _Dashed(_edge),
            ),
          ),
          const Positioned(
            left: -1.5, // `-translate-x-[1.5px]`
            top: -_notchH / 2, // `-translate-y-1/2`
            child: CustomPaint(
              key: Case03PopoverForm.notchKey,
              size: Size(_notchW, _notchH),
              painter: _Notch(),
            ),
          ),
          Positioned(
            right: -1.5,
            top: -_notchH / 2,
            child: Transform.rotate(
              angle: 3.141592653589793, // `rotate-180`：同一块图形转过去，舌头顶向右边
              child: const CustomPaint(size: Size(_notchW, _notchH), painter: _Notch()),
            ),
          ),
          // Submit 只有 24 高：受理区压在它底下，上下各探 10 凑够指尖那一格
          ...svTapPads(
            face: Rect.fromLTWH(
              _submitX - _gutter - _bw,
              (_footH - _submitH) / 2,
              _submitW,
              _submitH,
            ),
            onTap: _doSubmit,
            tag: 'submit',
          ),
          Positioned(
            left: _submitX - _gutter - _bw,
            top: (_footH - _submitH) / 2,
            child: _submitBtn(),
          ),
        ],
      ),
    );
  }

  /// 那行字：和按钮文字同一个 `layoutId`，所以是飞过去的，不是淡进来的
  Widget _label(double p) {
    return Positioned(
      left: _labelFrom.dx + (_labelTo.dx - _labelFrom.dx) * p,
      top: _labelFrom.dy + (_labelTo.dy - _labelFrom.dy) * p,
      child: Opacity(
        // `data-[success]:text-transparent`：换脸一落地这一行就不吭声了
        opacity: _success ? 0.0 : 1.0,
        // 同一块表面：在按钮里它是 `text-sm font-medium`（前景色），飞进面板之后
        // 换了 `PopoverForm` 自己那档 `text-muted-foreground` —— 换的是元素自己的
        // class，所以一落地就跟着换，不补间
        child: Text(_title,
            key: Case03PopoverForm.labelKey,
            style: _body.copyWith(color: _open ? _mutedInk : _ink)),
      ),
    );
  }

  /// 正文 + 光标：住在 textarea 的文本原点 (17,17)。
  /// 参考稿的 Label 只在成功页让位，打字时它和正文是**叠在一起**的（那行 placeholder
  /// 也被它挡住），这不是漏改，源码里就只有 `data-[success]` 一个条件
  List<Widget> _text() {
    if (_note.isEmpty) return const [];
    return [
      Positioned(
        left: _noteAt.dx,
        top: _noteAt.dy,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _noteMaxW),
          child: Text(_note, key: Case03PopoverForm.noteKey, style: _body),
        ),
      ),
      if (!_loading && !_success)
        Positioned(
          // 落点是文字推进宽度的**亚像素**位置，1px 头发丝骑在两个像素上会被摊成
          // 两根 50% 的灰条；取整才量得到一条实线（最多偏半格）
          left: (_noteAt.dx + _measure(_note, _body)).roundToDouble(),
          top: _noteAt.dy,
          child: const SizedBox(
            key: Case03PopoverForm.caretKey,
            width: 1,
            height: 17,
            child: ColoredBox(color: _ink),
          ),
        ),
    ];
  }

  /// Submit：24 高 104 宽的渐变实心小钮，文字和 Loader 在同一条进度里翻面
  Widget _submitBtn() {
    const style = TextStyle(
      fontFamily: SvFont.family,
      fontFamilyFallback: SvFont.fallback,
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w600,
      color: _btnInk,
    );
    final w = _w;
    // 受理区不在这里：24 高那一圈由页脚 Stack 里的 `SvTapPad` 收，见 `_footer()`
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 参考稿走的是 form 的 submit：textarea 空着直接 return
        onTap: _doSubmit,
        child: Container(
          key: Case03PopoverForm.submitKey,
          width: _submitW,
          height: _submitH,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_submitRadius),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              // `from-primary/90 → to-primary`
              colors: [Color(0xE6171717), _primary],
            ),
            boxShadow: const [
              // 外圈 0.5px 的蓝发丝 + 底下那层落影。
              // 内圈那根 `0 0 1px 1px rgba(255,255,255,.08) inset` 的白发丝在
              // Flutter 的 BoxShadow 里发不出来（inset 没有对应物），只能省
              BoxShadow(color: _blue, blurRadius: 0, spreadRadius: 0.5),
              BoxShadow(color: Color(0x52000000), blurRadius: 1.5, offset: Offset(0, 1)),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Opacity(
                opacity: 1 - w,
                child: Transform.translate(
                  offset: Offset(0, _flipRise * w),
                  child: const Center(
                      child: Text(_submitText, key: Case03PopoverForm.btnLabelKey, style: style)),
                ),
              ),
              Opacity(
                opacity: w,
                child: Transform.translate(
                  offset: Offset(0, -_flipRise * (1 - w)),
                  child: const _Spin(
                    child: SvIcon(
                      key: Case03PopoverForm.spinnerKey,
                      paths: [
                        'M12 2v4', 'M12 18v4', 'M4.93 4.93l2.83 2.83', 'M16.24 16.24l2.83 2.83',
                        'M2 12h4', 'M18 12h4', 'M4.93 19.07l2.83-2.83', 'M16.24 7.76l2.83-2.83',
                      ],
                      size: 12,
                      color: _btnInk,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 成功页：`flex h-full flex-col items-center justify-center`，没有卡也没有描边
  Widget _successBody() {
    return Container(
      key: Case03PopoverForm.successKey,
      width: _cardW,
      height: _cardH,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CustomPaint(size: Size(32, 32), painter: _OkMark()),
          const SizedBox(height: 8 - 4), // `mt-2` 让掉图标自己的 `-mt-1`
          Text(_successTitle,
              style: _body.copyWith(fontWeight: FontWeight.w500, color: _primary)),
          const SizedBox(height: 4), // `mb-1`
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320), // `max-w-xs`
            child: Text(_successText,
                textAlign: TextAlign.center,
                style: _body.copyWith(color: _mutedInk)),
          ),
        ],
      ),
    );
  }

  /// 顶部把手：12×26 的盒子骑在面板上沿，里面是 24 的 ChevronUp 和那块缺口。
  /// 它住在面板这一层里，所以探出上沿的那半截和参考稿一样被 `overflow:hidden` 裁掉
  Widget _tab() {
    return Positioned.fromRect(
      rect: _tabRect,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _close,
          child: Stack(
            key: Case03PopoverForm.tabKey,
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            // `Transform.rotate` 的构造不是 const，所以这一列不能整体 const
            children: [
              Transform.rotate(
                angle: 1.5707963267948966, // `rotate-90`
                child: const CustomPaint(size: Size(44, 22), painter: _TabNotch()),
              ),
              // lucide 的 ChevronUp 没给尺寸就是 24 见方，压在 12 宽的盒子上左右各探 6
              const SvIcon(paths: ['m18 15-6-6-6 6'], size: 24, color: _mi80),
            ],
          ),
        ),
      ),
    );
  }

  Widget _blur(double sigma, Widget child) {
    if (sigma <= 0.01) return child;
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal),
      child: child,
    );
  }
}

/// 页脚上沿那条 4/4 的虚线（`strokeDasharray="4 4"`，1px 粗）
class _Dashed extends CustomPainter {
  const _Dashed(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.butt;
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, 1), Offset((x + 4).clamp(0.0, size.width), 1), paint);
    }
  }

  @override
  bool shouldRepaint(_Dashed old) => old.color != color;
}

/// 缺口的两条 `d`：`--muted` 的舌头咬进卡边，`--border` 的线绕着它弯过去
abstract final class _NotchPaths {
  static const blob = 'M0 2C0.656613 2 1.30679 2.10346 1.91341 2.30448'
      'C2.52005 2.5055 3.07124 2.80014 3.53554 3.17157'
      'C3.99982 3.54301 4.36812 3.98396 4.6194 4.46927'
      'C4.87067 4.95457 5 5.47471 5 6C5 6.52529 4.87067 7.04543 4.6194 7.53073'
      'C4.36812 8.01604 3.99982 8.45699 3.53554 8.82843'
      'C3.07124 9.19986 2.52005 9.4945 1.91341 9.69552'
      'C1.30679 9.89654 0.656613 10 0 10V6V2Z';
  static const arc = 'M1 12V10C2.06087 10 3.07828 9.57857 3.82843 8.82843'
      'C4.57857 8.07828 5 7.06087 5 6C5 4.93913 4.57857 3.92172 3.82843 3.17157'
      'C3.07828 2.42143 2.06087 2 1 2V0';

  static void draw(Canvas canvas, double strokeWidth) {
    canvas.drawPath(
        parseSvgPathData(blob),
        Paint()
          ..color = const Color(0xFFF5F5F5)
          ..style = PaintingStyle.fill);
    canvas.drawPath(
        parseSvgPathData(arc),
        Paint()
          ..color = const Color(0xFFE5E5E5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeJoin = StrokeJoin.round);
  }
}

/// 6×12 的缺口：等比、1px 描边
class _Notch extends CustomPainter {
  const _Notch();

  @override
  void paint(Canvas canvas, Size size) => _NotchPaths.draw(canvas, 1);

  @override
  bool shouldRepaint(_Notch old) => false;
}

/// 顶部把手那块：同一个 6×12 的 viewBox 被非等比拉伸到 44×22（`preserveAspectRatio:"none"`），
/// 再 `rotate-90`。参考稿这组数自己就不自洽 —— 44×22 转 90° 之后是 22 宽 44 高，比 12×26
/// 的盒子还宽，等于一块比把手还大的灰舌头盖在面板上沿。这里照抄，由出图定档。
class _TabNotch extends CustomPainter {
  const _TabNotch();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 6, size.height / 12);
    _NotchPaths.draw(canvas, 0.6); // 参考稿这路的 strokeWidth 给的是 .6
  }

  @override
  bool shouldRepaint(_TabNotch old) => false;
}

/// 成功页那颗 32 的圆勾：#2090FF 的 16% 淡底 + 2.4 粗的实线圈和勾
class _OkMark extends CustomPainter {
  const _OkMark();

  static const ring = 'M27.6 16C27.6 17.5234 27.3 19.0318 26.717 20.4392'
      'C26.1341 21.8465 25.2796 23.1253 24.2025 24.2025'
      'C23.1253 25.2796 21.8465 26.1341 20.4392 26.717'
      'C19.0318 27.3 17.5234 27.6 16 27.6'
      'C14.4767 27.6 12.9683 27.3 11.5609 26.717'
      'C10.1535 26.1341 8.87475 25.2796 7.79759 24.2025'
      'C6.72043 23.1253 5.86598 21.8465 5.28302 20.4392'
      'C4.70007 19.0318 4.40002 17.5234 4.40002 16'
      'C4.40002 12.9235 5.62216 9.97301 7.79759 7.79759'
      'C9.97301 5.62216 12.9235 4.40002 16 4.40002'
      'C19.0765 4.40002 22.027 5.62216 24.2025 7.79759'
      'C26.3779 9.97301 27.6 12.9235 27.6 16Z';
  static const check = 'M12.1334 16.9667L15.0334 19.8667L19.8667 13.1';

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
        parseSvgPathData(ring),
        Paint()
          ..color = const Color(0xFF2090FF).withValues(alpha: 0.16)
          ..style = PaintingStyle.fill);
    final stroke = Paint()
      ..color = const Color(0xFF2090FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // 参考稿把勾和圈并成同一条 path，这里拆成两笔，视觉同一档
    canvas.drawPath(parseSvgPathData(check), stroke);
    canvas.drawPath(parseSvgPathData(ring), stroke);
  }

  @override
  bool shouldRepaint(_OkMark old) => false;
}

/// `animate-spin`：一秒一圈。出图喂的是假时钟，转过的角度由累计时长决定，可复现
class _Spin extends StatefulWidget {
  const _Spin({required this.child});

  final Widget child;

  @override
  State<_Spin> createState() => _SpinState();
}

class _SpinState extends State<_Spin> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(child: RotationTransition(turns: _c, child: widget.child));
}
