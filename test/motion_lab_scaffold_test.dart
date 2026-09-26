import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/pages/motion_lab/cases/motion_lab_cases.dart';
import 'package:slime_works/pages/motion_lab/lab_kit.dart';
import 'package:slime_works/pages/motion_lab/motion_lab_screen.dart';

import 'helpers/page_golden.dart';

// 动效实验室的验收：先钉住"43 格、一格一个组件、互不引用"这条契约，
// 再出图看外壳排版。每张图都只走离屏，不起第二个实例。

Future<void> _mount(WidgetTester tester) async {
  await loadAppFonts();
  await pumpAppPage(tester, const MotionLabScreen());
  await advance(tester);
}

void main() {
  test('43 格案例注册表：序号连续、标题唯一、各挂各的组件', () {
    expect(kLabCases.length, 43);
    expect(kLabCases.map((c) => c.seq).toList(), [for (var i = 1; i <= 43; i++) i]);
    expect(kLabCases.map((c) => c.title).toSet().length, 43);
    // 每格 build 出来的必须是各自不同的类型，否则就是两格共用了一份实现
    expect(kLabCases.map((c) => c.build().runtimeType).toSet().length, 43);
  });

  testWidgets('43 格排下去不炸', (tester) async {
    await _mount(tester);
    expect(tester.takeException(), isNull);
    await unmountPage(tester);
  });

  testWidgets('整页出图', tags: 'golden', (tester) async {
    await _mount(tester);
    await expectLater(
      find.byType(MotionLabScreen),
      matchesGoldenFile('goldens/motion_lab_grid.png'),
    );
    await unmountPage(tester);
  });

  // 放大层：点右下角圆钮，同一份组件放大一倍浮到页面中央
  testWidgets('放大层出图', tags: 'golden', (tester) async {
    await _mount(tester);
    await tester.tap(find.descendant(
      of: find.byType(LabCard),
      matching: find.byType(LabIconButton),
    ).first);
    await advance(tester);

    await expectLater(
      find.byType(MotionLabScreen),
      matchesGoldenFile('goldens/motion_lab_focus.png'),
    );
    await unmountPage(tester);
  });
}
