// Manga 登录对话框组件

import 'package:flutter/material.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/manga_service.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';

/// 显示登录对话框
///
/// 返回 true 表示登录成功
Future<bool> showMangaLoginDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _MangaLoginDialog(),
  );
  return result ?? false;
}

class _MangaLoginDialog extends StatefulWidget {
  const _MangaLoginDialog();

  @override
  State<_MangaLoginDialog> createState() => _MangaLoginDialogState();
}

class _MangaLoginDialogState extends State<_MangaLoginDialog> {
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
    final service = getIt<MangaService>();
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
      final service = getIt<MangaService>();
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
    final s = AppSemantic.of(context);
    final metrics = appMetrics;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: metrics.radiusOverlay),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: scaleW(380), maxHeight: scaleH(540)),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(metrics.kSpace20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: metrics.kSpace40,
                      height: metrics.kSpace40,
                      decoration: BoxDecoration(
                        color: s.accentContainer,
                        borderRadius: metrics.radius10,
                      ),
                      child: DrawIcon(StrokeIcons.autoStories,
                        // 图标装在固定 40×40 的方格里，尺寸必须走宽度族，
                        // 否则字号滑杆一拉图标就顶出方格。
                        size: scaleW(22),
                        color: s.accent,
                      ),
                    ),
                    SizedBox(width: metrics.kSpace12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Manga 登录', style: AppTextStyles.sectionTitle(context)),
                          SizedBox(height: metrics.kSpace2),
                          Text(
                            '登录后即可浏览和收藏漫画',
                            style: AppTextStyles.caption(context),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: DrawIcon(StrokeIcons.close),
                      onPressed: () => Navigator.of(context).pop(false),
                      tooltip: '取消',
                    ),
                  ],
                ),
                SizedBox(height: metrics.kSpace20),

                TextFormField(
                  controller: _emailController,
                  style: AppTheme.fieldTextStyle,
                  decoration: const InputDecoration(
                    labelText: '邮箱 / 账号',
                    prefixIcon: DrawIcon(StrokeIcons.personOutline),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: (v) => (v == null || v.trim().isEmpty) ? '请输入账号' : null,
                ),
                SizedBox(height: metrics.kSpace10),

                TextFormField(
                  controller: _passwordController,
                  style: AppTheme.fieldTextStyle,
                  decoration: InputDecoration(
                    labelText: '密码',
                    prefixIcon: DrawIcon(StrokeIcons.lockOutline),
                    suffixIcon: IconButton(
                      icon: DrawIcon(_obscurePassword ? StrokeIcons.visibilityOff : StrokeIcons.visibility),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.next,
                  validator: (v) => (v == null || v.isEmpty) ? '请输入密码' : null,
                ),
                SizedBox(height: metrics.kSpace10),

                TextFormField(
                  controller: _proxyController,
                  style: AppTheme.fieldTextStyle,
                  decoration: const InputDecoration(
                    labelText: '代理地址（可选）',
                    hintText: '如: http://127.0.0.1:7890',
                    prefixIcon: DrawIcon(StrokeIcons.router),
                  ),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _onLogin(),
                ),
                SizedBox(height: metrics.kSpace16),

                if (_errorMessage != null) ...[
                  Container(
                    padding: EdgeInsets.all(AppTheme.metrics.kSpace10),
                    decoration: BoxDecoration(
                      color: s.danger.container,
                      borderRadius: AppTheme.metrics.radius8,
                      border: Border.all(
                        color: s.danger.containerBorder,
                        width: scaleW(1),
                      ),
                    ),
                    child: Row(
                      children: [
                        DrawIcon(StrokeIcons.errorOutline, size: AppTheme.metrics.iconSize16, color: s.danger.color),
                        SizedBox(width: AppTheme.metrics.kSpace8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: AppTextStyles.caption(context).copyWith(color: s.danger.color),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: metrics.kSpace12),
                ],

                FilledButton(
                  onPressed: _isLoading ? null : _onLogin,
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: metrics.kSpace14),
                    shape: RoundedRectangleBorder(borderRadius: metrics.radius10),
                  ),
                  child: _isLoading
                      ? SizedBox(
                          height: AppTheme.metrics.kSpace20,
                          width: AppTheme.metrics.kSpace20,
                          child: CircularProgressIndicator(strokeWidth: scaleW(2)),
                        )
                      : const Text('登录'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
