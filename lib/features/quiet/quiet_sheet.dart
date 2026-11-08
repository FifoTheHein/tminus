import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../app/di.dart';
import '../../app/replan_scheduler.dart';
import '../../app/theme/tminus_theme.dart';
import '../../core/model/local_date.dart';
import '../../core/model/quiet_state.dart';
import '../../core/model/utc.dart';
import '../../core/rules/rules_engine.dart';
import '../../core/storage/settings_repository.dart';
import '../../core/text/time_text.dart';
import '../common/guarded.dart';

/// Opens the quiet modes sheet (mockup 2b). Completes when the sheet closes.
///
/// It goes on the root navigator, so it covers the navigation bar as the mockup
/// shows and the tabs cannot be switched underneath it.
Future<void> showQuietSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    useRootNavigator: true,
    builder: (_) => const QuietSheet(),
  );
}

/// The next time [time] occurs in [zone] after [now]: today if still ahead,
/// else tomorrow. A DST gap is resolved by TZDateTime's normalisation.
DateTime pauseUntil(TimeOfDay time, DateTime now, tz.Location zone) {
  final local = tz.TZDateTime.from(now, zone);
  var at = tz.TZDateTime(
    zone,
    local.year,
    local.month,
    local.day,
    time.hour,
    time.minute,
  );
  if (!at.isAfter(local)) {
    at = tz.TZDateTime(
      zone,
      local.year,
      local.month,
      local.day + 1,
      time.hour,
      time.minute,
    );
  }
  return plainUtc(at);
}

/// The sheet's content: the three quiet modes, a note and, while a mode is on,
/// a button that ends it.
///
/// Every choice is written with `setQuietStateAt`, never `setQuietState`, so a
/// quick-settings tile tap that is older than the choice cannot undo it. Each
/// choice then asks for a re-plan and closes the sheet.
class QuietSheet extends StatefulWidget {
  const QuietSheet({super.key});

  @override
  State<QuietSheet> createState() => _QuietSheetState();
}

class _QuietSheetState extends State<QuietSheet> {
  /// Shown when a save fails: fixed text, never the error's own message.
  static const _failure = 'Could not change the quiet mode.';

  late final SettingsRepository _settings;
  late final ReplanScheduler _replan;
  late final UtcClock _clock;
  late final Stream<QuietState> _states;

  /// True from the moment a choice starts (a picker opens, or a save begins)
  /// until it is over. A save always ends by closing the sheet, so a save never
  /// clears it. A second tap meanwhile would save twice and close the sheet
  /// twice.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _settings = getIt<SettingsRepository>();
    _replan = getIt<ReplanScheduler>();
    // The rules engine's clock: the app's one injected clock, and the engine
    // that judges the mode this sheet writes.
    _clock = getIt<RulesEngine>().clock;
    _states = _settings.watchQuietState();
  }

  Future<void> _mute() =>
      _save((now) => QuietState.muteToday(nowUtc: now, zone: tz.local));

  Future<void> _pauseFor(Duration length) =>
      _save((now) => PausedUntil(now.add(length)));

  Future<void> _end() => _save((_) => const QuietNone());

  /// "Pick a time": a 24-hour picker that starts an hour from now. The pause
  /// ends the next time the picked minute comes round.
  Future<void> _pickTime() async {
    if (_busy) return;
    _busy = true;
    final soon = tz.TZDateTime.from(
      _clock(),
      tz.local,
    ).add(const Duration(hours: 1));
    final time =
        await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: soon.hour, minute: soon.minute),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child!,
          ),
        ).whenComplete(() {
          _busy = false;
        });
    if (time == null || !mounted) return;
    await _save((now) => PausedUntil(pauseUntil(time, now, tz.local)));
  }

  /// "Vacation": a date range from today to a year ahead. Days are local days,
  /// so the picker's dates are read back by year, month and day only.
  Future<void> _pickDates(QuietState current) async {
    if (_busy) return;
    _busy = true;
    final today = LocalDate.of(_clock(), tz.local);
    final last = today.addDays(365);
    final range =
        await showDateRangePicker(
          context: context,
          firstDate: _dateOf(today),
          lastDate: _dateOf(last),
          currentDate: _dateOf(today),
          initialDateRange: _openAt(current, today, last),
        ).whenComplete(() {
          _busy = false;
        });
    if (range == null || !mounted) return;
    await _save((_) => Vacation(_dayOf(range.start), _dayOf(range.end)));
  }

  /// Writes the mode that [build] makes for the moment of the choice, asks for
  /// a re-plan, and closes the sheet. A failed write shows [_failure] and
  /// closes the sheet too, so the message is not left behind the sheet.
  Future<void> _save(QuietState Function(DateTime now) build) async {
    if (_busy) return;
    _busy = true;
    final now = _clock();
    final saved = await guarded<bool>(context, () async {
      await _settings.setQuietStateAt(build(now), changedAtUtc: now);
      return true;
    }, failure: _failure);
    // The write counts even if the sheet was dragged away while it ran.
    if (saved ?? false) _replan.request();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final subtle = text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    final mono = text.bodyMedium?.copyWith(fontFamily: TMinusFonts.mono);
    final chipShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(TMinusRadii.md),
    );
    return StreamBuilder<QuietState>(
      stream: _states,
      builder: (context, snapshot) {
        final zone = tz.local;
        final now = _clock();
        final state = snapshot.data ?? const QuietNone();
        // A stored mode that has already ended is not on.
        final on = state.isActive(nowUtc: now, zone: zone);
        final muting = on && state is MuteToday;
        final pause = on && state is PausedUntil ? state : null;
        final vacation = on && state is Vacation ? state : null;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            TMinusSpacing.md,
            0,
            TMinusSpacing.md,
            TMinusSpacing.xl + MediaQuery.viewPaddingOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: TMinusSpacing.xxs,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.bedtime, color: scheme.primary),
                        const SizedBox(width: TMinusSpacing.sm),
                        Expanded(
                          child: Semantics(
                            header: true,
                            child: Text('Quiet modes', style: text.titleLarge),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: TMinusSpacing.xxs),
                    Text(
                      on ? 'On · ${_summary(state, now, zone)}' : 'Off',
                      key: const Key('quiet-status'),
                      style: subtle,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: TMinusSpacing.md),
              _ModeCard(
                key: const Key('quiet-mute'),
                id: 'mute',
                icon: Icons.notifications_off_outlined,
                title: 'Mute today',
                subtitle: 'Until 07:00 tomorrow',
                selected: muting,
                onTap: _mute,
              ),
              const SizedBox(height: TMinusSpacing.sm),
              _ModeCard(
                key: const Key('quiet-pause'),
                id: 'pause',
                icon: Icons.pause_circle_outline,
                title: 'Pause until…',
                subtitle: pause == null
                    ? 'Choose how long'
                    : _resumes(pause.untilUtc, now, zone),
                selected: pause != null,
                footer: Wrap(
                  spacing: TMinusSpacing.xs,
                  runSpacing: TMinusSpacing.xs,
                  children: [
                    for (final hours in const [1, 2, 4])
                      ActionChip(
                        key: Key('quiet-pause-${hours}h'),
                        label: Text('$hours h', style: mono),
                        shape: chipShape,
                        onPressed: () => _pauseFor(Duration(hours: hours)),
                      ),
                    ActionChip(
                      key: const Key('quiet-pause-pick'),
                      avatar: const Icon(Icons.schedule, size: 18),
                      label: const Text('Pick a time'),
                      shape: chipShape,
                      onPressed: _pickTime,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: TMinusSpacing.sm),
              _ModeCard(
                key: const Key('quiet-vacation'),
                id: 'vacation',
                icon: Icons.beach_access_outlined,
                title: 'Vacation',
                subtitle: 'Everything stays silent',
                selected: vacation != null,
                onTap: () => _pickDates(state),
                footer: Container(
                  key: const Key('quiet-vacation-range'),
                  padding: const EdgeInsets.all(TMinusSpacing.sm),
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.outline),
                    borderRadius: BorderRadius.circular(TMinusRadii.md),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 20,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: TMinusSpacing.sm),
                      Expanded(
                        child: Text(
                          vacation == null
                              ? 'Choose dates'
                              : _dates(vacation.firstDay, vacation.lastDay),
                          style: mono,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: TMinusSpacing.md),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: TMinusSpacing.xxs,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: TMinusSpacing.xs),
                    Expanded(
                      child: Text(
                        'Important events still ring (except Vacation).',
                        style: subtle,
                      ),
                    ),
                  ],
                ),
              ),
              if (on) ...[
                const SizedBox(height: TMinusSpacing.md),
                OutlinedButton(
                  key: const Key('quiet-end'),
                  onPressed: _end,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: const Text('End quiet mode'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// One quiet mode as a card (mockup 2b): an icon, the name with a line under
/// it, and a mark at the right. The mode that is on has a check mark and an
/// outline. [onTap] makes the whole card the choice; a card with controls of
/// its own in [footer] passes none.
class _ModeCard extends StatelessWidget {
  const _ModeCard({
    super.key,
    required this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    this.onTap,
    this.footer,
  });

  /// The mode's name in the check mark's key, `quiet-check-<id>`.
  final String id;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? footer;

  static const _iconSize = 24.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final footer = this.footer;
    return Semantics(
      container: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      child: Material(
        color: scheme.surfaceContainerHighest,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TMinusRadii.lg),
          side: selected
              ? BorderSide(color: scheme.primary, width: 2)
              : BorderSide.none,
        ),
        child: InkWell(
          onTap: onTap,
          canRequestFocus: onTap != null,
          child: Padding(
            padding: const EdgeInsets.all(TMinusSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(icon, size: _iconSize, color: scheme.onSurface),
                    const SizedBox(width: TMinusSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: text.titleMedium),
                          Text(
                            subtitle,
                            style: text.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: TMinusSpacing.sm),
                    selected
                        ? Icon(
                            Icons.check_circle,
                            key: Key('quiet-check-$id'),
                            color: scheme.primary,
                          )
                        : Icon(
                            Icons.radio_button_unchecked,
                            color: scheme.outline,
                          ),
                  ],
                ),
                if (footer != null)
                  Padding(
                    padding: const EdgeInsets.only(
                      left: _iconSize + TMinusSpacing.md,
                      top: TMinusSpacing.sm,
                    ),
                    child: footer,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// When [utc] is, as the quiet notes say it: `14:00`, `tomorrow 09:00` or
/// `Fri 9 Oct 09:00`.
String _when(DateTime utc, DateTime now, tz.Location zone) {
  final today = LocalDate.of(now, zone);
  final day = LocalDate.of(utc, zone);
  final time = TimeText.hm(utc, zone);
  if (day == today) return time;
  if (day == today.addDays(1)) return 'tomorrow $time';
  return '${TimeText.day(day)} $time';
}

/// `Resumes at 14:00` for a pause that ends today, else `Resumes tomorrow 09:00`.
String _resumes(DateTime until, DateTime now, tz.Location zone) {
  final when = _when(until, now, zone);
  final sameDay = LocalDate.of(until, zone) == LocalDate.of(now, zone);
  return sameDay ? 'Resumes at $when' : 'Resumes $when';
}

/// `Mon 12 Oct – Fri 16 Oct`.
String _dates(LocalDate first, LocalDate last) =>
    '${TimeText.day(first)} – ${TimeText.day(last)}';

/// What is on, for the line under the title: `muted until tomorrow 07:00`.
String _summary(QuietState state, DateTime now, tz.Location zone) =>
    switch (state) {
      MuteToday(:final untilUtc) => 'muted until ${_when(untilUtc, now, zone)}',
      PausedUntil(:final untilUtc) =>
        'paused until ${_when(untilUtc, now, zone)}',
      Vacation(:final firstDay, :final lastDay) =>
        'vacation ${_dates(firstDay, lastDay)}',
      QuietNone() => '',
    };

/// The picker works in plain dates; only their year, month and day are used.
DateTime _dateOf(LocalDate d) => DateTime(d.year, d.month, d.day);

LocalDate _dayOf(DateTime d) => LocalDate(d.year, d.month, d.day);

/// The range the picker opens on: the vacation that is set, cut to the days the
/// picker allows (a vacation that began before today opens from today). Null
/// when none is set, or when nothing of it is left inside the allowed days.
DateTimeRange? _openAt(QuietState current, LocalDate today, LocalDate last) {
  if (current is! Vacation || !(current.lastDay >= today)) return null;
  final first = current.firstDay >= today ? current.firstDay : today;
  final end = current.lastDay <= last ? current.lastDay : last;
  if (!(first <= end)) return null;
  return DateTimeRange(start: _dateOf(first), end: _dateOf(end));
}
