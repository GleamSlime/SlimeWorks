import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// GetX 生命周期绑定 Widget
/// 用于在使用 GoRouter 时保持 GetX 的依赖注入和生命周期管理
class BindingWidget extends StatefulWidget {
  final Widget child;
  final Bindings? binding;

  const BindingWidget({super.key, required this.child, this.binding});

  @override
  State<BindingWidget> createState() => _BindingWidgetState();
}

class _BindingWidgetState extends State<BindingWidget> {
  @override
  void initState() {
    super.initState();
    // 应用绑定
    widget.binding?.dependencies();
  }

  @override
  void dispose() {
    // GetX 会自动清理依赖
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
