import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/tminus_theme.dart';
import '../../core/model/alert.dart';

/// The offsets offered as chips. Any other number goes through "Other…".
const _presetOffsets = [0, 1, 2, 5, 10, 15, 30];

/// The longest lead time the editor accepts: one day.
const _maxOffsetMinutes = 1440;

/// What "Add alert" appends.
const _newAlert = AlertSpec(5, AlertStrength.headsUp);

const _duplicateHint =
    'Two alerts at the same time ring once (the alarm wins).';

/// Edits a list of alerts: the profile editor's alert list and the event
/// sheet's "Customise". Each alert is a card with its minutes before start, a
/// Heads-up / Alarm choice and a remove button, and "Add alert" appends one.
///
/// Every change calls [onChanged] with a new unmodifiable list in row order;
/// [alerts] itself is never touched.
class AlertListEditor extends StatefulWidget {
  const AlertListEditor({
    super.key,
    required this.alerts,
    required this.onChanged,
  });

  final List<AlertSpec> alerts;
  final ValueChanged<List<AlertSpec>> onChanged;

  @override
  State<AlertListEditor> createState() => _AlertListEditorState();
}

class _AlertListEditorState extends State<AlertListEditor> {
  /// The list as of the last change made here. A second change can arrive
  /// before the parent has rebuilt, and it has to build on the first one
  /// instead of on the list this widget was last given.
  late List<AlertSpec> _latest = widget.alerts;

  @override
  void didUpdateWidget(AlertListEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _latest = widget.alerts;
  }

  void _emit(List<AlertSpec> next) {
    _latest = List.unmodifiable(next);
    widget.onChanged(_latest);
  }

  void _add() => _emit([..._latest, _newAlert]);

  void _remove(int row) {
    if (row >= _latest.length) return;
    _emit([..._latest]..removeAt(row));
  }

  void _setOffset(int row, int minutes) {
    if (row >= _latest.length) return;
    _emit([..._latest]..[row] = AlertSpec(minutes, _latest[row].strength));
  }

  void _setStrength(int row, AlertStrength strength) {
    if (row >= _latest.length) return;
    _emit(
      [..._latest]..[row] = AlertSpec(_latest[row].offsetMinutes, strength),
    );
  }

  Future<void> _pickOther(int row) async {
    if (row >= _latest.length) return;
    final current = _latest[row].offsetMinutes;
    final minutes = await showDialog<int>(
      context: context,
      builder: (_) => _OffsetDialog(initial: current),
    );
    if (minutes == null || !mounted) return;
    _setOffset(row, minutes);
  }

  @override
  Widget build(BuildContext context) {
    final alerts = widget.alerts;
    final offsets = {for (final a in alerts) a.offsetMinutes};
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < alerts.length; i++) ...[
          if (i > 0) const SizedBox(height: TMinusSpacing.xs),
          _AlertCard(
            key: ValueKey('alert-$i'),
            index: i,
            spec: alerts[i],
            onOffset: (minutes) => _setOffset(i, minutes),
            onOther: () => _pickOther(i),
            onStrength: (strength) => _setStrength(i, strength),
            onRemove: () => _remove(i),
          ),
        ],
        if (offsets.length != alerts.length)
          Padding(
            padding: const EdgeInsets.only(top: TMinusSpacing.xs),
            child: Text(
              _duplicateHint,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: context.tminusColors.tertiaryText),
            ),
          ),
        if (alerts.isNotEmpty) const SizedBox(height: TMinusSpacing.xs),
        OutlinedButton.icon(
          key: const Key('addAlert'),
          onPressed: _add,
          icon: const Icon(Icons.add),
          label: const Text('Add alert'),
          // A finite minimum width: the editor also sits in a dialog, whose
          // intrinsic-width pass cannot measure an infinite one.
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(64, TMinusSpacing.minTap),
          ),
        ),
      ],
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({
    super.key,
    required this.index,
    required this.spec,
    required this.onOffset,
    required this.onOther,
    required this.onStrength,
    required this.onRemove,
  });

  final int index;
  final AlertSpec spec;
  final ValueChanged<int> onOffset;
  final VoidCallback onOther;
  final ValueChanged<AlertStrength> onStrength;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final colors = context.tminusColors;
    final custom = !_presetOffsets.contains(spec.offsetMinutes);
    final alarm = spec.strength == AlertStrength.alarm;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(TMinusRadii.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          TMinusSpacing.md,
          TMinusSpacing.xs,
          TMinusSpacing.xs,
          TMinusSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'T−${spec.offsetMinutes}',
                  style: context.tminusType.countdownLUnit.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(width: TMinusSpacing.sm),
                Expanded(
                  child: Text(
                    _caption(spec),
                    style: textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  key: ValueKey('alert-$index-remove'),
                  tooltip: 'Remove alert',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: onRemove,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: TMinusSpacing.xs),
              child: Wrap(
                spacing: TMinusSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final minutes in _presetOffsets)
                    _OffsetChip(
                      key: ValueKey('alert-$index-offset-$minutes'),
                      label: '$minutes',
                      numeric: true,
                      selected: spec.offsetMinutes == minutes,
                      onTap: () => onOffset(minutes),
                    ),
                  _OffsetChip(
                    key: ValueKey('alert-$index-offset-other'),
                    label: custom ? '${spec.offsetMinutes}' : 'Other…',
                    numeric: custom,
                    selected: custom,
                    onTap: onOther,
                  ),
                ],
              ),
            ),
            const SizedBox(height: TMinusSpacing.xs),
            Padding(
              padding: const EdgeInsets.only(right: TMinusSpacing.xs),
              child: SegmentedButton<AlertStrength>(
                showSelectedIcon: false,
                // The chosen segment wears the strength's own look: solid for
                // an alarm, soft for a heads-up.
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: alarm
                      ? colors.alarmChipBg
                      : scheme.secondaryContainer,
                  selectedForegroundColor: alarm
                      ? colors.alarmChipFg
                      : scheme.onSecondaryContainer,
                ),
                segments: [
                  for (final s in AlertStrength.values)
                    ButtonSegment<AlertStrength>(
                      value: s,
                      icon: Icon(
                        s == AlertStrength.alarm
                            ? Icons.alarm_rounded
                            : Icons.notifications_outlined,
                      ),
                      label: Text(
                        s == AlertStrength.alarm ? 'Alarm' : 'Heads-up',
                        key: ValueKey('alert-$index-strength-${s.name}'),
                      ),
                    ),
                ],
                selected: {spec.strength},
                onSelectionChanged: (chosen) => onStrength(chosen.single),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Heads-up · 30 min before".
String _caption(AlertSpec spec) {
  final strength = spec.strength == AlertStrength.alarm ? 'Alarm' : 'Heads-up';
  final when = spec.offsetMinutes == 0
      ? 'at start'
      : '${spec.offsetMinutes} min before';
  return '$strength · $when';
}

/// One choice of minutes before start. The chosen one is filled.
class _OffsetChip extends StatelessWidget {
  const _OffsetChip({
    super.key,
    required this.label,
    required this.numeric,
    required this.selected,
    required this.onTap,
  });

  final String label;

  /// Numerals are set in the mono face, like every offset in the app.
  final bool numeric;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = numeric
        ? context.tminusType.chipNumeral
        : Theme.of(context).textTheme.labelMedium;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      selectedColor: scheme.primary,
      side: selected ? BorderSide.none : BorderSide(color: scheme.outline),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TMinusRadii.sm),
      ),
      padding: EdgeInsets.zero,
      labelPadding: const EdgeInsets.symmetric(horizontal: TMinusSpacing.sm),
      labelStyle: base?.copyWith(
        color: selected ? scheme.onPrimary : scheme.onSurface,
      ),
    );
  }
}

/// Asks for a number of minutes from 0 to [_maxOffsetMinutes] and pops it.
class _OffsetDialog extends StatefulWidget {
  const _OffsetDialog({required this.initial});

  final int initial;

  @override
  State<_OffsetDialog> createState() => _OffsetDialogState();
}

class _OffsetDialogState extends State<_OffsetDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: '${widget.initial}',
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final minutes = int.tryParse(_controller.text.trim());
    if (minutes == null || minutes < 0 || minutes > _maxOffsetMinutes) {
      setState(() => _error = 'Enter a number from 0 to $_maxOffsetMinutes.');
      return;
    }
    Navigator.of(context).pop(minutes);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Minutes before start'),
      content: TextField(
        key: const Key('alertOffsetField'),
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: 'Minutes', errorText: _error),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('alertOffsetSet'),
          onPressed: _submit,
          child: const Text('Set'),
        ),
      ],
    );
  }
}
