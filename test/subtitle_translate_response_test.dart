import 'package:flutter_test/flutter_test.dart';
import 'package:slime_works/core/services/asr/subtitle_translate_service.dart';

void main() {
  group('SubtitleTranslateService.normalizeTranslated', () {
    test('数组响应按条目一一对齐', () {
      final out = SubtitleTranslateService.normalizeTranslated(
        ['안녕', '그래'],
        2,
      );
      expect(out, ['안녕', '그래']);
    });

    test('整段文本响应按换行拆分', () {
      final out = SubtitleTranslateService.normalizeTranslated(
        '你好\n这样',
        2,
      );
      expect(out, ['你好', '这样']);
    });

    test('条数不一致时抛错，交由调用方保留原文', () {
      expect(
        () => SubtitleTranslateService.normalizeTranslated(['只有一条'], 2),
        throwsException,
      );
      expect(
        () => SubtitleTranslateService.normalizeTranslated('合成了一行', 2),
        throwsException,
      );
      expect(() => SubtitleTranslateService.normalizeTranslated(null, 1), throwsException);
    });
  });
}
