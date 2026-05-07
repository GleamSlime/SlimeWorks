import 'package:flutter_test/flutter_test.dart';
import 'package:slime_works/core/services/lan_transfer_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 辅助：构造 DeviceInfo
// ─────────────────────────────────────────────────────────────────────────────

DeviceInfo _makeDevice({
  String deviceId = 'dev-001',
  String deviceName = 'TestDevice',
  String deviceType = 'desktop',
  String ipAddress = '192.168.1.10',
  int port = 8889,
  String discoveredAt = '2025-01-01T12:00:00Z',
  bool isOnline = true,
}) {
  return DeviceInfo(
    deviceId: deviceId,
    deviceName: deviceName,
    deviceType: deviceType,
    ipAddress: ipAddress,
    port: port,
    discoveredAt: discoveredAt,
    isOnline: isOnline,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// TransferItem 序列化 / copyWith 测试
// ─────────────────────────────────────────────────────────────────────────────

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

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // TransferItem 序列化
  // ─────────────────────────────────────────────────────────────────────────
  group('TransferItem 序列化', () {
    test('toJson/fromJson 往返一致（文本消息）', () {
      final original = _makeItem();
      final json = original.toJson();
      final restored = TransferItem.fromJson(json);

      expect(restored.transferId, original.transferId);
      expect(restored.senderDeviceId, original.senderDeviceId);
      expect(restored.receiverDeviceId, original.receiverDeviceId);
      expect(restored.receiverDeviceName, original.receiverDeviceName);
      expect(restored.transferType, TransferType.text);
      expect(restored.textContent, 'hello');
      expect(restored.status, TransferStatus.completed);
      expect(restored.progress, 100.0);
    });

    test('toJson/fromJson 往返一致（文件消息，含 filePath）', () {
      final original = _makeItem(
        transferId: 'tx-file-001',
        type: TransferType.image,
        textContent: null,
        fileName: 'photo.jpg',
        fileSize: 204800,
        filePath: '/path/to/photo.jpg',
      );
      final json = original.toJson();
      final restored = TransferItem.fromJson(json);

      expect(restored.transferType, TransferType.image);
      expect(restored.fileName, 'photo.jpg');
      expect(restored.fileSize, 204800);
      expect(restored.filePath, '/path/to/photo.jpg');
    });

    test('fromJson 可处理缺省可选字段', () {
      final json = <String, dynamic>{
        'transfer_id': 'tx-min',
        'sender_device_id': 'dev-A',
        'sender_device_name': 'Device A',
        'receiver_device_id': 'dev-B',
        'transfer_type': 'Text',
        'status': 'Pending',
        'progress': 0.0,
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-01-01T00:00:00Z',
      };
      final item = TransferItem.fromJson(json);

      expect(item.receiverDeviceName, isNull);
      expect(item.fileName, isNull);
      expect(item.filePath, isNull);
      expect(item.textContent, isNull);
    });

    test('所有 TransferStatus 值均可往返序列化', () {
      for (final status in TransferStatus.values) {
        final item = _makeItem(status: status, progress: 0.0);
        final json = item.toJson();
        final restored = TransferItem.fromJson(json);
        expect(restored.status, status, reason: 'status=$status 往返失败');
      }
    });

    test('所有 TransferType 值均可往返序列化', () {
      for (final type in TransferType.values) {
        final item = _makeItem(type: type);
        final json = item.toJson();
        final restored = TransferItem.fromJson(json);
        expect(restored.transferType, type, reason: 'type=$type 往返失败');
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // TransferItem.copyWith
  // ─────────────────────────────────────────────────────────────────────────
  group('TransferItem.copyWith', () {
    test('不传参数时返回等值副本', () {
      final item = _makeItem();
      final copy = item.copyWith();

      expect(copy.transferId, item.transferId);
      expect(copy.textContent, item.textContent);
      expect(copy.status, item.status);
    });

    test('替换 status 字段', () {
      final item = _makeItem(status: TransferStatus.pending);
      final updated = item.copyWith(status: TransferStatus.completed);

      expect(updated.status, TransferStatus.completed);
      expect(updated.progress, item.progress); // 其余字段不变
    });

    test('替换 filePath 字段', () {
      final item = _makeItem(filePath: '/old/path.jpg');
      final updated = item.copyWith(filePath: '/new/path.jpg');

      expect(updated.filePath, '/new/path.jpg');
      expect(updated.fileName, item.fileName);
    });

    test('通过 sentinel 可将 nullable 字段设为 null', () {
      final item = _makeItem(filePath: '/path.jpg', textContent: 'msg');
      // copyWith 不传 filePath 时，原值保留
      final noChange = item.copyWith();
      expect(noChange.filePath, '/path.jpg');

      // 显式将 errorMessage 设为 null
      final withNullError = item.copyWith(errorMessage: null);
      expect(withNullError.errorMessage, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // transferHistoryPeers 分组逻辑（纯 Dart 镜像，不依赖 GetX）
  // ─────────────────────────────────────────────────────────────────────────
  group('transferHistoryPeers 分组逻辑', () {
    /// 镜像 ViewModel 中的分组逻辑（不引入 GetX 依赖）
    List<({String deviceId, String lastCreatedAt})> groupPeers(
      List<TransferItem> history,
      String localId,
    ) {
      if (localId.isEmpty) return [];
      final Map<String, TransferItem> latestByPeer = {};
      for (final item in history) {
        final peerId = item.senderDeviceId == localId ? item.receiverDeviceId : item.senderDeviceId;
        if (peerId.isEmpty) continue;
        final existing = latestByPeer[peerId];
        if (existing == null || item.createdAt.compareTo(existing.createdAt) > 0) {
          latestByPeer[peerId] = item;
        }
      }
      return latestByPeer.entries
          .map((e) => (deviceId: e.key, lastCreatedAt: e.value.createdAt))
          .toList();
    }

    test('localId 未知时返回空列表，不产生错误分组', () {
      final history = [
        _makeItem(transferId: 'tx1', senderDeviceId: 'device-A', receiverDeviceId: 'device-B'),
        _makeItem(transferId: 'tx2', senderDeviceId: 'device-B', receiverDeviceId: 'device-A'),
      ];
      // localId 空时返回空列表（防止错误分组）
      final peers = groupPeers(history, '');
      expect(peers, isEmpty);
    });

    test('双向消息正确归入同一会话', () {
      const aId = 'device-A';
      const bId = 'device-B';
      final history = [
        _makeItem(transferId: 'tx-A-to-B', senderDeviceId: aId, receiverDeviceId: bId),
        _makeItem(transferId: 'tx-B-to-A', senderDeviceId: bId, receiverDeviceId: aId),
      ];
      final peers = groupPeers(history, aId);
      expect(peers.length, 1);
      expect(peers.first.deviceId, bId);
    });

    test('不同对端各自独立分组', () {
      const aId = 'device-A';
      final history = [
        _makeItem(transferId: 'tx1', senderDeviceId: aId, receiverDeviceId: 'device-B'),
        _makeItem(transferId: 'tx2', senderDeviceId: aId, receiverDeviceId: 'device-C'),
      ];
      final peers = groupPeers(history, aId);
      expect(peers.length, 2);
      final ids = peers.map((p) => p.deviceId).toSet();
      expect(ids, {'device-B', 'device-C'});
    });

    test('每个分组保留最新消息的时间', () {
      const aId = 'device-A';
      const bId = 'device-B';
      final history = [
        _makeItem(
          transferId: 'tx-old',
          senderDeviceId: aId,
          receiverDeviceId: bId,
        ).copyWith(createdAt: '2025-01-01T10:00:00Z'),
        _makeItem(
          transferId: 'tx-new',
          senderDeviceId: bId,
          receiverDeviceId: aId,
        ).copyWith(createdAt: '2025-01-02T10:00:00Z'),
      ];
      final peers = groupPeers(history, aId);
      expect(peers.length, 1);
      expect(peers.first.lastCreatedAt, '2025-01-02T10:00:00Z');
    });

    test('空历史返回空列表', () {
      final peers = groupPeers([], 'device-A');
      expect(peers, isEmpty);
    });

    test('peerId 为空的记录被跳过', () {
      const aId = 'device-A';
      final history = [
        _makeItem(transferId: 'tx-valid', senderDeviceId: aId, receiverDeviceId: 'device-B'),
        _makeItem(
          transferId: 'tx-empty-receiver',
          senderDeviceId: aId,
          receiverDeviceId: '', // 空 receiverDeviceId
        ),
      ];
      final peers = groupPeers(history, aId);
      expect(peers.length, 1);
      expect(peers.first.deviceId, 'device-B');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // transferHistoryForPeer 过滤逻辑
  // ─────────────────────────────────────────────────────────────────────────
  group('transferHistoryForPeer 过滤逻辑', () {
    List<TransferItem> historyForPeer(
      List<TransferItem> history,
      String localId,
      String peerDeviceId,
    ) {
      return history.where((item) {
        final peerId = item.senderDeviceId == localId ? item.receiverDeviceId : item.senderDeviceId;
        return peerId == peerDeviceId;
      }).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }

    test('只返回与指定对端的消息', () {
      const local = 'device-A';
      const peer = 'device-B';
      const other = 'device-C';
      final history = [
        _makeItem(transferId: 'tx1', senderDeviceId: local, receiverDeviceId: peer),
        _makeItem(transferId: 'tx2', senderDeviceId: peer, receiverDeviceId: local),
        _makeItem(transferId: 'tx3', senderDeviceId: local, receiverDeviceId: other),
      ];
      final items = historyForPeer(history, local, peer);
      expect(items.length, 2);
      expect(items.map((i) => i.transferId), containsAll(['tx1', 'tx2']));
      expect(items.map((i) => i.transferId), isNot(contains('tx3')));
    });

    test('结果按 createdAt 升序排列', () {
      const local = 'device-A';
      const peer = 'device-B';
      final history = [
        _makeItem(
          transferId: 'tx-later',
          senderDeviceId: local,
          receiverDeviceId: peer,
        ).copyWith(createdAt: '2025-01-03T00:00:00Z'),
        _makeItem(
          transferId: 'tx-earlier',
          senderDeviceId: local,
          receiverDeviceId: peer,
        ).copyWith(createdAt: '2025-01-01T00:00:00Z'),
      ];
      final items = historyForPeer(history, local, peer);
      expect(items.first.transferId, 'tx-earlier');
      expect(items.last.transferId, 'tx-later');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 文件类型识别辅助（镜像 sendFileToDevice 中的类型判断逻辑）
  // ─────────────────────────────────────────────────────────────────────────
  group('文件传输类型识别', () {
    TransferType detectType(String fileName) {
      final lower = fileName.toLowerCase();
      if (lower.endsWith('.jpg') ||
          lower.endsWith('.jpeg') ||
          lower.endsWith('.png') ||
          lower.endsWith('.gif') ||
          lower.endsWith('.webp')) {
        return TransferType.image;
      }
      if (lower.endsWith('.mp4') ||
          lower.endsWith('.mov') ||
          lower.endsWith('.avi') ||
          lower.endsWith('.mkv')) {
        return TransferType.video;
      }
      return TransferType.file;
    }

    test('图片格式正确识别为 image', () {
      for (final ext in ['jpg', 'jpeg', 'png', 'gif', 'webp', 'JPG', 'PNG']) {
        expect(detectType('photo.$ext'), TransferType.image, reason: '.$ext 应识别为 image');
      }
    });

    test('视频格式正确识别为 video', () {
      for (final ext in ['mp4', 'mov', 'avi', 'mkv', 'MP4']) {
        expect(detectType('video.$ext'), TransferType.video, reason: '.$ext 应识别为 video');
      }
    });

    test('其他格式识别为 file', () {
      for (final name in ['doc.pdf', 'archive.zip', 'data.xlsx', 'readme.txt']) {
        expect(detectType(name), TransferType.file, reason: '$name 应识别为 file');
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // TransferStatus 枚举完整性
  // ─────────────────────────────────────────────────────────────────────────
  group('TransferStatus 枚举', () {
    test('包含所有预期状态', () {
      final statuses = TransferStatus.values.map((s) => s.name).toSet();
      for (final expected in [
        'pending',
        'accepted',
        'rejected',
        'transferring',
        'completed',
        'failed',
        'cancelled',
        'queued',
      ]) {
        expect(statuses, contains(expected), reason: '缺少状态: $expected');
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // DeviceInfo 序列化
  // ─────────────────────────────────────────────────────────────────────────
  group('DeviceInfo 序列化', () {
    test('toJson/fromJson 往返一致', () {
      final original = _makeDevice();
      final json = original.toJson();
      final restored = DeviceInfo.fromJson(json);

      expect(restored.deviceId, original.deviceId);
      expect(restored.deviceName, original.deviceName);
      expect(restored.deviceType, original.deviceType);
      expect(restored.ipAddress, original.ipAddress);
      expect(restored.port, original.port);
      expect(restored.discoveredAt, original.discoveredAt);
      expect(restored.isOnline, original.isOnline);
    });

    test('isOnline=false 正确序列化', () {
      final device = _makeDevice(isOnline: false);
      final restored = DeviceInfo.fromJson(device.toJson());
      expect(restored.isOnline, isFalse);
    });

    test('不同端口值正确保留', () {
      final device = _makeDevice(port: 12345);
      final restored = DeviceInfo.fromJson(device.toJson());
      expect(restored.port, 12345);
    });

    test('移动端设备类型正确保留', () {
      final device = _makeDevice(deviceType: 'mobile');
      final restored = DeviceInfo.fromJson(device.toJson());
      expect(restored.deviceType, 'mobile');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // TransferItem progress 字段边界值
  // ─────────────────────────────────────────────────────────────────────────
  group('TransferItem progress 边界值', () {
    test('progress = 0.0 正确序列化', () {
      final item = _makeItem(progress: 0.0);
      expect(TransferItem.fromJson(item.toJson()).progress, 0.0);
    });

    test('progress = 50.5 小数正确保留', () {
      final item = _makeItem(progress: 50.5);
      expect(TransferItem.fromJson(item.toJson()).progress, 50.5);
    });

    test('progress = 100.0 正确序列化', () {
      final item = _makeItem(progress: 100.0);
      expect(TransferItem.fromJson(item.toJson()).progress, 100.0);
    });

    test('fromJson 中 progress 为整数 JSON 类型时正确转为 double', () {
      // 服务端可能返回整数 0/100 而非浮点 0.0/100.0
      final json = <String, dynamic>{
        'transfer_id': 'tx-int-progress',
        'sender_device_id': 'dev-A',
        'sender_device_name': 'Device A',
        'receiver_device_id': 'dev-B',
        'transfer_type': 'File',
        'status': 'Transferring',
        'progress': 75, // 整数
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-01-01T00:00:00Z',
      };
      final item = TransferItem.fromJson(json);
      expect(item.progress, 75.0);
      expect(item.progress, isA<double>());
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // shouldRunEmptyDevicesSelfCheck 冷却逻辑（镜像 LanTransferService 中的逻辑）
  // ─────────────────────────────────────────────────────────────────────────
  group('shouldRunEmptyDevicesSelfCheck 冷却逻辑', () {
    /// 镜像 LanTransferService 中的时间冷却逻辑
    bool Function() buildChecker() {
      DateTime? lastAt;
      return () {
        final now = DateTime.now();
        if (lastAt == null) {
          lastAt = now;
          return true;
        }
        final delta = now.difference(lastAt!);
        if (delta.inSeconds >= 15) {
          lastAt = now;
          return true;
        }
        return false;
      };
    }

    test('首次调用始终返回 true', () {
      final checker = buildChecker();
      expect(checker(), isTrue);
    });

    test('冷却期内连续调用返回 false', () {
      final checker = buildChecker();
      checker(); // 首次
      expect(checker(), isFalse);
      expect(checker(), isFalse);
    });

    test('多次调用后仍只有首次为 true', () {
      final checker = buildChecker();
      final results = List.generate(5, (_) => checker());
      expect(results.first, isTrue);
      expect(results.skip(1).every((r) => r == false), isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // TrustedDevice 序列化
  // ─────────────────────────────────────────────────────────────────────────
  group('TrustedDevice 序列化', () {
    test('fromJson 正确解析各字段', () {
      final json = <String, dynamic>{
        'device_id': 'trusted-001',
        'device_name': 'iPad Pro',
        'trusted_at': '2025-06-01T09:00:00Z',
      };
      final device = TrustedDevice.fromJson(json);
      expect(device.deviceId, 'trusted-001');
      expect(device.deviceName, 'iPad Pro');
      expect(device.trustedAt, '2025-06-01T09:00:00Z');
    });
  });
}
