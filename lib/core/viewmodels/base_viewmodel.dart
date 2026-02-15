/// 基础 ViewModel
///
/// 所有 ViewModel 应继承此类，提供统一的生命周期管理和状态管理
///
/// 使用方式：
/// 1. 随页面销毁：在 createViewModel() 中直接返回实例
/// 2. 长期存在（即使页面销毁数据仍保留）：使用 Get.put() 并设置 permanent: true
///
/// 示例：
/// ```dart
/// // 方式1：随页面销毁
/// @override
/// MyViewModel createViewModel() => MyViewModel();
///
/// // 方式2：长期存在
/// late final MyViewModel longLivedViewModel = Get.put(
///   MyViewModel(),
///   permanent: true,
/// );
/// ```
library;

import 'package:get/get.dart';

/// 基于 GetX 的基础 ViewModel
///
/// 所有 ViewModel 应继承此类，提供统一的生命周期管理和状态管理
abstract class BaseViewModel extends GetxController {
  bool _isInitialized = false;

  /// 是否已初始化
  bool get isInitialized => _isInitialized;

  /// 异步初始化（供页面在需要时 await）
  Future<void> onInitAsync() async {
    _isInitialized = true;
  }

  /// 当控制器被关闭时调用
  @override
  void onClose() {
    super.onClose();
  }

  /// 显示加载状态
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  void setLoading(bool loading) {
    _isLoading = loading;
    update();
  }

  /// 错误信息
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  void setError(String? error) {
    _errorMessage = error;
    update();
  }

  void clearError() {
    _errorMessage = null;
    update();
  }
}
