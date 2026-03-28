import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/svg.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/buttons/svg_button.dart';
import 'package:slime_works/components/window/screen_top_bar.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:slime_works/core/routes/role_manager.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/gen/assets.gen.dart';

/// 侧边栏菜单项
class SidebarMenuItem {
  final AppRouteData route;
  final List<SidebarMenuItem>? children; // 子菜单

  const SidebarMenuItem({required this.route, this.children});

  bool get hasChildren => children != null && children!.isNotEmpty;
}

/// 侧边栏分组
class SidebarGroup {
  final String id;
  final String? title;
  final List<SidebarMenuItem> items;
  final int? sort;
  final String? icon;
  final Permission? permission;

  const SidebarGroup({
    required this.id,
    this.title,
    required this.items,
    this.icon,
    this.permission,
    this.sort,
  });
}

/// 侧边栏控制器
class SidebarController extends GetxController {
  // 侧边栏是否展开
  final RxBool isExpanded = isDesktop ? true.obs : false.obs;

  // 侧边栏扩展内容是否显示
  final RxBool showExtends = true.obs;

  // 当前选中的菜单路由
  final RxString selectedRoute = ''.obs;

  // 各个菜单项的展开状态 (使用label作为key)
  final RxMap<String, bool> expandedItems = <String, bool>{}.obs;

  // 是否已初始化为移动端模式
  bool _initializedMobile = false;

  /// 切换侧边栏展开/收起状态
  void toggleSidebar() async {
    isExpanded.value = !isExpanded.value;

    if (isExpanded.value) {
      await Future.delayed(const Duration(milliseconds: 100));
      showExtends.value = true;
    } else {
      showExtends.value = false;
    }
  }

  /// 打开侧边栏（移动端使用）
  void openSidebar() async {
    if (!isExpanded.value) {
      isExpanded.value = true;
      await Future.delayed(const Duration(milliseconds: 100));
      showExtends.value = true;
    }
  }

  /// 关闭侧边栏（移动端使用）
  void closeSidebar() {
    if (isExpanded.value) {
      showExtends.value = false;
      isExpanded.value = false;
    }
  }

  /// 初始化为移动端模式（默认收起）
  void initMobileMode() {
    if (!_initializedMobile) {
      _initializedMobile = true;
      isExpanded.value = false;
      showExtends.value = false;
    }
  }

  final RxBool isTest = false.obs;

  /// 选择菜单项
  void selectItem(String? route) {
    if (route != null && route.isNotEmpty) {
      selectedRoute.value = route;
    }
  }

  /// 切换菜单项的展开状态
  void toggleItemExpanded(String itemLabel) {
    expandedItems[itemLabel] = !(expandedItems[itemLabel] ?? false);
  }

  /// 检查菜单项是否展开
  bool isItemExpanded(String itemLabel) {
    return expandedItems[itemLabel] ?? false;
  }
}

/// 可收起的侧边栏组件
class CollapsibleSidebar extends StatelessWidget {
  final List<SidebarGroup> groups;
  final double expandedWidth;
  final double collapsedWidth;
  final Duration animationDuration;

  DesktopScreenProvider get desktopScreen => getIt.get<DesktopScreenProvider>();

  const CollapsibleSidebar({
    super.key,
    required this.groups,
    this.expandedWidth = 240.0,
    this.collapsedWidth = 75.0,
    this.animationDuration = const Duration(milliseconds: 300),
  });

  void _navigateAndMaybeClose(SidebarController controller, String route) {
    controller.selectItem(route);
    goRouter.go(route);
    if (desktopScreen.isMobile.value) {
      controller.closeSidebar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(SidebarController());
    final theme = Theme.of(context);

    return Obx(() {
      final isExpanded = controller.isExpanded.value;
      final showExtends = controller.showExtends.value;
      final targetWidth = scaleW(isExpanded ? expandedWidth : collapsedWidth);

      // 移动端使用抽屉式侧边栏
      if (desktopScreen.isMobile.value) {
        // 移动端默认收起（仅在首次）
        if (!controller._initializedMobile) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            controller.initMobileMode();
          });
        }

        final targetWidth = MediaQuery.of(context).size.width / 2;

        return MobileSidebar(
          controller: controller,
          theme: theme,
          targetWidth: targetWidth,
          animationDuration: animationDuration,
          isExpanded: isExpanded,
          showExtends: showExtends,
          isMobile: desktopScreen.isMobile.value,
          buildContent: (context) =>
              _buildSidebarContent(context, controller, isExpanded, showExtends),
        );
      }

      // 桌面端使用原有布局
      return Container(
        margin: EdgeInsets.all(AppTheme.metrics.kSpace12),
        child: AnimatedContainer(
          duration: animationDuration,
          curve: Curves.easeInOut,
          width: targetWidth,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: AppTheme.metrics.radius10,
            boxShadow: desktopScreen.isDesktop.value
                ? [BoxShadow(color: theme.shadowColor.withAlpha(25), blurRadius: scaleW(10))]
                : null,
            gradient: AppTheme.sideBarTheme(context),
            border: Border.all(
              width: 1.w,
              color: AppTheme.isLight(context)
                  ? Colors.white
                  : Color(0xFF333333).withAlpha((255 * 0.9).toInt()),
            ),
          ),
          child: _buildSidebarContent(context, controller, isExpanded, showExtends),
        ),
      );
    });
  }

  /// 构建侧边栏内容
  Widget _buildSidebarContent(
    BuildContext context,
    SidebarController controller,
    bool isExpanded,
    bool showExtends,
  ) {
    if (desktopScreen.isMobile.value) {
      isExpanded = true;
      showExtends = true;
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Obx(
          () => getIt<DesktopScreenProvider>().isMobile.value
              ? SizedBox.shrink()
              : Platform.isMacOS
              ? Padding(
                  padding: EdgeInsets.only(
                    top: AppTheme.metrics.kSpace8,
                    left: isExpanded ? AppTheme.metrics.kSpace8 : 0,
                  ),
                  child: MacWindowButtons(
                    mainAxisAlignment: showExtends
                        ? MainAxisAlignment.start
                        : MainAxisAlignment.center,
                  ),
                )
              : SizedBox.shrink(),
        ),

        // 侧边栏头部
        _buildHeader(context, controller, isExpanded),

        // 菜单列表（可滚动）
        Expanded(child: _buildScrollableMenuList(context, controller, isExpanded, showExtends)),

        // 底部固定菜单
        _buildBottomMenu(context, controller, isExpanded, showExtends),
      ],
    );
  }

  /// 构建侧边栏头部
  Widget _buildHeader(BuildContext context, SidebarController controller, bool isExpanded) {
    if (desktopScreen.isMobile.value) {
      return SizedBox.shrink();
    }

    return AnimatedContainer(
      duration: animationDuration,
      curve: Curves.easeInOut,
      padding: EdgeInsets.symmetric(
        horizontal: AppTheme.metrics.kSpace8,
        vertical: AppTheme.metrics.kSpace4,
      ),
      alignment: controller.isExpanded.value ? Alignment.bottomRight : Alignment.bottomCenter,
      child: HoverSvgButton(
        size: AppTheme.metrics.fontSize24,
        svg: controller.isExpanded.value
            ? Assets.image.svg.sidebarOpen
            : Assets.image.svg.sidebarClose,
        onTap: controller.toggleSidebar,
        color: Theme.of(context).iconTheme.color,
      ),
    );
  }

  /// 构建可滚动的菜单列表
  Widget _buildScrollableMenuList(
    BuildContext context,
    SidebarController controller,
    bool isExpanded,
    bool showExtends,
  ) {
    final scrollableGroups = groups
        .take(groups.length - 1)
        .where((group) => group.permission == null || RoleManager.canAccess(group.permission!))
        .toList();

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListView.builder(
        padding: EdgeInsets.symmetric(vertical: AppTheme.metrics.kSpace8),
        itemCount: scrollableGroups.length,
        itemBuilder: (context, groupIndex) {
          final group = scrollableGroups[groupIndex];
          return _buildGroup(context, controller, group, isExpanded, showExtends);
        },
      ),
    );
  }

  /// 构建底部固定菜单
  Widget _buildBottomMenu(
    BuildContext context,
    SidebarController controller,
    bool isExpanded,
    bool showExtends,
  ) {
    if (groups.isEmpty) return const SizedBox.shrink();

    final bottomGroup = groups.last;
    if (bottomGroup.permission != null && !RoleManager.canAccess(bottomGroup.permission!)) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(
          height: scaleW(1),
          thickness: scaleW(0.5),
          color: Theme.of(context).dividerColor.withAlpha(15),
        ),
        Padding(
          padding: EdgeInsets.symmetric(vertical: AppTheme.metrics.kSpace8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: bottomGroup.items
                .map(
                  (item) => _buildMenuItem(context, controller, item, isExpanded, showExtends, 0),
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  /// 构建分组
  Widget _buildGroup(
    BuildContext context,
    SidebarController controller,
    SidebarGroup group,
    bool isExpanded,
    bool showExtends,
  ) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 分组标题
        if (group.title != null && isExpanded)
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppTheme.metrics.kSpace12,
              vertical: AppTheme.metrics.kSpace4,
            ),
            child: Text(
              group.title!,
              style: TextStyle(
                fontSize: AppTheme.metrics.fontSize14,
                color: theme.hintColor,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.none,
              ),
            ),
          ),

        if (group.title != null && !isExpanded)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Divider(
              height: 1,
              thickness: scaleW(0.5),
              color: theme.dividerColor.withAlpha(25),
            ),
          ),

        // 菜单项列表
        ...group.items.map(
          (item) => _buildMenuItem(
            context,
            controller,
            item,
            isExpanded,
            showExtends,
            0, // 层级
          ),
        ),
      ],
    );
  }

  /// 构建菜单项
  Widget _buildMenuItem(
    BuildContext context,
    SidebarController controller,
    SidebarMenuItem item,
    bool isExpanded,
    bool showExtends,
    int level, // 菜单层级，0为顶级
  ) {
    return Obx(() {
      final isSelected = controller.selectedRoute.value == item.route.location;
      final isItemExpanded = controller.isItemExpanded(item.route.title);
      final theme = Theme.of(context);

      return Container(
        decoration: isExpanded
            ? null
            : BoxDecoration(
                color: isItemExpanded ? theme.dividerColor.withAlpha(5) : Colors.transparent,
                border: isItemExpanded
                    ? Border.all(width: 1.w, color: theme.dividerColor.withAlpha(10))
                    : null,
              ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 菜单项本身
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isExpanded ? AppTheme.metrics.kSpace10 : AppTheme.metrics.kSpace12,
                vertical: AppTheme.metrics.kSpace2,
              ),
              child: Material(
                color: isSelected ? theme.colorScheme.onSurface.withAlpha(25) : Colors.transparent,
                borderRadius: AppTheme.metrics.radius12,
                child: InkWell(
                  mouseCursor: SystemMouseCursors.click,
                  onTap: () {
                    if (item.hasChildren) {
                      return controller.toggleItemExpanded(item.route.title);
                    }

                    _navigateAndMaybeClose(controller, item.route.location);
                  },
                  splashFactory: NoSplash.splashFactory,
                  highlightColor: Colors.transparent,
                  borderRadius: AppTheme.metrics.radius12,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    height: AppTheme.metrics.kSpace44,
                    padding: EdgeInsets.only(
                      left: isExpanded
                          ? AppTheme.metrics.kSpace24 + (level * AppTheme.metrics.kSpace24)
                          : 0,
                      right: isExpanded ? AppTheme.metrics.kSpace8 : 0,
                    ),
                    alignment: isExpanded ? Alignment.centerLeft : Alignment.center,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        if (isExpanded && item.hasChildren)
                          Positioned(
                            left: -AppTheme.metrics.kSpace20,
                            top: AppTheme.metrics.kSpace4,
                            child: Padding(
                              padding: EdgeInsets.only(right: AppTheme.metrics.kSpace4),
                              child: AnimatedRotation(
                                duration: const Duration(milliseconds: 200),
                                turns: isItemExpanded ? 1 : 0.75,
                                child: SvgPicture.asset(
                                  Assets.image.svg.arrowRight,
                                  width: AppTheme.metrics.fontSize14,
                                  colorFilter: ColorFilter.mode(
                                    theme.textTheme.bodySmall?.color ?? Colors.black.withAlpha(51),
                                    BlendMode.srcIn,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Row(
                          mainAxisAlignment: isExpanded
                              ? MainAxisAlignment.start
                              : MainAxisAlignment.center,
                          children: [
                            if (item.route.sidebarIcon != null)
                              SvgPicture.asset(
                                item.route.sidebarIcon!,
                                width: isExpanded
                                    ? AppTheme.metrics.fontSize20
                                    : AppTheme.metrics.fontSize24,
                                colorFilter: isSelected
                                    ? ColorFilter.mode(theme.colorScheme.primary, BlendMode.srcIn)
                                    : ColorFilter.mode(
                                        theme.iconTheme.color?.withAlpha(179) ?? Colors.black,
                                        BlendMode.srcIn,
                                      ),
                              ),
                            if (isExpanded && showExtends)
                              Expanded(
                                child: AnimatedOpacity(
                                  duration: const Duration(milliseconds: 200),
                                  opacity: isExpanded ? 1.0 : 0.0,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      SizedBox(width: AppTheme.metrics.kSpace8),
                                      Expanded(
                                        child: Text(
                                          item.route.sidebarLabel,
                                          style: TextStyle(
                                            fontSize: AppTheme.metrics.fontSize16,
                                            color: isSelected
                                                ? theme.colorScheme.primary
                                                : theme.textTheme.bodyMedium?.color,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          softWrap: false,
                                          maxLines: 1,
                                        ),
                                      ),
                                      if (item.route.sidebarBadgeCount != null)
                                        Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: AppTheme.metrics.kSpace4,
                                            vertical: AppTheme.metrics.kSpace2,
                                          ),
                                          constraints: BoxConstraints(
                                            minWidth: AppTheme.metrics.kSpace16,
                                          ),
                                          decoration: BoxDecoration(
                                            color: theme.hintColor.withAlpha(38),
                                            borderRadius: AppTheme.metrics.radius8,
                                          ),
                                          child: Text(
                                            item.route.sidebarBadgeCount.toString(),
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: AppTheme.metrics.fontSize8,
                                              color: theme.hintColor,
                                            ),
                                            maxLines: 1,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            if (item.hasChildren)
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                child: isItemExpanded
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        spacing: AppTheme.metrics.kSpace4,
                        children: [
                          ...item.children!.map(
                            (child) => isExpanded && showExtends
                                ? _buildMenuItem(
                                    context,
                                    controller,
                                    child,
                                    isExpanded,
                                    showExtends,
                                    level + 1,
                                  )
                                : _buildCollapsedChildItem(context, controller, child),
                          ),
                          SizedBox(height: AppTheme.metrics.kSpace4),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
          ],
        ),
      );
    });
  }

  /// 构建收起状态下的子菜单项
  Widget _buildCollapsedChildItem(
    BuildContext context,
    SidebarController controller,
    SidebarMenuItem item,
  ) {
    return Obx(() {
      final isSelected = controller.selectedRoute.value == item.route.location;
      final theme = Theme.of(context);

      return Material(
        color: isSelected ? theme.colorScheme.onSurface.withAlpha(25) : Colors.transparent,
        child: InkWell(
          onTap: () {
            _navigateAndMaybeClose(controller, item.route.location);
          },
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          borderRadius: AppTheme.metrics.radius12,
          hoverColor: theme.colorScheme.onSurface.withAlpha(13),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: AppTheme.metrics.kSpace12,
              vertical: AppTheme.metrics.kSpace10,
            ),
            decoration: BoxDecoration(
              borderRadius: AppTheme.metrics.radius12,
              color: isSelected ? theme.colorScheme.onSurface.withAlpha(25) : Colors.transparent,
            ),
            child: Tooltip(
              message: item.route.sidebarLabel,
              child: HoverSvgButton(
                svg: item.route.sidebarIcon!,
                color: isSelected ? theme.colorScheme.primary : null,
                onTap: () {
                  _navigateAndMaybeClose(controller, item.route.location);
                },
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// 移动端侧边栏组件（支持手势滑动）
class MobileSidebar extends StatefulWidget {
  final SidebarController controller;
  final ThemeData theme;
  final double targetWidth;
  final Duration animationDuration;
  final bool isExpanded;
  final bool showExtends;
  final Widget Function(BuildContext) buildContent;
  final bool? isMobile;

  const MobileSidebar({
    super.key,
    required this.controller,
    required this.theme,
    required this.targetWidth,
    required this.animationDuration,
    required this.isExpanded,
    required this.showExtends,
    required this.buildContent,
    this.isMobile,
  });

  @override
  State<MobileSidebar> createState() => MobileSidebarState();
}

class MobileSidebarState extends State<MobileSidebar> {
  double _dragOffset = 0.0;
  bool _isDragging = false;

  DesktopScreenProvider get desktopScreen => getIt.get<DesktopScreenProvider>();

  @override
  Widget build(BuildContext context) {
    // 计算侧边栏位置
    double sidebarLeft;
    double sidebarExpandScale = desktopScreen.sidebarExpandScale.value;
    if (_isDragging) {
      // 拖动中：跟随手指
      sidebarLeft = -widget.targetWidth + _dragOffset;
    } else if (widget.isExpanded) {
      // 展开状态
      sidebarLeft = 0;
    } else {
      // 收起状态
      sidebarLeft = -widget.targetWidth;
      sidebarExpandScale = 1;
    }

    // 计算遮罩不透明度
    double maskOpacity = 0.0;
    if (_isDragging) {
      maskOpacity = (_dragOffset / widget.targetWidth).clamp(0.0, 1.0);
      sidebarExpandScale = (1 - maskOpacity).clamp(0.9, 1.0);
    } else if (widget.isExpanded) {
      maskOpacity = 1;
    }

    if (sidebarExpandScale != desktopScreen.sidebarExpandScale.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        desktopScreen.sidebarExpandScale.value = sidebarExpandScale;
      });
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            // 左侧边缘检测区域（用于开始拖动）
            if (!widget.isExpanded)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: scaleW(15), // 边缘检测区域宽度（缩小避免遮挡左侧按钮）
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragStart: (details) {
                    setState(() {
                      _isDragging = true;
                      _dragOffset = 0;
                    });
                  },
                  onHorizontalDragUpdate: (details) {
                    if (_isDragging) {
                      setState(() {
                        _dragOffset = (_dragOffset + details.delta.dx).clamp(
                          0.0,
                          widget.targetWidth,
                        );
                      });
                    }
                  },
                  onHorizontalDragEnd: (details) {
                    if (_isDragging) {
                      setState(() {
                        _isDragging = false;
                      });

                      // 根据拖动距离和速度决定打开或关闭
                      final velocity = details.primaryVelocity ?? 0;
                      if (velocity > 300 || _dragOffset > widget.targetWidth * 0.3) {
                        widget.controller.openSidebar();
                      }

                      setState(() {
                        _dragOffset = 0;
                      });
                    }
                  },
                  child: Container(color: Colors.transparent),
                ),
              ),

            // 背景遮罩层
            if (widget.isExpanded || _isDragging)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (widget.isExpanded && !_isDragging) {
                      widget.controller.closeSidebar();
                    }
                  },
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 4 * maskOpacity, sigmaY: 4 * maskOpacity),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).hintColor.withAlpha(((255 * maskOpacity) * 0.4).toInt()),
                      ),
                    ),
                  ),
                ),
              ),

            // 侧边栏主体
            AnimatedPositioned(
              duration: _isDragging ? Duration.zero : widget.animationDuration,
              curve: Curves.easeInOut,
              left: sidebarLeft,
              top: 0,
              bottom: 0,
              width: widget.targetWidth,
              child: GestureDetector(
                onHorizontalDragUpdate: (details) {
                  if (widget.isExpanded || _isDragging) {
                    setState(() {
                      if (!_isDragging) {
                        _isDragging = true;
                        _dragOffset = widget.targetWidth;
                      }
                      _dragOffset = (_dragOffset + details.delta.dx).clamp(0.0, widget.targetWidth);
                    });
                  }
                },
                onHorizontalDragEnd: (details) {
                  if (_isDragging) {
                    final velocity = details.primaryVelocity ?? 0;

                    setState(() {
                      _isDragging = false;
                    });

                    // 根据速度和位置判断
                    if (velocity < -300 || _dragOffset < widget.targetWidth * 0.5) {
                      widget.controller.closeSidebar();
                    } else if (velocity > 300 || _dragOffset > widget.targetWidth * 0.5) {
                      widget.controller.openSidebar();
                    }

                    setState(() {
                      _dragOffset = 0;
                    });
                  }
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: widget.theme.colorScheme.surface,
                    boxShadow: widget.isMobile != true
                        ? [
                            BoxShadow(
                              color: widget.theme.shadowColor.withAlpha(50),
                              blurRadius: AppTheme.metrics.kSpace20,
                              offset: Offset(AppTheme.metrics.kSpace2, 0),
                            ),
                          ]
                        : null,
                    gradient: AppTheme.sideBarTheme(context),
                  ),
                  child: widget.buildContent(context),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
