import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/di.dart';
import '../../app/replan_scheduler.dart';
import '../../app/sync_runner.dart';
import '../../app/theme/tminus_theme.dart';
import '../../core/model/source_config.dart';
import '../../core/sources/device_calendar_api.dart';
import '../../core/sources/ics_link_probe.dart';
import '../../core/sources/source_admin.dart';
import '../../core/storage/source_repository.dart';
import '../../core/sync/sync_service.dart';
import '../common/color_palette_picker.dart';
import '../common/guarded.dart';
import 'calendar_picker.dart';
import 'link_field.dart';
import 'link_help.dart';
import 'problem_card.dart' show syncBusyText;

/// The first colour of [calendarPalette] that none of [used] has, so each new
/// calendar looks different. With all six taken, the one used least.
int firstUnusedPaletteColour(Iterable<int> used) {
  final counts = {for (final c in calendarPalette) c: 0};
  for (final colour in used) {
    final n = counts[colour];
    if (n != null) counts[colour] = n + 1;
  }
  var best = calendarPalette.first;
  for (final c in calendarPalette) {
    if (counts[c]! < counts[best]!) best = c;
  }
  return best;
}

/// The two ways to add a calendar (mockup 5b), as two selectable cards: paste
/// a calendar's ICS link (with steps for Outlook, Google or any other), or use
/// a calendar on this phone. It adds the source,
/// syncs it once, and then calls [onAdded] with it. It is part of a screen,
/// not a screen: Add source and onboarding put it on theirs.
///
/// The link is typed into the field, checked by [IcsLinkProbe] (one real
/// fetch, nothing stored) and handed to `SourceAdmin`. Nothing else holds it.
class AddSourcePanel extends StatefulWidget {
  const AddSourcePanel({
    super.key,
    required this.onAdded,
    this.onboarding = false,
  });

  /// Called with each source that was added (the first, when several phone
  /// calendars were added at once), after it has been synced.
  final void Function(SourceConfig) onAdded;

  /// Onboarding keeps the panel on screen after an add (Add source leaves for
  /// the new source), so it tells the user what to do next.
  final bool onboarding;

  @override
  State<AddSourcePanel> createState() => _AddSourcePanelState();
}

enum _Choice { ics, phone }

class _AddSourcePanelState extends State<AddSourcePanel> {
  late final LinkChecker _link;

  /// Whose steps are shown. A link from a host we know switches it.
  LinkProvider _provider = LinkProvider.outlook;
  late final _name = TextEditingController(text: _provider.defaultName);
  _Choice _choice = _Choice.ics;

  /// The link text last looked at, so a selection or focus change (which
  /// also notifies the controller) does not undo the user's own choice.
  String _seenLink = '';

  /// A link is being added (and then synced): the button says so and is off.
  bool _busy = false;

  /// A calendar is being stored. Back does not leave while it is: the add
  /// would finish with nobody to say so. Not during the sync that follows,
  /// which can wait for another one for a minute.
  bool _saving = false;
  Set<String> _taken = const {};
  String? _addedNote;

  @override
  void initState() {
    super.initState();
    _link = LinkChecker(probe: getIt<IcsLinkProbe>());
    _link.text.addListener(_onLinkText);
    unawaited(_refreshTaken());
  }

  @override
  void dispose() {
    _link.text.removeListener(_onLinkText);
    _link.dispose();
    _name.dispose();
    super.dispose();
  }

  /// The phone calendars that are sources already, for **Already added**.
  Future<void> _refreshTaken() async {
    try {
      final taken = await takenCalendarIds();
      if (mounted) setState(() => _taken = taken);
    } catch (e) {
      debugPrint('Listing the phone calendars in use failed (${_tag(e)})');
    }
  }

  /// A pasted or typed link whose host is Outlook's or Google's shows their
  /// steps. Only the host is looked at.
  void _onLinkText() {
    final text = _link.text.text;
    if (text == _seenLink) return;
    _seenLink = text;
    final provider = providerForLink(text);
    if (provider != null) _setProvider(provider);
  }

  /// Shows [provider]'s steps. The name follows unless the user typed one.
  void _setProvider(LinkProvider provider) {
    if (provider == _provider) return;
    final typed = _name.text.trim();
    if (typed.isEmpty ||
        LinkProvider.values.any((p) => p.defaultName == typed)) {
      _name.text = provider.defaultName;
    }
    setState(() => _provider = provider);
  }

  void _selectPhone() {
    if (_choice == _Choice.phone) return;
    setState(() => _choice = _Choice.phone);
    unawaited(_refreshTaken());
  }

  /// A new source is synced once. One that finds another sync running is told
  /// so (it will not be fetched until the next sync), and the plan is asked to
  /// follow the add from the cache.
  Future<void> _syncAfterAdd() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final report = await getIt<SyncRunner>()(SyncTrigger.manual);
      if (report.outcome == SyncRunOutcome.busy) {
        getIt<ReplanScheduler>().request();
        messenger?.showSnackBar(const SnackBar(content: Text(syncBusyText)));
      }
    } catch (e) {
      // The source is added; the first sync is only what makes it show events.
      debugPrint('The sync after adding a calendar failed (${_tag(e)})');
    }
  }

  String _note(String what) => widget.onboarding
      ? 'Added $what. You can add another calendar, or continue.'
      : 'Added $what.';

  Future<void> _addIcs() async {
    final found = _link.found;
    if (found == null || _busy) return;
    final typed = _name.text.trim();
    final name = typed.isEmpty ? _provider.defaultName : typed;
    setState(() {
      _busy = true;
      _saving = true;
    });
    final source = await guarded<SourceConfig>(context, () async {
      final used = [
        for (final s in await getIt<SourceRepository>().all()) s.color,
      ];
      final added = await getIt<SourceAdmin>().addIcsSource(
        name: name,
        color: firstUnusedPaletteColour(used),
        url: found.url,
      );
      return added.source;
    }, failure: 'Could not add the calendar.');
    if (!mounted) return;
    if (source == null) {
      setState(() {
        _busy = false;
        _saving = false;
      });
      return;
    }
    setState(() => _saving = false);
    await _syncAfterAdd();
    if (!mounted) return;
    // The link is no longer needed: the field is emptied, so it does not stay
    // on a screen that onboarding keeps showing.
    _link.clear();
    _name.text = _provider.defaultName;
    setState(() {
      _busy = false;
      _addedNote = _note(source.name);
    });
    widget.onAdded(source);
  }

  Future<bool> _addDevice(List<DeviceCalendar> chosen) async {
    setState(() => _saving = true);
    SourceConfig? first;
    final added = await guarded<bool>(context, () async {
      final admin = getIt<SourceAdmin>();
      for (final calendar in chosen) {
        final source = await admin.addDeviceSource(calendar: calendar);
        first ??= source;
      }
      return true;
    }, failure: 'Could not add the calendar.');
    if (mounted) setState(() => _saving = false);
    // Calendars added before a failure are sources too.
    unawaited(_refreshTaken());
    final source = first;
    if (!mounted || added != true || source == null) return false;
    await _syncAfterAdd();
    if (!mounted) return true;
    setState(() {
      _addedNote = _note(
        chosen.length == 1 ? source.name : '${chosen.length} calendars',
      );
    });
    widget.onAdded(source);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(canPop: !_saving, child: _cards(context));
  }

  Widget _cards(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ChoiceCard(
          key: const Key('choice-ics'),
          icon: Icons.link,
          title: 'Paste a calendar link',
          subtitle: 'Outlook, Google Calendar or any ICS link',
          selected: _choice == _Choice.ics,
          onSelect: () => setState(() => _choice = _Choice.ics),
          child: _icsBody(context),
        ),
        const SizedBox(height: TMinusSpacing.sm),
        _ChoiceCard(
          key: const Key('choice-phone'),
          icon: Icons.phone_android,
          title: 'Use a calendar on this phone',
          subtitle: 'Google, Samsung, Exchange accounts',
          selected: _choice == _Choice.phone,
          onSelect: _selectPhone,
          child: CalendarPicker.pickMany(takenIds: _taken, onAdd: _addDevice),
        ),
        if (_addedNote != null) ...[
          const SizedBox(height: TMinusSpacing.sm),
          Text(
            _addedNote!,
            key: const Key('addedNote'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ],
    );
  }

  Widget _icsBody(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinkHelp(provider: _provider, onChanged: _setProvider),
        const SizedBox(height: TMinusSpacing.sm),
        LinkField(
          controller: _link.text,
          hintText: _provider.hint,
          onSubmitted: (_) => unawaited(_link.check()),
        ),
        const SizedBox(height: TMinusSpacing.xs),
        ListenableBuilder(
          listenable: Listenable.merge([_link, _link.text]),
          builder: (context, _) => Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              key: const Key('checkLink'),
              onPressed: _link.canCheck && !_busy
                  ? () => unawaited(_link.check())
                  : null,
              child: const Text('Check'),
            ),
          ),
        ),
        LinkCheckResult(checker: _link),
        const SizedBox(height: TMinusSpacing.sm),
        TextField(
          key: const Key('newSourceName'),
          controller: _name,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(TMinusRadii.sm),
            ),
            labelText: 'Name',
          ),
        ),
        const SizedBox(height: TMinusSpacing.md),
        ListenableBuilder(
          listenable: _link,
          builder: (context, _) => FilledButton(
            key: const Key('addCalendar'),
            onPressed: _link.state == LinkCheckState.found && !_busy
                ? _addIcs
                : null,
            child: Text(_busy ? 'Adding…' : 'Add calendar'),
          ),
        ),
      ],
    );
  }
}

/// What a failure may say in the log: a platform error's code, else the type.
String _tag(Object error) =>
    error is PlatformException ? error.code : '${error.runtimeType}';

/// One of the two ways to add a calendar: a header that selects it (icon,
/// title, subtitle, radio mark) and, while selected, its [child].
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onSelect,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onSelect;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: scheme.surfaceContainer,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TMinusRadii.xl),
        side: selected
            ? BorderSide(color: scheme.primary, width: 1.5)
            : BorderSide.none,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MergeSemantics(
            child: Semantics(
              inMutuallyExclusiveGroup: true,
              checked: selected,
              child: InkWell(
                onTap: onSelect,
                child: Padding(
                  padding: const EdgeInsets.all(TMinusSpacing.md),
                  child: Row(
                    children: [
                      Icon(icon, color: scheme.onSurfaceVariant),
                      const SizedBox(width: TMinusSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: textTheme.titleMedium),
                            Text(
                              subtitle,
                              style: textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: selected ? scheme.primary : scheme.outline,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (selected)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                TMinusSpacing.md,
                0,
                TMinusSpacing.md,
                TMinusSpacing.md,
              ),
              child: child,
            ),
        ],
      ),
    );
  }
}
