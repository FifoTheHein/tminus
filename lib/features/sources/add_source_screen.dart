import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/tminus_theme.dart';
import 'add_source_panel.dart';

/// Add source (the FAB on Sources): the same two ways to add a calendar as
/// onboarding, on a screen of their own. A new source opens its detail.
class AddSourceScreen extends StatelessWidget {
  const AddSourceScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Add a calendar')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        TMinusSpacing.lg,
        TMinusSpacing.xs,
        TMinusSpacing.lg,
        TMinusSpacing.xxl,
      ),
      child: AddSourcePanel(
        onAdded: (source) =>
            context.go('/sources/${Uri.encodeComponent(source.id)}'),
      ),
    ),
  );
}
