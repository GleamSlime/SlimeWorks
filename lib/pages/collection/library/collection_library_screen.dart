import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:slime_works/components/window/desktop_head.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:slime_works/pages/collection/library/components/library_book_append.dart';
import 'package:slime_works/pages/collection/library/components/library_book_card.dart';
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
      desktopScreen.setScreenHeadToolsWidget(
        Row(
          spacing: AppTheme.metrics.fontSize8,
          children: [
            // 重置书籍库（清空所有书籍）
            DesktopHeadToolsButton(
              icon: const Icon(Icons.refresh),
              size: AppTheme.metrics.kSpace40,
              onTap: viewModel.confirmClearAllNovels,
            ),
            // 新增文件夹
            DesktopHeadToolsButton(
              icon: const Icon(Icons.create_new_folder),
              size: AppTheme.metrics.kSpace40,
              onTap: viewModel.createFolder,
            ),
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
            LibraryBookAppendButton(viewModel: viewModel),
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

  @override
  NovelLibraryViewModel createViewModel() => NovelLibraryViewModel();

  late final NovelLibraryViewModel longLivedViewModel = Get.put(
    NovelLibraryViewModel(),
    permanent: true,
  );

  @override
  Widget buildContent(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Obx(() {
            final displayNovels = viewModel.filteredNovels;

            return GridView.builder(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: scaleW(200),
                childAspectRatio: 0.65,
                mainAxisSpacing: AppTheme.metrics.kSpace12,
                crossAxisSpacing: AppTheme.metrics.kSpace12,
              ),
              itemCount: displayNovels.length,
              itemBuilder: (context, index) {
                return LibraryBookCard(metadata: displayNovels[index], viewModel: viewModel);
              },
            );
          }),
        ),
      ],
    );
  }
}
