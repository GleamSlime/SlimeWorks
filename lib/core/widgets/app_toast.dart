library;

import 'package:flutter/material.dart';

import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';

/// 轻提示（Toast）
///
/// 报错原先有两种难看的样子：把异常原文整段铺在页面上，或各处手写一条
/// 时长/样式都不一致的 SnackBar。这里收敛成一条：浮层、语义图标、一句话，
/// 驻留时长走 `AppMotion` 的 dwell 档（§5.2）。
///
/// 弹层（Dialog / Sheet）里别用：SnackBar 画在页面 Scaffold 上，会被弹层挡住，
/// 那种场景仍用弹层内的行内提示。
class AppToast {
  AppToast._();

  /// 错误轻提示
  static void error(BuildContext context, String message, {Duration? duration}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      errorBar(AppSemantic.of(context), message, duration: duration),
    );
  }

  /// 错误提示条本体
  ///
  /// 单独暴露给"已经跨过异步间隙、只剩 messenger 可用"的调用点：
  /// 那类代码在 await 前就把语义快照取好了，不能再摸 context。
  static SnackBar errorBar(
    AppSemantic s,
    String message, {
    Duration? duration,
    SnackBarAction? action,
  }) => _bar(
    s,
    s.danger.color,
    StrokeIcons.errorOutline,
    message,
    duration ?? AppMotion.dwellLong,
    action: action,
  );

  static SnackBar _bar(
    AppSemantic s,
    Color color,
    StrokeIcon icon,
    String message,
    Duration duration, {
    SnackBarAction? action,
  }) {
    return SnackBar(
      duration: duration,
      action: action,
      // 一条提示只说一件事，读不完的就截断，别让它变成第二个错误详情页
      content: Row(
        children: [
          DrawIcon(icon, size: AppTheme.metrics.iconSize16, color: color),
          SizedBox(width: AppTheme.metrics.kSpace8),
          Expanded(
            child: Text(message, maxLines: 3, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
