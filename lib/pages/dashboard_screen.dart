import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;

import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/services/system_metrics_service.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/src/rust/api/system_metrics.dart' as rust_sys;
import 'package:slime_works/core/theme/app_colors.dart';

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
      duration: const Duration(milliseconds: 900),
    );

    _cardAnimations = List.generate(11, (index) {
      final start = (index * 0.06).clamp(0.0, 0.7);
      return CurvedAnimation(
        parent: _entranceController,
        curve: Interval(start, (start + 0.3).clamp(0.0, 1.0), curve: Curves.easeOutCubic),
      );
    });

    // 定时从 Service 拉取最新数据以刷新 UI
    _uiRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    Future.delayed(const Duration(milliseconds: 120), () {
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
              sliver: SliverToBoxAdapter(child: _buildHeader(context, isDark)),
            ),
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace20),
              sliver: SliverToBoxAdapter(child: _buildMetricSection(context, isDark)),
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
                  return _buildFeatureItem(context, index, isDark);
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

  Widget _buildHeader(BuildContext context, bool isDark) {
    final anim = _cardAnimations[0];
    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) {
        return Opacity(
          opacity: anim.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - anim.value)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: AppTheme.metrics.kSpace12),
                ShaderMask(
                  shaderCallback: (bounds) {
                    return LinearGradient(
                      colors: isDark
                          ? [DarkColors.primary, DarkColors.purple, DarkColors.blue]
                          : [LightColors.primary, LightColors.purple, LightColors.indigo],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ).createShader(bounds);
                  },
                  child: Text(
                    '工坊系统',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      fontSize: scaleS(32),
                    ),
                  ),
                ),
                SizedBox(height: AppTheme.metrics.kSpace6),
                Text(
                  '实时监控 · 模块管理 · 一站式工具',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).hintColor,
                    letterSpacing: 1.5,
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
    return Padding(
      padding: EdgeInsets.only(bottom: AppTheme.metrics.kSpace12),
      child: Row(
        children: [
          Container(
            width: 3,
            height: scaleW(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(width: AppTheme.metrics.kSpace8),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricSection(BuildContext context, bool isDark) {
    final snapshot = _metricsService.lastSnapshot;
    final metrics = [
      _MetricData(
        icon: Icons.memory_rounded,
        title: 'CPU',
        value: snapshot == null ? '--' : '${snapshot.cpuUsagePercent.toStringAsFixed(1)}%',
        history: List<double>.from(_metricsService.cpuHistory),
        chartColor: const Color(0xFF6FB8E8),
        gradientColors: const [Color(0xFF6FB8E8), Color(0xFFA8B8F6)],
      ),
      _MetricData(
        icon: Icons.storage_rounded,
        title: '内存',
        value: snapshot == null ? '--' : _formatMemory(snapshot),
        history: List<double>.from(_metricsService.memHistory),
        chartColor: const Color(0xFFF5A569),
        gradientColors: const [Color(0xFFF5A569), Color(0xFFFFCB3A)],
      ),
      _MetricData(
        icon: Icons.download_rounded,
        title: '下行',
        value: snapshot == null ? '--' : _formatSpeed(_metricsService.appRxKbps),
        history: List<double>.from(_metricsService.rxHistory),
        chartColor: isDark ? DarkColors.success : LightColors.success,
        gradientColors: isDark
            ? const [Color(0xFF66BB6A), Color(0xFF82D7BB)]
            : const [Color(0xFF4CAF50), Color(0xFF82D7BB)],
      ),
      _MetricData(
        icon: Icons.upload_rounded,
        title: '上行',
        value: snapshot == null ? '--' : _formatSpeed(_metricsService.appTxKbps),
        history: List<double>.from(_metricsService.txHistory),
        chartColor: const Color(0xFFBBA8F6),
        gradientColors: const [Color(0xFFBBA8F6), Color(0xFFA89FEE)],
      ),
    ];

    if (_metricsService.isLocalServerRunning) {
      metrics.add(
        _MetricData(
          icon: Icons.hub_rounded,
          title: '节点请求',
          value: _metricsService.nodeRequestCount.toString(),
          history: List<double>.from(_metricsService.reqHistory),
          chartColor: const Color(0xFF9AC8DD),
          gradientColors: const [Color(0xFF9AC8DD), Color(0xFF6FB8E8)],
        ),
      );
    }

    return Wrap(
      spacing: AppTheme.metrics.kSpace12,
      runSpacing: AppTheme.metrics.kSpace12,
      children: [
        for (int i = 0; i < metrics.length; i++) _buildMetricCard(context, metrics[i], i, isDark),
      ],
    );
  }

  Widget _buildMetricCard(BuildContext context, _MetricData data, int animIndex, bool isDark) {
    final anim = _cardAnimations[(animIndex + 1).clamp(0, _cardAnimations.length - 1)];
    final cardWidth = ((MediaQuery.of(context).size.width - scaleW(44)) / 2).clamp(100.0, 240.0);

    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) {
        return Opacity(
          opacity: anim.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - anim.value)),
            child: _MetricCardWidget(width: cardWidth, data: data, isDark: isDark),
          ),
        );
      },
    );
  }

  Widget _buildFeatureItem(BuildContext context, int index, bool isDark) {
    final features = [
      _FeatureData(
        icon: Icons.account_tree_outlined,
        title: '数据捕获',
        description: '强大的数据采集和处理功能',
        gradientColors: const [Color(0xFF6FB8E8), Color(0xFFA8B8F6)],
      ),
      _FeatureData(
        icon: Icons.water_drop_outlined,
        title: '流水账',
        description: '清晰的财务流水记录',
        gradientColors: const [Color(0xFF9AC8DD), Color(0xFF82D7BB)],
      ),
      _FeatureData(
        icon: Icons.cloud_outlined,
        title: '阿里云',
        description: '云服务管理工具',
        gradientColors: const [Color(0xFFF5A569), Color(0xFFFFCB3A)],
      ),
      _FeatureData(
        icon: Icons.build_circle_outlined,
        title: '工具箱',
        description: '丰富的实用工具集合',
        gradientColors: const [Color(0xFFBBA8F6), Color(0xFFA89FEE)],
      ),
      _FeatureData(
        icon: Icons.video_library_outlined,
        title: '媒体库',
        description: '媒体文件管理中心',
        gradientColors: const [Color(0xFFFF6C74), Color(0xFFF5A569)],
      ),
      _FeatureData(
        icon: Icons.note_outlined,
        title: '笔记',
        description: '快速记录和整理想法',
        gradientColors: isDark
            ? const [Color(0xFF66BB6A), Color(0xFF82D7BB)]
            : const [Color(0xFF4CAF50), Color(0xFF82D7BB)],
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
            offset: Offset(0, 20 * (1 - anim.value)),
            child: _FeatureCardWidget(feature: feature, isDark: isDark),
          ),
        );
      },
    );
  }
}

class _MetricData {
  final IconData icon;
  final String title;
  final String value;
  final List<double> history;
  final Color chartColor;
  final List<Color> gradientColors;

  const _MetricData({
    required this.icon,
    required this.title,
    required this.value,
    required this.history,
    required this.chartColor,
    required this.gradientColors,
  });
}

class _FeatureData {
  final IconData icon;
  final String title;
  final String description;
  final List<Color> gradientColors;

  const _FeatureData({
    required this.icon,
    required this.title,
    required this.description,
    required this.gradientColors,
  });
}

class _MetricCardWidget extends StatefulWidget {
  final double width;
  final _MetricData data;
  final bool isDark;

  const _MetricCardWidget({required this.width, required this.data, required this.isDark});

  @override
  State<_MetricCardWidget> createState() => _MetricCardWidgetState();
}

class _MetricCardWidgetState extends State<_MetricCardWidget> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: widget.width,
        decoration: BoxDecoration(
          color: widget.isDark
              ? DarkColors.background2.withValues(alpha: _hovered ? 0.95 : 0.75)
              : Colors.white.withValues(alpha: _hovered ? 0.95 : 0.80),
          borderRadius: m.radius16,
          border: Border.all(
            color: widget.isDark
                ? DarkColors.white10.withValues(alpha: _hovered ? 0.3 : 0.08)
                : LightColors.black10.withValues(alpha: _hovered ? 0.15 : 0.06),
          ),
          boxShadow: [
            BoxShadow(
              color: widget.data.chartColor.withValues(alpha: _hovered ? 0.18 : 0.06),
              blurRadius: _hovered ? 20 : 8,
              offset: Offset(0, _hovered ? 6 : 2),
            ),
            if (!widget.isDark)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: m.radius8,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Padding(
              padding: EdgeInsets.all(m.kSpace14),
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
                          gradient: LinearGradient(
                            colors: widget.data.gradientColors,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: m.radius8,
                        ),
                        child: Center(
                          child: Icon(widget.data.icon, size: m.iconSize16, color: Colors.white),
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
                                color: Theme.of(context).hintColor,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.5,
                              ),
                            ),
                            SizedBox(height: m.kSpace2),
                            Text(
                              widget.data.value,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: m.kSpace10),
                  SizedBox(
                    height: scaleW(40).clamp(32.0, 52.0),
                    child: _SparklineChart(
                      data: List<double>.from(widget.data.history),
                      color: widget.data.chartColor,
                      gradientColors: widget.data.gradientColors,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureCardWidget extends StatefulWidget {
  final _FeatureData feature;
  final bool isDark;

  const _FeatureCardWidget({required this.feature, required this.isDark});

  @override
  State<_FeatureCardWidget> createState() => _FeatureCardWidgetState();
}

class _FeatureCardWidgetState extends State<_FeatureCardWidget> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {},
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: widget.isDark
                ? DarkColors.background2.withValues(alpha: _hovered ? 0.95 : 0.70)
                : Colors.white.withValues(alpha: _hovered ? 0.95 : 0.78),
            borderRadius: m.radius20,
            border: Border.all(
              color: widget.isDark
                  ? DarkColors.white10.withValues(alpha: _hovered ? 0.25 : 0.06)
                  : LightColors.black10.withValues(alpha: _hovered ? 0.12 : 0.04),
            ),
            boxShadow: [
              BoxShadow(
                color: widget.feature.gradientColors.first.withValues(
                  alpha: _hovered ? 0.15 : 0.04,
                ),
                blurRadius: _hovered ? 24 : 8,
                offset: Offset(0, _hovered ? 8 : 2),
              ),
              if (!widget.isDark)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: m.radius20,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Padding(
                padding: EdgeInsets.all(m.kSpace20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      width: m.iconSize44,
                      height: m.iconSize44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: widget.feature.gradientColors,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: m.radius14,
                        boxShadow: [
                          BoxShadow(
                            color: widget.feature.gradientColors.first.withValues(
                              alpha: _hovered ? 0.4 : 0.2,
                            ),
                            blurRadius: _hovered ? 12 : 6,
                            offset: Offset(0, _hovered ? 4 : 2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(widget.feature.icon, size: m.iconSize24, color: Colors.white),
                      ),
                    ),
                    SizedBox(height: m.kSpace16),
                    Text(
                      widget.feature.title,
                      style: Theme.of(
                        context,
                      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: m.kSpace6),
                    Text(
                      widget.feature.description,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).hintColor,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Text(
                          '进入',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: widget.feature.gradientColors.first,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        SizedBox(width: m.kSpace4),
                        AnimatedRotation(
                          duration: const Duration(milliseconds: 250),
                          turns: _hovered ? 0.0 : 0.0,
                          child: AnimatedSlide(
                            duration: const Duration(milliseconds: 250),
                            offset: Offset(_hovered ? 0.15 : 0.0, 0),
                            child: Icon(
                              Icons.arrow_forward_rounded,
                              size: m.iconSize16,
                              color: widget.feature.gradientColors.first,
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
      ),
    );
  }
}

/// 迷你折线图（Sparkline），通过 [CustomPainter] 绘制渐变填充面积图。
class _SparklineChart extends StatelessWidget {
  const _SparklineChart({required this.data, required this.color, required this.gradientColors});

  final List<double> data;
  final Color color;
  final List<Color> gradientColors;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SparklinePainter(data: data, color: color, gradientColors: gradientColors),
      child: const SizedBox.expand(),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.data, required this.color, required this.gradientColors});

  final List<double> data;
  final Color color;
  final List<Color> gradientColors;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    final maxVal = data.reduce(math.max);
    final scale = maxVal > 0 ? maxVal : 1.0;
    final chartHeight = size.height * 0.85;
    final bottomPadding = size.height * 0.15;

    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    final linePaint = Paint()
      ..shader = LinearGradient(
        colors: gradientColors,
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
          gradientColors.first.withValues(alpha: 0.25),
          gradientColors.last.withValues(alpha: 0.02),
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
      final dotPaint = Paint()..color = color;
      final dotGlow = Paint()
        ..color = color.withValues(alpha: 0.3)
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
      old.data != data || old.color != color || old.gradientColors != gradientColors;
}
