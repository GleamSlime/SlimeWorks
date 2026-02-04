import 'package:flutter/material.dart';

class CollectionPictureScreen extends StatefulWidget {
  const CollectionPictureScreen({super.key});

  @override
  State<CollectionPictureScreen> createState() => _CollectionPictureScreenState();
}

class _CollectionPictureScreenState extends State<CollectionPictureScreen> {
  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Collection Picture')));
  }
}
