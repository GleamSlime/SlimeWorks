import 'package:flutter/material.dart';

import 'package:slime_works/core/utils/size_utils.dart';

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

  /// 应用启动时整块面板的入场时长
  ///
  /// 比 [emphasis] 长是有意的：这一下只在开机播一次，慢一点才看得出层次。
  static const Duration entrance = Duration(milliseconds: 600);

  /// 入场级联里每条的间隔（[stagger] 留给会反复触发的列表动效）
  static const Duration entranceGap = Duration(milliseconds: 80);

  /// 一条入场级联的主控时长：每张卡按 0~1 的 Interval 摊在这条轴上
  ///
  /// 比 [entrance] 长是有意的——它不是单次过渡的时长，而是"整页错开播完"的总长。
  static const Duration cascade = Duration(milliseconds: 900);

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

  // ── 弹簧 ──
  /// 状态改变用弹簧：阻尼比 ζ = 22 / (2√260) ≈ 0.68 → 过冲约 5%，只回一次
  static const SpringDescription spring = SpringDescription(
    mass: 1,
    stiffness: 260,
    damping: 22,
  );

  /// 同一个弹簧给 `AnimatedX` 用的曲线档
  ///
  /// 隐式动画只吃 `Curve`，拿不到 [spring]，所以配一条过冲量一致的近似曲线。
  /// 这样弹簧和曲线两条路出来的观感是同一个动作，不会一档偏弹一档偏黏。
  static const Cubic springCurve = Cubic(0.34, 1.26, 0.44, 1.0);

  /// 弹簧跑完一次的近似时长，只用来给需要 `Duration` 的接口占位
  static const Duration springSettle = Duration(milliseconds: 420);

  // ── 位移（一律宽度族：跟窗口走，不跟用户字号走）──
  /// 文字/图标换脸的位移
  static double get travelMicro => scaleW(4);

  /// 按压下沉、错误抖动
  static double get travelSmall => scaleW(6);

  /// 页面转场上浮、抽屉入场
  static double get travelBase => scaleW(8);

  /// 面板从触发点下方展开
  static double get travelMedium => scaleW(12);

  /// 整块内容换脸（列表↔详情这类）
  static double get travelLarge => scaleW(30);

  // ── 缩放（无量纲，不随窗口，也不许随手取别的值）──
  /// 按压：按下去一点，松手回位
  static const double scalePress = 0.98;

  /// 浮层进场起点（越大越不像"弹出来"）
  static const double scaleEnter = 0.96;

  /// 菜单从触发点长出来
  static const double scaleMenu = 0.97;

  /// 收起终态：差一点就是 1，留着这 1% 才看得出是"同一个东西缩回去"
  static const double scaleRetreat = 0.99;

  // ── 内容切换的瞬时模糊（BackdropFilter 的玻璃模糊另走 `AppGlass.*`）──
  /// 文字、图标换脸
  static const double blurContent = 2;

  /// 面板、抽屉、气泡
  static const double blurPanel = 4;

  /// 页面转场
  static const double blurPage = 8;

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
