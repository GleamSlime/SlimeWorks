import 'package:flutter/widgets.dart';

/// 描边动画的事件源。
///
/// 大容器（工具按钮、侧栏行）按下/悬停时，让**它内部所有** [DrawIcon] 一起重播，
/// 而不是只让指针正下方那 16px 的图形有反应。
class StrokeSignal extends ChangeNotifier {
  StrokeSignal({this.broadcastPress = true, this.broadcastHover = true});

  final bool broadcastPress;
  final bool broadcastHover;

  /// 递增计数：[DrawIcon] 比较它来判断"这一下要不要重播"，
  /// 不用布尔翻转是因为连点两次必须播两次。
  int _pulse = 0;
  int get pulse => _pulse;

  /// 上一次脉冲来自悬停还是按下（供组件决定强度）
  bool _lastFromHover = false;
  bool get lastFromHover => _lastFromHover;

  void fire({required bool fromHover}) {
    _lastFromHover = fromHover;
    _pulse++;
    notifyListeners();
  }
}

/// 给后代 [DrawIcon] 广播重播信号的容器。
///
/// 用 [Listener]（translucent）+ [MouseRegion] 观察事件，不吃事件、不改命中测试顺序，
/// 所以包在 `IconButton` / `InkWell` 外面不会破坏原有交互。
class StrokeZone extends StatefulWidget {
  const StrokeZone({
    super.key,
    required this.child,
    this.broadcastPress = true,
    this.broadcastHover = true,
    this.enabled = true,
  });

  final Widget child;

  /// 按下时是否让内部图标重播
  final bool broadcastPress;

  /// 鼠标进入时是否让内部图标重播（触屏无 hover，自动无效）
  final bool broadcastHover;

  /// 关掉后行为等同于无 Signal 祖先：后代 [DrawIcon] 退回"出现时播一次"
  final bool enabled;

  /// 取最近的事件源；没有则 null，[DrawIcon] 据此决定默认触发方式
  static StrokeSignal? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_StrokeSignalScope>()?.signal;

  @override
  State<StrokeZone> createState() => _StrokeZoneState();
}

class _StrokeZoneState extends State<StrokeZone> {
  late final StrokeSignal _signal = StrokeSignal(
    broadcastPress: widget.broadcastPress,
    broadcastHover: widget.broadcastHover,
  );

  @override
  void dispose() {
    _signal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return _StrokeSignalScope(
      signal: _signal,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: widget.broadcastPress
            ? (_) => _signal.fire(fromHover: false)
            : null,
        child: MouseRegion(
          // onEnter 而不是 onHover：一次进入播一次，鼠标在按钮内挪动不该反复播
          onEnter: widget.broadcastHover
              ? (_) => _signal.fire(fromHover: true)
              : null,
          child: widget.child,
        ),
      ),
    );
  }
}

class _StrokeSignalScope extends InheritedWidget {
  const _StrokeSignalScope({required this.signal, required super.child});

  final StrokeSignal signal;

  @override
  bool updateShouldNotify(_StrokeSignalScope oldWidget) =>
      oldWidget.signal != signal;
}
