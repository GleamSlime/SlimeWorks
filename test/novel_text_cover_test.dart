import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:slime_works/core/widgets/novel_text_cover.dart';

import 'helpers/page_golden.dart';

void main() {
  test('封面文字跳过标点、空白和表情，取首个字母或数字', () {
    expect(NovelTextCoverStyle.fromTitle('  三体').text, '三');
    expect(NovelTextCoverStyle.fromTitle('《哈利·波特》').text, '哈');
    expect(NovelTextCoverStyle.fromTitle('😀 1984').text, '1');
    expect(NovelTextCoverStyle.fromTitle('🚀星际穿越').text, '星');
    expect(NovelTextCoverStyle.fromTitle('Émile').text, 'É');
    expect(NovelTextCoverStyle.fromTitle('٩٩٩').text, '٩');
  });

  test('纯符号标题有可读兜底，同文字颜色稳定且不同字有区分', () {
    expect(NovelTextCoverStyle.fromTitle('！！！').text, '书');
    expect(NovelTextCoverStyle.fromTitle('   ').text, '书');
    final first = NovelTextCoverStyle.fromTitle('三体');
    expect(first.color, NovelTextCoverStyle.fromTitle('三体').color);
    expect(first.color, isNot(NovelTextCoverStyle.fromTitle('四体').color));
  });

  testWidgets('共享文字封面渲染首个字并保留完整书名语义', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpAppPage(
        tester,
        const SizedBox(width: 120, height: 180, child: NovelTextCover(title: '《三体》')),
      );
      expect(find.text('三'), findsOneWidget);
      expect(find.bySemanticsLabel('《三体》'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });
}
