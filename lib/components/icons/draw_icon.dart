import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme/app_motion.dart';
import '../../core/theme/app_semantics.dart';
import '../../core/theme/app_theme.dart';
import 'stroke_geometry.dart';
import 'stroke_zone.dart';

/// 描边动画的触发口径。
enum StrokeTrigger {
  /// 出现时播一次；若有 [StrokeZone] 祖先则按下/悬停再重播，没有则由图标自身
  /// 捕获按下。绝大多数调用点不用显式写。
  auto,

  /// 只在出现时播一次，不响应点击/悬停：密集列表、装饰性图标用它，避免满屏乱闪。
  appear,

  /// 只在按下时重播（首次出现仍会播，否则没点过的按钮会是一片空白）。
  press,

  /// 按下与悬停都重播。
  hover,

  /// 进度由 [DrawIcon.controller] 外部驱动：滚动进度、级联、录制时长等。
  manual,

  /// 完全静态，直接画完成态。
  none,
}

/// 描边动画的效果模式。
enum StrokeEffect {
  /// 沿弧长顺序描出来（默认）
  draw,

  /// 描的同时把模糊收敛掉：比纯描边更"浮现"，用于入场与强调
  blur,

  /// 画完后有一段高光沿笔画持续流动，用来表示"正在进行"
  flow,
}

/// 外部进度驱动器（配合 [StrokeTrigger.manual]）。
class StrokeController extends ChangeNotifier {
  StrokeController([this._progress = 0.0]);

  double _progress;
  double get progress => _progress;

  set progress(double value) {
    final clamped = value.clamp(0.0, 1.0);
    if (clamped == _progress) return;
    _progress = clamped;
    notifyListeners();
  }
}

/// 描边图标：Tabler outline 几何 + 笔画动画，取代 `Icon(Icons.*)` 与自绘 svg 资产。
///
/// 与 [Icon] 的替换关系：`size` / `color` 的缺省值同样取自 ambient [IconTheme]，
/// 所以从 `Icon` 直接换过来外观不变，差别只在会动。
///
/// 触发口径见 [StrokeTrigger]，缺省 [StrokeTrigger.auto]：可点击的在按下时重播，
/// 不可点击的在出现时播一次。
class DrawIcon extends StatefulWidget {
  const DrawIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.weight,
    this.trigger,
    this.effect = StrokeEffect.draw,
    this.duration,
    this.curve,
    this.controller,
    this.semanticLabel,
  });

  final StrokeIcon icon;

  /// 缺省跟随 [IconTheme]，与 `Icon` 一致
  final double? size;
  final Color? color;

  /// 24 空间下的描边宽度（Tabler 原图口径是 2）
  final double? weight;

  final StrokeTrigger? trigger;
  final StrokeEffect effect;

  /// 缺省 [AppMotion.slow]：再短看不出笔顺，再长就跟不上手
  final Duration? duration;
  final Curve? curve;

  /// [StrokeTrigger.manual] 时必填
  final StrokeController? controller;

  final String? semanticLabel;

  @override
  State<DrawIcon> createState() => _DrawIconState();
}

class _DrawIconState extends State<DrawIcon>
    with TickerProviderStateMixin {
  // 必须在 build 之前就有了：AnimatedBuilder 订阅的 Listenable 是 build 时快照，
  // 之后才把 controller 造出来的话订阅的是空列表，进度再涨也不会重画。
  late final AnimationController _draw = AnimationController(
    vsync: this,
    duration: _duration,
  );
  AnimationController? _flow;
  StrokeSignal? _zone;
  int _lastPulse = 0;
  bool _firstPass = true;

  /// 切换图标时留下的上一张几何，配合"旧的擦回去 + 新的描出来"过渡
  StrokeGeometry? _outgoing;

  StrokeTrigger get _trigger => widget.trigger ?? StrokeTrigger.auto;

  Duration get _duration => widget.duration ?? AppMotion.slow;

  Curve get _curve => widget.curve ?? AppMotion.standard;

  bool get _reducedMotion => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// 是否静态满画：关闭动效、显式 none、manual 由外部管进度
  bool get _staticOnly =>
      _reducedMotion || _trigger == StrokeTrigger.none;

  @override
  void dispose() {
    _zone?.removeListener(_onZonePulse);
    _draw.dispose();
    _flow?.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final zone = StrokeZone.maybeOf(context);
    if (zone != _zone) {
      _zone?.removeListener(_onZonePulse);
      _zone = zone;
      zone?.addListener(_onZonePulse);
      _lastPulse = zone?.pulse ?? 0;
    }
    if (_firstPass) {
      _firstPass = false;
      // 首帧后起播：initState 里拿不到 MediaQuery / InheritedWidget
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _playsOnAppear) replay();
      });
    }
    _syncFlowLoop();
  }

  bool get _playsOnAppear => switch (_trigger) {
        StrokeTrigger.auto ||
        StrokeTrigger.appear ||
        StrokeTrigger.press ||
        StrokeTrigger.hover =>
          true,
        StrokeTrigger.manual || StrokeTrigger.none => false,
      };

  @override
  void didUpdateWidget(DrawIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.effect != widget.effect) _syncFlowLoop();
    if (oldWidget.icon != widget.icon) {
      // 换图标：把旧几何留着擦回去，比硬切更能说明"状态变了"
      if (!_staticOnly) _outgoing = geometryOf(oldWidget.icon);
      if (_playsOnAppear) replay();
    } else if (oldWidget.trigger != widget.trigger && _playsOnAppear) {
      replay();
    }
  }

  /// flow 是无限循环的，单独一个 controller，不能混进一次性描边时长
  void _syncFlowLoop() {
    if (widget.effect != StrokeEffect.flow || _reducedMotion) {
      _flow?.stop();
      return;
    }
    _flow ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _flow!
      ..duration = _duration * 4
      ..value = 0
      ..repeat();
  }

  void _onZonePulse() {
    final zone = _zone;
    if (zone == null || zone.pulse == _lastPulse) return;
    _lastPulse = zone.pulse;
    if (zone.lastFromHover && _trigger == StrokeTrigger.press) return;
    if (_trigger == StrokeTrigger.appear ||
        _trigger == StrokeTrigger.manual ||
        _trigger == StrokeTrigger.none) {
      return;
    }
    replay();
  }

  /// 指针正下方落在图标上时重播，不依赖外层有没有包 StrokeZone
  void _onSelfPointerDown(PointerDownEvent event) {
    if (_zone != null) return; // 有事件源时交给事件源，避免一次按下播两下
    if (_trigger != StrokeTrigger.auto && _trigger != StrokeTrigger.press) {
      return;
    }
    replay();
  }

  /// 重播一次描边
  void replay() {
    if (_staticOnly) {
      setState(() => _outgoing = null);
      return;
    }
    _draw
      ..duration = _duration
      ..forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final size = widget.size ?? iconTheme.size ?? AppTheme.metrics.iconSize24;
    final semantic = AppSemantic.of(context);
    final base = widget.color ?? iconTheme.color ?? semantic.textSecondary;
    final color = iconTheme.opacity == null
        ? base
        : base.withValues(alpha: base.a * iconTheme.opacity!);
    final manual = _trigger == StrokeTrigger.manual;

    // 每帧都要重新造 CustomPaint：把 painter 建在 build 里、让 builder 返回那个
    // 固定实例的话，AnimatedBuilder 只会重复挂同一份 widget，进度永远停在第一帧
    Widget paint() {
      final progress = _staticOnly
          ? 1.0
          : manual
              ? (widget.controller?.progress ?? 0.0)
              : _curve.transform(_draw.value);
      return CustomPaint(
        size: Size.square(size),
        painter: _StrokePainter(
          geometry: geometryOf(widget.icon),
          progress: progress,
          outgoing: _outgoing,
          color: color,
          weight: widget.weight ?? 2.0,
          effect: widget.effect,
          flowProgress: _flow?.value ?? 0.0,
          done: () => _outgoing = null,
        ),
      );
    }

    // 每一层的 child 都用各自的名字：Dart 闭包按变量引用捕获，写成
    // `child = AnimatedBuilder(builder: (_, _) => child)` 的话 builder 读到的是
    // 最后一次赋值，等于把 AnimatedBuilder 塞进自己当 child，挂载时无限递归。
    Widget child = AnimatedBuilder(
      animation: Listenable.merge([
        _draw,
        ?_flow,
        if (manual) ?widget.controller,
      ]),
      builder: (context, _) => paint(),
    );

    child = Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onSelfPointerDown,
      child: child,
    );

    if (widget.semanticLabel != null) {
      child = Semantics(label: widget.semanticLabel, child: child);
    }
    return SizedBox(width: size, height: size, child: child);
  }
}

class _StrokePainter extends CustomPainter {
  _StrokePainter({
    required this.geometry,
    required this.progress,
    required this.outgoing,
    required this.color,
    required this.weight,
    required this.effect,
    required this.flowProgress,
    required this.done,
  });

  final StrokeGeometry geometry;
  final double progress;
  final StrokeGeometry? outgoing;
  final Color color;
  final double weight;
  final StrokeEffect effect;
  final double flowProgress;
  final VoidCallback done;

  /// 测试与调试用：当前描边进度
  @visibleForTesting
  double get debugProgress => progress;

  @override
  void paint(Canvas canvas, Size size) {
    final reverse = outgoing;
    if (reverse != null && progress < 1) {
      // 旧的从尾部擦回，新的同时描出，读起来像同一支笔在换字形
      _paintIcon(canvas, reverse, 1 - progress, size, erase: true);
    } else if (reverse != null) {
      done();
    }
    _paintIcon(canvas, geometry, progress, size);
  }

  void _paintIcon(
    Canvas canvas,
    StrokeGeometry geometry,
    double progress,
    Size size, {
    bool erase = false,
  }) {
    // 缩放按各自几何的坐标系走：24 的 Tabler 和 40 的品牌标记能在同一张画布上
    // 叠着擦/描，换图标过渡才不会跳一下
    canvas.save();
    canvas.scale(size.width / geometry.viewBox);
    // weight 的口径固定在 24 空间，所以换到别的坐标系要跟着放大，
    // 否则同一支笔在 40 空间里会细 1.7 倍
    final strokeWidth = weight * geometry.viewBox / 24;
    final locals = strokeProgressFor(geometry, progress);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = strokeWidth
      // flow 模式下本体压暗成"轨道"，高光段才走得出来；同亮度画是看不出流动的
      ..color = !erase && effect == StrokeEffect.flow
          ? color.withValues(alpha: color.a * 0.42)
          : color;
    if (!erase && effect == StrokeEffect.blur && progress < 1) {
      stroke.maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        (1 - progress) * weight * 1.6,
      );
    }

    for (var i = 0; i < geometry.paths.length; i++) {
      final path = geometry.paths[i];
      final local = locals[i];
      if (geometry.solid[i]) {
        // 实心小块没有中心线可描，只能跟着进度淡入
        canvas.drawPath(
          path,
          Paint()
            ..color = color.withValues(alpha: color.a * local)
            ..style = PaintingStyle.fill,
        );
        continue;
      }
      if (local <= 0) continue;
      if (local >= 1 && (erase || effect != StrokeEffect.flow)) {
        canvas.drawPath(path, stroke);
        continue;
      }
      canvas.drawPath(_trimmed(geometry, i, local, erase), stroke);
    }

    if (!erase && effect == StrokeEffect.flow && progress >= 1) {
      _paintFlow(canvas, geometry, stroke);
    }
    canvas.restore();
  }

  ui.Path _trimmed(
    StrokeGeometry geometry,
    int index,
    double local,
    bool fromTail,
  ) {
    final out = ui.Path();
    for (final metric in geometry.metrics[index]) {
      final end = metric.length * local;
      final start = fromTail ? metric.length - end : 0.0;
      out.addPath(metric.extractPath(start, end), Offset.zero);
    }
    return out;
  }

  /// 沿笔画移动的高光窗：跨笔画时窗口首尾相接，绕一圈连续走
  void _paintFlow(Canvas canvas, StrokeGeometry geometry, Paint stroke) {
    final total = geometry.totalLength;
    if (total <= 0) return;
    final window = total * 0.22;
    final head = flowProgress * (total + window) - window;
    final flowStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      // 跟着本体笔宽走：坐标系已经不是 24 了，再取 weight 会细一档
      ..strokeWidth = stroke.strokeWidth
      // 高光段比本体重一点，才读得出"在流"
      ..color = color.withValues(alpha: color.a.clamp(0.35, 1.0));
    var walked = 0.0;
    for (var i = 0; i < geometry.metrics.length; i++) {
      final length = geometry.lengths[i];
      final start = walked;
      walked += length;
      if (length <= 0) continue;
      final from = (head - start).clamp(0.0, length);
      final to = (head + window - start).clamp(0.0, length);
      if (to - from <= 0) continue;
      for (final metric in geometry.metrics[i]) {
        final s = from / length * metric.length;
        final e = to / length * metric.length;
        if (e - s <= 0) continue;
        canvas.drawPath(metric.extractPath(s, e), flowStroke);
      }
    }
  }

  @override
  bool shouldRepaint(_StrokePainter old) =>
      old.geometry != geometry ||
      old.outgoing != outgoing ||
      old.progress != progress ||
      old.color != color ||
      old.weight != weight ||
      old.effect != effect ||
      old.flowProgress != flowProgress;
}
