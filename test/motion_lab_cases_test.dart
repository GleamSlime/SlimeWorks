import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/pages/motion_lab/cases/case_03_notification_badge.dart';
import 'package:slime_works/pages/motion_lab/cases/case_19_tabs_sliding.dart';
import 'package:slime_works/pages/motion_lab/cases/case_44_voice_waveform.dart';

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

  // 44 号的三档状态。常态那一圈由 motion_lab_all_cases_test 出三帧，这里只补
  // 另两档：静音要拍出"没有波浪但还有高度"，讲话要拍出峰值是一波一个样的
  group('44. Voice waveform 档位', () {
    testWidgets('静音档静止', tags: 'golden', (tester) async {
      await shootLabCase(
        tester,
        name: 'case_44_silent',
        child: const Case44VoiceWaveform(),
        act: (t) => t.tap(find.text('静音')),
        // 说明文字换档是 120ms 的淡入淡出，不等它走完拍到的是两行叠在一起
        thenMs: 200,
      );
    });

    testWidgets('讲话档途中帧', tags: 'golden', (tester) async {
      await shootLabCase(
        tester,
        name: 'case_44_talking_mid',
        child: const Case44VoiceWaveform(),
        act: (t) => t.tap(find.text('讲话')),
        thenMs: 1300,
      );
    });

    // 同一档再推 600ms：两帧一比才看得出波确实在往外走、峰值是一波一个样
    testWidgets('讲话档再推一格', tags: 'golden', (tester) async {
      await shootLabCase(
        tester,
        name: 'case_44_talking_late',
        child: const Case44VoiceWaveform(),
        act: (t) => t.tap(find.text('讲话')),
        thenMs: 1900,
      );
    });
  });
}
