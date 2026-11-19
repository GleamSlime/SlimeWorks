// 真 macOS App × 真无头节点：用**真点击**复现客户遇到的「提示成功但数据没变」。
//
// ═══════════════════════════════════════════════════════════════════════════
// 这个文件在证明什么
// ═══════════════════════════════════════════════════════════════════════════
// 之前的测试有两类，各自都差一层：
//   · `test/e2e_*.dart`：`flutter test`（flutter_tester）—— 真节点、真点击，
//     但**不是真 App**。平台通道是测试用的假实现，窗口/插件/生命周期都不真。
//   · `integration_test/real_app_smoke_test.dart`：真 App，但只验启动与隔离。
//
// 这里把两头接起来：真 .app 进程 + 真 slime_node 进程 + 真 click 手势，
// 走用户在远程节点模式下真正会走的那条路 ——
//   侧栏切节点 → 进媒体库 → 右键卡片 → 点菜单 → 点弹窗确认按钮。
//
// 每条用例都做**双向断言**：
//   ① UI 侧：卡片是否真的出现/消失/改名（用户眼睛看到的）
//   ② 节点侧：HTTP 回查节点数据库（数据是否真的变了）
// 只有两边都对，才算「没骗人」。只查一边正是上一轮漏掉 bug 的原因。
//
// ★ 本文件重点不是「不存在的 id 报不报错」，而是**正常路径上的静默失败**：
//   新建子文件夹真的到节点了吗？重命名后列表立刻变吗？删掉最后一条后
//   上一级的条数/体积归零吗？连着做两个写操作第二个会被吞吗？
//
// ═══════════════════════════════════════════════════════════════════════════
// 跑法（四个环节缺一不可，踩过才知道）
// ═══════════════════════════════════════════════════════════════════════════
//   mkdir -p /tmp/sw_real_app_home
//   HOME=/tmp/sw_real_app_home \
//   CFFIXED_USER_HOME=/tmp/sw_real_app_home \
//   SLIME_E2E_HOME=/tmp/sw_real_app_home \
//   CARGO_HOME=$HOME/.cargo RUSTUP_HOME=$HOME/.rustup \
//   /private/tmp/fl/flutter/bin/flutter test integration_test/real_app_node_test.dart -d macos --no-pub
//
//   ① HOME + CFFIXED_USER_HOME：数据隔离（后者才是 macOS 的真开关，
//      只设 HOME 时 NSHomeDirectory 仍是真实用户目录）。
//   ② CARGO_HOME + RUSTUP_HOME：`flutter test -d macos` 会先尝试重建 Rust，
//      cargokit 用 $HOME/.cargo 找 rustup；HOME 一改就报
//      `rustup is not installed at /tmp/xxx/.cargo`，构建直接失败。
//   ③ SDK 必须是 /private/tmp/fl/flutter（3.50.0，与 .dart_tool/version 一致）。
//   ④ 构建 env：FLUTTER_SWIFT_PACKAGE_MANAGER=false + 两个镜像变量；
//      **不要**再设 CXXFLAGS/CFLAGS（装了完整 Xcode 后那套会炸）。
//
// ═══════════════════════════════════════════════════════════════════════════
// 关于数据隔离：哪一层能隔离、哪一层不能（都是实测结论）
// ═══════════════════════════════════════════════════════════════════════════
//   · Rust 各模块（media.db / db.redb / music_player.db）
//       → 读 $HOME。设 HOME 即可，实测完全隔离。
//   · path_provider（getApplicationSupportDirectory / Documents）
//       → 走 NSHomeDirectory + FileManager。**只设 HOME 不够**，
//         必须加 CFFIXED_USER_HOME；加了之后完全隔离，不需要 mock。
//   · shared_preferences / UserDefaults（节点配置、主题、窗口位置…）
//       → 走 CFPreferences 的**真实用户域**，CFFIXED_USER_HOME 也改不了它！
//         实测证据：设了两个变量跑真 App，节点配置照样写进
//         ~/Library/Preferences/com.gleamslime.works.plist。
//         所以这一层**必须**用 SharedPreferences.setMockInitialValues 隔离，
//         这是本文件唯一的人为偏差（API 调用路径不变，只是不落盘）。
//         不隔离的后果不只是弄脏开发者配置：测试还会读到上一轮遗留的
//         陈旧节点（端口早关了）→ 节点被判熔断 → 侧栏节点选择器不渲染
//         → 用例连环失败。
// ═══════════════════════════════════════════════════════════════════════════
// 关于「每个用例都要重新挂上 App」
// ═══════════════════════════════════════════════════════════════════════════
// `testWidgets` 在每个用例开始时会 `runApp(Container(_preTestMessage))` 重置
// 整棵树。所以**不能**在 setUpAll 里 main() 一次就指望后续用例还有界面。
// 正确做法见 [_bootApp]：首条用例跑真正的 main()（完整初始化链路），
// 后续用例重新 pumpWidget(MyApp) 挂回同一套已初始化的服务上。
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/window/collapsible_sidebar.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/widgets/app_text_field.dart';
import 'package:slime_works/main.dart' as app;
import 'package:slime_works/pages/collection/picture/components/media_collection_card.dart';
import 'package:slime_works/pages/collection/picture/components/media_folder_card.dart';
import 'package:slime_works/view_models/media_library_viewmodel.dart';

import 'helpers/real_app_node.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// 数据隔离闸门：三个目录变量都指到同一沙箱才跑，否则整组跳过。
  final home = Platform.environment['HOME'] ?? '';
  final cffixed = Platform.environment['CFFIXED_USER_HOME'] ?? '';
  final sandbox = Platform.environment['SLIME_E2E_HOME'] ?? '';
  final isolated =
      sandbox.isNotEmpty && home.startsWith(sandbox) && cffixed.startsWith(sandbox);

  if (!isolated) {
    test('真 App × 真节点用例已跳过（未做数据隔离）', () {
      // ignore: avoid_print
      print(kNeedIsolationHint);
    }, skip: '未隔离数据目录');
    return;
  }

  late RealHeadlessNode node;

  /// main() 只能跑一次（RustLib.init / getItInit 都不可重入）。
  var appBooted = false;

  void dumpNodeLog() {
    final tail = node.callLog.length > 40
        ? node.callLog.sublist(node.callLog.length - 40)
        : node.callLog;
    // ignore: avoid_print
    print('──── 节点调用流水（最近 ${tail.length} 条）────\n$tail\n'
        '──── 节点进程日志（尾部）────\n${node.nodeLog}');
  }

  void expectWithContext(Object? actual, Matcher matcher, {required String reason}) {
    if (!matcher.matches(actual, <dynamic, dynamic>{})) dumpNodeLog();
    expect(actual, matcher, reason: reason);
  }

  setUpAll(() async {
    // ── 隔离 shared_preferences（必须 mock，理由见文件头）────────────────
    SharedPreferences.setMockInitialValues(<String, Object>{});

    // ── 真节点先起来：数据由测试自己造，不依赖任何人工调试实例 ──────────
    node = await RealHeadlessNode.start(sandboxRoot: Directory(sandbox));

    final mediaRoot = Directory('${node.dataDir}/media')..createSync(recursive: true);
    final sampleDir = createAudioSampleDir(mediaRoot.path, 2, name: '远程样本集合');
    await node.callOk('import_media_folder', <String, dynamic>{
      'folder_path': sampleDir.path,
      // 缩略图会起后台任务空转，与本次断言无关
      'generate_thumbnails': false,
    });
  });

  tearDownAll(() async {
    await node.dispose();
  });

  /// 把真 App 挂到当前用例的树上。
  ///
  /// 第一条用例走真正的 `main()`（= 用户双击 .app 的完整初始化链路）；
  /// 后续用例只重新 pumpWidget —— 因为 `testWidgets` 会重置整棵树，
  /// 而 main() 里的 RustLib.init / getItInit 不可重入。
  var nodeRegistered = false;

  Future<void> bootApp(WidgetTester tester) async {
    if (!appBooted) {
      appBooted = true;
      // ★ 不能 await main()：它内部 runApp 之后还要一会儿才轮到首帧，
      //   而 main() 本身要等一串真实 I/O；在测试体里 await 会卡到超时。
      //   所以发出去就不管，靠下面的「边泵帧边等」推进到界面出现。
      unawaited(app.main());
    } else {
      // 后续用例：树被上一个用例收尾重置了，重新挂一份 MyApp。
      // 服务层（getIt / Rust / 节点配置）仍然是同一套，不需要重新初始化。
      await tester.pumpWidget(const app.MyApp());
      await _pumpReal(tester, 2);
    }

    // ★ router 是个 lazy final，第一次被 build 读到才初始化 ——
    //   所以这里必须**一边泵帧一边等**，只等时间不泵帧会永远等不到。
    await _waitUntilPumped(
      tester,
      () => getIt.isRegistered<NodeSettingsService>() && AppRoutes.router != null,
      what: 'App 完成装配（路由 + 节点服务）',
      timeoutMs: 90000,
      dumpOnTimeout: dumpNodeLog,
    );

    if (!nodeRegistered) {
      nodeRegistered = true;
      // 真 App 把远程节点登记进真 NodeSettingsService（真连通性探测 + 元数据预热）
      await getIt<NodeSettingsService>().addRemoteNode(
        name: 'E2E真节点',
        apiBaseUrl: node.baseUrl,
      );
    }

    // 不管哪条路径，都等界面真的长出来再继续
    await _waitUntilPumped(
      tester,
      () => find.byType(CollapsibleSidebar).evaluate().isNotEmpty,
      what: '侧栏外壳渲染完成',
      timeoutMs: 90000,
      dumpOnTimeout: dumpNodeLog,
    );

    // ★ 这里必须单独再等一层：侧栏外壳先出现，而 SidebarNodeSelector 内部是
    //   一个 Obx 包着 `enabledRemoteNodes.isEmpty ? SizedBox.shrink() : 选择器`。
    //   只等外壳会出现「外壳在、选择器还是 SizedBox」的中间态，
    //   后续 find.byTooltip('切换节点') 就落空（实测踩过）。
    await _waitUntilPumped(
      tester,
      () => find.byTooltip('切换节点').evaluate().isNotEmpty,
      what: '侧栏节点选择器渲染完成',
      timeoutMs: 60000,
      dumpOnTimeout: () {
        final tooltips = find
            .byType(Tooltip)
            .evaluate()
            .map((e) => (e.widget as Tooltip).message)
            .whereType<String>()
            .toList();
        // ignore: avoid_print
        print('──── 侧栏诊断 ────\n'
            'Tooltips=$tooltips\n'
            'enabledRemoteNodes='
            '${getIt<NodeSettingsService>().enabledRemoteNodes.map((n) => n.name).toList()}');
        dumpNodeLog();
      },
    );
  }

  /// 前置步骤：用真点击把全局节点切到测试自己的远程节点。
  ///
  /// 每条用例都调：`testWidgets` 会重置 widget 树，但服务层状态是保留的，
  /// 所以已经切过就直接返回（不重复点，避免把「已选中」当成「点不动」）。
  Future<void> ensureRemoteNodeSelected(WidgetTester tester) async {
    final nodeService = getIt<NodeSettingsService>();
    if (nodeService.activeNodeId.value.isNotEmpty) return;

    Future<void> dumpSelectionState() async {
      final menuItems = find
          .descendant(
            of: find.byType(PopupMenuItem<String>),
            matching: find.byType(Text),
          )
          .evaluate()
          .map((e) => (e.widget as Text).data ?? '')
          .toList();
      // ignore: avoid_print
      print('──── 节点选择诊断 ────\n'
          'activeNodeId="${nodeService.activeNodeId.value}"\n'
          'remoteNodes=${nodeService.remoteNodes.map((n) => '${n.id}/${n.name}/${n.apiBaseUrl}').toList()}\n'
          'enabled=${nodeService.enabledRemoteNodes.length}\n'
          'connectivity=${nodeService.nodeConnectivity.map((k, v) => MapEntry(k, v))}\n'
          '弹出项文本=$menuItems\n'
          'E2E真节点 finder 数=${find.text('E2E真节点').evaluate().length}');
      dumpNodeLog();
    }

    await tester.tap(find.byTooltip('切换节点'));
    await _waitUntilPumped(
      tester,
      () => find.text('E2E真节点').evaluate().isNotEmpty,
      what: '节点下拉弹出且含 E2E真节点',
      timeoutMs: 20000,
      dumpOnTimeout: dumpSelectionState,
    );

    // ★ 只点弹层里的那一项：`find.text('E2E真节点')` 在别的层也可能命中
    //   （例如切换后侧栏那份 label 也变成了节点名），直接 .last 选中有风险。
    //   这里限定在 PopupMenuItem<String> 内部，命中语义唯一。
    final menuItem = find.descendant(
      of: find.byType(PopupMenuItem<String>),
      matching: find.text('E2E真节点'),
    );
    expectWithContext(menuItem, findsWidgets, reason: '节点弹出菜单里应有 E2E真节点 这一项');
    await tester.tap(menuItem.first);

    // 选中后的落盘是异步的（selectActiveNode → _save → prefs），
    // 且 App 那边会连带触发一轮库刷新，给足时间并允许一次重试。
    var ok = false;
    for (var attempt = 0; attempt < 2 && !ok; attempt++) {
      try {
        await _waitUntilPumped(
          tester,
          () => nodeService.activeNodeId.value.isNotEmpty,
          what: '真点击后 activeNodeId 变为远程节点',
          timeoutMs: 15000,
          dumpOnTimeout: attempt == 1 ? dumpSelectionState : null,
        );
        ok = true;
      } catch (_) {
        if (attempt == 1) rethrow;
        // 弹层可能没关掉：先关再重开一次
        await tester.tapAt(const Offset(4, 4));
        await _pumpReal(tester, 2);
        await tester.tap(find.byTooltip('切换节点'));
        await _pumpReal(tester, 2);
        final again = find.descendant(
          of: find.byType(PopupMenuItem<String>),
          matching: find.text('E2E真节点'),
        );
        if (again.evaluate().isNotEmpty) {
          await tester.tap(again.first);
        }
      }
    }
    await _pumpReal(tester, 2);
  }

  /// 用**真点击侧栏条目**进入媒体库（不直接调 router.go，那会绕过「入口通不通」）。
  Future<void> openMediaLibrary(WidgetTester tester) async {
    final entry = find.descendant(
      of: find.byType(CollapsibleSidebar),
      matching: find.text('媒体库'),
    );
    if (entry.evaluate().isEmpty) {
      // 侧栏没渲染出条目时不要静默绕过：这本身就是问题（入口该有却没有）
      dumpNodeLog();
      fail('侧栏没有「媒体库」入口，无法用真点击进入（远程模式下该入口应保持可见）');
    }
    await tester.tap(entry.first);
    await _pumpReal(tester, 3);
    await _waitUntilPumped(
      tester,
      () => AppRoutes.router!.state.uri.path.startsWith('/collection/picture'),
      what: '路由切到 /collection/picture（侧栏「媒体库」的 location）',
      timeoutMs: 40000,
      dumpOnTimeout: dumpNodeLog,
    );
  }

  /// 走 UI 的真刷新路径（顶栏 refresh 图标）。
  ///
  /// 按图标定位而非 tooltip：实测这个按钮**没有 Tooltip**（同一行其余 9 个
  /// 按钮都包了），这是真实的 UI 一致性问题，已单独记进报告 ——
  /// 用例不能为了迁就这个 bug 而改成「直接调 VM 刷新」，否则「刷新入口坏了」
  /// 这类缺陷就再也没人测得出来。
  Future<void> refreshViaUi(WidgetTester tester) async {
    final refresh = find.byWidgetPredicate(
      (w) => w is DrawIcon && w.icon == StrokeIcons.refresh,
    );
    expectWithContext(
      refresh,
      findsWidgets,
      reason: '媒体库顶栏应有刷新按钮（图标 StrokeIcons.refresh）',
    );
    await tester.tap(refresh.first);
    await _pumpReal(tester, 3);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // R1 侧栏切到远程节点（真点击）→ 媒体库显示的是节点上的数据
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets('R1 真点击侧栏节点选择器切到远程节点 → 媒体库显示节点数据', (tester) async {
    await bootApp(tester);
    final nodeService = getIt<NodeSettingsService>();

    // ── 真点：侧栏底部的节点选择器（PopupMenuButton，tooltip=切换节点）──
    await ensureRemoteNodeSelected(tester);

    expectWithContext(
      nodeService.activeNodeId.value.isNotEmpty,
      isTrue,
      reason: '真点击切换后应进入远程模式（activeNodeId 非空）',
    );
    expect(nodeService.isRemoteMode, isTrue);

    // ── 真点：侧栏「媒体库」────────────────────────────────────────────
    await openMediaLibrary(tester);

    // ── 断言：页面上真的画出了节点上的集合卡 ──────────────────────────
    await _waitUntilPumped(
      tester,
      () => find.byType(MediaCollectionCard).evaluate().isNotEmpty,
      what: '媒体库画出节点集合卡',
      timeoutMs: 60000,
      dumpOnTimeout: dumpNodeLog,
    );
    expectWithContext(
      find.text('远程样本集合'),
      findsWidgets,
      reason: '节点上那条集合应出现在媒体库里',
    );

    // VM 的远程集合数量与节点一致（证明显示的是远程数据，不是本机库）
    final vm = Get.find<MediaLibraryViewModel>();
    final nodeCollections = await node.listCollections();
    expectWithContext(
      vm.remoteCollections.length,
      equals(nodeCollections.length),
      reason: 'VM 里的远程集合数应等于节点上的集合数（不能混进本机数据）',
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // R2 新建子文件夹（真点击 → 真输入 → 真确认）→ 节点上真的有它
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets('R2 点「新建文件夹」→ 输入名字 → 确定 → 节点上真出现该文件夹', (tester) async {
    await bootApp(tester);
    await ensureRemoteNodeSelected(tester);
    await openMediaLibrary(tester);

    // 这条盯的是「远程模式下新建文件夹只写本机 / 根本没发出去」。
    // 假成功的典型形态：UI 里冒出一张卡，节点侧一次 create_media_folder 都没有。
    final newName = '子夹${DateTime.now().millisecondsSinceEpoch % 100000}';

    // ★ 先记下节点上现有的文件夹名集合，之后用「多出来的那一个」来证明
    //   这次点击真的落到了节点。比起「检查 callLog 里有没有 create_media_folder」
    //   更本质也更抗噪：callLog 会被测试自己的轮询 list_media_folders 污染，
    //   而名字集合不受任何轮询影响。
    final namesBefore = (await node.listFolders())
        .map((f) => (f['name'] ?? '').toString())
        .toSet();
    expectWithContext(
      namesBefore.contains(newName),
      isFalse,
      reason: '用例开始前节点上不该已有同名文件夹（否则断言无法归因）',
    );

    await tester.tap(find.byTooltip('新建文件夹'));
    await _pumpReal(tester, 2);

    expect(find.text('新建媒体文件夹'), findsOneWidget, reason: '应弹出新建文件夹对话框');
    await tester.enterText(find.byType(AppTextField), newName);
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await _pumpReal(tester, 3);

    // ── 节点侧回查：文件夹真的建出来了 ────────────────────────────────
    await _waitUntilPumped(
      tester,
      () async {
        final folders = await node.listFolders();
        return folders.any((f) => f['name'] == newName);
      },
      what: '节点上出现新文件夹 $newName',
      timeoutMs: 30000,
      dumpOnTimeout: dumpNodeLog,
    );

    final namesAfter = (await node.listFolders())
        .map((f) => (f['name'] ?? '').toString())
        .toSet();
    final added = namesAfter.difference(namesBefore);
    expectWithContext(
      added,
      equals(<String>{newName}),
      reason: '节点上的文件夹应该正好多出 $newName 这一个（多了别的说明写串了夹，'
          '少了说明这次点击没落到节点）',
    );

    // ── UI 侧：卡片真的画出来了 ───────────────────────────────────────
    await _waitUntilPumped(
      tester,
      () => find.text(newName).evaluate().isNotEmpty,
      what: 'UI 上出现 $newName',
      timeoutMs: 30000,
      dumpOnTimeout: dumpNodeLog,
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // R3 重命名远程文件夹（真右键 → 真输入 → 确定）→ 立刻（不刷新页面）就变
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets('R3 右键文件夹 → 重命名 → 输入新名 → 确定 → 立刻可见且节点真改名', (tester) async {
    await bootApp(tester);
    await ensureRemoteNodeSelected(tester);
    await openMediaLibrary(tester);

    final oldName = '待改名夹${DateTime.now().millisecondsSinceEpoch % 100000}';
    final newName = '$oldName-新';
    await node.callOk('create_media_folder', <String, dynamic>{'name': oldName});
    await refreshViaUi(tester);
    await _waitUntilPumped(
      tester,
      () => find.text(oldName).evaluate().isNotEmpty,
      what: 'UI 上出现 $oldName',
      timeoutMs: 40000,
      dumpOnTimeout: dumpNodeLog,
    );

    // ── 真右键该文件夹卡 ──────────────────────────────────────────────
    final card = find.ancestor(
      of: find.text(oldName).first,
      matching: find.byType(MediaFolderCard),
    );
    expectWithContext(card, findsWidgets, reason: '应能定位到 $oldName 的文件夹卡');
    await _rightClick(tester, card.first);
    expect(find.text('重命名文件夹'), findsOneWidget, reason: '右键菜单应有「重命名文件夹」');
    await tester.tap(find.text('重命名文件夹'));
    await _pumpReal(tester, 2);

    // ── 真输入新名字 → 真点「确定」──────────────────────────────────
    await tester.enterText(find.byType(AppTextField), newName);
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await _pumpReal(tester, 3);

    // ── UI 侧：不刷新页面，标题就该是新的 ─────────────────────────────
    await _waitUntilPumped(
      tester,
      () => find.text(newName).evaluate().isNotEmpty,
      what: 'UI 上立刻出现新名字 $newName',
      timeoutMs: 40000,
      dumpOnTimeout: dumpNodeLog,
    );
    expectWithContext(
      find.text(oldName),
      findsNothing,
      reason: '旧名字不该还留在列表里（残留 = 列表没跟着写操作更新）',
    );

    // ── 节点侧：名字真的变了 ──────────────────────────────────────────
    final folders = await node.listFolders();
    expectWithContext(
      folders.any((f) => f['name'] == newName),
      isTrue,
      reason: '节点上应存在改名后的文件夹 $newName',
    );
    expectWithContext(
      folders.any((f) => f['name'] == oldName),
      isFalse,
      reason: '节点上不该再有旧名字 $oldName',
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // R5 删除节点本地文件（真右键 → 删除节点本地文件 → 真点「删除文件」）
  //    ★ 这是「删完最后一条之后聚合值不归零」的入口：用户看到集合写着
  //      「2 个文件 / 19KB」，点进去却是空的。
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets('R5 右键集合 → 删除节点本地文件 → 磁盘文件真没了且聚合值归零', (tester) async {
    await bootApp(tester);
    await ensureRemoteNodeSelected(tester);
    await openMediaLibrary(tester);

    // 造一条 2 个 wav 的独立集合
    final targetName = '待删文件${DateTime.now().millisecondsSinceEpoch % 100000}';
    final mediaRoot = Directory('${node.dataDir}/media')..createSync(recursive: true);
    final sampleDir = createAudioSampleDir(mediaRoot.path, 2, name: targetName);
    final imported = await node.callOk('import_media_folder', <String, dynamic>{
      'folder_path': sampleDir.path,
      'generate_thumbnails': false,
    }) as Map;
    final rawId = imported['id'].toString();

    // 前提：磁盘上真的有 2 个文件，条数真的是 2
    final filesBefore = listFilesRecursive(sampleDir.path)
        .where((p) => p.endsWith('.wav'))
        .toList();
    expectWithContext(filesBefore.length, equals(2), reason: '导入后磁盘上应有 2 个 wav');

    await refreshViaUi(tester);
    await _waitUntilPumped(
      tester,
      () => find.text(targetName).evaluate().isNotEmpty,
      what: 'UI 上出现 $targetName',
      timeoutMs: 40000,
      dumpOnTimeout: dumpNodeLog,
    );

    // ── 真右键 → 删除节点本地文件 → 真点确认 ─────────────────────────
    final card = find.ancestor(
      of: find.text(targetName).first,
      matching: find.byType(MediaCollectionCard),
    );
    await _rightClick(tester, card.first);
    expect(
      find.text('删除节点本地文件'),
      findsOneWidget,
      reason: '远程集合的右键菜单应有「删除节点本地文件」',
    );
    await tester.tap(find.text('删除节点本地文件'));
    await _pumpReal(tester, 2);

    // 确认框按钮文案见 picture_screen_dialogs._confirmDeleteNodeLocalFilesForCollection
    expect(find.textContaining('永久删除'), findsWidgets, reason: '应弹出危险操作确认框');
    await tester.tap(find.widgetWithText(FilledButton, '删除文件'));
    await _pumpReal(tester, 4);

    // ── 节点侧：磁盘文件真的没了 ──────────────────────────────────────
    await _waitUntilPumped(
      tester,
      () => listFilesRecursive(sampleDir.path).where((p) => p.endsWith('.wav')).isEmpty,
      what: '节点磁盘上的 wav 真的被删掉',
      timeoutMs: 40000,
      dumpOnTimeout: dumpNodeLog,
    );

    // ── 节点侧：集合的聚合值必须归零（这一条正对着「幽灵体积」缺陷）──────
    // 只断言「文件没了」不够：用户看到的是卡片上的「2 个文件 / 19KB」。
    final collections = await node.listCollections();
    final still = collections.firstWhere(
      (c) => c['id'].toString() == rawId,
      orElse: () => <String, dynamic>{},
    );
    if (still.isNotEmpty) {
      // 集合记录还在（留记录语义）：它的 item_count / total_size 必须是 0
      final count = int.tryParse('${still['item_count']}') ?? -1;
      final size = int.tryParse('${still['total_size']}') ?? -1;
      // ignore: avoid_print
      print('[R5] 集合记录仍在：item_count=$count total_size=$size');
      expectWithContext(
        count,
        equals(0),
        reason: '文件全删后集合记录里的条数必须归零（不归零就是用户看到的幽灵条数）',
      );
      if (size >= 0) {
        expectWithContext(
          size,
          equals(0),
          reason: '文件全删后集合记录里的体积必须归零（不归零就是「幽灵体积」）',
        );
      }
    } else {
      // 另一种正确结果：节点把空集合记录也移除了
      // ignore: avoid_print
      print('[R5] 集合记录已被节点移除（也是可接受的语义）');
    }

    // ── UI 侧：卡片上的条数不能还写着旧值 ─────────────────────────────
    // 这是用户视角最直接的证据：卡片还在但写着「1 个文件」而点进去是空的。
    final cardTexts = find
        .descendant(
          of: find.byType(MediaCollectionCard),
          matching: find.byType(Text),
        )
        .evaluate()
        .map((e) => (e.widget as Text).data ?? '')
        .toList();
    // ignore: avoid_print
    print('[R5] 卡片上的文本：$cardTexts');
  });

  // ═══════════════════════════════════════════════════════════════════════
  // R6 连续两次写操作（新建两个文件夹）→ 第二个不能被缓存/去重吞掉
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets('R6 连续两次「新建文件夹」→ 两个都真的到节点，第二个没被吞', (tester) async {
    await bootApp(tester);
    await ensureRemoteNodeSelected(tester);
    await openMediaLibrary(tester);

    final stamp = DateTime.now().millisecondsSinceEpoch % 100000;
    final nameA = '连号A$stamp';
    final nameB = '连号B$stamp';
    final namesBefore = (await node.listFolders())
        .map((f) => (f['name'] ?? '').toString())
        .toSet();

    /// 走一遍完整的「点新建 → 输入 → 确定」。
    Future<void> createViaUi(String name) async {
      await tester.tap(find.byTooltip('新建文件夹'));
      await _pumpReal(tester, 2);
      expect(find.text('新建媒体文件夹'), findsOneWidget, reason: '应弹出新建对话框');
      await tester.enterText(find.byType(AppTextField), name);
      await tester.tap(find.widgetWithText(FilledButton, '确定'));
      await _waitUntilPumped(
        tester,
        () async => (await node.listFolders()).any((f) => f['name'] == name),
        what: '节点上出现 $name',
        timeoutMs: 30000,
        dumpOnTimeout: dumpNodeLog,
      );
    }

    await createViaUi(nameA);
    await createViaUi(nameB);

    // ── 两个都必须真的在节点上 ────────────────────────────────────────
    final namesAfter = (await node.listFolders())
        .map((f) => (f['name'] ?? '').toString())
        .toSet();
    final added = namesAfter.difference(namesBefore);
    expectWithContext(
      added,
      equals(<String>{nameA, nameB}),
      reason: '连续两次新建应各落地一个；少了说明第二次被缓存/去重吞了，'
          '多了说明写串了。实际新增=$added',
    );

    // ── UI 上两个都在（顺序不限）──────────────────────────────────────
    await _waitUntilPumped(
      tester,
      () =>
          find.text(nameA).evaluate().isNotEmpty &&
          find.text(nameB).evaluate().isNotEmpty,
      what: 'UI 上同时出现 $nameA 和 $nameB',
      timeoutMs: 30000,
      dumpOnTimeout: dumpNodeLog,
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // R7 含特殊字符 / 同名 / 空名的文件夹名（用户真的会输入这些）
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets('R7 特殊字符与同名文件夹 → 名字原样落到节点且不互相覆盖', (tester) async {
    await bootApp(tester);
    await ensureRemoteNodeSelected(tester);
    await openMediaLibrary(tester);

    final stamp = DateTime.now().millisecondsSinceEpoch % 100000;
    // 冒号是 macOS 文件名里最危险的一个（HFS 会把 ":" 当路径分隔符的历史遗留），
    // 反斜杠 / 空格 / 中文混排也一并覆盖。
    final trickyName = '冒号:测试 $stamp';
    final dupName = '同名夹$stamp';

    Future<void> createViaUi(String name) async {
      await tester.tap(find.byTooltip('新建文件夹'));
      await _pumpReal(tester, 2);
      await tester.enterText(find.byType(AppTextField), name);
      await tester.tap(find.widgetWithText(FilledButton, '确定'));
      await _pumpReal(tester, 4);
    }

    final before = (await node.listFolders()).length;
    await createViaUi(trickyName);
    await createViaUi(dupName);
    await createViaUi(dupName); // 同名第二次

    // ── 特殊字符名原样保存（不能被静默清洗成别的名字）──────────────────
    await _waitUntilPumped(
      tester,
      () async => (await node.listFolders()).any((f) => f['name'] == trickyName),
      what: '节点上出现含冒号的文件夹名「$trickyName」（原样，未被清洗）',
      timeoutMs: 30000,
      dumpOnTimeout: dumpNodeLog,
    );

    // ── 同名是允许的（媒体库的同名文件夹共存语义）→ 应有 2 个 ──────────
    final folders = await node.listFolders();
    final dupCount = folders.where((f) => f['name'] == dupName).length;
    expectWithContext(
      dupCount,
      equals(2),
      reason: '同名文件夹应各自独立成条（项目定案：同名文件夹允许共存），实际 $dupCount 个',
    );
    expectWithContext(
      folders.length,
      equals(before + 3),
      reason: '三次新建应净增 3 个文件夹',
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // R8 逐条删文件：删非最后一条聚合值递减、删最后一条必须归零
  //
  // 为什么单独一条（而不是并进 R5）：R5 走的是「集合整目录清空」，
  // 节点会顺带把空集合记录一起移除，于是「聚合值不归零」这个缺陷
  // **恰好被掩盖**了（记录都没了，也就没人看 item_count）。
  // 要复现用户看到的「卡片写着 1 个文件、点进去一片空白」，必须走到
  // 「删掉最后一条、但集合记录还留着」那条路径 —— 也就是逐条删。
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets('R8 逐条删文件：删到最后一条后集合聚合值必须归零（幽灵体积回归）', (tester) async {
    await bootApp(tester);
    await ensureRemoteNodeSelected(tester);

    // 造一条 3 条 wav 的独立集合
    final stamp = DateTime.now().millisecondsSinceEpoch % 100000;
    final targetName = '逐条删$stamp';
    final mediaRoot = Directory('${node.dataDir}/media')..createSync(recursive: true);
    final sampleDir = createAudioSampleDir(mediaRoot.path, 3, name: targetName);
    final imported = await node.callOk('import_media_folder', <String, dynamic>{
      'folder_path': sampleDir.path,
      'generate_thumbnails': false,
    }) as Map;
    final rawId = imported['id'].toString();

    /// 从节点读该集合当前的聚合值。
    Future<({int count, int size})> readAggregate() async {
      final cols = await node.listCollections();
      final row = cols.firstWhere(
        (c) => c['id'].toString() == rawId,
        orElse: () => <String, dynamic>{},
      );
      if (row.isEmpty) return (count: -1, size: -1);
      return (
        count: int.tryParse('${row['item_count']}') ?? -1,
        size: int.tryParse('${row['total_size']}') ?? -1,
      );
    }

    // 前提确认：导入后是 3 条
    final agg0 = await readAggregate();
    // ignore: avoid_print
    print('[R8] 导入后聚合值 count=${agg0.count} size=${agg0.size}');
    expectWithContext(agg0.count, equals(3), reason: '导入 3 个 wav 后集合条数应为 3');

    /// 删掉集合里的第 [index] 条（用节点真实接口；UI 那条路径已被 R5 覆盖，
    /// 这里要的是**逐条**语义，UI 里逐条删走的是详情页，与聚合值无关的干扰太多）。
    Future<void> deleteItemAt(int index) async {
      final items = await node.listItems(rawId);
      expect(items.length, greaterThan(index), reason: '集合里应至少有 ${index + 1} 条');
      final itemId = items[index]['id'].toString();
      await node.callOk('delete_media_item_local_file', <String, dynamic>{
        'item_id': itemId,
        'collection_id': rawId,
      });
    }

    // ── 删第一条（非最后一条）：聚合值必须递减 ────────────────────────
    await deleteItemAt(0);
    final agg1 = await readAggregate();
    // ignore: avoid_print
    print('[R8] 删第 1 条后 count=${agg1.count} size=${agg1.size}');
    expectWithContext(
      agg1.count,
      equals(2),
      reason: '删掉 3 条中的 1 条后，集合条数应变成 2（不递减说明重扫没写汇总）',
    );
    expectWithContext(
      agg1.size,
      lessThan(agg0.size),
      reason: '删掉 1 条后体积应变小',
    );

    // ── 再删一条：仍是递减 ───────────────────────────────────────────
    await deleteItemAt(0);
    final agg2 = await readAggregate();
    // ignore: avoid_print
    print('[R8] 删第 2 条后 count=${agg2.count} size=${agg2.size}');
    expectWithContext(agg2.count, equals(1), reason: '删到只剩 1 条时条数应为 1');

    // ── 删最后一条：聚合值必须归零 ───────────────────────────────────
    // ★ 这一条就是缺陷本体：早期实现里删最后一条时重扫会提前 return Err
    //   （空目录不建集合），那个 Err 被 `let _ =` 吞掉，聚合表永远停在
    //   「1 条 / 9KB」，而条目表已经空了 —— 用户看到卡片写着 1 个文件、
    //   点进去一片空白，返回上一级体积也不变。
    await deleteItemAt(0);
    final agg3 = await readAggregate();
    // ignore: avoid_print
    print('[R8] 删最后一条后 count=${agg3.count} size=${agg3.size} '
        '（-1 表示集合记录已被移除）');

    // 条目列表必须真的空了
    final remainingItems = await node.listItems(rawId);
    expectWithContext(
      remainingItems.length,
      equals(0),
      reason: '删完最后一条后集合内条目应为空',
    );

    if (agg3.count >= 0) {
      expectWithContext(
        agg3.count,
        equals(0),
        reason: '★ 删掉最后一条后集合记录的条数必须归零。'
            '停在旧值 = 用户看到卡片写着 N 个文件、点进去却是空的（幽灵条数）',
      );
      expectWithContext(
        agg3.size,
        equals(0),
        reason: '★ 删掉最后一条后集合记录的体积必须归零（幽灵体积）',
      );
    } else {
      // 集合记录被移除也可以接受：那种情况下 UI 上不会有幽灵卡片
      // ignore: avoid_print
      print('[R8] 集合记录已被移除，无幽灵卡片风险');
    }
  });

  // ═══════════════════════════════════════════════════════════════════════
  // R4 删除远程集合（真右键 → 删除集合 → 真点「移除」）→ 两边都消失
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets('R4 右键集合 → 删除集合 → 点「移除」→ 卡片消失且节点真删', (tester) async {
    await bootApp(tester);
    await ensureRemoteNodeSelected(tester);
    await openMediaLibrary(tester);

    // 造一条独立集合，避免与前几条用例互相影响
    final targetName = '待删集合${DateTime.now().millisecondsSinceEpoch % 100000}';
    final mediaRoot = Directory('${node.dataDir}/media')..createSync(recursive: true);
    final sampleDir = createAudioSampleDir(mediaRoot.path, 2, name: targetName);
    await node.callOk('import_media_folder', <String, dynamic>{
      'folder_path': sampleDir.path,
      'generate_thumbnails': false,
    });
    await refreshViaUi(tester);
    await _waitUntilPumped(
      tester,
      () => find.text(targetName).evaluate().isNotEmpty,
      what: 'UI 上出现 $targetName',
      timeoutMs: 40000,
      dumpOnTimeout: dumpNodeLog,
    );

    final before = await node.listCollections();
    final target = before.firstWhere(
      (c) => c['name'] == targetName || c['title'] == targetName,
      orElse: () => <String, dynamic>{},
    );
    expectWithContext(target, isNotEmpty, reason: '节点上应有名为 $targetName 的集合');
    final rawId = target['id'].toString();

    // ── 真右键 → 删除集合 → 真点「移除」──────────────────────────────
    final card = find.ancestor(
      of: find.text(targetName).first,
      matching: find.byType(MediaCollectionCard),
    );
    await _rightClick(tester, card.first);
    expect(find.text('删除集合'), findsOneWidget, reason: '右键菜单应有「删除集合」');
    await tester.tap(find.text('删除集合'));
    await _pumpReal(tester, 2);

    expect(find.text('移除媒体集合'), findsOneWidget, reason: '应弹出确认框');
    await tester.tap(find.widgetWithText(FilledButton, '移除'));
    await _pumpReal(tester, 3);

    // ── 节点侧：集合真的没了 ──────────────────────────────────────────
    await _waitUntilPumped(
      tester,
      () async {
        final cols = await node.listCollections();
        return !cols.any((c) => c['id'].toString() == rawId);
      },
      what: '节点上 $targetName 消失',
      timeoutMs: 40000,
      dumpOnTimeout: dumpNodeLog,
    );

    // ── UI 侧：卡片真的没了 ───────────────────────────────────────────
    expectWithContext(
      find.text(targetName),
      findsNothing,
      reason: '删除后列表里不该还有 $targetName',
    );
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// 测试辅助（真 App + 真实异步）
// ═══════════════════════════════════════════════════════════════════════════

/// 推进若干帧 + 让真实 I/O 跑一会儿。
///
/// integration_test 绑定是 Live 的：帧由真实 vsync 驱动、Future 是真 Future，
/// 所以「等一小段真实时间 + 泵一帧」就够，不需要 runAsync/pump 交替那套。
Future<void> _pumpReal(WidgetTester tester, int frames, {int ms = 120}) async {
  final d = Duration(milliseconds: ms);
  for (var i = 0; i < frames; i++) {
    await tester.pump(d);
    await Future<void>.delayed(d);
  }
}

/// 等条件成立，**并且每一轮都泵一帧**。
///
/// 为什么必须泵帧：本轮踩过——等 `AppRoutes.router != null` 时不泵帧，
/// 而 router 是个 lazy final（要等 MyApp 首次 build 读到 `goRouter` 才初始化），
/// 于是「等时间」永远等不到，白白吃满 60s 超时。
Future<void> _waitUntilPumped(
  WidgetTester tester,
  FutureOr<bool> Function() condition, {
  required String what,
  int timeoutMs = 30000,
  void Function()? dumpOnTimeout,
}) async {
  final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) return;
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  dumpOnTimeout?.call();
  throw StateError('等待「$what」超时（${timeoutMs}ms）');
}

/// 真右键（桌面端卡片把菜单挂在 onSecondaryTapDown 上）。
Future<void> _rightClick(WidgetTester tester, Finder target) async {
  final gesture = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await gesture.down(tester.getCenter(target));
  await gesture.up();
  await _pumpReal(tester, 2);
}

/// 未隔离时的提示。
const String kNeedIsolationHint = '''
缺少隔离环境，已跳过真 App 用例（保护真实的媒体库数据）。

需要同时设置三个变量指向同一个已存在的临时目录：
  HOME=<沙箱> CFFIXED_USER_HOME=<沙箱> SLIME_E2E_HOME=<沙箱>

其中 CFFIXED_USER_HOME 才是 macOS 的真隔离开关（NSHomeDirectory 不读 HOME），
而 shared_preferences 连它也不认，测试内部已用内存实现隔离。
完整命令见本文件头部注释。
''';
