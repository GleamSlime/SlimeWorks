import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/svg.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/buttons/svg_button.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/gen/assets.gen.dart';

/// 侧边栏菜单项
class SidebarMenuItem {
  final String icon;
  final String label;
  final String? route;
  final int? badge; // 徽章数字
  final List<SidebarMenuItem>? children; // 子菜单

  const SidebarMenuItem({required this.icon, required this.label, this.route, this.badge, this.children});

  bool get hasChildren => children != null && children!.isNotEmpty;
}

/// 侧边栏分组
class SidebarGroup {
  final String? title;
  final List<SidebarMenuItem> items;

  const SidebarGroup({this.title, required this.items});
}

/// 侧边栏控制器
class SidebarController extends GetxController {
  // 侧边栏是否展开
  final RxBool isExpanded = true.obs;

  // 侧边栏扩展内容是否显示
  final RxBool showExtends = true.obs;

  // 当前选中的菜单路由
  final RxString selectedRoute = ''.obs;

  // 各个菜单项的展开状态 (使用label作为key)
  final RxMap<String, bool> expandedItems = <String, bool>{}.obs;

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

  const CollapsibleSidebar({
    super.key,
    required this.groups,
    this.expandedWidth = 240.0,
    this.collapsedWidth = 85.0,
    this.animationDuration = const Duration(milliseconds: 300),
  });

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(SidebarController());
    final theme = Theme.of(context);

    return Obx(() {
      final isExpanded = controller.isExpanded.value;
      final showExtends = controller.showExtends.value;
      final targetWidth = scaleW(isExpanded ? expandedWidth : collapsedWidth);

      return Container(
        margin: EdgeInsets.all(AppThemeCommon.kSpace12),
        child: AnimatedContainer(
          duration: animationDuration,
          curve: Curves.easeInOut,
          width: targetWidth,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            // color: Colors.red,
            borderRadius: AppThemeCommon.radius16,
            boxShadow: [BoxShadow(color: theme.shadowColor.withAlpha(25), blurRadius: scaleW(30))],
            gradient: AppTheme.sideBarTheme(context),
            border: BoxBorder.all(width: 1.w, color: AppTheme.isLight(context) ? Colors.white : Color(0xFF333333).withAlpha((255 * 0.9).toInt())),
          ),
          child: Column(
            children: [
              // 侧边栏头部
              _buildHeader(context, controller, isExpanded),

              // 菜单列表（可滚动）
              Expanded(child: _buildScrollableMenuList(context, controller, isExpanded, showExtends)),

              // 底部固定菜单
              _buildBottomMenu(context, controller, isExpanded, showExtends),
            ],
          ),
        ),
      );
    });
  }

  /// 构建侧边栏头部
  Widget _buildHeader(BuildContext context, SidebarController controller, bool isExpanded) {
    return AnimatedContainer(
      duration: animationDuration,
      curve: Curves.easeInOut,
      height: controller.isExpanded.value ? scaleH(40) : scaleH(64),
      padding: EdgeInsets.symmetric(horizontal: AppThemeCommon.kSpace8),
      alignment: controller.isExpanded.value ? Alignment.bottomRight : Alignment.bottomCenter,
      child: HoverSvgButton(
        size: AppThemeCommon.fontSize24,
        svg: controller.isExpanded.value ? Assets.image.svg.sidebarOpen : Assets.image.svg.sidebarClose,
        onTap: controller.toggleSidebar,
        color: Theme.of(context).iconTheme.color,
      ),
    );
  }

  /// 构建可滚动的菜单列表
  Widget _buildScrollableMenuList(BuildContext context, SidebarController controller, bool isExpanded, bool showExtends) {
    final scrollableGroups = groups.take(groups.length - 1).toList();

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListView.builder(
        padding: EdgeInsets.symmetric(vertical: AppThemeCommon.kSpace8),
        itemCount: scrollableGroups.length,
        itemBuilder: (context, groupIndex) {
          final group = scrollableGroups[groupIndex];
          return _buildGroup(context, controller, group, isExpanded, showExtends);
        },
      ),
    );
  }

  /// 构建底部固定菜单
  Widget _buildBottomMenu(BuildContext context, SidebarController controller, bool isExpanded, bool showExtends) {
    if (groups.isEmpty) return const SizedBox.shrink();

    final bottomGroup = groups.last;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(height: 1, thickness: 1, color: Theme.of(context).dividerColor.withAlpha(25)),
        Padding(
          padding: EdgeInsets.symmetric(vertical: AppThemeCommon.kSpace8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: bottomGroup.items.map((item) => _buildMenuItem(context, controller, item, isExpanded, showExtends, 0)).toList(),
          ),
        ),
      ],
    );
  }

  /// 构建分组
  Widget _buildGroup(BuildContext context, SidebarController controller, SidebarGroup group, bool isExpanded, bool showExtends) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 分组标题
        if (group.title != null && isExpanded)
          Padding(
            padding: EdgeInsets.fromLTRB(AppThemeCommon.kSpace12, AppThemeCommon.kSpace4, AppThemeCommon.kSpace12, AppThemeCommon.kSpace4),
            child: Text(
              group.title!,
              style: TextStyle(fontSize: AppThemeCommon.fontSize14, color: theme.hintColor, fontWeight: FontWeight.w500),
            ),
          ),

        if (group.title != null && !isExpanded) Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Divider()),

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
      final isSelected = controller.selectedRoute.value == item.route;
      final isItemExpanded = controller.isItemExpanded(item.label);
      final theme = Theme.of(context);

      return Container(
        decoration: isExpanded
            ? null
            : BoxDecoration(
                color: isItemExpanded ? theme.dividerColor.withAlpha(5) : Colors.transparent,
                border: isItemExpanded ? Border.all(width: 1.w, color: theme.dividerColor.withAlpha(10)) : null,
              ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 菜单项本身
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isExpanded ? AppThemeCommon.kSpace10 : AppThemeCommon.kSpace16,
                vertical: AppThemeCommon.kSpace2,
              ),
              child: Material(
                color: isSelected ? theme.colorScheme.onSurface.withAlpha(25) : Colors.transparent,
                borderRadius: AppThemeCommon.radius12,
                child: InkWell(
                  mouseCursor: SystemMouseCursors.click,
                  onTap: () {
                    if (item.hasChildren) {
                      controller.toggleItemExpanded(item.label);
                    } else if (item.route != null) {
                      controller.selectItem(item.route);
                      Get.toNamed(item.route!);
                    }
                  },
                  splashFactory: NoSplash.splashFactory,
                  highlightColor: Colors.transparent,
                  borderRadius: AppThemeCommon.radius12,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    height: scaleH(44),
                    padding: EdgeInsets.only(left: isExpanded ? scaleW(8 + 20) + (level * scaleW(8 + 20)) : 0, right: isExpanded ? scaleW(8) : 0),
                    alignment: isExpanded ? Alignment.centerLeft : Alignment.center,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        if (isExpanded && item.hasChildren)
                          Positioned(
                            left: -scaleW(20),
                            top: scaleH(5),
                            child: Padding(
                              padding: EdgeInsets.only(right: AppThemeCommon.kSpace4),
                              child: AnimatedRotation(
                                duration: const Duration(milliseconds: 200),
                                turns: isItemExpanded ? 1 : 0.75,
                                child: SvgPicture.asset(
                                  Assets.image.svg.arrowRight,
                                  width: AppThemeCommon.fontSize14,
                                  colorFilter: ColorFilter.mode(theme.textTheme.bodySmall?.color ?? Colors.black.withAlpha(51), BlendMode.srcIn),
                                ),
                              ),
                            ),
                          ),
                        Row(
                          mainAxisAlignment: isExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
                          children: [
                            SvgPicture.asset(
                              item.icon,
                              width: isExpanded ? AppThemeCommon.fontSize20 : AppThemeCommon.fontSize24,
                              colorFilter: isSelected
                                  ? ColorFilter.mode(theme.colorScheme.primary, BlendMode.srcIn)
                                  : ColorFilter.mode(theme.iconTheme.color?.withAlpha(179) ?? Colors.black, BlendMode.srcIn),
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
                                      SizedBox(width: AppThemeCommon.kSpace8),
                                      Expanded(
                                        child: Text(
                                          item.label,
                                          style: TextStyle(
                                            fontSize: AppThemeCommon.fontSize14,
                                            color: isSelected ? theme.colorScheme.primary : theme.textTheme.bodyMedium?.color,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          softWrap: false,
                                          maxLines: 1,
                                        ),
                                      ),
                                      if (item.badge != null)
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: scaleW(5), vertical: scaleH(1)),
                                          constraints: BoxConstraints(minWidth: scaleW(18)),
                                          decoration: BoxDecoration(color: theme.hintColor.withAlpha(38), borderRadius: AppThemeCommon.radius8),
                                          child: Text(
                                            item.badge.toString(),
                                            textAlign: TextAlign.center,
                                            style: TextStyle(fontSize: AppThemeCommon.fontSize8, color: theme.hintColor),
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
                        spacing: AppThemeCommon.kSpace4,
                        children: [
                          ...item.children!.map(
                            (child) => isExpanded && showExtends
                                ? _buildMenuItem(context, controller, child, isExpanded, showExtends, level + 1)
                                : _buildCollapsedChildItem(context, controller, child),
                          ),
                          SizedBox(height: AppThemeCommon.kSpace4),
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
  Widget _buildCollapsedChildItem(BuildContext context, SidebarController controller, SidebarMenuItem item) {
    return Obx(() {
      final isSelected = controller.selectedRoute.value == item.route;
      final theme = Theme.of(context);

      return Material(
        color: isSelected ? theme.colorScheme.onSurface.withAlpha(25) : Colors.transparent,
        child: InkWell(
          onTap: () {
            if (item.route != null) {
              controller.selectItem(item.route);
              Get.toNamed(item.route!);
            }
          },
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          borderRadius: AppThemeCommon.radius12,
          hoverColor: theme.colorScheme.onSurface.withAlpha(13),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: scaleW(14), vertical: scaleH(10)),
            decoration: BoxDecoration(
              borderRadius: AppThemeCommon.radius12,
              color: isSelected ? theme.colorScheme.onSurface.withAlpha(25) : Colors.transparent,
            ),
            child: Tooltip(
              message: item.label,
              child: HoverSvgButton(
                svg: item.icon,
                color: isSelected ? theme.colorScheme.primary : null,
                onTap: () {
                  if (item.route != null) {
                    controller.selectItem(item.route);
                    Get.toNamed(item.route!);
                  }
                },
              ),
            ),
          ),
        ),
      );
    });
  }
}
