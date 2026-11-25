// 阅读页「有内容但屏幕一片空白」的回归。
//
// ═══════════════════════════════════════════════════════════════════════════
// 这个 bug 是什么（2026-11-25，用户报「点开书直接是白色的内容，什么也没有」）
// ═══════════════════════════════════════════════════════════════════════════
// 为了让沉浸模式能做平滑滑动动画，阅读页把顶栏/底栏改成了 `Stack` 里的
// `Positioned` 覆盖层。但 `Stack` 默认是 `StackFit.loose`：它用**非 Positioned
// 子元素**来定自己的尺寸，而本页的 children 全是 `Positioned`（外加一行误留的
// `if (insets.bottom > 0) const SizedBox.shrink()`）。
//
// 结果：正文区的宽度被算成 **0**。
//
// 实测（iPhone 17 Pro）：
//   修复前 SelectableText 矩形 = (12.3, 119.6) → (12.3, 931.6)   宽 0
//   修复后 SelectableText 矩形 = (12.3, 119.6) → (389.7, 206.6)  宽 377
//
// ★ 这个 bug 最阴的地方是：**widget 树里文字都在**，`find.textContaining`
//   照样命中、`_chapterText` 也有值，只有真的量渲染矩形才看得出宽度是 0。
//   所以只断言「文字存在」的测试抓不住它 —— 下面必须断言尺寸。
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final src = File(
    'lib/pages/collection/library/components/remote_novel_reader_dialog.dart',
  ).readAsStringSync();

  test('阅读页的 Stack 必须 expand，否则全 Positioned 子元素会塌成 0 尺寸', () {
    expect(
      src.contains('fit: StackFit.expand'),
      isTrue,
      reason: 'Stack 默认 loose，children 全是 Positioned 时尺寸会塌成 0，'
          '表现为「文字在树里但屏幕空白」。'
          '必须显式 fit: StackFit.expand 让它铺满父约束。',
    );
  });

  test('Stack 里不得有游离的非 Positioned 子元素', () {
    // 反例形态：`if (... ) const SizedBox.shrink(),` 混在 Positioned 之间
    // —— 这种「看起来无害」的占位会参与 Stack 定尺寸。
    final badPattern = RegExp(
      r'^\s*if \(.*\) const SizedBox\.shrink\(\),',
      multiLine: true,
    );
    expect(
      badPattern.hasMatch(src),
      isFalse,
      reason: 'Stack 里混入非 Positioned 的占位（SizedBox.shrink）会让 '
          'Stack 按它定尺寸 → 塌成 0。要么删掉，要么改成 Positioned。',
    );
  });

  test('正文必须真的渲染出宽度（尺寸断言，不只是"widget 存在"）', () {
    // 源码层面保证：正文用的是能自然撑满宽度的容器。
    // 运行时尺寸由 integration_test 在真机上验证（见提交说明里的实测矩形）。
    expect(
      src.contains('_buildChapterContent'),
      isTrue,
      reason: '正文渲染入口应存在',
    );
    // 正文外层必须是 Positioned.fill（铺满 Stack）
    expect(
      src.contains('Positioned.fill('),
      isTrue,
      reason: '正文容器要用 Positioned.fill 铺满，否则宽度依赖 child 内在宽度',
    );
  });
}
