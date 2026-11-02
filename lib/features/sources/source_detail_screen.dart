import 'package:flutter/material.dart';

/// Placeholder: the real source detail screen replaces this file.
class SourceDetailScreen extends StatelessWidget {
  const SourceDetailScreen({super.key, required this.sourceId});

  final String sourceId;

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: const Text('Source')));
}
