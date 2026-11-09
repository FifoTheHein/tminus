import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/di.dart';
import '../../app/theme/tminus_theme.dart';
import '../../core/model/source_config.dart';
import '../../core/platform/ui_platform.dart';
import '../../core/sources/device_calendar_api.dart';
import '../../core/storage/app_settings.dart';
import '../../core/storage/source_repository.dart';
import '../common/guarded.dart';

/// Said after one "Don't allow" (decision 12).
const calendarAccessNeededText =
    "T-Minus needs calendar access to read this phone's calendars.";

/// Said when Android will not ask again (decision 12).
const calendarAccessOffText = 'Calendar access is off. Turn it on in Settings.';

/// The ids of the phone calendars that a source already reads, so the picker
/// can mark them **Already added** (decision 18). A source that still waits
/// for its calendar after a restore holds an id from another phone, which
/// means nothing here, so it counts for nothing. [exceptSourceId] leaves one
/// source out: the one that is choosing again.
Future<Set<String>> takenCalendarIds({String? exceptSourceId}) async {
  final appSettings = getIt<AppSettings>();
  final taken = <String>{};
  for (final source in await getIt<SourceRepository>().all()) {
    final calendarId = source.deviceCalendarId;
    if (source.kind != SourceKind.device ||
        calendarId == null ||
        source.id == exceptSourceId) {
      continue;
    }
    if (await appSettings.sourceSetup(source.id) != SourceSetup.ready) continue;
    taken.add(calendarId);
  }
  return taken;
}

enum _Access { asking, granted, denied, permanentlyDenied, failed }

/// Asks for calendar access, then lists the calendars on this phone.
///
/// [CalendarPicker.pickMany] (Add source) shows checkboxes and an **Add
/// selected** button; [CalendarPicker.pickOne] (choosing a calendar again for
/// a restored source) answers as soon as a row is tapped. A calendar in
/// [takenIds] is checked, disabled and marked **Already added**.
class CalendarPicker extends StatefulWidget {
  const CalendarPicker.pickOne({
    super.key,
    required this.takenIds,
    required ValueChanged<DeviceCalendar> this.onPick,
  }) : onAdd = null;

  /// [onAdd] answers whether the calendars were added; the selection is
  /// cleared when they were.
  const CalendarPicker.pickMany({
    super.key,
    required this.takenIds,
    required Future<bool> Function(List<DeviceCalendar> chosen) this.onAdd,
  }) : onPick = null;

  final Set<String> takenIds;

  /// Set by [CalendarPicker.pickOne]: the tapped calendar is the answer.
  final ValueChanged<DeviceCalendar>? onPick;

  /// Set by [CalendarPicker.pickMany]: the **Add selected** button.
  final Future<bool> Function(List<DeviceCalendar> chosen)? onAdd;

  @override
  State<CalendarPicker> createState() => _CalendarPickerState();
}

class _CalendarPickerState extends State<CalendarPicker> {
  _Access _access = _Access.asking;
  List<DeviceCalendar> _calendars = const [];
  final _selected = <String>{};
  bool _adding = false;

  bool get _single => widget.onPick != null;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    var access = _Access.failed;
    var calendars = const <DeviceCalendar>[];
    try {
      switch (await getIt<UiPlatform>().requestPermission(
        UiPermission.calendar,
      )) {
        case PermissionResult.granted:
          calendars = await getIt<DeviceCalendarApi>().calendars();
          access = _Access.granted;
        case PermissionResult.denied:
          access = _Access.denied;
        case PermissionResult.permanentlyDenied:
          access = _Access.permanentlyDenied;
      }
    } on PlatformException catch (e) {
      // The code only: a message can carry more than the user expects.
      debugPrint('Reading the phone calendars failed (${e.code})');
      access = e.code == DeviceCalendarApi.permissionDenied
          ? _Access.denied
          : _Access.failed;
    } catch (e) {
      debugPrint('Reading the phone calendars failed (${e.runtimeType})');
    }
    if (!mounted) return;
    setState(() {
      _access = access;
      _calendars = calendars;
    });
  }

  void _retry() {
    setState(() => _access = _Access.asking);
    unawaited(_load());
  }

  void _openSettings() {
    unawaited(
      guarded<void>(
        context,
        () => getIt<UiPlatform>().openAppDetails(),
        failure: 'Could not open Settings.',
      ),
    );
  }

  /// The calendars that would be added: ticked, and not a source already.
  List<DeviceCalendar> _chosen() => [
    for (final c in _calendars)
      if (_selected.contains(c.id) && !widget.takenIds.contains(c.id)) c,
  ];

  void _tap(DeviceCalendar calendar) {
    final pick = widget.onPick;
    if (pick != null) {
      pick(calendar);
      return;
    }
    setState(() {
      if (!_selected.add(calendar.id)) _selected.remove(calendar.id);
    });
  }

  Future<void> _add() async {
    final onAdd = widget.onAdd;
    final chosen = _chosen();
    if (onAdd == null || chosen.isEmpty || _adding) return;
    setState(() => _adding = true);
    var added = false;
    try {
      added = await onAdd(chosen);
    } finally {
      if (mounted) {
        setState(() {
          _adding = false;
          if (added) _selected.clear();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_access) {
      case _Access.asking:
        return const Padding(
          padding: EdgeInsets.all(TMinusSpacing.md),
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      case _Access.denied:
        return _Message(
          text: calendarAccessNeededText,
          actionLabel: 'Try again',
          onAction: _retry,
        );
      case _Access.permanentlyDenied:
        return _Message(
          text: calendarAccessOffText,
          actionLabel: 'Open settings',
          onAction: _openSettings,
        );
      case _Access.failed:
        return _Message(
          text: "Could not read this phone's calendars.",
          actionLabel: 'Try again',
          onAction: _retry,
        );
      case _Access.granted:
        return _list(context);
    }
  }

  Widget _list(BuildContext context) {
    if (_calendars.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(TMinusSpacing.md),
        child: Text(
          'No calendars found on this phone.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in _calendars)
          _CalendarRow(
            calendar: c,
            taken: widget.takenIds.contains(c.id),
            checked: _selected.contains(c.id),
            single: _single,
            onTap: () => _tap(c),
          ),
        if (!_single)
          Padding(
            padding: const EdgeInsets.only(top: TMinusSpacing.sm),
            child: FilledButton(
              key: const Key('addSelected'),
              onPressed: _chosen().isEmpty || _adding ? null : _add,
              child: Text(_adding ? 'Adding…' : 'Add selected'),
            ),
          ),
      ],
    );
  }
}

/// A one-line answer with one button (denied, turned off, or failed).
class _Message extends StatelessWidget {
  const _Message({
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: TMinusSpacing.xs),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          key: const Key('calendarAccessMessage'),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        TextButton(onPressed: onAction, child: Text(actionLabel)),
      ],
    ),
  );
}

class _CalendarRow extends StatelessWidget {
  const _CalendarRow({
    required this.calendar,
    required this.taken,
    required this.checked,
    required this.single,
    required this.onTap,
  });

  final DeviceCalendar calendar;
  final bool taken;
  final bool checked;
  final bool single;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final muted = context.tminusColors.tertiaryText;
    final account = calendar.accountName;
    return InkWell(
      key: Key('calendar-${calendar.id}'),
      onTap: taken ? null : onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: TMinusSpacing.minTap),
        child: Row(
          children: [
            if (single)
              const SizedBox(width: TMinusSpacing.xs)
            else
              // A calendar that is a source already reads as ticked, and the
              // box is disabled.
              Checkbox(
                value: taken || checked,
                onChanged: taken ? null : (_) => onTap(),
              ),
            // The calendar's own colour is data, not a theme colour.
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: Color(calendar.color),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: TMinusSpacing.sm),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: TMinusSpacing.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      calendar.name,
                      style: textTheme.titleMedium?.copyWith(
                        color: taken ? scheme.onSurfaceVariant : null,
                      ),
                    ),
                    if (account != null && account.isNotEmpty)
                      Text(
                        account,
                        style: textTheme.bodySmall?.copyWith(color: muted),
                      ),
                  ],
                ),
              ),
            ),
            if (taken)
              Padding(
                padding: const EdgeInsets.only(left: TMinusSpacing.xs),
                child: Text(
                  'Already added',
                  style: textTheme.bodySmall?.copyWith(color: muted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
