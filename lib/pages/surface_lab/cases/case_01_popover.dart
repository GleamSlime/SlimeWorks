import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';

import '../kit.dart';
import 'package:slime_works/core/widgets/app_text_field.dart';

/// 1 号 Popover：一颗按钮形变成一张面板，文字是同一块飞过去的
///
/// 参考稿这套是 `layoutId` 共享元素形变：按钮和面板挂同一个 id，
/// 面板的 Label 又和按钮里的文字挂同一个 id，于是"点开"不是淡入一层新东西，
/// 而是**同一个盒子从 36 高长到 200 高**、同一行字从按钮里挪到左上角。
/// 四条量（左/上/宽/高）吃同一条弹簧，零初速的线性系统里归一化进度一样，
/// 所以这里只需要一个 0→1 的进度去插值矩形。
class Case01Popover extends StatefulWidget {
  const Case01Popover({super.key});

  /// 测试要读的那几个落点/尺寸
  static const boxKey = ValueKey<String>('sv-c01-box');
  static const labelKey = ValueKey<String>('sv-c01-label');
  static const noteKey = ValueKey<String>('sv-c01-note');
  static const submitKey = ValueKey<String>('sv-c01-submit');
  static const caretKey = ValueKey<String>('sv-c01-caret');

  @override
  State<Case01Popover> createState() => _Case01PopoverState();
}

class _Case01PopoverState extends State<Case01Popover> with SingleTickerProviderStateMixin {
  // ===== 参考稿量出来的那一套（字面 px，见 §12.3 的例外）=====

  /// 面板：`h-[200px] w-[364px]`，圆角 12
  static const _panelW = 364.0;
  static const _panelH = 200.0;
  static const _panelRadius = 12.0;

  /// 按钮：`h-9` + `px-3`，圆角 8
  static const _btnH = 36.0;
  static const _btnPadX = 12.0;
  static const _btnRadius = 8.0;

  /// 面板 `absolute` 挂在按钮的左上角上（`top/left:auto`、`transform:none`），
  /// 所以形变是"从这一点往右下长"。这一档是舞台坐标。
  static const _origin = Offset(4, 24);

  /// 描边占的宽度：CSS 的 border-box 里 1px 边框把内容盒往里让一格，
  /// 而 Flutter 的 `DecoratedBox` 只画不让（它就是层 RenderProxyBox，
  /// 子节点拿到的是同一份约束），所以这一格要自己钉进布局里
  static const _bw = 1.0;

  /// 内容盒 = 边框盒减掉一圈 1px
  static const _contentW = _panelW - _bw * 2;
  static const _contentH = _panelH - _bw * 2;

  /// 按钮里的文字：`items-center` 把 20 的行盒居中在 36 的边框盒里 → 顶 8，
  /// 换算到内容盒是 7
  static const _labelFrom = Offset(_btnPadX, (_btnH - 20) / 2 - _bw);

  /// 面板里的 Label：`left-4 top-3`
  static const _labelTo = Offset(16, 12);

  /// 表单内边距：textarea `px-4 py-3`、footer `px-4 py-3`
  static const _fieldPad = EdgeInsets.fromLTRB(16, 12, 16, 12);

  /// footer 高 = Submit 的 32 + 上下各 12
  static const _footerH = 56.0;
  static const _submitH = 32.0;

  /// Submit 的 `rounded-lg`：参考稿把 radius 标尺重定义在 `--radius:10px` 上，
  /// 所以 `lg` 是 10、`md` 是 8，不是 Tailwind v3 那套 8/12
  static const _submitRadius = 10.0;

  /// textarea 的行宽上限：`w-full px-4` 在 362 的内容盒里减掉左右各 16
  static const _noteMaxW = _contentW - 32.0;

  /// 参考稿 `border-zinc-950/10` = rgba(9,9,11,.1)
  static const _edge = Color(0x1A09090B);
  static const _ink = Color(0xFF09090B);
  static const _mutedInk = Color(0xFF71717A);
  static const _hoverInk = Color(0xFF27272A);
  static const _hoverBg = Color(0xFFF4F4F5);

  /// 参考稿的 `MotionConfig`：`{type:'spring', bounce:.05, duration:.3}`。
  /// bounce 读成阻尼比 ζ = 1−.05 = .95，阻尼比一定就只剩刚度可调：
  /// 拿假时钟逐帧（4ms 子步）扫过，行程 164px、0.02px 收口，S=1500 那档
  /// 落定在 304ms——正对着参考稿声明的 .3 秒。
  static const _stiffness = 1500.0;
  static const _damping = 73.5;

  static const _triggerText = 'Add Feedback';

  /// 弹簧吃的是**高度像素**，不是 0→1 的进度
  ///
  /// kit 里 `rest` 是位置阈值（px）：拿进度当量的话 0.02 相当于 2%（≈3.3px），
  /// 收口时肉眼看得见台阶，而且"多少毫秒落定"也失去意义。
  final SvSpring _u =
      SvSpring.phys(stiffness: _stiffness, damping: _damping, from: _btnH);
  final FocusNode _focus = FocusNode(debugLabel: 'surface-lab.popover');

  /// 软键盘只给"带输入连接的可编辑控件"弹出，这一格的假输入走 `Focus.onKeyEvent`
  /// （物理键盘那套），触屏上 `requestFocus()` 什么也不弹。于是常驻压一颗隐形
  /// TextField 在 textarea 那一格里，文字经 `onChanged` 喂回 `_note`；桌面不挂这颗，
  /// 事件仍走外层 `Focus`，golden 一像素不动。
  static final bool _softKeyboard = SvTouch.softKeyboard;
  final TextEditingController _editor = TextEditingController();
  final FocusNode _fieldFocus = FocusNode(debugLabel: 'surface-lab.popover.field');

  /// 只有这一条弹簧要吃帧，所以表挂在 State 上而不是套一层 [SvSpringDrive]
  ///
  /// 必须在 initState 里建：`late final` 的懒初始化要是没人碰过它，
  /// dispose 里读一次就会在"树已经拆了"的时刻去查祖先，直接抛。
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  bool _open = false;
  String _note = '';
  bool _hovSubmit = false;
  bool _prsSubmit = false;

  /// 按钮宽 = 12 + 文字 + 12：文字量一次就够，形变期间它是常量
  double? _btnW;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    _u.addListener(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _u.removeListener(_onTick);
    _focus.dispose();
    _fieldFocus.dispose();
    _editor.dispose();
    super.dispose();
  }

  void _onTick() {
    setState(() {});
    if (_u.atRest) {
      _ticker.stop();
      return;
    }
    // 停过再起的表，对钟值要跟着归零，不然第一帧拿到的是"距上次起跑"的整个时长
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final dt = elapsed - _last;
    _last = elapsed;
    _u.step(dt.inMilliseconds.toDouble());
  }

  /// 归一化进度：四条量（左/上/宽/高）都从它派生
  double get _p => (_u.value - _btnH) / (_panelH - _btnH);

  /// 形变中的盒子（舞台坐标）
  Rect _box() {
    final w = _btnW ?? _btnPadX * 2;
    return Rect.fromLTWH(_origin.dx, _origin.dy, w + (_panelW - w) * _p, _u.value);
  }

  void _openIt() {
    if (_open) return;
    setState(() => _open = true);
    if (_softKeyboard) {
      // 焦点给真输入才弹得出键盘；这颗 TextField 常驻挂在树里（收起态被 IgnorePointer
      // 挡掉命中），所以这一刻 request 得到
      _editor.text = _note;
      _fieldFocus.requestFocus();
    } else {
      _focus.requestFocus();
    }
    _u.aim(_panelH);
  }

  /// 唯一改 `_note` 的口
  ///
  /// 真输入框要跟着回写：清空/提交时它要是还留着旧字，下一次 `onChanged` 会把旧值顶回来
  void _setNote(String next) {
    if (_note != next) setState(() => _note = next);
    if (_softKeyboard && _editor.text != next) _editor.text = next;
  }

  /// 参考稿的 `closePopover` 顺手把 note 清空
  void _close() {
    if (!_open) return;
    setState(() => _open = false);
    _setNote('');
    _focus.unfocus();
    _fieldFocus.unfocus();
    _u.aim(_btnH);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_open) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
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
    final local = e.localPosition;
    if (_box().contains(local)) return;
    _close();
  }

  double _measure(String text, TextStyle style) {
    final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)
      ..layout();
    final w = tp.width;
    tp.dispose();
    return w;
  }

  @override
  Widget build(BuildContext context) {
    final labelStyle = SvText.body.copyWith(fontSize: 14, height: 20 / 14, color: _ink);
    // 宽 = 1 + 12 + 文字 + 12 + 1：border-box 里描边也占宽，少算那 2px 右边留白就比左边窄
    _btnW ??= _btnPadX * 2 + 2 + _measure(_triggerText, labelStyle);
    final box = _box();
    final p = _p;
    final radius = BorderRadius.circular(_btnRadius + (_panelRadius - _btnRadius) * p);

    return SvStage(
      center: false,
      height: 248,
      child: Listener(
        // `Listener` 默认 `deferToChild`：光标落在面板外的空白上时，
        // 树里没任何东西受理命中，这一层根本收不到 mousedown。
        // 参考稿的 outside-click 挂在 document 上，那一段空白也算"点在外面"，
        // 所以这里必须把命中铺满整块舞台。
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
                    // 而是"把收掉的键盘要回来"（textarea 那一格由真输入自己接）
                    onTap: () {
                      if (!_open) {
                        _openIt();
                      } else if (_softKeyboard && !_fieldFocus.hasFocus) {
                        _fieldFocus.requestFocus();
                      }
                    },
                    child: DecoratedBox(
                      key: Case01Popover.boxKey,
                      decoration: BoxDecoration(
                        // 参考稿的按钮没有 hover 档，只有手型光标
                        color: SvColor.pane,
                        borderRadius: radius,
                        border: Border.all(color: _edge, width: 1),
                      ),
                      child: Padding(
                        // 描边不让位，内容盒就得自己缩（见 [_bw]）
                        padding: const EdgeInsets.all(_bw),
                        child: ClipRRect(
                          borderRadius: radius,
                          // 面板按最终尺寸排版，盒子比它小就是 `overflow:hidden` 在裁
                          child: OverflowBox(
                            alignment: Alignment.topLeft,
                            minWidth: _contentW,
                            minHeight: _contentH,
                            maxWidth: _contentW,
                            maxHeight: _contentH,
                            child: SizedBox(
                              width: _contentW,
                              height: _contentH,
                              child: _form(p, labelStyle),
                            ),
                          ),
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

  Widget _form(double p, TextStyle labelStyle) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // textarea：`h-full w-full px-4 py-3`，收起态被盒子裁掉，展开后占满 Label 以下
        // 行盒只给宽度上限、不给死宽度，测试才量得到"这一行有多长"来对光标
        Positioned(
          left: _fieldPad.left,
          top: _fieldPad.top,
          child: _note.isEmpty
              ? const SizedBox.shrink()
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _noteMaxW),
                  child: Text(_note,
                      key: Case01Popover.noteKey,
                      style: labelStyle.copyWith(color: _ink)),
                ),
        ),
        Positioned(
          left: 0,
          top: _contentH - _footerH,
          right: 0,
          height: _footerH,
          child: Stack(
            children: [
              // 两张脸都只有 32 高、X 更是只有 16 宽，指尖按不准：受理区压在它们底下，
              // 上下各探 6 凑到 44（页脚 56 高，正好容得下）
              ...svTapPads(
                face: Rect.fromLTWH(_fieldPad.left, _fieldPad.top, 16, _submitH),
                onTap: _close,
                tag: 'close',
              ),
              ...svTapPads(
                face: Rect.fromLTWH(
                  _contentW - _fieldPad.right - _submitW,
                  _fieldPad.top,
                  _submitW,
                  _submitH,
                ),
                onTap: _tapSubmit,
                tag: 'submit',
              ),
              Padding(
                padding: _fieldPad,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // X：`flex items-center` + lucide X size=16
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _close,
                        child: const SizedBox(
                          width: 16,
                          height: _submitH,
                          child: Center(
                            child: SvIcon(
                              paths: ['M18 6 6 18', 'm6 6 12 12'],
                              size: 16,
                              color: _ink,
                            ),
                          ),
                        ),
                      ),
                    ),
                    _submit(),
                  ],
                ),
              ),
            ],
          ),
        ),
        // 光标：跟着已输入的文字排，参考稿是浏览器自己的插入符（这里不闪，出图才稳定）
        if (_note.isNotEmpty)
          Positioned(
            // 落点是文字推进宽度的**亚像素**位置，1px 的头发丝骑在两个像素上会被
            // 摊成两根 50% 的灰条；取整才量得到一条 1px×17 的实线（最多偏半格）
            left: (_fieldPad.left + _measure(_note, labelStyle)).roundToDouble(),
            top: _fieldPad.top,
            child: const SizedBox(
              key: Case01Popover.caretKey,
              width: 1,
              height: 17,
              child: ColoredBox(color: _ink),
            ),
          ),
        // Label：和按钮文字同一个 layoutId，所以它是"飞过去"的而不是淡入的
        Positioned(
          left: _labelTo.dx + (_labelFrom.dx - _labelTo.dx) * (1 - p),
          top: _labelTo.dy + (_labelFrom.dy - _labelTo.dy) * (1 - p),
          child: Opacity(
            // 参考稿是 `opacity: note ? 0 : 1`，一有字就让位
            opacity: _note.isEmpty ? 1 : 0,
            // 同一块表面在按钮里是 `text-zinc-950`，飞进面板之后它是
            // `PopoverLabel` 那档 `text-zinc-500` —— 换的是元素自己的 class，
            // 所以形变一落地就跟着换色，不是渐变的
            child: Text(_triggerText,
                key: Case01Popover.labelKey,
                style: labelStyle.copyWith(color: _open ? _mutedInk : _ink)),
          ),
        ),
        // 真输入：压在 textarea 那一格里，字全由上面那套假文本画，所以自己隐掉。
        // 排在最上层是因为 `Text` 自己受理命中（`RenderParagraph.hitTestSelf` 恒真），
        // 压在它下面那一笔就进不了这颗字段；收起态由 IgnorePointer 挡掉，否则点按钮
        // 下半侧会被它接走，键盘弹了面板却没开。
        if (_softKeyboard)
          Positioned(
            left: _fieldPad.left,
            top: _fieldPad.top,
            width: _noteMaxW,
            height: _contentH - _footerH - _fieldPad.top,
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
                    style: labelStyle,
                    onChanged: _setNote,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Submit 那一格的宽度：`px-2` 内衬 8+8、描边 1+1，再加文字本身
  /// （页脚里那颗受理区要按它定位，改内衬记得一起改）
  double get _submitW =>
      18.0 + _measure('Submit', SvText.body.copyWith(fontSize: 14, height: 20 / 14));

  void _tapSubmit() {
    setState(() => _prsSubmit = false);
    _close();
  }

  Widget _submit() {
    final scale = _prsSubmit ? 0.98 : 1.0;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovSubmit = true),
      onExit: (_) => setState(() => _hovSubmit = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _tapSubmit,
        // 按下档挂在 `Listener` 上而不是 `onTapDown`：手势竞技场要到松手才判出
        // 胜负，`onTapDown` 于是也拖到松手才响；参考稿的 `active:` 是 mousedown
        // 立刻生效的。命中同样要铺满，否则按在描边那一圈上收不到。
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => setState(() => _prsSubmit = true),
          onPointerUp: (_) => setState(() => _prsSubmit = false),
          onPointerCancel: (_) => setState(() => _prsSubmit = false),
          child: Transform.scale(
            scale: scale,
            child: Container(
              key: Case01Popover.submitKey,
              height: _submitH,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _hovSubmit ? _hoverBg : Colors.transparent,
                borderRadius: BorderRadius.circular(_submitRadius),
                border: Border.all(color: _edge, width: 1),
              ),
              child: Text(
                'Submit',
                style: SvText.body.copyWith(
                  fontSize: 14,
                  height: 20 / 14,
                  color: _hovSubmit ? _hoverInk : _mutedInk,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
