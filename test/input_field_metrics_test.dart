import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/core/widgets/app_text_field.dart';

// 输入框尺寸守卫
//
// 踩过的坑：Material 3 的输入正文固定继承 textTheme.bodyLarge（本项目 14 / 行高 1.7），
// 主题的 inputDecorationTheme 却只写了 hint/label（scaleS(13)，且不含用户字号）。
// 三处不同源，于是——打字瞬间字号跳档、字号滑杆只拉动正文而占位符原地不动、
// 1.7 的行高把框撑到比同排按钮高一截。这里把三条都钉住：同源同档、随用户字号缩放、
// 与按钮同高；并守住 AppTextField 不丢 TextField 的默认行为。

/// 测试窗口的尺寸：与 page_golden 的 kTestWindowSize 一致，
/// 保证 scaleW/scaleS 的档位和真机开发窗口相同。
const Size _kWindowSize = Size(1440, 900);

Future<void> _pump(
  WidgetTester tester, {
  required double fontScale,
  Widget? field,
  Widget? trailing,
}) async {
  tester.view.physicalSize = _kWindowSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  AppTheme.fontScaleObs.value = fontScale;

  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: _kWindowSize,
      minTextAdapt: true,
      splitScreenMode: false,
      builder: (context, _) {
        AppTheme.resetMetrics();
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.buildCustomDark(
            AppTheme.kFollowThemeAccent,
            fontScale,
          ),
          home: Scaffold(
            backgroundColor: AppSemantic.dark.canvas,
            body: Center(
              child: SizedBox(
                width: 360,
                child: Row(
                  children: [
                    Expanded(
                      child:
                          field ??
                          const AppTextField(
                            decoration: InputDecoration(hintText: '搜索集合'),
                          ),
                    ),
                    if (trailing != null) ...[const SizedBox(width: 8), trailing],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// 标签当前生效的样式。
///
/// InputDecorator 是通过 AnimatedDefaultTextStyle 把 labelStyle/floatingLabelStyle
/// 下发给标签的，Text 自己没有 style；直接读排版产物才是最终生效的那一条。
TextStyle _labelStyle(WidgetTester tester) {
  final span = tester.renderObject<RenderParagraph>(find.text('集合名称')).text;
  return (span as TextSpan).style!;
}

void main() {
  tearDown(() {
    AppTheme.fontScaleObs.value = 1.0;
    AppTheme.resetMetrics();
  });

  group('AppTextField 正文样式', () {
    testWidgets('与占位符同源同档', (tester) async {
      await _pump(tester, fontScale: 1.0);
      final m = AppTheme.metrics;

      final input = tester.widget<EditableText>(find.byType(EditableText)).style;
      final hint = tester.widget<Text>(find.text('搜索集合')).style;

      expect(input.fontSize, m.fontSize13);
      expect(hint?.fontSize, m.fontSize13);
      expect(input.height, 1.4);
      expect(hint?.height, 1.4);
      // metrics.fontSize13 == scaleS(13) × 用户字号：正文与占位符都会跟着滑杆走
      expect(m.fontSize13, closeTo(scaleS(13), 0.01));
    });

    testWidgets('随字号滑杆一起缩放', (tester) async {
      await _pump(tester, fontScale: 1.0);
      final base = tester
          .widget<EditableText>(find.byType(EditableText))
          .style
          .fontSize!;

      await _pump(tester, fontScale: 1.5);
      final scaled = tester
          .widget<EditableText>(find.byType(EditableText))
          .style
          .fontSize!;
      final hint = tester.widget<Text>(find.text('搜索集合')).style!.fontSize!;

      expect(scaled / base, closeTo(1.5, 0.02));
      expect(hint / base, closeTo(1.5, 0.02));
    });

    testWidgets('调用点显式样式仍然优先', (tester) async {
      await _pump(
        tester,
        fontScale: 1.0,
        field: const AppTextField(
          style: TextStyle(fontSize: 20, fontFamily: 'monospace'),
        ),
      );

      final input = tester.widget<EditableText>(find.byType(EditableText)).style;
      expect(input.fontSize, 20);
      expect(input.fontFamily, 'monospace');
      // 调用点没写的档仍由封装补齐
      expect(input.height, 1.4);
    });
  });

  group('AppTextField 不丢 TextField 的默认行为', () {
    test('构造默认值仍来自 TextField', () {
      const field = AppTextField();
      expect(field.maxLines, 1);
      expect(field.textCapitalization, TextCapitalization.none);
      expect(field.obscuringCharacter, '•');
      expect(field.clipBehavior, Clip.hardEdge);
      // 右键/长按菜单的默认构建器不能被 super 参数转成 null
      expect(field.contextMenuBuilder, isNotNull);
      expect(field.decoration, isA<InputDecoration>());
    });

    testWidgets('转发生效：密文输入与 onChanged', (tester) async {
      var last = '';
      await _pump(
        tester,
        fontScale: 1.0,
        field: AppTextField(
          obscureText: true,
          onChanged: (v) => last = v,
          decoration: const InputDecoration(hintText: '节点密钥'),
        ),
      );

      await tester.enterText(find.byType(EditableText), 'abc');
      expect(last, 'abc');
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).obscureText,
        isTrue,
      );
    });
  });

  group('框高与控件档', () {
    testWidgets('与同排按钮齐平', (tester) async {
      await _pump(
        tester,
        fontScale: 1.0,
        trailing: FilledButton(
          onPressed: () {},
          child: const Text('取消'),
        ),
      );
      final m = AppTheme.metrics;

      final fieldHeight = tester.getSize(find.byType(InputDecorator)).height;
      final buttonHeight = tester.getSize(find.byType(FilledButton)).height;

      expect(fieldHeight, greaterThanOrEqualTo(m.kSpace32 - 1));
      expect((fieldHeight - buttonHeight).abs(), lessThan(4.0));
    });

    testWidgets('带浮动标签时框高不变', (tester) async {
      await _pump(tester, fontScale: 1.0);
      final plain = tester.getSize(find.byType(InputDecorator)).height;

      await _pump(
        tester,
        fontScale: 1.0,
        field: const AppTextField(
          decoration: InputDecoration(labelText: '集合名称'),
        ),
      );
      final withLabel = tester.getSize(find.byType(InputDecorator)).height;

      // 描边框的浮动标签骑在边框线上（floatingLabelHeight = 0），不吃纵向空间
      expect(withLabel, closeTo(plain, 1.0));
      // 未浮起时标签和正文同档，占位读起来与输入一致
      expect(_labelStyle(tester).fontSize, AppTheme.metrics.fontSize13);

      // 有内容后标签浮到边框上：Flutter 会再乘一档 0.75 缩放，
      // 所以主题的 floatingLabelStyle 给 16 档，落到边框上正好是 12。
      // 注意不能 pumpAndSettle：光标闪烁是无限动画。
      await tester.enterText(find.byType(EditableText), '夏日');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(_labelStyle(tester).fontSize, AppTheme.metrics.fontSize16);
    });
  });
}
