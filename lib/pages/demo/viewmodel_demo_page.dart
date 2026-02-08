import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/view_models/demo_screen_viewmodel.dart';

class ViewModelDemoScreenPage extends BasePage<DemoScreenViewModel> {
  const ViewModelDemoScreenPage({super.key});

  @override
  State<ViewModelDemoScreenPage> createState() => _ViewModelDemoScreenPageState();
}

class _ViewModelDemoScreenPageState extends BasePageState<DemoScreenViewModel, ViewModelDemoScreenPage> {
  // ==================== ViewModel ====================
  /// 创建页面对应的 ViewModel（页面关闭销毁）
  @override
  DemoScreenViewModel createViewModel() => DemoScreenViewModel();

  /// 长期存在的模型（即便页面关闭也不会销毁）
  late final DemoScreenViewModel longLivedViewModel = Get.put(DemoScreenViewModel());

  // ==================== UI 构建 ====================
  @override
  Widget buildContent(BuildContext context) {
    return Column(
      children: [
        Text('当前计数：${viewModel.a}', style: TextStyle(fontSize: AppTheme.metrics.fontSize16)),
        SizedBox(height: AppTheme.metrics.kSpace8),
        ElevatedButton(
          onPressed: () {
            viewModel.add();
          },
          child: const Text('增加计数'),
        ),

        Divider(height: AppTheme.metrics.kSpace32),

        Text('长期存在的模型计数：${longLivedViewModel.a}', style: TextStyle(fontSize: AppTheme.metrics.fontSize16)),
        SizedBox(height: AppTheme.metrics.kSpace8),
        ElevatedButton(
          onPressed: () {
            longLivedViewModel.add();
            setState(() {}); // 手动刷新 UI
          },
          child: const Text('增加长期模型计数'),
        ),
      ],
    );
  }
}
