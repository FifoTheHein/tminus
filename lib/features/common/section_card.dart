import 'package:flutter/material.dart';

import '../../app/theme/tminus_theme.dart';

/// A group of rows on a rounded surface with a divider between the rows,
/// under an optional title (mockups 4d, 5f). The rows bring their own padding.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              TMinusSpacing.xs,
              TMinusSpacing.md,
              TMinusSpacing.xs,
              TMinusSpacing.xs,
            ),
            child: Text(title!, style: Theme.of(context).textTheme.titleSmall),
          ),
        Material(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(TMinusRadii.lg),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: scheme.outlineVariant,
                  ),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}
