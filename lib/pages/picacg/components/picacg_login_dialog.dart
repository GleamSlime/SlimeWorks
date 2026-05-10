// PicACG 登录对话框组件

import 'package:flutter/material.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/picacg_service.dart';
import 'package:slime_works/core/theme/app_theme.dart';

/// 显示登录对话框
///
/// 返回 true 表示登录成功
Future<bool> showPicAcgLoginDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _PicAcgLoginDialog(),
  );
  return result ?? false;
}

class _PicAcgLoginDialog extends StatefulWidget {
  const _PicAcgLoginDialog();

  @override
  State<_PicAcgLoginDialog> createState() => _PicAcgLoginDialogState();
}

class _PicAcgLoginDialogState extends State<_PicAcgLoginDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _proxyController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    /// 加载已保存的代理与登录凭据
    _loadSavedInputs();
  }

  Future<void> _loadSavedInputs() async {
    final service = getIt<PicAcgService>();
    final proxy = await service.getSavedProxy();
    final credentials = await service.getSavedLoginCredentials();
    if (mounted) {
      _proxyController.text = proxy;
      _emailController.text = credentials['email'] ?? '';
      _passwordController.text = credentials['password'] ?? '';
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _proxyController.dispose();
    super.dispose();
  }

  Future<void> _onLogin() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final service = getIt<PicAcgService>();
      // 先更新代理配置
      final proxy = _proxyController.text.trim();
      await service.setProxy(proxy);

      // 执行登录
      await service.login(_emailController.text.trim(), _passwordController.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metrics = appMetrics;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(metrics.kSpace12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360, maxHeight: 520),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(metrics.kSpace16),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                /// 标题
                Row(
                  children: [
                    Text('PicACG 登录', style: theme.textTheme.titleLarge),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(false),
                      tooltip: '取消',
                    ),
                  ],
                ),
                SizedBox(height: metrics.kSpace12),

                /// 邮箱
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: '邮箱 / 账号',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: (v) => (v == null || v.trim().isEmpty) ? '请输入账号' : null,
                ),
                SizedBox(height: metrics.kSpace8),

                /// 密码
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: '密码',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.next,
                  validator: (v) => (v == null || v.isEmpty) ? '请输入密码' : null,
                ),
                SizedBox(height: metrics.kSpace8),

                /// 代理设置（可选）
                TextFormField(
                  controller: _proxyController,
                  decoration: const InputDecoration(
                    labelText: '代理地址（可选）',
                    hintText: '如: http://127.0.0.1:7890',
                    prefixIcon: Icon(Icons.router_outlined),
                  ),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _onLogin(),
                ),
                SizedBox(height: metrics.kSpace12),

                /// 错误信息
                if (_errorMessage != null) ...[
                  Container(
                    padding: EdgeInsets.all(AppTheme.metrics.kSpace8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error.withValues(alpha: 0.1),
                      borderRadius: AppTheme.metrics.radius8,
                    ),
                    child: Text(
                      _errorMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                  SizedBox(height: metrics.kSpace8),
                ],

                /// 登录按钮
                FilledButton(
                  onPressed: _isLoading ? null : _onLogin,
                  child: _isLoading
                      ? SizedBox(
                          height: AppTheme.metrics.kSpace20,
                          width: AppTheme.metrics.kSpace20,
                          child: const CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('登录'),
                ),
              ],
            ), // Column
          ), // Form
        ), // SingleChildScrollView
      ), // ConstrainedBox
    ); // Dialog
  }
}
