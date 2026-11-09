import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slime_works/core/utils/system_proxy.dart';

/// 系统代理自适应检测的纯逻辑单测：环境变量优先级、URL→findProxy 规则转换、
/// macOS scutil / Windows 注册表输出解析，以及 Dio 适配器注入。
/// （真实平台探测依赖 Process.runSync，测试环境只验证可注入的解析层。）
void main() {
  tearDown(SystemProxy.invalidateCache);

  group('SystemProxy.proxyRuleFromEnv', () {
    test('HTTPS_PROXY 优先于 HTTP_PROXY / ALL_PROXY', () {
      expect(
        SystemProxy.proxyRuleFromEnv({
          'HTTP_PROXY': 'http://127.0.0.1:1080',
          'HTTPS_PROXY': 'http://127.0.0.1:7890',
          'ALL_PROXY': 'socks5://127.0.0.1:7891',
        }),
        'PROXY 127.0.0.1:7890',
      );
    });

    test('小写变量同样识别', () {
      expect(
        SystemProxy.proxyRuleFromEnv({'https_proxy': '127.0.0.1:7890'}),
        'PROXY 127.0.0.1:7890',
      );
    });

    test('socks5 scheme 转成 SOCKS 规则', () {
      expect(
        SystemProxy.proxyRuleFromEnv({'ALL_PROXY': 'socks5://127.0.0.1:7891'}),
        'SOCKS 127.0.0.1:7891',
      );
    });

    test('空环境返回 null；空值跳过继续找下一个', () {
      expect(SystemProxy.proxyRuleFromEnv({}), isNull);
      expect(
        SystemProxy.proxyRuleFromEnv({
          'HTTPS_PROXY': '  ',
          'http_proxy': '127.0.0.1:8888',
        }),
        'PROXY 127.0.0.1:8888',
      );
    });
  });

  group('SystemProxy.proxyUrlToRule', () {
    test('裸 host:port 默认 HTTP 代理', () {
      expect(SystemProxy.proxyUrlToRule('127.0.0.1:7890'), 'PROXY 127.0.0.1:7890');
    });

    test('带 scheme / 用户信息 / 路径尾巴都能剥掉', () {
      expect(SystemProxy.proxyUrlToRule('http://user:pass@proxy.local:8080/path'),
          'PROXY proxy.local:8080');
      expect(SystemProxy.proxyUrlToRule('socks5h://127.0.0.1:1080/'),
          'SOCKS 127.0.0.1:1080');
    });

    test('无端口按 scheme 补默认端口', () {
      expect(SystemProxy.proxyUrlToRule('http://proxy.local'), 'PROXY proxy.local:80');
      expect(SystemProxy.proxyUrlToRule('socks5://proxy.local'), 'SOCKS proxy.local:1080');
    });

    test('IPv6 地址保留方括号', () {
      expect(SystemProxy.proxyUrlToRule('http://[::1]:7890'), 'PROXY [::1]:7890');
    });

    test('不支持的 scheme / 非法值返回 null', () {
      expect(SystemProxy.proxyUrlToRule('socks4://127.0.0.1:1080'), isNull);
      expect(SystemProxy.proxyUrlToRule('ftp://x:21'), isNull);
      expect(SystemProxy.proxyUrlToRule(''), isNull);
      expect(SystemProxy.proxyUrlToRule('not a host'), isNull);
    });
  });

  group('SystemProxy.parseScutilProxy', () {
    const fullOutput = '''<dictionary> {
  ExceptionsList : <array> {
    0 : *.local
    1 : 169.254/16
  }
  HTTPEnable : 1
  HTTPPort : 7890
  HTTPProxy : 127.0.0.1
  HTTPSEnable : 1
  HTTPSPort : 7890
  HTTPSProxy : 127.0.0.1
  SOCKSEnable : 1
  SOCKSPort : 7891
  SOCKSProxy : 127.0.0.1
}''';

    test('HTTPS 优先', () {
      expect(SystemProxy.parseScutilProxy(fullOutput), 'PROXY 127.0.0.1:7890');
    });

    test('HTTPS 关闭时回退 HTTP，再回退 SOCKS', () {
      final noHttps = fullOutput.replaceAll('HTTPSEnable : 1', 'HTTPSEnable : 0');
      expect(SystemProxy.parseScutilProxy(noHttps), 'PROXY 127.0.0.1:7890');
      final onlySocks = noHttps.replaceAll('HTTPEnable : 1', 'HTTPEnable : 0');
      expect(SystemProxy.parseScutilProxy(onlySocks), 'SOCKS 127.0.0.1:7891');
    });

    test('全部关闭 / 空输出返回 null', () {
      final allOff = fullOutput
          .replaceAll('HTTPSEnable : 1', 'HTTPSEnable : 0')
          .replaceAll('HTTPEnable : 1', 'HTTPEnable : 0')
          .replaceAll('SOCKSEnable : 1', 'SOCKSEnable : 0');
      expect(SystemProxy.parseScutilProxy(allOff), isNull);
      expect(SystemProxy.parseScutilProxy('<dictionary> {}'), isNull);
    });
  });

  group('SystemProxy.parseWindowsProxyServer', () {
    test('单一 host:port 形式', () {
      const out =
          '    ProxyServer    REG_SZ    127.0.0.1:7890\r\n';
      expect(SystemProxy.parseWindowsProxyServer(out), 'PROXY 127.0.0.1:7890');
    });

    test('分协议形式优先 https 项', () {
      const out =
          '    ProxyServer    REG_SZ    http=127.0.0.1:7890;https=127.0.0.1:7891;ftp=127.0.0.1:7890\r\n';
      expect(SystemProxy.parseWindowsProxyServer(out), 'PROXY 127.0.0.1:7891');
    });

    test('只有 socks 项时转 SOCKS 规则', () {
      const out =
          '    ProxyServer    REG_SZ    socks=127.0.0.1:7891\r\n';
      expect(SystemProxy.parseWindowsProxyServer(out), 'SOCKS 127.0.0.1:7891');
    });

    test('缺值 / 无匹配返回 null', () {
      expect(SystemProxy.parseWindowsProxyServer(''), isNull);
      expect(SystemProxy.parseWindowsProxyServer('    OtherKey    REG_SZ    x'), isNull);
    });
  });

  group('SystemProxy.detect / applyToDio', () {
    test('注入环境变量可探测；无代理环境返回 null（自适应感知代理关闭）', () {
      final env1 = {'HTTPS_PROXY': 'http://127.0.0.1:7890'};
      expect(SystemProxy.detect(environment: env1), 'PROXY 127.0.0.1:7890');
      // 注入环境只查 env、不落缓存：换成空环境立刻回到"无代理"
      expect(SystemProxy.detect(environment: <String, String>{}), isNull);
      // invalidateCache 不影响注入路径的确定性
      SystemProxy.invalidateCache();
      expect(SystemProxy.detect(environment: env1), 'PROXY 127.0.0.1:7890');
    });

    test('applyToDio 注入 IO 适配器并返回规则；无代理不动适配器', () {
      final dio = Dio();
      final rule = SystemProxy.applyToDio(
        dio,
        environment: {'HTTPS_PROXY': 'http://127.0.0.1:19999'},
      );
      expect(rule, 'PROXY 127.0.0.1:19999');
      expect(dio.httpClientAdapter, isA<IOHttpClientAdapter>());
      dio.close();
    });

    test('本机/环回地址绕过代理', () {
      expect(SystemProxy.bypassed(Uri.parse('http://localhost:8080/x')), isTrue);
      expect(SystemProxy.bypassed(Uri.parse('http://127.0.0.1/x')), isTrue);
      expect(SystemProxy.bypassed(Uri.parse('http://nas.local/x')), isTrue);
      expect(SystemProxy.bypassed(Uri.parse('https://api.github.com/x')), isFalse);
    });
  });
}