import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/svg.dart';
import 'package:slime_works/components/dropdown/gooey_dropdown.dart';
import 'package:slime_works/components/window/desktop_head.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:slime_works/gen/assets.gen.dart';
import 'package:slime_works/pages/backup/demo.dart';
import 'package:slime_works/pages/collection/library/components/library_book_append.dart';
import 'package:slime_works/pages/demo/gooey_dropdown_demo_page.dart';
import 'package:get/get.dart';
import 'package:slime_works/view_models/novel_library_viewmodel.dart';

class CollectionLibraryScreen extends BasePage<NovelLibraryViewModel> {
  const CollectionLibraryScreen({super.key});

  @override
  State<CollectionLibraryScreen> createState() => _CollectionLibraryScreenState();
}

class _CollectionLibraryScreenState
    extends BasePageState<NovelLibraryViewModel, CollectionLibraryScreen> {
  DesktopScreenProvider desktopScreen = getIt<DesktopScreenProvider>();

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ThemeData theme = Theme.of(context);

      desktopScreen.setScreenHeadToolsWidget(
        Row(
          spacing: AppTheme.metrics.fontSize8,
          children: [
            // DesktopHeadToolsButton(
            //   icon: const Icon(Icons.refresh),
            //   size: AppTheme.metrics.fontSize34,
            //   onTap: () {
            //     // Implement refresh functionality here
            //   },
            // ),
            // Container(
            //   padding: EdgeInsets.all(AppTheme.metrics.kSpace4),

            //   decoration: BoxDecoration(
            //     color: theme.colorScheme.surface,
            //     borderRadius: BorderRadius.circular(AppTheme.metrics.kSpace32),
            //     boxShadow: [BoxShadow(color: theme.shadowColor.withAlpha(25), blurRadius: scaleW(10))],
            //     border: Border.all(width: 1.w, color: AppTheme.isLight(context) ? Colors.white : Color(0xFF333333).withAlpha((255 * 0.9).toInt())),
            //   ),
            //   child: LibraryBookAppendButton(),
            // ),
            LibraryBookAppendButton(),
            // GooeyDropdown(dropdownWidth: 260, dropdownHeight: 320, dropdown: YourDropdownContent(), child: Icon(Icons.menu)),
          ],
        ),
      );
    });
    super.initState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      desktopScreen.setScreenHeadToolsWidget(null);
    });
    super.dispose();
  }

  // ==================== ViewModel ====================
  /// 创建页面对应的 ViewModel（页面关闭销毁）
  @override
  NovelLibraryViewModel createViewModel() => NovelLibraryViewModel();

  /// 长期存在的模型（即便页面关闭也不会销毁）
  late final NovelLibraryViewModel longLivedViewModel = Get.put(
    NovelLibraryViewModel(),
    permanent: true,
  );

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
