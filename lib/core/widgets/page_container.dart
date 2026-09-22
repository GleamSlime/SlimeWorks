import 'package:flutter/material.dart';

import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';

/// 内容宽度档位
///
/// 项目里出现过 18 种不同的 maxWidth（800/720/680/560/520/480/420/380/300/200…），
/// 直接后果是：切换页面时正文区宽度乱跳，看起来不像同一个产品。
/// 收敛为 4 档，语义清晰到调用点不需要思考数字。
enum ContentWidth {
  /// 表单、设置、详情侧栏
  narrow,

  /// 阅读区、会话流
  medium,

  /// 常规页面（默认）
  regular,

  /// 网格/库视图：铺满，仅留安全上限
  wide;

  /// 逻辑像素上限（未经缩放，交由 [ContentContainer] 走 scaleW）
  double get rawMaxWidth => switch (this) {
    ContentWidth.narrow => 460,
    ContentWidth.medium => 680,
    ContentWidth.regular => 920,
    ContentWidth.wide => 1440,
  };
}

/// 页面内容容器
///
/// 负责三件事，且只负责这三件事：水平居中的宽度上限、左右内距、上下留白。
/// 页面骨架仍由既有的 `ScreenChrome` / `BasePage` 提供，这里是它们内部的
/// 内容层，不改变现有路由结构。
class ContentContainer extends StatelessWidget {
  const ContentContainer({
    super.key,
    required this.child,
    this.width = ContentWidth.regular,
    this.padding,
    this.scrollable = false,
    this.controller,
    this.physics,
  });

  final Widget child;
  final ContentWidth width;
  final EdgeInsetsGeometry? padding;

  /// 为 true 时外层直接套 SingleChildScrollView
  final bool scrollable;
  final ScrollController? controller;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final content = Padding(
      padding:
          padding ??
          EdgeInsets.symmetric(
            horizontal: m.kSpace24,
            vertical: m.kSpace24,
          ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: scaleW(width.rawMaxWidth)),
          child: child,
        ),
      ),
    );

    if (!scrollable) return content;

    return SingleChildScrollView(
      controller: controller,
      physics: physics,
      child: content,
    );
  }
}

/// 分栏容器：固定侧栏 + 自适应主区
///
/// 取代各页面各自 `Row(children:[SizedBox(width: 某魔数), Expanded(...)])` 的写法，
/// 保证不同模块的分栏宽度和间距节奏一致，并在窄屏自动降级为 Tab/堆叠。
class AppSplitView extends StatelessWidget {
  const AppSplitView({
    super.key,
    required this.sidebar,
    required this.body,
    this.sidebarWidth = 260,
    this.gap,
    this.minBodyWidth = 360,
  });

  final Widget sidebar;
  final Widget body;

  /// 未缩放的侧栏设计宽度
  final double sidebarWidth;
  final double? gap;

  /// 主区小于该宽度时，侧栏折叠隐藏（由调用方决定如何补一个入口）
  final double minBodyWidth;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);

    // 侧栏占掉宽度后主区放不下时，改为上下堆叠，避免主区被压到不可用
    final available = MediaQuery.sizeOf(context).width - scaleW(sidebarWidth);
    if (available < scaleW(minBodyWidth)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [sidebar, SizedBox(height: m.kSpace16), Expanded(child: body)],
      );
    }

    // stretch 要求父级给有界高度，因此本组件只能放在撑满区域的容器里
    // （如 Scaffold body / Expanded），不能塞进 ListView / Column。
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: scaleW(sidebarWidth), child: sidebar),
        Container(width: scaleW(1), color: s.hairline),
        SizedBox(width: gap ?? m.kSpace20),
        Expanded(child: body),
      ],
    );
  }
}
