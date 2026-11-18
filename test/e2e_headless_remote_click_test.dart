// 无头节点「假成功」端到端测试 —— B 线：真 Flutter 树 + 真点击 + 真无头节点。
//
// ═══════════════════════════════════════════════════════════════════════════
// 这个文件在证明什么
// ═══════════════════════════════════════════════════════════════════════════
// A 线（e2e_headless_node_contract_test.dart）证明了「节点的 HTTP 语义是对的」。
// 但那还不够：用户报的是「客户端提示成功、数据却没变」，中间隔着一整层
// ViewModel 与 UI。所以这里：
//
//   · 真起一个 slime_node 子进程（不是 FakeNodeServer）
//   · 真初始化 Rust（真实 x86_64 dylib，真 FFI）
//   · 真 new 出 NodeSettingsService / MediaLibraryViewModel
//   · 真 pump 出 CollectionPictureScreen（真实页面，不吃任何测试假件）
//   · **真的 tap / 右键 / 点弹窗按钮 / enterText**，不绕过 VM 直接调方法
//   · 每一步之后既看 UI（卡片消失/改名），也回查节点 HTTP（数据真的变了）
//
// 「点击和弹窗确认必须是真 tap」是这次的核心要求：绕过 VM 直接调
// deleteCollection() 又变成「只走 API」了，测不出「按钮连错、弹窗没弹、
// 提示文案骗人」这类问题。
//
// ═══════════════════════════════════════════════════════════════════════════
// 跑法（HOME 隔离是硬要求，不隔离会写坏你真实那 217MB 的 media.db）
// ═══════════════════════════════════════════════════════════════════════════
//   mkdir -p /tmp/sw_e2e_home
//   HOME=/tmp/sw_e2e_home SLIME_E2E_HOME=/tmp/sw_e2e_home \
//     /private/tmp/fl/flutter/bin/flutter test test/e2e_headless_remote_click_test.dart --no-pub
//
// 必须用 /private/tmp/fl/flutter（3.50.0，引擎产物是 x86_64）；
// PATH 上的 /opt/homebrew/bin/flutter 是 3.47.2，加载不了这份 x86_64 dylib。
//
// ★ 本文件最重要的一条工程约束（踩了一整轮才定位）：
//   `testWidgets` 默认把测试体跑在 **fake-async 区**里，那里的时钟是模拟的，
//   真实的 socket / FFI 完成回调永远不会被推进 —— 直接 await 真实网络会无限挂起，
//   表现为「3 分钟超时、没有任何输出」。
//   所以凡是「真 I/O」（起节点、HTTP 调用、FFI）都必须放进 `tester.runAsync(...)`；
//   而 UI 推进则用 `tester.pump`。两者交替，见 [pumpRealIo]。
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:slime_works/core/provider/screen_provider_impl.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/services/media_prefs_service.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/widgets/app_text_field.dart';
import 'package:slime_works/pages/collection/picture/collection_picture_screen.dart';
import 'package:slime_works/pages/collection/picture/components/media_collection_card.dart';
import 'package:slime_works/pages/collection/picture/components/media_folder_card.dart';
import 'package:slime_works/src/rust/frb_generated.dart';
import 'package:slime_works/view_models/media_library_viewmodel.dart';

import 'helpers/e2e_headless_node.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 安全闸门：与 A 线同一套判据，未隔离 HOME 就整组跳过。
  final isolatedHome = e2eIsolatedHome;
  if (isolatedHome == null) {
    test('真点击端到端用例已跳过（未隔离 HOME）', () {
      // ignore: avoid_print
      print(kNeedIsolatedHomeHint);
    }, skip: kNeedIsolatedHomeHint);
    return;
  }

  /// Rust 只初始化一次（重复 init 会抛 already initialized）。
  var rustReady = false;

  Future<void> ensureRust() async {
    if (rustReady) return;
    await RustLib.init(
      // ★ 必须显式给这一条 x86_64 路径：这批 SDK 的引擎产物只有 x86_64，
      //   默认的 RustLib.init() 会去 target/release 捞 arm64 库，必失败。
      externalLibrary: ExternalLibrary.open(rustDylibPath),
    );
    rustReady = true;
  }

  RealHeadlessNode? activeNode;
  MediaLibraryViewModel? activeViewModel;

  /// 交替「让真 I/O 跑一会儿」与「让 UI 推进一帧」。
  ///
  /// 一个 `runAsync` 只推进真实事件循环（socket 回调、FFI 完成），
  /// 期间 UI 是停着的；反过来 `pump` 只画帧不推进真实 I/O。
  /// 页面首帧之后要经历「onInitAsync → refreshAll → 后台远程刷新 → HTTP 回调
  /// → Rx 写入 → 重建」这一长串，两者必须交替，单靠任一方都到不了稳定态。
  Future<void> pumpRealIo(
    WidgetTester tester, {
    int rounds = 16,
    int ioMs = 120,
    int frameMs = 40,
  }) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(Duration(milliseconds: ioMs)),
      );
      await tester.pump(Duration(milliseconds: frameMs));
    }
  }

  /// 等到 [condition] 成立（真 I/O 在推进、帧也在刷），超时则抛并附诊断。
  ///
  /// 不用固定帧数：节点取数是真实的环回 HTTP，耗时随机器负载浮动，
  /// 写死轮数在某些机器上刚好差一口气。等条件比等时间稳。
  Future<void> waitFor(
    WidgetTester tester,
    bool Function() condition, {
    String what = '条件',
    int timeoutMs = 20000,
    String Function()? diagnose,
  }) async {
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
    while (DateTime.now().isBefore(deadline)) {
      if (condition()) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
    final extra = diagnose == null ? '' : '\n诊断：${diagnose()}';
    throw StateError('等待「$what」超时（${timeoutMs}ms）$extra');
  }

  /// 收尾：**先卸载页面，再删 VM，最后 reset 服务**。
  ///
  /// 顺序是硬要求，反了会踩两个坑：
  ///  ① ScreenChrome.dispose 里要 getIt<DesktopScreenProvider>()，
  ///     服务先 reset 就在收尾阶段抛「未注册」；
  ///  ② MediaLibraryViewModel 那堆 Timer（远程缩略图轮询 15s 等）只能靠
  ///     onClose 收，而 onClose 由 Get.delete 触发；手动再调一次会
  ///     二次 dispose 同一个 ValueNotifier 而崩。
  Future<void> shutdown(WidgetTester tester) async {
    // ① 先卸载页面：ScreenChrome.dispose 会取 getIt<DesktopScreenProvider>()，
    //    必须在服务还在的时候执行。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    // ② 关节点：让所有在途的真实请求立刻失败返回。
    //    关掉之后 pollRemoteThumbProgress 的下一轮不会再有真实数据，
    //    它会在 finally 前把结果定为 total=0 并续挂一个 15s 轮询 —— 
    //    那个「最后一次」续挂必须发生在 ③ 之前，才能被 onClose 收掉。
    await tester.runAsync(() async {
      await activeNode?.dispose();
    });
    activeNode = null;

    // ③ 用真实 I/O 充分 drain：等所有在途请求的 catch 分支跑完、
    //    最后一轮轮询把 15s 表挂上。这段必须是真的等待（runAsync），
    //    fake-async 区里 Dio 的完成回调永远不会被推进。
    for (var round = 0; round < 8; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }

    // ④ 最后才删 VM：onClose 一次性 cancel 掉此刻挂着的轮询/防抖 Timer。
    //    这是唯一可靠的收尾顺序 —— 早删 VM 的话，drain 期间新挂的表就没人收了。
    if (Get.isRegistered<MediaLibraryViewModel>()) {
      Get.delete<MediaLibraryViewModel>(force: true);
    }
    await tester.pump();

    // ⑤ 清服务。
    await getIt.reset();
    activeViewModel = null;
  }

  /// 起节点 + 建服务 + 切远程模式 + 导入样本 + pump 真实页面。
  ///
  /// [sampleCount] 要导入的 wav 数量；[folderName] 决定集合标题。
  Future<void> bootScene(
    WidgetTester tester, {
    int sampleCount = 2,
    String folderName = '远程集合',
  }) async {
    // ── 环境 ────────────────────────────────────────────────────────────
    // flutter_test 默认装了拦截所有 HttpClient 的 mock（一切请求回 400），
    // 摘掉它，Dio 才能真的打到环回端口上的节点。
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.runAsync(() async {
      await ensureRust();

      // ── 真节点 + 真数据 ───────────────────────────────────────────────
      final node = await RealHeadlessNode.start(sandboxRoot: Directory(isolatedHome));
      activeNode = node;
      final mediaRoot = Directory('${node.dataDir}/media')..createSync(recursive: true);
      final sampleDir = createAudioSampleDir(mediaRoot.path, sampleCount, name: folderName);
      await node.callOk('import_media_folder', <String, dynamic>{
        'folder_path': sampleDir.path,
        // 关掉缩略图生成：会起后台任务空转、拖慢用例，且与本次断言无关
        'generate_thumbnails': false,
      });

      // ── 服务装配（真实实现，不吃桩）─────────────────────────────────
      await getIt.reset();
      // DesktopScreenProvider 的字段初始化就读 dotenv（APP_SIZE_WIDTH 等），
      // 没 loadFromString 的话第一次 getIt<DesktopScreenProvider>() 直接抛。
      dotenv.loadFromString(
        envString: 'APP_SIZE_WIDTH=1600\nAPP_SIZE_HEIGHT=1000\nAPP_NAME=E2E',
      );
      getIt.registerLazySingleton<DesktopScreenProvider>(
        () => DesktopScreenProviderImpl(),
      );
      final nodeService = NodeSettingsService();
      final prefs = MediaPrefsService();
      getIt
        ..registerSingleton<NodeSettingsService>(nodeService)
        ..registerSingleton<MediaPrefsService>(prefs);
      await nodeService.init();
      // 真 addRemoteNode：会顺手做一次真连通性探测 + 元数据预热
      await nodeService.addRemoteNode(name: 'E2E 真节点', apiBaseUrl: node.baseUrl);
      // 切到远程模式：页面此后只认节点上的数据（本地 FFI 那一路会被整段跳过）
      await nodeService.selectActiveNode(nodeService.remoteNodes.single.id);
    });

    // ── 真实页面 ────────────────────────────────────────────────────────
    // ★ AppTheme.lightTheme 必须在 ScreenUtilInit.builder 里取：
    //   ThemeMetrics 用 ScreenUtil 的静态系数算尺寸，而那些系数要等
    //   ScreenUtilInit 建好才存在。在 builder 外取会抛 LateInitializationError。
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(1600, 1000),
        builder: (context, _) {
          final theme = AppTheme.lightTheme;
          return MaterialApp(
            navigatorKey: navigatorKey,
            debugShowCheckedModeBanner: false,
            theme: theme,
            // 页面自己会 Get.put(permanent: true) 一份 MediaLibraryViewModel，
            // 所以下面 Get.find 拿到的就是页面真正在用的那一份。
            home: Material(
              color: theme.colorScheme.surface,
              child: const CollectionPictureScreen(),
            ),
          );
        },
      ),
    );
    activeViewModel = Get.find<MediaLibraryViewModel>();

    // 等真实网络把节点数据送进 VM **并且**网格真的画出了卡片。
    //
    // 两个条件都要等：VM 有数据 ≠ 画面已出（网格 build 里有入场动画+
    // 分批 reveal 的 Timer，从数据到像素还差几帧）。只等 VM 会出现
    // "数据在、卡片还没画"的中间态，后续 findByType 就落空。
    await waitFor(
      tester,
      () => activeViewModel!.remoteCollections.isNotEmpty &&
          find.byType(MediaCollectionCard).evaluate().isNotEmpty,
      what: 'VM 拿到节点集合且网格画出卡片',
      diagnose: () => 'VM.remoteCollections=${activeViewModel!.remoteCollections.length} '
          'isLoadingRemote=${activeViewModel!.isLoadingRemote.value} '
          '卡片数=${find.byType(MediaCollectionCard).evaluate().length} '
          'visibleItems=${activeViewModel!.visibleItems.length} '
          'nodeCallLog=${activeNode!.callLog.length}条',
    );

    // 收尾排在这个位置：能拿到 tester，顺序才排得对（见 shutdown 注释）
    addTearDown(() => shutdown(tester));
  }


  /// 只推进 UI 帧（不推进真实 I/O），用于等弹窗/菜单这类纯动画。
  Future<void> pumpFrames(WidgetTester tester, int frames, {int ms = 40}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(Duration(milliseconds: ms));
    }
  }

  /// 右键点某张卡片（桌面端卡片把菜单挂在 onSecondaryTapDown 上）。
  Future<void> rightClick(WidgetTester tester, Finder target) async {
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.down(tester.getCenter(target));
    await gesture.up();
    // ★ 不能用 pumpAndSettle：这个页面挂着常驻的入场动画与远程缩略图轮询
    //   Timer，pumpAndSettle 永远等不到「没有待处理帧」，会直接超时。
    //   固定推进若干帧足够让 showMenu 的 route 动画落地。
    await pumpFrames(tester, 8);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // B1 删除远程集合：右键 → 「删除集合」→ 弹窗「移除」→ 卡片消失 + 节点真删
  // ═══════════════════════════════════════════════════════════════════════
  group('B1 删除远程集合（真点击）', () {
    testWidgets('右键 → 删除集合 → 点「移除」→ 卡片消失且节点列表为空', (tester) async {
      await bootScene(tester, sampleCount: 2, folderName: '待删集合');
      final node = activeNode!;
      final viewModel = activeViewModel!;

      // ── 断言 0：页面上真的画出了集合卡 ───────────────────────────────
      // 这一步覆盖「远程元数据 → 合并列表 → 网格渲染」整条链路。
      expect(viewModel.remoteCollections, isNotEmpty, reason: '节点上的集合应已被拉进 VM');
      expect(
        find.byType(MediaCollectionCard),
        findsOneWidget,
        reason: '页面上必须真的渲染出集合卡片',
      );
      expect(find.text('待删集合'), findsWidgets);

      final collectionId = viewModel.remoteCollections.single.id;
      final rawId = collectionId.split(':').last;

      // ── 真右键 → 点菜单「删除集合」──────────────────────────────────
      await rightClick(tester, find.byType(MediaCollectionCard).first);
      expect(find.text('删除集合'), findsOneWidget, reason: '右键后菜单里必须有「删除集合」');
      await tester.tap(find.text('删除集合'));
      await pumpFrames(tester, 8);

      // ── 真点确认弹窗按钮 ────────────────────────────────────────────
      // 文案来自 picture_screen_dialogs.dart 的 _confirmDeleteSingle
      expect(find.text('移除媒体集合'), findsOneWidget, reason: '删除前必须弹确认框');
      await tester.tap(find.widgetWithText(FilledButton, '移除'));
      await tester.pump();
      await pumpRealIo(tester);

      // ── 断言一：UI 层面卡片真的没了 ─────────────────────────────────
      expect(
        viewModel.remoteCollections.any((c) => c.id == collectionId),
        isFalse,
        reason: 'VM 的远程集合列表里不该还有它',
      );
      expect(find.byType(MediaCollectionCard), findsNothing, reason: '页面上不能再画这张卡');

      // ── 断言二：节点侧数据真的变了（不是客户端自己骗自己）──────────
      final nodeCollections = await tester.runAsync(() => node.listCollections());
      expect(
        nodeCollections!.any((c) => c['id'] == rawId),
        isFalse,
        reason: '回查节点：集合必须真的从节点库里消失了',
      );
      expect(nodeCollections, isEmpty);
    });

    /// 这条用例盯的是「假成功」在 UI 上的样子：
    /// 节点若对不存在的集合回 ok:true，客户端会弹**成功**提示。
    testWidgets('对已消失的集合再删一次 → 用户看到失败提示，不是成功提示', (tester) async {
      await bootScene(tester, sampleCount: 1, folderName: '重复删除');
      final node = activeNode!;
      final viewModel = activeViewModel!;

      final collectionId = viewModel.remoteCollections.single.id;
      final rawId = collectionId.split(':').last;

      // 让节点先把它删掉（模拟「别的窗口已经删了、本页列表还是旧的」）
      await tester.runAsync(
        () => node.callOk('delete_media_collection', <String, dynamic>{
          'collection_id': rawId,
        }),
      );
      // 确认前提成立：节点上确实已经没有它了
      final afterExternalDelete =
          await tester.runAsync(() => node.listCollections());
      expect(afterExternalDelete!.any((c) => c['id'] == rawId), isFalse);
      // 而 VM 里还留着（陈旧列表），正是要测的场景
      expect(viewModel.remoteCollections.any((c) => c.id == collectionId), isTrue);

      // ── 走完整的真实手势链路再删一次 ────────────────────────────────
      await rightClick(tester, find.byType(MediaCollectionCard).first);
      await tester.tap(find.text('删除集合'));
      await pumpFrames(tester, 8);
      await tester.tap(find.widgetWithText(FilledButton, '移除'));
      await tester.pump();
      await pumpRealIo(tester);

      // ── 断言：用户看到的是失败提示 ──────────────────────────────────
      // showSnack 拼的是「标题：内容」，失败标题是「错误」。
      // 假成功时这里会是「成功：…」，所以这条断言正对着本次 bug。
      expect(
        find.textContaining('错误：'),
        findsWidgets,
        reason: '删已不存在的集合必须给用户失败提示（假成功会显示成成功）',
      );
      expect(
        find.textContaining('删除集合失败'),
        findsWidgets,
        reason: '提示里要带上是哪一步失败了',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // B2 重命名远程文件夹：右键 → 重命名 → 真输入 → 点「确定」→ 两边都改名
  // ═══════════════════════════════════════════════════════════════════════
  group('B2 重命名远程文件夹（真点击 + 真输入）', () {
    testWidgets('右键文件夹 → 重命名文件夹 → 输入新名 → 点「确定」→ UI 与节点都改名', (tester) async {
      await bootScene(tester, sampleCount: 1, folderName: '子集合');
      final node = activeNode!;
      final viewModel = activeViewModel!;

      // 在节点上建一个真文件夹，再让页面刷新出来
      final created = await tester.runAsync(
        () => node.callOk('create_media_folder', <String, dynamic>{'name': '旧夹名'}),
      ) as Map;
      final rawFolderId = created['id'].toString();
      await tester.runAsync(() => viewModel.refreshRemoteLibrary());
      await pumpRealIo(tester);

      // ── 断言 0：页面上真有这张文件夹卡 ──────────────────────────────
      expect(find.byType(MediaFolderCard), findsOneWidget, reason: '文件夹卡要能画出来');
      expect(find.text('旧夹名'), findsWidgets);

      // ── 真右键 → 点「重命名文件夹」──────────────────────────────────
      await rightClick(tester, find.byType(MediaFolderCard).first);
      expect(find.text('重命名文件夹'), findsOneWidget);
      await tester.tap(find.text('重命名文件夹'));
      await pumpFrames(tester, 10);

      // ── 真输入 ──────────────────────────────────────────────────────
      expect(find.text('输入新的文件夹名称'), findsOneWidget, reason: '重命名弹窗要真的弹出来');
      await tester.enterText(find.byType(AppTextField).last, '新夹名');
      await tester.pump();

      // ── 真点「确定」──────────────────────────────────────────────────
      await tester.tap(find.widgetWithText(FilledButton, '确定'));
      await tester.pump();
      await pumpRealIo(tester);

      // ── 断言一：UI 上标题真的变了 ───────────────────────────────────
      expect(find.text('新夹名'), findsWidgets, reason: '改名后页面上必须显示新名字');
      expect(find.text('旧夹名'), findsNothing, reason: '旧名字不能还留在页面上');

      // ── 断言二：节点侧真的改名了（回查 HTTP）───────────────────────
      final nodeFolders = await tester.runAsync(() => node.listFolders());
      final renamed = nodeFolders!.firstWhere(
        (f) => f['id'] == rawFolderId,
        orElse: () => <String, dynamic>{},
      );
      expect(renamed['name'], '新夹名', reason: '节点库里的文件夹名必须真的变了');
    });

    /// 对不存在的文件夹改名：UI 必须给出失败提示。
    /// 修复前节点回 ok:true，用户看到"重命名成功"但名字纹丝不动。
    testWidgets('对已消失的文件夹改名 → 用户看到失败提示', (tester) async {
      await bootScene(tester, sampleCount: 1, folderName: '徒劳改名');
      final node = activeNode!;
      final viewModel = activeViewModel!;

      final created = await tester.runAsync(
        () => node.callOk('create_media_folder', <String, dynamic>{'name': '将被偷走的夹'}),
      ) as Map;
      final rawFolderId = created['id'].toString();
      await tester.runAsync(() => viewModel.refreshRemoteLibrary());
      await pumpRealIo(tester);
      expect(find.text('将被偷走的夹'), findsWidgets);

      // 节点侧先删掉它（模拟并发删除），VM 里仍是陈旧数据
      await tester.runAsync(
        () => node.callOk('delete_media_folder', <String, dynamic>{
          'folder_id': rawFolderId,
        }),
      );

      // 走真实手势去改名
      await rightClick(tester, find.byType(MediaFolderCard).first);
      await tester.tap(find.text('重命名文件夹'));
      await pumpFrames(tester, 10);
      await tester.enterText(find.byType(AppTextField).last, '改不动的夹');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '确定'));
      await tester.pump();
      await pumpRealIo(tester);

      expect(
        find.textContaining('重命名文件夹失败'),
        findsWidgets,
        reason: '对不存在的文件夹改名必须提示失败（假成功会显示成成功）',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // B3 删除远程集合的节点本地文件：右键 → 弹窗「删除文件」→ 磁盘真清空
  // ═══════════════════════════════════════════════════════════════════════
  group('B3 删除远程集合的节点本地文件（真点击）', () {
    testWidgets('右键 → 删除节点本地文件 → 点「删除文件」→ 磁盘清空、集合记录仍在', (tester) async {
      await bootScene(tester, sampleCount: 3, folderName: '节点文件集合');
      final node = activeNode!;
      final viewModel = activeViewModel!;

      final rawCollectionId = viewModel.remoteCollections.single.id.split(':').last;
      // 记录删除前磁盘上真实存在的文件（后面「真没了」的对照基准）
      final itemsBefore = await tester.runAsync(() => node.listItems(rawCollectionId));
      expect(itemsBefore, hasLength(3), reason: '前提：节点上有 3 个条目');
      final diskPaths = itemsBefore!.map((i) => i['file_path'].toString()).toList();
      for (final path in diskPaths) {
        expect(File(path).existsSync(), isTrue, reason: '前提：文件此刻在节点磁盘上');
      }
      // 节点目录本身也要记下来：删空后连空目录都会被收掉
      final collectionDir = File(diskPaths.first).parent.path;

      // ── 真右键 → 点「删除节点本地文件」──────────────────────────────
      await rightClick(tester, find.byType(MediaCollectionCard).first);
      expect(find.text('删除节点本地文件'), findsOneWidget);
      await tester.tap(find.text('删除节点本地文件'));
      await pumpFrames(tester, 10);

      // ── 真点确认按钮：文案是「删除文件」（ConfirmDialog）────────────
      await tester.tap(find.widgetWithText(FilledButton, '删除文件'));
      await tester.pump();
      await pumpRealIo(tester);

      // ── 断言一：节点磁盘上的文件真的没了 ────────────────────────────
      for (final path in diskPaths) {
        expect(
          File(path).existsSync(),
          isFalse,
          reason: '用户点了「删除文件」，$path 必须真的从节点磁盘上消失',
        );
      }

      // ── 断言二：集合记录与卡片都消失了 ──────────────────────────────
      //
      // 这里刻意写清楚**两层语义**，避免下一个人照抄错断言：
      //  · 节点侧 delete_collection_local_files 只删文件、保留集合记录；
      //  · 客户端 deleteNodeLocalFilesForCollection 在确认「文件已删空」后
      //    **会主动把集合记录也删掉**（见 media_library_vm_collections.dart
      //    里 remaining==0 那一支），并提示「已删除全部文件，集合已从库中移除」。
      // 所以用户点完这一下，正确结果是：磁盘没了 + 集合记录没了 + 卡片没了。
      expect(
        Directory(collectionDir).existsSync(),
        isFalse,
        reason: '文件删完后空的集合目录也应被收掉',
      );

      final collections = await tester.runAsync(() => node.listCollections());
      expect(
        collections!.any((c) => c['id'] == rawCollectionId),
        isFalse,
        reason: '文件删空后客户端会移除集合记录，节点上不该还留着它',
      );

      // ── 断言三：UI 上也确实没有这张卡了 ────────────────────────────
      expect(
        viewModel.remoteCollections.any((c) => c.id.endsWith(rawCollectionId)),
        isFalse,
        reason: '集合没了，列表里不该还有它',
      );
      expect(find.byType(MediaCollectionCard), findsNothing);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // B4 UI 与节点数据一致
  // ═══════════════════════════════════════════════════════════════════════
  group('B4 UI 与节点数据一致', () {
    testWidgets('页面上每张远程集合卡都能在节点库里查到同 id 的记录', (tester) async {
      await bootScene(tester, sampleCount: 2, folderName: '一致性集合');
      final node = activeNode!;
      final viewModel = activeViewModel!;

      final nodeCollections = await tester.runAsync(() => node.listCollections());
      final nodeIds = nodeCollections!.map((c) => c['id'].toString()).toSet();

      expect(viewModel.remoteCollections, isNotEmpty);
      for (final collection in viewModel.remoteCollections) {
        final rawId = collection.id.split(':').last;
        expect(
          nodeIds,
          contains(rawId),
          reason: 'UI 上的集合 ${collection.title} 在节点库里查不到 —— 这就是"界面有、数据没"',
        );
      }
      // 反向也成立：节点上的集合都该出现在 UI 里（不能只显示一部分）
      expect(viewModel.remoteCollections, hasLength(nodeIds.length));
    });
  });
}
