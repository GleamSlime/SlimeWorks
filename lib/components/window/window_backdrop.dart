import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_provider.dart';

/// 窗口背后能挂哪种系统材质。
enum BackdropKind {
  none('none'),
  mica('mica'),
  acrylic('acrylic');

  const BackdropKind(this.wireName);

  /// 和原生侧约定的取值。
  final String wireName;

  static BackdropKind fromWire(String? name) {
    return BackdropKind.values.firstWhere(
      (kind) => kind.wireName == name,
      orElse: () => BackdropKind.none,
    );
  }
}

/// Windows 系统背景材质（Mica / 压克力）的原生通道。
///
/// 原生实现见 `windows/runner/window_backdrop.cpp`。[applied] 是**原生回读过的
/// 真实结果**而不是“请求过”：材质没挂上时半透明只会压在一片黑上，这个坑在 macOS
/// 上已经踩过一次，所以界面侧必须以它为准。
///
/// 还剩一层只能靠真机肉眼判断的风险：[applied] 非 none 只说明 DWM 认了这个材质，
/// 材质画在顶层窗口上，而 Flutter 的内容渲染在它的一块**子窗口**里，子窗口的透明
/// 像素让不让材质透出来读不出来。一旦 Windows 上出现“侧栏发黑 / 完全不跟壁纸变色”，
/// 就是被子窗口挡住了，把 [kWindowsGlassEnabled] 改成 false 整体退回实心底，
/// 其余改动不受影响。
class WindowsBackdrop {
  WindowsBackdrop._();

  static const MethodChannel _channel =
      MethodChannel('slime_works/desktop_backdrop');

  /// 在 Windows 上启用系统材质磨砂。唯一需要动的开关，缘由见类注释。
  static const bool kWindowsGlassEnabled = true;

  static bool transparentEffectsEnabled = true;
  static bool publicBackdropSupported = false;
  static bool legacyMicaSupported = false;
  static int buildNumber = 0;

  /// 当前真正生效的材质。
  static BackdropKind applied = BackdropKind.none;

  /// 启动时探测一次能力并按 [requested] 挂上材质。
  ///
  /// 必须在 runApp 之前 await 完成：侧栏要不要画成半透明是同步取值的，
  /// 首帧就得按正确结论画，否则会先实心再闪成磨砂。
  static Future<void> probe({BackdropKind requested = BackdropKind.mica}) async {
    if (!Platform.isWindows || !kWindowsGlassEnabled) {
      return;
    }
    try {
      final Map<Object?, Object?>? capability =
          await _channel.invokeMethod<Map<Object?, Object?>>('getCapability');
      if (capability != null) {
        transparentEffectsEnabled =
            capability['transparentEffectsEnabled'] as bool? ?? true;
        publicBackdropSupported =
            capability['publicBackdropSupported'] as bool? ?? false;
        legacyMicaSupported = capability['legacyMicaSupported'] as bool? ?? false;
        buildNumber = capability['buildNumber'] as int? ?? 0;
      }
      await apply(requested);
    } on PlatformException catch (error) {
      // 探测失败只影响磨砂这一件事，退回实心底继续用。
      applied = BackdropKind.none;
      debugPrint('[WindowsBackdrop] 材质能力探测失败，退回实心底: $error');
    }
    _syncGlassFlag();
  }

  /// 切换材质，返回真正生效的那种（系统拒绝时为 [BackdropKind.none]）。
  static Future<BackdropKind> apply(BackdropKind requested) async {
    if (!Platform.isWindows || !kWindowsGlassEnabled) {
      applied = BackdropKind.none;
      return applied;
    }
    try {
      final String? name = await _channel
          .invokeMethod<String>('setBackdrop', requested.wireName);
      applied = BackdropKind.fromWire(name);
    } on PlatformException catch (error) {
      applied = BackdropKind.none;
      debugPrint('[WindowsBackdrop] 挂载材质 ${requested.wireName} 失败: $error');
    }
    _syncGlassFlag();
    return applied;
  }

  /// 按当前已生效的材质原样重挂一次。
  ///
  /// window_manager 落窗口底色时会用老 Accent 策略盖掉 DWM 材质，底色落地后
  /// 需要调这个把材质抢回来；从没挂上过（[applied] 为 none）就什么都不做。
  static Future<void> reapply() async {
    final kind = applied;
    if (kind == BackdropKind.none) {
      return;
    }
    await apply(kind);
  }

  /// 把结论同步给 provider：侧栏等组件都在 Obx 里取值，靠它才能当场重画。
  static void _syncGlassFlag() {
    if (getIt.isRegistered<DesktopScreenProvider>()) {
      getIt<DesktopScreenProvider>().windowsBackdropActive.value =
          applied != BackdropKind.none;
    }
  }
}

/// 界面到底能不能透出窗口背后的东西。
///
/// 这些判断原先散在各个组件里写 `Platform.isMacOS`，等于把“平台”当成了“能力”。
/// Windows 挂上 DWM 材质之后这个等号不成立，所以统一收到这里：一处决定、多处取值。
class WindowGlass {
  WindowGlass._();

  /// 侧栏那一栏能不能画成半透明。
  ///
  /// macOS 的 behindWindow 振动层由 MainFlutterWindow 直接挂好，必然可用；
  /// Windows 要看 DWM 到底认了没有。
  static bool get sidebar =>
      Platform.isMacOS || _windowsBackdropActive;

  /// 内容区（正文）能不能压半透明。
  ///
  /// 只有 macOS 可以：正文密度高，透明度已经收敛得很低（见 [_contentAlphaMacOS]）；
  /// Windows 这条链路还没在真机上验证过，正文保持实心。
  static bool get content => Platform.isMacOS;

  /// 内容区/页面底色的不透明度。
  ///
  /// 只有 macOS 有原生 behindWindow 振动层可以透；其它平台窗口本身不透明，留
  /// 半透明只会和窗口底色混色，拿不到磨砂。正文密度远高于侧栏，所以这里的值
  /// 比侧栏高（更实）：180 是实测下限，再降正文就开始跟着壁纸变色。
  static const int _contentAlphaMacOS = 180;

  /// 页面内分区面板（播放器头部、歌单侧栏这类）：色块比正文稀疏，可以再透一点。
  static const int _panelAlphaMacOS = 200;

  /// 浮层（菜单、对话框、底部抽屉）压在内容之上，几乎实心才不会和底下的字糊在一起。
  static const int _overlayAlpha = 242;

  static int get contentAlpha => content ? _contentAlphaMacOS : 255;

  static int get panelAlpha => content ? _panelAlphaMacOS : 255;

  /// 没有磨砂可透的平台就保持原来的实心浮层，别为了半透明牺牲可读性。
  static int get overlayAlpha => sidebar ? _overlayAlpha : 255;

  static bool get _windowsBackdropActive {
    if (!Platform.isWindows || !getIt.isRegistered<DesktopScreenProvider>()) {
      return false;
    }
    return getIt<DesktopScreenProvider>().windowsBackdropActive.value;
  }
}
