// 记一笔编辑器的行为测试。
//
// 这一版表单把"收/支"两态扩成了 支出/收入/转账/余额调整 四态，外加两级类别、
// 标签、附件占位、存为模板。四态之间最容易出事的是**残留选择**：换方向没清掉
// 旧类别，就会把一笔支出挂到收入类别的 id 上；切到转账不清类别，落库就带着
// 一个毫不相干的"餐饮"。所以这里的断言全部盯着"换型之后剩下了什么"。
//
// 数据全是编的（仓库公开，真实账单不许进仓库）。标签/模板走 LedgerStubStore，
// 账户与类别由测试直接喂给表单——这条链不碰 FFI，也就无需 RustLib.initMock。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:slime_works/core/services/ledger_stub_store.dart';
import 'package:slime_works/core/widgets/app_text_field.dart';
import 'package:slime_works/pages/ledger/components/ledger_tx_editor.dart';
import 'package:slime_works/pages/ledger/models/ledger_models.dart';

import 'helpers/page_golden.dart';

const List<LedgerAccount> _accounts = <LedgerAccount>[
  LedgerAccount(id: 1, name: '储蓄库', type: 'debit_card', last4: '0001'),
  LedgerAccount(id: 2, name: '零钱袋', type: 'cash'),
  LedgerAccount(id: 3, name: '信用卡', type: 'credit_card', last4: '0002'),
];

/// 两级类别：餐饮(10) 下面挂 早饭(11)/午饭(12)；交通(20) 是叶子
const List<LedgerCategory> _categories = <LedgerCategory>[
  LedgerCategory(id: 10, name: '吃饭', icon: 'restaurant'),
  LedgerCategory(id: 11, name: '早饭', icon: 'coffee', parentId: 10),
  LedgerCategory(id: 12, name: '午饭', icon: 'coffee', parentId: 10),
  LedgerCategory(id: 20, name: '公交', icon: 'bus'),
  LedgerCategory(id: 30, name: '工资', icon: 'money', direction: kLedgerDirectionIncome),
];

/// showLedgerTxEditor 是 pop 回来的，测试要等 pumpAndSettle 之后才读得到值
class _Saved {
  LedgerTx? tx;
}

/// 把表单挂到一个页面上并点开，返回承接结果的那个盒子
Future<_Saved> _open(
  WidgetTester tester, {
  LedgerTx? initial,
  Size size = kTestWindowSize,
  Size? designSize,
}) async {
  final saved = _Saved();
  await pumpAppPage(
    tester,
    Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              saved.tx = await showLedgerTxEditor(
                context,
                initial: initial,
                accounts: _accounts,
                categories: _categories,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
    size: size,
    designSize: designSize,
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return saved;
}

/// 点一个胶囊/输入项。用 last 是因为转账页两行账户里可能同时有同名账户，
/// 而转入那一行排在后面；其余场景本来就只有一个匹配项。
Future<void> _pickType(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// 转账那两行账户都列着全部账户，按下标点才分得清转出侧和转入侧
Future<void> _pickNth(WidgetTester tester, String label, int index) async {
  await tester.tap(find.text(label).at(index));
  await tester.pumpAndSettle();
}

Future<void> _typeAmount(WidgetTester tester, String value) async {
  await tester.enterText(find.bySubtype<TextField>().first, value);
  await tester.pumpAndSettle();
}

Future<void> _typeMerchant(WidgetTester tester, String value) async {
  await tester.enterText(find.widgetWithText(AppTextField, '商户 / 说明'), value);
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  // 表单加了四类型/标签/附件之后比窗口还高，保存那颗常在折叠线以下
  await tester.ensureVisible(find.text('记下来'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('记下来'));
  await tester.pumpAndSettle();
}

/// 出图用的草稿：日期时刻钉死，否则"9:46 PM"每过一分钟就把基线红掉一次。
/// id 留 0，编辑器仍然走"记一笔"而不是"编辑这笔"。
final LedgerTx _draft = LedgerTx(occurredAt: '2026-03-28 20:15:00', billDate: '2026-03-28');

void main() {
  setUpAll(() async {
    // 最后一张是出图基线：不挂字体，中文全是豆腐块，图就没法当验收依据
    await loadAppFonts();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // 桩仓库是进程级单例：不清零，前一个用例新建的标签和附件会漂进后一个用例，
    // 出图基线就每月红一次那种红。
    await LedgerStubStore.instance.resetForTest();
  });

  group('四类型切换', () {
    testWidgets('默认是支出：有类别行、只有一个账户字段', (tester) async {
      await _open(tester);
      expect(find.text('类别'), findsOneWidget);
      expect(find.text('账户'), findsOneWidget);
      expect(find.text('转出账户'), findsNothing);
      expect(find.textContaining('要等后端建表'), findsNothing);
      await unmountPage(tester);
    });

    testWidgets('切到转账：换成两边账户，类别行收掉，并写明后端未接入', (tester) async {
      await _open(tester);
      await _pickType(tester, '转账');
      expect(find.text('转出账户'), findsOneWidget);
      expect(find.text('转入账户'), findsOneWidget);
      expect(find.text('类别'), findsNothing);
      expect(find.text('到账金额'), findsOneWidget);
      expect(find.textContaining('转账的双边记账'), findsOneWidget);
      await unmountPage(tester);
    });

    testWidgets('切到余额调整：金额位改成"调整后的余额"，不出现转入账户', (tester) async {
      await _open(tester);
      await _pickType(tester, '余额调整');
      expect(find.text('转入账户'), findsNothing);
      expect(find.text('调整后的余额'), findsOneWidget);
      expect(find.textContaining('余额调整要等后端建表'), findsOneWidget);
      await unmountPage(tester);
    });

    testWidgets('选了支出类别再切收入：候选换成收入侧，旧选择不留着', (tester) async {
      await _open(tester);
      await _pickType(tester, '公交');
      await _pickType(tester, '收入');
      expect(find.text('类别'), findsOneWidget);
      expect(find.text('公交'), findsNothing);
      expect(find.text('吃饭'), findsNothing);
      expect(find.text('工资'), findsOneWidget);
      await unmountPage(tester);
    });
  });

  group('两级类别', () {
    testWidgets('点父类先展开二级，本级不并列叶子', (tester) async {
      await _open(tester);
      // 有子类时一级行只列父类，公交这种叶子不会被并列进来
      expect(find.text('吃饭'), findsOneWidget);
      expect(find.text('早饭'), findsNothing);
      await _pickType(tester, '吃饭');
      expect(find.text('早饭'), findsOneWidget);
      expect(find.text('午饭'), findsOneWidget);
      await unmountPage(tester);
    });

    testWidgets('只点父类不选子类，没有子类的父类直接落给自己', (tester) async {
      await _open(tester);
      await _pickType(tester, '公交');
      // 公交没有子类：不该长出第二行
      expect(find.text('公交'), findsOneWidget);
      await unmountPage(tester);
    });
  });

  group('落库字段', () {
    testWidgets('支出：direction/txType/账户名/类别名一起带上', (tester) async {
      final saved = await _open(tester);
      await _pickType(tester, '公交');
      await _typeAmount(tester, '23.45');
      await _pickType(tester, '零钱袋');
      await _typeMerchant(tester, '测试便利店');
      await _save(tester);

      expect(saved.tx, isNotNull);
      expect(saved.tx!.amount, closeTo(23.45, 0.001));
      expect(saved.tx!.direction, kLedgerDirectionExpense);
      expect(saved.tx!.txType, kLedgerTxTypeExpense);
      expect(saved.tx!.accountId, 2);
      expect(saved.tx!.accountName, '零钱袋');
      expect(saved.tx!.categoryId, 20);
      expect(saved.tx!.categoryName, '公交');
      expect(saved.tx!.merchant, '测试便利店');
      expect(saved.tx!.billDate, isNotEmpty);
      expect(saved.tx!.countsInFlow, isTrue);
      expect(saved.tx!.destAccountId, 0);
      await unmountPage(tester);
    });

    testWidgets('转账：带上落点账户与落点名，类别强制为 0', (tester) async {
      final saved = await _open(tester);
      await _pickType(tester, '公交');
      await _pickType(tester, '转账');
      await _typeAmount(tester, '5000');
      // 转出/转入两行都列着同样的账户名，第 0 个是转出侧、最后一个是转入侧
      await _pickNth(tester, '储蓄库', 0);
      await _pickType(tester, '零钱袋');
      await _save(tester);

      expect(saved.tx, isNotNull);
      expect(saved.tx!.txType, kLedgerTxTypeTransfer);
      expect(saved.tx!.isTransfer, isTrue);
      // 切类型前选的"公交"不能跟着进转账，否则统计里会冒出一笔带类别的搬运
      expect(saved.tx!.categoryId, 0);
      expect(saved.tx!.categoryName, isEmpty);
      expect(saved.tx!.accountId, 1);
      expect(saved.tx!.destAccountId, 2);
      expect(saved.tx!.destAccountName, '零钱袋');
      // 没填到账金额时按转出数看；countsInFlow=false 才是它不进收支的理由
      expect(saved.tx!.destSignedAmount, closeTo(5000, 0.001));
      expect(saved.tx!.countsInFlow, isFalse);
      await unmountPage(tester);
    });

    testWidgets('转账只选了一边：拦住并说明，不 pop', (tester) async {
      final saved = await _open(tester);
      await _pickType(tester, '转账');
      await _typeAmount(tester, '100');
      await _pickNth(tester, '储蓄库', 0);
      await _save(tester);
      expect(find.text('转账要把转出、转入两边都选好'), findsOneWidget);
      expect(find.text('记下来'), findsOneWidget);
      expect(saved.tx, isNull);
      await unmountPage(tester);
    });

    testWidgets('金额为 0 不给保存', (tester) async {
      final saved = await _open(tester);
      await _save(tester);
      expect(find.text('金额要大于 0'), findsOneWidget);
      expect(find.text('记下来'), findsOneWidget);
      expect(saved.tx, isNull);
      await unmountPage(tester);
    });
  });

  group('标签与模板', () {
    testWidgets('挑选器里就地新建会立刻选上，确认后跟着这笔走', (tester) async {
      await LedgerStubStore.instance.init();
      final before = await LedgerStubStore.instance.listTags();
      final saved = await _open(tester);
      await tester.tap(find.text('添加标签'));
      await tester.pumpAndSettle();
      expect(find.text('这笔的标签'), findsOneWidget);
      expect(find.textContaining('标签是演示数据'), findsOneWidget);

      await tester.enterText(find.widgetWithText(AppTextField, '新建标签名'), '测试新建标签');
      await tester.tap(find.text('新建'));
      await tester.pumpAndSettle();

      final after = await LedgerStubStore.instance.listTags();
      expect(after.length, before.length + 1);
      expect(after.map((t) => t.name), contains('测试新建标签'));

      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      await _typeAmount(tester, '12');
      await _pickType(tester, '零钱袋');
      await _save(tester);

      expect(saved.tx, isNotNull);
      expect(saved.tx!.tagNames, contains('测试新建标签'));
      expect(saved.tx!.tagIds, hasLength(1));
      await unmountPage(tester);
    });

    testWidgets('勾了存为模板，模板仓库多出一条且带着这笔的口径', (tester) async {
      await LedgerStubStore.instance.init();
      final store = LedgerStubStore.instance;
      final before = await store.listTxTemplates();
      final saved = await _open(tester);
      await _typeAmount(tester, '18');
      await _pickType(tester, '零钱袋');
      await _typeMerchant(tester, '每月固定支出');
      await tester.tap(find.textContaining('存为模板'));
      await tester.pumpAndSettle();
      await _save(tester);

      expect(saved.tx, isNotNull);
      final after = await store.listTxTemplates();
      expect(after.length, greaterThan(before.length));
      final created = after.firstWhere((t) => t.title == '每月固定支出');
      expect(created.amount, closeTo(18, 0.001));
      expect(created.accountId, 2);
      await unmountPage(tester);
    });
  });

  group('编辑已有的一笔', () {
    testWidgets('标题变成"编辑这笔"，字段回填，且不出现存为模板', (tester) async {
      final existing = LedgerTx(
        id: 77,
        billDate: '2026-03-05',
        occurredAt: '2026-03-05 12:34:00',
        direction: kLedgerDirectionIncome,
        txType: kLedgerTxTypeIncome,
        amount: 999,
        accountId: 3,
        categoryId: 30,
        merchant: '三月工资',
      );
      await _open(tester, initial: existing);
      expect(find.text('编辑这笔'), findsOneWidget);
      expect(find.text('记下来'), findsNothing);
      expect(find.text('保存修改'), findsOneWidget);
      expect(find.textContaining('存为模板'), findsNothing);
      expect(find.text('999.00'), findsOneWidget);
      expect(find.text('三月工资'), findsOneWidget);
      // 回填要停在收入侧，否则类别行会先闪一遍支出类别
      expect(find.text('工资'), findsOneWidget);
      await unmountPage(tester);
    });

    testWidgets('已选的标签在表单里看得到，点 × 能摘掉', (tester) async {
      await LedgerStubStore.instance.init();
      final tag = await LedgerStubStore.instance.upsertTagByName('待摘测试标签');
      final existing = LedgerTx(
        id: 78,
        direction: kLedgerDirectionExpense,
        amount: 10,
        accountId: 1,
        tagIds: <int>[tag.id],
        tagNames: <String>[tag.name],
      );
      await _open(tester, initial: existing);
      expect(find.text('待摘测试标签'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('tag-remove:待摘测试标签')));
      await tester.pumpAndSettle();
      expect(find.text('待摘测试标签'), findsNothing);
      await unmountPage(tester);
    });
  });

  testWidgets('桌面 1440 宽：类型条拉成四等分', (tester) async {
    await _open(tester, initial: _draft);
    await _pickType(tester, '吃饭');
    await _pickType(tester, '早饭');
    await _pickType(tester, '零钱袋');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Dialog),
      matchesGoldenFile('goldens/ledger_editor_desktop.png'),
    );
    await unmountPage(tester);
  }, tags: <String>['golden']);

  testWidgets('手机 390 宽整表逐帧排得出，不溢出', (tester) async {
    await _open(
      tester,
      initial: _draft,
      size: const Size(390, 844),
      designSize: const Size(375, 815),
    );
    for (final type in <String>['收入', '转账', '余额调整', '支出']) {
      await _pickType(tester, type);
    }
    await _pickType(tester, '吃饭');
    await _pickType(tester, '早饭');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Dialog),
      matchesGoldenFile('goldens/ledger_editor_phone.png'),
    );
    await unmountPage(tester);
  }, tags: <String>['golden']);
}
