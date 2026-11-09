import 'package:flutter/material.dart';

import '../../app/theme/tminus_theme.dart';
import 'status_tone.dart';

/// A rounded notice in the tone's container colour: an icon, a title, optional
/// [text] and an optional action (mockups 2c, 6d, 4b).
///
/// Without [text] it is the compact one-line banner, with the action at the
/// right. With [text] it is the larger card: a bold title, the text, and the
/// action under it.
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    super.key,
    required this.tone,
    required this.icon,
    required this.title,
    this.text,
    this.actionLabel,
    this.onAction,
  });

  final StatusTone tone;
  final IconData icon;
  final String title;
  final String? text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = context.tminusColors;
    final textTheme = Theme.of(context).textTheme;
    final (background, foreground, accent) = switch (tone) {
      StatusTone.ok => (
        colors.statusOkContainer,
        colors.onStatusOkContainer,
        colors.statusOk,
      ),
      StatusTone.warn => (
        colors.statusWarnContainer,
        colors.onStatusWarnContainer,
        colors.statusWarn,
      ),
      StatusTone.error => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        scheme.error,
      ),
      StatusTone.neutral => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        scheme.primary,
      ),
    };
    final body = text;
    final label = actionLabel;

    if (body == null) {
      return Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: EdgeInsets.fromLTRB(
          TMinusSpacing.md,
          TMinusSpacing.xs,
          label == null ? TMinusSpacing.md : TMinusSpacing.xs,
          TMinusSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(TMinusRadii.md),
        ),
        child: Row(
          children: [
            Icon(icon, color: accent),
            const SizedBox(width: TMinusSpacing.sm),
            Expanded(
              child: Text(
                title,
                style: textTheme.bodyLarge?.copyWith(color: foreground),
              ),
            ),
            if (label != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(foregroundColor: foreground),
                child: Text(label),
              ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(TMinusSpacing.md),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(TMinusRadii.xl),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent),
          const SizedBox(width: TMinusSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.titleMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: TMinusSpacing.xxs),
                Text(
                  body,
                  style: textTheme.bodyMedium?.copyWith(color: foreground),
                ),
                if (label != null)
                  TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      foregroundColor: foreground,
                      padding: EdgeInsets.zero,
                      alignment: Alignment.centerLeft,
                      minimumSize: const Size(
                        TMinusSpacing.minTap,
                        TMinusSpacing.minTap,
                      ),
                    ),
                    child: Text(label),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
