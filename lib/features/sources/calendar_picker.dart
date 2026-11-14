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
import 'calendar_groups.dart';

/// Said after one "Don't allow" (decision 12).
const calendarAccessNeededText =
    "T-Minus needs calendar access to read this phone's calendars.";

/// Said when Android will not ask again (decision 12).
const calendarAccessOffText = 'Calendar access is off. Turn it on in Settings.';

/// The line under the list while a calendar in it has no events on this phone.
const _notSyncedNote =
    'Calendars marked Not synced have no events on this phone. Turn on sync '
    'for them in their calendar app, then come back.';

/// How faint the colour dot of a calendar that is not synced is.
const _notSyncedDotOpacity = 0.38;

/// The widest a row's trailing label gets before it wraps, so a long one
/// ("Already added, not synced") cannot squeeze the calendar's name out.
const _statusMaxWidth = 120.0;

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

/// Asks for calendar access, then lists the calendars on this phone, grouped
/// under a heading for each account (see [groupCalendars]).
///
/// [CalendarPicker.pickMany] (Add source) shows checkboxes and an **Add
/// selected** button; [CalendarPicker.pickOne] (choosing a calendar again for
/// a restored source) answers as soon as a row is tapped. A calendar in
/// [takenIds] is checked, disabled and marked **Already added**. One with no
/// events on this phone ([DeviceCalendar.syncEvents] is false) is greyed,
/// marked **Not synced** and cannot be chosen either.
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

  /// The calendars that would be added: ticked, with events on this phone, and
  /// not a source already. A row that is not synced cannot be ticked, so the
  /// check here is a second line of defence.
  List<DeviceCalendar> _chosen() => [
    for (final c in _calendars)
      if (c.syncEvents &&
          _selected.contains(c.id) &&
          !widget.takenIds.contains(c.id))
        c,
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
    final groups = groupCalendars(_calendars);
    final noteStyle = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: context.tminusColors.tertiaryText);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < groups.length; i++) ...[
          _GroupHeading(group: groups[i], first: i == 0),
          for (final c in groups[i].calendars)
            _CalendarRow(
              calendar: c,
              taken: widget.takenIds.contains(c.id),
              checked: _selected.contains(c.id),
              single: _single,
              showAccount: groups[i].showAccountLineFor(c),
              onTap: () => _tap(c),
            ),
        ],
        if (_calendars.any((c) => !c.syncEvents))
          Padding(
            padding: const EdgeInsets.only(top: TMinusSpacing.sm),
            child: Text(
              _notSyncedNote,
              key: const Key('notSyncedNote'),
              style: noteStyle,
            ),
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

/// The heading over one group of calendars: the kind in capitals, then the
/// account as the provider spelled it, as in `GOOGLE · alex@example.com`. A
/// screen reader skips the capitals and reads the sentence form, and can jump
/// from heading to heading.
class _GroupHeading extends StatelessWidget {
  const _GroupHeading({required this.group, required this.first});

  final CalendarGroup group;

  /// The first heading has nothing above it to leave room for.
  final bool first;

  @override
  Widget build(BuildContext context) {
    final words = _kindWords(group.kind);
    final name = group.accountName;
    // With no name there is no ` · ` either.
    final account = name == null || name.isEmpty ? null : name;
    return Padding(
      padding: EdgeInsets.only(
        top: first ? 0 : TMinusSpacing.md,
        bottom: TMinusSpacing.xxs,
      ),
      child: Semantics(
        container: true,
        header: true,
        label: account == null ? words : '$words, $account',
        child: ExcludeSemantics(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: words.toUpperCase()),
                // The account is a name or an address, so it keeps its case
                // and takes normal letter spacing: the overline's wide
                // tracking pulls an address apart until it is hard to read.
                if (account != null)
                  TextSpan(
                    text: ' · $account',
                    style: const TextStyle(letterSpacing: 0),
                  ),
              ],
            ),
            style: context.tminusType.overline.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

/// The words that name a kind of group, as a sentence. The heading shows them
/// in capitals; a screen reader reads them as they are.
String _kindWords(CalendarGroupKind kind) => switch (kind) {
  CalendarGroupKind.google => 'Google',
  CalendarGroupKind.samsung => 'Samsung account',
  CalendarGroupKind.outlook => 'Outlook',
  CalendarGroupKind.exchange => 'Exchange',
  CalendarGroupKind.other => 'Other',
  CalendarGroupKind.shared => 'Shared with you',
  CalendarGroupKind.holidays => 'Holidays and birthdays',
  CalendarGroupKind.phoneOnly => 'On this phone only',
};

class _CalendarRow extends StatelessWidget {
  const _CalendarRow({
    required this.calendar,
    required this.taken,
    required this.checked,
    required this.single,
    required this.showAccount,
    required this.onTap,
  });

  final DeviceCalendar calendar;
  final bool taken;
  final bool checked;
  final bool single;

  /// Whether the grey account line shows under the name. The group decides.
  final bool showAccount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final muted = context.tminusColors.tertiaryText;
    final account = calendar.accountName;
    final notSynced = !calendar.syncEvents;
    // A source already, or a calendar with no events on this phone: neither
    // can be chosen.
    final disabled = taken || notSynced;
    final status = switch ((taken, notSynced)) {
      (true, true) => 'Already added, not synced',
      (true, false) => 'Already added',
      (false, true) => 'Not synced',
      (false, false) => null,
    };
    // The calendar's own colour is data, not a theme colour.
    final dotColor = Color(calendar.color);
    // One node for the whole row, as a checkbox list tile makes: name, account
    // and state read together. Without a checkbox (choosing again), `enabled`
    // is what says a row is unavailable.
    return MergeSemantics(
      child: Semantics(
        enabled: !disabled,
        child: InkWell(
          key: Key('calendar-${calendar.id}'),
          onTap: disabled ? null : onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: TMinusSpacing.minTap),
            child: Row(
              children: [
                if (single)
                  const SizedBox(width: TMinusSpacing.xs)
                else
                  // A calendar that is a source already reads as ticked, and
                  // the box is disabled. A calendar that is not synced has a
                  // disabled box too, and it stays unticked.
                  Checkbox(
                    value: taken || (!notSynced && checked),
                    onChanged: disabled ? null : (_) => onTap(),
                  ),
                // Decoration only, so a screen reader skips it.
                ExcludeSemantics(
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: notSynced
                          ? dotColor.withValues(alpha: _notSyncedDotOpacity)
                          : dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: TMinusSpacing.sm),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: TMinusSpacing.xs,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          calendar.name,
                          style: textTheme.titleMedium?.copyWith(
                            color: disabled ? scheme.onSurfaceVariant : null,
                          ),
                        ),
                        if (showAccount && account != null)
                          Text(
                            account,
                            style: textTheme.bodySmall?.copyWith(color: muted),
                          ),
                      ],
                    ),
                  ),
                ),
                if (status != null)
                  Padding(
                    padding: const EdgeInsets.only(left: TMinusSpacing.xs),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _statusMaxWidth,
                      ),
                      child: Text(
                        status,
                        style: textTheme.bodySmall?.copyWith(color: muted),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
