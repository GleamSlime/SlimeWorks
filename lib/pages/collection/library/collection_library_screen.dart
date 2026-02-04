import 'package:flutter/material.dart';
import 'package:slime_works/components/window/desktop_head.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_provider.dart';

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
          children: [
            DesktopHeadToolsButton(
              icon: const Icon(Icons.refresh),
              size: AppTheme.metrics.fontSize34,
              onTap: () {
                // Implement refresh functionality here
              },
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
    return const Scaffold(body: Center(child: Text('Collection Library')));
  }
}
