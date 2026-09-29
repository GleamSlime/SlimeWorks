import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/components/window/window_backdrop.dart';

/// 抓帧链路的日志出口：这条链路全程在平台通道和定时器里跑，出问题时界面上一句
/// 话都看不到，只能落到文件日志里查。
const Loggers _logger = Loggers(name: 'LiveFrost');

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

  /// 模糊半径，单位是**图像像素**（也就是缩小后的桌面像素）。10 个图像像素
  /// = 40 物理像素 = 32 逻辑像素，和界面里全局封面底（BackdropFilter sigma 30）
  /// 同一档，才像磨砂玻璃；取 5 只有 16 逻辑像素，桌面字形轮廓还认得出来，
  /// 用户看到的就是「把截图糊了一下」而不是磨砂。
  static const double _blurSigma = 10;

  /// 采集矩形比窗口向外扩的屏幕像素。高斯模糊会采到贴图边缘之外，边缘没邻域
  /// 数据就淡成白/半透明；多抓一圈真实桌面再在渲染时裁掉，白边就没了。取 sigma
  /// 的约 3 倍影响半径（10*3*downscale=120）再留点余量。
  static const int _captureMargin = 128;

  /// 心跳间隔与「隐身→抓帧」之间给合成器留的时间。
  ///
  /// 抓帧必须把窗口短暂隐到 alpha=1，每次隐身都是一次可感知的闪。所以节奏是：
  /// 心跳只问一次窗口矩形（一个 platform call，便宜），**矩形和上次成功抓帧时
  /// 一样就立刻返回**——静止时一次都不闪。间隔短只影响「多久发现窗口动了」，
  /// 不会增加闪烁，所以取 400ms：拖完窗口到磨砂跟上不超过半秒。
  /// grace 只保证合成器把隐身帧落下去再 BitBlt，一帧（16ms）足矣，越短闪得越轻。
  static const Duration _interval = Duration(milliseconds: 400);
  static const Duration _hideGrace = Duration(milliseconds: 16);

  static bool get supported => Platform.isWindows;

  /// 当前帧（已模糊的窗口区域桌面图）。换帧时替换实例，配合
  /// [liveFrostActive] 一起被界面 Obx 取值。
  static ui.Image? frame;
  static final RxInt frameVersion = 0.obs;

  /// 当前帧里「窗口本体」所在的内区（图像像素坐标，已扣掉向外扩的那一圈）。
  /// 渲染时按固定倍率把整图铺开，再把这个内区的左上角对齐视口原点；扩出去的
  /// 那一圈落在视口外被裁掉，只用来给边缘的模糊提供真实邻域数据。
  static Rect frameInner = Rect.zero;


  /// 抓帧链路是否已启动（窗口可见且开关打开）。界面按它决定要不要留透明底。
  static final RxBool running = false.obs;

  static Timer? _timer;

  /// 一次「等停稳 → 隐身 → 抓帧 → 恢复」的全过程。整段串行，心跳撞上来直接跳过。
  static bool _busy = false;

  /// 最近一次成功抓帧所对应的窗口矩形。心跳拿当前矩形和它比：相同说明窗口底下
  /// 的桌面没变，直接返回——静止时一次都不会闪。
  static Rect? _capturedRect;

  static const Duration _settlePoll = Duration(milliseconds: 120);
  static const Duration _settleTimeout = Duration(milliseconds: 1200);

  /// 轮询窗口矩形直到它停稳：连续两次取值相同才算停，返回停稳时的矩形。
  ///
  /// 窗口在动的时候抓，抓到的是移动中的瞬态矩形，画出来就是「磨砂跟窗口错位」；
  /// 而且最大化/贴边/恢复这类程序化动作还会让矩形在若干帧里收敛（最小尺寸与宽高
  /// 比约束），所以必须等它不动了再抓。超时仍在动就返回 null，交给下一跳心跳。
  static Future<Rect?> _waitSettled() async {
    Rect? prev;
    final DateTime deadline = DateTime.now().add(_settleTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final Rect now = await windowManager.getBounds();
      if (prev != null && prev == now) {
        return now;
      }
      prev = now;
      await Future<void>.delayed(_settlePoll);
    }
    return null;
  }

  /// 立即强制补抓一帧。启动归位后调用：程序化移动不会产生 WM_EXITSIZEMOVE、
  /// window_manager 的 onWindowMoved 也不触发，光靠事件永远等不到重抓。
  static Future<void> refresh() async {
    if (!running.value) {
      return;
    }
    _capturedRect = null; // 作废「已抓」判定，逼 _tick 必抓
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
      _timer ??= Timer.periodic(_interval, (_) => _tick());
      unawaited(_tick());
    }
  }

  /// 拖拽窗口期间不做任何特殊处理：不挂「拖拽中」标志，靠心跳发现矩形在变就不抓、
  /// 停下才补一帧。之前那种标志写法在这里必翻车——startDragging 把指针交给系统后
  /// Flutter 收不到 onPanEnd，标志永久卡在 true，磨砂从此再也不更新。

  /// 启动时按已存偏好恢复（在 initManager 拼 WindowOptions 之前 await）。
  static Future<void> restore() async {
    if (!supported || !await loadPreference()) {
      return;
    }
    await _sync(true);
  }

  static Future<void> _tick() async {
    // 上一轮「等停稳+抓帧」还没收尾时直接跳过（拖拽期间每跳都会撞进来，
    // 串行标志就是天然的「动个不停就不抓」闸门）。
    if (_busy || !running.value) {
      return;
    }
    // 心跳自己问矩形，不依赖 window_manager 的移动/缩放事件（实测这些事件在本机
    // 不触发，磨砂会永远停在启动那一帧的位置，窗口一动就错位、像放大）。
    final Rect now = await windowManager.getBounds();
    // 矩形和上次成功抓帧时一样 → 窗口底下的桌面没变，直接返回，静止时零闪烁。
    if (_capturedRect == now) {
      return;
    }
    _busy = true;
    bool hidden = false;
    try {
      // 窗口刚动过：先等它彻底停下再抓。抓移动中的瞬态矩形就是「磨砂错位」。
      final Rect? settled = await _waitSettled();
      if (settled == null) {
        return; // 还在动，交给下一跳心跳
      }
      await _channel.invokeMethod<int>(
          'setWindowBehindVisible', <String, Object?>{'on': true});
      hidden = true;
      await Future<void>.delayed(_hideGrace);
      final Map<Object?, Object?>? shot = await _channel.invokeMethod<
          Map<Object?, Object?>>('captureBehindWindow',
          <String, Object?>{'downscale': _downscale, 'margin': _captureMargin});
      if (shot == null) {
        return; // 抓失败保持「未抓」，下一跳再试
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
      _retireFrame();
      frame = await _blurred(image);
      // 记下这帧对应的窗口矩形，直到窗口再次移动前不再重复抓帧。
      _capturedRect = settled;
      frameVersion.value++;
    } on PlatformException catch (error) {
      // 抓帧失败不算致命：窗口下一跳会恢复可见，磨砂停在上一帧。
      _logger.error('实时磨砂抓帧失败: $error');
    } finally {
      // 无论如何都要把窗口恢复可见，否则抓帧异常会把窗口永久留在 alpha=1
      // 的隐身态（比闪烁更严重的「窗口消失」）。
      if (hidden) {
        await _channel.invokeMethod<int>(
            'setWindowBehindVisible', <String, Object?>{'on': false});
      }
      _busy = false;
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

  static Future<ui.Image> _blurred(ui.Image src) async {
    // 模糊在「图像像素」空间做一次就够：小图模糊便宜，而且 sigma 的含义和屏幕
    // 缩放、视口大小都无关，换窗口尺寸/换显示器都不会让磨砂粒度跟着变。
    // 之后渲染只负责按固定倍率放大贴图，放大用的双线性/三线性采样不会引入
    // 额外的高频，糊完的帧放大看依然是连续的磨砂。
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    final Paint paint = Paint()
      ..filterQuality = FilterQuality.high
      ..imageFilter = ui.ImageFilter.blur(
          sigmaX: _blurSigma, sigmaY: _blurSigma, tileMode: TileMode.decal);
    canvas.drawImage(src, Offset.zero, paint);
    final ui.Picture picture = recorder.endRecording();
    final ui.Image out = await picture.toImage(src.width, src.height);
    picture.dispose();
    src.dispose();
    return out;
  }

  /// 已经换下、但还不能立刻释放的帧。栅格化线程可能正拿着上一张纹理画，当场
  /// dispose 会让那次绘制踩到已释放的对象；抓帧最少隔 400ms（几十帧），所以
  /// 让旧帧在队列里压两代再释放，既不积压也不会有人还在画它。
  static final List<ui.Image> _retired = <ui.Image>[];

  static void _retireFrame() {
    final ui.Image? old = frame;
    frame = null;
    if (old != null) {
      _retired.add(old);
    }
    while (_retired.length > 2) {
      _retired.removeAt(0).dispose();
    }
  }

  static void _disposeFrame() {
    _retireFrame();
    // 关掉磨砂（窗口要落实心底色）：剩下的旧帧等下一帧再释放，
    // 此刻可能还有一帧正在合成，不能当场 dispose。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final ui.Image image in _retired) {
        image.dispose();
      }
      _retired.clear();
    });
  }

  static void _syncProvider() {
    if (getIt.isRegistered<DesktopScreenProvider>()) {
      getIt<DesktopScreenProvider>().liveFrostActive.value = running.value;
    }
  }
}

/// 实时磨砂背景层：铺在窗口最底下，由 [LiveFrost] 的抓帧驱动。
///
/// 抓帧时采集矩形比窗口向外扩了一圈，渲染时按「图像像素 × 缩小倍率 ÷ 屏幕缩放」
/// 这个固定倍率放大，并把内区左上角对齐视口原点——于是屏幕上的每一个逻辑像素
/// 画的就是它自己背后那块桌面，磨砂和桌面严格对齐；外扩圈落在视口外被裁掉，
/// 窗口边缘又有真实邻域像素可糊，不会淡成白边。1/4 缩采的方块感由这层模糊抹平，
/// 正是磨砂粒度。
/// 为什么用 CustomPaint 而不是 Stack+SizedBox 那套布局：外层是
/// `Positioned.fill` + `Stack(fit: StackFit.expand)`，传下去的是**紧约束**，
/// 而 SizedBox 只能把松约束压小、压不动紧约束（enforce 会把 695 抬回视口宽），
/// 于是图先被拉成视口大小（约 2.9 倍），矩阵再按 3.2 倍放大，实测磨砂整体
/// 放大了近 3 倍——正是「位置不对、而且像被放大的截图」。CustomPaint 不参与
/// 子件布局，直接在绘制期按算好的目标矩形贴图，几何由代码说了算。
class LiveFrostBackdrop extends StatelessWidget {
  const LiveFrostBackdrop({super.key});

  static Widget _layer(ui.Image? image, Size viewport, double devicePixelRatio) {
    if (viewport.width <= 0) {
      return const SizedBox.shrink();
    }
    // 图像像素 → 逻辑像素的倍率**必须是常数**（缩小倍率 ÷ 屏幕缩放），不能按视口
    // 宽去除以内区宽：窗口贴到屏幕边缘时采集矩形会被虚拟屏幕夹掉一边（原生如实
    // 回报 pad*），内区于是比窗口本体窄，按视口拉伸就等于把残缺的一帧横向放大
    // ——现象就是「磨砂位置不对而且被放大」，越靠边放大越厉害。
    final double scale = LiveFrost._downscale / devicePixelRatio;
    return CustomPaint(
      size: viewport,
      isComplex: true,
      painter: _FrostPainter(image, LiveFrost.frameInner, scale),
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
      return LayoutBuilder(
        builder: (context, constraints) => Stack(
          fit: StackFit.expand,
          children: [
            _layer(
                image, constraints.biggest, MediaQuery.devicePixelRatioOf(context)),
            // 一层薄纱：纯模糊帧对比度太高会抢正文的可读性；没帧时铺实底。
            // 这层就是「磨砂玻璃」本身，所以浓度要留得住桌面的色，又不能糊到看不见；
            // 内容区/面板那两层底已经为它让位（见 WindowGlass._contentAlphaLiveFrost），
            // 别在这里和那里同时压浓度，否则磨砂整个消失。
            ColoredBox(color: canvas.withAlpha(image == null ? 255 : 100)),
          ],
        ),
      );
    });
  }
}

/// 磨砂帧贴图：按固定倍率把整张（已模糊的）抓帧放大到逻辑像素，再把内区左上角
/// 平移到视口原点。外扩圈因此落在视口外，由画布自然裁掉。
class _FrostPainter extends CustomPainter {
  _FrostPainter(this._image, this._inner, this._scale);

  final ui.Image? _image;
  final Rect _inner;
  final double _scale;

  @override
  void paint(Canvas canvas, Size size) {
    final ui.Image? image = _image;
    if (image == null) {
      return;
    }
    // 内区退化为空（还没抓到带 margin 的帧）时兜底整图拉伸，至少不空白。
    final Rect inner = _inner.width > 0 && _inner.height > 0
        ? _inner
        : Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final double w = image.width.toDouble(), h = image.height.toDouble();
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, w, h),
      // 1 个图像像素 = downscale 个物理屏幕像素 = 1 个逻辑屏幕像素的倒数：
      // 这样画出来的每个像素正是它自己背后那块桌面，磨砂与桌面严格对齐。
      Rect.fromLTWH(-inner.left * _scale, -inner.top * _scale, w * _scale, h * _scale),
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  @override
  bool shouldRepaint(_FrostPainter oldDelegate) {
    return oldDelegate._image != _image ||
        oldDelegate._inner != _inner ||
        oldDelegate._scale != _scale;
  }
}
