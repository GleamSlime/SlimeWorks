import 'package:flutter/material.dart';
import 'pages/gooey_dropdown_demo_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: GooeyDropdownDemoPage(), debugShowCheckedModeBanner: false);
  }
}
