import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:timezone/timezone.dart' as tz;

import '../../app/di.dart';
import '../../app/theme/tminus_theme.dart';
import '../../core/model/alert.dart';
import '../../core/model/local_date.dart';
import '../../core/text/time_text.dart';
import '../common/alert_list_editor.dart';
import '../common/notice_banner.dart';
import '../common/profile_radio_list.dart';
import '../common/status_tone.dart';
import 'agenda_model.dart';
import 'event_sheet_controller.dart';
import 'why_text.dart';

/// Opens the event sheet (mockup 2a) for [item], the meeting as the Agenda
/// has it now.
///
/// It goes on the root navigator: opened from a card, which sits inside the
/// Agenda tab's navigator, it would otherwise be drawn inside the tab and leave
/// the navigation bar showing under it, where the mockup has the sheet cover
/// it.
Future<void> showEventSheet(BuildContext context, AgendaItem item) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    useRootNavigator: true,
    builder: (_) => EventSheet(item: item),
  );
}

/// The detail of one meeting: where it is from, when, who holds it, a Join
/// button, the alerts it gets and why (Plan 5 decisions 8 and 9).
///
/// The sheet takes [item] as it was when opened and does not resolve it again.
/// After a write the Agenda reloads behind the sheet, the radio list follows
/// the stored override, and the WHY card says it is out of date.
class EventSheet extends StatefulWidget {
  const EventSheet({super.key, required this.item});

  final AgendaItem item;

  @override
  State<EventSheet> createState() => _EventSheetState();
}

class _EventSheetState extends State<EventSheet> {
  static const _loadFailure = 'Could not load the alert choices.';
  static const _saveFailure = 'Could not save the change.';
  static const _joinFailure = 'Could not open the Teams link.';

  late final EventSheetController _controller;

  /// The fixed text of the action that failed last. It is shown in the sheet:
  /// a snack bar would be drawn behind a modal sheet, where nobody sees it.
  String? _failure;

  @override
  void initState() {
    super.initState();
    _controller = EventSheetController(
      item: widget.item,
      overrides: getIt(),
      profiles: getIt(),
      replan: getIt(),
      ui: getIt(),
    );
    unawaited(_run(_controller.load, _loadFailure));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Runs a sheet action. A failure shows [failure] and is logged by its type,
  /// or by its code for a platform error, never by its message: a message can
  /// carry a link or a row's values. Returns null when it failed.
  Future<T?> _run<T>(Future<T> Function() action, String failure) async {
    if (_failure != null) setState(() => _failure = null);
    try {
      return await action();
    } on PlatformException catch (e) {
      debugPrint('$failure (${e.code})');
    } catch (e) {
      debugPrint('$failure (${e.runtimeType})');
    }
    if (mounted) setState(() => _failure = failure);
    return null;
  }

  Future<void> _join() async {
    final opened = await _run(_controller.join, _joinFailure);
    // `false`: no app took the link. `null` was reported by [_run].
    if (opened == false && mounted) setState(() => _failure = _joinFailure);
  }

  void _choose(String profileId) {
    // The Custom row is the choice already made.
    if (profileId == customProfileId) return;
    unawaited(_run(() => _controller.chooseProfile(profileId), _saveFailure));
  }

  Future<void> _customise() async {
    final alerts = await showDialog<List<AlertSpec>>(
      context: context,
      builder: (_) => _CustomAlertsDialog(
        initial: _controller.customiseSeed,
        forSeries: _controller.scope == SheetScope.series,
      ),
    );
    if (alerts == null || !mounted) return;
    await _run(() => _controller.setCustomAlerts(alerts), _saveFailure);
  }

  /// The source whose default profile decided, for the WHY text: the first of
  /// the meeting's sources, in rank order, that has one. The rules engine reads
  /// them in that order too.
  String? get _defaultSourceName {
    for (final s in widget.item.sources) {
      if (s.defaultProfileId != null) return s.name;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                TMinusSpacing.md,
                0,
                TMinusSpacing.md,
                TMinusSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ..._details(context),
                  ListenableBuilder(
                    listenable: _controller,
                    builder: (context, _) => _alertsAndWhy(context),
                  ),
                ],
              ),
            ),
          ),
          // Outside the scrolling part, so it is seen wherever the sheet is
          // scrolled to.
          if (_failure != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                TMinusSpacing.md,
                0,
                TMinusSpacing.md,
                TMinusSpacing.md,
              ),
              child: Semantics(
                liveRegion: true,
                child: NoticeBanner(
                  key: const Key('sheetFailure'),
                  tone: StatusTone.error,
                  icon: Icons.error_outline,
                  title: _failure!,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Everything the meeting itself says: its source, title, time, organiser,
  /// place, whether it repeats, and the Join button.
  List<Widget> _details(BuildContext context) {
    final item = widget.item;
    final m = item.meeting;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final colors = context.tminusColors;

    // The sources are in rank order, so the time source comes first.
    final timeSource = item.sources
        .where((s) => s.id == m.sourceId)
        .followedBy(item.sources)
        .firstOrNull;
    final day = TimeText.day(LocalDate.of(m.startUtc, tz.local));
    final when = m.allDay
        ? 'All day'
        : TimeText.range(m.startUtc, m.endUtc, tz.local);
    final organiser = m.organizer;
    final location = m.location;

    return [
      if (timeSource != null)
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: Color(m.calendarColor),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: TMinusSpacing.xs),
            Expanded(
              child: Text(
                timeSource.name,
                key: const Key('sheetSource'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      if (item.sources.length > 1)
        Padding(
          padding: const EdgeInsets.only(top: TMinusSpacing.xxs),
          child: Text(
            'In: ${item.sources.map((s) => s.name).join(', ')}',
            key: const Key('sheetSources'),
            style: textTheme.bodySmall?.copyWith(color: colors.tertiaryText),
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(top: TMinusSpacing.xs),
        child: Text(
          m.title,
          key: const Key('sheetTitle'),
          style: textTheme.headlineSmall?.copyWith(color: scheme.onSurface),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: TMinusSpacing.xxs),
        child: Text(
          '$day · $when',
          key: const Key('sheetTime'),
          style: context.tminusType.time.copyWith(color: scheme.onSurface),
        ),
      ),
      if (organiser != null && organiser.isNotEmpty)
        _InfoRow(icon: Icons.person_outline, text: 'Organiser · $organiser'),
      if (location != null && location.isNotEmpty)
        _InfoRow(icon: Icons.place_outlined, text: location),
      if (m.seriesUid != null)
        const _InfoRow(icon: Icons.repeat, text: 'Part of a series'),
      if (item.hasTeams)
        Padding(
          padding: const EdgeInsets.only(top: TMinusSpacing.lg),
          child: FilledButton.icon(
            key: const Key('joinButton'),
            onPressed: _join,
            style: FilledButton.styleFrom(minimumSize: const Size(64, 56)),
            icon: const Icon(Icons.videocam_rounded),
            label: const Text('Join Teams meeting'),
          ),
        ),
    ];
  }

  /// The scope switch, the profile list and the WHY card. They follow the
  /// controller.
  Widget _alertsAndWhy(BuildContext context) {
    final c = _controller;
    final series = c.scope == SheetScope.series;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: TMinusSpacing.xl),
        Text(
          'Alerts for this event',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: TMinusSpacing.sm),
        SegmentedButton<SheetScope>(
          showSelectedIcon: false,
          segments: [
            const ButtonSegment(
              value: SheetScope.occurrence,
              label: Text('This occurrence'),
            ),
            ButtonSegment(
              value: SheetScope.series,
              label: const Text('Whole series'),
              enabled: c.canUseSeries,
            ),
          ],
          selected: {c.scope},
          onSelectionChanged: (chosen) =>
              unawaited(_run(() => c.setScope(chosen.single), _loadFailure)),
        ),
        const SizedBox(height: TMinusSpacing.sm),
        if (c.loaded)
          ProfileRadioList(
            profiles: c.choices,
            selectedId: c.selectedProfileId,
            onSelected: _choose,
          ),
        TextButton.icon(
          key: const Key('customiseButton'),
          onPressed: c.loaded ? _customise : null,
          style: TextButton.styleFrom(alignment: Alignment.centerLeft),
          icon: const Icon(Icons.tune),
          label: Text(
            series
                ? 'Customise for the whole series'
                : 'Customise for this event',
          ),
        ),
        if (c.current != null)
          TextButton(
            key: const Key('resetOverride'),
            onPressed: () => unawaited(_run(c.reset, _saveFailure)),
            style: TextButton.styleFrom(alignment: Alignment.centerLeft),
            child: const Text('Reset to automatic'),
          ),
        const SizedBox(height: TMinusSpacing.md),
        _whyCard(context),
      ],
    );
  }

  Widget _whyCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final colors = context.tminusColors;
    final sentence = whyText(
      widget.item.resolved,
      sourceName: _defaultSourceName,
    );
    return Container(
      key: const Key('whyCard'),
      padding: const EdgeInsets.all(TMinusSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(TMinusRadii.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.help_outline, color: scheme.onSurfaceVariant),
          const SizedBox(width: TMinusSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WHY',
                  style: context.tminusType.overline.copyWith(
                    color: colors.tertiaryText,
                  ),
                ),
                const SizedBox(height: TMinusSpacing.xxs),
                Text.rich(
                  key: const Key('whyText'),
                  TextSpan(
                    children: [
                      for (final piece in whyPieces(sentence))
                        TextSpan(
                          text: piece.text,
                          style: piece.bold
                              ? const TextStyle(fontWeight: FontWeight.w600)
                              : null,
                        ),
                    ],
                  ),
                  style: textTheme.bodyLarge?.copyWith(color: scheme.onSurface),
                ),
                if (_controller.changed)
                  Padding(
                    padding: const EdgeInsets.only(top: TMinusSpacing.xs),
                    child: Text(
                      'Updated — close to see the new reason.',
                      key: const Key('whyStale'),
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.tertiaryText,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// An icon and one line of text, like "Organiser · Thandi M.".
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: TMinusSpacing.md),
      child: Row(
        children: [
          Icon(icon, color: scheme.onSurfaceVariant),
          const SizedBox(width: TMinusSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Customise for this event": the alert list of this event only, edited with
/// the shared editor. Pops the new list, or nothing.
class _CustomAlertsDialog extends StatefulWidget {
  const _CustomAlertsDialog({required this.initial, required this.forSeries});

  final List<AlertSpec> initial;
  final bool forSeries;

  @override
  State<_CustomAlertsDialog> createState() => _CustomAlertsDialogState();
}

class _CustomAlertsDialogState extends State<_CustomAlertsDialog> {
  late List<AlertSpec> _alerts = widget.initial;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(
        widget.forSeries
            ? 'Custom alerts for the whole series'
            : 'Custom alerts for this event',
      ),
      content: AlertListEditor(
        alerts: _alerts,
        onChanged: (alerts) => setState(() => _alerts = alerts),
      ),
      actions: [
        TextButton(
          key: const Key('customAlertsCancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        // A list with nothing in it would count as no custom alerts at all, so
        // there is nothing to save.
        TextButton(
          key: const Key('customAlertsSave'),
          onPressed: _alerts.isEmpty
              ? null
              : () => Navigator.of(context).pop(_alerts),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
