import 'package:flutter/material.dart';
import 'dart:async';

import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/src/rust/api/system_metrics.dart' as rust_sys;

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

  void _refreshResourceSnapshot() {
    try {
      final next = rust_sys.getSystemResourceSnapshot();
      _nodeSettingsService.syncTrafficDisplayNow();
      if (!mounted) return;
      setState(() {
        _snapshot = next;
        _appRxKbps = _nodeSettingsService.appRxKbps.value;
        _appTxKbps = _nodeSettingsService.appTxKbps.value;
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
    return CustomScrollView(
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
                  '这是一个功能强大的 macOS 和 Windows 桌面应用',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(color: Theme.of(context).hintColor),
                ),
                SizedBox(height: AppTheme.metrics.kSpace48),
                Wrap(
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
                    ),
                    _buildMetricCard(
                      context,
                      icon: Icons.storage,
                      title: '内存',
                      value: _snapshot == null ? '--' : _formatMemory(_snapshot!),
                    ),
                    _buildMetricCard(
                      context,
                      icon: Icons.download,
                      title: '下行',
                      value: _snapshot == null ? '--' : _formatSpeed(_appRxKbps),
                    ),
                    _buildMetricCard(
                      context,
                      icon: Icons.upload,
                      title: '上行',
                      value: _snapshot == null ? '--' : _formatSpeed(_appTxKbps),
                    ),
                  ],
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
                  color: Colors.green,
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
    );
  }

  Widget _buildMetricCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      width: scaleW(180).clamp(140.0, 240.0),
      padding: EdgeInsets.symmetric(
        horizontal: AppTheme.metrics.kSpace12,
        vertical: AppTheme.metrics.kSpace10,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
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
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.1)),
      ),
      child: InkWell(
        onTap: () {
          // TODO: 导航到对应页面
        },
        borderRadius: BorderRadius.circular(16),
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
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
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
