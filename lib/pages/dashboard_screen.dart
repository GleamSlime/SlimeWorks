import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';

/// 概览页面
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 欢迎标题
          Text('欢迎使用工坊系统', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold)),
          SizedBox(height: AppTheme.metrics.kSpace16),
          Text('这是一个功能强大的 macOS 和 Windows 桌面应用', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).hintColor)),
          SizedBox(height: AppTheme.metrics.kSpace48),

          // 功能卡片网格
          Expanded(
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 320,
                // crossAxisCount: 3,
                mainAxisSpacing: 24,
                crossAxisSpacing: 24,
                // childAspectRatio: 1.5,
                mainAxisExtent: scaleW(230),
              ),
              itemCount: 6,
              itemBuilder: (context, index) {
                final features = [
                  _buildFeatureCard(context, icon: Icons.account_tree_outlined, title: '数据捕获', description: '强大的数据采集和处理功能', color: Colors.blue),
                  _buildFeatureCard(context, icon: Icons.water_drop_outlined, title: '流水账', description: '清晰的财务流水记录', color: Colors.cyan),
                  _buildFeatureCard(context, icon: Icons.cloud_outlined, title: '阿里云', description: '云服务管理工具', color: Colors.orange),
                  _buildFeatureCard(context, icon: Icons.build_circle_outlined, title: '工具箱', description: '丰富的实用工具集合', color: Colors.purple),
                  _buildFeatureCard(context, icon: Icons.video_library_outlined, title: '媒体库', description: '媒体文件管理中心', color: Colors.pink),
                  _buildFeatureCard(context, icon: Icons.note_outlined, title: '笔记', description: '快速记录和整理想法', color: Colors.green),
                ];
                return features[index];
              },
            ),
          ),
        ],
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
          padding: EdgeInsets.all(AppTheme.metrics.kSpace20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 图标
              Container(
                width: AppTheme.metrics.kSpace48,
                height: AppTheme.metrics.kSpace48,
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, size: AppTheme.metrics.kSpace24, color: color),
              ),
              SizedBox(height: AppTheme.metrics.kSpace16),

              // 标题
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: AppTheme.metrics.kSpace4),

              // 描述
              Text(
                description,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).hintColor),
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
