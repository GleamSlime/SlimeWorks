// 顶层变量遮蔽 `BaseViewModel.isInitialized` 的回归。
//
// ═══════════════════════════════════════════════════════════════════════════
// 这个 bug 是什么（2026-11-21，用户报「移动端选了远程节点还是没书库」）
// ═══════════════════════════════════════════════════════════════════════════
// `lib/core/provider/main.dart` 里有个**顶层变量** `bool isInitialized`，
// 原本只用来给 `getItInit()` 做幂等守卫。而 ViewModel 文件普遍
// `import 'package:slime_works/core/provider/main.dart'`（为了拿 `getIt`）。
//
// Dart 的作用域规则下，子类方法体里裸写 `isInitialized` 会解析到**这个顶层
// 变量**，而不是基类的 `BaseViewModel.isInitialized` getter：
//
//   Future<void> onInitAsync() async {
//     if (isInitialized) return;   // ← 读的是顶层变量，不是本 VM 的状态
//     ...
//   }
//
// `main()` 里 `getItInit()` 一跑就把它置成 true，于是 VM 的
// `onInitAsync()` **永远在第一步就 return**：
//   · `refreshRemoteNovels()` 一次都没执行 → 远程书库永远空；
//   · 本机模式靠别处直接读 FFI 照样有数据，把这个坑完全盖住；
//   · `MediaLibraryViewModel` 同款写法，也受影响。
//
// 这是个**不报错、只静默跑错分支**的隐式遮蔽。修法：把顶层变量改名成
// `diRegistryInitialized`（语义也更准），VM 里的 `isInitialized` 就恢复
// 指向基类 getter。
//
// 下面这几条断言都是「改名之后才可能成立」的，回退改名会立刻变红。
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('provider/main.dart 不得再导出名为 isInitialized 的顶层变量', () async {
    final src = File('lib/core/provider/main.dart').readAsStringSync();
    // 允许出现 `BaseViewModel.isInitialized` 这类带前缀的写法，
    // 但**不允许**有裸的顶层声明 `bool isInitialized`。
    final bareDecl = RegExp(r'^\s*bool\s+isInitialized\s*=', multiLine: true);
    expect(
      bareDecl.hasMatch(src),
      isFalse,
      reason: '顶层 bool isInitialized 会遮蔽 BaseViewModel.isInitialized，'
          '让 VM 的 onInitAsync() 静默提前返回（远程书库永远空）',
    );
    expect(
      src.contains('diRegistryInitialized'),
      isTrue,
      reason: 'DI 幂等守卫应使用语义明确的 diRegistryInitialized',
    );
  });

  test('ViewModel 的 onInitAsync 不得被顶层变量遮蔽', () async {
    // 这两个文件都 import 了 provider/main.dart，是最容易踩的行。
    for (final f in <String>[
      'lib/view_models/novel_library_viewmodel.dart',
      'lib/view_models/media_library_viewmodel.dart',
    ]) {
      final src = File(f).readAsStringSync();
      if (!src.contains('import \'package:slime_works/core/provider/main.dart\'')) {
        continue; // 没导入就不可能被遮蔽
      }
      // 只要它同时用了裸 isInitialized，就必须确认 provider 那边已经改名
      if (RegExp(r'\bif\s*\(\s*!?isInitialized\s*\)').hasMatch(src)) {
        final provider = File('lib/core/provider/main.dart').readAsStringSync();
        expect(
          RegExp(r'^\s*bool\s+isInitialized\s*=', multiLine: true)
              .hasMatch(provider),
          isFalse,
          reason: '$f 裸用了 isInitialized 且 import 了 provider/main.dart；'
              'provider 那边必须先改名，否则两者会串在一起',
        );
      }
    }
  });
}
