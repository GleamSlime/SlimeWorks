import 'dart:io';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/buttons/stroke_icon_button.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/icons/stroke_zone.dart';
import 'package:slime_works/components/window/screen_top_bar.dart';
import 'package:slime_works/components/window/sidebar_resize_handle.dart';
import 'package:slime_works/components/window/window_backdrop.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:slime_works/core/routes/role_manager.dart';
import 'package:slime_works/core/services/app_info_service.dart';
import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/core/widgets/tree_connector.dart';

/// 子项行高：`TreeConnector` 要按它算每枝的中心线，必须是确定值
double get _kChildRowHeight => AppTheme.metrics.kSpace40;

/// 侧栏行图标的描边时长
///
/// 缺省的 `AppMotion.slow` 压在 22 设计像素的图标上一闪而过，笔顺根本走不完一遍，
/// hover 那一下读起来像抖了一下而不是"这行被指到了"。提到 emphasis 档才看得清。
const Duration _kRowStrokeDuration = AppMotion.emphasis;

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

  // 隐藏态：整条栏不占宽度，只剩内容区左缘那根指示条
  final RxBool isHidden = false.obs;

  // 进"默认隐藏页"之前的显示状态（展开/收起），离开时按它恢复
  bool _lastVisibleExpanded = isDesktop;
  bool _routeForcedHidden = false;

  // 侧边栏扩展内容是否显示
  final RxBool showExtends = true.obs;

  // 当前选中的菜单路由
  final RxString selectedRoute = ''.obs;

  // 各个菜单项的展开状态 (使用label作为key)
  final RxMap<String, bool> expandedItems = <String, bool>{}.obs;

  // 各分组的折叠状态 (使用group.id作为key，true=折叠)
  final RxMap<String, bool> collapsedGroups = <String, bool>{}.obs;

  // ── 展开态宽度（可拖拽）──
  // 存的是设计稿像素，渲染时仍走 scaleW，窄窗自动收缩的行为不变。
  static const double kDefaultExpandedWidth = 240;
  static const double kMinExpandedWidth = 160;
  static const double kMaxExpandedWidth = 420;

  /// 侧栏宽度动画时长：文字揭示要等它跑完，两处必须共用同一个值
  static const Duration kWidthAnimation = AppMotion.slow;

  static const String _prefExpandedWidth = 'sidebar.expandedWidth';

  final RxDouble expandedWidth = kDefaultExpandedWidth.obs;

  // 拖拽中：宽度动画要关掉，否则容器慢半拍、缝追不上手指
  final RxBool resizing = false.obs;

  @override
  void onInit() {
    super.onInit();
    _loadExpandedWidth();
  }

  Future<void> _loadExpandedWidth() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(_prefExpandedWidth);
    if (saved != null && saved >= kMinExpandedWidth && saved <= kMaxExpandedWidth) {
      expandedWidth.value = saved;
    }
  }

  Future<void> _saveExpandedWidth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefExpandedWidth, expandedWidth.value);
  }

  void beginResize() {
    resizing.value = true;
    if (!isExpanded.value) _beginFollow();
  }

  // ── 收起/隐藏态起拖：跟手展开 ──
  // 过去往右拖一下等于点了展开，整条栏"啪"地弹到全宽，和手上的位移对不上。
  // 现在拖拽期间栏宽直接跟着指针走：拖过图标条宽当场离开隐藏态，拖回它以下
  // 当场进隐藏态；拖过最小展开宽文字就地出现；松手按进度决定展开还是弹回。
  static const double kCollapsedWidth = 75;
  final RxBool following = false.obs;
  final RxDouble followWidth = 0.0.obs;

  void _beginFollow() {
    following.value = true;
    followWidth.value = isHidden.value ? 0 : kCollapsedWidth;
  }

  /// [deltaLogical] 是指针的横向位移（逻辑像素），这里换算回设计稿像素
  void resizeBy(double deltaLogical) {
    final ratio = scaleW(100) / 100;
    if (!isExpanded.value) {
      if (!following.value) _beginFollow();
      followWidth.value = (followWidth.value + deltaLogical / ratio).clamp(
        0.0,
        kMaxExpandedWidth,
      );
      _syncHiddenWithFollowWidth();
      return;
    }
    final next = (expandedWidth.value + deltaLogical / ratio).clamp(
      kMinExpandedWidth,
      kMaxExpandedWidth,
    );
    if (next <= kMinExpandedWidth) {
      _collapseByResize();
      return;
    }
    expandedWidth.value = next;
  }

  /// 隐藏态跟着拖拽宽度就地翻转，不等松手：
  /// 拖过图标条宽等于把栏拉回可见态，拖回图标条宽以下直接进隐藏态——
  /// 手上的位移和栏的状态始终一一对应。
  void _syncHiddenWithFollowWidth() {
    if (isHidden.value) {
      if (followWidth.value >= kCollapsedWidth) {
        _routeForcedHidden = false;
        isHidden.value = false;
      }
    } else if (followWidth.value < kCollapsedWidth) {
      hideSidebar();
    }
  }

  void endResize() {
    resizing.value = false;
    if (following.value) {
      following.value = false;
      // 过半才认：拖到最小展开宽的六成算"要展开"，往回弹是手滑
      if (followWidth.value >= kMinExpandedWidth * 0.6) {
        // 落点宽直接接手跟手宽：松手瞬间不许跳
        expandedWidth.value = followWidth.value.clamp(
          kMinExpandedWidth,
          kMaxExpandedWidth,
        );
        _routeForcedHidden = false;
        isHidden.value = false;
        openSidebar();
        _saveExpandedWidth();
      }
      return;
    }
    _saveExpandedWidth();
  }

  /// 拖到最窄就自动收成图标条
  ///
  /// 宽度同时回到默认值：肯一路拖到最窄的人是想要它收起来，不是想要一条
  /// 160 的窄栏，下次展开给他一条正常的。
  void _collapseByResize() {
    // 收这一刻要把动画打开，否则整条侧栏是瞬间弹没而不是收起来
    resizing.value = false;
    expandedWidth.value = kDefaultExpandedWidth;
    toggleSidebar();
    _saveExpandedWidth();
  }

  // 是否已初始化为移动端模式
  bool _initializedMobile = false;

  /// 切换侧边栏展开/收起状态
  void toggleSidebar() async {
    isExpanded.value = !isExpanded.value;

    if (isExpanded.value) {
      await Future.delayed(SidebarController.kWidthAnimation);
      showExtends.value = true;
    } else {
      showExtends.value = false;
    }
  }

  void openSidebar() async {
    if (!isExpanded.value) {
      isExpanded.value = true;
      await Future.delayed(SidebarController.kWidthAnimation);
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

  /// 进入隐藏态：整条栏收到 0 宽，只剩内容区左缘的指示条
  void hideSidebar() {
    if (isHidden.value) return;
    // 路由强制隐藏时不许覆盖记忆：_routeForcedHidden 置位就是"已经记过了"
    if (!_routeForcedHidden) _lastVisibleExpanded = isExpanded.value;
    showExtends.value = false;
    isExpanded.value = false;
    isHidden.value = true;
  }

  /// 退出隐藏态，回到之前记着的显示状态
  void _revealSidebar({bool? expanded}) {
    if (!isHidden.value) return;
    isHidden.value = false;
    if (expanded ?? _lastVisibleExpanded) {
      openSidebar();
    }
  }

  /// 指示条的三态循环：展开 → 收起 → 隐藏 → 展开
  void cycleVisibility() {
    if (isHidden.value) {
      _routeForcedHidden = false;
      _revealSidebar(expanded: true);
    } else if (isExpanded.value) {
      toggleSidebar();
    } else {
      _routeForcedHidden = false;
      hideSidebar();
    }
  }

  /// 路由切换时对齐显示状态：默认隐藏页强制隐藏，回到普通页恢复进页前的状态。
  /// 用户在普通页手动隐藏的意图不被恢复——只有"页面逼的"才在离开时还原。
  void applyVisibilityForPath(String path, {required bool defaultHidden}) {
    if (defaultHidden) {
      if (!isHidden.value) {
        _lastVisibleExpanded = isExpanded.value;
        _routeForcedHidden = true;
        hideSidebar();
      }
    } else if (_routeForcedHidden && isHidden.value) {
      _routeForcedHidden = false;
      _revealSidebar();
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

/// 挂在内容区左缘的侧栏把手
///
/// 放在内容区而不是侧栏里：Row 里后画的盖先画的，把手贴在侧栏右缘上会被
/// 内容区吃掉半截，缩回侧栏内侧又会被那条滚动条压住——两边都不干净，
/// 只有内容区这一侧是没人挡的。
class SidebarResizeStrip extends StatelessWidget {
  const SidebarResizeStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<SidebarController>();
    return Obx(
      () => SidebarResizeHandle(
        collapsed: !controller.isExpanded.value,
        onDragStart: controller.beginResize,
        onDragUpdate: controller.resizeBy,
        onDragEnd: controller.endResize,
        // 箭头只沿"可见"这根轴走一格：展开 ↔ 收起，隐藏态点它 = 展开。
        // 从收起再往"看不见"走一格交给悬停时浮出的闭眼图标——过去点一下
        // 箭头三态连跳，收起态点完直接消失，看着像侧栏丢了。
        onToggle: () {
          if (controller.isHidden.value) {
            controller.cycleVisibility(); // 隐藏 → 展开
          } else {
            controller.toggleSidebar(); // 展开 ↔ 收起
          }
        },
        onHide: !controller.isExpanded.value && !controller.isHidden.value
            ? controller.hideSidebar
            : null,
      ),
    );
  }
}

/// 可收起的侧边栏组件
class CollapsibleSidebar extends StatefulWidget {
  final List<SidebarGroup> groups;
  // 展开态宽度不在此处：它是用户可改的持久状态，归 SidebarController 管
  final double collapsedWidth;
  final Duration animationDuration;

  const CollapsibleSidebar({
    super.key,
    required this.groups,
    this.collapsedWidth = SidebarController.kCollapsedWidth,
    this.animationDuration = SidebarController.kWidthAnimation,
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
    _entranceController = AnimationController(vsync: this, duration: AppMotion.entrance);
    _entranceAnimation = CurvedAnimation(parent: _entranceController, curve: Curves.easeOutCubic);
    Future.delayed(AppMotion.base, () {
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
    final s = AppSemantic.of(context);

    return Obx(() {
      final isExpanded = controller.isExpanded.value;
      final showExtends = controller.showExtends.value;
      final resizing = controller.resizing.value;
      final isHidden = controller.isHidden.value;
      // 侧栏不该吃掉整个窗口：窄窗时按窗口宽度设上限
      final maxWidth = math.min(
        scaleW(SidebarController.kMaxExpandedWidth),
        MediaQuery.sizeOf(context).width * 0.45,
      );
      final expandedPx = math.min(scaleW(controller.expandedWidth.value), maxWidth);
      // 跟手展开中：宽度就是指针拖出来的那个数，不掺动画
      final following = controller.following.value;
      final targetWidth = following
          ? math.min(scaleW(controller.followWidth.value), maxWidth)
          : isHidden
          ? 0.0
          : (isExpanded ? expandedPx : scaleW(widget.collapsedWidth));
      // 隐藏态必须清 padding/边框/子内容：0 宽里塞 6 的 padding 和 1 的描边
      // 会留一条幽灵发丝线。跟手拉出来之后这些又要回来，所以分开判。
      final chromeHidden = isHidden && !following;
      // 拖过最小展开宽（也就是往回拖会自动收起的那条线）：栏里的文字当场就该
      // 出来，而不是等松手才补齐
      final followExpanded =
          following &&
          !isExpanded &&
          controller.followWidth.value >= SidebarController.kMinExpandedWidth;

      if (desktopScreen.isMobile.value) {
        if (!controller._initializedMobile) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            controller.initMobileMode();
          });
        }

        final targetWidth = MediaQuery.of(context).size.width / 2;

        return MobileSidebar(
          controller: controller,
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
      final isDark = s.isDark;

      return FadeTransition(
        opacity: _entranceAnimation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-0.15, 0),
            end: Offset.zero,
          ).animate(_entranceAnimation),
          child: AnimatedContainer(
            // 跟手期间动画必须关掉，否则容器慢半拍、缝追不上手指
            duration: resizing || following ? Duration.zero : widget.animationDuration,
            curve: AppMotion.standard,
            width: targetWidth,
            // 侧栏贴住窗口左/上/下边缘，圆角交给 macOS 的窗口蒙版去裁（实测内容
            // 层确实会被裁），这样两个圆角天然一致。原来的 margin+radius12 浮卡
            // 比窗口角（实测半径约 19pt）更方，两条弧在角上会分叉露出底下的振动层。
            padding: chromeHidden
                ? EdgeInsets.zero
                : EdgeInsets.only(
                    left: AppTheme.metrics.kSpace6,
                    top: AppTheme.metrics.kSpace6,
                    bottom: AppTheme.metrics.kSpace6,
                  ),
            decoration: BoxDecoration(
              // 这里原来还写了 color: colorScheme.surface，但 BoxDecoration 里
              // gradient 会盖掉 color，那行是不生效的，删掉免得误以为侧栏必须是不透明。
              // 原来还有一圈 boxShadow：贴边之后阴影左侧被窗口裁掉、右侧被同一行
              // 里后画的内容区盖住，已经完全不可见，所以删掉。
              gradient: AppTheme.sideBarTheme(
                context,
                // macOS 下留透明度，让原生 behindWindow 振动层透出来形成磨砂；
                // 其它平台没有这一层，保持实心否则直接透出桌面。
                // 165 实测会把振动层的背景细节压平（侧栏 sd 0.36，且完全不跟壁纸
                // 变色），降到 120 后侧栏底色会随壁纸走暖，透出感才成立。
                // 深浅色不对称：浅色玻璃压在亮壁纸上对比余量大，深色玻璃压在亮
                // 壁纸上会被提亮到中灰、浅色字只剩 2.8:1，所以深色主题取值更高。
                alpha: globalBackgroundPath.isNotEmpty
                    ? 100
                    : (WindowGlass.sidebar ? (isDark ? 175 : 120) : 255),
              ),
              // 只剩右侧一条发丝分隔线：四周描边在贴边布局下会被窗口蒙版裁掉半截
              // 线宽固定 1，不吃窗口缩放——缩放后不足 1 物理像素会被抗锯齿冲淡。
              border: chromeHidden
                  ? null
                  : Border(right: BorderSide(color: s.glassBorder)),
            ),
            child: chromeHidden
                ? const SizedBox.shrink()
                : _buildFittedContent(
                    context,
                    controller,
                    isExpanded: isExpanded || followExpanded,
                    showExtends: showExtends || followExpanded,
                    transient: following || isHidden,
                  ),
          ),
        ),
      );
    });
  }

  /// 侧栏内容的排版宽度下限：不足就按下限排版再用 ClipRect 裁出可见的一截。
  /// 拖拽拉出和宽度动画的中间帧都会路过"比内容固有宽更窄"的宽度，直接按
  /// 真实宽排版就是满屏 RenderFlex overflowed；窄时只露左半截、拖宽自然全
  /// 露出来。静止态不掺和：收起态图标条按自身宽度自然排版，中轴才不会挪。
  Widget _buildFittedContent(
    BuildContext context,
    SidebarController controller, {
    required bool isExpanded,
    required bool showExtends,
    required bool transient,
  }) {
    // 6 的左 padding 要一并扣掉：容器给内容的真实宽就是栏宽减它，
    // 下限按"栏宽"算会在刚好贴合的那一刻误判成窄、白白裁一刀。
    final floorPx = isExpanded
        ? scaleW(SidebarController.kMinExpandedWidth) - AppTheme.metrics.kSpace6
        : transient
        ? scaleW(widget.collapsedWidth) - AppTheme.metrics.kSpace6
        : null;
    final content = _buildSidebarContent(context, controller, isExpanded, showExtends);
    if (floorPx == null) {
      return content;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= floorPx) {
          return content;
        }
        final height = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height;
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: floorPx,
            maxWidth: floorPx,
            minHeight: height,
            maxHeight: height,
            child: content,
          ),
        );
      },
    );
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

  /// 构建侧边栏头部：产品身份位 + 折叠开关
  ///
  /// 展开态是一条 Row（字标在左、把手在右）；收起态只剩把手一枚，居中放，
  /// 和上面的窗口灯、下面的图标条对齐到同一条中轴。
  /// 展开↔收起之间不换 Column/Row 结构，整条头部才不会重排。
  Widget _buildHeader(BuildContext context, SidebarController controller, bool isExpanded) {
    if (desktopScreen.isMobile.value) {
      return const SizedBox.shrink();
    }

    final m = AppTheme.metrics;

    return AnimatedContainer(
      duration: widget.animationDuration,
      curve: AppMotion.standard,
      padding: EdgeInsets.symmetric(
        horizontal: m.kSpace8,
        vertical: m.kSpace8,
      ),
      child: Row(
        // 收起态把把手和上面的灯、下面的图标条对齐到同一条中轴；展开态才是"字标在左、把手在右"
        mainAxisAlignment: isExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
        children: [
          // 图标条只有 75 设计像素，装不下产品身份位：收起态直接不画，
          // 而不是缩成一枚挤在把手旁边
          if (isExpanded) const _SidebarLogo(),
          if (isExpanded) Expanded(child: SizedBox(width: m.kSpace4)),
          StrokeIconButton(
            // 展开/收起是同一支笔换字形：旧的擦回去、新的描出来，比硬切更能读出"栏宽变了"
            isExpanded ? StrokeIcons.assetSidebarOpen : StrokeIcons.assetSidebarClose,
            size: scaleW(22),
            onTap: controller.toggleSidebar,
            color: Theme.of(context).iconTheme.color,
            semanticLabel: isExpanded ? '收起侧栏' : '展开侧栏',
          ),
        ],
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
            color: AppSemantic.of(context).hairline,
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(vertical: AppTheme.metrics.kSpace8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: bottomGroup.items
                .map(
                  (item) => _buildMenuItem(context, controller, item, isExpanded, showExtends),
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
    final s = AppSemantic.of(context);

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
                          color: s.textTertiary,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: isCollapsed ? -0.25 : 0,
                      duration: AppMotion.base,
                      curve: AppMotion.standard,
                      child: DrawIcon(
                        StrokeIcons.expandMore,
                        size: AppTheme.metrics.iconSize14,
                        color: s.textTertiary,
                        trigger: StrokeTrigger.appear,
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
              child: Divider(height: 1, thickness: scaleW(0.5), color: s.hairline),
            ),

          AnimatedSize(
            duration: AppMotion.base,
            curve: AppMotion.standard,
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
  ) {
    return Obx(() {
      final isSelected = controller.selectedRoute.value == item.route.location;
      final isItemExpanded = controller.isItemExpanded(item.route.title);
      final s = AppSemantic.of(context);

      return Container(
        decoration: isExpanded
            ? null
            : BoxDecoration(
                color: isItemExpanded ? s.surfaceHover : Colors.transparent,
                border: isItemExpanded ? Border.all(width: 1, color: s.hairline) : null,
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
                onTap: () {
                  if (item.hasChildren) {
                    return controller.toggleItemExpanded(item.route.title);
                  }
                  _navigateAndMaybeClose(controller, item.route.location);
                },
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // 展开箭头在行的**右端**，不在行首：行首那一格是图标和
                    // 选中指示条的位置，再塞一个箭头会先撞车，读起来也像两列。
                    if (isExpanded && item.hasChildren)
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: AnimatedRotation(
                            duration: AppMotion.base,
                            curve: AppMotion.standard,
                            // 收合时 ›、展开时 ⌄。和分组标题那枚箭头是同一个图形，
                            // 用整支箭头（带杆）会读成"往下跳"而不是"这一组有子项"。
                            turns: isItemExpanded ? 0 : -0.25,
                            child: DrawIcon(
                              StrokeIcons.expandMore,
                              size: AppTheme.metrics.fontSize13,
                              color: s.textTertiary,
                              trigger: StrokeTrigger.appear,
                            ),
                          ),
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        if (item.route.sidebarIcon != null)
                          isExpanded
                              ? AnimatedContainer(
                                  duration: AppMotion.base,
                                  curve: AppMotion.standard,
                                  padding: EdgeInsets.all(AppTheme.metrics.kSpace4),
                                  decoration: BoxDecoration(
                                    color: isSelected ? s.accentContainer : Colors.transparent,
                                    borderRadius: AppTheme.metrics.radius8,
                                  ),
                                  child: DrawIcon(
                                    item.route.sidebarIcon!,
                                    size: AppTheme.metrics.fontSize18,
                                    color: isSelected ? s.accent : s.textPrimary,
                                    duration: _kRowStrokeDuration,
                                  ),
                                )
                              : Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    AnimatedContainer(
                                      duration: AppMotion.base,
                                      curve: AppMotion.standard,
                                      // 内边距只到 kSpace4：这一格横向只余 32 设计像素，
                                      // 图标 22 再加两侧各 6 就已经撑破
                                      padding: EdgeInsets.all(AppTheme.metrics.kSpace4),
                                      decoration: BoxDecoration(
                                        color: isSelected && isExpanded
                                            ? s.accentContainer
                                            : Colors.transparent,
                                        borderRadius: AppTheme.metrics.radius8,
                                      ),
                                      child: DrawIcon(
                                        item.route.sidebarIcon!,
                                        // 图标必须和这条栏同一个缩放族：fontSize22 走的是
                                        // 字号族，还要再乘用户调的字号比例——栏宽不动、
                                        // 图标跟着字体长，比例不是 1 就把这一行顶破
                                        size: scaleW(22),
                                        color: isSelected ? s.accent : s.textTertiary,
                                        duration: _kRowStrokeDuration,
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
                              duration: AppMotion.base,
                              curve: AppMotion.standard,
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
                                          color: isSelected ? s.accentText : s.textPrimary,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        softWrap: false,
                                        maxLines: 1,
                                      ),
                                    ),
                                    if (item.route.sidebarBadgeCount != null)
                                      _trailing(
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
                                                ? s.accentContainer
                                                : s.surfaceHover,
                                            borderRadius: AppTheme.metrics.radius8,
                                          ),
                                          child: Text(
                                            item.route.sidebarBadgeCount.toString(),
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: AppTheme.metrics.fontSize9,
                                              fontWeight: FontWeight.w600,
                                              color: isSelected
                                                  ? s.accentText
                                                  : s.textSecondary,
                                            ),
                                            maxLines: 1,
                                          ),
                                        ),
                                      ),
                                    if (item.route.sidebarBadgeWidget(context) != null)
                                      _trailing(
                                        Padding(
                                          padding: EdgeInsets.only(
                                            left: AppTheme.metrics.kSpace4,
                                          ),
                                          child: item.route.sidebarBadgeWidget(context)!,
                                        ),
                                      ),
                                    if (item.route.sidebarStatusWidget(context) != null)
                                      _trailing(
                                        Padding(
                                          padding: EdgeInsets.only(
                                            left: AppTheme.metrics.kSpace4,
                                          ),
                                          child: item.route.sidebarStatusWidget(context)!,
                                        ),
                                      ),
                                    // 给行末的展开箭头让出横向空间，否则长标签会钻到箭头底下
                                    if (item.hasChildren)
                                      SizedBox(width: AppTheme.metrics.kSpace20),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            if (item.hasChildren)
              AnimatedSize(
                duration: AppMotion.base,
                curve: AppMotion.standard,
                alignment: Alignment.topCenter,
                child: !isItemExpanded
                    ? const SizedBox.shrink()
                    : isExpanded && showExtends
                    ? TreeConnector(
                        // 竖干在父项图标下方起，横枝把每个子项接到竖干上：
                        // 一族的关系靠线成立，不靠缩进猜。
                        childCount: item.children!.length,
                        rowHeight: _kChildRowHeight,
                        spacing: AppTheme.metrics.kSpace2,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          spacing: AppTheme.metrics.kSpace2,
                          children: [
                            for (final child in item.children!)
                              _SidebarChildItem(
                                item: child,
                                selected:
                                    controller.selectedRoute.value == child.route.location,
                                onTap: () => _navigateAndMaybeClose(
                                  controller,
                                  child.route.location,
                                ),
                              ),
                            SizedBox(height: AppTheme.metrics.kSpace4),
                          ],
                        ),
                      )
                    : Column(
                        // 图标条太窄，画不出竖干；子项仍逐条排在父项下面
                        mainAxisSize: MainAxisSize.min,
                        spacing: AppTheme.metrics.kSpace4,
                        children: [
                          for (final child in item.children!)
                            _buildCollapsedChildItem(context, controller, child),
                          SizedBox(height: AppTheme.metrics.kSpace4),
                        ],
                      ),
              ),
          ],
        ),
      );
    });
  }

  /// 行尾那簇附加内容（计数徽章 / 状态点 / 版本字）
  ///
  /// 它们内部全是字号族，字号比例拉到 2 倍时固有宽度能吃完整行宽，而这一行的宽
  /// 只由侧栏宽决定——族不同就压不动。统一钉在宽度族的上限里再裁：宁可截一段，
  /// 不许顶破。
  Widget _trailing(Widget child) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: AppTheme.metrics.kSpace56),
      child: ClipRect(child: child),
    );
  }

  /// 构建收起状态下的子菜单项
  Widget _buildCollapsedChildItem(
    BuildContext context,
    SidebarController controller,
    SidebarMenuItem item,
  ) {
    return Obx(() {
      final isSelected = controller.selectedRoute.value == item.route.location;
      final s = AppSemantic.of(context);

      return Material(
        color: Colors.transparent,
        child: StrokeZone(
          // 整行都是命中区，点在文字上也该让图标描一次
          child: InkWell(
            onTap: () {
              _navigateAndMaybeClose(controller, item.route.location);
            },
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            borderRadius: AppTheme.metrics.radius12,
            hoverColor: s.surfaceHover,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: AppTheme.metrics.kSpace12,
                vertical: AppTheme.metrics.kSpace10,
              ),
              decoration: BoxDecoration(
                borderRadius: AppTheme.metrics.radius12,
                color: isSelected ? s.accentContainer : Colors.transparent,
              ),
              child: Tooltip(
                message: item.route.sidebarLabel,
                child: DrawIcon(
                  item.route.sidebarIcon!,
                  size: scaleW(22),
                  color: isSelected ? s.accent : null,
                  // auto：悬停进这一格和按下都描一次，事件源是包住整行的 StrokeZone
                  trigger: StrokeTrigger.auto,
                  duration: _kRowStrokeDuration,
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// 侧栏顶部的产品身份位（仅展开态构建，收起态整枚不画）
///
/// 展开态内部不重排：图标是同一个元素，字标只是宽度收放。
/// 点它等于回概览——侧栏是导航，产品名是它的根。
///
/// 标记不吃 SvgPicture：几何由生成器直接从那张 svg 资产裁成 [StrokeIcons.brandMark]，
/// 所以栏展开那一下能一笔一笔描出来，而不是整枚换透明度淡入。
class _SidebarLogo extends StatelessWidget {
  const _SidebarLogo();

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);
    final controller = Get.find<SidebarController>();

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          controller.selectItem(const DashboardRoute().location);
          goRouter.go(const DashboardRoute().location);
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 宽度族：图标条只有 75 设计像素，跟着字号长的图标会把它顶穿。
            // 笔宽 0.9（24 空间口径）：原资产是 40 空间里 0.5~1 的发丝线，换算过来
            // 只有 0.3~0.6，压到 22 像素上会被抗锯齿冲淡；但再粗过 1 就把四个
            // 空心节点填成实心饼，等于回到原来那团黑
            DrawIcon(
              StrokeIcons.brandMark,
              size: scaleW(22),
              weight: 0.9,
              color: s.textPrimary,
              // 45 条笔画按弧长顺序描，缺省的 AppMotion.slow 会糊成一团闪，
              // 按入场档给足时间。栏展开时它是新挂载的，appear 正好描这一下。
              trigger: StrokeTrigger.appear,
              duration: AppMotion.entrance,
              semanticLabel: AppInfoService.appName,
            ),
            AnimatedSize(
              duration: SidebarController.kWidthAnimation,
              curve: AppMotion.standard,
              alignment: Alignment.centerLeft,
              child: Obx(
                () => controller.isExpanded.value && controller.showExtends.value
                    ? Padding(
                        padding: EdgeInsets.only(left: m.kSpace8),
                        child: Text(
                          AppInfoService.appName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: m.fontSize14,
                            fontWeight: FontWeight.w600,
                            color: s.textPrimary,
                            letterSpacing: 0.2,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 展开后的子项
///
/// 和顶层项差两件事：**不抬白卡、不出指示条**。一族里只允许一个抬升主体，
/// 否则连接线和白卡会打架——到底是这行被选中，还是这一族被选中，读不出来。
/// 子项的反馈只有水洗 + 文字升色，够用了。
class _SidebarChildItem extends StatefulWidget {
  const _SidebarChildItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final SidebarMenuItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SidebarChildItem> createState() => _SidebarChildItemState();
}

class _SidebarChildItemState extends State<_SidebarChildItem> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);
    final icon = widget.item.route.sidebarIcon;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: StrokeZone(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedContainer(
            duration: AppMotion.fast,
            curve: AppMotion.standard,
            height: _kChildRowHeight,
            padding: EdgeInsets.symmetric(horizontal: m.kSpace6),
            decoration: BoxDecoration(
              color: _pressed
                  ? s.surfaceActive
                  : _hovered
                  ? s.surfaceHover
                  : Colors.transparent,
              borderRadius: m.radiusControl,
            ),
            child: Row(
              spacing: m.kSpace8,
              children: [
                if (icon != null)
                  DrawIcon(
                    icon,
                    // 宽度族：这一行不吃用户字号比例，理由和图标条一样
                    size: scaleW(16),
                    color: widget.selected ? s.accent : s.textSecondary,
                    trigger: StrokeTrigger.auto,
                    duration: _kRowStrokeDuration,
                  ),
                Expanded(
                  child: Text(
                    widget.item.route.sidebarLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: m.fontSize13,
                      fontWeight: widget.selected ? FontWeight.w500 : FontWeight.w400,
                      color: widget.selected ? s.textPrimary : s.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 侧边栏菜单项按钮（带选中指示条 + 悬停发光效果）
class _SidebarMenuItemButton extends StatefulWidget {
  final bool isSelected;
  final bool isExpanded;
  final VoidCallback onTap;
  final Widget child;

  const _SidebarMenuItemButton({
    required this.isSelected,
    required this.isExpanded,
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
    final s = AppSemantic.of(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      // 悬停到哪一行就描那一行的图标：事件源套在整行上，点在文字上也算这一行
      child: StrokeZone(
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: AppMotion.base,
            curve: AppMotion.standard,
            height: m.kSpace44,
            padding: EdgeInsets.symmetric(horizontal: m.kSpace4),
            decoration: BoxDecoration(
              // 选中项不再染一层品牌色，而是抬起成一张白卡：侧栏底就是画布色，
              // 白卡 + 1px 描边 + 一层极轻投影本身就是它的选中态。
              color: widget.isSelected
                  ? s.surface
                  : _hovered
                  ? s.surfaceHover
                  : Colors.transparent,
              borderRadius: m.radiusControl,
              // 只有选中项描边：每行都套一个框的话，一列看下去全是格子，
              // 抬升关系反而读不出来；悬停有水洗，未选中不需要常驻描边。
              border: widget.isSelected
                  ? Border.all(color: s.accentContainerBorder)
                  : null,
              boxShadow: [
                if (widget.isSelected) ...s.elevation(Elevation.raised),
              ],
            ),
            child: Row(
              spacing: m.kSpace8,
              children: [
                if (widget.isExpanded)
                  AnimatedContainer(
                    duration: AppMotion.base,
                    curve: AppMotion.standard,
                    width: scaleW(3),
                    height: widget.isSelected ? m.kSpace20 : 0,
                    decoration: BoxDecoration(
                      color: widget.isSelected ? s.accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(scaleW(2)),
                    ),
                  ),
                Expanded(child: widget.child),
              ],
            ),
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
    _controller = AnimationController(vsync: this, duration: AppMotion.emphasis);
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    final delay = AppMotion.slow + AppMotion.entranceGap * widget.index;
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
  final double targetWidth;
  final Duration animationDuration;
  final bool isExpanded;
  final bool showExtends;
  final Widget Function(BuildContext) buildContent;
  final bool? isMobile;

  const MobileSidebar({
    super.key,
    required this.controller,
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
    final s = AppSemantic.of(context);
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
                    duration: _isDragging ? Duration.zero : AppMotion.slow,
                    curve: AppMotion.standard,
                    color: s.scrim.withAlpha(((255 * maskOpacity) * 0.45).toInt()),
                  ),
                ),
              ),

            AnimatedPositioned(
              duration: _isDragging ? Duration.zero : widget.animationDuration,
              curve: AppMotion.standard,
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
                    // 这里不写 color：下一行的 gradient 会盖掉它，写了也不生效。
                    boxShadow: widget.isMobile != true
                        ? [
                            BoxShadow(
                              color: s.shadowKey.withAlpha(40),
                              blurRadius: AppTheme.metrics.kSpace24,
                              offset: Offset(AppTheme.metrics.kSpace2, 0),
                            ),
                            BoxShadow(
                              color: AppBrand.soft.withAlpha(12),
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
