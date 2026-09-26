import 'package:flutter_test/flutter_test.dart';
import 'package:slime_works/pages/interaction_lab/interaction_lab_screen.dart';
import 'helpers/page_golden.dart';

void main() {
  testWidgets('交互实验室整页', tags: 'golden', (tester) async {
    await loadAppFonts();
    await pumpAppPage(tester, const InteractionLabScreen());
    await advance(tester);
    await expectLater(find.byType(InteractionLabScreen),
        matchesGoldenFile('goldens/interaction_lab_page.png'));
    expect(tester.takeException(), isNull);
    await unmountPage(tester);
  });
}
