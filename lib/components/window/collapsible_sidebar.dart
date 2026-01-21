import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';

/// 侧边栏菜单项
class SidebarMenuItem {
  final IconData icon;
  final String label;
  final String? route;
  final int? badge; // 徽章数字
  final List<SidebarMenuItem>? children; // 子菜单

  const SidebarMenuItem({required this.icon, required this.label, this.route, this.badge, this.children});

  bool get hasChildren => children != null && children!.isNotEmpty;
}

/// 侧边栏分组
class SidebarGroup {
  final String? title; // 分组标题，null表示无标题
  final List<SidebarMenuItem> items;

  const SidebarGroup({this.title, required this.items});
}

/// 侧边栏控制器
class SidebarController extends GetxController {
  // 侧边栏是否展开
  final RxBool isExpanded = true.obs;

  // 当前选中的菜单路由
  final RxString selectedRoute = ''.obs;

  // 各个菜单项的展开状态 (使用label作为key)
  final RxMap<String, bool> expandedItems = <String, bool>{}.obs;

  /// 切换侧边栏展开/收起状态
  void toggleSidebar() {
    isExpanded.value = !isExpanded.value;
  }

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
    this.collapsedWidth = 60.0,
    this.animationDuration = const Duration(milliseconds: 300),
  });

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(SidebarController());
    final theme = Theme.of(context);

    return Obx(() {
      final isExpanded = controller.isExpanded.value;
      final targetWidth = isExpanded ? expandedWidth.w : collapsedWidth.w;

      return AnimatedContainer(
        duration: animationDuration,
        curve: Curves.easeInOut,
        width: targetWidth,
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            // color: Colors.red,
            borderRadius: AppThemeCommon.radius16,
            boxShadow: [BoxShadow(color: theme.shadowColor.withAlpha(25), blurRadius: scaleW(30))],
            gradient: AppTheme.sideBarTheme(context),
            border: BoxBorder.all(width: 1.w, color: AppTheme.isLight(context) ? Colors.white : Color(0xFF333333).withAlpha((255 * 0.9).toInt())),
          ),
          margin: EdgeInsets.all(AppThemeCommon.kSpace12),
          child: Column(
            children: [
              // 侧边栏头部
              _buildHeader(context, controller, isExpanded),

              // 菜单列表（可滚动）
              Expanded(child: _buildScrollableMenuList(context, controller, isExpanded)),

              // 底部固定菜单
              _buildBottomMenu(context, controller, isExpanded),
            ],
          ),
        ),
      );
    });
  }

  /// 构建侧边栏头部
  Widget _buildHeader(BuildContext context, SidebarController controller, bool isExpanded) {
    return Container(
      height: 64.h,
      padding: EdgeInsets.symmetric(horizontal: isExpanded ? 12.w : 0, vertical: 12.h),
      child: isExpanded
          ? Row(
              children: [
                // macOS 交通灯按钮占位
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTrafficLight(Colors.red.shade400),
                    SizedBox(width: 6.w),
                    _buildTrafficLight(Colors.amber.shade400),
                    SizedBox(width: 6.w),
                    _buildTrafficLight(Colors.green.shade400),
                  ],
                ),
                const Spacer(),
                // 收起按钮
                IconButton(
                  icon: Icon(Icons.menu_open, size: 18.sp),
                  onPressed: () => controller.toggleSidebar(),
                  tooltip: '收起侧边栏',
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(minWidth: 28.w, minHeight: 28.h),
                ),
              ],
            )
          : Center(
              child: IconButton(
                icon: Icon(Icons.menu, size: 20.sp),
                onPressed: () => controller.toggleSidebar(),
                tooltip: '展开侧边栏',
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(minWidth: 40.w, minHeight: 40.h),
              ),
            ),
    );
  }

  /// 构建交通灯按钮
  Widget _buildTrafficLight(Color color) {
    return Container(
      width: 12.w,
      height: 12.h,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  /// 构建可滚动的菜单列表（不包括底部固定菜单）
  Widget _buildScrollableMenuList(BuildContext context, SidebarController controller, bool isExpanded) {
    // 过滤出非底部菜单的分组
    final scrollableGroups = groups.take(groups.length - 1).toList();

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        scrollbars: false, // 隐藏滚动条
      ),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: scrollableGroups.length,
        itemBuilder: (context, groupIndex) {
          final group = scrollableGroups[groupIndex];
          return _buildGroup(context, controller, group, isExpanded);
        },
      ),
    );
  }

  /// 构建底部固定菜单
  Widget _buildBottomMenu(BuildContext context, SidebarController controller, bool isExpanded) {
    if (groups.isEmpty) return const SizedBox.shrink();

    final bottomGroup = groups.last;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(height: 1, thickness: 1, color: Theme.of(context).dividerColor.withOpacity(0.1)),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: bottomGroup.items.map((item) => _buildMenuItem(context, controller, item, isExpanded, 0)).toList(),
          ),
        ),
      ],
    );
  }

  /// 构建分组
  Widget _buildGroup(BuildContext context, SidebarController controller, SidebarGroup group, bool isExpanded) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 分组标题
        if (group.title != null && isExpanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              group.title!,
              style: TextStyle(fontSize: 12, color: theme.hintColor, fontWeight: FontWeight.w500),
            ),
          ),

        // 分组标题 - 收起状态显示分割线
        if (group.title != null && !isExpanded)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Divider(height: 1, color: theme.dividerColor.withOpacity(0.3)),
          ),

        // 菜单项列表
        ...group.items.map(
          (item) => _buildMenuItem(
            context,
            controller,
            item,
            isExpanded,
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
    int level, // 菜单层级，0为顶级
  ) {
    return Obx(() {
      final isSelected = controller.selectedRoute.value == item.route;
      final isItemExpanded = controller.isItemExpanded(item.label);
      final theme = Theme.of(context);

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 菜单项本身
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isExpanded ? 8.w : 0, vertical: 2.h),
            child: Material(
              color: isSelected ? theme.colorScheme.primary.withOpacity(0.1) : Colors.transparent,
              borderRadius: BorderRadius.circular(8.r),
              child: InkWell(
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
                hoverColor: theme.colorScheme.primary.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8.r),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  height: 44.h,
                  padding: EdgeInsets.only(left: isExpanded ? (12 + (level * 16.0)).w : 12.w, right: isExpanded ? 4.w : 12.w),
                  child: ClipRect(
                    child: Row(
                      children: [
                        // 图标 - 收起时放大动画
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          child: Icon(
                            item.icon,
                            size: isExpanded ? 20.sp : 24.sp,
                            color: isSelected ? theme.colorScheme.primary : theme.iconTheme.color?.withOpacity(0.7),
                          ),
                        ),
                        // 标签 - 使用Opacity动画而不是直接隐藏
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: isExpanded ? 1.0 : 0.0,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                            width: isExpanded ? null : 0,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(width: isExpanded ? 12.w : 0),
                                // 标签文字
                                if (isExpanded)
                                  Flexible(
                                    child: Text(
                                      item.label,
                                      style: TextStyle(
                                        fontSize: 14.sp,
                                        color: isSelected ? theme.colorScheme.primary : theme.textTheme.bodyMedium?.color,
                                        fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                                      ),
                                      overflow: TextOverflow.clip,
                                      softWrap: false,
                                      maxLines: 1,
                                    ),
                                  ),
                                // 徽章
                                if (item.badge != null && isExpanded) ...[
                                  SizedBox(width: 4.w),
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 1.h),
                                    constraints: BoxConstraints(minWidth: 18.w, maxWidth: 36.w),
                                    decoration: BoxDecoration(color: theme.hintColor.withOpacity(0.15), borderRadius: BorderRadius.circular(9.r)),
                                    child: Text(
                                      '${item.badge}',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 10.sp, color: theme.hintColor),
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                                // 展开图标
                                if (item.hasChildren && isExpanded) ...[
                                  SizedBox(width: 2.w),
                                  SizedBox(
                                    width: 16.w,
                                    height: 16.h,
                                    child: AnimatedRotation(
                                      duration: const Duration(milliseconds: 200),
                                      turns: isItemExpanded ? 0.25 : 0,
                                      child: Icon(Icons.chevron_right, size: 14.sp, color: theme.iconTheme.color?.withOpacity(0.5)),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 子菜单 - 在收起状态下也可展开，使用Tooltip显示
          if (item.hasChildren)
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child: isItemExpanded
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: item.children!
                          .map(
                            (child) => isExpanded
                                ? _buildMenuItem(context, controller, child, isExpanded, level + 1)
                                : _buildCollapsedChildItem(context, controller, child),
                          )
                          .toList(),
                    )
                  : const SizedBox.shrink(),
            ),
        ],
      );
    });
  }

  /// 构建收起状态下的子菜单项
  Widget _buildCollapsedChildItem(BuildContext context, SidebarController controller, SidebarMenuItem item) {
    return Obx(() {
      final isSelected = controller.selectedRoute.value == item.route;
      final theme = Theme.of(context);

      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
        child: Tooltip(
          message: item.label,
          child: Material(
            color: isSelected ? theme.colorScheme.primary.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(8.r),
            child: InkWell(
              onTap: () {
                if (item.route != null) {
                  controller.selectItem(item.route);
                  Get.toNamed(item.route!);
                }
              },
              splashFactory: NoSplash.splashFactory,
              highlightColor: Colors.transparent,
              hoverColor: theme.colorScheme.primary.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8.r),
              child: Container(
                height: 38.h,
                alignment: Alignment.center,
                child: Icon(item.icon, size: 20.sp, color: isSelected ? theme.colorScheme.primary : theme.iconTheme.color?.withOpacity(0.6)),
              ),
            ),
          ),
        ),
      );
    });
  }
}
