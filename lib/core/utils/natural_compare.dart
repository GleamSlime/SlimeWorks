/// 自然序比较工具。
///
/// 与纯字典序（[String.compareTo]）不同，自然序将字符串中的连续数字段
/// 按数值比较，其余字符忽略大小写逐字符比较。
/// 例：`XXX(9)` < `XXX(10)` < `XXX(100)` < `XXX(101)`，
/// 而字典序会错误地排成 `XXX(10)` < `XXX(100)` < `XXX(11)`。
library;

bool _isDigit(int code) => code >= 0x30 && code <= 0x39;

/// ASCII 字母统一转小写码元，其余字符原样返回。
int _toLowerAscii(int code) {
  if (code >= 0x41 && code <= 0x5A) return code + 0x20;
  return code;
}

/// 按自然序比较两个字符串，返回值语义与 [Comparable.compareTo] 一致：
/// 负数 = [a] 在前，0 = 相等，正数 = [b] 在前。
int naturalCompare(String a, String b) {
  int ia = 0;
  int ib = 0;
  while (ia < a.length && ib < b.length) {
    final ca = a.codeUnitAt(ia);
    final cb = b.codeUnitAt(ib);
    final da = _isDigit(ca);
    final db = _isDigit(cb);
    if (da && db) {
      // 两侧均为数字段：按数值比较（先剥离前导零，再比有效位数，最后逐位比）
      int ea = ia;
      int eb = ib;
      while (ea < a.length && _isDigit(a.codeUnitAt(ea))) {
        ea++;
      }
      while (eb < b.length && _isDigit(b.codeUnitAt(eb))) {
        eb++;
      }
      int sa = ia;
      int sb = ib;
      while (sa < ea - 1 && a.codeUnitAt(sa) == 0x30) {
        sa++;
      }
      while (sb < eb - 1 && b.codeUnitAt(sb) == 0x30) {
        sb++;
      }
      final lenA = ea - sa;
      final lenB = eb - sb;
      if (lenA != lenB) return lenA - lenB;
      for (int i = 0; i < lenA; i++) {
        final diff = a.codeUnitAt(sa + i) - b.codeUnitAt(sb + i);
        if (diff != 0) return diff;
      }
      ia = ea;
      ib = eb;
    } else {
      // 非数字字符：忽略大小写逐字符比较
      final diff = _toLowerAscii(ca) - _toLowerAscii(cb);
      if (diff != 0) return diff;
      ia++;
      ib++;
    }
  }
  // 前缀相同时较短者在前，长度相同则视为相等
  return (a.length - ia) - (b.length - ib);
}
