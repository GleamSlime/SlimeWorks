// 流水账图标表的契约测试。
//
// 这里守的是三条"改名就会静默坏掉"的链：
// 1) kLedgerIconLabels（图标挑选器展示的键）必须都能在 kLedgerIcons 查到真图标；
// 2) kLedgerAccountTypes 的键必须与 ledgerAccountIconOf 的 switch 分支对得上；
// 3) Rust `ledger_module` 播种内置类别时写进 categories.icon 的字符串，必须能在
//    kLedgerIcons 里查到——库里存的是这个字符串而不是图标常量，两边没有任何东西在守。
//    第 3 条除了硬编码快照，还直接读 rust/ledger_module/src/storage.rs 的
//    BUILTIN_CATEGORIES 做一次源码级比对，作为漂移报警。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/components/icons/stroke_geometry.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/pages/ledger/components/ledger_icons.dart';

// ── 辅助：Rust 播种内置类别用到的图标键 ─────────────────────────────────────

/// 内置类别播种快照，与 `rust/ledger_module/src/storage.rs` 的 BUILTIN_CATEGORIES
/// 逐条对应（键值、条数、顺序都要一致）。Rust 侧新增/改名内置类别时，这张表和
/// kLedgerIcons 必须一起改，否则界面会画出一堆回落图标。
const Map<String, String> _rustBuiltinCategoryIcons = <String, String>{
  '餐饮美食': 'restaurant',
  '交通出行': 'bus',
  '购物消费': 'shoppingCart',
  '休闲娱乐': 'game',
  '居家缴费': 'home',
  '医疗健康': 'firstAid',
  '学习进修': 'book',
  '住房物业': 'building',
  '人情往来': 'gift',
  '宠物': 'paw',
  '美容美发': 'scissors',
  '旅行': 'plane',
  '通讯网络': 'deviceSimChat',
  '日用百货': 'deviceDesktop',
  '其他支出': 'dots',
  '工资收入': 'money',
  '奖金补贴': 'giftCard',
  '理财收益': 'chartLine',
  '报销款': 'receipt',
  '退款退货': 'refund',
  '其他收入': 'dots', // 与"其他支出"复用同一支笔
  '转账': 'exchange',
};

const String _rustStoragePath = 'rust/ledger_module/src/storage.rs';

/// 引用了"另一支笔"的键：car/coffee/heart 与表内其它键指向同一图标（旧数据兜底用的别名），
/// deviceSimChat/wallet/trendUp/trendDown 只是图标常量名与键名不同，图标本身唯一。
const Map<String, String> _kLedgerIconAliases = <String, String>{
  'car': 'bus',
  'coffee': 'restaurant',
  'heart': 'firstAid',
  'deviceSimChat': 'deviceSim',
  'wallet': 'accountBalanceWallet',
  'trendUp': 'trendingUp',
  'trendDown': 'trendingDown',
};

/// 与表内另一个键共用同一支笔的别名键（挑选器里不该再出现一次）
const List<String> _kLedgerIconDuplicatedKeys = <String>['car', 'coffee', 'heart'];

/// 从 Rust 源码里抓 BUILTIN_CATEGORIES 的 `("名称", "图标", DIRECTION_XXX)` 三元组。
/// 找不到文件或解析不出条目时返回 null，由用例自行跳过（打包环境里没有 rust/ 目录）。
Map<String, String>? _builtinCategoriesFromRust() {
  final File file = File(_rustStoragePath);
  if (!file.existsSync()) return null;
  final String source = file.readAsStringSync();
  final RegExp tuple = RegExp(
    r'\(\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,\s*DIRECTION_[A-Z]+\s*\)',
  );
  final Map<String, String> result = <String, String>{};
  for (final RegExpMatch m in tuple.allMatches(source)) {
    result[m.group(1)!] = m.group(2)!;
  }
  return result.isEmpty ? null : result;
}

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // kLedgerIcons / kLedgerIconLabels
  // ══════════════════════════════════════════════════════════════════════════

  group('kLedgerIconLabels 与 kLedgerIcons 对齐', () {
    test('每个展示用键都能查到真图标', () {
      for (final MapEntry<String, String> entry in kLedgerIconLabels.entries) {
        expect(
          kLedgerIcons.containsKey(entry.key),
          isTrue,
          reason: '图标挑选器列出了 ${entry.key}（${entry.value}），但 kLedgerIcons 没有对应项',
        );
        expect(kLedgerIcons[entry.key], isA<StrokeIcon>());
      }
    });

    test('每个展示用键解析出的图标不是回落图标（避免挑选器里出现空洞）', () {
      for (final String key in kLedgerIconLabels.keys) {
        expect(
          identical(ledgerIconOf(key), StrokeIcons.category),
          isFalse,
          reason: '$key 回落到了 category，说明两张表的键对不上',
        );
      }
    });

    test('每支图标都有笔画，viewBox 统一 24', () {
      for (final MapEntry<String, StrokeIcon> entry in kLedgerIcons.entries) {
        expect(entry.value.paths, isNotEmpty, reason: entry.key);
        expect(entry.value.viewBox, 24, reason: entry.key);
      }
    });

    test('中文名不为空且互不重复', () {
      expect(kLedgerIconLabels.values.every((String label) => label.trim().isNotEmpty), isTrue);
      expect(kLedgerIconLabels.values.toSet().length, kLedgerIconLabels.length);
    });

    test('kLedgerIconKeys 就是 labels 的键顺序（挑选器按这个顺序画格子）', () {
      expect(kLedgerIconKeys, kLedgerIconLabels.keys.toList());
      expect(kLedgerIconKeys, isNotEmpty);
      // 是不可变视图，UI 侧不能就地改表
      expect(() => kLedgerIconKeys.add('_新键'), throwsUnsupportedError);
    });

    test('kLedgerIcons 的键都能被 ledgerIconOf 命中（没有死键）', () {
      for (final MapEntry<String, StrokeIcon> entry in kLedgerIcons.entries) {
        expect(identical(ledgerIconOf(entry.key), entry.value), isTrue, reason: entry.key);
      }
    });
  });

  group('ledgerIconOf 回落', () {
    test('未知键回落到 StrokeIcons.category，不抛异常', () {
      expect(identical(ledgerIconOf('不存在的键'), StrokeIcons.category), isTrue);
      expect(identical(ledgerIconOf(''), StrokeIcons.category), isTrue);
      expect(identical(ledgerIconOf('Restaurant'), StrokeIcons.category), isTrue); // 大小写敏感
      expect(identical(ledgerIconOf('resturant'), StrokeIcons.category), isTrue); // 拼错的
      expect(identical(ledgerIconOf('dots '), StrokeIcons.category), isTrue); // 带空格的脏数据
    });

    test('回落图标本身可用（有笔画），不会画出空白', () {
      expect(StrokeIcons.category.paths, isNotEmpty);
      expect(StrokeIcons.category.name, 'category');
    });
  });

  group('图标别名（复用同一支笔的键）', () {
    test('别名指向的图标与文档一致', () {
      expect(identical(kLedgerIcons['car'], StrokeIcons.bus), isTrue);
      expect(identical(kLedgerIcons['coffee'], StrokeIcons.restaurant), isTrue);
      expect(identical(kLedgerIcons['heart'], StrokeIcons.firstAid), isTrue);
      expect(identical(kLedgerIcons['deviceSimChat'], StrokeIcons.deviceSim), isTrue);
      expect(identical(kLedgerIcons['wallet'], StrokeIcons.accountBalanceWallet), isTrue);
      expect(identical(kLedgerIcons['trendUp'], StrokeIcons.trendingUp), isTrue);
      expect(identical(kLedgerIcons['trendDown'], StrokeIcons.trendingDown), isTrue);
      // 别名走的是同一支笔，所以 ledgerIconOf 两侧结果必须完全一致
      expect(identical(ledgerIconOf('car'), ledgerIconOf('bus')), isTrue);
      expect(identical(ledgerIconOf('coffee'), ledgerIconOf('restaurant')), isTrue);
      expect(identical(ledgerIconOf('heart'), ledgerIconOf('firstAid')), isTrue);
    });

    test('所有别名键都在表里且不会退化成回落图标', () {
      for (final String alias in _kLedgerIconAliases.keys) {
        expect(kLedgerIcons.containsKey(alias), isTrue, reason: alias);
        expect(
          identical(ledgerIconOf(alias), StrokeIcons.category),
          isFalse,
          reason: '$alias 挂到了不存在的图标常量上',
        );
      }
    });

    test('共用同一支笔的别名键不落在挑选器列表里（同一图标不该出现两次）', () {
      for (final String alias in _kLedgerIconDuplicatedKeys) {
        expect(kLedgerIconLabels.containsKey(alias), isFalse, reason: alias);
        expect(kLedgerIcons.containsKey(alias), isTrue, reason: alias);
      }
    });

    test('图标表里的重复项有且只有那 3 组别名，其余键各自一支笔', () {
      // 按 const 身份分组；StrokeIcon 没有 operator==，这里用的就是对象同一性
      final Map<StrokeIcon, List<String>> groups = <StrokeIcon, List<String>>{};
      kLedgerIcons.forEach((String key, StrokeIcon icon) {
        groups.putIfAbsent(icon, () => <String>[]).add(key);
      });
      final List<List<String>> duplicated = groups.values
          .where((List<String> keys) => keys.length > 1)
          .map((List<String> keys) => keys.toList()..sort())
          .toList()
        ..sort((List<String> a, List<String> b) => a.first.compareTo(b.first));
      expect(duplicated, <List<String>>[
        <String>['bus', 'car'],
        <String>['coffee', 'restaurant'],
        <String>['firstAid', 'heart'],
      ]);
      // deviceSimChat / wallet / trendUp / trendDown 引用的常量名和键名不同，
      // 但目标图标在表里是唯一的，不构成重复
      expect(groups.length, kLedgerIcons.length - 3);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 账户类型
  // ══════════════════════════════════════════════════════════════════════════

  group('kLedgerAccountTypes 与 ledgerAccountIconOf 分支', () {
    test('值域与 Rust Account.type 的注释口径一致（credit_card|debit_card|cash|deposit|other）', () {
      expect(kLedgerAccountTypes.keys, <String>[
        'credit_card',
        'debit_card',
        'cash',
        'deposit',
        'other',
      ]);
      expect(kLedgerAccountTypes.values, <String>['信用卡', '储蓄卡', '现金', '存款', '其他']);
    });

    test('四个显式分支各自拿到不同的图标', () {
      final List<StrokeIcon> icons = <StrokeIcon>[
        ledgerAccountIconOf('credit_card'),
        ledgerAccountIconOf('debit_card'),
        ledgerAccountIconOf('cash'),
        ledgerAccountIconOf('deposit'),
      ];
      expect(identical(icons[0], StrokeIcons.creditCard), isTrue);
      expect(identical(icons[1], StrokeIcons.accountBalanceWallet), isTrue);
      expect(identical(icons[2], StrokeIcons.money), isTrue);
      expect(identical(icons[3], StrokeIcons.building), isTrue);
      // 同一支笔不能代表两种账户，否则列表页看不出差别
      for (var i = 0; i < icons.length; i++) {
        for (var j = i + 1; j < icons.length; j++) {
          expect(identical(icons[i], icons[j]), isFalse, reason: '$i 与 $j 撞图标');
        }
      }
    });

    test('other 与未知值都走 default 分支拿到 dots', () {
      expect(identical(ledgerAccountIconOf('other'), StrokeIcons.dots), isTrue);
      expect(identical(ledgerAccountIconOf(''), StrokeIcons.dots), isTrue);
      expect(identical(ledgerAccountIconOf('unknown_type'), StrokeIcons.dots), isTrue);
    });

    test('ledgerAccountTypeLabel 命中中文，未命中时原样返回键', () {
      expect(ledgerAccountTypeLabel('credit_card'), '信用卡');
      expect(ledgerAccountTypeLabel('other'), '其他');
      expect(ledgerAccountTypeLabel('unknown_type'), 'unknown_type');
      expect(ledgerAccountTypeLabel(''), '');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Rust 播种内置类别的 icon 字符串
  // ══════════════════════════════════════════════════════════════════════════

  group('Rust 内置类别 icon 与 Dart 图标表一致', () {
    test('快照里的每个内置类别图标都能在 kLedgerIcons 查到', () {
      for (final MapEntry<String, String> entry in _rustBuiltinCategoryIcons.entries) {
        expect(
          kLedgerIcons.containsKey(entry.value),
          isTrue,
          reason: 'Rust 播种的内置类别「${entry.key}」写了 icon=${entry.value}，'
              '但 Dart 的 kLedgerIcons 没有这个键，界面上会画成回落图标',
        );
      }
    });

    test('这些图标还能在图标挑选器里选到（有中文名）', () {
      for (final String icon in _rustBuiltinCategoryIcons.values.toSet()) {
        expect(
          kLedgerIconLabels.containsKey(icon),
          isTrue,
          reason: '内置类别用了 icon=$icon，但挑选器 kLedgerIconLabels 里没有它，'
              '用户改类别时选不到同一个图标',
        );
      }
    });

    test('内置类别图标数与 Rust 条数对得上（22 条里"dots"复用，去重后 21 个键）', () {
      expect(_rustBuiltinCategoryIcons.length, 22);
      expect(_rustBuiltinCategoryIcons.values.toSet().length, 21);
    });

    test('源码级漂移报警：storage.rs 的 BUILTIN_CATEGORIES 与本文件快照逐字一致', () {
      final Map<String, String>? fromRust = _builtinCategoriesFromRust();
      if (fromRust == null) {
        markTestSkipped('读不到 $_rustStoragePath（环境里没有 rust/ 目录），跳过源码级比对');
        return;
      }
      expect(
        fromRust,
        _rustBuiltinCategoryIcons,
        reason: 'Rust BUILTIN_CATEGORIES 与本文件快照不一致：'
            '要么 Rust 侧新增/改名了内置类别（记得同步 kLedgerIcons 与挑选器），要么快照该更新了',
      );
      for (final String icon in fromRust.values) {
        expect(kLedgerIcons.containsKey(icon), isTrue, reason: 'Rust 侧 icon=$icon 查不到');
      }
    });
  });
}
