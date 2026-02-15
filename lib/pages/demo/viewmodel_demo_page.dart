import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/view_models/demo_screen_viewmodel.dart';

class ViewModelDemoScreenPage extends BasePage<DemoScreenViewModel> {
  const ViewModelDemoScreenPage({super.key});

  @override
  State<ViewModelDemoScreenPage> createState() => _ViewModelDemoScreenPageState();
}

class _ViewModelDemoScreenPageState
    extends BasePageState<DemoScreenViewModel, ViewModelDemoScreenPage> {
  // ==================== 配置 ====================
  /// 是否启用网络状态监听（启用后网络重连时会自动调用 fetchData）
  @override
  bool get enableNetworkMonitoring => true; // 设置为 true 以启用网络监听

  /// 页面 ViewModel 的唯一标识（保留 null 以使用默认实例管理）
  @override
  String? get viewModelTag => null;

  // ==================== ViewModel ====================
  /// 创建页面对应的 ViewModel（页面关闭销毁）
  @override
  DemoScreenViewModel createViewModel() => DemoScreenViewModel();

  /// 长期存在的模型（即便页面关闭也不会销毁）
  static const String _longLivedTag = 'DemoScreen_longLived';
  late final DemoScreenViewModel longLivedViewModel = Get.put(
    DemoScreenViewModel(),
    tag: _longLivedTag,
    permanent: true,
  );

  // ==================== 数据请求生命周期 ====================
  /// 请求或获取数据（会在页面初始化和网络重连时调用）
  @override
  Future<void> fetchData() async {
    // await viewModel.loadData();
    if (kDebugMode) {
      print('[fetchData] 重新获取数据... 时间: ${DateTime.now()}');
    }
  }

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

        Text(
          '长期存在的模型计数：${longLivedViewModel.a}',
          style: TextStyle(fontSize: AppTheme.metrics.fontSize16),
        ),
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
