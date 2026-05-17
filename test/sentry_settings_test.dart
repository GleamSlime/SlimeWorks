import 'package:flutter_test/flutter_test.dart';
import 'package:slime_works/core/services/sentry_settings_service.dart';

void main() {
  group('SentrySettingsService', () {
    test('初始默认值正确', () {
      final service = SentrySettingsService();
      expect(service.enabled.value, isTrue);
      expect(service.selectedNodeId.value, '');
      expect(service.autoRefresh.value, isFalse);
      expect(service.refreshIntervalSeconds.value, 30);
    });

    test('isLocal 判断正确', () {
      final service = SentrySettingsService();
      expect(service.isLocal, isTrue);
      service.selectedNodeId.value = 'node-001';
      expect(service.isLocal, isFalse);
      service.selectedNodeId.value = '';
      expect(service.isLocal, isTrue);
    });

    test('currentDsn 本机模式返回本地地址', () {
      final service = SentrySettingsService();
      final dsn = service.currentDsn;
      expect(dsn.contains('17888'), isTrue);
      expect(dsn.contains('<project_id>'), isTrue);
    });

    test('setEnabled 更新状态', () {
      final service = SentrySettingsService();
      service.enabled.value = false;
      expect(service.enabled.value, isFalse);
      service.enabled.value = true;
      expect(service.enabled.value, isTrue);
    });

    test('setAutoRefresh 更新状态', () {
      final service = SentrySettingsService();
      service.autoRefresh.value = true;
      expect(service.autoRefresh.value, isTrue);
      service.autoRefresh.value = false;
      expect(service.autoRefresh.value, isFalse);
    });

    test('refreshIntervalSeconds 可设置不同值', () {
      final service = SentrySettingsService();
      service.refreshIntervalSeconds.value = 60;
      expect(service.refreshIntervalSeconds.value, 60);
      service.refreshIntervalSeconds.value = 10;
      expect(service.refreshIntervalSeconds.value, 10);
    });

    test('selectedNodeId 切换节点', () {
      final service = SentrySettingsService();
      service.selectedNodeId.value = 'node-123';
      expect(service.selectedNodeId.value, 'node-123');
      expect(service.isLocal, isFalse);
      service.selectedNodeId.value = '';
      expect(service.isLocal, isTrue);
    });
  });
}