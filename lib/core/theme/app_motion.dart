import 'package:flutter/material.dart';

/// 动效令牌（Motion Tokens）
///
/// 项目里原本散落着 250/280/300/400/600ms 等各自为政的时长，
/// 导致整体观感"有的跟手、有的迟钝"。这里统一为一套节奏：
///
/// - 反馈类（hover/press/选中）→ instant / fast，必须跟手
/// - 状态类（展开/收起/切换）→ base
/// - 空间类（页面转场/抽屉/弹窗）→ slow / emphasis
///
/// 曲线取自 Material 3 Expressive 的命名曲线，减速用 emphasizedDecelerate
/// （进场有弹性收束），加速退场用 emphasizedAccelerate（干脆不拖尾）。
class AppMotion {
  AppMotion._();

  // ── 时长 ──
  static const Duration instant = Duration(milliseconds: 90);
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration base = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 320);
  static const Duration emphasis = Duration(milliseconds: 460);

  /// 列表/卡片批量入场的逐条间隔
  static const Duration stagger = Duration(milliseconds: 45);

  // ── 曲线 ──
  /// 通用：起步快、收尾稳
  static const Cubic standard = Cubic(0.2, 0.0, 0.0, 1.0);

  /// 进场 / 展开：明显减速，产生"落位"感
  static const Cubic decelerate = Cubic(0.05, 0.7, 0.1, 1.0);

  /// 退场 / 收起：加速离开，不拖泥带水
  static const Cubic accelerate = Cubic(0.3, 0.0, 0.8, 0.15);

  /// 线性辅助（进度条等）
  static const Cubic linearish = Cubic(0.0, 0.0, 1.0, 1.0);

  static const Curve standardCurve = standard;
  static const Curve emphasizedDecelerate = decelerate;

  /// 统一的 AnimatedContainer 参数组，避免每处手写 duration+curve
  static const Duration defaultDuration = base;
  static const Curve defaultCurve = standard;
}

/// 页面转场构建器
///
/// 对齐 AI 客户端的常见做法：内容轻微上浮 + 淡入，而不是 Material 默认的
/// 大距离横向推入。转场时长统一走 [AppMotion.slow]。
class AppPageTransitions {
  AppPageTransitions._();

  /// 淡入 + 8px 上浮（用于平级页面切换）
  static PageRouteBuilder<T> fadeUp<T>(
    Widget page, {
    required RouteSettings settings,
  }) {
    return PageRouteBuilder<T>(
      settings: settings,
      transitionDuration: AppMotion.slow,
      reverseTransitionDuration: AppMotion.fast,
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: AppMotion.decelerate,
          reverseCurve: AppMotion.accelerate,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.02),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}

/// 交错入场动画控制器
///
/// 用于卡片网格/列表首次挂载时的逐条浮现，取代各页面手写的
/// `Future.delayed(300 + index * 80)`（该写法会产生可点击但无内容的空窗）。
class StaggerEntrance extends StatefulWidget {
  const StaggerEntrance({
    super.key,
    required this.index,
    required this.child,
    this.delay = AppMotion.fast,
    this.interval = AppMotion.stagger,
    this.duration = AppMotion.slow,
    this.slideFraction = 0.06,
  });

  final int index;
  final Widget child;

  /// 第一条开始的时间
  final Duration delay;

  /// 每条之间的间隔
  final Duration interval;

  /// 单条动画时长
  final Duration duration;

  /// 起始上浮距离（相对自身高度的比例）
  final double slideFraction;

  @override
  State<StaggerEntrance> createState() => _StaggerEntranceState();
}

class _StaggerEntranceState extends State<StaggerEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.decelerate,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: Offset(0, widget.slideFraction),
    end: Offset.zero,
  ).animate(_fade);

  @override
  void initState() {
    super.initState();
    final start = widget.delay + widget.interval * widget.index;
    Future.delayed(start, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
