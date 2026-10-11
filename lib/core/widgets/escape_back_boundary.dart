import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// ESC 返回上一页的全局兜底层
///
/// 挂在每条路由的 child 外面（见 `AppRoutes.buildPage`），于是"ESC 退回上一层"
/// 不再需要每个页面自己写一遍。放在路由这一层而不是侧栏外壳那一层，是因为外壳在
/// Navigator 之上——那样对话框、底部抽屉也会把 ESC 冒泡过来，弹层还开着就把底下的
/// 页给弹掉了。
///
/// 三条次序保证：
/// 1. 页内已有的 ESC 处理（媒体库的逐级返回、图片查看器、阅读器）都在这层的子树里，
///    按键先经过它们；它们 `handled` 就到不了这里，`ignored` 才由我们兜底。
/// 2. 焦点被页面里的输入框拿住时同样成立——输入框是我们的后代，事件照样往上冒。
/// 3. 用 `maybePop()` 而不是 `pop()`：`PopScope(canPop: false)` 那些"还有内部层级
///    要退"的页面（媒体库就是）会继续走它自己的退级逻辑，而不是整页弹掉。
class EscapeBackBoundary extends StatefulWidget {
  const EscapeBackBoundary({super.key, required this.child});

  final Widget child;

  @override
  State<EscapeBackBoundary> createState() => _EscapeBackBoundaryState();
}

class _EscapeBackBoundaryState extends State<EscapeBackBoundary> {
  final FocusNode _escNode = FocusNode(debugLabel: 'EscapeBackBoundary');

  /// 本页 scope 的焦点监听对象：上层路由退场、弹层关闭后焦点会交回 scope，
  /// 那一刻才需要再兜底认领一次
  FocusNode? _watchedScope;

  @override
  void initState() {
    super.initState();
    // 首帧之后才谈得上兜底：路由的 scope 要已经建好、页内的 autofocus 也要先跑完
    WidgetsBinding.instance.addPostFrameCallback((_) => _onAttached());
  }

  @override
  void dispose() {
    _watchedScope?.removeListener(_onScopeFocusChanged);
    _watchedScope = null;
    _escNode.dispose();
    super.dispose();
  }

  void _onAttached() {
    if (!mounted) return;
    final scope = _escNode.enclosingScope;
    if (scope != _watchedScope) {
      _watchedScope?.removeListener(_onScopeFocusChanged);
      _watchedScope = scope;
      scope?.addListener(_onScopeFocusChanged);
    }
    _claimIfIdle();
  }

  /// 只有"整页没有任何控件拿到焦点"（primaryFocus 还停在本页 scope 上）时才认领。
  ///
  /// 不能图省事写 `autofocus: true`：那样这一层会在 depth-first 顺序里先于页内的
  /// `Focus(autofocus: true)` 拿到焦点，媒体库正文那种逐级返回就再也没机会跑了
  /// ——事件从我们这层起步，只会往上冒，不会往下走。
  void _claimIfIdle() {
    final scope = _escNode.enclosingScope;
    if (scope == null) return;
    if (identical(FocusManager.instance.primaryFocus, scope)) {
      _escNode.requestFocus();
    }
  }

  void _onScopeFocusChanged() => _claimIfIdle();

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    final navigator = Navigator.of(context);
    // 侧栏直达的顶层页没有上一页，ESC 在这里不该有任何动作
    if (!navigator.canPop()) return KeyEventResult.ignored;
    navigator.maybePop();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _escNode,
      onKeyEvent: _onKeyEvent,
      child: widget.child,
    );
  }
}
