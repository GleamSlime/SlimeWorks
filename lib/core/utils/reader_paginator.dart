import 'package:flutter/painting.dart';

/// 把一段长正文按「可视区域 + 排版样式」切成若干页。
///
/// ═══════════════════════════════════════════════════════════════════════════
/// 为什么要自己切页
/// ═══════════════════════════════════════════════════════════════════════════
/// 微信读书那类阅读器是**分页**的：左右滑动翻页、底部显示「3/12」，
/// 而不是一条长列表上下滚。分页必须知道「这段文字在给定宽高下能排几行、
/// 每行多高」，这只有 `TextPainter` 能算准（中英混排、标点避头尾、
/// 行高 1.8 这类都不能用字数估算）。
///
/// ═══════════════════════════════════════════════════════════════════════════
/// 实现要点（踩过的坑）
/// ═══════════════════════════════════════════════════════════════════════════
/// 1. `LineMetrics` **不带字符索引**，所以不能直接拿行号换算切点。
/// 2. 用「上一行末尾坐标去 getPositionForOffset」推算切点会偏一行，
///    实测会出现某页高度 609 > 页高 600（渲染时被裁）。
/// 3. 可靠做法：**按整段排一次版，再从第一行开始一行行累加高度**，
///    累加到超过页高就把这一行**之前**的字符全部归为一页。
///    切点用「该行首字符」的偏移，由 `getPositionForOffset` 在该行
///    垂直中心、x=0 处取得——这个位置稳定落在行首。
/// 4. 最后用「拼回去等于原文」做兜底校验：万一某个切点算错，
///    宁可退化成整段一页，也不要静默丢字。
/// ═══════════════════════════════════════════════════════════════════════════
class ReaderPaginator {
  /// 把 [text] 切成每页一个字符串。
  ///
  /// - [size]：正文可视区域尺寸（已扣掉工具栏/安全区/内边距）
  /// - [style]：与最终渲染**完全一致**的文字样式（字号/行高/字族都要一致，
  ///   否则算出的换行与真实渲染不符，页面会出现半行或大段空白）
  /// - [textScale]：系统字体缩放因子
  ///
  /// 返回至少一页；空文本返回 `['']`，让 UI 不用处理空列表。
  static List<String> paginate({
    required String text,
    required Size size,
    required TextStyle style,
    double textScale = 1.0,
  }) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (normalized.isEmpty) return <String>[''];
    if (size.width <= 0 || size.height <= 0) return <String>[normalized];

    final painter = TextPainter(
      text: TextSpan(text: normalized, style: style),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.linear(textScale),
    )..layout(maxWidth: size.width);

    final metrics = painter.computeLineMetrics();
    if (metrics.isEmpty) {
      painter.dispose();
      return <String>[normalized];
    }

    // 每行的 (首字符偏移, 行顶 y, 行底 y)
    final lineStart = <int>[];
    final lineTop = <double>[];
    final lineBottom = <double>[];
    var cursor = 0;
    for (final m in metrics) {
      // 在该行垂直中心、x≈0 处取字符位置 → 稳定落在行首
      final probeY = m.baseline - m.ascent + m.height * 0.5;
      var off = painter.getPositionForOffset(Offset(0.5, probeY)).offset;
      // 防御：位置不得回退（宽字符/连字可能给出更早的偏移）
      if (off < cursor) off = cursor;
      if (off > normalized.length) off = normalized.length;
      lineStart.add(off);
      lineTop.add(m.baseline - m.ascent);
      lineBottom.add(m.baseline + m.descent);
      cursor = off;
    }
    // 行首偏移必须是单调递增的；否则说明探测不可靠，退化成整段一页
    for (var i = 1; i < lineStart.length; i++) {
      if (lineStart[i] < lineStart[i - 1]) {
        painter.dispose();
        return <String>[normalized];
      }
    }

    final pages = <String>[];
    var pageFirstLine = 0;
    for (var i = 0; i < metrics.length; i++) {
      final pageTopY = lineTop[pageFirstLine];
      // 这一行放进来后是否超页
      final overflow = (lineBottom[i] - pageTopY) > size.height + 0.5;
      if (overflow && i > pageFirstLine) {
        // i 是放不下的那一行 → 【pageFirstLine, i) 归为一页
        final startOff = lineStart[pageFirstLine];
        final endOff = lineStart[i];
        if (endOff > startOff) {
          pages.add(normalized.substring(startOff, endOff).trimRight());
          pageFirstLine = i;
        }
      }
    }
    // 收尾
    final tailStart = lineStart[pageFirstLine];
    if (tailStart < normalized.length) {
      pages.add(normalized.substring(tailStart).trimRight());
    }
    if (pages.isEmpty) pages.add(normalized);

    painter.dispose();

    // 兜底校验：拼回去必须与原文一致（去空白）。不一致就退化成整段一页，
    // 宁可翻页体验差一点，也绝不静默丢字。
    final rejoined = pages.join('').replaceAll(RegExp(r'\s'), '');
    final expected = normalized.replaceAll(RegExp(r'\s'), '');
    if (rejoined != expected) {
      return <String>[normalized];
    }
    return pages;
  }

  /// 估算一页能放多少行（仅用于日志/调试，切页以 [paginate] 为准）
  static int estimateLinesPerPage({
    required Size size,
    required TextStyle style,
    double textScale = 1.0,
  }) {
    final probe = TextPainter(
      text: TextSpan(text: '字', style: style),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.linear(textScale),
    )..layout();
    final lineHeight = probe.height;
    probe.dispose();
    if (lineHeight <= 0) return 0;
    return (size.height / lineHeight).floor();
  }
}
