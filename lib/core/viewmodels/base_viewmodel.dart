/// 基础 ViewModel
///
/// 所有 ViewModel 应继承此类，提供统一的生命周期管理和状态管理

import 'package:flutter/foundation.dart';

abstract class BaseViewModel extends ChangeNotifier {
  bool _isDisposed = false;
  bool _isInitialized = false;

  /// 是否已初始化
  bool get isInitialized => _isInitialized;

  /// 初始化（在 State.initState 中调用）
  Future<void> onInit() async {
    _isInitialized = true;
  }

  /// 销毁（在 State.dispose 中调用）
  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  /// 安全地通知监听器（检查是否已销毁）
  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  /// 显示加载状态
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  /// 错误信息
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  void setError(String? error) {
    _errorMessage = error;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
