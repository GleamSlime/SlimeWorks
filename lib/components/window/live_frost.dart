import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:slime_works/components/window/window_backdrop.dart';

/// 「实时半透明」的开关与抓帧服务。
///
/// 背景：这台机器的 Windows 26200 实测不给非 WinUI3 窗口渲染任何系统材质
/// （DWMWA_SYSTEMBACKDROP_TYPE、老 Accent 全部只回读成功、不绘制），磨砂只能
/// 自绘：把窗口短暂隐到 alpha=1 → 抓窗口所在屏幕区域 → 恢复窗口 → 在 Flutter
/// 里把这一帧缩小放大 + 高斯模糊当窗口底。关掉开关则整条链路停止，窗口退回
/// 不透明的 Dart 底色。
class LiveFrost {
  LiveFrost._();

  static const MethodChannel _channel =
      MethodChannel('slime_works/desktop_backdrop');

  static const String prefsKey = 'window_live_translucent';

  /// 抓帧缩放：1/4 分辨率足够模糊底用，解码和上传纹理都便宜。
  static const int _downscale = 4;

  /// 采集矩形比窗口向外扩的屏幕像素。高斯模糊会采到贴图边缘之外，边缘没邻域
  /// 数据就淡成白/半透明；多抓一圈真实桌面再在渲染时裁掉，白边就没了。取 sigma
  /// 的约 3 倍影响半径（5*3*downscale≈60）再留点余量。
  static const int _captureMargin = 72;

  /// 心跳间隔与「隐身→抓帧」之间给合成器留的时间。
  ///
  /// 抓帧必须把窗口短暂隐到 alpha=1，每次隐身都是一次可感知的闪。所以节奏是：
  /// 1 秒一跳、且只在「画面脏了」（窗口移动/缩放）时才真的抓——静止时完全零
  /// 闪烁，操作窗口时最多每秒闪一下。间隔不能再短，短了就是用户反馈的「一直闪」。
  /// grace 只保证合成器把隐身帧落下去再 BitBlt，一帧（16ms）足矣，越短闪得越轻。
  static const Duration _interval = Duration(seconds: 1);
  static const Duration _hideGrace = Duration(milliseconds: 16);

  static bool get supported => Platform.isWindows;

  /// 当前帧（窗口矩形的缩略屏幕图）。换帧时替换实例，配合
  /// [liveFrostActive] 一起被界面 Obx 取值。
  static ui.Image? frame;
  static final RxInt frameVersion = 0.obs;

  /// 当前帧里「窗口本体」所在的内区（图像像素坐标，已扣掉向外扩的那一圈）。
  /// 渲染时只把这块铺满视口，扩出去的那圈真实桌面被裁掉，边缘模糊才有邻域数据。
  static Rect frameInner = Rect.zero;


  /// 抓帧链路是否已启动（窗口可见且开关打开）。界面按它决定要不要留透明底。
  static final RxBool running = false.obs;

  static Timer? _timer;
  static bool _capturing = false;
  static bool _dragging = false;

  /// 上一次心跳采样到的窗口矩形，用来同时判断「窗口是否还在动」与「这一帧是不
  /// 是已经过时」。窗口一动，rect 就和上次的采样不同，据此置 [_rectMoved]。
  static Rect? _lastProbe;
  static bool _rectMoved = true;

  /// 最近一次成功抓帧所对应的窗口矩形。rect 与它相同说明底下的桌面没变，直接
  /// 跳过抓帧——静止时一次都不闪。
  static Rect? _capturedRect;

  static const Duration _settlePoll = Duration(milliseconds: 120);
  static const Duration _settleTimeout = Duration(milliseconds: 1500);

  /// 采样窗口矩形并判断是否已停稳：连续两次取值相同才算停。窗口还在动时返回
  /// false 并记下「动过」，让心跳下一跳再判，绝不抓移动中的瞬态矩形。
  static Future<bool> _settled() async {
    final Rect now = await windowManager.getBounds();
    final bool stable = _lastProbe == now;
    if (!stable) {
      _rectMoved = true;
    }
    _lastProbe = now;
    return stable;
  }

  /// 立即强制补抓一帧。启动归位后调用：程序化移动不会产生 WM_EXITSIZEMOVE、
  /// window_manager 的 onWindowMoved 也不触发，光靠事件永远等不到重抓。这里先
  /// 轮询到矩形停稳（宽高比/最小尺寸约束还会让窗口收敛若干帧），再强制抓一帧。
  static Future<void> refresh() async {
    if (!running.value) {
      return;
    }
    _capturedRect = null; // 作废「已抓」判定，逼 _tick 必抓
    _lastProbe = null;
    _rectMoved = true;
    Rect? prev;
    final DateTime deadline = DateTime.now().add(_settleTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final Rect now = await windowManager.getBounds();
      if (prev == now) {
        break;
      }
      prev = now;
      await Future<void>.delayed(_settlePoll);
    }
    await _tick();
  }

  static Future<bool> loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(prefsKey) ?? false;
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefsKey, enabled);
    await _sync(enabled);
  }

  /// 按偏好启动/停止抓帧。启动时窗口底色必须同步改成透明，否则磨砂层被
  /// 原生窗口底色整个盖住，看到的还是实心。
  ///
  /// 透明底色要再走一步 WindowsBackdrop.apply：window_manager 落底色用的是
  /// Accent TRANSPARENTGRADIENT，Win11 上它只会把窗口染成一层深色，正好糊住
  /// 自绘的磨砂帧；apply 内部会把 Accent 置回 DISABLED。
  static Future<void> _sync(bool enabled) async {
    if (!supported) {
      return;
    }
    if (enabled) {
      await windowManager.setBackgroundColor(Colors.transparent);
      await WindowsBackdrop.apply(BackdropKind.acrylic);
      _timer ??= Timer.periodic(_interval, (_) => _tick());
      running.value = true;
      unawaited(_tick());
    } else {
      _timer?.cancel();
      _timer = null;
      // 先摘材质把 applied 状态清干净，再落实心底色（window_manager 会重新挂
      // Accent）；顺序反了的话 windowsBackdropActive 残留，侧栏会压在实心底上
      // 半透成一片怪色。
      await WindowsBackdrop.apply(BackdropKind.none);
      await windowManager.setBackgroundColor(LightColors.background1);
      running.value = false;
      _disposeFrame();
    }
    _syncProvider();
  }

  /// 窗口隐藏/最小化时暂停抓帧：看不见的时候没必要闪给自己看。
  static void setPaused(bool paused) {
    if (!running.value) {
      return;
    }
    if (paused) {
      _timer?.cancel();
      _timer = null;
    } else {
      // 恢复可见：位置可能已变，作废「已抓」判定逼心跳按新矩形补抓一帧。
      _capturedRect = null;
      _lastProbe = null;
      _rectMoved = true;
      _timer ??= Timer.periodic(_interval, (_) => _tick());
      unawaited(_tick());
    }
  }

  /// 拖拽窗口期间完全停抓：跟手刷新意味着每秒十几次隐身，是灾难性的闪烁；
  /// 松手时把「已抓」判定作废，下一跳心跳就会按新位置补抓一帧。
  static void setDragging(bool dragging) {
    _dragging = dragging;
    if (!dragging) {
      _capturedRect = null;
      _lastProbe = null;
      _rectMoved = true;
    }
  }

  /// 启动时按已存偏好恢复（在 initManager 拼 WindowOptions 之前 await）。
  static Future<void> restore() async {
    if (!supported || !await loadPreference()) {
      return;
    }
    await _sync(true);
  }

  static Future<void> _tick() async {
    // 拖拽中或正在抓帧时直接跳过。
    if (_capturing || _dragging) {
      return;
    }
    // 心跳自查矩形是否变化，不再依赖 window_manager 的移动/缩放事件（实测这些
    // 事件在本机不触发，磨砂会永远停在启动那一帧的位置，窗口一动就错位、像放大）。
    // 矩形还在变（没停稳）时先不抓，避免抓到移动中的瞬态矩形。
    final bool stable = await _settled();
    if (!stable || !_rectMoved) {
      return;
    }
    // 矩形与上次成功抓帧时相同 → 底下的桌面没变，跳过，静止时一次都不闪。
    if (_capturedRect == _lastProbe) {
      return;
    }
    _capturing = true;
    bool hidden = false;
    try {
      await _channel.invokeMethod<int>(
          'setWindowBehindVisible', <String, Object?>{'on': true});
      hidden = true;
      await Future<void>.delayed(_hideGrace);
      final Map<Object?, Object?>? shot = await _channel.invokeMethod<
          Map<Object?, Object?>>('captureBehindWindow',
          <String, Object?>{'downscale': _downscale, 'margin': _captureMargin});
      if (shot == null) {
        return; // 抓失败保持 _rectMoved，下一跳再试
      }
      final int width = shot['width'] as int? ?? 0;
      final int height = shot['height'] as int? ?? 0;
      final Uint8List? bytes = shot['pixels'] as Uint8List?;
      if (width == 0 || height == 0 || bytes == null || bytes.isEmpty) {
        return;
      }
      // 四边外扩量（屏幕像素）换算到图像像素，得到窗口本体的内区。原生已把
      // 整块（含外扩圈）按 downscale 缩小，所以 pad 同比例除即可。
      final double pl = (shot['padLeft'] as int? ?? 0) / _downscale;
      final double pt = (shot['padTop'] as int? ?? 0) / _downscale;
      final double pr = (shot['padRight'] as int? ?? 0) / _downscale;
      final double pb = (shot['padBottom'] as int? ?? 0) / _downscale;
      final ui.Image image = await _decodeRgba(bytes, width, height);
      frameInner = Rect.fromLTRB(
          pl.clamp(0, width.toDouble()),
          pt.clamp(0, height.toDouble()),
          (width - pr).clamp(0, width.toDouble()),
          (height - pb).clamp(0, height.toDouble()));
      _disposeFrame();
      frame = image;
      // 记下这帧对应的窗口矩形（停稳时的采样），并清「动过」标记，直到窗口
      // 再次移动前不再重复抓帧。
      _capturedRect = _lastProbe;
      _rectMoved = false;
      frameVersion.value++;
    } on PlatformException catch (error) {
      debugPrint('[LiveFrost] 抓帧失败: $error');
    } finally {
      // 无论如何都要把窗口恢复可见，否则抓帧异常会把窗口永久留在 alpha=1
      // 的隐身态（比闪烁更严重的「窗口消失」）。
      if (hidden) {
        await _channel.invokeMethod<int>(
            'setWindowBehindVisible', <String, Object?>{'on': false});
      }
      _capturing = false;
    }
  }

  static Future<ui.Image> _decodeRgba(
      Uint8List bytes, int width, int height) {
    final Completer<ui.Image> completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(bytes, width, height, ui.PixelFormat.rgba8888,
        (ui.Image image) {
      completer.complete(image);
    });
    return completer.future;
  }

  static void _disposeFrame() {
    frame?.dispose();
    frame = null;
  }

  static void _syncProvider() {
    if (getIt.isRegistered<DesktopScreenProvider>()) {
      getIt<DesktopScreenProvider>().liveFrostActive.value = running.value;
    }
  }
}

/// 实时磨砂背景层：铺在窗口最底下，由 [LiveFrost] 的抓帧驱动。
///
/// 抓帧时采集矩形比窗口向外扩了一圈（[_captureMargin]），这里只把「窗口本体」
/// 那块内区拉伸铺满视口、把外扩圈裁掉——于是窗口边缘落在有真实邻域像素的位置，
/// 高斯模糊不会再淡成白边。1/4 缩采的方块感同样被这层模糊抹平，正是磨砂粒度。
class LiveFrostBackdrop extends StatelessWidget {
  const LiveFrostBackdrop({super.key});

  static Widget _layer(ui.Image? image, BoxConstraints constraints) {
    if (image == null || constraints.maxWidth <= 0) {
      return const SizedBox.shrink();
    }
    // 内区退化为空（还没抓到带 margin 的帧）时兜底整图拉伸，至少不空白。
    Rect inner = LiveFrost.frameInner;
    if (inner.width <= 0 || inner.height <= 0) {
      inner = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    }
    final double scaleX = constraints.maxWidth / inner.width;
    final double scaleY = constraints.maxHeight / inner.height;
    // 先按内区比例放大整图，再把内区左上角平移到视口原点；外扩圈落到视口外，
    // 由 Stack 的裁剪自然切掉（不能再套 ClipRect——ClipRect 会按子组件的固有
    // 尺寸即小图大小来裁，把放大后的磨砂整个裁没）。
    final Matrix4 matrix = Matrix4.identity()
      ..setEntry(0, 0, scaleX)
      ..setEntry(1, 1, scaleY)
      ..setEntry(0, 3, -inner.left * scaleX)
      ..setEntry(1, 3, -inner.top * scaleY);
    // 关键：用 SizedBox 把贴图钉在图像固有尺寸上。否则 Stack(fit: expand) 会把
    // RawImage 拉成视口大小，上面按「图像像素」算的裁剪矩阵就把整张图推到视口外
    // ——现象就是磨砂层什么都不画、窗口只剩透明底，看到背后清晰的桌面。
    return Transform(
      transform: matrix,
      alignment: Alignment.topLeft,
      // 变换作用在绘制阶段：模糊先按小图尺寸算（便宜），再随矩阵放大。
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: SizedBox(
          width: image.width.toDouble(),
          height: image.height.toDouble(),
          child: RawImage(image: image, fit: BoxFit.fill),
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final Color canvas = AppSemantic.of(context).canvas;
    // observable 必须在 Obx 自己的 builder 里读，且 Obx 不能一个都不读
    // （GetX 对空 Obx 直接渲染错误条），所以贴图与薄纱共用这一个 Obx。
    return Obx(() {
      LiveFrost.frameVersion.value;
      final ui.Image? image = LiveFrost.frame;
      return Stack(
        fit: StackFit.expand,
        children: [
          LayoutBuilder(
              builder: (context, constraints) => _layer(image, constraints)),
          // 一层薄纱：纯模糊帧对比度太高会抢正文的可读性；没帧时铺实底。
          ColoredBox(color: canvas.withAlpha(image == null ? 255 : 60)),
        ],
      );
    });
  }
}
