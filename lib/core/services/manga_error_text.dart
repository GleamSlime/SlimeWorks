library;

/// Manga 接口异常的用户可读文案
///
/// 上游（Rust 侧 `MangaError`）抛出来的是带 `caused by:` 链的一长串，
/// 例如 `网络错误: error sending request for url (...) caused by: client error (Connect)`。
/// 原样铺到界面上就是几十行英文，既读不下去也盖住了正文，所以统一先翻成一句话：
/// 命中已知类别就给"用户下一步能做什么"的短句，其余截断成一行。
/// 完整原文由调用方写日志，界面上不留堆栈。
class MangaErrorText {
  MangaErrorText._();

  /// 单条提示能占的字符数，超出就截断（省略号另计）
  static const int maxLength = 48;

  /// 关键字 → 提示语。按顺序匹配，先具体后宽泛。
  static const List<(List<String>, String)> _rules = [
    (['未登录', 'token', '401', 'unauthorized'], '登录已过期，请重新登录'),
    (['超时', 'timed out', 'timeout'], '请求超时，可切换分流节点后重试'),
    (['解析', 'parse', 'json'], '数据解析失败，请重试'),
    (['403', 'forbidden'], '没有访问权限，请重新登录'),
    (['404', 'not found'], '内容不存在或已下架'),
    (['429', 'too many'], '请求太频繁，稍后再试'),
    (['500', '502', '503', 'server'], '服务器繁忙，稍后再试'),
    (['certificate', 'tls', 'ssl'], '证书校验失败，可能被网络拦截'),
    (['resolve', 'dns', '域名'], '域名解析失败，请检查网络'),
    (['connect', 'refused', 'unreachable', '不可达'], '连不上服务器，试试切换分流节点'),
  ];

  /// 把任意异常翻成一句界面提示
  static String describe(Object error) {
    final raw = error
        .toString()
        // FRB 抛出来的是 Exception/自定义 Error，前缀对使用者没有意义
        .replaceFirst(RegExp(r'^\w*(Exception|Error):\s*'), '')
        // 一条提示就占一行：换行/制表/回车一律压成空格
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (raw.isEmpty) return '操作失败，请稍后重试';

    final lower = raw.toLowerCase();
    for (final (keywords, text) in _rules) {
      if (keywords.any(lower.contains)) return text;
    }
    return raw.length <= maxLength ? raw : '${raw.substring(0, maxLength)}…';
  }
}
