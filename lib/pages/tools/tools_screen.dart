import 'package:flutter/material.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/pages/tools/components/extract_card.dart';
import 'package:slime_works/pages/tools/components/sentry_log_card.dart';

class ToolsScreen extends StatefulWidget {
  const ToolsScreen({super.key});

  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends State<ToolsScreen> {
  @override
  Widget build(BuildContext context) {
    return ScreenChrome(
      data: ScreenChromeData(title: '工具'),
      child: SingleChildScrollView(
        padding: EdgeInsets.all(AppTheme.metrics.kSpace24),
        child: Wrap(
          spacing: AppTheme.metrics.kSpace16,
          runSpacing: AppTheme.metrics.kSpace16,
          children: const [ExtractCard(), SentryLogCard()],
        ),
      ),
    );
  }
}
