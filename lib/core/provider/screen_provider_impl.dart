import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_provider.dart';

class DesktopScreenProviderImpl extends DesktopScreenProvider {
  final List<ScreenChromeEntry> _chromeStack = <ScreenChromeEntry>[];

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
    final ScreenChromeEntry entry = ScreenChromeEntry(owner: owner, data: chrome);

    if (owner == null) {
      _chromeStack
        ..clear()
        ..add(entry);
      screenChrome.value = entry;
      mobileImmersiveMode.value = false;
      return;
    }

    final int existingIndex = _chromeStack.indexWhere((item) => identical(item.owner, owner));
    if (existingIndex >= 0) {
      _chromeStack[existingIndex] = entry;
    } else {
      _chromeStack.add(entry);
      mobileImmersiveMode.value = false;
    }

    screenChrome.value = _chromeStack.isEmpty ? const ScreenChromeEntry.empty() : _chromeStack.last;
  }

  @override
  void clearScreenChrome({Object? owner}) {
    if (owner == null) {
      _chromeStack.clear();
      screenChrome.value = const ScreenChromeEntry.empty();
      mobileImmersiveMode.value = false;
      return;
    }

    _chromeStack.removeWhere((entry) => identical(entry.owner, owner));
    screenChrome.value = _chromeStack.isEmpty ? const ScreenChromeEntry.empty() : _chromeStack.last;
    mobileImmersiveMode.value = false;
  }

  @override
  void setMobileImmersiveMode(bool isImmersive) {
    mobileImmersiveMode.value = isImmersive;
  }
}
