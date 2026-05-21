import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/services/extract_service.dart';

class ExtractSettingsTab extends StatelessWidget {
  const ExtractSettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;
    final service = getIt.get<ExtractService>();

    return SingleChildScrollView(
      padding: EdgeInsets.all(m.kSpace24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(context, '解压方式', Icons.folder_zip_outlined),
          SizedBox(height: m.kSpace12),
          _buildSettingsCard(
            context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '选择默认的解压后文件夹创建方式',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(150),
                  ),
                ),
                SizedBox(height: m.kSpace12),
                _buildOutputModeOption(
                  context,
                  '按压缩包名称创建文件夹',
                  ExtractOutputMode.byArchiveName,
                  Icons.folder_outlined,
                ),
                _buildOutputModeOption(
                  context,
                  '全部解压到目录下',
                  ExtractOutputMode.flatToOutput,
                  Icons.list_outlined,
                ),
                _buildOutputModeOption(
                  context,
                  '按原目录结构创建',
                  ExtractOutputMode.preserveStructure,
                  Icons.account_tree_outlined,
                ),
                _buildOutputModeOption(
                  context,
                  '解压到同级目录',
                  ExtractOutputMode.sameDirectory,
                  Icons.drive_file_move_outline,
                ),
              ],
            ),
          ),
          SizedBox(height: m.kSpace24),
          _buildSectionTitle(context, '并行解压数', Icons.speed_rounded),
          SizedBox(height: m.kSpace12),
          _buildSettingsCard(
            context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '设置同时解压的压缩包数量',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(150),
                  ),
                ),
                SizedBox(height: m.kSpace12),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: 1,
                        min: 1,
                        max: 8,
                        divisions: 7,
                        label: '1',
                        onChanged: (_) {},
                      ),
                    ),
                    SizedBox(
                      width: m.kSpace40,
                      child: Text('1', textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: m.kSpace24),
          _buildPasswordManagement(context, service),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title, IconData icon) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;
    return Row(
      children: [
        Container(
          width: m.kSpace24,
          height: m.kSpace24,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withAlpha(20),
            borderRadius: m.radius6,
          ),
          child: Icon(
            icon,
            size: m.iconSize12,
            color: theme.colorScheme.primary,
          ),
        ),
        SizedBox(width: m.kSpace8),
        Text(
          title,
          style: TextStyle(
            fontSize: m.fontSize15,
            height: 1.4,
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsCard(BuildContext context, {required Widget child}) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(m.kSpace16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
        borderRadius: m.radius12,
        border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: child,
    );
  }

  Widget _buildOutputModeOption(
    BuildContext context,
    String label,
    ExtractOutputMode mode,
    IconData icon,
  ) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;

    return ListTile(
      dense: true,
      leading: Container(
        width: m.kSpace32,
        height: m.kSpace32,
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withAlpha(15),
          borderRadius: m.radius8,
        ),
        child: Icon(icon, size: m.iconSize16, color: theme.colorScheme.primary),
      ),
      title: Text(label, style: theme.textTheme.bodySmall),
      trailing: Icon(
        Icons.check_circle_outline,
        size: m.iconSize18,
        color: theme.colorScheme.primary.withAlpha(80),
      ),
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildPasswordManagement(BuildContext context, ExtractService service) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;
    final isDark = theme.brightness == Brightness.dark;
    final brandColor = isDark ? DarkColors.primary : LightColors.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildSectionTitle(context, '解压密码管理', Icons.vpn_key_outlined),
            Spacer(),
            IconButton(
              icon: Icon(Icons.add_circle_outline, size: m.iconSize20),
              onPressed: () => _showAddPasswordDialog(context, service),
              tooltip: '添加密码',
            ),
          ],
        ),
        SizedBox(height: m.kSpace4),
        Text(
          '管理解压密码，在解压时可直接选择',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withAlpha(150),
          ),
        ),
        SizedBox(height: m.kSpace12),
        Obx(() {
          final passwords = service.passwords;
          if (passwords.isEmpty) {
            return Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: m.kSpace24, vertical: m.kSpace32),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
                borderRadius: m.radius12,
                border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(60)),
              ),
              child: Column(
                children: [
                  Container(
                    width: m.kSpace40,
                    height: m.kSpace40,
                    decoration: BoxDecoration(
                      color: brandColor.withAlpha(20),
                      borderRadius: m.radius10,
                    ),
                    child: Icon(Icons.lock_outline, size: m.iconSize20, color: brandColor),
                  ),
                  SizedBox(height: m.kSpace12),
                  Text(
                    '暂无保存的密码',
                    style: TextStyle(
                      fontSize: m.fontSize13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  SizedBox(height: m.kSpace4),
                  Text(
                    '点击右上角 + 添加解压密码',
                    style: TextStyle(
                      fontSize: m.fontSize12,
                      color: theme.colorScheme.onSurface.withAlpha(120),
                    ),
                  ),
                ],
              ),
            );
          }
          return _buildSettingsCard(
            context,
            child: Column(
              children: passwords
                  .map((entry) => _buildPasswordItem(context, service, entry))
                  .toList(),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildPasswordItem(BuildContext context, ExtractService service, PasswordEntry entry) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: m.kSpace32,
        height: m.kSpace32,
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withAlpha(15),
          borderRadius: m.radius8,
        ),
        child: Icon(Icons.vpn_key_outlined, size: m.iconSize16, color: theme.colorScheme.primary),
      ),
      title: Text(
        entry.displayName,
        style: theme.textTheme.bodySmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: entry.remark?.isNotEmpty == true
          ? Text(
              '密码: ${_maskPassword(entry.password)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(120),
                fontSize: m.fontSize10,
              ),
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.edit_outlined, size: m.iconSize16),
            onPressed: () => _showEditRemarkDialog(context, service, entry),
            tooltip: '编辑备注',
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, size: m.iconSize16, color: theme.colorScheme.error),
            onPressed: () => _confirmDelete(context, service, entry),
            tooltip: '删除',
          ),
        ],
      ),
    );
  }

  String _maskPassword(String password) {
    if (password.length <= 2) return '****';
    return '${password.substring(0, 1)}****${password.substring(password.length - 1)}';
  }

  void _showAddPasswordDialog(BuildContext context, ExtractService service) {
    final m = AppTheme.metrics;
    final passwordCtrl = TextEditingController();
    final remarkCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加解压密码'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: passwordCtrl,
                decoration: const InputDecoration(hintText: '输入密码', labelText: '密码'),
                obscureText: true,
              ),
              SizedBox(height: m.kSpace12),
              TextField(
                controller: remarkCtrl,
                decoration: const InputDecoration(hintText: '输入备注（可选）', labelText: '备注'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              if (passwordCtrl.text.isNotEmpty) {
                service.addPassword(
                  passwordCtrl.text,
                  remark: remarkCtrl.text.isEmpty ? null : remarkCtrl.text,
                );
                Navigator.pop(ctx);
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  void _showEditRemarkDialog(BuildContext context, ExtractService service, PasswordEntry entry) {
    final remarkCtrl = TextEditingController(text: entry.remark ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑备注'),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: remarkCtrl,
            decoration: const InputDecoration(hintText: '输入备注', labelText: '备注'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              service.updatePasswordRemark(
                entry.id,
                remarkCtrl.text.isEmpty ? null : remarkCtrl.text,
              );
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, ExtractService service, PasswordEntry entry) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除密码「${entry.displayName}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              service.removePassword(entry.id);
              Navigator.pop(ctx);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
