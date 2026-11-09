import 'package:flutter/material.dart';

import '../../app/theme/tminus_theme.dart';
import '../../core/model/alert_profile.dart';
import 'alert_chips.dart';

/// One row per profile with a radio indicator, the name and the profile's
/// alert chips (mockup 2a). The chosen row is filled. [selectedId] may be null
/// when nothing is chosen.
class ProfileRadioList extends StatelessWidget {
  const ProfileRadioList({
    super.key,
    required this.profiles,
    required this.selectedId,
    required this.onSelected,
  });

  final List<AlertProfile> profiles;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final p in profiles)
          _ProfileRow(
            key: ValueKey('profile-${p.id}'),
            profile: p,
            selected: p.id == selectedId,
            onTap: () => onSelected(p.id),
          ),
      ],
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    super.key,
    required this.profile,
    required this.selected,
    required this.onTap,
  });

  final AlertProfile profile;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(TMinusRadii.md);
    return MergeSemantics(
      child: Semantics(
        inMutuallyExclusiveGroup: true,
        checked: selected,
        child: Material(
          type: MaterialType.transparency,
          child: Ink(
            decoration: BoxDecoration(
              color: selected ? scheme.secondaryContainer : null,
              borderRadius: radius,
            ),
            child: InkWell(
              borderRadius: radius,
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: TMinusSpacing.md,
                    vertical: TMinusSpacing.xs,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: selected ? scheme.primary : scheme.outline,
                      ),
                      const SizedBox(width: TMinusSpacing.md),
                      Expanded(
                        flex: 2,
                        child: Text(
                          profile.name,
                          style: textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: profile.alerts.isEmpty
                              ? Text(
                                  'No alerts',
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: context.tminusColors.tertiaryText,
                                  ),
                                )
                              : AlertChips(profile.alerts),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
