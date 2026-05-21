import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/src/rust/api/system_metrics.dart' as rust_sys;
import 'package:slime_works/core/theme/app_colors.dart';

/// 折线图历史点数量（每秒采样 1 次，保留 60 秒）
const int _kHistoryLength = 60;

/// 概览页面
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Timer? _resourceTimer;
  rust_sys.SystemResourceSnapshot? _snapshot;
  final NodeSettingsService _nodeSettingsService = getIt<NodeSettingsService>();
  double _appRxKbps = 0;
  double _appTxKbps = 0;
  bool _isLocalServerRunning = false;
  int _nodeRequestCount = 0;

  /// 历史数据缓冲区（CPU%、内存MB、下行kbps、上行kbps、节点请求数/s）
  final List<double> _cpuHistory = [];
  final List<double> _memHistory = [];
  final List<double> _rxHistory = [];
  final List<double> _txHistory = [];
  final List<double> _reqHistory = [];
  int _lastNodeRequestCount = 0;

  @override
  void initState() {
    super.initState();
    _refreshResourceSnapshot();
    _resourceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _refreshResourceSnapshot();
    });
  }

  @override
  void dispose() {
    _resourceTimer?.cancel();
    super.dispose();
  }

  void _appendHistory(List<double> buf, double value) {
    buf.add(value);
    if (buf.length > _kHistoryLength) buf.removeAt(0);
  }

  void _refreshResourceSnapshot() {
    try {
      final next = rust_sys.getSystemResourceSnapshot();
      _nodeSettingsService.syncTrafficDisplayNow();
      if (!mounted) return;
      final rxKbps = _nodeSettingsService.appRxKbps.value;
      final txKbps = _nodeSettingsService.appTxKbps.value;
      final reqCount = _nodeSettingsService.nodeRequestCount.value;
      final reqDelta = (reqCount - _lastNodeRequestCount).clamp(0, 999999).toDouble();
      setState(() {
        _snapshot = next;
        _appRxKbps = rxKbps;
        _appTxKbps = txKbps;
        _lastNodeRequestCount = reqCount;
        _isLocalServerRunning = _nodeSettingsService.isLocalServerRunning;
        _nodeRequestCount = reqCount;
        _appendHistory(_cpuHistory, next.cpuUsagePercent);
        _appendHistory(_memHistory, next.memoryUsedMb.toDouble());
        _appendHistory(_rxHistory, rxKbps);
        _appendHistory(_txHistory, txKbps);
        _appendHistory(_reqHistory, reqDelta);
      });
    } catch (_) {}
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
              padding: EdgeInsets.all(AppTheme.metrics.kSpace12),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '欢迎使用工坊系统',
                      style: Theme.of(
                        context,
                      ).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: AppTheme.metrics.kSpace16),
                    Text(
                      // '这是一个功能强大的 macOS 和 Windows 桌面应用',
                      '',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(color: Theme.of(context).hintColor),
                    ),
                    SizedBox(height: AppTheme.metrics.kSpace48),
                    SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        spacing: AppTheme.metrics.kSpace12,
                        runSpacing: AppTheme.metrics.kSpace12,
                        children: [
                          _buildMetricCard(
                            context,
                            icon: Icons.memory,
                            title: 'CPU',
                            value: _snapshot == null
                                ? '--'
                                : '${_snapshot!.cpuUsagePercent.toStringAsFixed(1)}%',
                            history: _cpuHistory,
                            chartColor: Colors.blue,
                          ),
                          _buildMetricCard(
                            context,
                            icon: Icons.storage,
                            title: '内存',
                            value: _snapshot == null ? '--' : _formatMemory(_snapshot!),
                            history: _memHistory,
                            chartColor: Colors.orange,
                          ),
                          _buildMetricCard(
                            context,
                            icon: Icons.download,
                            title: '下行',
                            value: _snapshot == null ? '--' : _formatSpeed(_appRxKbps),
                            history: _rxHistory,
                            chartColor: (Theme.of(context).brightness == Brightness.dark)
                                ? DarkColors.success
                                : LightColors.success,
                          ),
                          _buildMetricCard(
                            context,
                            icon: Icons.upload,
                            title: '上行',
                            value: _snapshot == null ? '--' : _formatSpeed(_appTxKbps),
                            history: _txHistory,
                            chartColor: Colors.purple,
                          ),
                          if (_isLocalServerRunning)
                            _buildMetricCard(
                              context,
                              icon: Icons.hub,
                              title: '节点请求数',
                              value: _nodeRequestCount.toString(),
                              history: _reqHistory,
                              chartColor: Colors.teal,
                            ),
                        ],
                      ),
                    ),
                    SizedBox(height: AppTheme.metrics.kSpace24),
                  ],
                ),
              ),
            ),

            SliverPadding(
              padding: EdgeInsets.symmetric(
                horizontal: AppTheme.metrics.kSpace12,
                vertical: AppTheme.metrics.kSpace12,
              ),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final features = [
                    _buildFeatureCard(
                      context,
                      icon: Icons.account_tree_outlined,
                      title: '数据捕获',
                      description: '强大的数据采集和处理功能',
                      color: Colors.blue,
                    ),
                    _buildFeatureCard(
                      context,
                      icon: Icons.water_drop_outlined,
                      title: '流水账',
                      description: '清晰的财务流水记录',
                      color: Colors.cyan,
                    ),
                    _buildFeatureCard(
                      context,
                      icon: Icons.cloud_outlined,
                      title: '阿里云',
                      description: '云服务管理工具',
                      color: Colors.orange,
                    ),
                    _buildFeatureCard(
                      context,
                      icon: Icons.build_circle_outlined,
                      title: '工具箱',
                      description: '丰富的实用工具集合',
                      color: Colors.purple,
                    ),
                    _buildFeatureCard(
                      context,
                      icon: Icons.video_library_outlined,
                      title: '媒体库',
                      description: '媒体文件管理中心',
                      color: Colors.pink,
                    ),
                    _buildFeatureCard(
                      context,
                      icon: Icons.note_outlined,
                      title: '笔记',
                      description: '快速记录和整理想法',
                      color: (Theme.of(context).brightness == Brightness.dark)
                          ? DarkColors.success
                          : LightColors.success,
                    ),
                  ];
                  return features[index];
                }, childCount: 6),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 320,
                  mainAxisSpacing: 24,
                  crossAxisSpacing: 24,
                  mainAxisExtent: scaleW(230).clamp(180.0, 320.0),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
    required List<double> history,
    required Color chartColor,
  }) {
    return Container(
      width: ((MediaQuery.of(context).size.width - scaleW(36)) / 2).clamp(70.0, 200.0),
      padding: EdgeInsets.symmetric(
        horizontal: AppTheme.metrics.kSpace12,
        vertical: AppTheme.metrics.kSpace10,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: AppTheme.metrics.radius12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部：图标 + 当前值
          Row(
            children: [
              Icon(icon, size: AppTheme.metrics.kSpace16),
              SizedBox(width: AppTheme.metrics.kSpace8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.bodySmall),
                    Text(
                      value,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: AppTheme.metrics.kSpace8),
          // 底部：迷你折线图
          SizedBox(
            height: scaleW(36).clamp(28.0, 48.0),
            child: _SparklineChart(data: List<double>.from(history), color: chartColor),
          ),
        ],
      ),
    );
  }

  /// 构建功能卡片
  Widget _buildFeatureCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppTheme.metrics.radius16,
        side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
      ),
      child: InkWell(
        onTap: () {
          // TODO: 导航到对应页面
        },
        borderRadius: AppTheme.metrics.radius16,
        child: Padding(
          padding: EdgeInsets.all(AppTheme.metrics.kSpace20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 图标
              Container(
                width: AppTheme.metrics.kSpace48,
                height: AppTheme.metrics.kSpace48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: AppTheme.metrics.radius12,
                ),
                child: Icon(icon, size: AppTheme.metrics.kSpace24, color: color),
              ),
              SizedBox(height: AppTheme.metrics.kSpace16),

              // 标题
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: AppTheme.metrics.kSpace4),

              // 描述
              Text(
                description,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: Theme.of(context).hintColor),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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
  const _SparklineChart({required this.data, required this.color});

  final List<double> data;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SparklinePainter(data: data, color: color),
      child: const SizedBox.expand(),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.data, required this.color});

  final List<double> data;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    final maxVal = data.reduce(math.max);
    // 至少保留一个非零上限，防止全零时除以零
    final scale = maxVal > 0 ? maxVal : 1.0;

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withAlpha(80), color.withAlpha(0)],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.fill;

    final linePath = Path();
    final fillPath = Path();

    final step = size.width / (data.length - 1);

    for (int i = 0; i < data.length; i++) {
      final x = i * step;
      final y = size.height - (data[i] / scale) * size.height;
      if (i == 0) {
        linePath.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        linePath.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    // 完成填充路径
    fillPath.lineTo((data.length - 1) * step, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(linePath, linePaint);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => old.data != data || old.color != color;
}
