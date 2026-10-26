// 电力统计页的离屏出图 + 逐帧排版冒烟。
//
// 这一页的动效全部挂在"数据到达"那一刻，所以出图分两刀：
// 一刀在静置（所有错开与滚动都跑完，画面必须静止），一刀在抓取事件
// 刚擦进来的中途（横幅只揭开左半截）。两张图不一样才证明动的是数据那一下，
// 而不是一直在跳。
//
// 动效本身另有硬判据：生长从第几根起、折线画到横轴的哪儿，都直接读 painter
// 的字段；浮层则用鼠标真的移过去验它报的是不是那一段的数。
//
// FFI 在测试进程里没有原生库，Service 每次刷新都会抛并被自己的 try/catch 吞掉，
// 页面于是停在空态——空态不是要验收的东西，所以数据由用例直接灌进
// ViewModel：绕开 Service，形状与 Rust 侧解析后完全一致。
@Tags(['golden'])
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:slime_works/components/window/collapsible_sidebar.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/services/power_stats_service.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/pages/power_stats/components/power_stats_chart.dart';
import 'package:slime_works/pages/power_stats/power_stats_screen.dart';
import 'package:slime_works/view_models/power_stats_viewmodel.dart';

import 'helpers/page_golden.dart';

// ── 窗口档位（真机按固定设计稿出图：桌面 1920x1080，手机 375x815）────────
const Size _desktopWindow = Size(1440, 900);
const Size _desktopDesign = Size(1920, 1080);
const Size _phoneWindow = Size(390, 844);
const Size _phoneDesign = Size(375, 815);

/// 高窗口：900 的视口只够看到柱状带，TOP5 / 维度网格 / 配置 / 日志全在折线以下
const Size _tallWindow = Size(1440, 2180);

/// 桩数据的日子：钉死在 2026-10-13（周二）当地零点
///
/// 浮层那句"几号 周几"是从 timestamp 现算的，用 now() 就等于每周换一个 golden。
final int _baseTs = DateTime(2026, 10, 13).millisecondsSinceEpoch ~/ 1000;

/// 灌进 ViewModel 的假数据
///
/// 24 个小时桶，凌晨六段表根本没走（读数是 0），用电集中在晚间，余额单调下降
/// ——折线、柱状带、TOP5 才有形状，也一眼能看出"峰值"标在了对的柱子上、
/// 那六段 0 有没有被过滤掉。数值全是编的。
List<PowerStatBucket> _fakeBuckets() {
  double balanceYuan = 86.40;
  double balanceKwh = 720.0;
  return [
    for (int h = 0; h < 24; h++)
      () {
        final kwh = h < 6
            ? 0.0
            : (h >= 18 && h <= 23
                  ? 1.8 + (h - 18) * 0.45
                  : (h >= 8 && h <= 17 ? 0.42 + (h % 4) * 0.13 : 0.16 + (h % 3) * 0.07));
        final cost = kwh * 0.5831;
        balanceYuan -= cost;
        balanceKwh -= kwh;
        return PowerStatBucket(
          label: '${h.toString().padLeft(2, '0')}:00',
          timestamp: _baseTs + h * 3600,
          consumptionKwh: kwh,
          costYuan: cost,
          balanceYuan: balanceYuan,
          balanceKwh: balanceKwh,
        );
      }(),
  ];
}

Map<String, dynamic> _fakeSummary() => {
  'current_yuan': 68.31,
  'current_kwh': 569.4,
  'minute_consumption': 0.0312,
  'hour_consumption': 1.86,
  'hour_cost': 1.0857,
  'day_consumption': 22.44,
  'day_cost': 13.08,
  'week_consumption': 151.3,
  'week_cost': 88.22,
  'fifteen_day_consumption': 322.7,
  'fifteen_day_cost': 188.16,
  'sixteen_day_consumption': 344.1,
  'thirty_day_consumption': 641.8,
  'thirty_day_cost': 374.22,
};

/// 挂载并等入场/滚动全部收敛，返回页面上那个 ViewModel
Future<PowerStatsViewModel> _mountSettled(
  WidgetTester tester, {
  required bool dark,
  required Size window,
  required Size design,
}) async {
  // 顶栏面包屑要读侧栏当前选中项：真机由 createRouter() 注册，这里补一颗钉
  Get.put(
    SidebarController()
      ..selectedRoute.value = const PowerStatsRoute().location,
  );

  await pumpAppPage(
    tester,
    const PowerStatsScreen(),
    dark: dark,
    size: window,
    designSize: design,
    withTopBar: true,
  );
  // 先让 Service 那一路空跑（ensureInitialized → refreshAll）落到终态再灌数据：
  // 反过来灌会被 refreshSummary 用空表盖回去
  await advance(tester, steps: 6);

  final vm = Get.find<PowerStatsViewModel>();
  vm.meterName.value = '家里电表';
  vm.price.value = 0.5831;
  vm.sampleCount.value = 1268;
  vm.currentKwh.value = 569.4;
  vm.currentYuan.value = 68.31;
  vm.summary.addAll(_fakeSummary());
  vm.buckets
    ..clear()
    ..addAll(_fakeBuckets());
  vm.logs
    ..clear()
    ..addAll([
      {
        'success': true,
        'timestamp': '2026-10-13 19:05:02',
        'message': '抓取成功，当前余额 68.44 元',
        'kwh': 68.44,
      },
      {
        'success': false,
        'timestamp': '2026-10-13 19:10:02',
        'message': '连接超时，本次未取到读数',
        'kwh': 0.0,
      },
      {
        'success': true,
        'timestamp': '2026-10-13 19:15:02',
        'message': '抓取成功，当前余额 68.31 元',
        'kwh': 68.31,
      },
    ]);
  // 错开入场最后一档 7×45ms + 460ms，滚动数字 720ms，柱状带逐根生长：
  // 小步推 1.8s 全部收敛，此刻画面应当完全静止
  await advance(tester, steps: 60, ms: 30);
  return vm;
}

void main() {
  setUpAll(() async {
    // 页面通过 GetIt 拿服务，注册表得先摆好；lazySingleton 不取不跑，碰不到 FFI
    if (!GetIt.instance.isRegistered<PowerStatsService>()) {
      GetIt.instance.registerLazySingleton<PowerStatsService>(
        () => PowerStatsService(),
      );
    }
    await loadAppFonts();
  });

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  tearDown(() {
    // 页面 dispose 里会 Get.delete 自己的 VM，侧栏那颗钉没人管，手动清掉，
    // 否则下一个用例拿到上一个页面的控制器
    Get.delete<SidebarController>(force: true);
  });

  testWidgets('电力统计页：浅色静置', (tester) async {
    await _mountSettled(
      tester,
      dark: false,
      window: _desktopWindow,
      design: _desktopDesign,
    );
    await expectLater(
      pageSurface(),
      matchesGoldenFile('goldens/power_stats_light.png'),
    );
    await unmountPage(tester);
  });

  testWidgets('电力统计页：深色静置', (tester) async {
    await _mountSettled(
      tester,
      dark: true,
      window: _desktopWindow,
      design: _desktopDesign,
    );
    await expectLater(
      pageSurface(),
      matchesGoldenFile('goldens/power_stats_dark.png'),
    );
    await unmountPage(tester);
  });

  testWidgets('电力统计页：手机窄屏静置', (tester) async {
    await _mountSettled(
      tester,
      dark: false,
      window: _phoneWindow,
      design: _phoneDesign,
    );
    await expectLater(
      pageSurface(),
      matchesGoldenFile('goldens/power_stats_mobile.png'),
    );
    await unmountPage(tester);
  });

  testWidgets('电力统计页：整页长图（折线以下的区块也要验）', (tester) async {
    await _mountSettled(
      tester,
      dark: false,
      window: _tallWindow,
      design: _desktopDesign,
    );
    // 出图之外再钉一层：这几块在 900 高的视口里根本没进过树，
    // 光看前几张图等于没测
    expect(find.text('峰值时段'), findsOneWidget);
    expect(find.text('抓取日志'), findsOneWidget);
    await expectLater(
      pageSurface(),
      matchesGoldenFile('goldens/power_stats_tall.png'),
    );
    await unmountPage(tester);
  });

  testWidgets('电力统计页：横幅只在数据到达那一下擦进来，自己收势', (tester) async {
    final vm = await _mountSettled(
      tester,
      dark: false,
      window: _desktopWindow,
      design: _desktopDesign,
    );

    // 静置态：一条读数都没到，页头不该有任何横幅
    expect(find.text('抓取成功'), findsNothing);

    // 推到"刚拿到一条新读数"：lastFetch 一变，页面就推一个抓取事件，
    // 横幅擦入 / 曲线末端涟漪 / 卡外发光同一下起钟
    vm.currentYuan.value = 68.02;
    vm.lastResult.value = '抓取成功，当前余额 68.02 元';
    vm.lastFetch.value = '2026-10-13 19:20:31';
    await tester.pump();
    // 擦入 160ms，这里停在 40ms：横幅正半遮半露（再晚就擦完了，出图看不出动过）
    await advance(tester, steps: 2, ms: 20);
    expect(find.text('抓取成功'), findsOneWidget);
    // 只比"擦入途中"和"驻留"两帧的图肉眼看不出差别，直接量裁切盒的宽度：
    // 途中这一帧必须明显比整宽窄，否则擦入根本没在动
    final wipe = find.byKey(const ValueKey('ps-banner-wipe'));
    expect(wipe, findsOneWidget);
    final midWidth = tester.getSize(wipe).width;
    expect(midWidth, lessThan(_desktopWindow.width - 100));
    await expectLater(
      pageSurface(),
      matchesGoldenFile('goldens/power_stats_event_mid.png'),
    );

    // 驻留峰值（160 擦入走完，还在 700 驻留里）：这一帧必须和途中那一帧不同
    await advance(tester, steps: 4, ms: 30);
    expect(find.text('抓取成功'), findsOneWidget);
    expect(tester.getSize(wipe).width, greaterThan(midWidth));
    await expectLater(
      pageSurface(),
      matchesGoldenFile('goldens/power_stats_event_hold.png'),
    );

    // 收势（160 擦入 + 700 驻留 + 300 收势 = 1160ms）之后必须彻底静止
    await advance(tester, steps: 40, ms: 30);
    expect(
      find.text('抓取成功'),
      findsNothing,
      reason: '横幅应当自己收势，不赖在卡头上',
    );
    expect(wipe, findsNothing);
    await expectLater(
      pageSurface(),
      matchesGoldenFile('goldens/power_stats_event_settled.png'),
    );
  });

  testWidgets('电力统计页：抓取失败也要有交代', (tester) async {
    final vm = await _mountSettled(
      tester,
      dark: false,
      window: _desktopWindow,
      design: _desktopDesign,
    );
    // 失败路径：Rust 侧不一定动 last_fetch，靠 last_result 的前缀认失败
    vm.lastResult.value = '抓取失败: 连接超时';
    vm.lastFetch.value = '2026-10-13 19:20:31';
    await tester.pump();
    await advance(tester, steps: 6, ms: 30);

    expect(find.text('抓取失败'), findsOneWidget);
    // 标题已经报了"抓取失败"，正文只留原因；再出现整串 last_result 就是重复一句话
    expect(find.text('连接超时'), findsOneWidget);
    expect(find.text('抓取失败: 连接超时'), findsNothing);
    await expectLater(
      pageSurface(),
      matchesGoldenFile('goldens/power_stats_event_failed.png'),
    );
    await unmountPage(tester);
  });

  testWidgets('柱状带：0 读数那段根本不画，末尾补一段只长新来的那根', (tester) async {
    final vm = await _mountSettled(
      tester,
      dark: false,
      window: _tallWindow,
      design: _desktopDesign,
    );
    // 24 段里凌晨那 6 段表根本没走：留在带上就是基线上一排扁胶囊
    expect(find.text('共 18 段'), findsOneWidget);
    // 入场那一轮从第 0 根开始，此刻已经长满
    expect(_painter(tester, '_TapePainter').from, 0);
    expect(_painter(tester, '_TapePainter').elapsed, greaterThan(1000));

    // 轮询补一段：前面 18 段的 label 一个字没变
    vm.buckets.add(
      PowerStatBucket(
        label: '次日的00:00',
        timestamp: _baseTs + 24 * 3600,
        consumptionKwh: 0.9,
        costYuan: 0.5248,
        balanceYuan: 67.79,
        balanceKwh: 568.5,
      ),
    );
    await tester.pump();
    await advance(tester, steps: 1, ms: 20);

    expect(find.text('共 19 段'), findsOneWidget);
    final tape = _painter(tester, '_TapePainter');
    // 生长起点就是新来那根：还是 0 的话等于整条带又抖了一遍
    expect(tape.from, 18);
    expect(tape.elapsed, lessThan(200));
    await expectLater(
      pageSurface(),
      matchesGoldenFile('goldens/power_stats_tape_tail.png'),
    );

    await advance(tester, steps: 20, ms: 30);
    expect(_painter(tester, '_TapePainter').elapsed, greaterThan(400));
    await unmountPage(tester);
  });

  testWidgets('换区间：折线、柱状带、迷你趋势一起整条重播', (tester) async {
    final vm = await _mountSettled(
      tester,
      dark: false,
      window: _tallWindow,
      design: _desktopDesign,
    );
    expect(_painter(tester, '_PsChartCanvas').reveal, 1.0);
    expect(_painter(tester, '_SparklinePainter').reveal, 1.0);

    // 只改档位，不碰 Service 那一路（测试进程里 FFI 直接空跑，换了区间数据会整份没了）
    vm.selectedRange.value = '7day';
    await tester.pump();
    await advance(tester, steps: 2, ms: 30);

    expect(
      _painter(tester, '_PsChartCanvas').reveal,
      lessThan(1.0),
      reason: '主曲线应当正在被重新画出来',
    );
    final tape = _painter(tester, '_TapePainter');
    expect(tape.from, 0, reason: '换区间换的是整套数据，生长要从第 0 根重来');
    expect(tape.elapsed, lessThan(460));
    expect(_painter(tester, '_SparklinePainter').reveal, lessThan(1.0));
    await expectLater(
      pageSurface(),
      matchesGoldenFile('goldens/power_stats_range_replay.png'),
    );

    await advance(tester, steps: 60, ms: 30);
    expect(_painter(tester, '_PsChartCanvas').reveal, 1.0);
    expect(_painter(tester, '_TapePainter').elapsed, greaterThan(1000));
    await unmountPage(tester);
  });

  testWidgets('维度统计：列数跟着宽度走，宽屏一排摆得下六档', (tester) async {
    // 出图看不到卡片内部对齐，但"到底几列"这件事本来就是个数，直接问 delegate
    Future<int> columnsAt(Size window, Size design) async {
      await _mountSettled(tester, dark: false, window: window, design: design);
      final delegate =
          tester
              .widget<GridView>(find.byType(GridView))
              .gridDelegate
          as SliverGridDelegateWithFixedCrossAxisCount;
      await unmountPage(tester);
      return delegate.crossAxisCount;
    }

    expect(await columnsAt(_desktopWindow, _desktopDesign), 6);
    expect(await columnsAt(_phoneWindow, _phoneDesign), 2);
  });

  testWidgets('悬停：柱状带与账户余额迷你趋势都要报出那一段的数', (tester) async {
    await _mountSettled(
      tester,
      dark: false,
      window: _tallWindow,
      design: _desktopDesign,
    );

    // 柱状带：鼠标落在正中那根柱子上，浮层要说出它的时段名，后面还跟着几号周几
    await _hover(tester, tester.getCenter(_canvasOf('_TapePainter')));
    expect(find.text('10-13 周二 15:00'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '浮层不该把画布那点高度当上限');
    await expectLater(
      pageSurface(),
      matchesGoldenFile('goldens/power_stats_hover_tape.png'),
    );

    // hero 的余额线：浮层除了数值还要给出环比
    // 先量尺寸——Stack 里的 CustomPaint 不写 size 会塌成 0×0，那时悬停永远只
    // 落在第一个点上，浮层看着"有"其实指着错的那一段
    expect(
      tester.getSize(_canvasOf('_SparklinePainter')).width,
      greaterThan(100),
    );
    await _hover(tester, tester.getCenter(_canvasOf('_SparklinePainter')));
    expect(find.textContaining('较上一点'), findsOneWidget);
    // hero 只有 84 高，比浮层三行字矮，是最容易被"顶到溢出"的那一处
    expect(find.textContaining(RegExp(r'^10-13 周二 \d\d:00$')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      pageSurface(),
      matchesGoldenFile('goldens/power_stats_hover_hero.png'),
    );

    // 主趋势图那侧原本就有浮层，这里一起验掉，免得改完只补了两处
    // 判据用"那句维度名多出一枚"：这张图的落点按 padLeft/padRight 反算索引，
    // 具体是哪一段取决于画布宽度，写死时段名就成了跟着几何走脆的断言
    await _hover(tester, tester.getCenter(_canvasOf('_PsChartCanvas')));
    expect(find.text('耗电量'), findsNWidgets(2));
    expect(find.textContaining(RegExp(r'^10-13 周二 \d\d:\d\d$')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      pageSurface(),
      matchesGoldenFile('goldens/power_stats_hover_chart.png'),
    );
    await unmountPage(tester);
  });

  testWidgets('字号调到最大档：浮层比画布高也不许溢出', (tester) async {
    // 字号走 scaleSWithUserFont（乘用户那档字阶），画布高度走 scaleW（不乘）。
    // 字阶一放大，三行浮层就比画布高，而浮层是被画布那档 maxHeight 顶着的，
    // 真机在放大字号下报的就是这一句 "A RenderFlex overflowed by 4.9 pixels"
    AppTheme.fontScaleObs.value = 1.6;
    addTearDown(() => AppTheme.fontScaleObs.value = 1.0);

    await _mountSettled(
      tester,
      dark: false,
      window: _tallWindow,
      design: _desktopDesign,
    );

    for (final painter in ['_TapePainter', '_SparklinePainter', '_PsChartCanvas']) {
      await _hover(tester, tester.getCenter(_canvasOf(painter)));
      expect(
        find.textContaining(RegExp(r'^10-13 周二 ')),
        findsOneWidget,
        reason: '$painter 悬停后浮层应当真的报出那一段',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: '$painter 的浮层在 1.6 倍字阶下溢出了',
      );
    }
    await unmountPage(tester);
  });

  group('浮层时间标签', () {
    // 后端两种区间给的是两种短标签，补的那一半不一样，得分别钉住
    test('时刻型把日期顶在前面，日期型把周几挂在后面', () {
      final ts = DateTime(2026, 10, 14, 15).millisecondsSinceEpoch ~/ 1000;
      expect(psTooltipLabel('15:00', ts), '10-14 周三 15:00');
      expect(psTooltipLabel('10-14', ts), '10-14 周三');
    });

    test('没有时间的桩数据原样返回，不编一句 1970', () {
      expect(psTooltipLabel('15:00', 0), '15:00');
    });
  });
}

/// 按 painter 的类名认领画布：一个卡里往往叠着好几层 CustomPaint，
/// 只有 painter 的类型不会认错
Finder _canvasOf(String painterType) => find.byWidgetPredicate(
  (w) =>
      w is CustomPaint && w.painter?.runtimeType.toString() == painterType,
);

/// 读那块画布上 painter 的实时状态
///
/// 生长从第几根起、折线画到了哪儿，这些只在 painter 的字段里，比从截图猜
/// "这根是不是长到一半"直接。类是私有的但字段名是公开的，dynamic 读得到。
dynamic _painter(WidgetTester tester, String painterType) {
  final f = _canvasOf(painterType);
  expect(f, findsOneWidget, reason: '$painterType 应当正好落在一块画布上');
  return tester.widget<CustomPaint>(f).painter;
}

/// 把鼠标真的挪过去
///
/// MouseRegion 只认喂进 binding 的 hover 事件，直接改内部状态等于没测这条路径。
Future<void> _hover(WidgetTester tester, Offset at) async {
  await tester.sendEventToBinding(
    PointerHoverEvent(position: at, kind: PointerDeviceKind.mouse),
  );
  await tester.pump();
}
