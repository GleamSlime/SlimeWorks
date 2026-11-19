// 真 App 冒烟（最小版）：跑在真 macOS App 里的「Rust 桥接是否可用」自检。
//
// ═══════════════════════════════════════════════════════════════════════════
// 这个文件在证明什么
// ═══════════════════════════════════════════════════════════════════════════
// 这是仓库最初 Initial commit 留下的模板测试，原本断言首页上有一句
// `Result: `Hello, Tom!`` —— 那句文案早就从 UI 里删掉了，于是这条测试
// 长期处于「必然失败」的死状态。它失败时还会**连带打断整个
// `flutter test integration_test/` 的后续文件**（同一进程退出），
// 造成「真 App 测试根本跑不起来」的假象。
//
// 现在把它改成本来该有的样子：不复刻 UI 文案，只验证真 App 里
// **Rust 桥接真的通了**。UI 文案属于产品行为、天天会变；Rust 桥接是地基。
//
// 跑法（真设备，不是 flutter_tester）：
//   mkdir -p /tmp/sw_real_app_home
//   HOME=/tmp/sw_real_app_home CFFIXED_USER_HOME=/tmp/sw_real_app_home \
//     SLIME_E2E_HOME=/tmp/sw_real_app_home \
//     CARGO_HOME=$HOME/.cargo RUSTUP_HOME=$HOME/.rustup \
//     /private/tmp/fl/flutter/bin/flutter test integration_test/simple_test.dart -d macos --no-pub
//
// ★ 两个环境变量缺一不可（真 App 会写真实目录）：
//   - HOME              → Rust 侧各模块的数据目录
//   - CFFIXED_USER_HOME → macOS 的 NSHomeDirectory()（path_provider /
//                         UserDefaults 全跟它走，只设 HOME 拦不住）
//
// 完整的真 App 用户场景见 real_app_node_test.dart；这里只做地基自检。
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:slime_works/src/rust/api/simple.dart' as simple_api;
import 'package:slime_works/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());

  testWidgets('真 App 里 Rust 桥接可用', (WidgetTester tester) async {
    // 能走到这里就说明 RustLib.init() 在真 .app 进程里加载成功了
    // （framework 由 macos/Podfile + cargokit 打进 App bundle）。
    // 真实 FFI 调用必须放进 runAsync：testWidgets 默认在 fake-async 区，
    // 真实完成回调不会被推进，直接 await 会挂到超时且没有任何日志。
    final greeted = await tester.runAsync(
      () async => simple_api.greet(name: 'SlimeWorks'),
    );
    expect(greeted, contains('SlimeWorks'));

    // 真 App 进程的特征值，留档便于排障时区分「真设备」与 flutter_tester
    // ignore: avoid_print
    print(
      '[smoke] platform=${Platform.operatingSystem} '
      'dpr=${tester.view.devicePixelRatio} '
      'viewSize=${tester.view.physicalSize}',
    );
  });
}
