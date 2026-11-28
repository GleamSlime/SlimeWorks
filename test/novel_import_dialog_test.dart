import 'package:material_ui/material_ui.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/ollama/ollama_models.dart';
import 'package:slime_works/core/services/ollama/ollama_service.dart';
import 'package:slime_works/core/services/ollama/ollama_settings_service.dart';
import 'package:slime_works/pages/collection/library/components/library_book_import_dialog.dart';

class _SettingsStub extends OllamaSettingsService {
  _SettingsStub() : super(OllamaService());

  List<OllamaModelOption> options = <OllamaModelOption>[];
  Object? error;

  @override
  Future<void> init() async {}

  @override
  Future<List<OllamaModelOption>> getModelOptions() async {
    if (error != null) throw error!;
    return options;
  }
}

void main() {
  late _SettingsStub settings;

  setUp(() {
    settings = _SettingsStub();
    getIt.registerSingleton<OllamaSettingsService>(settings);
  });

  tearDown(() async {
    await getIt.reset();
  });

  Future<void> open(
    WidgetTester tester, {
    bool scanFolder = false,
    void Function(NovelImportDialogResult?)? onResult,
    bool supportsDirectoryStructure = true,
  }) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(1000, 800),
        builder: (context, child) => MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final result = await showNovelImportDialog(
                  context: context,
                  scanFolder: scanFolder,
                  supportsDirectoryStructure: supportsDirectoryStructure,
                );
                onResult?.call(result);
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  testWidgets('展示所有服务器模型并允许不检测直接导入', (tester) async {
    settings.options = <OllamaModelOption>[
      OllamaModelOption(
        model: OllamaModel(name: 'model-a'),
        server: OllamaServer(url: 'http://host-a:11434'),
      ),
      OllamaModelOption(
        model: OllamaModel(name: 'model-b'),
        server: OllamaServer(url: 'http://host-b:11434'),
      ),
    ];

    await open(tester);

    expect(find.text('请选择大模型'), findsOneWidget);
    expect(find.text('未选择模型：仅导入书籍，不执行 AI 检测。'), findsOneWidget);
    await tester.tap(find.text('使用大模型检测书籍（可选）'));
    await tester.pumpAndSettle();
    expect(find.text('model-a (host-a)'), findsOneWidget);
    expect(find.text('model-b (host-b)'), findsOneWidget);
    await tester.tap(find.text('model-a (host-a)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('将使用 model-a'), findsOneWidget);
  });

  testWidgets('扫描文件夹时默认按原目录归档且可关闭', (tester) async {
    NovelImportDialogResult? result;
    await open(tester, scanFolder: true, onResult: (value) => result = value);
    expect(find.text('按原目录创建文件夹'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    await tester.tap(find.text('按原目录创建文件夹'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择文件夹'));
    await tester.pumpAndSettle();
    expect(result?.preserveDirectoryStructure, isFalse);
  });

  testWidgets('本机移动端不展示无法保留的目录结构选项', (tester) async {
    await open(tester, scanFolder: true, supportsDirectoryStructure: false);
    expect(find.text('按原目录创建文件夹'), findsNothing);
  });

  testWidgets('模型读取失败时仍可继续普通导入', (tester) async {
    settings.error = Exception('离线');

    await open(tester, scanFolder: true);

    expect(find.textContaining('模型读取失败'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '选择文件夹'))
          .onPressed,
      isNotNull,
    );
    expect(find.text('取消'), findsOneWidget);
  });
}
