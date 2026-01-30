/// 基础页面
///
/// 所有页面应继承此类，提供统一的页面结构和 ViewModel 管理

import 'package:flutter/material.dart';
import 'base_viewmodel.dart';

/// 基础页面（StatefulWidget）
abstract class BasePage<VM extends BaseViewModel> extends StatefulWidget {
  const BasePage({super.key});
}

/// 页面初始化状态
enum PageInitState {
  /// 初始化中
  loading,

  /// 初始化成功
  success,

  /// 初始化失败
  error,
}

/// 基础页面状态
abstract class BasePageState<VM extends BaseViewModel, T extends BasePage<VM>> extends State<T> {
  late VM viewModel;

  /// 当前页面标题（支持动态更新）
  String? _currentTitle;

  /// 页面初始化状态
  PageInitState _pageInitState = PageInitState.loading;

  /// 初始化错误信息
  String? _initErrorMessage;

  /// 页面标题（可选，可被 setTitle 覆盖）
  String? get title => null;

  /// 是否显示 AppBar
  bool get showAppBar => true;

  /// 是否在初始化失败时显示错误页面
  bool get showErrorPageOnInitFailed => true;

  /// 是否启用网络状态监听和自动重连
  bool get enableNetworkMonitoring => false;

  /// 创建 ViewModel（子类必须实现）
  VM createViewModel();

  /// 构建页面内容（子类必须实现）
  Widget buildContent(BuildContext context);

  /// 页面初始化（可选覆盖，用于加载初始数据）
  Future<void> onPageInit() async {
    // 默认调用 ViewModel 的 onInit
    await viewModel.onInit();
  }

  /// 网络重连时调用（可选覆盖）
  Future<void> onNetworkReconnected() async {
    // 默认重新初始化页面
    await _initializePage();
  }

  /// 动态设置标题
  void setTitle(String? newTitle) {
    if (mounted) {
      setState(() {
        _currentTitle = newTitle;
      });
    }
  }

  /// 获取当前显示的标题
  String? get currentTitle => _currentTitle ?? title;

  /// 构建 AppBar（可选覆盖）
  PreferredSizeWidget? buildAppBar(BuildContext context) {
    if (!showAppBar) return null;
    final displayTitle = currentTitle;
    if (displayTitle == null) return null;

    return AppBar(title: Text(displayTitle));
  }

  /// 构建错误页面（可选覆盖）
  Widget buildErrorPage(BuildContext context, String errorMessage) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('页面加载失败', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(errorMessage, style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(onPressed: _retryInitialization, icon: const Icon(Icons.refresh), label: const Text('重试')),
          ],
        ),
      ),
    );
  }

  /// 初始化页面
  Future<void> _initializePage() async {
    if (!mounted) return;

    setState(() {
      _pageInitState = PageInitState.loading;
      _initErrorMessage = null;
    });

    try {
      await onPageInit();
      if (mounted) {
        setState(() {
          _pageInitState = PageInitState.success;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _pageInitState = PageInitState.error;
          _initErrorMessage = e.toString();
        });
      }
    }
  }

  /// 重试初始化
  Future<void> _retryInitialization() async {
    await _initializePage();
  }

  @override
  void initState() {
    super.initState();
    viewModel = createViewModel();

    // 异步初始化页面
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializePage();
    });

    // TODO: 如果启用网络监听，可以在这里添加网络状态监听
    // if (enableNetworkMonitoring) {
    //   _startNetworkMonitoring();
    // }
  }

  @override
  void dispose() {
    viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: buildAppBar(context), body: _buildBody(context));
  }

  /// 构建页面主体
  Widget _buildBody(BuildContext context) {
    // 显示初始化错误页面
    if (_pageInitState == PageInitState.error && showErrorPageOnInitFailed) {
      return buildErrorPage(context, _initErrorMessage ?? '未知错误');
    }

    // 显示初始化加载状态
    if (_pageInitState == PageInitState.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    // 初始化成功，显示正常内容
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, child) {
        // 显示 ViewModel 的错误信息（通过 SnackBar）
        if (viewModel.errorMessage != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(viewModel.errorMessage!),
                  action: SnackBarAction(
                    label: '关闭',
                    onPressed: () {
                      viewModel.clearError();
                    },
                  ),
                ),
              );
              viewModel.clearError();
            }
          });
        }

        // 显示 ViewModel 的加载状态（遮罩层）
        if (viewModel.isLoading) {
          return Stack(
            children: [
              buildContent(context),
              Container(
                color: Colors.black.withOpacity(0.3),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ],
          );
        }

        return buildContent(context);
      },
    );
  }
}
