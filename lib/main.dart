import 'package:flutter/material.dart';
import 'package:slime_works/components/window/desktop_scaffold.dart';
import 'package:slime_works/src/rust/api/simple.dart';
import 'package:slime_works/src/rust/frb_generated.dart';

Future<void> main() async {
  DesktopScaffold.initManager();

  await RustLib.init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: DesktopScaffold(
        child: Row(
          children: [
            Center(
              child: Text(
                'Action: Call Rust `greet("Tom")`\nResult: `${greet(name: "Tom13")}`',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
