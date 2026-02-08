import 'package:flutter/foundation.dart';
import 'package:slime_works/core/index.dart';

class DemoScreenViewModel extends BaseViewModel {
  int a = 0;

  @override
  Future<void> onInit() async {
    if (kDebugMode) {
      print('DemoScreenViewModel initialized');
    }
    await super.onInit();
  }

  @override
  void dispose() {
    if (kDebugMode) {
      print('DemoScreenViewModel disposed');
    }
    super.dispose();
  }

  void add() {
    a += 1;
    notifyListeners();
  }
}
