import 'package:flutter/material.dart';

/// Placeholder: the real rule editor replaces this file. A null [ruleId]
/// makes a new rule.
class RuleEditorScreen extends StatelessWidget {
  const RuleEditorScreen({super.key, this.ruleId});

  final String? ruleId;

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: const Text('Rule')));
}
