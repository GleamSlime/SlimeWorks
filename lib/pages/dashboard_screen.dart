import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/services/system_metrics_service.dart';
import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/src/rust/api/system_metrics.dart' as rust_sys;
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_viz.dart';

/// 概览页面
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with TickerProviderStateMixin {
  Timer? _uiRefreshTimer;
  final SystemMetricsService _metricsService = getIt<SystemMetricsService>();

  late final AnimationController _entranceController;
  late final List<Animation<double>> _cardAnimations;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: AppMotion.cascade,
    );

    _cardAnimations = List.generate(11, (index) {
      final start = (index * 0.06).clamp(0.0, 0.7);
      return CurvedAnimation(
        parent: _entranceController,
        curve: Interval(
          start,
          (start + 0.3).clamp(0.0, 1.0),
          curve: AppMotion.decelerate,
        ),
      );
    });

    // 定时从 Service 拉取最新数据以刷新 UI
    _uiRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    Future.delayed(AppMotion.fast, () {
      if (mounted) _entranceController.forward();
    });
  }

  @override
  void dispose() {
    _uiRefreshTimer?.cancel();
    _entranceController.dispose();
    super.dispose();
  }

  String _formatMemory(rust_sys.SystemResourceSnapshot snapshot) {
    return '${snapshot.memoryUsedMb} MB';
  }

  String _formatSpeed(double kbps) {
    if (kbps >= 1024) {
      return '${(kbps / 1024).toStringAsFixed(2)} MB/s';
    }
    return '${kbps.toStringAsFixed(0)} KB/s';
  }

  @override
  Widget build(BuildContext context) {
    return ScreenChrome(
      data: const ScreenChromeData(title: '概览'),
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.symmetric(
                horizontal: AppTheme.metrics.kSpace20,
                vertical: AppTheme.metrics.kSpace16,
              ),
              sliver: SliverToBoxAdapter(child: _buildHeader(context)),
            ),
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace20),
              sliver: SliverToBoxAdapter(child: _buildMetricSection(context)),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                AppTheme.metrics.kSpace20,
                AppTheme.metrics.kSpace24,
                AppTheme.metrics.kSpace20,
                AppTheme.metrics.kSpace24,
              ),
              sliver: SliverToBoxAdapter(child: _buildSectionLabel(context, '功能模块')),
            ),
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace20),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate((context, index) {
                  return _buildFeatureItem(context, index);
                }, childCount: 6),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 320,
                  mainAxisSpacing: AppTheme.metrics.kSpace16,
                  crossAxisSpacing: AppTheme.metrics.kSpace16,
                  mainAxisExtent: scaleW(200).clamp(160.0, 260.0),
                ),
              ),
            ),
            SliverToBoxAdapter(child: SizedBox(height: AppTheme.metrics.kSpace40)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final s = AppSemantic.of(context);
    final anim = _cardAnimations[0];
    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) {
        return Opacity(
          opacity: anim.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, scaleW(20) * (1 - anim.value)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: AppTheme.metrics.kSpace12),
                // 标题不再做渐变：主色换成近黑之后渐变两端同色，ShaderMask 只剩
                // 一层无意义的蒙版开销，直接落到主文字色。
                Text(
                  '工坊系统',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: s.textPrimary,
                    fontSize: scaleS(32),
                  ),
                ),
                SizedBox(height: AppTheme.metrics.kSpace6),
                // 中文不做正向字距：拉丁字母拉开是排版惯例，CJK 拉开只会散。
                Text(
                  '实时监控 · 模块管理 · 一站式工具',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: s.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionLabel(BuildContext context, String label) {
    final s = AppSemantic.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: AppTheme.metrics.kSpace12),
      child: Row(
        children: [
          Container(
            width: scaleW(3),
            height: scaleW(16),
            decoration: BoxDecoration(
              color: s.accent,
              borderRadius: BorderRadius.circular(scaleW(2)),
            ),
          ),
          SizedBox(width: AppTheme.metrics.kSpace8),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricSection(BuildContext context) {
    final viz = AppVizSet.of(context);
    final snapshot = _metricsService.lastSnapshot;

    String fmtPercent(List<double> h) {
      if (h.isEmpty) return '--';
      return '${h.reduce(math.max).toStringAsFixed(1)}%';
    }

    String fmtPercentVal(List<double> h) {
      if (h.isEmpty) return '--';
      return '${h.reduce(math.min).toStringAsFixed(1)}%';
    }

    String fmtPercentAvg(List<double> h) {
      if (h.isEmpty) return '--';
      return '${(h.reduce((a, b) => a + b) / h.length).toStringAsFixed(1)}%';
    }

    String fmtSpeedVal(double kbps) {
      if (kbps >= 1024) return '${(kbps / 1024).toStringAsFixed(2)} MB/s';
      return '${kbps.toStringAsFixed(0)} KB/s';
    }

    String fmtSpeedPeak(List<double> h) {
      if (h.isEmpty) return '--';
      return fmtSpeedVal(h.reduce(math.max));
    }

    String fmtSpeedValley(List<double> h) {
      if (h.isEmpty) return '--';
      return fmtSpeedVal(h.reduce(math.min));
    }

    String fmtSpeedAvg(List<double> h) {
      if (h.isEmpty) return '--';
      return fmtSpeedVal(h.reduce((a, b) => a + b) / h.length);
    }

    String fmtMemVal(double mb) {
      if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(2)} GB';
      return '${mb.toStringAsFixed(0)} MB';
    }

    String fmtMemPeak(List<double> h) {
      if (h.isEmpty) return '--';
      return fmtMemVal(h.reduce(math.max));
    }

    String fmtMemValley(List<double> h) {
      if (h.isEmpty) return '--';
      return fmtMemVal(h.reduce(math.min));
    }

    String fmtMemAvg(List<double> h) {
      if (h.isEmpty) return '--';
      return fmtMemVal(h.reduce((a, b) => a + b) / h.length);
    }

    final metrics = [
      _MetricData(
        icon: StrokeIcons.memory,
        title: 'CPU',
        value: snapshot == null ? '--' : '${snapshot.cpuUsagePercent.toStringAsFixed(1)}%',
        history: List<double>.from(_metricsService.cpuHistory),
        viz: viz.sky,
        peak: fmtPercent(_metricsService.cpuHistory),
        valley: fmtPercentVal(_metricsService.cpuHistory),
        average: fmtPercentAvg(_metricsService.cpuHistory),
      ),
      _MetricData(
        icon: StrokeIcons.storage,
        title: '内存',
        value: snapshot == null ? '--' : _formatMemory(snapshot),
        history: List<double>.from(_metricsService.memHistory),
        viz: viz.amber,
        peak: fmtMemPeak(_metricsService.memHistory),
        valley: fmtMemValley(_metricsService.memHistory),
        average: fmtMemAvg(_metricsService.memHistory),
      ),
      _MetricData(
        icon: StrokeIcons.download,
        title: '下行',
        value: snapshot == null ? '--' : _formatSpeed(_metricsService.appRxKbps),
        history: List<double>.from(_metricsService.rxHistory),
        viz: viz.mint,
        peak: fmtSpeedPeak(_metricsService.rxHistory),
        valley: fmtSpeedValley(_metricsService.rxHistory),
        average: fmtSpeedAvg(_metricsService.rxHistory),
      ),
      _MetricData(
        icon: StrokeIcons.upload,
        title: '上行',
        value: snapshot == null ? '--' : _formatSpeed(_metricsService.appTxKbps),
        history: List<double>.from(_metricsService.txHistory),
        viz: viz.lilac,
        peak: fmtSpeedPeak(_metricsService.txHistory),
        valley: fmtSpeedValley(_metricsService.txHistory),
        average: fmtSpeedAvg(_metricsService.txHistory),
      ),
    ];

    if (_metricsService.isLocalServerRunning) {
      metrics.add(
        _MetricData(
          icon: StrokeIcons.hub,
          title: '节点请求',
          value: _metricsService.nodeRequestCount.toString(),
          history: List<double>.from(_metricsService.reqHistory),
          viz: viz.sea,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = AppTheme.metrics.kSpace12;
        final cardWidth = ((constraints.maxWidth - spacing) / 2).clamp(100.0, 300.0);

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (int i = 0; i < metrics.length; i++)
              _buildMetricCard(context, metrics[i], i, cardWidth),
          ],
        );
      },
    );
  }

  Widget _buildMetricCard(
    BuildContext context,
    _MetricData data,
    int animIndex,
    double cardWidth,
  ) {
    final anim = _cardAnimations[(animIndex + 1).clamp(0, _cardAnimations.length - 1)];

    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) {
        return Opacity(
          opacity: anim.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, scaleW(16) * (1 - anim.value)),
            child: _MetricCardWidget(width: cardWidth, data: data),
          ),
        );
      },
    );
  }

  Widget _buildFeatureItem(BuildContext context, int index) {
    final viz = AppVizSet.of(context);
    final features = [
      _FeatureData(
        icon: StrokeIcons.accountTree,
        title: '数据捕获',
        description: '强大的数据采集和处理功能',
        viz: viz.sky,
      ),
      _FeatureData(
        icon: StrokeIcons.waterDrop,
        title: '流水账',
        description: '清晰的财务流水记录',
        viz: viz.lagoon,
      ),
      _FeatureData(
        icon: StrokeIcons.cloud,
        title: '阿里云',
        description: '云服务管理工具',
        viz: viz.amber,
      ),
      _FeatureData(
        icon: StrokeIcons.buildCircle,
        title: '工具箱',
        description: '丰富的实用工具集合',
        viz: viz.lilac,
      ),
      _FeatureData(
        icon: StrokeIcons.videoLibrary,
        title: '媒体库',
        description: '媒体文件管理中心',
        viz: viz.coral,
      ),
      _FeatureData(
        icon: StrokeIcons.note,
        title: '笔记',
        description: '快速记录和整理想法',
        viz: viz.mint,
      ),
    ];

    final feature = features[index];
    final anim = _cardAnimations[(index + 5).clamp(0, _cardAnimations.length - 1)];

    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) {
        return Opacity(
          opacity: anim.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, scaleW(20) * (1 - anim.value)),
            child: _FeatureCardWidget(feature: feature),
          ),
        );
      },
    );
  }
}

class _MetricData {
  final StrokeIcon icon;
  final String title;
  final String value;
  final List<double> history;
  final AppViz viz;
  final String? peak;
  final String? valley;
  final String? average;

  const _MetricData({
    required this.icon,
    required this.title,
    required this.value,
    required this.history,
    required this.viz,
    this.peak,
    this.valley,
    this.average,
  });
}

class _FeatureData {
  final StrokeIcon icon;
  final String title;
  final String description;
  final AppViz viz;

  const _FeatureData({
    required this.icon,
    required this.title,
    required this.description,
    required this.viz,
  });
}

class _MetricCardWidget extends StatefulWidget {
  final double width;
  final _MetricData data;

  const _MetricCardWidget({required this.width, required this.data});

  @override
  State<_MetricCardWidget> createState() => _MetricCardWidgetState();
}

class _MetricCardWidgetState extends State<_MetricCardWidget> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);
    final viz = widget.data.viz;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: AppMotion.base,
        curve: AppMotion.standard,
        width: widget.width,
        padding: EdgeInsets.all(m.kSpace14),
        decoration: BoxDecoration(
          // 卡片不再半透明叠背景模糊：实色表面 + 1px 描边 + 中性抬升就是它全部的
          // 高度信息，身份色只留在图标底和折线图上。
          color: s.surface,
          borderRadius: m.radiusCard,
          border: Border.all(color: _hovered ? s.borderStrong : s.border),
          boxShadow: s.elevation(_hovered ? Elevation.card : Elevation.raised),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: m.iconSize28,
                  height: m.iconSize28,
                  decoration: BoxDecoration(
                    // 水洗底 + 同色图标，替代整块渐变实底：渐变是旧语言的招牌
                    color: viz.base.withValues(alpha: s.isDark ? 0.18 : 0.12),
                    borderRadius: m.radiusControl,
                  ),
                  child: Center(
                    child: DrawIcon(widget.data.icon, size: m.iconSize16, color: viz.base),
                  ),
                ),
                SizedBox(width: m.kSpace10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.data.title,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: s.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: m.kSpace2),
                      Text(
                        widget.data.value,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (widget.data.peak != null ||
                    widget.data.valley != null ||
                    widget.data.average != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (widget.data.peak != null) _statLine(context, '↑ ${widget.data.peak}'),
                      if (widget.data.valley != null) _statLine(context, '↓ ${widget.data.valley}'),
                      if (widget.data.average != null) _statLine(
                        context,
                        '≈ ${widget.data.average}',
                      ),
                    ],
                  ),
              ],
            ),
            SizedBox(height: m.kSpace10),
            SizedBox(
              height: scaleW(40).clamp(32.0, 52.0),
              child: _SparklineChart(data: List<double>.from(widget.data.history), viz: viz),
            ),
          ],
        ),
      ),
    );
  }

  /// 峰值/谷值/均值这三行是次要中的次要，但要读得出来，不能用透明黑叠透明黑
  Widget _statLine(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: AppSemantic.of(context).textTertiary,
        fontFeatures: const [FontFeature.tabularFigures()],
        fontSize: scaleS(9),
      ),
    );
  }
}

class _FeatureCardWidget extends StatefulWidget {
  final _FeatureData feature;

  const _FeatureCardWidget({required this.feature});

  @override
  State<_FeatureCardWidget> createState() => _FeatureCardWidgetState();
}

class _FeatureCardWidgetState extends State<_FeatureCardWidget> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);
    final viz = widget.feature.viz;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {},
        child: AnimatedContainer(
          duration: AppMotion.base,
          curve: AppMotion.standard,
          padding: EdgeInsets.all(m.kSpace20),
          decoration: BoxDecoration(
            color: s.surface,
            borderRadius: m.radiusCard,
            border: Border.all(color: _hovered ? s.borderStrong : s.border),
            boxShadow: s.elevation(_hovered ? Elevation.card : Elevation.raised),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: AppMotion.base,
                curve: AppMotion.standard,
                width: m.iconSize44,
                height: m.iconSize44,
                decoration: BoxDecoration(
                  color: viz.base.withValues(alpha: s.isDark ? 0.18 : 0.12),
                  borderRadius: m.radiusControl,
                ),
                child: Center(
                  child: DrawIcon(widget.feature.icon, size: m.iconSize24, color: viz.base),
                ),
              ),
              SizedBox(height: m.kSpace16),
              Text(
                widget.feature.title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: m.kSpace6),
              // 用 Flexible 包裹，允许描述文本在卡片高度紧张时收缩，避免 sub-pixel 溢出
              Flexible(
                child: Text(
                  widget.feature.description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: s.textSecondary,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Spacer(),
              // 「进入」是可点标签，走强调色而不是卡片身份色：
              // 淡紫/浅海蓝压在白卡上只有 1.9:1，读不出"这行能点"
              Row(
                children: [
                  Text(
                    '进入',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: s.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(width: m.kSpace4),
                  AnimatedSlide(
                    duration: AppMotion.base,
                    curve: AppMotion.standard,
                    offset: Offset(_hovered ? 0.15 : 0.0, 0),
                    child: DrawIcon(StrokeIcons.arrowForward, size: m.iconSize16, color: s.accent),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 迷你折线图（Sparkline），通过 [CustomPainter] 绘制渐变填充面积图。
class _SparklineChart extends StatelessWidget {
  const _SparklineChart({required this.data, required this.viz});

  final List<double> data;
  final AppViz viz;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SparklinePainter(data: data, viz: viz),
      child: const SizedBox.expand(),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.data, required this.viz});

  final List<double> data;
  final AppViz viz;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    final maxVal = data.reduce(math.max);
    final scale = maxVal > 0 ? maxVal : 1.0;
    final chartHeight = size.height * 0.85;
    final bottomPadding = size.height * 0.15;

    final glowPaint = Paint()
      ..color = viz.base.withValues(alpha: 0.15)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    final linePaint = Paint()
      ..shader = LinearGradient(
        colors: viz.gradient,
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(Offset.zero & size)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          viz.base.withValues(alpha: 0.25),
          viz.to.withValues(alpha: 0.02),
        ],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.fill;

    final points = <Offset>[];
    final step = size.width / (data.length - 1);

    for (int i = 0; i < data.length; i++) {
      final x = i * step;
      final normalizedVal = (data[i] / scale).clamp(0.0, 1.0);
      final y = size.height - bottomPadding - normalizedVal * chartHeight;
      points.add(Offset(x, y));
    }

    final linePath = _buildSmoothPath(points);
    final fillPath = Path.from(linePath);
    fillPath.lineTo(points.last.dx, size.height);
    fillPath.lineTo(points.first.dx, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(linePath, glowPaint);
    canvas.drawPath(linePath, linePaint);

    if (points.isNotEmpty) {
      final lastPoint = points.last;
      final dotPaint = Paint()..color = viz.base;
      final dotGlow = Paint()
        ..color = viz.base.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(lastPoint, 4, dotGlow);
      canvas.drawCircle(lastPoint, 2.5, dotPaint);
    }
  }

  Path _buildSmoothPath(List<Offset> points) {
    final path = Path();
    if (points.isEmpty) return path;

    path.moveTo(points.first.dx, points.first.dy);

    if (points.length == 2) {
      path.lineTo(points.last.dx, points.last.dy);
      return path;
    }

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = i > 0 ? points[i - 1] : points[i];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = i < points.length - 2 ? points[i + 2] : points[i + 1];

      final cp1x = p1.dx + (p2.dx - p0.dx) / 6;
      final cp1y = p1.dy + (p2.dy - p0.dy) / 6;
      final cp2x = p2.dx - (p3.dx - p1.dx) / 6;
      final cp2y = p2.dy - (p3.dy - p1.dy) / 6;

      path.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
    }

    return path;
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.data != data || old.viz.base != viz.base || old.viz.to != viz.to;
}
