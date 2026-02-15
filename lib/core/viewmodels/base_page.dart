library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
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

  /// ViewModel 的唯一标识（可选，用于避免同类型实例冲突）
  String? get viewModelTag => null;

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _wasConnected = true;

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
    // 默认调用 ViewModel 的异步初始化
    await viewModel.onInitAsync();
  }

  /// 请求或获取数据的生命周期方法
  ///
  /// 此方法会在以下情况下被调用：
  /// 1. 页面初始化时（如果 onPageInit 中调用）
  /// 2. 网络重连时（如果启用了 enableNetworkMonitoring）
  /// 3. 手动调用刷新时
  ///
  /// 子类应该覆盖此方法来实现具体的数据获取逻辑
  Future<void> fetchData() async {
    // 默认实现为空，子类可根据需要覆盖
  }

  /// 网络重连时调用（可选覆盖）
  ///
  /// 默认行为：调用 fetchData() 重新获取数据
  Future<void> onNetworkReconnected() async {
    // 网络恢复时重新获取数据
    await fetchData();
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
            Text(
              errorMessage,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _retryInitialization,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
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

    // 如果启用网络监听，添加网络状态监听
    if (enableNetworkMonitoring) {
      _startNetworkMonitoring();
    }
  }

  /// 开始网络状态监听
  void _startNetworkMonitoring() async {
    try {
      final initial = await _connectivity.checkConnectivity();
      _wasConnected = _isConnected(initial);
      if (kDebugMode) {
        print('[网络监听] 初始网络状态: ${initial.map((e) => e.name).join(", ")} | 已连接: $_wasConnected');
      }
    } catch (e) {
      _wasConnected = true;
      if (kDebugMode) {
        print('[网络监听] 获取初始状态失败: $e');
      }
    }

    _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {
      final isConnected = _isConnected(results);
      if (kDebugMode) {
        print(
          '[网络监听] 网络状态变化: ${results.map((e) => e.name).join(", ")} | 已连接: $isConnected | 之前状态: $_wasConnected',
        );
      }

      if (!_wasConnected && isConnected) {
        // 从断网恢复到连网
        _wasConnected = true;
        if (kDebugMode) {
          print('[网络监听] 检测到网络恢复，触发 onNetworkReconnected()');
        }
        if (mounted) {
          onNetworkReconnected();
        }
      } else if (_wasConnected && !isConnected) {
        // 从连网变为断网
        _wasConnected = false;
        if (kDebugMode) {
          print('[网络监听] 检测到网络断开');
        }
      }
    });

    if (kDebugMode) {
      print('[网络监听] 已启用：根据设备网络状态触发数据刷新');
    }
  }

  bool _isConnected(List<ConnectivityResult> results) {
    return results.any((result) => result != ConnectivityResult.none);
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _connectivitySub = null;

    // 触发 GetxController 的关闭回调
    try {
      if (viewModelTag != null) {
        Get.delete<VM>(tag: viewModelTag, force: true);
      } else {
        viewModel.onClose();
      }
    } catch (_) {}
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
    return GetBuilder<VM>(
      tag: viewModelTag,
      init: viewModel,
      builder: (_) {
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
