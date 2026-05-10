import 'package:slime_works/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// 显示密码输入对话框
Future<String?> showPasswordDialog(BuildContext context) async {
  final passwordController = TextEditingController(text: '');
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Row(children: [Icon(Icons.security, size: AppTheme.metrics.iconSize24), SizedBox(width: AppTheme.metrics.kSpace8), const Text('安装CA证书')]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('需要管理员密码来安装CA证书到系统钥匙串。'),
          SizedBox(height: AppTheme.metrics.kSpace8),
          Text(
            '这是HTTPS流量捕获所必需的步骤。',
            style: TextStyle(
              fontSize: AppTheme.metrics.fontSize11,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          SizedBox(height: AppTheme.metrics.kSpace16),
          TextField(
            controller: passwordController,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '管理员密码',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.lock),
            ),
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.pop(context, passwordController.text),
          child: const Text('确定'),
        ),
      ],
    ),
  );
}

/// 显示信任证书引导对话框
void showTrustCertificateGuide(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(
        children: [Icon(Icons.verified_user, size: AppTheme.metrics.iconSize24), SizedBox(width: AppTheme.metrics.kSpace8), const Text('信任CA证书')],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('证书已安装到系统钥匙串，请按以下步骤信任证书：'),
            SizedBox(height: AppTheme.metrics.kSpace16),
            const _GuideStep(number: '1', text: '打开"钥匙串访问"应用'),
            const _GuideStep(number: '2', text: '在"系统"钥匙串中找到"SlimeWorks CA"证书'),
            const _GuideStep(number: '3', text: '双击证书，展开"信任"部分'),
            const _GuideStep(number: '4', text: '将"使用此证书时"设置为"始终信任"'),
            const _GuideStep(number: '5', text: '关闭窗口并输入密码确认'),
            SizedBox(height: AppTheme.metrics.kSpace16),
            Container(
              padding: EdgeInsets.all(AppTheme.metrics.kSpace12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: AppTheme.metrics.radius8,
                border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue, size: AppTheme.metrics.iconSize20),
                  SizedBox(width: AppTheme.metrics.kSpace8),
                  Expanded(
                    child: Text(
                      '只有信任证书后才能捕获HTTPS流量',
                      style: TextStyle(fontSize: AppTheme.metrics.fontSize11),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('我知道了'))],
    ),
  );
}

/// 显示清除数据确认对话框
Future<bool?> showClearDataDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('确认清除'),
      content: const Text('确定要清除所有捕获的数据吗？'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('确定')),
      ],
    ),
  );
}

/// 显示编辑任务名称对话框
Future<String?> showEditTaskNameDialog(BuildContext context, String currentName) async {
  final controller = TextEditingController(text: currentName);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('修改录制名称'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(labelText: '录制名称', border: OutlineInputBorder()),
        autofocus: true,
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('确定')),
      ],
    ),
  );
}

/// 显示删除任务确认对话框
Future<bool?> showDeleteTaskDialog(
  BuildContext context,
  String taskName,
  bool hasFile,
  String? fileSize,
) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.warning_amber, color: Colors.orange),
          SizedBox(width: AppTheme.metrics.kSpace8),
          const Text('确认删除'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('确定要删除录制任务"$taskName"吗？'),
          SizedBox(height: AppTheme.metrics.kSpace16),
          if (hasFile)
            Container(
              padding: EdgeInsets.all(AppTheme.metrics.kSpace12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: AppTheme.metrics.radius8,
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange, size: AppTheme.metrics.iconSize20),
                  SizedBox(width: AppTheme.metrics.kSpace8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '是否同时删除已录制的文件？',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: AppTheme.metrics.fontSize11,
                          ),
                        ),
                        SizedBox(height: AppTheme.metrics.kSpace4),
                        Text(
                          '文件大小：$fileSize',
                          style: TextStyle(
                            fontSize: AppTheme.metrics.fontSize11,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('仅删除任务')),
        if (hasFile)
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('删除任务和文件'),
          )
        else
          FilledButton(onPressed: () => Navigator.pop(context, false), child: const Text('确定')),
      ],
    ),
  );
}

/// 显示批量删除确认对话框
Future<bool?> showBatchDeleteDialog(BuildContext context, int count) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('批量删除'),
      content: Text('确定要删除 $count 个录制任务吗？'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          child: const Text('确定'),
        ),
      ],
    ),
  );
}

/// 显示重新录制确认对话框
Future<bool?> showReRecordDialog(BuildContext context, String taskName, bool isCompleted) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.refresh, color: Colors.orange),
          SizedBox(width: AppTheme.metrics.kSpace8),
          const Text('确认重新录制'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('确定要重新录制"$taskName"吗？'),
          SizedBox(height: AppTheme.metrics.kSpace8),
          if (isCompleted)
            Text(
              '原有录制文件将被覆盖',
              style: TextStyle(color: Colors.orange, fontSize: AppTheme.metrics.fontSize11),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('确定')),
      ],
    ),
  );
}

/// 显示视频预览对话框
void showVideoPreview(BuildContext context, String taskName) {
  showDialog(
    context: context,
    builder: (context) => Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
        child: Column(
          children: [
            AppBar(
              title: Text(taskName),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.play_circle_outline, size: AppTheme.metrics.iconSize64),
                    SizedBox(height: AppTheme.metrics.kSpace16),
                    Text('视频预览功能待实现', style: Theme.of(context).textTheme.bodyLarge),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 引导步骤组件
class _GuideStep extends StatelessWidget {
  final String number;
  final String text;

  const _GuideStep({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: AppTheme.metrics.kSpace4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: AppTheme.metrics.kSpace24,
            height: AppTheme.metrics.kSpace24,
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              number,
              style: TextStyle(
                color: Colors.white,
                fontSize: AppTheme.metrics.fontSize11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(width: AppTheme.metrics.kSpace12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: AppTheme.metrics.kSpace2),
              child: Text(text, style: TextStyle(fontSize: AppTheme.metrics.fontSize13)),
            ),
          ),
        ],
      ),
    );
  }
}
