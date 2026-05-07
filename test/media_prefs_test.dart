import 'package:flutter_test/flutter_test.dart';
import 'package:slime_works/core/services/media_prefs_service.dart';

void main() {
  // ── ThumbQualityLevel 静态配置 ─────────────────────────────────────────

  group('ThumbQualityLevel 配置', () {
    test('levels 共 5 个级别', () {
      expect(MediaPrefsService.levels.length, 5);
    });

    test('每个级别的 label 均唯一且非空', () {
      final labels = MediaPrefsService.levels.map((l) => l.label).toList();
      expect(labels.toSet().length, labels.length); // 无重复
      for (final l in labels) {
        expect(l, isNotEmpty);
      }
    });

    test('级别索引 0=极低，4=超高', () {
      expect(MediaPrefsService.levels[0].label, '极低');
      expect(MediaPrefsService.levels[4].label, '超高');
    });

    test('scaleWidth 随级别递增', () {
      final widths = MediaPrefsService.levels.map((l) => l.scaleWidth).toList();
      for (int i = 1; i < widths.length; i++) {
        expect(widths[i], greaterThan(widths[i - 1]), reason: '级别 $i 的 scaleWidth 应大于级别 ${i - 1}');
      }
    });

    test('qv（画质参数）随级别递减（值越小质量越高）', () {
      final qvs = MediaPrefsService.levels.map((l) => l.qv).toList();
      for (int i = 1; i < qvs.length; i++) {
        expect(qvs[i], lessThan(qvs[i - 1]), reason: '级别 $i 的 qv 应小于级别 ${i - 1}（更高质量）');
      }
    });

    test('frameCount 均 > 0', () {
      for (final l in MediaPrefsService.levels) {
        expect(l.frameCount, greaterThan(0));
        expect(l.frameCountFallback, greaterThan(0));
      }
    });

    test('frameCountFallback 不超过 frameCount', () {
      for (final l in MediaPrefsService.levels) {
        expect(l.frameCountFallback, lessThanOrEqualTo(l.frameCount));
      }
    });
  });

  // ── currentLevel 逻辑（通过镜像服务 _currentLevel 函数测试） ───────────

  group('currentLevel 映射', () {
    // 镜像 MediaPrefsService.currentLevel 的纯逻辑
    ThumbQualityLevel levelForQuality(int quality) {
      return MediaPrefsService.levels[(quality - 1).clamp(0, MediaPrefsService.levels.length - 1)];
    }

    test('quality=1 映射到极低', () {
      expect(levelForQuality(1).label, '极低');
    });

    test('quality=3 映射到中', () {
      expect(levelForQuality(3).label, '中');
    });

    test('quality=5 映射到超高', () {
      expect(levelForQuality(5).label, '超高');
    });

    test('quality=0（越界）被 clamp 为极低', () {
      expect(levelForQuality(0).label, '极低');
    });

    test('quality=9（越界）被 clamp 为超高', () {
      expect(levelForQuality(9).label, '超高');
    });
  });

  // ── 预设列表完整性 ──────────────────────────────────────────────────────

  group('cacheLimitPresets', () {
    test('预设列表非空', () {
      expect(MediaPrefsService.cacheLimitPresets, isNotEmpty);
    });

    test('包含 "无限制" 选项（value=0）', () {
      final unlimited = MediaPrefsService.cacheLimitPresets.where((p) => p.value == 0).toList();
      expect(unlimited, isNotEmpty);
      expect(unlimited.first.label, '无限制');
    });

    test('所有 value >= 0', () {
      for (final p in MediaPrefsService.cacheLimitPresets) {
        expect(p.value, greaterThanOrEqualTo(0));
      }
    });

    test('labels 均唯一且非空', () {
      final labels = MediaPrefsService.cacheLimitPresets.map((p) => p.label).toList();
      expect(labels.toSet().length, labels.length);
      for (final l in labels) {
        expect(l, isNotEmpty);
      }
    });
  });

  group('remoteCoverWidthPresets', () {
    test('包含 "原图" 选项（value=0）', () {
      final orig = MediaPrefsService.remoteCoverWidthPresets.where((p) => p.value == 0).toList();
      expect(orig, isNotEmpty);
    });

    test('所有 value >= 0', () {
      for (final p in MediaPrefsService.remoteCoverWidthPresets) {
        expect(p.value, greaterThanOrEqualTo(0));
      }
    });
  });

  group('remoteImageWidthPresets', () {
    test('包含 "原图" 选项（value=0）', () {
      final orig = MediaPrefsService.remoteImageWidthPresets.where((p) => p.value == 0).toList();
      expect(orig, isNotEmpty);
    });

    test('所有 value >= 0', () {
      for (final p in MediaPrefsService.remoteImageWidthPresets) {
        expect(p.value, greaterThanOrEqualTo(0));
      }
    });
  });

  group('localPreviewWidthPresets', () {
    test('包含 "原图" 选项（value=0）', () {
      final orig = MediaPrefsService.localPreviewWidthPresets.where((p) => p.value == 0).toList();
      expect(orig, isNotEmpty);
    });

    test('非原图预设 value 递减（大到小）', () {
      final nonOrig = MediaPrefsService.localPreviewWidthPresets.where((p) => p.value > 0).toList();
      for (int i = 1; i < nonOrig.length; i++) {
        expect(nonOrig[i].value, lessThan(nonOrig[i - 1].value), reason: '宽度预设应从大到小排列');
      }
    });
  });
}
