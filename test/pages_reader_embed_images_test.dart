// P2-6：embedLocalImages 从 O(n²) 改成单趟扫描 + 单次 StringBuffer 重建。
//
// 这条改动的验收口径只有一条：**输出必须与旧实现逐字节一致**。
// 所以这里把改动前的实现原样抄一份当 oracle（只去掉日志），用各种
// 畸形/边角 HTML 逐一比对。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slime_works/pages/novel_reader/components/reader_highlight_utils.dart';

/// 旧实现（改动前逐字抄录，仅把 logger 换成静默）。本测试的 oracle。
String _legacyEmbedLocalImages(String html) {
  try {
    String out = html;
    int idx = 0;
    while (true) {
      final imgIdx = out.toLowerCase().indexOf('<img', idx);
      if (imgIdx == -1) break;

      const srcKey = 'src=';
      final srcPos = out.toLowerCase().indexOf(srcKey, imgIdx);
      if (srcPos == -1) {
        idx = imgIdx + 4;
        continue;
      }

      int q = srcPos + srcKey.length;
      while (q < out.length &&
          (out[q] == ' ' || out[q] == '\t' || out[q] == '\n' || out[q] == '\r')) {
        q++;
      }
      if (q >= out.length) break;
      final quote = out[q];
      if (quote != '"' && quote != "'") {
        idx = srcPos + srcKey.length;
        continue;
      }
      final endQuote = out.indexOf(quote, q + 1);
      if (endQuote == -1) break;

      final src = out.substring(q + 1, endQuote);
      if (src.isEmpty) {
        idx = endQuote + 1;
        continue;
      }

      try {
        final lower = src.toLowerCase();
        if (lower.startsWith('data:') ||
            lower.startsWith('http:') ||
            lower.startsWith('https:')) {
          idx = endQuote + 1;
          continue;
        }

        String path = '';
        if (lower.startsWith('file:')) {
          try {
            final uri = Uri.parse(src);
            path = uri.toFilePath(windows: Platform.isWindows);
          } catch (_) {
            path = src.replaceFirst(RegExp(r'^file:///?'), '');
            if (Platform.isWindows && path.startsWith('/')) path = path.substring(1);
          }
        } else {
          path = src.replaceAll('\\', '/');
          if (!File(path).existsSync()) {
            final cwdPath = '${Directory.current.path}/$path';
            if (File(cwdPath).existsSync()) path = cwdPath;
          }
        }

        File file = File(path);
        if (!file.existsSync()) {
          idx = endQuote + 1;
          continue;
        }

        final bytes = file.readAsBytesSync();
        final b64 = base64Encode(bytes);
        final ext = path.contains('.') ? path.split('.').last.toLowerCase() : '';
        final mime =
            {
              'png': 'image/png',
              'jpg': 'image/jpeg',
              'jpeg': 'image/jpeg',
              'gif': 'image/gif',
              'webp': 'image/webp',
              'svg': 'image/svg+xml',
            }[ext] ??
            'application/octet-stream';
        final dataUrl = 'data:$mime;base64,$b64';

        out = out.substring(0, q + 1) + dataUrl + out.substring(endQuote);
        idx = q + 1 + dataUrl.length;
      } catch (e) {
        idx = endQuote + 1;
        continue;
      }
    }
    return out;
  } catch (e) {
    return html;
  }
}

void main() {
  late Directory tmp;
  late String pngPath;
  late String jpgPath;
  late String pngUri;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('embed_imgs_');
    final png = File('${tmp.path}/cover.png');
    png.writeAsBytesSync(<int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    ]);
    pngPath = png.path;
    pngUri = Uri.file(pngPath).toString();

    final jpg = File('${tmp.path}/pic.JPG');
    jpg.writeAsBytesSync(<int>[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
    jpgPath = jpg.path;
  });

  tearDownAll(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('embedLocalImages 与旧实现逐字节一致', () {
    final cases = <String, String Function()>{};

    void addCase(String name, String Function() build) => cases[name] = build;

    String expand(String s) =>
        s.replaceAll('@P', pngPath).replaceAll('@J', jpgPath).replaceAll('@U', pngUri);

    addCase('无 img', () => '<p>只有文字</p>');
    addCase('空串', () => '');
    addCase('单张本地图', () => '<p><img src="@P"/></p>');
    addCase('双引号与单引号混用', () => '<img src="@P"><img src=\'@P\'>');
    addCase('大写 IMG 与 SRC', () => '<IMG SRC="@P">');
    addCase('src 前有多余空白与换行', () => '<img\n  src =  "@P" >');
    addCase('http 与 data 原样保留', () {
      return '<img src="http://a/b.png"><img src="data:image/png;base64,AAA">'
          '<img src="@P">';
    });
    addCase('缺文件被跳过', () => '<img src="/definitely/not/here.png"><img src="@P">');
    addCase('src 后不是引号', () => '<img src=abc><img src="@P">');
    addCase('无 src 的 img', () => '<img alt="x"><img src="@P">');
    addCase('引号未闭合', () => '<img src="@P');
    addCase('空 src', () => '<img src=""><img src="@P">');
    addCase('扩展名大小写无关（JPG）', () => '<img src="@J">');
    addCase('file URI 形式', () => '<img src="@U">');
    addCase('文字里出现 img 字样', () => '说明: <img 标签用法 <img src="@P">');
    addCase('多行正文与中英混排', () {
      return '<h1>第一章</h1>\n<p>Hello <b>世界</b></p>\n<img src="@P"/>\n<p>结尾</p>';
    });
    addCase('一百张图', () {
      final sb = StringBuffer('<div>');
      for (int i = 0; i < 100; i++) {
        sb.write('<p>第 $i 段</p><img src="@P"/>');
      }
      sb.write('</div>');
      return sb.toString();
    });

    for (final entry in cases.entries) {
      test(entry.key, () {
        final html = expand(entry.value());
        expect(
          embedLocalImages(html),
          _legacyEmbedLocalImages(html),
          reason: '新旧实现输出必须逐字节一致（case: ${entry.key}）',
        );
      });
    }
  });

  test('幂等：对已嵌入的结果再跑一次不再变化', () {
    final once = embedLocalImages('<p><img src="$pngPath"/></p>');
    expect(once, contains('data:image/png;base64,'));
    expect(embedLocalImages(once), once);
  });

  test('mime 按扩展名判定（大小写无关）', () {
    final out = embedLocalImages('<img src="$jpgPath">');
    expect(out, contains('data:image/jpeg;base64,'));
  });

  test('100 张同图不会退化成平方级（宽松耗时闸门）', () {
    final sb = StringBuffer();
    for (int i = 0; i < 100; i++) {
      sb.write('<img src="$pngPath">');
    }
    final sw = Stopwatch()..start();
    final out = embedLocalImages(sb.toString());
    sw.stop();
    expect(out, contains('data:image/png;base64,'));
    expect(sw.elapsedMilliseconds, lessThan(5000));
  });
}
