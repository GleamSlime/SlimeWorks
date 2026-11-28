import 'dart:io';

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
import 'package:slime_works/view_models/novel_library_viewmodel.dart';

class _StubNodeSettingsService extends NodeSettingsService {
  @override
  NodeEndpoint? get activeNode => null;

  @override
  bool get isRemoteMode => false;
}

class _StubOllamaSettingsService extends OllamaSettingsService {
  _StubOllamaSettingsService() : super(OllamaService());

  @override
  Future<void> init() async {}

  @override
  Future<List<OllamaModelOption>> getModelOptions() async => [];
}

class _FakeFilePicker extends FilePicker {
  String? directoryPath;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
  }) async => directoryPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NovelLibraryViewModel viewModel;
  late Directory scanDirectory;
  late _FakeFilePicker filePicker;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await getIt.reset();
    getIt.registerSingleton<NodeSettingsService>(_StubNodeSettingsService());
    getIt.registerSingleton<OllamaSettingsService>(
      _StubOllamaSettingsService(),
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
