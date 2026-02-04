import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:slime_works/components/dropdown/gooey_dropdown.dart';
import 'package:slime_works/components/window/desktop_head.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:slime_works/gen/assets.gen.dart';
import 'package:slime_works/pages/backup/demo.dart';
import 'package:slime_works/pages/collection/library/components/library_book_append.dart';
import 'package:slime_works/pages/gooey_dropdown_demo_page.dart';

class YourDropdownContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: const [
        ListTile(title: Text("选项 1")),
        ListTile(title: Text("选项 2")),
        ListTile(title: Text("选项 3")),
      ],
    );
  }
}

class CollectionLibraryScreen extends StatefulWidget {
  const CollectionLibraryScreen({super.key});

  @override
  State<CollectionLibraryScreen> createState() => _CollectionLibraryScreenState();
}

class _CollectionLibraryScreenState extends State<CollectionLibraryScreen> {
  DesktopScreenProvider desktopScreen = getIt<DesktopScreenProvider>();

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      desktopScreen.setScreenHeadToolsWidget(
        Row(
          spacing: AppTheme.metrics.fontSize8,
          children: [
            DesktopHeadToolsButton(
              icon: const Icon(Icons.refresh),
              size: AppTheme.metrics.fontSize34,
              onTap: () {
                // Implement refresh functionality here
              },
            ),
            LibraryBookAppendButton(),
            GooeyDropdown(
              dropdownWidth: 260,
              dropdownHeight: 320,
              dropdown: YourDropdownContent(),
              child: Icon(Icons.menu), // 👈 只是UI
            ),
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
  Widget build(BuildContext context) {
    return GooeyDropdownDemoPage();
  }
}
