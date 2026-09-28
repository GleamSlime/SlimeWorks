import 'package:flutter_test/flutter_test.dart';
import 'package:slime_works/core/services/asr/asr_service.dart';

void main() {
  group('内网转写 verbose_json 解析', () {
    test('segments 秒换算为毫秒并保留文本', () {
      final result = AsrService.parseTranscriptionResponse({
        'text': '第一句第二句',
        'language': 'zh',
        'segments': [
          {'id': 0, 'start': 0.0, 'end': 2.5, 'text': ' 第一句 '},
          {'id': 1, 'start': 2.5, 'end': 5.125, 'text': '第二句'},
        ],
      });

      expect(result.language, 'zh');
      expect(result.segments.length, 2);
      expect(result.segments.first.startMs, 0);
      expect(result.segments.first.endMs, 2500);
      expect(result.segments.first.text, '第一句');
      expect(result.segments.last.endMs, 5125);
    });

    test('服务端只回整段文本时降级为单条字幕', () {
      final result = AsrService.parseTranscriptionResponse({
        'text': '只有文本没有时间轴',
      });

      expect(result.segments.length, 1);
      expect(result.segments.single.text, '只有文本没有时间轴');
      expect(result.segments.single.startMs, 0);
    });

    test('丢弃时间轴非法或空文本的片段', () {
      final result = AsrService.parseTranscriptionResponse({
        'segments': [
          {'start': 3.0, 'end': 1.0, 'text': '时间倒挂'},
          {'start': 1.0, 'end': 2.0, 'text': '   '},
          {'start': '2.0', 'end': '3.5', 'text': '字符串时间'},
        ],
      });

      expect(result.segments.length, 1);
      expect(result.segments.single.endMs, 3500);
    });
  });
}
