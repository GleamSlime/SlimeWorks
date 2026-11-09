import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slime_works/core/utils/system_proxy.dart';

/// 真实链路冒烟（手动跑，不进 CI）：验证 SystemProxy 注入后能否通过
/// 系统代理访问 GitHub Release API。运行：
///   flutter test test/system_proxy_live_test.dart --tags live
/// 无网络/无代理环境会失败，属预期，默认 flutter test 已排除该 tag。
/// 注意：不能初始化 TestWidgetsFlutterBinding——它会把 HttpClient 全部
/// mock 成 400，真实请求发不出去；本文件只测纯 Dart 网络层，无需绑定。
void main() {
  test('通过自适应代理拉取 GitHub 最新 Release', () async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'User-Agent': 'SlimeWorks-Updater'},
    ));
    addTearDown(dio.close);
    final rule = SystemProxy.applyToDio(dio);
    // ignore: avoid_print
    print('探测到代理: ${rule ?? '直连'}');
    expect(dio.httpClientAdapter, isA<IOHttpClientAdapter>());
    final resp = await dio.get<dynamic>(
      'https://api.github.com/repos/GleamSlime/SlimeWorks/releases/latest',
      options: Options(responseType: ResponseType.plain),
    );
    expect(resp.statusCode, 200);
    expect((resp.data as String), contains('tag_name'));
  }, tags: 'live', timeout: const Timeout(Duration(minutes: 1)));
}