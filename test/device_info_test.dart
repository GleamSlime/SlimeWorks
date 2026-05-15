import 'package:flutter_test/flutter_test.dart';
import 'package:slime_works/core/services/lan_transfer_service.dart';

void main() {
  // ── DeviceInfo ────────────────────────────────────────────────────────────

  group('DeviceInfo', () {
    test('构造函数正确赋值', () {
      final device = DeviceInfo(
        deviceId: 'dev-001',
        deviceName: 'MacBook Pro',
        deviceType: 'desktop',
        ipAddress: '192.168.1.10',
        port: 8889,
        discoveredAt: '2025-01-15T10:00:00Z',
        isOnline: true,
      );
      expect(device.deviceId, 'dev-001');
      expect(device.deviceName, 'MacBook Pro');
      expect(device.deviceType, 'desktop');
      expect(device.ipAddress, '192.168.1.10');
      expect(device.port, 8889);
      expect(device.discoveredAt, '2025-01-15T10:00:00Z');
      expect(device.isOnline, isTrue);
    });

    test('toJson/fromJson 往返一致', () {
      final device = DeviceInfo(
        deviceId: 'dev-002',
        deviceName: 'iPhone',
        deviceType: 'mobile',
        ipAddress: '192.168.1.20',
        port: 9999,
        discoveredAt: '2025-06-01T08:30:00Z',
        isOnline: false,
      );
      final json = device.toJson();
      final restored = DeviceInfo.fromJson(json);

      expect(restored.deviceId, device.deviceId);
      expect(restored.deviceName, device.deviceName);
      expect(restored.deviceType, device.deviceType);
      expect(restored.ipAddress, device.ipAddress);
      expect(restored.port, device.port);
      expect(restored.discoveredAt, device.discoveredAt);
      expect(restored.isOnline, device.isOnline);
    });

    test('toJson 键名使用 snake_case', () {
      final device = DeviceInfo(
        deviceId: 'd',
        deviceName: 'n',
        deviceType: 't',
        ipAddress: '1.2.3.4',
        port: 8080,
        discoveredAt: '2025-01-01',
        isOnline: true,
      );
      final json = device.toJson();
      expect(json.containsKey('device_id'), isTrue);
      expect(json.containsKey('device_name'), isTrue);
      expect(json.containsKey('device_type'), isTrue);
      expect(json.containsKey('ip_address'), isTrue);
      expect(json.containsKey('port'), isTrue);
      expect(json.containsKey('discovered_at'), isTrue);
      expect(json.containsKey('is_online'), isTrue);
    });

    test('离线设备 isOnline 为 false', () {
      final device = DeviceInfo(
        deviceId: 'offline',
        deviceName: 'Offline Device',
        deviceType: 'desktop',
        ipAddress: '10.0.0.1',
        port: 8889,
        discoveredAt: '2025-01-01',
        isOnline: false,
      );
      expect(device.isOnline, isFalse);
    });
  });

  // ── TrustedDevice ────────────────────────────────────────────────────────

  group('TrustedDevice', () {
    test('构造函数正确赋值', () {
      final device = TrustedDevice(
        deviceId: 'trusted-001',
        deviceName: 'My Laptop',
        trustedAt: '2025-03-15T12:00:00Z',
      );
      expect(device.deviceId, 'trusted-001');
      expect(device.deviceName, 'My Laptop');
      expect(device.trustedAt, '2025-03-15T12:00:00Z');
    });

    test('fromJson 正确解析', () {
      final json = <String, dynamic>{
        'device_id': 'trusted-002',
        'device_name': 'My Phone',
        'trusted_at': '2025-06-01T00:00:00Z',
      };
      final device = TrustedDevice.fromJson(json);
      expect(device.deviceId, 'trusted-002');
      expect(device.deviceName, 'My Phone');
      expect(device.trustedAt, '2025-06-01T00:00:00Z');
    });
  });

  // ── TransferType 序列化 ──────────────────────────────────────────────────

  group('TransferType 序列化', () {
    test('所有 TransferType 值可通过字符串映射', () {
      final typeMap = <TransferType, String>{
        TransferType.file: 'File',
        TransferType.text: 'Text',
        TransferType.image: 'Image',
        TransferType.video: 'Video',
      };
      for (final entry in typeMap.entries) {
        final item = _makeItem(type: entry.key);
        final json = item.toJson();
        final restored = TransferItem.fromJson(json);
        expect(restored.transferType, entry.key, reason: '${entry.value} 往返失败');
      }
    });
  });

  // ── TransferStatus 序列化 ────────────────────────────────────────────────

  group('TransferStatus 序列化', () {
    test('所有 TransferStatus 值可通过字符串映射', () {
      for (final status in TransferStatus.values) {
        final item = _makeItem(status: status);
        final json = item.toJson();
        final restored = TransferItem.fromJson(json);
        expect(restored.status, status, reason: 'status=${status.name} 往返失败');
      }
    });
  });
}

TransferItem _makeItem({
  String transferId = 'tx-001',
  String senderDeviceId = 'device-A',
  String senderDeviceName = 'MacBook',
  String receiverDeviceId = 'device-B',
  String? receiverDeviceName = 'iPhone',
  TransferType type = TransferType.text,
  String? textContent = 'hello',
  String? fileName,
  int? fileSize,
  String? filePath,
  TransferStatus status = TransferStatus.completed,
  double progress = 100.0,
}) {
  return TransferItem(
    transferId: transferId,
    senderDeviceId: senderDeviceId,
    senderDeviceName: senderDeviceName,
    receiverDeviceId: receiverDeviceId,
    receiverDeviceName: receiverDeviceName,
    transferType: type,
    textContent: textContent,
    fileName: fileName,
    fileSize: fileSize,
    filePath: filePath,
    status: status,
    progress: progress,
    createdAt: '2025-01-01T12:00:00.000Z',
    updatedAt: '2025-01-01T12:00:01.000Z',
  );
}