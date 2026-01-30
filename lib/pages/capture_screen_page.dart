import 'package:flutter/material.dart';
import 'package:slime_works/core/index.dart';
import '../viewmodels/capture_screen_viewmodel.dart';

class CaptureScreenPage extends BasePage<CaptureScreenViewModel> {
  const CaptureScreenPage({super.key});

  @override
  State<CaptureScreenPage> createState() => _CaptureScreenPageState();
}

class _CaptureScreenPageState extends BasePageState<CaptureScreenViewModel, CaptureScreenPage> {
  // ==================== UI 配置 ====================
  @override
  String get title => 'Capture Screen';

  // ==================== ViewModel ====================
  @override
  CaptureScreenViewModel createViewModel() => CaptureScreenViewModel();

  // ==================== UI 构建 ====================
  @override
  Widget buildContent(BuildContext context) {
    return const Center(
      child: Text('CaptureScreenPage'),
    );
  }
}
