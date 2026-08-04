part of '../app_routes.dart';

@TypedGoRoute<ImageToolsRoute>(path: '/image-tools')
class ImageToolsRoute extends GoRouteData with $ImageToolsRoute {
  const ImageToolsRoute();

  static const Permission routePermission = Permission.viewDashboard;
  Permission get permission => ImageToolsRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, AppRoutes.buildPlaceholder('图片工具'));
  }
}

@TypedGoRoute<ImageToolboxRoute>(path: '/image-toolbox')
class ImageToolboxRoute extends GoRouteData with $ImageToolboxRoute {
  const ImageToolboxRoute();

  static const Permission routePermission = Permission.viewDashboard;
  Permission get permission => ImageToolboxRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, AppRoutes.buildPlaceholder('图片工具盒'));
  }
}

@TypedGoRoute<MediaLibraryRoute>(path: '/media-library')
class MediaLibraryRoute extends GoRouteData with $MediaLibraryRoute {
  const MediaLibraryRoute();

  static const Permission routePermission = Permission.viewDashboard;
  Permission get permission => MediaLibraryRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const CollectionPictureScreen());
  }
}

@TypedGoRoute<SentryLogRoute>(path: '/sentry-log')
class SentryLogRoute extends AppRouteData with $SentryLogRoute {
  const SentryLogRoute();

  @override
  String get title => '日志';

  @override
  String get sidebarLabel => title;

  @override
  String get sidebarIcon => Assets.image.svg.menuLog;

  @override
  String get sidebarGroupId => 'tools';

  @override
  bool get desktopOnly => true;

  static const Permission routePermission = Permission.accessSentryLog;
  @override
  Permission get permission => SentryLogRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const SentryLogScreen());
  }
}

@TypedGoRoute<AliyunDdnsRoute>(path: '/aliyun')
class AliyunDdnsRoute extends AppRouteData with $AliyunDdnsRoute {
  const AliyunDdnsRoute();

  @override
  String get title => '阿里云';

  @override
  String get sidebarLabel => title;

  @override
  String get sidebarIcon => Assets.image.svg.menuAli;

  @override
  String get sidebarGroupId => 'tools';

  @override
  bool get desktopOnly => true;

  @override
  Widget? sidebarStatusWidget(BuildContext context) {
    try {
      final service = Get.find<AliyunDdnsService>();
      return Obx(() {
        final enabled = service.enabled.value;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final activeColor = isDark ? const Color(0xFF4CAF50) : LightColors.success;
        final color = enabled ? activeColor : Theme.of(context).hintColor.withAlpha(120);
        return Tooltip(
          message: enabled ? 'DDNS 运行中' : 'DDNS 已停止',
          child: Container(
            width: AppTheme.metrics.kSpace8,
            height: AppTheme.metrics.kSpace8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: color.withAlpha(80),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
          ),
        );
      });
    } catch (_) {
      return null;
    }
  }

  static const Permission routePermission = Permission.accessAliyunDdns;
  @override
  Permission get permission => AliyunDdnsRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const AliyunDdnsScreen());
  }
}

class ToolsRoute extends AppRouteData with $ToolsRoute {
  const ToolsRoute();

  @override
  String get title => '工具';

  @override
  String get sidebarLabel => title;

  @override
  String get sidebarIcon => Assets.image.svg.menuTools;

  @override
  String get sidebarGroupId => 'tools';

  @override
  bool get desktopOnly => true;

  static const Permission routePermission = Permission.accessTools;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const ToolsScreen());
  }
}

@TypedGoRoute<NcmDecryptRoute>(path: '/ncm-decrypt')
class NcmDecryptRoute extends AppRouteData with $NcmDecryptRoute {
  const NcmDecryptRoute();

  @override
  String get title => 'NCM解密';

  @override
  String get sidebarLabel => title;

  @override
  String get sidebarIcon => Assets.image.svg.menuTools;

  @override
  String get sidebarGroupId => 'tools';

  @override
  bool get desktopOnly => true;

  static const Permission routePermission = Permission.accessTools;
  @override
  Permission get permission => NcmDecryptRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const NcmDecryptScreen());
  }
}

@TypedGoRoute<PowerStatsRoute>(path: '/power-stats')
class PowerStatsRoute extends AppRouteData with $PowerStatsRoute {
  const PowerStatsRoute();

  @override
  String get title => '电力统计';

  @override
  String get sidebarLabel => title;

  @override
  String get sidebarIcon => Assets.image.svg.menuBill;

  @override
  String get sidebarGroupId => 'tools';

  @override
  bool get desktopOnly => false;

  static const Permission routePermission = Permission.accessPowerStats;
  @override
  Permission get permission => PowerStatsRoute.routePermission;

  @override
  Widget? sidebarStatusWidget(BuildContext context) {
    try {
      if (!GetIt.instance.isRegistered<PowerStatsService>()) return null;
      final service = GetIt.instance.get<PowerStatsService>();
      return Obx(() {
        final enabled = service.enabled.value;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final activeColor = isDark ? const Color(0xFFF5A569) : LightColors.orange;
        final color = enabled ? activeColor : Theme.of(context).hintColor.withAlpha(120);
        return Tooltip(
          message: enabled ? '电力统计运行中' : '电力统计已停止',
          child: Container(
            width: AppTheme.metrics.kSpace8,
            height: AppTheme.metrics.kSpace8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: color.withAlpha(80),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
          ),
        );
      });
    } catch (_) {
      return null;
    }
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const PowerStatsScreen());
  }
}
