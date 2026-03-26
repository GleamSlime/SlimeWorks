import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_provider.dart';

class DesktopScreenProviderImpl extends DesktopScreenProvider {
  @override
  void setWidth(double w) {
    width.value = w;
  }

  @override
  void setHeight(double h) {
    height.value = h;
  }

  @override
  void setTitle(String t) {
    title.value = t;
  }

  @override
  void setScreenChrome(ScreenChromeData chrome, {Object? owner}) {
    screenChrome.value = ScreenChromeEntry(owner: owner, data: chrome);
  }

  @override
  void clearScreenChrome({Object? owner}) {
    if (owner != null && !identical(screenChrome.value.owner, owner)) {
      return;
    }
    screenChrome.value = const ScreenChromeEntry.empty();
  }
}
