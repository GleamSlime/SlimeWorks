import 'package:flutter/material.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/view_models/capture_screen_viewmodel.dart';

class CaptureScreen extends BasePage<CaptureScreenViewModel> {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends BasePageState<CaptureScreenViewModel, CaptureScreen> {
  // ==================== UI 配置 ====================
  @override
  String get title => 'Capture Screen';

  // ==================== ViewModel ====================
  @override
  CaptureScreenViewModel createViewModel() => CaptureScreenViewModel();

  // ==================== UI 构建 ====================
  @override
  Widget buildContent(BuildContext context) {
    return const Center(child: Text('CaptureScreen'));
  }
}
