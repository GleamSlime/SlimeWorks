// 临时探针 2：点完卡片（不可聚焦的 GestureDetector）之后，ESC 到底还能不能被正文那层收到。
//
// 这条链是问题现场：搜索框拿焦点 → 点搜索结果里的集合卡（卡片是 GestureDetector，
// 不要焦点）→ TextField 的默认 onTapOutside 把焦点 unfocus 掉 → primary focus 退回
// 最近的 FocusScopeNode。此后按键派发只从 scope 往上走，页面里的任何 Focus
// （正文那层也好、包在工具栏外面那层也好）都在 scope 的**下面**，一律看不到 ESC。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const fieldKey = Key('field');
  const cardKey = Key('card');

  Future<List<String>> scenario(WidgetTester tester, {required bool reclaimFocus}) async {
    final seen = <String>[];
    final fieldNode = FocusNode();
    final bodyNode = FocusNode();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            title: SizedBox(width: 160, child: TextField(focusNode: fieldNode, key: fieldKey)),
          ),
          body: Focus(
            focusNode: bodyNode,
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent) seen.add(event.logicalKey.keyLabel);
              return KeyEventResult.ignored;
            },
            child: GestureDetector(
              key: cardKey,
              onTap: () {
                // 真机这里进集合；进完之后把焦点收回正文，让 ESC 重新有主
                if (reclaimFocus) bodyNode.requestFocus();
              },
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );

    // 1. 点搜索框并输入
    await tester.tap(find.byKey(fieldKey));
    await tester.pump();
    expect(fieldNode.hasFocus, isTrue);
    // 2. 点卡片（卡片不要焦点）
    await tester.tap(find.byKey(cardKey));
    await tester.pump();
    final focusAfterCard = (
      field: fieldNode.hasFocus,
      body: bodyNode.hasFocus,
      primary: Focus.of(tester.element(find.byKey(cardKey))).toStringShort(),
    );
    seen.clear();
    // 3. 敲 ESC
    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    fieldNode.dispose();
    bodyNode.dispose();
    debugPrint('点完卡片后焦点: $focusAfterCard');
    return seen;
  }

  testWidgets('不抢焦点：ESC 到不了正文（复现用户现场）', (tester) async {
    final seen = await scenario(tester, reclaimFocus: false);
    expect(seen, isEmpty, reason: 'primary focus 退回 scope，页面里的 Focus 全在 scope 下面');
  });

  testWidgets('进集合后把焦点收回正文：ESC 重新生效', (tester) async {
    final seen = await scenario(tester, reclaimFocus: true);
    expect(seen, contains('Escape'));
  });
}
