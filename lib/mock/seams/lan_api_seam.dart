import 'package:slime_works/mock/data/lan_mock_data.dart';
import 'package:slime_works/mock/mock_mode.dart';
import 'package:slime_works/src/rust/api/lan_transfer.dart' as rust;

MockLanData get _m => MockLanData.instance;

void lanTransferInit() {
  if (MockMode.enabled) return;
  rust.lanTransferInit();
}

Future<void> lanTransferStart({
  required int port,
  required String saveDir,
  required List<String> preTrustedJson,
  String? accessCode,
}) async {
  if (MockMode.enabled) return;
  await rust.lanTransferStart(
    port: port,
    saveDir: saveDir,
    preTrustedJson: preTrustedJson,
    accessCode: accessCode,
  );
}

Future<void> lanTransferSetAccessCode({String? code}) async {
  if (MockMode.enabled) return;
  await rust.lanTransferSetAccessCode(code: code);
}

Future<void> lanTransferStop() async {
  if (MockMode.enabled) return;
  await rust.lanTransferStop();
}

Future<String> lanTransferGetLocalDevice({required int port}) async {
  if (MockMode.enabled) return _m.localDeviceJson;
  return rust.lanTransferGetLocalDevice(port: port);
}

Future<List<String>> lanTransferGetDevices() async {
  if (MockMode.enabled) return _m.deviceJsonList;
  return rust.lanTransferGetDevices();
}

Future<String> lanTransferSendText({
  required String targetIp,
  required int targetPort,
  required String targetDeviceId,
  required String text,
}) async {
  if (MockMode.enabled) return _m.sendResult(targetDeviceId, isFile: false);
  return rust.lanTransferSendText(
    targetIp: targetIp,
    targetPort: targetPort,
    targetDeviceId: targetDeviceId,
    text: text,
  );
}

Future<String> lanTransferSendFile({
  required String targetIp,
  required int targetPort,
  required String targetDeviceId,
  required String filePath,
}) async {
  if (MockMode.enabled) return _m.sendResult(targetDeviceId, isFile: true);
  return rust.lanTransferSendFile(
    targetIp: targetIp,
    targetPort: targetPort,
    targetDeviceId: targetDeviceId,
    filePath: filePath,
  );
}

Future<void> lanTransferAccept({required String transferId}) async {
  if (MockMode.enabled) return;
  await rust.lanTransferAccept(transferId: transferId);
}

Future<void> lanTransferReject({required String transferId}) async {
  if (MockMode.enabled) return;
  await rust.lanTransferReject(transferId: transferId);
}

Future<void> lanTransferCancel({required String transferId}) async {
  if (MockMode.enabled) {
    _m.cancelled.add(transferId);
    return;
  }
  await rust.lanTransferCancel(transferId: transferId);
}

Future<List<String>> lanTransferGetTransfers() async {
  if (MockMode.enabled) return _m.transferJsonList;
  return rust.lanTransferGetTransfers();
}

Future<void> lanTransferAddTrusted({
  required String deviceId,
  required String deviceName,
}) async {
  if (MockMode.enabled) {
    _m.addTrusted(deviceId, deviceName);
    return;
  }
  await rust.lanTransferAddTrusted(
    deviceId: deviceId,
    deviceName: deviceName,
  );
}

Future<void> lanTransferRemoveTrusted({required String deviceId}) async {
  if (MockMode.enabled) {
    _m.trusted.remove(deviceId);
    return;
  }
  await rust.lanTransferRemoveTrusted(deviceId: deviceId);
}

Future<bool> lanTransferIsTrusted({required String deviceId}) async {
  if (MockMode.enabled) return _m.trusted.contains(deviceId);
  return rust.lanTransferIsTrusted(deviceId: deviceId);
}

Future<List<String>> lanTransferGetTrustedDevices() async {
  if (MockMode.enabled) return _m.trustedJsonList;
  return rust.lanTransferGetTrustedDevices();
}
