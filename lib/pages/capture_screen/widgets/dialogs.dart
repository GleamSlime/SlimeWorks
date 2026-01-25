import 'package:flutter/material.dart';

/// 显示密码输入对话框
Future<String?> showPasswordDialog(BuildContext context) async {
  final passwordController = TextEditingController(text: '');
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Row(children: [Icon(Icons.security, size: 24), SizedBox(width: 8), Text('安装CA证书')]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('需要管理员密码来安装CA证书到系统钥匙串。'),
          const SizedBox(height: 8),
          const Text('这是HTTPS流量捕获所必需的步骤。', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 16),
          TextField(
            controller: passwordController,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: '管理员密码', border: OutlineInputBorder(), prefixIcon: Icon(Icons.lock)),
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, passwordController.text), child: const Text('确定')),
      ],
    ),
  );
}

/// 显示信任证书引导对话框
void showTrustCertificateGuide(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Row(children: [Icon(Icons.verified_user, size: 24), SizedBox(width: 8), Text('信任CA证书')]),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('证书已安装到系统钥匙串，请按以下步骤信任证书：'),
            const SizedBox(height: 16),
            _GuideStep(number: '1', text: '打开"钥匙串访问"应用'),
            _GuideStep(number: '2', text: '在"系统"钥匙串中找到"SlimeWorks CA"证书'),
            _GuideStep(number: '3', text: '双击证书，展开"信任"部分'),
            _GuideStep(number: '4', text: '将"使用此证书时"设置为"始终信任"'),
            _GuideStep(number: '5', text: '关闭窗口并输入密码确认'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue, size: 20),
                  SizedBox(width: 8),
                  Expanded(child: Text('只有信任证书后才能捕获HTTPS流量', style: TextStyle(fontSize: 12))),
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
Future<bool?> showDeleteTaskDialog(BuildContext context, String taskName, bool hasFile, String? fileSize) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.warning_amber, color: Colors.orange),
          SizedBox(width: 8),
          Text('确认删除'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('确定要删除录制任务"$taskName"吗？'),
          const SizedBox(height: 16),
          if (hasFile)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('是否同时删除已录制的文件？', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text('文件大小：$fileSize', style: const TextStyle(fontSize: 11, color: Colors.grey)),
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
      title: const Row(
        children: [
          Icon(Icons.refresh, color: Colors.orange),
          SizedBox(width: 8),
          Text('确认重新录制'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('确定要重新录制"$taskName"吗？'),
          const SizedBox(height: 8),
          if (isCompleted) const Text('原有录制文件将被覆盖', style: TextStyle(color: Colors.orange, fontSize: 12)),
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
              actions: [IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))],
            ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.play_circle_outline, size: 64),
                    const SizedBox(height: 16),
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(color: Theme.of(context).primaryColor, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(
              number,
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(text, style: const TextStyle(fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }
}
