import 'package:flutter/material.dart';

class CollectionLibraryScreen extends StatefulWidget {
  const CollectionLibraryScreen({super.key});

  @override
  State<CollectionLibraryScreen> createState() => _CollectionLibraryScreenState();
}

class _CollectionLibraryScreenState extends State<CollectionLibraryScreen> {
  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Collection Library')));
  }
}
