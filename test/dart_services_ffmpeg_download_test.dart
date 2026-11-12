import 'package:flutter_test/flutter_test.dart';
import 'package:slime_works/core/services/initialize/ffmpeg.dart';

// P1-6 回归：Windows 下 ffprobe 下载命令的 PowerShell 参数拼接。
//
// 旧实现是 `-OutFile "$targetPath"-UseBasicParsing`——少一个空格，PowerShell
// 会把 `-UseBasicParsing` 当成路径尾巴的一部分，命令必然失败，Windows 上
// ffprobe 永远下不下来（视频元数据/缩略图整条链路不可用）。
void main() {
  group('Windows ffprobe 下载命令拼接', () {
    test('OutFile 与 UseBasicParsing 之间有空格', () {
      final cmd = RustFFmpeg.buildProbePowershellCommand(
        url: 'https://example.com/ffprobe.exe',
        targetPath: r'C:\Users\me\AppData\Roaming\SlimeWorks\ffprobe.exe',
      );

      expect(cmd, contains('" -UseBasicParsing'));
      // 反向断言：旧 bug 的拼接形式（引号紧跟参数名）不许再出现
      expect(cmd, isNot(contains(r'"-UseBasicParsing')));
      expect(cmd, isNot(contains(r'.exe"-UseBasicParsing')));
    });

    test('URL 与目标路径各自被引号包住', () {
      final cmd = RustFFmpeg.buildProbePowershellCommand(
        url: 'https://example.com/ffprobe.exe',
        targetPath: r'C:\Program Files\SlimeWorks\ffprobe.exe',
      );

      expect(cmd, contains('-Uri "https://example.com/ffprobe.exe"'));
      // 路径含空格时必须整体被引号包住，否则 PowerShell 会拆成两个参数
      expect(cmd, contains('-OutFile "C:\\Program Files\\SlimeWorks\\ffprobe.exe"'));
      expect(cmd.startsWith('Invoke-WebRequest '), isTrue);
    });

    test('参数顺序固定：Uri → OutFile → UseBasicParsing', () {
      final cmd = RustFFmpeg.buildProbePowershellCommand(
        url: 'https://a/b',
        targetPath: '/tmp/b',
      );
      final uriAt = cmd.indexOf('-Uri');
      final outFileAt = cmd.indexOf('-OutFile');
      final useBasicAt = cmd.indexOf('-UseBasicParsing');

      expect(uriAt, greaterThanOrEqualTo(0));
      expect(outFileAt, greaterThan(uriAt));
      expect(useBasicAt, greaterThan(outFileAt));
    });
  });
}
