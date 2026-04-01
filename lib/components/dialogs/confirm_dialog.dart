import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 统一的二次确认弹窗。
///
/// - 支持 Enter 键快捷确认（等同于点击「确认」按钮）
/// - 支持自定义按钮颜色（危险操作可传 [confirmColor] = error）
/// - 通过 [showConfirmDialog] 工具函数调用，返回 `true` 表示用户确认
class ConfirmDialog extends StatefulWidget {
  const ConfirmDialog({
    super.key,
    required this.title,
    this.message,
    this.confirmLabel = '确认',
    this.cancelLabel = '取消',
    this.confirmColor,
  });

  final String title;
  final String? message;
  final String confirmLabel;
  final String cancelLabel;
  final Color? confirmColor;

  @override
  State<ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<ConfirmDialog> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _confirm() => Navigator.of(context).pop(true);
  void _cancel() => Navigator.of(context).pop(false);

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.enter) {
          _confirm();
        }
      },
      child: AlertDialog(
        title: Text(widget.title),
        content: widget.message != null ? Text(widget.message!) : null,
        actions: [
          TextButton(
            onPressed: _cancel,
            child: Text(widget.cancelLabel),
          ),
          FilledButton(
            onPressed: _confirm,
            style: widget.confirmColor != null
                ? FilledButton.styleFrom(backgroundColor: widget.confirmColor)
                : null,
            child: Text(widget.confirmLabel),
          ),
        ],
      ),
    );
  }
}

/// 显示统一二次确认弹窗，返回 `true` 表示用户点击了确认（或按下 Enter）。
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = '确认',
  String cancelLabel = '取消',
  Color? confirmColor,
}) async {
  return await showDialog<bool>(
    context: context,
    builder: (ctx) => ConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      confirmColor: confirmColor,
    ),
  ) ??
      false;
}
