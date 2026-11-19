// 真 macOS App 冒烟：先把「真 App 能起来 + 数据全落在沙箱」这条地基验穿。
//
// ═══════════════════════════════════════════════════════════════════════════
// 这个测试在证明什么
// ═══════════════════════════════════════════════════════════════════════════
// 用户原话是「请使用真实的客户端的测试，以复现客户才会遇到的问题」。
// 之前的 e2e 都是 `flutter test`（flutter_tester 无头引擎），而用户手上
// 跑的是打包出来的 macOS .app：真 Cocoa 窗口、真 NSApplication、真插件
// （path_provider / shared_preferences / window_manager / media_kit）、
// 真 Rust framework。两者在**平台通道**这一层就是不同的实现，很多缺陷
// 只会在真 .app 里出现（典型例子：NSHomeDirectory 忽略 HOME，
// 于是 ledger.db 照样写进开发者真实目录）。
//
// 所以这个文件必须用真设备跑：
//   /private/tmp/fl/flutter/bin/flutter test integration_test/real_app_smoke_test.dart -d macos --no-pub
//
// 它验证两件事：
//   1. 真 .app 能启动到主界面（跑真实的 main()，不是拼个假页面）。
//   2. **数据隔离生效**：Rust 侧（读 $HOME）与 macOS 壳里的平台通道
//      （NSHomeDirectory / UserDefaults）全部落在测试沙箱目录里，
//      开发者那份 217MB 的真实 media.db 一个字节都没被碰。
//
// ═══════════════════════════════════════════════════════════════════════════
// 数据隔离的机制（本机实测，两个变量缺一不可）
// ═══════════════════════════════════════════════════════════════════════════
//   · HOME              —— Rust 各模块用 `$HOME/Library/Application Support/SlimeWorks`
//                          推数据库路径（db_module/src/paths.rs）。
//   · CFFIXED_USER_HOME —— 只设 HOME **不够**：macOS 的 NSHomeDirectory() 不读
//                          HOME，path_provider 的 getApplicationSupportDirectory()
//                          与 UserDefaults（shared_preferences）都跟着它走，
//                          于是 ledger.db / prefs.plist 仍写进开发者真实目录。
//                          实测：HOME=/tmp/x 时 NSHomeDirectory 仍是 /Users/xxx；
//                          加上 CFFIXED_USER_HOME=/tmp/x 后两者都变成 /tmp/x。
//
// 跑法（两个变量都必须带，且目录要先建好）：
//   mkdir -p /tmp/sw_real_app_home
//   HOME=/tmp/sw_real_app_home CFFIXED_USER_HOME=/tmp/sw_real_app_home \
//     SLIME_E2E_HOME=/tmp/sw_real_app_home \
//     /private/tmp/fl/flutter/bin/flutter test integration_test/real_app_smoke_test.dart -d macos --no-pub
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 必须带前缀：测试文件自己的 main() 会遮蔽 App 的 main()，
// 不加前缀调用的其实是测试入口本身（analyze 会报 use_of_void_result）。
import 'package:slime_works/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// 沙箱根目录：测试自己从环境变量读，没给就整组跳过。
  ///
  /// 这里不复用 test/helpers/e2e_headless_node.dart 的闸门，因为那个是按
  /// 「flutter test 无头」写的；真 App 场景多一条 CFFIXED_USER_HOME 判据。
  final home = Platform.environment['HOME'] ?? '';
  final cffixed = Platform.environment['CFFIXED_USER_HOME'] ?? '';
  final sandbox = Platform.environment['SLIME_E2E_HOME'] ?? '';
  final isolated =
      sandbox.isNotEmpty && home.startsWith(sandbox) && cffixed.startsWith(sandbox);

  if (!isolated) {
    test('真 App 冒烟已跳过（未做数据隔离）', () {
      // ignore: avoid_print
      print('''
未隔离数据目录，已跳过真 App 用例（保护你真实的媒体库）。

当前环境：
  HOME               = ${home.isEmpty ? '<空>' : home}
  CFFIXED_USER_HOME  = ${cffixed.isEmpty ? '<空>' : cffixed}
  SLIME_E2E_HOME     = ${sandbox.isEmpty ? '<空>' : sandbox}

正确跑法（三个变量都要指到同一个临时目录，且目录已存在）：
  mkdir -p /tmp/sw_real_app_home
  HOME=/tmp/sw_real_app_home CFFIXED_USER_HOME=/tmp/sw_real_app_home \\
    SLIME_E2E_HOME=/tmp/sw_real_app_home \\
    /private/tmp/fl/flutter/bin/flutter test integration_test/real_app_smoke_test.dart -d macos --no-pub
''');
    }, skip: '未隔离数据目录');
    return;
  }

  testWidgets('R0 真 App 启动 + 数据隔离（这一条不过，后面的场景全部不可信）', (tester) async {
    // ── 第一步：跑真实的 main()，等价于用户双击 .app ──────────────────
    // main() 内部会：加载 .env → getItInit → 窗口管理器 → 系统托盘 →
    // RustLib.init（真 Rust framework）→ NodeSettingsService.init →
    // 主题 → runApp(MyApp) → _postAppInit（日志/节点预热/ffmpeg/记账库…）。
    app.main();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // 首帧之后还有一串异步初始化，全是真实 I/O，必须给真实时间；
    // 用 runAsync 推进真实事件循环，用 pump 推进帧（两者交替，见之前
    // e2e 踩过的 fake-async 坑：单靠任一方都到不了稳定态）。
    final probe = <String>[];
    for (var i = 0; i < 80; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump(const Duration(milliseconds: 40));
      if (i % 20 == 0) probe.add('t=${i * 150}ms elems=${tester.allElements.length}');
    }
    // ignore: avoid_print
    print('[冒烟] 启动轨迹 ${probe.join(' | ')}');

    // ── 第二步：App 真的起来了（树不是空的）──────────────────────────
    // 注意：不要去断言某个具体文案。用户首启可能落 dashboard、也可能弹引导；
    // 那是产品行为，不是本次要测的东西。这里只证明「启动链路活到了首帧之后」。
    final elementCount = tester.allElements.length;
    // ignore: avoid_print
    print('[冒烟] 最终 element 数=$elementCount');
    expect(
      elementCount,
      greaterThan(100),
      reason: '真 App 首帧之后应有完整 widget 树；元素数过少说明启动链路断了',
    );

    // ── 第三步：命门——平台通道拿到的目录必须全在沙箱里 ────────────────
    final supportDir = await getApplicationSupportDirectory();
    final docsDir = await getApplicationDocumentsDirectory();
    // ignore: avoid_print
    print('[冒烟] appSupport=${supportDir.path}');
    // ignore: avoid_print
    print('[冒烟] appDocs=${docsDir.path}');

    expect(
      supportDir.path.startsWith(sandbox),
      isTrue,
      reason: 'Application Support 必须落在沙箱 $sandbox 内，实际 ${supportDir.path}\n'
          '否则真 App 会把 ledger.db / ffmpeg / 缓存写进开发者真实目录',
    );
    expect(
      docsDir.path.startsWith(sandbox),
      isTrue,
      reason: 'Documents 必须落在沙箱内，实际 ${docsDir.path}',
    );

    // shared_preferences（UserDefaults）同样依赖 NSHomeDirectory。
    // 写一个探针键，隔离生效时它只会落在沙箱的 Preferences 里。
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sw_e2e_isolation_probe', 'sandboxed');
    // ignore: avoid_print
    print('[冒烟] prefs 探针已写入');

    // ── 第四步：Rust 侧的数据目录也落在沙箱 ──────────────────────────
    // Rust 各模块按 $HOME/Library/Application Support/SlimeWorks 推路径；
    // 这个目录存在就说明 HOME 真的传进进程了（而不是被 Cocoa 改掉）。
    final rustDir = Directory('$sandbox/Library/Application Support/SlimeWorks');
    // ignore: avoid_print
    print('[冒烟] rust 数据目录存在=${rustDir.existsSync()} path=${rustDir.path}');
    expect(
      rustDir.existsSync(),
      isTrue,
      reason: 'Rust 应在沙箱下建出数据目录 $rustDir（不存在说明 HOME 没生效）',
    );

    // ── 第五步：真 App 应该报出「自己是真 macOS 进程」的证据 ─────────
    // 无头 flutter_tester 里 Platform.isMacOS 也是 true，所以这条不能靠它；
    // 真正的区分点是：integration_test 绑定在真引擎上跑，且窗口有真实
    // 设备像素比 + 真实视图。这里把证据打印出来留档，不做硬断言。
    // ignore: avoid_print
    print('[冒烟] platform=${Platform.operatingSystem} '
        'dpr=${tester.view.devicePixelRatio} '
        'viewSize=${tester.view.physicalSize}');
  });
}
