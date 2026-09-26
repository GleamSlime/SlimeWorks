import 'dart:async';

import 'package:flutter/material.dart';

import '../kit.dart';

/// 5. Inline confirm — 一按就删，只留 4 秒反悔
///
/// 参考稿这一格没有二次确认：点一下"Delete"直接进 done 态，同时起 4000ms 的钟
/// 自己收回去。能动的东西只有一颗——**背景药丸被弹簧驱动**，标签那两层是
/// "整块瞬移到目标矩形、只补透明度"（`.say-face`/`.say-merged` 的 left/width
/// 走的是 to 值，不是弹簧值），所以交接那一瞬会看到白底还在长大、字已经就位。
///
/// 宽度从 112 长到 206、左右各对称伸出，`left = (260 - w) / 2` 和参考稿那两条
/// 同步弹簧是同一解（left 是 width 的仿射函数，初值也在这条线上）。
/// 去和回是两条弹簧：去 `{460,30,.9}` 干脆，回 `{420,20,.9}` 末尾带一点回送。
///
/// 压扁只在 idle 态有（`:has(.say-face:hover)` 前面钉着 `[data-phase=idle]`）：
/// 悬停 .97、按住 .94，180ms `cubic-bezier(.3,.9,.4,1)`。body 和 face 两颗盒子
/// 都和舞台同心，所以整组按中心缩放是等价的。
///
/// 底部那条 2px 的倒计时从满宽烧到 0，4000ms 线性，被 `.say-merged` 的圆角裁着。
class Case05InlineConfirm extends StatefulWidget {
  const Case05InlineConfirm({super.key});

  @override
  State<Case05InlineConfirm> createState() => _Case05InlineConfirmState();
}

class _Case05InlineConfirmState extends State<Case05InlineConfirm>
    with TickerProviderStateMixin {
  /// `ov=260` 井、`sv=112`/`cv=206` 两态宽；胶囊 44 高坐在 `top:26`
  /// （26+44=70，96-70=26 → 上下各余 26，正好垂直居中）
  static const _wellW = 260.0;
  static const _wellH = 96.0;
  static const _idleW = 112.0;
  static const _doneW = 206.0;
  static const _pillTop = 26.0;
  static const _pillH = 44.0;

  /// `corner` 旋钮默认 22，上限也是 22 —— 三处圆角（body/face/merged）一起走
  static const _corner = 22.0;

  /// `iv=4e3`：反悔窗口，也是倒计时条的时长
  static const _window = Duration(milliseconds: 4000);

  static const _ink = IlColor.ink; // #17181a，face 的字色
  static const _pick = Color(0xFF0D99FF); // undo 的字色/倒计时条
  static const _pickWash = Color(0x1F0D99FF); // rgba(13,153,255,.12)

  /// framer 没写 ease 的补间默认是它自己的 easeOut 表
  static const _fade = Cubic(0, 0.58, 1, 1);

  /// `transition: background .14s` —— CSS 不写时长曲线就是 `ease`
  static const _cssEase = Cubic(0.25, 0.1, 0.25, 1);

  /// 压扁那条：`.3,.9,.4,1`
  static const _squashEase = Cubic(0.3, 0.9, 0.4, 1);

  /// 延后起淡入 = 把整段补间的前一截压成 0（`Interval` 前段恒读 begin 侧的值）
  static const _faceBack = Interval(80 / 260, 1, curve: _fade); // 延 80ms 走 180ms
  static const _mergedIn = Interval(100 / 300, 1, curve: _fade); // 延 100ms 走 200ms

  final IlSpring _w = IlSpring.phys(stiffness: 460, damping: 30, mass: 0.9);

  late final AnimationController _fuse = AnimationController(
    vsync: this,
    duration: _window,
  )..addListener(() {
      if (mounted) setState(() {});
    });

  bool _done = false;
  bool _hover = false;
  bool _pressed = false;
  bool _undoHover = false;
  Timer? _revert;

  @override
  void initState() {
    super.initState();
    _w.jumpTo(_idleW);
  }

  @override
  void dispose() {
    _revert?.cancel();
    _fuse.dispose();
    _w.dispose();
    super.dispose();
  }

  void _delete() {
    setState(() {
      _done = true;
      _pressed = false;
    });
    _w.retune(stiffness: 460, damping: 30, mass: 0.9);
    _w.aim(_doneW);
    _fuse.forward(from: 0);
    _revert?.cancel();
    _revert = Timer(_window, _back);
  }

  void _undo() {
    _revert?.cancel();
    _back();
  }

  void _back() {
    if (!mounted) return;
    setState(() => _done = false);
    _w.retune(stiffness: 420, damping: 20, mass: 0.9);
    _w.aim(_idleW);
    _fuse.stop();
  }

  /// 只有 idle 态吃 squash；done 态那两档在 CSS 里被 `[data-phase=idle]` 挡掉
  double get _sqTarget => _done ? 1 : (_pressed ? 0.94 : _hover ? 0.97 : 1);

  @override
  Widget build(BuildContext context) {
    return IlStage(
      child: IlSpringDrive(
        spring: _w,
        builder: (context) {
          final w = _w.value;
          return SizedBox(
            width: _wellW,
            height: _wellH,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                IlTween(
                  target: _sqTarget,
                  duration: const Duration(milliseconds: 180),
                  curve: _squashEase,
                  builder: (context, s) => Transform.scale(
                    scale: s,
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: _wellW,
                      height: _wellH,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [_body(w), _face()],
                      ),
                    ),
                  ),
                ),
                _merged(),
              ],
            ),
          );
        },
      ),
    );
  }

  /// `.say-body`：唯一被弹簧驱动的那颗白药丸
  Widget _body(double w) => Positioned(
        left: (_wellW - w) / 2,
        top: _pillTop,
        width: w,
        height: _pillH,
        child: const DecoratedBox(
          decoration: BoxDecoration(
            color: IlColor.pane,
            borderRadius: BorderRadius.all(Radius.circular(_corner)),
          ),
        ),
      );

  /// `.say-face`：钉在 idle 矩形上，只有透明度会动
  Widget _face() => Positioned(
        left: (_wellW - _idleW) / 2,
        top: _pillTop,
        width: _idleW,
        height: _pillH,
        child: IlTween(
          target: _done ? 0 : 1,
          duration: Duration(milliseconds: _done ? 80 : 260),
          curve: _done ? _fade : _faceBack,
          builder: (context, o) => Opacity(
            opacity: o.clamp(0.0, 1.0),
            // 透明不等于不存在：`AnimatePresence` 只把退场那一层留 80ms，
            // 这里靠 ignoring 挡住——不挡的话淡没了的 Delete 还在吞点击
            child: IgnorePointer(
              ignoring: _done,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _hover = true),
                onExit: (_) => setState(() => _hover = false),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (_) => setState(() => _pressed = true),
                  onTapCancel: () => setState(() => _pressed = false),
                  onTap: _delete,
                  child: const Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IlIcon(paths: _trash2, size: 15, viewBox: 24, strokeWidth: 2, color: _ink),
                        SizedBox(width: 8),
                        Text('Delete', style: _faceStyle),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  /// `.say-merged`：钉在 done 矩形上，`overflow:hidden` 把倒计时条裁在胶囊里
  Widget _merged() => Positioned(
        left: (_wellW - _doneW) / 2,
        top: _pillTop,
        width: _doneW,
        height: _pillH,
        child: IlTween(
          target: _done ? 1 : 0,
          duration: Duration(milliseconds: _done ? 300 : 80),
          curve: _done ? _mergedIn : _fade,
          builder: (context, o) => Opacity(
            opacity: o.clamp(0.0, 1.0),
            // 同理：idle 态这一整块只是透明度 0，Undo 不能隔着它接指针
            child: IgnorePointer(
              ignoring: !_done,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_corner),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // margin-left:auto：Undo 顶到右端，右端再留 `padding-right:4`
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Row(
                          children: [
                            _deletedPart(),
                            const Spacer(),
                            _undoPart(),
                          ],
                        ),
                      ),
                    ),
                    // width:100% → 0，4000ms 线性 forwards
                    Positioned(
                      left: 0,
                      bottom: 0,
                      width: _doneW * (1 - _fuse.value),
                      height: 2,
                      child: const ColoredBox(color: _pick),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  Widget _deletedPart() => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IlIcon(paths: _check, size: 14, viewBox: 24, strokeWidth: 2, color: IlColor.ink3),
            SizedBox(width: 7),
            Text('Deleted', style: _doneStyle),
          ],
        ),
      );

  Widget _undoPart() => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _undoHover = true),
        onExit: (_) => setState(() => _undoHover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _undo,
          child: IlTween(
            target: _undoHover ? 1 : 0,
            duration: const Duration(milliseconds: 140),
            curve: _cssEase,
            builder: (context, t) => Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 13),
              decoration: BoxDecoration(
                color: Color.lerp(null, _pickWash, t),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IlIcon(paths: _undo2, size: 13, viewBox: 24, strokeWidth: 2, color: _pick),
                  SizedBox(width: 6),
                  Text('Undo', style: _undoStyle),
                ],
              ),
            ),
          ),
        ),
      );
}

/// lucide `trash-2`
const _trash2 = <String>[
  'M10 11v6',
  'M14 11v6',
  'M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6',
  'M3 6h18',
  'M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2',
];

/// lucide `check`
const _check = <String>['M20 6L9 17l-5-5'];

/// lucide `undo-2`
const _undo2 = <String>[
  'M9 14L4 9l5-5',
  'M4 9h10.5a5.5 5.5 0 0 1 5.5 5.5a5.5 5.5 0 0 1-5.5 5.5H11',
];

// `.say-*` 一律不声明字距，行高继承 body 的 1.5；字重只有 undo 那一档是 500

const _faceStyle = TextStyle(
  fontFamily: IlFont.family,
  fontFamilyFallback: IlFont.fallback,
  fontSize: 13,
  fontWeight: FontWeight.w400,
  letterSpacing: 0,
  height: 1.5,
  color: IlColor.ink,
);

const _doneStyle = TextStyle(
  fontFamily: IlFont.family,
  fontFamilyFallback: IlFont.fallback,
  fontSize: 13,
  fontWeight: FontWeight.w400,
  letterSpacing: 0,
  height: 1.5,
  color: IlColor.ink3,
);

const _undoStyle = TextStyle(
  fontFamily: IlFont.family,
  fontFamilyFallback: IlFont.fallback,
  fontSize: 12.5,
  fontWeight: FontWeight.w500,
  letterSpacing: 0,
  height: 1.5,
  color: Color(0xFF0D99FF),
);
