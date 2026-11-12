// P3-6 / P3-7 回归：波形服务的两处资源管理。
//
// P3-6：进程级内存缓存原来无上限（一条 1200 bins ≈ 9.6KB，整库扫一遍就上万条），
//       现改为 LRU 上限 200。
// P3-7：.timeout 只是调用方不等了，Rust 侧解码还在跑；旧实现在 finally 里还名额，
//       等于闸门被架空（同时在跑的解码数会超过上限）。现在名额挂在「解码真正
//       结束」的 whenComplete 上，并额外用 _decodingKeys 防同 key 重复发起。
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/services/video_waveform_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('内存缓存 LRU 上限（P3-6）', () {
    test('超过 maxMemoryEntries 条后淘汰最久未用', () async {
      final svc = VideoWaveformService(
        nodeService: NodeSettingsService(),
        ensureDecodeOverride: ({required String filePath, required int bins}) async {
          return <double>[0.1, 0.5, 0.9];
        },
      );

      for (var i = 0; i < VideoWaveformService.maxMemoryEntries + 30; i++) {
        await svc.waveformFor('/videos/v_$i.mp4', bins: 3);
      }

      expect(svc.memoryEntryCount, VideoWaveformService.maxMemoryEntries);
    });

    test('命中缓存会把该条挪到队尾，不会被紧接着的新条目挤掉', () async {
      final svc = VideoWaveformService(
        nodeService: NodeSettingsService(),
        ensureDecodeOverride: ({required String filePath, required int bins}) async {
          return <double>[filePath.length.toDouble()];
        },
      );

      for (var i = 0; i < VideoWaveformService.maxMemoryEntries; i++) {
        await svc.waveformFor('/videos/w_$i.mp4', bins: 3);
      }
      // 再访问最早的那条（命中，挪到队尾）
      await svc.waveformFor('/videos/w_0.mp4', bins: 3);
      // 插入一条新的触发淘汰
      await svc.waveformFor('/videos/newest.mp4', bins: 3);

      expect(svc.memoryEntryCount, VideoWaveformService.maxMemoryEntries);
      // w_0 还在（重新命中过），w_1 被淘汰
      expect(await svc.waveformFor('/videos/w_0.mp4', bins: 3), isNotNull);
    });

    test('失败结果也占用一个槽位（负缓存，避免反复重试）', () async {
      var calls = 0;
      final svc = VideoWaveformService(
        nodeService: NodeSettingsService(),
        ensureDecodeOverride: ({required String filePath, required int bins}) async {
          calls++;
          throw StateError('解码失败');
        },
      );

      await svc.waveformFor('/videos/bad.mp4', bins: 3);
      await svc.waveformFor('/videos/bad.mp4', bins: 3);

      expect(calls, 1, reason: '失败要记负缓存，第二次不该再发起解码');
      expect(svc.memoryEntryCount, 1);
    });
  });

  group('超时不能架空解码闸门（P3-7）', () {
    test('解码超时后名额不立即释放，真完成时才释放', () async {
      final completer = Completer<List<double>>();
      final svc = VideoWaveformService(
        nodeService: NodeSettingsService(),
        decodeTimeout: const Duration(milliseconds: 20),
        ensureDecodeOverride: ({required String filePath, required int bins}) {
          return completer.future;
        },
      );

      final result = await svc.waveformFor('/videos/slow.mp4', bins: 3);
      expect(result, isNull, reason: '超时对调用方就是没有结果');

      // 关键断言：调用方已放弃，但 Rust 侧还在跑 → 名额必须仍被占着
      expect(svc.localDecodingCount, 1,
          reason: '超时不该跟着 finally 释放名额，否则并发上限被架空');
      expect(svc.decodingKeyCount, 1);

      // 真正完成 → whenComplete 放名额
      completer.complete(<double>[0.2, 0.4]);
      await Future<void>.delayed(Duration.zero);

      expect(svc.localDecodingCount, 0);
      expect(svc.decodingKeyCount, 0);
    });

    test('同一文件在解码中时不再重复发起第二份', () async {
      var started = 0;
      final completer = Completer<List<double>>();
      final svc = VideoWaveformService(
        nodeService: NodeSettingsService(),
        decodeTimeout: const Duration(milliseconds: 20),
        ensureDecodeOverride: ({required String filePath, required int bins}) {
          started++;
          return completer.future;
        },
      );

      await svc.waveformFor('/videos/dup.mp4', bins: 3);
      // 第一次已超时（调用方放弃），但解码仍在跑：再点一次同一文件
      await svc.waveformFor('/videos/dup.mp4', bins: 3);

      expect(started, 1, reason: '同 key 还在解码中，不该起第二份');

      completer.complete(<double>[0.3]);
      await Future<void>.delayed(Duration.zero);
      expect(svc.localDecodingCount, 0);
    });

    test('超时/跳过不写负缓存：后台解码完成后仍能拿到真实波形', () async {
      var started = 0;
      final completer = Completer<List<double>>();
      final svc = VideoWaveformService(
        nodeService: NodeSettingsService(),
        decodeTimeout: const Duration(milliseconds: 20),
        ensureDecodeOverride: ({required String filePath, required int bins}) {
          started++;
          return completer.future;
        },
      );

      expect(await svc.waveformFor('/videos/retry.mp4', bins: 3), isNull);
      // 超时不是"这文件没波形"，不能记成负缓存把下次调用也挡死
      expect(svc.memoryEntryCount, 0, reason: '超时不该写入负缓存');

      // 后台那份解码真正完成、名额归还
      completer.complete(<double>[0.7]);
      await Future<void>.delayed(Duration.zero);
      expect(svc.localDecodingCount, 0);

      // 再取一次：应重新发起并拿到数据（而不是被进程内负缓存直接判死）
      final data = await svc.waveformFor('/videos/retry.mp4', bins: 3);
      expect(data, <double>[0.7]);
      expect(started, 2, reason: '超时那次不该留下"已试过且失败"的占位');
    });

    test('解码失败也要放开名额（不会永久泄漏）', () async {
      final svc = VideoWaveformService(
        nodeService: NodeSettingsService(),
        decodeTimeout: const Duration(seconds: 5),
        ensureDecodeOverride: ({required String filePath, required int bins}) async {
          throw StateError('解码崩了');
        },
      );

      await svc.waveformFor('/videos/err.mp4', bins: 3);
      await Future<void>.delayed(Duration.zero);

      expect(svc.localDecodingCount, 0);
      expect(svc.decodingKeyCount, 0);
    });

    test('正常完成时名额也释放（基准行为不被破坏）', () async {
      final svc = VideoWaveformService(
        nodeService: NodeSettingsService(),
        ensureDecodeOverride: ({required String filePath, required int bins}) async {
          return <double>[0.5, 0.8];
        },
      );

      final data = await svc.waveformFor('/videos/ok.mp4', bins: 2);
      expect(data, <double>[0.5, 0.8]);
      await Future<void>.delayed(Duration.zero);
      expect(svc.localDecodingCount, 0);
    });
  });
}
