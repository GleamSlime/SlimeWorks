import 'dart:convert';

/// 局域网传输演示数据：本机、附近设备、信任设备与传输记录。
class MockLanData {
  MockLanData._();

  static final MockLanData instance = MockLanData._();

  final Set<String> trusted = <String>{'peer-macbook'};
  final Set<String> cancelled = <String>{};

  String get localDeviceJson => jsonEncode({
    'device_id': 'local-demo',
    'device_name': '演示 MacBook Pro',
    'device_type': 'desktop',
    'ip_address': '192.168.1.20',
    'port': 8889,
    'discovered_at': _time(0),
    'is_online': true,
  });

  List<String> get deviceJsonList => [
    jsonEncode({
      'device_id': 'peer-macbook',
      'device_name': '客厅 MacBook',
      'device_type': 'desktop',
      'ip_address': '192.168.1.31',
      'port': 8889,
      'discovered_at': _time(3),
      'is_online': true,
    }),
    jsonEncode({
      'device_id': 'peer-iphone',
      'device_name': '演示 iPhone',
      'device_type': 'mobile',
      'ip_address': '192.168.1.42',
      'port': 8889,
      'discovered_at': _time(9),
      'is_online': true,
    }),
    jsonEncode({
      'device_id': 'peer-windows',
      'device_name': '书房 Windows',
      'device_type': 'desktop',
      'ip_address': '192.168.1.55',
      'port': 8889,
      'discovered_at': _time(26),
      'is_online': false,
    }),
  ];

  List<String> get transferJsonList {
    final items = <Map<String, dynamic>>[
      _transfer(
        id: 'tx-1',
        type: 'File',
        fileName: '京都赏樱.zip',
        fileSize: 184 * 1024 * 1024,
        status: 'Completed',
        progress: 1.0,
        minutesAgo: 2,
      ),
      _transfer(
        id: 'tx-2',
        type: 'Image',
        fileName: 'IMG_2048.jpg',
        fileSize: 6 * 1024 * 1024,
        status: 'Transferring',
        progress: 0.42,
        minutesAgo: 1,
      ),
      _transfer(
        id: 'tx-3',
        type: 'Text',
        textContent: '今晚把素材同步一下',
        status: 'Completed',
        progress: 1.0,
        minutesAgo: 18,
      ),
      _transfer(
        id: 'tx-4',
        type: 'File',
        fileName: 'novel-backup.epub',
        fileSize: 2 * 1024 * 1024,
        status: 'Cancelled',
        progress: 0.31,
        minutesAgo: 55,
      ),
      _transfer(
        id: 'tx-5',
        type: 'Video',
        fileName: 'vlog-raw-01.mp4',
        fileSize: 920 * 1024 * 1024,
        status: 'Failed',
        progress: 0.12,
        minutesAgo: 120,
      ),
      _transfer(
        id: 'tx-6',
        type: 'File',
        fileName: 'wallpaper-pack.zip',
        fileSize: 58 * 1024 * 1024,
        status: 'Queued',
        progress: 0.0,
        minutesAgo: 3,
      ),
    ];
    return items.map(jsonEncode).toList();
  }

  Map<String, dynamic> _transfer({
    required String id,
    required String type,
    String? fileName,
    int? fileSize,
    String? textContent,
    required String status,
    required double progress,
    required int minutesAgo,
  }) {
    return {
      'transfer_id': id,
      'sender_device_id': 'local-demo',
      'sender_device_name': '演示 MacBook Pro',
      'receiver_device_id': 'peer-macbook',
      'receiver_device_name': '客厅 MacBook',
      'transfer_type': type,
      'file_name': fileName,
      'file_size': fileSize,
      'text_content': textContent,
      'file_path': fileName == null ? null : '/mock/lan/$fileName',
      'status': cancelled.contains(id) ? 'Cancelled' : status,
      'progress': progress,
      'created_at': _time(minutesAgo),
      'updated_at': _time(minutesAgo),
      'error_message': status == 'Failed' ? '连接中断（演示）' : null,
    };
  }

  List<String> get trustedJsonList => trusted
      .map(
        (id) => jsonEncode({
          'device_id': id,
          'device_name': id == 'peer-macbook' ? '客厅 MacBook' : '演示设备',
          'trusted_at': _time(1440),
        }),
      )
      .toList();

  String addTrusted(String deviceId, String deviceName) {
    trusted.add(deviceId);
    return jsonEncode({
      'device_id': deviceId,
      'device_name': deviceName,
      'trusted_at': _time(0),
    });
  }

  String sendResult(String targetDeviceId, {required bool isFile}) => jsonEncode({
    '_id': 'tx-${DateTime.now().millisecondsSinceEpoch}',
    'transfer_id': 'tx-${DateTime.now().millisecondsSinceEpoch}',
    'sender_device_id': 'local-demo',
    'sender_device_name': '演示 MacBook Pro',
    'receiver_device_id': targetDeviceId,
    'receiver_device_name': '演示设备',
    'transfer_type': isFile ? 'File' : 'Text',
    'file_name': isFile ? '演示文件.zip' : null,
    'file_size': isFile ? 1024 * 1024 : null,
    'text_content': isFile ? null : '演示消息',
    'status': 'Queued',
    'progress': 0.0,
    'created_at': _time(0),
    'updated_at': _time(0),
  });

  static String _time(int minutesAgo) =>
      DateTime.now().subtract(Duration(minutes: minutesAgo)).toIso8601String();
}
