import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/provider/main.dart';
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
          Text('解压设置', style: theme.textTheme.titleMedium),
          SizedBox(height: m.kSpace16),
          _buildDefaultOutputModeSetting(context, service),
          SizedBox(height: m.kSpace16),
          _buildDefaultParallelCountSetting(context, service),
          SizedBox(height: m.kSpace24),
          _buildPasswordManagement(context, service),
        ],
      ),
    );
  }

  Widget _buildDefaultOutputModeSetting(BuildContext context, ExtractService service) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(m.kSpace16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '默认解压方式',
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            SizedBox(height: m.kSpace8),
            Text(
              '选择默认的解压后文件夹创建方式',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
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
      leading: Icon(icon, size: m.iconSize20, color: theme.hintColor),
      title: Text(label, style: theme.textTheme.bodySmall),
      trailing: Icon(
        Icons.check_circle_outline,
        size: m.iconSize18,
        color: theme.colorScheme.primary.withAlpha(80),
      ),
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildDefaultParallelCountSetting(BuildContext context, ExtractService service) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(m.kSpace16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '默认并行解压数',
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            SizedBox(height: m.kSpace8),
            Text(
              '设置同时解压的压缩包数量',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
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
    );
  }

  Widget _buildPasswordManagement(BuildContext context, ExtractService service) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(m.kSpace16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '解压密码管理',
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                IconButton(
                  icon: Icon(Icons.add_circle_outline, size: m.iconSize20),
                  onPressed: () => _showAddPasswordDialog(context, service),
                  tooltip: '添加密码',
                ),
              ],
            ),
            SizedBox(height: m.kSpace8),
            Text(
              '管理解压密码，在解压时可直接选择',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
            SizedBox(height: m.kSpace12),
            Obx(() {
              final passwords = service.passwords;
              if (passwords.isEmpty) {
                return Padding(
                  padding: EdgeInsets.symmetric(vertical: m.kSpace16),
                  child: Center(
                    child: Text(
                      '暂无保存的密码',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                    ),
                  ),
                );
              }
              return Column(
                children: passwords
                    .map((entry) => _buildPasswordItem(context, service, entry))
                    .toList(),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordItem(BuildContext context, ExtractService service, PasswordEntry entry) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.vpn_key_outlined, size: m.iconSize18, color: theme.hintColor),
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
                color: theme.hintColor,
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
