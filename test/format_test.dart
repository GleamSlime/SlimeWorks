import 'package:flutter_test/flutter_test.dart';
import 'package:slime_works/core/utils/format.dart';

void main() {
  group('formatFileSize', () {
    // ── 字节 ─────────────────────────────────────────────────────────────

    test('0 字节显示为 0.00 B', () {
      expect(formatFileSize(BigInt.zero), '0.00 B');
    });

    test('1 字节显示为 1.00 B', () {
      expect(formatFileSize(BigInt.one), '1.00 B');
    });

    test('1023 字节仍显示为 B', () {
      expect(formatFileSize(BigInt.from(1023)), '1023.00 B');
    });

    // ── KB 边界 ──────────────────────────────────────────────────────────

    test('1024 字节精确转换为 1.00 KB', () {
      expect(formatFileSize(BigInt.from(1024)), '1.00 KB');
    });

    test('1536 字节显示为 1.50 KB', () {
      expect(formatFileSize(BigInt.from(1536)), '1.50 KB');
    });

    test('1023 * 1024 + 1023 仍在 KB 范围内', () {
      final bytes = BigInt.from(1023 * 1024 + 1023);
      final result = formatFileSize(bytes);
      expect(result, endsWith('KB'));
    });

    // ── MB 边界 ──────────────────────────────────────────────────────────

    test('1 MB (1024^2) 精确转换为 1.00 MB', () {
      expect(formatFileSize(BigInt.from(1024 * 1024)), '1.00 MB');
    });

    test('10 MB 正确格式化', () {
      expect(formatFileSize(BigInt.from(10 * 1024 * 1024)), '10.00 MB');
    });

    test('1.5 MB 显示为 1.50 MB', () {
      expect(formatFileSize(BigInt.from((1.5 * 1024 * 1024).round())), '1.50 MB');
    });

    // ── GB 边界 ──────────────────────────────────────────────────────────

    test('1 GB 精确转换为 1.00 GB', () {
      expect(formatFileSize(BigInt.from(1024 * 1024 * 1024)), '1.00 GB');
    });

    test('2.5 GB 正确格式化', () {
      final bytes = BigInt.from((2.5 * 1024 * 1024 * 1024).round());
      expect(formatFileSize(bytes), '2.50 GB');
    });

    // ── TB 边界 ──────────────────────────────────────────────────────────

    test('1 TB 精确转换为 1.00 TB', () {
      expect(formatFileSize(BigInt.from(1024).pow(4)), '1.00 TB');
    });

    test('1.25 TB 正确格式化', () {
      final bytes = BigInt.from(1024).pow(4) * BigInt.from(5) ~/ BigInt.from(4);
      expect(formatFileSize(bytes), '1.25 TB');
    });

    // ── 超大值不超出 TB 范围（停在 TB 级别） ─────────────────────────────

    test('超过 1 PB 仍保留为 TB 计量（不使用 PB 标记）', () {
      // suffixes 只到 TB，超大值继续在 TB 范围内显示
      final bytes = BigInt.from(1024).pow(5); // 1 PB
      final result = formatFileSize(bytes);
      expect(result, endsWith('TB'));
    });

    // ── 精度验证 ──────────────────────────────────────────────────────────

    test('结果始终包含两位小数', () {
      for (final n in [0, 1, 100, 1024, 10000, 1048576]) {
        final result = formatFileSize(BigInt.from(n));
        // 格式必须为 "N.NN <unit>"
        expect(result, matches(r'^\d+\.\d{2} [A-Z]+$'), reason: 'n=$n 格式不正确: $result');
      }
    });
  });
}
