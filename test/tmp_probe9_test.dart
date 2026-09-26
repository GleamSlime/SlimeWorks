import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/pages/interaction_lab/cases/case_09_one_time_code.dart';

import 'helpers/il_golden.dart';

void main() {
  testWidgets('probe', (tester) async {
    for (final r in '0123456789a'.runes) {
      debugPrint('rune $r -> ${LogicalKeyboardKey(r).keyLabel}');
    }
    await mountIlCase(tester, const Case09OneTimeCode());
    await tester.tapAt(ilStageCenter(tester));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    for (final ch in ['1', '2', '9']) {
      await ilType(tester, ch);
      await tester.pump(const Duration(milliseconds: 16));
      debugPrint('after $ch: '
          '${[0, 1, 2, 3].map((i) => find.byKey(ValueKey('digit-$i')).evaluate().isNotEmpty ? 'Y' : '.').join()} '
          'caret=${tester.widget<Transform>(find.byKey(const ValueKey('caret-xf'))).transform.storage[12] + 1}');
    }
    await unmountPage(tester);
  });
}
