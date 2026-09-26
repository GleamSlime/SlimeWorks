import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/pages/motion_lab/cases/case_03_notification_badge.dart';
import 'package:slime_works/pages/motion_lab/cases/case_19_tabs_sliding.dart';

import 'helpers/lab_golden.dart';

// 逐案例的三态出图。一格的三个 test 只验一件事：
// 静止样对不对、途中帧有没有真的在动、走完停在哪儿。

void main() {
  group('3. Notification badge', () {
    testWidgets('静止', tags: 'golden', (tester) async {
      await shootLabCase(
        tester,
        name: 'case_03_idle',
        child: const Case03NotificationBadge(),
      );
    });

    testWidgets('弹出途中', tags: 'golden', (tester) async {
      await shootLabCase(
        tester,
        name: 'case_03_mid',
        child: const Case03NotificationBadge(),
        act: tapAnimate,
        thenMs: 120,
      );
    });

    testWidgets('弹出终态', tags: 'golden', (tester) async {
      await shootLabCase(
        tester,
        name: 'case_03_end',
        child: const Case03NotificationBadge(),
        act: tapAnimate,
        thenMs: 900,
      );
    });
  });

  group('19. Tabs sliding', () {
    testWidgets('静止', tags: 'golden', (tester) async {
      await shootLabCase(
        tester,
        name: 'case_19_idle',
        child: const Case19TabsSliding(),
      );
    });

    testWidgets('指示条途中', tags: 'golden', (tester) async {
      await shootLabCase(
        tester,
        name: 'case_19_mid',
        child: const Case19TabsSliding(),
        act: (t) => t.tap(find.text('Ask')),
        thenMs: 120,
      );
    });

    testWidgets('指示条终态', tags: 'golden', (tester) async {
      await shootLabCase(
        tester,
        name: 'case_19_end',
        child: const Case19TabsSliding(),
        act: (t) => t.tap(find.text('Ask')),
        thenMs: 500,
      );
    });
  });
}
