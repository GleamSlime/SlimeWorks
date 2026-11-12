// P2-4 回归：用户正在操作时不许静默装更新并重启。
//
// 旧实现里 markUserActive() 零调用、闲置判定只看 lifecycle（桌面端恒 resumed），
// 于是五分钟一到必然触发「静默下载 + 安装 + 重启」，用户正在用也被打断；
// 而且检查失败后没有任何退避，闲置轮询每分钟重打一次 GitHub。
//
// 这里用注入时钟验证三件事：
//  1) 活跃输入会重置闲置计时（窗口聚焦时一律不算可静默安装）；
//  2) 窗口失焦 + 闲置够久才算可以静默安装；
//  3) 失败退避 1min → 2 → 4 … 上限 1h。
import 'package:flutter/material.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/core/services/app_update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppUpdateService service;
  late DateTime fakeNow;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    service = AppUpdateService();
    fakeNow = DateTime(2026, 11, 12, 10, 0, 0);
    service.nowProvider = () => fakeNow;
  });

  void advance(Duration d) => fakeNow = fakeNow.add(d);

  group('活跃输入重置闲置计时（P2-4）', () {
    test('focus 状态下即使闲置很久也不允许静默安装', () async {
      await service.setAutoUpdateEnabled(true);
      // 默认 windowFocused = true：模拟窗口一直在前台被人使用
      advance(const Duration(hours: 2));

      expect(service.canAutoInstallQuietly(), isFalse,
          reason: '窗口聚焦 = 人就在旁边，静默重启会直接打断');
    });

    test('窗口失焦 + 闲置够阈值才允许静默安装', () async {
      await service.setAutoUpdateEnabled(true);
      service.onWindowFocusChanged(false);

      // 刚失焦，闲置还不够 5 分钟
      advance(const Duration(minutes: 1));
      expect(service.canAutoInstallQuietly(), isFalse);

      // 越过 5 分钟阈值
      advance(const Duration(minutes: 5));
      expect(service.canAutoInstallQuietly(), isTrue);
    });

    test('markUserActive 把闲置计时重置（鼠标/键盘活动）', () async {
      await service.setAutoUpdateEnabled(true);
      service.onWindowFocusChanged(false);

      advance(const Duration(minutes: 10));
      expect(service.canAutoInstallQuietly(), isTrue);

      // 用户碰了一下鼠标/敲了个键
      service.markUserActive();
      expect(service.canAutoInstallQuietly(), isFalse,
          reason: '刚有输入就该重新开始算闲置');

      advance(const Duration(minutes: 4));
      expect(service.canAutoInstallQuietly(), isFalse);
    });

    test('窗口重新聚焦按活跃处理', () async {
      await service.setAutoUpdateEnabled(true);
      service.onWindowFocusChanged(false);
      advance(const Duration(minutes: 10));
      expect(service.canAutoInstallQuietly(), isTrue);

      service.onWindowFocusChanged(true);
      expect(service.canAutoInstallQuietly(), isFalse);
    });

    test('lifecycle resumed 也重置闲置计时', () async {
      await service.setAutoUpdateEnabled(true);
      service.onWindowFocusChanged(false);
      advance(const Duration(minutes: 10));
      expect(service.canAutoInstallQuietly(), isTrue);

      service.onLifecycleStateChanged(AppLifecycleState.resumed);
      expect(service.canAutoInstallQuietly(), isFalse);
    });

    test('自动更新开关关闭时永不允许静默安装', () async {
      service.onWindowFocusChanged(false);
      advance(const Duration(hours: 3));

      expect(service.canAutoInstallQuietly(), isFalse);
    });
  });

  group('检查失败指数退避（P2-4）', () {
    test('连续失败：1min → 2 → 4 → 8 … 上限 1h', () async {
      expect(service.currentBackoff, Duration.zero);
      expect(service.backoffUntil, isNull);

      final expected = <Duration>[
        const Duration(minutes: 1),
        const Duration(minutes: 2),
        const Duration(minutes: 4),
        const Duration(minutes: 8),
        const Duration(minutes: 16),
        const Duration(minutes: 32),
        const Duration(hours: 1), // 64min 超上限 → 钳到 1h
        const Duration(hours: 1), // 之后一直保持 1h
      ];

      for (final want in expected) {
        service.registerCheckFailure();
        expect(service.currentBackoff, want);
      }
    });

    test('backoffUntil = 失败时刻 + 当前退避', () {
      service.registerCheckFailure();
      expect(service.backoffUntil, fakeNow.add(const Duration(minutes: 1)));

      advance(const Duration(minutes: 1));
      service.registerCheckFailure();
      expect(service.backoffUntil, fakeNow.add(const Duration(minutes: 2)));
    });

    test('startAutoCheck 会清掉退避状态（用户手动重开开关）', () async {
      await service.setAutoUpdateEnabled(true);
      service.registerCheckFailure();
      service.registerCheckFailure();
      expect(service.currentBackoff, const Duration(minutes: 2));

      service.startAutoCheck();
      expect(service.currentBackoff, Duration.zero);
      expect(service.backoffUntil, isNull);

      service.stopAutoCheck();
    });
  });
}
