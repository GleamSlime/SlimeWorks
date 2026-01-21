import 'package:flutter/material.dart';
import 'package:slime_works/components/window/desktop_layout.dart';

/// 概览页面
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DesktopLayout(
      title: '概览',
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 欢迎标题
            Text('欢迎使用工坊', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Text('这是一个功能强大的 macOS 和 Windows 桌面应用', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).hintColor)),
            const SizedBox(height: 48),

            // 功能卡片网格
            Expanded(
              child: GridView.count(
                crossAxisCount: 3,
                mainAxisSpacing: 24,
                crossAxisSpacing: 24,
                childAspectRatio: 1.5,
                children: [
                  _buildFeatureCard(context, icon: Icons.account_tree_outlined, title: '数据捕获', description: '强大的数据采集和处理功能', color: Colors.blue),
                  _buildFeatureCard(context, icon: Icons.water_drop_outlined, title: '流水账', description: '清晰的财务流水记录', color: Colors.cyan),
                  _buildFeatureCard(context, icon: Icons.cloud_outlined, title: '阿里云', description: '云服务管理工具', color: Colors.orange),
                  _buildFeatureCard(context, icon: Icons.build_circle_outlined, title: '工具箱', description: '丰富的实用工具集合', color: Colors.purple),
                  _buildFeatureCard(context, icon: Icons.video_library_outlined, title: '媒体库', description: '媒体文件管理中心', color: Colors.pink),
                  _buildFeatureCard(context, icon: Icons.note_outlined, title: '笔记', description: '快速记录和整理想法', color: Colors.green),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建功能卡片
  Widget _buildFeatureCard(BuildContext context, {required IconData icon, required String title, required String description, required Color color}) {
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
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 图标
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, size: 24, color: color),
              ),
              const SizedBox(height: 16),

              // 标题
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),

              // 描述
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
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
