// P1-4 回归：歌词翻译必须能读到已持久化的默认模型。
//
// 根因在 OllamaSettingsService：defaultModel 只在 init() 里从 prefs 载入，
// 而 init() 全仓只有 Ollama 设置页 / 小说翻译面板那三处调用；音乐播放器
// 走 translateLyrics() 时直接读 defaultModel.value —— 新启动没打开过那些
// 面板时恒为空串，翻译永远报「未设置默认翻译模型」（即使配置早已保存）。
//
// MusicPlayerViewModel 实例在 flutter_tester 里不可构造（media_kit Player
// 会 DynamicLibrary.open Mpv.framework 失败，见 music_player_logic_test.dart
// 的既有结论），所以这里锁定**服务侧契约**：
//   未 init → 读不到；init 后 → 读到；重复 init 幂等。
// translateLyrics 里现在在读模型前 await settingsService.init()，正是靠这条契约。
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/core/services/ollama/ollama_service.dart';
import 'package:slime_works/core/services/ollama/ollama_settings_service.dart';

const String _kKeyDefaultModel = 'ollama_default_model';
const String _kKeyServers = 'ollama_servers';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      _kKeyServers: '[]', // 空服务器列表：避免 init 时发起真实连通性探测
      _kKeyDefaultModel: 'qwen2.5:14b',
    });
  });

  group('OllamaSettingsService 的模型载入契约（P1-4）', () {
    test('未 init 时 defaultModel 为空（这正是旧实现的 bug 来源）', () {
      final settings = OllamaSettingsService(OllamaService());
      expect(settings.defaultModel.value, '');
      expect(settings.isInitialized.value, isFalse);
    });

    test('init 之后能读到已持久化的默认模型', () async {
      final settings = OllamaSettingsService(OllamaService());
      await settings.init();

      expect(settings.isInitialized.value, isTrue);
      expect(settings.defaultModel.value, 'qwen2.5:14b');
    });

    test('重复 init 幂等：不抛错、值不变', () async {
      final settings = OllamaSettingsService(OllamaService());
      await settings.init();
      await settings.init();
      await settings.init();

      expect(settings.isInitialized.value, isTrue);
      expect(settings.defaultModel.value, 'qwen2.5:14b');
    });

    test('未持久化模型时 init 后仍为空（此时翻译应当报未设置）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _kKeyServers: '[]',
      });
      final settings = OllamaSettingsService(OllamaService());
      await settings.init();

      expect(settings.defaultModel.value, '');
    });

    test('翻译前先 init 的调用顺序能拿到模型（模拟 translateLyrics 路径）', () async {
      // 模拟：用户启动应用后直接进音乐页翻译，从未打开过 Ollama 设置面板
      final settings = OllamaSettingsService(OllamaService());
      final ollama = OllamaService();

      // translateLyrics 当前顺序：取服务 → 确保服务器 → await init → 读模型
      await settings.init();
      final model = settings.defaultModel.value;

      expect(model, isNotEmpty, reason: '模型必须可读到，否则翻译恒失败');
      expect(model, 'qwen2.5:14b');
      // 顺带确认服务对象不带模型状态（模型只在 settings 侧）
      expect(ollama.currentServer, isNull);
    });
  });
}
