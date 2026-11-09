import 'package:flutter/material.dart';

import '../../app/theme/tminus_theme.dart';
import '../common/status_tone.dart';

/// One permission on the Permissions step: an icon, the title, a one-line
/// reason and then either a button or, once the permission is in order, a tick
/// with "Allowed". The button says **Allow**, or whatever [actionLabel] says
/// when Android will not ask again (**Open settings**).
///
/// The row is keyed `permission-<id>` and its button `allow-<id>`.
class PermissionRow extends StatelessWidget {
  const PermissionRow({
    super.key,
    required this.id,
    required this.icon,
    required this.title,
    required this.reason,
    required this.allowed,
    required this.onAction,
    this.actionLabel = 'Allow',
  });

  /// `notifications`, `fullScreen`, `battery` or `calendar`.
  final String id;
  final IconData icon;
  final String title;
  final String reason;

  /// The permission is in order: a tick instead of the button.
  final bool allowed;

  /// What the button does.
  final VoidCallback onAction;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      key: Key('permission-$id'),
      padding: const EdgeInsets.symmetric(
        horizontal: TMinusSpacing.md,
        vertical: TMinusSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(icon, color: scheme.onSurfaceVariant),
          const SizedBox(width: TMinusSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: textTheme.bodyLarge),
                Text(
                  reason,
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: TMinusSpacing.sm),
          if (allowed)
            const _Allowed()
          else
            FilledButton(
              key: Key('allow-$id'),
              onPressed: onAction,
              // A screen reader says which permission, not just "Allow".
              child: Text(actionLabel, semanticsLabel: '$actionLabel $title'),
            ),
        ],
      ),
    );
  }
}

/// The tick and "Allowed" of a permission that is in order. Status colours are
/// for health, and a permission is part of the health of the alarms.
class _Allowed extends StatelessWidget {
  const _Allowed();

  @override
  Widget build(BuildContext context) {
    final ok = toneColor(context, StatusTone.ok);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle, color: ok, size: 20),
        const SizedBox(width: TMinusSpacing.xxs),
        Text(
          'Allowed',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: ok),
        ),
      ],
    );
  }
}
