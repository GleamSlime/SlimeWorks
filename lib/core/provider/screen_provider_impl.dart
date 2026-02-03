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
}
