import 'package:material_ui/material_ui.dart';

import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';

/// 内联错误提示条：把「读取失败的原因」直接显示在页面上。
///
/// 为什么需要它：阿里云 / 电力统计 / 日志中心这批页面的远程读取此前全是
/// `catch (_) {}`，错误只进日志。节点连不上、授权码错、节点模块未初始化，
/// 在用户眼里一律变成「空列表 / 全 0 的空图表」，被误导成「功能还没接好」。
/// 数据为空和加载失败是两件完全不同的事，必须能区分。
///
/// 用法：调用方在 `Obx` 里读到底层 VM 的 errorMessage，非空时渲染本组件。
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel = '重试',
  });

  /// 错误原文（一般就是 `'读取xxx失败: $e'`）
  final String message;

  /// 给了就显示重试按钮
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    if (message.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      margin: EdgeInsets.only(bottom: m.kSpace12),
      padding: EdgeInsets.symmetric(
        horizontal: m.kSpace16,
        vertical: m.kSpace12,
      ),
      decoration: BoxDecoration(
        color: s.danger.container,
        borderRadius: m.radius12,
        border: Border.all(color: s.danger.containerBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: m.kSpace2),
            child: DrawIcon(
              StrokeIcons.errorOutline,
              size: m.iconSize18,
              color: s.danger.color,
            ),
          ),
          SizedBox(width: m.kSpace12),
          Expanded(
            child: SelectableText(
              message,
              style: AppTextStyles.role(
                context,
                fontSize: m.fontSize13,
                color: s.danger.color,
                height: 1.5,
              ),
            ),
          ),
          if (onRetry != null) ...[
            SizedBox(width: m.kSpace12),
            TextButton(
              onPressed: onRetry,
              child: Text(retryLabel),
            ),
          ],
        ],
      ),
    );
  }
}
