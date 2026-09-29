// 流水账纯 Dart 数据模型与日期/金额 helper 的单测。
//
// 目标不是"能跑通"，而是把边界钉死：跨年、闰年月末、千分位与二进制浮点四舍五入、
// 非法输入的实际回落值，以及"空串/0 到底算不算筛选"这类很容易被 UI 误用的判定。
// 所有断言描述的都是**当前实现的行为**；其中带「现状锁定」注释的条目是已知怪癖，
// 一旦生产代码改了口径，这里的失败就是提醒，不是测试写错了。
//
// 样例数据一律脱敏：假尾号 0000、假金额 12.34、假商户「测试商户」。
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/pages/ledger/models/ledger_models.dart';

// ── 辅助：与运行时刻无关的相对日期 ──────────────────────────────────────────

String _two(int v) => v.toString().padLeft(2, '0');

/// `yyyy-MM-dd` 形态的"今天"
String _today() {
  final DateTime now = DateTime.now();
  return '${now.year}-${_two(now.month)}-${_two(now.day)}';
}

/// 相对今天偏移 [delta] 天的 `yyyy-MM-dd`（用 DateTime 构造器归一，避开 Duration 的时区坑）
String _dateAfterToday(int delta) {
  final DateTime now = DateTime.now();
  final DateTime d = DateTime(now.year, now.month, now.day + delta);
  return '${d.year}-${_two(d.month)}-${_two(d.day)}';
}

/// `_dateAfterToday` 对应的「M月D日」展示串
String _mdLabel(int delta) {
  final DateTime now = DateTime.now();
  final DateTime d = DateTime(now.year, now.month, now.day + delta);
  return '${d.month}月${d.day}日';
}

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // ledgerMonthOf
  // ══════════════════════════════════════════════════════════════════════════

  group('ledgerMonthOf', () {
    test('月份补零到两位', () {
      expect(ledgerMonthOf(DateTime(2026, 1, 5)), '2026-01');
      expect(ledgerMonthOf(DateTime(2026, 9, 30)), '2026-09');
      expect(ledgerMonthOf(DateTime(2026, 12, 1)), '2026-12');
    });

    test('只看年月，忽略日与时分秒（月末/年末最后一秒仍属当月）', () {
      expect(ledgerMonthOf(DateTime(2026, 2, 28)), '2026-02');
      expect(ledgerMonthOf(DateTime(2026, 12, 31, 23, 59, 59, 999)), '2026-12');
    });

    test('与 ledgerMonthShift(…, 0) 对同一个月的输出一致', () {
      final DateTime d = DateTime(2026, 7, 15);
      expect(ledgerMonthShift(ledgerMonthOf(d), 0), ledgerMonthOf(d));
    });

    test('现状锁定：年份不足 4 位时不补零，产物不是 4 位年月', () {
      expect(ledgerMonthOf(DateTime(999, 1, 1)), '999-01');
      // 回读没问题：ledgerMonthShift 用的是 int.tryParse，不要求定长
      expect(ledgerMonthShift('999-01', 1), '999-02');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // ledgerMonthShift
  // ══════════════════════════════════════════════════════════════════════════

  group('ledgerMonthShift - 跨年与越界', () {
    test('1 月往前一个月要退到上一年 12 月', () {
      expect(ledgerMonthShift('2026-01', -1), '2025-12');
      expect(ledgerMonthShift('2026-01', -2), '2025-11');
      expect(ledgerMonthShift('2026-02', -1), '2026-01');
    });

    test('12 月往后一个月要进到下一年 1 月', () {
      expect(ledgerMonthShift('2025-12', 1), '2026-01');
      expect(ledgerMonthShift('2025-11', 2), '2026-01');
    });

    test('跨多年/跨 12 个月以上', () {
      expect(ledgerMonthShift('2026-01', -13), '2024-12');
      expect(ledgerMonthShift('2026-12', 13), '2028-01');
      expect(ledgerMonthShift('2026-01', 12), '2027-01');
      expect(ledgerMonthShift('2026-06', -6), '2025-12');
    });

    test('delta 0 仍然是归一化，不是原样返回', () {
      expect(ledgerMonthShift('2026-01', 0), '2026-01');
      // 越界月份被 DateTime 归一：13 月 = 次年 1 月，0 月 = 上年 12 月
      expect(ledgerMonthShift('2026-13', 0), '2027-01');
      expect(ledgerMonthShift('2026-00', 0), '2025-12');
      // 月份不补零的输入也能读回来
      expect(ledgerMonthShift('2026-1', 1), '2026-02');
    });

    test('12 个月逐一验证 +1/-1 往返回到原月', () {
      for (var m = 1; m <= 12; m++) {
        final String month = '2026-${_two(m)}';
        expect(ledgerMonthShift(ledgerMonthShift(month, 1), -1), month, reason: month);
        expect(ledgerMonthShift(ledgerMonthShift(month, -1), 1), month, reason: month);
      }
    });

    test('游标连续走一年回到起点（页面上"下一月"点 12 次）', () {
      String cursor = '2026-01';
      for (var i = 0; i < 12; i++) {
        cursor = ledgerMonthShift(cursor, 1);
      }
      expect(cursor, '2027-01');
    });

    test('现状锁定：月份段缺失/非法时回落到"当前月"，不抛异常', () {
      // 竞态说明：这里与 DateTime.now() 比较，只有在跨月瞬间（每月 1 日 00:00:00）才会误判，
      // 概率可忽略；若真要消除竞态，需要把 now 变成可注入参数（见报告的注入点清单）。
      expect(ledgerMonthShift('abc', 0), ledgerMonthOf(DateTime.now()));
      expect(ledgerMonthShift('', 1), ledgerMonthShift(ledgerMonthOf(DateTime.now()), 1));
      expect(ledgerMonthShift('2026', 0), ledgerMonthOf(DateTime.now()));
      expect(ledgerMonthShift('2026-xyz', 0), ledgerMonthOf(DateTime.now()));
      expect(ledgerMonthShift('abc', 0), matches(r'^\d{4}-\d{2}$'));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // ledgerMonthStart / ledgerMonthEnd
  // ══════════════════════════════════════════════════════════════════════════

  group('ledgerMonthStart', () {
    test('就是字符串拼接，不校验输入', () {
      expect(ledgerMonthStart('2026-02'), '2026-02-01');
      expect(ledgerMonthStart('2026-12'), '2026-12-01');
      // 现状锁定：垃圾进垃圾出，产出的仍是可用字符串（'-01' 不是合法日期）
      expect(ledgerMonthStart('abc'), 'abc-01');
      expect(ledgerMonthStart(''), '-01');
    });

    test('产物可被 DateTime.parse 接受（合法输入下）', () {
      expect(DateTime.parse(ledgerMonthStart('2026-02')), DateTime(2026, 2, 1));
    });
  });

  group('ledgerMonthEnd - 闰年与大小月', () {
    test('2 月：普通闰年 29 天、平年 28 天', () {
      expect(ledgerMonthEnd('2024-02'), '2024-02-29');
      expect(ledgerMonthEnd('2028-02'), '2028-02-29');
      expect(ledgerMonthEnd('2023-02'), '2023-02-28');
      expect(ledgerMonthEnd('2026-02'), '2026-02-28');
    });

    test('世纪年：400 倍数闰、100 倍数不闰', () {
      expect(ledgerMonthEnd('2000-02'), '2000-02-29');
      expect(ledgerMonthEnd('1900-02'), '1900-02-28');
      expect(ledgerMonthEnd('2100-02'), '2100-02-28');
    });

    test('大月 31、小月 30', () {
      expect(ledgerMonthEnd('2026-01'), '2026-01-31');
      expect(ledgerMonthEnd('2026-03'), '2026-03-31');
      expect(ledgerMonthEnd('2026-04'), '2026-04-30');
      expect(ledgerMonthEnd('2026-06'), '2026-06-30');
      expect(ledgerMonthEnd('2026-09'), '2026-09-30');
      expect(ledgerMonthEnd('2026-11'), '2026-11-30');
    });

    test('12 月不会跑到下一年（"下个月第 0 天"写法的关键回归点）', () {
      expect(ledgerMonthEnd('2026-12'), '2026-12-31');
      expect(ledgerMonthEnd('2025-12'), '2025-12-31');
    });

    test('全年 12 个月与 DateTime 的权威结果逐月对齐', () {
      for (final int y in <int>[2024, 2026]) {
        for (var m = 1; m <= 12; m++) {
          final String month = '$y-${_two(m)}';
          final int expectedLastDay = DateTime(y, m + 1, 0).day;
          expect(ledgerMonthEnd(month), '$month-$expectedLastDay', reason: month);
          // 月末当天必须仍落在该月内
          final DateTime parsed = DateTime.parse(ledgerMonthEnd(month));
          expect(parsed.year, y, reason: month);
          expect(parsed.month, m, reason: month);
        }
      }
    });

    test('现状锁定：非法输入回落默认年月，且前缀原样保留', () {
      // 缺省按 1970-01 计算，但返回串保留调用方传进来的垃圾月份
      expect(ledgerMonthEnd('abc'), 'abc-31');
      expect(ledgerMonthEnd(''), '-31'); // '' 解析失败 → 1970-01 → 1 月末 31 天
      expect(ledgerMonthEnd('2026-2'), '2026-2-28'); // 不补零
      expect(ledgerMonthEnd('2026-13'), '2026-13-31'); // 天数按次年 2 月前一天算，串本身非法
      expect(ledgerMonthEnd('2026-00'), '2026-00-31');
    });

    test('月末与次月月初相差一天（区间闭合性检查）', () {
      final DateTime end = DateTime.parse(ledgerMonthEnd('2026-01'));
      final DateTime nextStart = DateTime.parse(ledgerMonthStart('2026-02'));
      expect(nextStart.difference(end).inDays, 1);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // formatLedgerAmount
  // ══════════════════════════════════════════════════════════════════════════

  group('formatLedgerAmount - 基本形态', () {
    test('0 与负零都输出 0.00（不带符号时）', () {
      expect(formatLedgerAmount(0), '0.00');
      expect(formatLedgerAmount(0.0), '0.00');
      expect(formatLedgerAmount(-0.0), '0.00');
    });

    test('两位小数恒定补齐', () {
      expect(formatLedgerAmount(12.34), '12.34');
      expect(formatLedgerAmount(10), '10.00');
      expect(formatLedgerAmount(1234.5), '1,234.50');
      expect(formatLedgerAmount(0.1), '0.10');
    });

    test('千分位：三位以内不加逗号，四位起加分隔', () {
      expect(formatLedgerAmount(999), '999.00');
      expect(formatLedgerAmount(1000), '1,000.00');
      expect(formatLedgerAmount(9999), '9,999.00');
      expect(formatLedgerAmount(10000), '10,000.00');
      expect(formatLedgerAmount(999999), '999,999.00');
      expect(formatLedgerAmount(1000000), '1,000,000.00');
      expect(formatLedgerAmount(12345678), '12,345,678.00');
    });

    test('负数只取绝对值，符号交给调用方（金额正数存储的口径）', () {
      expect(formatLedgerAmount(-12.34), '12.34');
      expect(formatLedgerAmount(-1234.5), '1,234.50');
    });
  });

  group('formatLedgerAmount - 四舍五入', () {
    test('常规舍入', () {
      expect(formatLedgerAmount(1234.567), '1,234.57');
      expect(formatLedgerAmount(1234.561), '1,234.56');
      expect(formatLedgerAmount(0.001), '0.00');
      expect(formatLedgerAmount(1234567890.125), '1,234,567,890.13');
    });

    test('进位跨整数与跨千分位', () {
      expect(formatLedgerAmount(9.999), '10.00');
      expect(formatLedgerAmount(999.999), '1,000.00');
      expect(formatLedgerAmount(999999.999), '1,000,000.00');
    });

    test('现状锁定：二进制浮点决定了"看起来该进位的数"实际不进位', () {
      // 2.675 / 0.995 在 double 里略小于十进制真值，toStringAsFixed 会向下截断；
      // 而 0.005 / -1000.005 略大或恰在边界，会向上。这是 Dart 的既定行为，
      // 任何"金额四舍五入"的 UI 断言都必须按此口径写。
      expect(formatLedgerAmount(2.675), '2.67');
      expect(formatLedgerAmount(0.995), '0.99');
      expect(formatLedgerAmount(0.005), '0.01');
      expect(formatLedgerAmount(-1000.005), '1,000.00');
      expect(formatLedgerAmount(0.1 + 0.2), '0.30');
    });
  });

  group('formatLedgerAmount - withSign', () {
    test('支出为负、收入为正', () {
      expect(formatLedgerAmount(12.34, withSign: true), '-12.34');
      expect(formatLedgerAmount(12.34, withSign: true, income: true), '+12.34');
      expect(formatLedgerAmount(1234.5, withSign: true, income: true), '+1,234.50');
    });

    test('现状锁定：符号只看 income 参数，与数值自身正负无关', () {
      expect(formatLedgerAmount(-12.34, withSign: true, income: true), '+12.34');
      expect(formatLedgerAmount(-12.34, withSign: true), '-12.34');
    });

    test('现状锁定：0 元加支出符号会得到 "-0.00"', () {
      expect(formatLedgerAmount(0, withSign: true), '-0.00');
      expect(formatLedgerAmount(0, withSign: true, income: true), '+0.00');
      // 0.001 同样会被渲染成 -0.00，UI 若不想显示要自己挡掉
      expect(formatLedgerAmount(0.001, withSign: true), '-0.00');
    });

    test('withSign=false 时永远没有符号（含负数）', () {
      expect(formatLedgerAmount(-12.34, income: true), '12.34');
    });
  });

  group('formatLedgerAmount - 极端值', () {
    test('现状锁定：1e20 仍可格式化，1e21 起 toStringAsFixed 转科学计数法后越界抛错', () {
      expect(formatLedgerAmount(1e20), '100,000,000,000,000,000,000.00');
      expect(() => formatLedgerAmount(1e21), throwsRangeError);
      expect(() => formatLedgerAmount(double.infinity), throwsRangeError);
      expect(() => formatLedgerAmount(double.negativeInfinity), throwsRangeError);
      expect(() => formatLedgerAmount(double.nan), throwsRangeError);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // ledgerDateLabel
  // ══════════════════════════════════════════════════════════════════════════

  group('ledgerDateLabel', () {
    test('今天/昨天/前天', () {
      expect(ledgerDateLabel(_today()), '今天');
      expect(ledgerDateLabel(_dateAfterToday(0)), '今天');
      expect(ledgerDateLabel(_dateAfterToday(-1)), '昨天');
      expect(ledgerDateLabel(_dateAfterToday(-2)), '前天');
    });

    test('3 天前起改为「M月D日」，且月日不补零', () {
      expect(ledgerDateLabel(_dateAfterToday(-3)), _mdLabel(-3));
      expect(ledgerDateLabel(_dateAfterToday(-30)), _mdLabel(-30));
    });

    test('未来日期不落进今天/昨天/前天，同样给「M月D日」', () {
      expect(ledgerDateLabel(_dateAfterToday(1)), _mdLabel(1));
      expect(ledgerDateLabel(_dateAfterToday(365)), _mdLabel(365));
    });

    test('比较只看日粒度：带时分秒后缀不影响"今天"判定', () {
      expect(ledgerDateLabel('${_dateAfterToday(0)} 23:59'), '今天');
      expect(ledgerDateLabel('${_dateAfterToday(-1)} 00:01'), '昨天');
      expect(ledgerDateLabel('${_dateAfterToday(0)}T12:00:00'), '今天');
    });

    test('跨年只输出月日，不含年份信息（现状锁定：去年今天与今年同月同日无法区分）', () {
      final DateTime now = DateTime.now();
      final DateTime lastYear = DateTime(now.year - 1, now.month, now.day);
      expect(
        ledgerDateLabel('${lastYear.year}-${_two(lastYear.month)}-${_two(lastYear.day)}'),
        '${lastYear.month}月${lastYear.day}日',
      );
    });

    test('短于 10 字符直接原样返回，不解析', () {
      expect(ledgerDateLabel(''), '');
      expect(ledgerDateLabel('2026-9-1'), '2026-9-1'); // 合法但只 9 位 → 不美化
      expect(ledgerDateLabel('9月1日'), '9月1日');
    });

    test('长度够但解析失败也原样返回', () {
      expect(ledgerDateLabel('abcdefghij'), 'abcdefghij');
      expect(ledgerDateLabel('2026-13-45 10:00:00 附加说明'), '2026-13-45 10:00:00 附加说明');
    });

    test('现状锁定：越界月日不报错，被 DateTime 静默归一到另一个日期', () {
      // 2026-13-45 → 2027-02-14，标签只剩月日，调用方无法察觉输入本来就是脏的
      expect(ledgerDateLabel('2026-13-45'), '2月14日');
      expect(ledgerDateLabel('2026-02-30'), '3月2日');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // LedgerFilter：什么算"没筛选"
  // ══════════════════════════════════════════════════════════════════════════

  group('LedgerFilter.toJson', () {
    test('默认实例是空条件', () {
      expect(const LedgerFilter().toJson(), isEmpty);
      expect(const LedgerFilter().json, '{}');
    });

    test('空串字段一律省略（字符串条件用"非空"表示"已筛选"）', () {
      const LedgerFilter f = LedgerFilter(
        startDate: '',
        endDate: '',
        direction: '',
        source: '',
        status: '',
        keyword: '',
      );
      expect(f.toJson(), isEmpty);
    });

    test('值为 0 的 accountId/categoryId/limit/offset 视为未筛选', () {
      const LedgerFilter f = LedgerFilter(accountId: 0, categoryId: 0, limit: 0, offset: 0);
      expect(f.toJson(), isEmpty);
    });

    test('现状锁定：负数 id/limit/offset 也被当成"未筛选"静默丢弃，而不是报错', () {
      const LedgerFilter f = LedgerFilter(
        accountId: -1,
        categoryId: -2,
        limit: -5,
        offset: -9,
        direction: '',
      );
      expect(f.toJson(), isEmpty);
      // 但只要跨到正数就会下发
      expect(const LedgerFilter(accountId: 1).toJson(), <String, dynamic>{'account_id': 1});
      expect(const LedgerFilter(categoryId: 1).toJson(), <String, dynamic>{'category_id': 1});
      expect(const LedgerFilter(limit: 1).toJson(), <String, dynamic>{'limit': 1});
      expect(const LedgerFilter(offset: 1).toJson(), <String, dynamic>{'offset': 1});
    });

    test('全字段展开：键名与键序都被钉住（Rust 侧按这些 snake_case 读）', () {
      const LedgerFilter f = LedgerFilter(
        startDate: '2026-01-01',
        endDate: '2026-01-31',
        direction: 'expense',
        accountId: 3,
        categoryId: 4,
        source: 'email',
        status: 'posted',
        keyword: '测试商户',
        limit: 50,
        offset: 500,
      );
      expect(
        f.json,
        '{"start_date":"2026-01-01","end_date":"2026-01-31","direction":"expense",'
        '"account_id":3,"category_id":4,"source":"email","status":"posted",'
        '"keyword":"测试商户","limit":50,"offset":500}',
      );
    });

    test('单值条件：income / pending / ignored 都能原样透传', () {
      expect(const LedgerFilter(direction: 'income').toJson()['direction'], 'income');
      expect(const LedgerFilter(status: 'pending').toJson()['status'], 'pending');
      expect(const LedgerFilter(source: 'manual').toJson()['source'], 'manual');
    });
  });

  group('LedgerFilter.copyWith', () {
    test('不给的参数保持原值', () {
      const LedgerFilter f = LedgerFilter(startDate: '2026-01-01', limit: 10, keyword: 'abc');
      final LedgerFilter g = f.copyWith(categoryId: 7);
      expect(g.startDate, '2026-01-01');
      expect(g.limit, 10);
      expect(g.keyword, 'abc');
      expect(g.categoryId, 7);
      expect(g.accountId, 0);
    });

    test('无参 copyWith 等价于原条件', () {
      const LedgerFilter f = LedgerFilter(startDate: '2026-01-01', accountId: 2);
      expect(f.copyWith().json, f.json);
    });

    test('可以取消筛选：显式传空串/0 会覆盖原值（?? 语义只对 null 生效）', () {
      const LedgerFilter f = LedgerFilter(
        startDate: '2026-01-01',
        keyword: 'abc',
        accountId: 3,
        limit: 20,
      );
      final LedgerFilter cleared = f.copyWith(startDate: '', keyword: '', accountId: 0, limit: 0);
      expect(cleared.json, '{}');
    });

    test('分页只动 offset 时条件保持不变', () {
      const LedgerFilter f = LedgerFilter(accountId: 2, keyword: 'abc', limit: 20, offset: 0);
      final LedgerFilter page2 = f.copyWith(offset: 20);
      expect(page2.accountId, 2);
      expect(page2.keyword, 'abc');
      expect(page2.limit, 20);
      expect(page2.offset, 20);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 各模型 fromJson：默认值与容错
  // ══════════════════════════════════════════════════════════════════════════

  group('LedgerAccount.fromJson', () {
    test('缺字段走默认：信用卡 / CNY / 启用', () {
      final LedgerAccount a = LedgerAccount.fromJson(<String, dynamic>{});
      expect(a.id, 0);
      expect(a.name, '');
      expect(a.type, 'credit_card');
      expect(a.currency, 'CNY');
      expect(a.enabled, isTrue);
      expect(a.creditLimit, 0);
      expect(a.createdAt, '');
    });

    test('空串 type/currency 也回落默认（不是保留空串）', () {
      final LedgerAccount a = LedgerAccount.fromJson(
        <String, dynamic>{'type': '', 'currency': ''},
      );
      expect(a.type, 'credit_card');
      expect(a.currency, 'CNY');
    });

    test('enabled 只在键缺失时默认 true；数值 0 视为 false，字符串不被认作 true', () {
      expect(LedgerAccount.fromJson(<String, dynamic>{'enabled': false}).enabled, isFalse);
      expect(LedgerAccount.fromJson(<String, dynamic>{'enabled': 0}).enabled, isFalse);
      expect(LedgerAccount.fromJson(<String, dynamic>{'enabled': 1}).enabled, isTrue);
      // 现状锁定：'true' 字符串既不是 bool 也不是 num → false
      expect(LedgerAccount.fromJson(<String, dynamic>{'enabled': 'true'}).enabled, isFalse);
    });

    test('数值字段容忍字符串与坏字符串', () {
      final LedgerAccount a = LedgerAccount.fromJson(<String, dynamic>{
        'id': '42',
        'credit_limit': '1234.5',
        'balance': '12.34',
        'sort_order': '3',
      });
      expect(a.id, 42);
      expect(a.creditLimit, 1234.5);
      expect(a.balance, 12.34);
      expect(a.sortOrder, 3);
      // 整数位读不到小数串 → 0（现状锁定：不要把浮点串塞进 id）
      expect(LedgerAccount.fromJson(<String, dynamic>{'id': '12.34'}).id, 0);
    });

    test('displaySuffix：有尾号才拼"尾号"，空尾号返回空串', () {
      expect(const LedgerAccount(last4: '0000').displaySuffix, '尾号0000');
      expect(const LedgerAccount(last4: '').displaySuffix, '');
    });

    test('copyWith 保持 createdAt（该字段不可改）', () {
      final LedgerAccount a = LedgerAccount.fromJson(
        <String, dynamic>{'id': 1, 'name': '旧名', 'created_at': '2026-01-01 10:00:00'},
      );
      final LedgerAccount b = a.copyWith(name: '新名', balance: 12.34);
      expect(b.name, '新名');
      expect(b.balance, 12.34);
      expect(b.createdAt, '2026-01-01 10:00:00');
      expect(b.id, 1);
    });

    test('toJson 用 snake_case 且不含 created_at：往返后 createdAt 丢失（现状锁定）', () {
      final LedgerAccount a = LedgerAccount(
        id: 7,
        name: '测试卡',
        last4: '0000',
        creditLimit: 1000,
        balance: 12.34,
        createdAt: '2026-01-01 10:00:00',
      );
      expect(a.toJson()['credit_limit'], 1000);
      expect(a.toJson().containsKey('created_at'), isFalse);
      final LedgerAccount round = LedgerAccount.fromJson(a.toJson());
      expect(round.id, 7);
      expect(round.last4, '0000');
      expect(round.creditLimit, 1000);
      expect(round.createdAt, '');
    });
  });

  group('LedgerCategory.fromJson', () {
    test('direction 缺失或空串 → expense；isIncome 只在 income 时为真', () {
      expect(LedgerCategory.fromJson(<String, dynamic>{}).direction, kLedgerDirectionExpense);
      expect(LedgerCategory.fromJson(<String, dynamic>{'direction': ''}).direction, 'expense');
      expect(LedgerCategory.fromJson(<String, dynamic>{'direction': 'income'}).isIncome, isTrue);
      expect(LedgerCategory.fromJson(<String, dynamic>{'direction': 'income'}).direction, 'income');
    });

    test('is_builtin 走数值布尔容错', () {
      expect(LedgerCategory.fromJson(<String, dynamic>{'is_builtin': 1}).isBuiltin, isTrue);
      expect(LedgerCategory.fromJson(<String, dynamic>{'is_builtin': 0}).isBuiltin, isFalse);
      expect(LedgerCategory.fromJson(<String, dynamic>{}).isBuiltin, isFalse);
    });

    test('icon 原样保留（未知键也不清空，交给 ledgerIconOf 回落）', () {
      expect(LedgerCategory.fromJson(<String, dynamic>{'icon': 'whatever'}).icon, 'whatever');
    });

    test('copyWith 不改 id/isBuiltin', () {
      final LedgerCategory c = LedgerCategory.fromJson(<String, dynamic>{
        'id': 5,
        'name': '餐饮美食',
        'icon': 'restaurant',
        'is_builtin': 1,
      });
      final LedgerCategory d = c.copyWith(name: '吃饭', icon: 'coffee', sortOrder: 9);
      expect(d.id, 5);
      expect(d.isBuiltin, isTrue);
      expect(d.name, '吃饭');
      expect(d.icon, 'coffee');
      expect(d.sortOrder, 9);
      expect(d.direction, kLedgerDirectionExpense);
    });
  });

  group('LedgerTx.fromJson', () {
    test('缺字段默认：支出 / CNY / manual / posted', () {
      final LedgerTx t = LedgerTx.fromJson(<String, dynamic>{});
      expect(t.direction, kLedgerDirectionExpense);
      expect(t.currency, 'CNY');
      expect(t.source, kLedgerSourceManual);
      expect(t.status, kLedgerStatusPosted);
      expect(t.amount, 0);
    });

    test('空串字段同样回落默认，而不是保留空串', () {
      final LedgerTx t = LedgerTx.fromJson(<String, dynamic>{
        'direction': '',
        'currency': '',
        'source': '',
        'status': '',
      });
      expect(t.direction, 'expense');
      expect(t.currency, 'CNY');
      expect(t.source, 'manual');
      expect(t.status, 'posted');
    });

    test('amount 字符串可解析，pending/ignored 标志位正确', () {
      final LedgerTx t = LedgerTx.fromJson(<String, dynamic>{
        'amount': '12.34',
        'direction': 'income',
        'status': 'pending',
        'source': 'email',
      });
      expect(t.amount, 12.34);
      expect(t.isIncome, isTrue);
      expect(t.isPending, isTrue);
      expect(t.isIgnored, isFalse);
      expect(t.fromEmail, isTrue);
      expect(t.signedAmount, 12.34);
      expect(const LedgerTx(amount: 12.34).signedAmount, -12.34);
    });

    test('status=ignored 的三态互斥', () {
      final LedgerTx t = LedgerTx.fromJson(<String, dynamic>{'status': 'ignored'});
      expect(t.isIgnored, isTrue);
      expect(t.isPending, isFalse);
    });

    test('timeLabel 只在 occurred_at 够长时取 11..16 位，否则空串', () {
      expect(const LedgerTx(occurredAt: '2026-09-29 10:30:00').timeLabel, '10:30');
      expect(const LedgerTx(occurredAt: '2026-09-29T10:30:00').timeLabel, '10:30');
      expect(const LedgerTx(occurredAt: '2026-09-29 10:30').timeLabel, '10:30'); // 恰好 16 位
      expect(const LedgerTx(occurredAt: '2026-09-29 10:3').timeLabel, ''); // 15 位
      expect(const LedgerTx(occurredAt: '2026-09-29').timeLabel, '');
      expect(const LedgerTx().timeLabel, '');
    });

    test('dateLabel 优先 bill_date，为空时截 occurred_at 前 10 位', () {
      expect(const LedgerTx(billDate: '2026-08-01', occurredAt: '2026-09-29 10:30:00').dateLabel, '2026-08-01');
      expect(const LedgerTx(occurredAt: '2026-09-29 10:30:00').dateLabel, '2026-09-29');
    });

    test('现状锁定：bill_date 为空且 occurred_at 短于 10 位时 dateLabel 直接 RangeError', () {
      expect(() => const LedgerTx(occurredAt: '2026-09').dateLabel, throwsRangeError);
      expect(() => const LedgerTx().dateLabel, throwsRangeError);
    });

    test('occurredDateTime：空格/ISO 两种写法都能解析，坏值回落 bill_date 再回落 now', () {
      expect(const LedgerTx(occurredAt: '2026-09-29 10:30:00').occurredDateTime, DateTime(2026, 9, 29, 10, 30));
      expect(const LedgerTx(occurredAt: '2026-09-29T10:30:00').occurredDateTime, DateTime(2026, 9, 29, 10, 30));
      expect(const LedgerTx(occurredAt: '垃圾', billDate: '2026-08-01').occurredDateTime, DateTime(2026, 8, 1));
      // 两者都坏 → DateTime.now()
      final DateTime now = DateTime.now();
      final DateTime fallback = const LedgerTx(occurredAt: 'T', billDate: '垃圾').occurredDateTime;
      expect(fallback.difference(now).abs(), lessThan(const Duration(seconds: 5)));
    });

    test('occurred_at 里只替换第一个空格：多余空格解析失败时回落 bill_date', () {
      expect(
        const LedgerTx(occurredAt: '2026-09-29 10:30:00', billDate: '2026-08-01').occurredDateTime,
        DateTime(2026, 9, 29, 10, 30),
      );
      expect(
        const LedgerTx(occurredAt: '2026-09-29 10:30 00', billDate: '2026-08-01').occurredDateTime,
        DateTime(2026, 8, 1),
      );
    });

    test('copyWith 保留 id/source/ruleId/emailUid/createdAt/updatedAt 与 currency', () {
      final LedgerTx t = LedgerTx.fromJson(<String, dynamic>{
        'id': 9,
        'source': 'email',
        'rule_id': 3,
        'email_uid': 'uid-1',
        'created_at': '2026-01-01 00:00:00',
        'updated_at': '2026-01-02 00:00:00',
        'currency': 'USD',
        'amount': 12.34,
      });
      final LedgerTx c = t.copyWith(categoryId: 4, status: 'posted', merchant: '测试商户');
      expect(c.id, 9);
      expect(c.source, 'email');
      expect(c.ruleId, 3);
      expect(c.emailUid, 'uid-1');
      expect(c.createdAt, '2026-01-01 00:00:00');
      expect(c.updatedAt, '2026-01-02 00:00:00');
      expect(c.currency, 'USD');
      expect(c.amount, 12.34);
      expect(c.categoryId, 4);
      expect(c.status, 'posted');
      expect(c.merchant, '测试商户');
    });

    test('toJson 是 snake_case 且不含 created_at/updated_at/账号类别名', () {
      final LedgerTx t = LedgerTx.fromJson(<String, dynamic>{
        'id': 1,
        'occurred_at': '2026-09-29 10:30:00',
        'bill_date': '2026-09-29',
        'amount': 12.34,
        'merchant': '测试商户',
        'created_at': '2026-09-29 10:31:00',
        'account_name': '测试卡',
        'category_name': '餐饮美食',
      });
      expect(t.toJson()['occurred_at'], '2026-09-29 10:30:00');
      expect(t.toJson()['bill_date'], '2026-09-29');
      expect(t.toJson().containsKey('created_at'), isFalse);
      expect(t.toJson().containsKey('account_name'), isFalse);
      expect(t.toJson().containsKey('category_name'), isFalse);
      // 关联名在往返后丢失（列表页靠 Rust JOIN 回填，落库不需要）
      expect(LedgerTx.fromJson(t.toJson()).accountName, '');
    });
  });

  group('LedgerRule.fromJson', () {
    test('缺字段默认：imap / INBOX / auto / {} / enabled+useSsl 为真', () {
      final LedgerRule r = LedgerRule.fromJson(<String, dynamic>{});
      expect(r.protocol, 'imap');
      expect(r.mailbox, 'INBOX');
      expect(r.templateId, 'auto');
      expect(r.templateConfig, '{}');
      expect(r.enabled, isTrue);
      expect(r.useSsl, isTrue);
      expect(r.matchIsRegex, isFalse);
      expect(r.intervalMinutes, 0);
    });

    test('enabled/use_ssl 显式 false 时不会被默认值吃掉', () {
      final LedgerRule r = LedgerRule.fromJson(<String, dynamic>{'enabled': false, 'use_ssl': false});
      expect(r.enabled, isFalse);
      expect(r.useSsl, isFalse);
    });

    test('protocolSupported 只放行 imap/pop3/smtp，占位协议明确不支持', () {
      for (final String p in <String>['imap', 'pop3', 'smtp']) {
        expect(LedgerRule.fromJson(<String, dynamic>{'protocol': p}).protocolSupported, isTrue, reason: p);
      }
      for (final String p in <String>['eas', 'carddav', 'Exchange', 'IMAP']) {
        expect(LedgerRule.fromJson(<String, dynamic>{'protocol': p}).protocolSupported, isFalse, reason: p);
      }
      // 空串会被默认成 imap，因此"支持"；协议名大小写敏感
      expect(LedgerRule.fromJson(<String, dynamic>{'protocol': ''}).protocol, 'imap');
      expect(LedgerRule.fromJson(<String, dynamic>{'protocol': ''}).protocolSupported, isTrue);
    });

    test('toJson 用 snake_case 且没有 password 字段（口令只走安全存储）', () {
      final LedgerRule r = LedgerRule.fromJson(<String, dynamic>{
        'protocol': 'imap',
        'use_ssl': true,
        'match_is_regex': true,
        'accept_invalid_certs': true,
      });
      expect(r.toJson()['use_ssl'], isTrue);
      expect(r.toJson()['match_is_regex'], isTrue);
      expect(r.toJson()['accept_invalid_certs'], isTrue);
      expect(r.toJson().containsKey('password'), isFalse);
      expect(r.toJson().containsKey('secret_ref'), isFalse);
      // last_run_at / last_result 也不回写，属于运行时观测字段
      expect(r.toJson().containsKey('last_run_at'), isFalse);
    });

    test('copyWith 保留 lastRunAt/lastResult', () {
      final LedgerRule r = LedgerRule.fromJson(<String, dynamic>{
        'id': 2,
        'last_run_at': '2026-09-29 08:00:00',
        'last_result': '新增 3 笔',
      });
      final LedgerRule c = r.copyWith(name: '银行邮件', intervalMinutes: 30);
      expect(c.id, 2);
      expect(c.name, '银行邮件');
      expect(c.intervalMinutes, 30);
      expect(c.lastRunAt, '2026-09-29 08:00:00');
      expect(c.lastResult, '新增 3 笔');
    });
  });

  group('LedgerPendingEmail / LedgerParsedTx / LedgerParseResult', () {
    test('可选数值：缺字段是 null，0 是 0.0（不是 null）', () {
      final LedgerPendingEmail missing = LedgerPendingEmail.fromJson(<String, dynamic>{});
      expect(missing.availableCredit, isNull);
      expect(missing.pointsBalance, isNull);
      expect(missing.warnings, isEmpty);

      final LedgerPendingEmail zero = LedgerPendingEmail.fromJson(
        <String, dynamic>{'available_credit': 0, 'points_balance': 0},
      );
      expect(zero.availableCredit, 0.0);
      expect(zero.pointsBalance, 0);

      // 显式 null 与缺字段等价
      expect(LedgerPendingEmail.fromJson(<String, dynamic>{'available_credit': null}).availableCredit, isNull);

      final LedgerPendingEmail str = LedgerPendingEmail.fromJson(
        <String, dynamic>{'available_credit': '12.34', 'points_balance': '900'},
      );
      expect(str.availableCredit, 12.34);
      expect(str.pointsBalance, 900);
    });

    test('warnings：非列表 → 空列表，非字符串元素 → toString', () {
      expect(LedgerPendingEmail.fromJson(<String, dynamic>{'warnings': '字符串'}).warnings, isEmpty);
      expect(
        LedgerPendingEmail.fromJson(<String, dynamic>{'warnings': <dynamic>[1, '模板未命中']}).warnings,
        <String>['1', '模板未命中'],
      );
    });

    test('LedgerParsedTx：direction 空串回落 expense，但 status 缺字段是空串（与 LedgerTx 不同）', () {
      final LedgerParsedTx p = LedgerParsedTx.fromJson(<String, dynamic>{});
      expect(p.direction, kLedgerDirectionExpense);
      expect(p.currency, 'CNY');
      expect(p.txId, 0);
      // 现状锁定：构造器默认是 pending，fromJson 却没有兜底 → 空串
      expect(p.status, '');
      expect(const LedgerParsedTx().status, kLedgerStatusPending);
      expect(LedgerParsedTx.fromJson(<String, dynamic>{'status': 'posted'}).status, 'posted');
      expect(LedgerParsedTx.fromJson(<String, dynamic>{'direction': 'income'}).isIncome, isTrue);
    });

    test('LedgerParseResult：transactions 非列表时降级为空，isEmpty 跟随', () {
      expect(LedgerParseResult.fromJson(<String, dynamic>{}).isEmpty, isTrue);
      expect(LedgerParseResult.fromJson(<String, dynamic>{'transactions': 'notalist'}).transactions, isEmpty);
      final LedgerParseResult r = LedgerParseResult.fromJson(<String, dynamic>{
        'template_id': 'cmb',
        'bill_date': '2026-09-01',
        'transactions': <dynamic>[
          <String, dynamic>{'amount': 12.34, 'description': '测试商户', 'card_tail': '0000'},
        ],
      });
      expect(r.isEmpty, isFalse);
      expect(r.templateId, 'cmb');
      expect(r.transactions, hasLength(1));
      expect(r.transactions.first.amount, 12.34);
      expect(r.transactions.first.cardTail, '0000');
    });

    test('LedgerFetchedEmail：transactions 与 warnings 同时容错', () {
      final LedgerFetchedEmail e = LedgerFetchedEmail.fromJson(<String, dynamic>{
        'uid': '42',
        'matched': true,
        'size_bytes': '2048',
        'body_text_head': '账单正文开头',
        'warnings': <dynamic>['w'],
        'transactions': <dynamic>[
          <String, dynamic>{'amount': '12.34'},
        ],
      });
      expect(e.matched, isTrue);
      expect(e.sizeBytes, 2048);
      expect(e.bodyTextHead, '账单正文开头');
      expect(e.warnings, <String>['w']);
      expect(e.transactions.single.amount, 12.34);
      expect(LedgerFetchedEmail.fromJson(<String, dynamic>{}).transactions, isEmpty);
    });
  });

  group('统计行模型', () {
    test('LedgerDayRow.net = 收入 - 支出（浮点口径按 2 位小数展示由调用方负责）', () {
      expect(const LedgerDayRow(income: 10, expense: 3.66).net, closeTo(6.34, 1e-9));
      expect(const LedgerDayRow(income: 0, expense: 12.34).net, -12.34);
      expect(LedgerDayRow.fromJson(<String, dynamic>{'income': '10', 'expense': '3'}).net, 7);
    });

    test('LedgerCategoryRow 不补 direction 默认（空串就留空串）', () {
      final LedgerCategoryRow r = LedgerCategoryRow.fromJson(<String, dynamic>{
        'category_id': 3,
        'category_name': '餐饮美食',
        'category_icon': 'restaurant',
        'total': '1234.5',
        'count': '7',
      });
      expect(r.categoryId, 3);
      expect(r.categoryIcon, 'restaurant');
      expect(r.total, 1234.5);
      expect(r.count, 7);
      // 现状锁定：构造器默认 expense，但 fromJson 直接读 → 缺失时为空串
      expect(r.direction, '');
      expect(const LedgerCategoryRow().direction, kLedgerDirectionExpense);
    });

    test('LedgerMerchantRow 字段', () {
      final LedgerMerchantRow r = LedgerMerchantRow.fromJson(<String, dynamic>{
        'merchant': '测试商户',
        'total': 1234.5,
        'count': 3,
        'last_date': '2026-09-29',
      });
      expect(r.merchant, '测试商户');
      expect(r.total, 1234.5);
      expect(r.count, 3);
      expect(r.lastDate, '2026-09-29');
    });

    test('LedgerMonthRow.shortLabel 只切两段，其余原样', () {
      expect(const LedgerMonthRow(month: '2026-09').shortLabel, '9月');
      expect(const LedgerMonthRow(month: '2026-01').shortLabel, '1月');
      expect(const LedgerMonthRow(month: '2026-12').shortLabel, '12月');
      // 无分隔符 / 多段 → 原样返回
      expect(const LedgerMonthRow(month: 'abc').shortLabel, 'abc');
      expect(const LedgerMonthRow(month: 'a-b-c').shortLabel, 'a-b-c');
      // 月份解析失败 → 0月（现状锁定）
      expect(const LedgerMonthRow(month: '2026-xx').shortLabel, '0月');
      // 空串 split 只有一段 → 原样返回空串
      expect(const LedgerMonthRow().shortLabel, '');
    });

    test('LedgerSummary.isEmpty 只看 count，与金额无关', () {
      expect(LedgerSummary.fromJson(<String, dynamic>{}).isEmpty, isTrue);
      expect(LedgerSummary.fromJson(<String, dynamic>{'count': 0, 'income': 12.34}).isEmpty, isTrue);
      expect(LedgerSummary.fromJson(<String, dynamic>{'count': 2}).isEmpty, isFalse);
      expect(LedgerSummary.fromJson(<String, dynamic>{'count': '2'}).count, 2);
    });

    test('LedgerProbeReport / LedgerDupCheck / LedgerFetchLog / LedgerSchedulerStatus 容错', () {
      expect(LedgerProbeReport.fromJson(<String, dynamic>{'capabilities': 'x', 'folders': 3}).folders, isEmpty);
      expect(LedgerProbeReport.fromJson(<String, dynamic>{'ok': 1}).ok, isTrue);
      expect(
        LedgerProbeReport.fromJson(<String, dynamic>{'folders': <dynamic>['INBOX', 2]}).folders,
        <String>['INBOX', '2'],
      );
      expect(LedgerDupCheck.fromJson(<String, dynamic>{}).duplicated, isFalse);
      expect(LedgerDupCheck.fromJson(<String, dynamic>{'duplicated': 1, 'existing_id': '8'}).duplicated, isTrue);
      expect(LedgerDupCheck.fromJson(<String, dynamic>{'duplicated': 1, 'existing_id': '8'}).existingId, 8);
      expect(LedgerFetchLog.fromJson(<String, dynamic>{'ok': true, 'new_tx': '3'}).newTx, 3);
      expect(LedgerFetchLog.fromJson(<String, dynamic>{}).ok, isFalse);
      // 现状锁定：check_interval_secs 缺字段得到 0，而不是构造器默认的 60
      expect(LedgerSchedulerStatus.fromJson(<String, dynamic>{}).checkIntervalSecs, 0);
      expect(const LedgerSchedulerStatus().checkIntervalSecs, 60);
      expect(LedgerTemplate.fromJson(<String, dynamic>{'id': 'auto'}).id, 'auto');
      expect(LedgerTemplate.fromJson(<String, dynamic>{}).description, '');
    });
  });

  group('常量与枚举', () {
    test('方向/来源/状态字面量与 Rust serde 口径一致', () {
      expect(kLedgerDirectionExpense, 'expense');
      expect(kLedgerDirectionIncome, 'income');
      expect(kLedgerSourceManual, 'manual');
      expect(kLedgerSourceEmail, 'email');
      expect(kLedgerStatusPending, 'pending');
      expect(kLedgerStatusPosted, 'posted');
      expect(kLedgerStatusIgnored, 'ignored');
    });

    test('LedgerSaveResult 三态且 duplicate 独立于 failed', () {
      expect(LedgerSaveResult.values, <LedgerSaveResult>[
        LedgerSaveResult.saved,
        LedgerSaveResult.duplicate,
        LedgerSaveResult.failed,
      ]);
    });
  });
}
