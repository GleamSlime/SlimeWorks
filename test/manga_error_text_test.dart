import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/core/services/manga_error_text.dart';

void main() {
  group('MangaErrorText.describe', () {
    test('FRB 的 Exception 前缀不进界面', () {
      expect(
        MangaErrorText.describe(Exception('解析错误: bad json')),
        '数据解析失败，请重试',
      );
    });

    test('带 caused by 链的网络错误翻成可行动的一句话', () {
      final text = MangaErrorText.describe(
        Exception(
          '网络错误: error sending request for url (https://api.example.com/eps) '
          'caused by: client error (Connect) caused by: tcp connect error',
        ),
      );
      expect(text, '连不上服务器，试试切换分流节点');
      expect(text.contains('caused by'), isFalse);
    });

    test('401 一律说重新登录，不暴露 token 字样', () {
      expect(
        MangaErrorText.describe(Exception('API错误 [401]: token expired')),
        '登录已过期，请重新登录',
      );
    });

    test('超时优先于连接类关键字', () {
      expect(
        MangaErrorText.describe(Exception('网络错误: request timed out')),
        '请求超时，可切换分流节点后重试',
      );
    });

    test('未知错误截断成一行，不整段甩出堆栈', () {
      final text = MangaErrorText.describe(Exception('x' * 200));
      expect(text.length, MangaErrorText.maxLength + 1); // 截断位 + 省略号
      expect(text.endsWith('…'), isTrue);
    });

    test('换行/制表/CRLF 一律压成一行', () {
      expect(MangaErrorText.describe(Exception('A  \r\nB\t\r\n')), 'A B');
      expect(MangaErrorText.describe(Exception('第1行\n第2行')), '第1行 第2行');
    });

    test('空异常给兜底文案', () {
      expect(MangaErrorText.describe(Exception('')), '操作失败，请稍后重试');
    });
  });
}
