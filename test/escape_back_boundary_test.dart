import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/core/widgets/escape_back_boundary.dart';

// ESC 全局返回兜底层
//
// 这层挂在每条路由的 child 外面（AppRoutes.buildPage），所以它必须同时满足两件事：
// 页内自己的 ESC 逻辑一点都不能被它抢走（媒体库的逐级返回、阅读器的按键），
// 而页面里"没人拿到焦点"时它又必须自己兜住，否则子页按 ESC 毫无反应。
// 这两条在真机上都由焦点链决定，光看代码容易想反，所以逐条钉成测试。

Widget _app(Widget childPage) {
  return MaterialApp(
    initialRoute: '/',
    routes: {
      '/': (context) => const Scaffold(body: Center(child: Text('顶层页'))),
      '/child': (context) => EscapeBackBoundary(child: Scaffold(body: childPage)),
    },
  );
}

Future<void> _openChild(WidgetTester tester, Widget childPage) async {
  await tester.pumpWidget(_app(childPage));
  final context = tester.element(find.text('顶层页'));
  Navigator.of(context).pushNamed('/child');
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('子页里没人拿焦点时，ESC 由兜底层退回上一页', (tester) async {
    await _openChild(tester, const Center(child: Text('漫画详情')));

    expect(FocusManager.instance.primaryFocus!.debugLabel, 'EscapeBackBoundary');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('顶层页'), findsOneWidget);
    expect(find.text('漫画详情'), findsNothing);
  });

  testWidgets('焦点在页内输入框时，ESC 照样冒到兜底层', (tester) async {
    final field = FocusNode();
    addTearDown(field.dispose);
    await _openChild(
      tester,
      Center(child: TextField(focusNode: field, autofocus: true)),
    );
    expect(field.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('顶层页'), findsOneWidget);
  });

  testWidgets('页内自己的 ESC 层先跑，handled 时兜底层不越级弹页', (tester) async {
    final calls = <String>[];
    await _openChild(
      tester,
      // 模拟媒体库的逐级返回：内层这一档还有东西要退，退掉就把事件吃掉
      Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
            calls.add('inner');
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: const Center(child: Text('集合正文')),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(calls, ['inner']);
    expect(find.text('集合正文'), findsOneWidget);
    expect(find.text('顶层页'), findsNothing);
  });

  testWidgets('页面挂着 PopScope 守卫时，ESC 交还给页面自己的退级逻辑', (tester) async {
    var intercepted = false;
    await _openChild(
      tester,
      PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) => intercepted = !didPop,
        child: const Center(child: Text('文件夹内')),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(intercepted, isTrue);
    expect(find.text('文件夹内'), findsOneWidget);
  });

  testWidgets('对话框开着时 ESC 只关掉弹层，不把底下的页弹掉', (tester) async {
    await _openChild(tester, const Center(child: Text('漫画阅读')));

    showDialog(context: tester.element(find.text('漫画阅读')), builder: (_) => const Text('提示'));
    await tester.pumpAndSettle();
    expect(find.text('提示'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // 弹层由 ModalBarrier 自己的 ESC 撤销处理收掉；底下的页必须原地不动，
    // 否则就是"关一个弹窗把整页也弹掉了"
    expect(find.text('提示'), findsNothing);
    expect(find.text('漫画阅读'), findsOneWidget);
  });

  testWidgets('侧栏直达的顶层页没有上一页，ESC 不动作', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EscapeBackBoundary(child: const Scaffold(body: Center(child: Text('Manga 首页')))),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Manga 首页'), findsOneWidget);
  });

  testWidgets('退回上层后再进一次，兜底层仍然接得住', (tester) async {
    await _openChild(tester, const Center(child: Text('漫画详情')));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('顶层页'), findsOneWidget);

    final context = tester.element(find.text('顶层页'));
    Navigator.of(context).pushNamed('/child');
    await tester.pumpAndSettle();
    expect(find.text('漫画详情'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('漫画详情'), findsNothing);
  });
}
