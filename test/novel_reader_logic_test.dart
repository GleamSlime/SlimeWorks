// 小说阅读器 ViewModel 可测逻辑切片单测。
//
// 设计约束（不触发 FFI / 不发真实网络 / 不需要 RustLib.init）：
// - NovelReaderViewModel 构造函数只接收 NovelMetadata，直接 new 即可，
//   不走 Get.put（避免 onInit 里的自动 loadNovelContent 触发 FRB）。
// - 章节内容加载路径（getChapterContent 等 FRB 调用）在测试环境必抛，
//   VM 自身 try/catch 吞掉，本文件同时锁定"FFI 不可用时错误被兜住"。
// - 翻译管线经注册 OllamaService 桩子类驱动：translateCurrentChapter 内
//   getIt.get<OllamaService>() 命中桩实现，可端到端验证 _cleanTranslationResult
//   与 HTML 文本节点替换；全程不发网络。
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
// assignAll 等 Rx 集合扩展由 get 包提供（hide 避免与 dio 的同名类型冲突）
// ignore: depend_on_referenced_packages
import 'package:get/get.dart' hide Response, FormData, MultipartFile;
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/ollama/ollama_models.dart';
import 'package:slime_works/core/services/ollama/ollama_service.dart';
import 'package:slime_works/src/rust/api/novel_reader.dart';
import 'package:slime_works/view_models/novel_reader_viewmodel.dart';

/// 桩 Ollama 服务：translate 从预设映射取译文，可指定按文本抛错。
class _StubOllamaService extends OllamaService {
  final Map<String, String> responses = {};
  final Set<String> failOn = {};
  final List<String> calls = [];

  @override
  Future<String> translate({
    required String model,
    required String text,
    required TranslationLanguagePair languagePair,
    void Function(String chunk)? onChunk,
    CancelToken? cancelToken,
  }) async {
    calls.add(text);
    if (failOn.contains(text)) throw Exception('模拟翻译失败');
    return responses[text] ?? '译文:$text';
  }
}

NovelMetadata book({String id = 'n1', double progress = 0}) {
  return NovelMetadata(
    id: id,
    title: '测试书',
    filePath: '/lib/$id.txt',
    format: NovelFormat.txt,
    fileSize: BigInt.one,
    modifiedAt: 0,
    addedAt: 0,
    progress: progress,
    isFavorite: false,
    tags: const [],
  );
}

NovelChapter chapter(int i) => NovelChapter(id: 'c$i', title: '第$i章', index: BigInt.from(i));

SearchMatch matchAt(int chapterIndex, {int position = 0}) {
  return SearchMatch(
    chapterIndex: BigInt.from(chapterIndex),
    chapterTitle: '第$chapterIndex章',
    position: BigInt.from(position),
    snippet: '命中片段',
  );
}

/// 让 FRB 调用失败后的异步 catch/finally 完成传播。
Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NovelReaderViewModel vm;

  setUp(() {
    vm = NovelReaderViewModel(book());
  });

  // ── 章节边界状态机 ─────────────────────────────────────────────────────────

  group('章节导航边界', () {
    setUp(() {
      vm.chapters.assignAll([chapter(0), chapter(1), chapter(2)]);
    });

    test('首页 hasPreviousChapter=false / 末页 hasNextChapter=false', () {
      expect(vm.hasPreviousChapter(), isFalse);
      expect(vm.hasNextChapter(), isTrue);
      vm.currentChapterIndex.value = 2;
      expect(vm.hasPreviousChapter(), isTrue);
      expect(vm.hasNextChapter(), isFalse);
    });

    test('previousChapter / nextChapter 边界处不移动索引', () {
      vm.previousChapter(); // 已在 0，守卫不通过，不触发加载
      expect(vm.currentChapterIndex.value, 0);
      expect(vm.errorMessage.value, isEmpty); // 未走 FFI

      vm.currentChapterIndex.value = 2;
      vm.nextChapter(); // 已在末页
      expect(vm.currentChapterIndex.value, 2);
    });

    test('nextChapter 前进一章：索引立即更新，FFI 失败被兜住', () async {
      vm.nextChapter();
      expect(vm.currentChapterIndex.value, 1); // 索引先于加载同步更新
      await settle();
      // 未初始化 RustLib：getChapterContent 抛错 → errorMessage 记录、loading 归位
      expect(vm.errorMessage.value, isNotEmpty);
      expect(vm.isLoading.value, isFalse);
    });

    test('goToChapter 越界索引不改动当前章，也不触发加载', () {
      vm.currentChapterIndex.value = 1;
      vm.goToChapter(-1);
      vm.goToChapter(3);
      expect(vm.currentChapterIndex.value, 1);
      expect(vm.errorMessage.value, isEmpty);
      expect(vm.isLoading.value, isFalse);
    });

    test('goToChapter 合法索引：立即更新并走（失败的）内容加载', () async {
      vm.goToChapter(2);
      expect(vm.currentChapterIndex.value, 2);
      await settle();
      expect(vm.errorMessage.value, isNotEmpty);
      expect(vm.isLoading.value, isFalse);
    });

    test('空章节列表时任何跳转都不动状态', () async {
      final empty = NovelReaderViewModel(book());
      empty.goToChapter(0);
      empty.nextChapter();
      empty.previousChapter();
      expect(empty.currentChapterIndex.value, 0);
      expect(empty.errorMessage.value, isEmpty);
      await settle();
      expect(empty.isLoading.value, isFalse);
    });
  });

  // ── HTML 缓存与逐出 ───────────────────────────────────────────────────────

  group('cacheHtml / getCachedHtml', () {
    test('写入即读回，重复写入同 key 覆盖', () {
      vm.cacheHtml(0, '<p>A</p>');
      expect(vm.getCachedHtml(0), '<p>A</p>');
      vm.cacheHtml(0, '<p>B</p>');
      expect(vm.getCachedHtml(0), '<p>B</p>');
      expect(vm.getCachedHtml(9), isNull);
    });

    test('超过 3 个条目时按 key 数值保留最大 3 个（逐出最小 key）', () {
      // 注意：实现的"保留最近 3 章"以 key 排序为准而非插入序，
      // 该用例锁定这一确定性行为。
      vm.cacheHtml(1, 'a');
      vm.cacheHtml(2, 'b');
      vm.cacheHtml(3, 'c');
      vm.cacheHtml(4, 'd'); // 触发逐出：keys [1,2,3,4] → 删 1
      expect(vm.getCachedHtml(1), isNull);
      expect(vm.getCachedHtml(4), 'd');
      vm.cacheHtml(10, 'e'); // keys [2,3,4,10] → 删 2
      expect(vm.getCachedHtml(2), isNull);
      expect(vm.getCachedHtml(10), 'e');
      expect(vm.getCachedHtml(3), 'c');
      expect(vm.getCachedHtml(4), 'd');
    });
  });

  // ── 搜索导航状态演化 ───────────────────────────────────────────────────────

  group('搜索结果导航', () {
    setUp(() {
      vm.chapters.assignAll([chapter(0), chapter(1), chapter(2)]);
    });

    test('空结果集时 next/previous 为无操作', () {
      final before = vm.searchScrollTrigger.value;
      vm.nextSearchResult();
      vm.previousSearchResult();
      expect(vm.searchScrollTrigger.value, before);
      expect(vm.selectedSearchIndex.value, -1);
    });

    test('同章节内 next/previous 环形推进并触发滚动信号', () {
      vm.searchMatches.assignAll([matchAt(0), matchAt(0, position: 5), matchAt(0, position: 9)]);
      vm.selectedSearchIndex.value = 0;
      final trigger0 = vm.searchScrollTrigger.value;

      vm.nextSearchResult();
      expect(vm.selectedSearchIndex.value, 1);
      expect(vm.searchScrollTrigger.value, trigger0 + 1);
      vm.nextSearchResult();
      vm.nextSearchResult(); // 环形回到 0
      expect(vm.selectedSearchIndex.value, 0);
      expect(vm.currentChapterIndex.value, 0); // 未跨章

      vm.previousSearchResult(); // 0 → 环形到 2
      expect(vm.selectedSearchIndex.value, 2);
      expect(vm.searchScrollTrigger.value, trigger0 + 4);
    });

    test('跨章结果：当前章索引同步切换，FFI 失败被兜住', () async {
      vm.searchMatches.assignAll([matchAt(0), matchAt(2)]);
      vm.selectedSearchIndex.value = 0;
      vm.nextSearchResult(); // 跳到第 2 章
      expect(vm.selectedSearchIndex.value, 1);
      expect(vm.currentChapterIndex.value, 2); // goToChapter 同步部分生效
      await settle();
      expect(vm.isLoading.value, isFalse);
    });

    test('lastSearchQuery 记录：直接赋值语义（搜索执行本身依赖 FFI，不在此覆盖）', () {
      vm.lastSearchQuery.value = '关键词';
      expect(vm.lastSearchQuery.value, '关键词');
    });

    test('clearSearch 清空结果与选中态', () {
      vm.searchMatches.assignAll([matchAt(0), matchAt(1)]);
      vm.selectedSearchIndex.value = 1;
      vm.clearSearch();
      expect(vm.searchMatches, isEmpty);
      expect(vm.selectedSearchIndex.value, -1);
    });

    test('openSearchResultsList 无匹配时空转，有匹配但无页面上下文时安全返回', () {
      vm.openSearchResultsList(); // matches 为空 → 早退
      vm.searchMatches.assignAll([matchAt(0)]);
      vm.openSearchResultsList(); // _pageContext 为 null → 弹对话框逻辑早退，不崩
    });
  });

  // ── 字号 / 行距 / 侧栏开关 ─────────────────────────────────────────────────

  group('阅读偏好', () {
    test('字号上下界：32 封顶、12 封底，步进 2', () {
      for (var i = 0; i < 12; i++) {
        vm.increaseFontSize();
      }
      expect(vm.fontSize.value, 32);
      vm.decreaseFontSize();
      expect(vm.fontSize.value, 30);
      for (var i = 0; i < 15; i++) {
        vm.decreaseFontSize();
      }
      expect(vm.fontSize.value, 12);
    });

    test('setLineHeight 夹在 1.2~2.6', () {
      vm.setLineHeight(0.5);
      expect(vm.lineHeight.value, 1.2);
      vm.setLineHeight(9);
      expect(vm.lineHeight.value, 2.6);
      vm.setLineHeight(1.9);
      expect(vm.lineHeight.value, 1.9);
    });

    test('toggleChapterList 翻转显隐', () {
      final before = vm.showChapterList.value;
      vm.toggleChapterList();
      expect(vm.showChapterList.value, isNot(before));
    });

    test('toggleAutoTranslate 仅翻转开关：模型未配置时不启动翻译', () {
      vm.toggleAutoTranslate();
      expect(vm.isAutoTranslateEnabled.value, isTrue);
      expect(vm.isTranslating.value, isFalse); // translationModel 为 null → 不触发
      vm.toggleAutoTranslate();
      expect(vm.isAutoTranslateEnabled.value, isFalse);
    });
  });

  // ── 翻译管线（含 _cleanTranslationResult 清洗） ───────────────────────────

  group('章节翻译（OllamaService 桩驱动）', () {
    late _StubOllamaService ollama;

    setUp(() async {
      await getIt.reset();
      ollama = _StubOllamaService();
      getIt.registerSingleton<OllamaService>(ollama);
    });

    tearDown(() async {
      await getIt.reset();
    });

    test('未配置模型或章节为空时早退，不发起翻译', () async {
      vm.currentContent.value = '<p>有内容</p>';
      await vm.translateCurrentChapter(); // model null → 早退
      expect(ollama.calls, isEmpty);

      vm.translationModel.value = 'test-model';
      vm.currentContent.value = ''; // 内容为空 → 早退
      await vm.translateCurrentChapter();
      expect(ollama.calls, isEmpty);
      expect(vm.isTranslating.value, isFalse);
    });

    test('整章翻译：标签包装被清洗，原文标记写入翻译单元的父元素', () async {
      vm.translationModel.value = 'test-model';
      vm.currentContent.value = '<p>Hello there</p><p>Second part</p><p>Third</p>';
      ollama.responses
        ..['Hello there'] = '<target>你好，世界</target>\n'
        ..['Second part'] = '<result>  第二话  </result>' // 包装+内部空白都被剥掉
        ..['Third'] = 'keep <target>x</target> tail'; // 非整体包装（未锚定）→ 原样保留

      await vm.translateCurrentChapter();

      expect(vm.isTranslating.value, isFalse);
      expect(vm.translationTotal.value, 3);
      expect(vm.translationProgress.value, 3);
      expect(vm.failedTranslations, isEmpty);
      expect(vm.currentContent.value, contains('你好，世界'));
      expect(vm.currentContent.value, contains('第二话'));
      // 未清洗掉的包装作为纯文本写回，序列化时被 HTML 转义
      expect(vm.currentContent.value, contains('keep &lt;target&gt;x&lt;/target&gt; tail'));
      // 清洗结果不应残留有效包装标签
      expect(vm.currentContent.value, isNot(contains('<target>你好')));
      expect(vm.currentContent.value, isNot(contains('<translation>')));
      expect(vm.currentContent.value, isNot(contains('<result>')));
      // 重试标记打在翻译单元的父元素上（<p> 本身就是单元时，宿主是 body），
      // 多次翻译会互相覆盖属性值 —— 这里只锁定"属性存在且带转义原文"
      expect(vm.currentContent.value, contains('data-original-text='));
      expect(vm.currentContent.value, contains('data-translated="true"'));
    });

    test('单段翻译失败：保留原文并记入 failedTranslations', () async {
      vm.translationModel.value = 'test-model';
      vm.currentContent.value = '<p>坏段落</p>';
      ollama.failOn.add('坏段落');

      await vm.translateCurrentChapter();

      expect(vm.failedTranslations, ['坏段落']);
      expect(vm.currentContent.value, contains('坏段落'));
      expect(vm.isTranslating.value, isFalse);
      // 进度自增在成功分支内：失败段落不计进度
      expect(vm.translationProgress.value, 0);
      expect(vm.translationTotal.value, 1);
    });

    test('重试段落：反转义入参并命中原标记，译文原位替换', () async {
      vm.translationModel.value = 'test-model';
      vm.currentContent.value = '<p>Retry me</p>';
      ollama.responses['Retry me'] = '<target>首次译文</target>';
      await vm.translateCurrentChapter();
      expect(vm.currentContent.value, contains('首次译文'));

      // 换响应后走 handleRetryFromHtml（入参是 HTML 属性里的转义形态）
      ollama.responses['Retry me'] = '<result>重译成功</result>';
      await vm.handleRetryFromHtml('Retry me');
      expect(vm.currentContent.value, contains('重译成功'));
      expect(vm.currentContent.value, isNot(contains('首次译文')));
      expect(vm.currentContent.value, isNot(contains('<result>')));
      expect(ollama.calls.where((t) => t == 'Retry me').length, 2); // 首轮 + 重试
    });

    test('重试守卫：未翻译过（无原文快照）时不发请求', () async {
      vm.translationModel.value = 'test-model';
      await vm.retryTranslateParagraph('无快照');
      expect(ollama.calls, isEmpty);
    });

    test('retryAllFailedTranslations：失败段落从未被打标，批量重试清列表但换不回译文', () async {
      vm.translationModel.value = 'test-model';
      vm.currentContent.value = '<p>x</p>';
      ollama.failOn.add('x');
      await vm.translateCurrentChapter();
      expect(vm.failedTranslations, ['x']);

      // 失败发生在打标之前，文档里没有 data-original-text 可寻，
      // 重试调用翻译成功后仍会"找不到指定段落"，但列表被无条件清空 —— 锁定现有语义
      ollama.failOn.clear();
      ollama.responses['x'] = '<target>修好了</target>';
      await vm.retryAllFailedTranslations();
      expect(vm.failedTranslations, isEmpty);
      expect(vm.currentContent.value, isNot(contains('修好了')));
      expect(ollama.calls.where((t) => t == 'x').length, 2); // 首轮 + 批量重试各一次
    });
  });
}
