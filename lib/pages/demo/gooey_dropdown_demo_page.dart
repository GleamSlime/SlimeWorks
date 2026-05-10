import 'package:slime_works/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:slime_works/components/dropdown/gooey_dropdown_shader.dart';
import 'package:slime_works/core/index.dart';

/// GooeyDropdownShader 使用示例页面
class GooeyDropdownDemoPage extends StatelessWidget {
  const GooeyDropdownDemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff2f2f2),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('点击按钮查看粘连效果', style: TextStyle(fontSize: AppTheme.metrics.fontSize18, color: Colors.black54)),
            SizedBox(height: AppTheme.metrics.kSpace40),

            // 示例1：默认样式
            GooeyDropdownShader(
              button: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: AppTheme.metrics.radius25,
                  boxShadow: [const BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4))],
                ),
                child: const Icon(Icons.chat_bubble_outline, color: Colors.white),
              ),
              cardOffset: 30,
              direction: DropdownDirection.left,
              content: const _MessageContent(),
              onOpen: () => debugPrint('打开了消息卡片'),
              onClose: () => debugPrint('关闭了消息卡片'),
            ),

            SizedBox(height: AppTheme.metrics.kSpace80),

            // 示例2：自定义样式
            GooeyDropdownShader(
              button: const Icon(Icons.menu, color: Colors.white),
              content: const _MenuContent(),
              buttonSize: const Size(48, 48),
              cardSize: const Size(280, 240),
              buttonColor: Colors.deepPurple,
              cardRadius: 12,
              cardOffset: 10,
              duration: const Duration(milliseconds: 1000),
              onOpen: () => debugPrint('打开了菜单'),
              onClose: () => debugPrint('关闭了菜单'),
            ),
            SizedBox(height: AppTheme.metrics.kSpace80),

            // 示例3：默认样式
            GooeyDropdownShader(
              button: Container(
                width: AppTheme.metrics.kSpace48,
                height: AppTheme.metrics.kSpace48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: AppTheme.metrics.radius24,
                  border: Border.all(color: Colors.black12),
                  boxShadow: [const BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
                ),
                child: Text(
                  "data",
                  style: TextStyle(color: Colors.black, fontSize: AppTheme.metrics.fontSize9, decoration: TextDecoration.none),
                ),
              ),
              cardBorder: Border.all(color: Colors.black12),
              cardBoxShadow: [const BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
              buttonColor: Colors.white,
              cardColor: Colors.white,
              cardOffset: 30,
              direction: DropdownDirection.left,
              content: const _MessageContent(),
              onOpen: () => debugPrint('打开了消息卡片'),
              onClose: () => debugPrint('关闭了消息卡片'),
              duration: const Duration(milliseconds: 250),
            ),
          ],
        ),
      ),
    );
  }
}

/// 消息内容示例
class _MessageContent extends StatelessWidget {
  const _MessageContent();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(AppTheme.metrics.kSpace12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Messages',
            style: TextStyle(color: Colors.white, fontSize: AppTheme.metrics.fontSize15, fontWeight: FontWeight.bold, decoration: TextDecoration.none),
          ),
          SizedBox(height: AppTheme.metrics.kSpace8),
          const _MessageRow(avatar: Icons.person, name: 'Alice', message: 'Hey, how are you?'),
          const _MessageRow(avatar: Icons.person_outline, name: 'Bob', message: 'Meeting at 3pm'),
          const _MessageRow(avatar: Icons.group, name: 'Team Chat', message: 'New updates available'),
        ],
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  final IconData avatar;
  final String name;
  final String message;

  const _MessageRow({required this.avatar, required this.name, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: AppTheme.metrics.kSpace6),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.white24,
              child: Icon(avatar, size: AppTheme.metrics.iconSize18, color: Colors.white),
            ),
            SizedBox(width: AppTheme.metrics.kSpace10),
            SizedBox(
              width: 200,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(color: Colors.white, fontSize: AppTheme.metrics.fontSize13, fontWeight: FontWeight.w500, decoration: TextDecoration.none),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    message,
                    style: TextStyle(color: Colors.white70, fontSize: AppTheme.metrics.fontSize11, decoration: TextDecoration.none),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 菜单内容示例
class _MenuContent extends StatelessWidget {
  const _MenuContent();

  @override
  Widget build(BuildContext context) {
    return const Material(
      color: Colors.transparent,
      child: Column(
        children: [
          _MenuItem(icon: Icons.settings, label: 'Settings'),
          _MenuItem(icon: Icons.person, label: 'Profile'),
          _MenuItem(icon: Icons.help, label: 'Help'),
          _MenuItem(icon: Icons.logout, label: 'Logout'),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MenuItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => debugPrint('点击了 $label'),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace20, vertical: AppTheme.metrics.kSpace8),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: AppTheme.metrics.iconSize20),
              SizedBox(width: AppTheme.metrics.kSpace12),
              SizedBox(
                width: 140,
                child: Text(
                  label,
                  style: TextStyle(color: Colors.white, fontSize: AppTheme.metrics.fontSize15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
