import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/node/node_models.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/services/ollama/ollama_models.dart';
import 'package:slime_works/core/services/ollama/ollama_service.dart';
import 'package:slime_works/core/services/ollama/ollama_settings_service.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/mock/mock_mode.dart';
import 'package:slime_works/pages/collection/library/components/library_book_append.dart';
import 'package:slime_works/pages/collection/library/components/library_import_progress.dart';
import 'package:slime_works/view_models/novel_library_viewmodel.dart';

class _StubNodeSettingsService extends NodeSettingsService {
  @override
  NodeEndpoint? get activeNode => null;

  @override
  bool get isRemoteMode => false;
}

class _StubOllamaSettingsService extends OllamaSettingsService {
  _StubOllamaSettingsService(super.ollama);

  @override
  Future<void> init() async {}

  @override
  Future<List<OllamaModelOption>> getModelOptions() async => [];
}

class _ControlledOllamaService extends OllamaService {
  final Completer<String> firstResponse = Completer<String>();
  final Completer<void> started = Completer<void>();
  int calls = 0;

  @override
  Future<String> generateStructured({
    required OllamaModelOption model,
    required String systemPrompt,
    required String userPrompt,
    CancelToken? cancelToken,
  }) async {
    calls++;
    if (!started.isCompleted) started.complete();
    if (calls == 1) return firstResponse.future;
    return '{"genres":["科幻"],"explicit_content":false,"confidence":0.9}';
  }
}

class _FakeFilePicker extends FilePicker {
  String? directoryPath;
  List<PlatformFile> files = <PlatformFile>[];

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
  }) async => directoryPath;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => FilePickerResult(files);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NovelLibraryViewModel viewModel;
  late Directory scanDirectory;
  late _FakeFilePicker filePicker;
  late _ControlledOllamaService ollama;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await getIt.reset();
    ollama = _ControlledOllamaService();
    getIt.registerSingleton<NodeSettingsService>(_StubNodeSettingsService());
    getIt.registerSingleton<OllamaService>(ollama);
    getIt.registerSingleton<OllamaSettingsService>(
      _StubOllamaSettingsService(ollama),
    );
    scanDirectory = Directory.systemTemp.createTempSync('novel_import_entry');
    filePicker = _FakeFilePicker()..directoryPath = scanDirectory.path;
    FilePicker.platform = filePicker;
    await MockMode.setRuntimeEnabled(true);
    viewModel = NovelLibraryViewModel();
  });

  tearDown(() async {
    await MockMode.setRuntimeEnabled(false);
    await getIt.reset();
    scanDirectory.deleteSync(recursive: true);
  });

  test('拖入文件夹会触发扫描，而不是按文件后缀静默丢弃', () async {
    await viewModel.addDroppedFiles(<String>[scanDirectory.path]);

    expect(
      viewModel.novels.map((novel) => novel.filePath),
      contains('${scanDirectory.path}/演示书籍.epub'),
    );
  });

  test('未选择模型时仍应用关键词自动标签', () async {
    viewModel.keywordRules.add(<String, String>{
      'keyword': '列车',
      'tag': '关键词命中',
    });

    await viewModel.scanFolder(localFolderPath: scanDirectory.path);

    final imported = viewModel.novels.firstWhere(
      (novel) => novel.filePath == '${scanDirectory.path}/演示书籍.epub',
    );
    expect(imported.tags, contains('关键词命中'));
    expect(imported.tags, isNot(contains('科幻')));
  });

  testWidgets('选择模型后显示 AI 样本进度并跳过关键词标签', (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    viewModel.keywordRules.add(<String, String>{
      'keyword': '列车',
      'tag': '关键词命中',
    });

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(1000, 800),
        builder: (context, child) => MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Column(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: LibraryBookAppendButton(viewModel: viewModel),
                ),
                LibraryImportProgressBanner(viewModel: viewModel),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final model = OllamaModelOption(
      model: OllamaModel(name: 'test-model'),
      server: OllamaServer(url: 'http://127.0.0.1:11434'),
    );
    late Future<void> scanning;
    await tester.runAsync(() async {
      scanning = viewModel.scanFolder(
        localFolderPath: scanDirectory.path,
        detectionModel: model,
      );
      await ollama.started.future;
    });
    await tester.pump();

    expect(ollama.calls, 1);
    expect(viewModel.isDetecting.value, isTrue);
    expect(viewModel.detectionSampleTotal.value, 3);
    final banner = find.byKey(const ValueKey('novel-import-progress'));
    expect(banner, findsOneWidget);
    expect(
      find.descendant(of: banner, matching: find.textContaining('AI 正在解析')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: banner, matching: find.textContaining('样本 0/3')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0,
    );

    ollama.firstResponse.complete(
      '{"genres":["科幻"],"explicit_content":false,"confidence":0.9}',
    );
    await tester.pump();
    await tester.runAsync(() => scanning);
    await tester.pump();

    expect(viewModel.isDetecting.value, isFalse);
    expect(banner, findsNothing);
    final imported = viewModel.novels.firstWhere(
      (novel) => novel.filePath == '${scanDirectory.path}/演示书籍.epub',
    );
    expect(imported.tags, contains('科幻'));
    expect(imported.tags, isNot(contains('关键词命中')));
  });

  testWidgets('单文件导入也显示 AI 进度并跳过关键词标签', (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const path = '/mock/novels/单本.epub';
    filePicker.files = <PlatformFile>[
      PlatformFile(name: '单本.epub', path: path, size: 1024),
    ];
    viewModel.keywordRules.add(<String, String>{
      'keyword': '列车',
      'tag': '关键词命中',
    });

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(1000, 800),
        builder: (context, child) => MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: LibraryImportProgressBanner(viewModel: viewModel),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final model = OllamaModelOption(
      model: OllamaModel(name: 'test-model'),
      server: OllamaServer(url: 'http://127.0.0.1:11434'),
    );
    late Future<void> importing;
    await tester.runAsync(() async {
      importing = viewModel.addSingleNovel(detectionModel: model);
      await ollama.started.future;
    });
    await tester.pump();

    expect(viewModel.isDetecting.value, isTrue);
    expect(find.textContaining('AI 正在解析'), findsOneWidget);
    expect(find.textContaining('样本 0/3'), findsOneWidget);

    ollama.firstResponse.complete(
      '{"genres":["科幻"],"explicit_content":false,"confidence":0.9}',
    );
    await tester.pump();
    await tester.runAsync(() => importing);
    await tester.pump();

    expect(viewModel.isDetecting.value, isFalse);
    expect(viewModel.isScanning.value, isFalse);
    expect(find.byKey(const ValueKey('novel-import-progress')), findsNothing);
    final imported = viewModel.novels.firstWhere(
      (novel) => novel.filePath == path,
    );
    expect(imported.tags, contains('科幻'));
    expect(imported.tags, isNot(contains('关键词命中')));
  });

  testWidgets('顶部导入菜单的扫描文件夹入口能打开导入对话框', (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(1000, 800),
        builder: (context, child) => MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: LibraryBookAppendButton(viewModel: viewModel),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('导入').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('扫描文件夹'), findsWidgets);

    await tester.tap(find.text('扫描文件夹').hitTestable());
    await tester.pumpAndSettle();

    expect(find.text('扫描小说文件夹'), findsOneWidget);

    await tester.tap(find.text('选择文件夹'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(
      viewModel.novels.map((novel) => novel.filePath),
      contains('${scanDirectory.path}/演示书籍.epub'),
    );
  });
}
