import 'dart:io';

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
import 'package:slime_works/core/theme/app_colors.dart';

/// 侧边栏菜单项
class SidebarMenuItem {
  final AppRouteData route;
  final List<SidebarMenuItem>? children;

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

  // 各分组的折叠状态 (使用group.id作为key，true=折叠)
  final RxMap<String, bool> collapsedGroups = <String, bool>{}.obs;
  // 是否已初始化为移动端模式
  bool _initializedMobile = false;

  /// 切换侧边栏展开/收起状态
  void toggleSidebar() async {
    isExpanded.value = !isExpanded.value;

    if (isExpanded.value) {
      await Future.delayed(const Duration(milliseconds: 280));
      showExtends.value = true;
    } else {
      showExtends.value = false;
    }
  }

  void openSidebar() async {
    if (!isExpanded.value) {
      isExpanded.value = true;
      await Future.delayed(const Duration(milliseconds: 280));
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

  /// 切换分组的折叠/展开状态
  void toggleGroupCollapsed(String groupId) {
    collapsedGroups[groupId] = !(collapsedGroups[groupId] ?? false);
  }

  /// 检查分组是否折叠
  bool isGroupCollapsed(String groupId) {
    return collapsedGroups[groupId] ?? false;
  }
}

/// 可收起的侧边栏组件
class CollapsibleSidebar extends StatefulWidget {
  final List<SidebarGroup> groups;
  final double expandedWidth;
  final double collapsedWidth;
  final Duration animationDuration;

  const CollapsibleSidebar({
    super.key,
    required this.groups,
    this.expandedWidth = 240.0,
    this.collapsedWidth = 75.0,
    this.animationDuration = const Duration(milliseconds: 300),
  });

  @override
  State<CollapsibleSidebar> createState() => _CollapsibleSidebarState();
}

class _CollapsibleSidebarState extends State<CollapsibleSidebar>
    with SingleTickerProviderStateMixin {
  DesktopScreenProvider get desktopScreen => getIt.get<DesktopScreenProvider>();

  late final AnimationController _entranceController;
  late final Animation<double> _entranceAnimation;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _entranceAnimation = CurvedAnimation(parent: _entranceController, curve: Curves.easeOutCubic);
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        _entranceController.forward();
      }
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

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
      final targetWidth = scaleW(isExpanded ? widget.expandedWidth : widget.collapsedWidth);

      if (desktopScreen.isMobile.value) {
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
          animationDuration: widget.animationDuration,
          isExpanded: isExpanded,
          showExtends: showExtends,
          isMobile: desktopScreen.isMobile.value,
          buildContent: (context) => SafeArea(
            bottom: false,
            child: _buildSidebarContent(context, controller, isExpanded, showExtends),
          ),
        );
      }

      final String globalBackgroundPath = getIt<DesktopScreenProvider>().globalBackgroundPath.value;
      final isDark = theme.brightness == Brightness.dark;

      return FadeTransition(
        opacity: _entranceAnimation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-0.15, 0),
            end: Offset.zero,
          ).animate(_entranceAnimation),
          child: Container(
            margin: EdgeInsets.all(AppTheme.metrics.kSpace6),
            child: AnimatedContainer(
              duration: widget.animationDuration,
              curve: Curves.easeInOutCubic,
              width: targetWidth,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: AppTheme.metrics.radius12,
                boxShadow: desktopScreen.isDesktop.value
                    ? [
                        BoxShadow(
                          color: theme.shadowColor.withAlpha(18),
                          blurRadius: scaleW(16),
                          offset: Offset(scaleW(2), scaleW(2)),
                        ),
                        BoxShadow(
                          color: (isDark ? DarkColors.primary : LightColors.primary).withAlpha(8),
                          blurRadius: scaleW(24),
                          offset: Offset(0, scaleW(4)),
                        ),
                      ]
                    : null,
                gradient: AppTheme.sideBarTheme(
                  context,
                  alpha: globalBackgroundPath.isNotEmpty ? 100 : 255,
                ),
                border: Border.all(
                  width: 1.w,
                  color: isDark
                      ? DarkColors.white10.withAlpha((255 * 0.6).toInt())
                      : Colors.white.withAlpha(180),
                ),
              ),
              child: _buildSidebarContent(context, controller, isExpanded, showExtends),
            ),
          ),
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
              ? const SizedBox.shrink()
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
              : const SizedBox.shrink(),
        ),

        _buildHeader(context, controller, isExpanded),

        Expanded(child: _buildScrollableMenuList(context, controller, isExpanded, showExtends)),

        _buildBottomMenu(context, controller, isExpanded, showExtends),
      ],
    );
  }

  /// 构建侧边栏头部
  Widget _buildHeader(BuildContext context, SidebarController controller, bool isExpanded) {
    if (desktopScreen.isMobile.value) {
      return const SizedBox.shrink();
    }

    return AnimatedContainer(
      duration: widget.animationDuration,
      curve: Curves.easeInOutCubic,
      padding: EdgeInsets.symmetric(
        horizontal: AppTheme.metrics.kSpace8,
        vertical: AppTheme.metrics.kSpace4,
      ),
      alignment: controller.isExpanded.value ? Alignment.bottomRight : Alignment.bottomCenter,
      child: HoverSvgButton(
        size: AppTheme.metrics.fontSize22,
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
    final scrollableGroups = widget.groups
        .take(widget.groups.length - 1)
        .where((group) => group.permission == null || RoleManager.canAccess(group.permission!))
        .toList();

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListView.builder(
        padding: EdgeInsets.symmetric(vertical: AppTheme.metrics.kSpace8),
        itemCount: scrollableGroups.length,
        itemBuilder: (context, groupIndex) {
          final group = scrollableGroups[groupIndex];
          return _SidebarEntranceAnimation(
            index: groupIndex,
            child: _buildGroup(context, controller, group, isExpanded, showExtends),
          );
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
    if (widget.groups.isEmpty) return const SizedBox.shrink();

    final bottomGroup = widget.groups.last;
    if (bottomGroup.permission != null && !RoleManager.canAccess(bottomGroup.permission!)) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace16),
          child: Divider(
            height: scaleW(1),
            thickness: scaleW(0.5),
            color: Theme.of(context).dividerColor.withAlpha(20),
          ),
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

    return Obx(() {
      final bool isCollapsed = controller.isGroupCollapsed(group.id);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (group.title != null && isExpanded)
            InkWell(
              onTap: () => controller.toggleGroupCollapsed(group.id),
              borderRadius: AppTheme.metrics.radius6,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: AppTheme.metrics.kSpace14,
                  vertical: AppTheme.metrics.kSpace6,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        group.title!,
                        style: TextStyle(
                          fontSize: AppTheme.metrics.fontSize11,
                          color: theme.hintColor.withAlpha(180),
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: isCollapsed ? -0.25 : 0,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOutCubic,
                      child: Icon(
                        Icons.expand_more,
                        size: AppTheme.metrics.iconSize14,
                        color: theme.hintColor.withAlpha(120),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (group.title != null && !isExpanded)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppTheme.metrics.kSpace16,
                vertical: AppTheme.metrics.kSpace8,
              ),
              child: Divider(
                height: 1,
                thickness: scaleW(0.5),
                color: theme.dividerColor.withAlpha(20),
              ),
            ),

          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            child: isCollapsed && isExpanded
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: group.items
                        .asMap()
                        .entries
                        .map(
                          (entry) => _buildMenuItem(
                            context,
                            controller,
                            entry.value,
                            isExpanded,
                            showExtends,
                            0,
                          ),
                        )
                        .toList(),
                  ),
          ),
        ],
      );
    });
  }

  /// 构建菜单项
  Widget _buildMenuItem(
    BuildContext context,
    SidebarController controller,
    SidebarMenuItem item,
    bool isExpanded,
    bool showExtends,
    int level,
  ) {
    return Obx(() {
      final isSelected = controller.selectedRoute.value == item.route.location;
      final isItemExpanded = controller.isItemExpanded(item.route.title);
      final theme = Theme.of(context);
      final isDark = theme.brightness == Brightness.dark;

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
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isExpanded ? AppTheme.metrics.kSpace10 : AppTheme.metrics.kSpace12,
                vertical: AppTheme.metrics.kSpace2,
              ),
              child: _SidebarMenuItemButton(
                isSelected: isSelected,
                isExpanded: isExpanded,
                isDark: isDark,
                primaryColor: theme.colorScheme.primary,
                onSurfaceColor: theme.colorScheme.onSurface,
                iconColor: theme.iconTheme.color,
                onTap: () {
                  if (item.hasChildren) {
                    return controller.toggleItemExpanded(item.route.title);
                  }
                  _navigateAndMaybeClose(controller, item.route.location);
                },
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
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeInOutCubic,
                            turns: isItemExpanded ? 0.25 : 0,
                            child: SvgPicture.asset(
                              Assets.image.svg.arrowRight,
                              width: AppTheme.metrics.fontSize13,
                              colorFilter: ColorFilter.mode(
                                theme.textTheme.bodySmall?.color ?? Colors.black.withAlpha(51),
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                        ),
                      ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOutCubic,
                      padding: EdgeInsets.only(left: isExpanded ? 0 : AppTheme.metrics.kSpace4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          if (item.route.sidebarIcon != null)
                            isExpanded
                                ? AnimatedContainer(
                                    duration: const Duration(milliseconds: 250),
                                    curve: Curves.easeInOutCubic,
                                    padding: EdgeInsets.all(AppTheme.metrics.kSpace4),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? theme.colorScheme.primary.withAlpha(isDark ? 25 : 20)
                                          : Colors.transparent,
                                      borderRadius: AppTheme.metrics.radius8,
                                    ),
                                    child: SvgPicture.asset(
                                      item.route.sidebarIcon!,
                                      width: AppTheme.metrics.fontSize18,
                                      colorFilter: isSelected
                                          ? ColorFilter.mode(
                                              theme.colorScheme.primary,
                                              BlendMode.srcIn,
                                            )
                                          : ColorFilter.mode(
                                              theme.iconTheme.color?.withAlpha(179) ?? Colors.black,
                                              BlendMode.srcIn,
                                            ),
                                    ),
                                  )
                                : Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      AnimatedContainer(
                                        duration: const Duration(milliseconds: 250),
                                        curve: Curves.easeInOutCubic,
                                        padding: EdgeInsets.all(AppTheme.metrics.kSpace6),
                                        decoration: BoxDecoration(
                                          color: isSelected && isExpanded
                                              ? theme.colorScheme.primary.withAlpha(
                                                  isDark ? 25 : 20,
                                                )
                                              : Colors.transparent,
                                          borderRadius: AppTheme.metrics.radius8,
                                        ),
                                        child: SvgPicture.asset(
                                          item.route.sidebarIcon!,
                                          width: AppTheme.metrics.fontSize22,
                                          colorFilter: isSelected
                                              ? ColorFilter.mode(
                                                  theme.colorScheme.primary,
                                                  BlendMode.srcIn,
                                                )
                                              : ColorFilter.mode(
                                                  theme.iconTheme.color?.withAlpha(179) ??
                                                      Colors.black,
                                                  BlendMode.srcIn,
                                                ),
                                        ),
                                      ),
                                      if (item.route.sidebarBadgeWidget(context) != null)
                                        Positioned(
                                          right: AppTheme.metrics.kSpace2,
                                          top: AppTheme.metrics.kSpace2,
                                          child: item.route.sidebarBadgeWidget(context)!,
                                        ),
                                    ],
                                  ),
                          if (isExpanded && showExtends)
                            Expanded(
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeInOutCubic,
                                opacity: showExtends ? 1.0 : 0.0,
                                child: ClipRect(
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      SizedBox(width: AppTheme.metrics.kSpace8),
                                      Expanded(
                                        child: Text(
                                          item.route.sidebarLabel,
                                          style: TextStyle(
                                            fontSize: AppTheme.metrics.fontSize13,
                                            fontWeight: isSelected
                                                ? FontWeight.w600
                                                : FontWeight.w500,
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
                                            horizontal: AppTheme.metrics.kSpace6,
                                            vertical: AppTheme.metrics.kSpace2,
                                          ),
                                          constraints: BoxConstraints(
                                            minWidth: AppTheme.metrics.kSpace18,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? theme.colorScheme.primary.withAlpha(25)
                                                : theme.hintColor.withAlpha(30),
                                            borderRadius: AppTheme.metrics.radius8,
                                          ),
                                          child: Text(
                                            item.route.sidebarBadgeCount.toString(),
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: AppTheme.metrics.fontSize9,
                                              fontWeight: FontWeight.w600,
                                              color: isSelected
                                                  ? theme.colorScheme.primary
                                                  : theme.hintColor,
                                            ),
                                            maxLines: 1,
                                          ),
                                        ),
                                      if (item.route.sidebarBadgeWidget(context) != null)
                                        Padding(
                                          padding: EdgeInsets.only(left: AppTheme.metrics.kSpace4),
                                          child: item.route.sidebarBadgeWidget(context)!,
                                        ),
                                      if (item.route.sidebarStatusWidget(context) != null)
                                        Padding(
                                          padding: EdgeInsets.only(left: AppTheme.metrics.kSpace4),
                                          child: item.route.sidebarStatusWidget(context)!,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (item.hasChildren)
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOutCubic,
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

/// 侧边栏菜单项按钮（带选中指示条 + 悬停发光效果）
class _SidebarMenuItemButton extends StatefulWidget {
  final bool isSelected;
  final bool isExpanded;
  final bool isDark;
  final Color primaryColor;
  final Color onSurfaceColor;
  final Color? iconColor;
  final VoidCallback onTap;
  final Widget child;

  const _SidebarMenuItemButton({
    required this.isSelected,
    required this.isExpanded,
    required this.isDark,
    required this.primaryColor,
    required this.onSurfaceColor,
    this.iconColor,
    required this.onTap,
    required this.child,
  });

  @override
  State<_SidebarMenuItemButton> createState() => _SidebarMenuItemButtonState();
}

class _SidebarMenuItemButtonState extends State<_SidebarMenuItemButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOutCubic,
          height: m.kSpace44,
          padding: EdgeInsets.symmetric(horizontal: widget.isExpanded ? m.kSpace4 : m.kSpace4),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? widget.primaryColor.withAlpha(widget.isDark ? 22 : 16)
                : _hovered
                ? widget.onSurfaceColor.withAlpha(widget.isDark ? 10 : 8)
                : Colors.transparent,
            borderRadius: m.radius10,
            boxShadow: [
              if (widget.isSelected)
                BoxShadow(
                  color: widget.primaryColor.withAlpha(widget.isDark ? 18 : 12),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              if (_hovered && !widget.isSelected)
                BoxShadow(
                  color: widget.onSurfaceColor.withAlpha(5),
                  blurRadius: 8,
                  offset: const Offset(0, 1),
                ),
            ],
          ),
          child: Row(
            spacing: m.kSpace8,
            children: [
              if (widget.isExpanded)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOutCubic,
                  width: scaleW(3),
                  height: widget.isSelected ? m.kSpace20 : 0,
                  decoration: BoxDecoration(
                    color: widget.isSelected ? widget.primaryColor : Colors.transparent,
                    borderRadius: BorderRadius.circular(scaleW(2)),
                    boxShadow: widget.isSelected
                        ? [
                            BoxShadow(
                              color: widget.primaryColor.withAlpha(60),
                              blurRadius: scaleW(6),
                              offset: Offset(scaleW(2), 0),
                            ),
                          ]
                        : null,
                  ),
                ),
              Expanded(child: widget.child),
            ],
          ),
        ),
      ),
    );
  }
}

/// 侧边栏菜单项入场动画
class _SidebarEntranceAnimation extends StatefulWidget {
  final int index;
  final Widget child;

  const _SidebarEntranceAnimation({required this.index, required this.child});

  @override
  State<_SidebarEntranceAnimation> createState() => _SidebarEntranceAnimationState();
}

class _SidebarEntranceAnimationState extends State<_SidebarEntranceAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    final delay = Duration(milliseconds: 300 + widget.index * 80);
    Future.delayed(delay, () {
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
      opacity: _animation,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(-0.2, 0), end: Offset.zero).animate(_animation),
        child: widget.child,
      ),
    );
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
    double sidebarLeft;
    double sidebarExpandScale = desktopScreen.sidebarExpandScale.value;
    if (_isDragging) {
      sidebarLeft = -widget.targetWidth + _dragOffset;
    } else if (widget.isExpanded) {
      sidebarLeft = 0;
    } else {
      sidebarLeft = -widget.targetWidth;
      sidebarExpandScale = 1;
    }

    double maskOpacity = 0.0;
    if (_isDragging) {
      maskOpacity = (_dragOffset / widget.targetWidth).clamp(0.0, 1.0);
      sidebarExpandScale = 1.0 - 0.1 * maskOpacity;
    } else if (widget.isExpanded) {
      maskOpacity = 1;
      sidebarExpandScale = 0.9;
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
            if (!widget.isExpanded)
              Positioned(
                left: 0,
                top: 0,
                width: scaleW(12),
                height: scaleH(250),
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragStart: (details) {
                    if (Navigator.of(context).canPop()) return;
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

            if (widget.isExpanded || _isDragging)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (widget.isExpanded && !_isDragging) {
                      widget.controller.closeSidebar();
                    }
                  },
                  child: AnimatedContainer(
                    duration: _isDragging ? Duration.zero : const Duration(milliseconds: 300),
                    curve: Curves.easeInOutCubic,
                    color: Colors.black.withAlpha(((255 * maskOpacity) * 0.45).toInt()),
                  ),
                ),
              ),

            AnimatedPositioned(
              duration: _isDragging ? Duration.zero : widget.animationDuration,
              curve: Curves.easeInOutCubic,
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
                              color: widget.theme.shadowColor.withAlpha(40),
                              blurRadius: AppTheme.metrics.kSpace24,
                              offset: Offset(AppTheme.metrics.kSpace2, 0),
                            ),
                            BoxShadow(
                              color:
                                  (widget.theme.brightness == Brightness.dark
                                          ? DarkColors.primary
                                          : LightColors.primary)
                                      .withAlpha(12),
                              blurRadius: AppTheme.metrics.kSpace32,
                              offset: Offset(0, AppTheme.metrics.kSpace4),
                            ),
                          ]
                        : null,
                    gradient: AppTheme.sideBarTheme(context),
                    borderRadius: BorderRadius.only(
                      topRight: Radius.circular(scaleW(16)),
                      bottomRight: Radius.circular(scaleW(16)),
                    ),
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
