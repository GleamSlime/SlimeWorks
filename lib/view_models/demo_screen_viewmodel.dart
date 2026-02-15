import 'package:flutter/foundation.dart';
import 'package:slime_works/core/index.dart';

class DemoScreenViewModel extends BaseViewModel {
  int a = 0;

  @override
  Future<void> onInitAsync() async {
    if (kDebugMode) {
      print('DemoScreenViewModel initialized');
    }
    await super.onInitAsync();
  }

  @override
  void onClose() {
    if (kDebugMode) {
      print('DemoScreenViewModel disposed');
    }
    super.onClose();
  }

  void add() {
    a += 1;
    update();
  }
}
