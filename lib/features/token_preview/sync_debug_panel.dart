import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/di.dart';
import '../../core/sources/device_calendar_api.dart';
import '../../core/sources/fast_alarms.dart';
import '../../core/sources/source_admin.dart';
import '../../core/storage/alert_history_repository.dart';
import '../../core/storage/source_repository.dart';
import '../../core/sync/outcome_severity.dart';
import '../../core/sync/sync_platform.dart';
import '../../core/sync/sync_service.dart';

/// Debug-only sync controls (spec §11 "fast alarms"), so Plan 4 can be tried
/// on a device before the Sources and Health screens (Plan 5) exist: fast
/// alarms, a pasted ICS link, the first phone calendar, and sync buttons.
class SyncDebugPanel extends StatefulWidget {
  const SyncDebugPanel({super.key = const Key('syncDebugPanel')});

  /// One line per run, e.g. `6 alerts planned · armed 4, kept 0, cancelled 0`.
  static String describe(SyncReport r) {
    if (r.outcome == SyncRunOutcome.busy) return 'Another sync is running';
    final applied = r.applied;
    final problems = [
      for (final s in r.sources)
        if (s.outcome.severity != OutcomeSeverity.ok)
          '${s.sourceId}: ${s.outcome.name}',
    ];
    return [
      '${r.planned} alerts planned',
      applied == null
          ? 'applyPlan failed'
          : 'armed ${applied.armed}, kept ${applied.kept}, cancelled ${applied.cancelled}',
      if (r.missedSystem > 0) '${r.missedSystem} missed (system)',
      ...problems,
    ].join(' · ');
  }

  @override
  State<SyncDebugPanel> createState() => _SyncDebugPanelState();
}

class _SyncDebugPanelState extends State<SyncDebugPanel> {
  final _link = TextEditingController();
  String? _status;
  bool _busy = false;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  /// Runs [action], shows its message (or the failure) and enables the buttons
  /// again. A failure is shown by its platform error code, or by its type for
  /// anything else, never by its message: an error message can carry a row's
  /// values or a feed link.
  Future<void> _run(Future<String> Function() action) async {
    setState(() => _busy = true);
    String status;
    try {
      status = await action();
    } on PlatformException catch (e) {
      status = 'Failed: ${e.code}';
    } on MissingPluginException {
      status = 'Sync not available on this platform';
    } catch (e) {
      status = 'Failed: ${e.runtimeType}';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = status;
    });
  }

  Future<String> _sync() async => SyncDebugPanel.describe(
    await getIt<SyncService>().run(SyncTrigger.debug),
  );

  Future<String> _fastAlarms() async {
    await getIt<FastAlarms>().create(DateTime.now().toUtc());
    return 'Fast alarms added · ${await _sync()}';
  }

  Future<String> _clearFastAlarms() async {
    await getIt<FastAlarms>().clear();
    return 'Fast alarms cleared · ${await _sync()}';
  }

  Future<String> _addFeed() async {
    try {
      final added = await getIt<SourceAdmin>().addIcsSource(
        name: 'Debug',
        color: 0xFF6AA0F5,
        url: _link.text,
      );
      _link.clear();
      final warning = added.insecure ? ' (http: not encrypted)' : '';
      return 'Feed added$warning · ${await _sync()}';
    } on IcsUrlException catch (e) {
      return e.message;
    }
  }

  Future<String> _addPhoneCalendar() async {
    final List<DeviceCalendar> calendars;
    try {
      calendars = await getIt<DeviceCalendarApi>().calendars();
    } on PlatformException catch (e) {
      if (e.code != DeviceCalendarApi.permissionDenied) rethrow;
      return 'Calendar access not granted: adb shell pm grant '
          'io.github.fifothehein.tminus android.permission.READ_CALENDAR';
    }
    final visible = calendars.where((c) => c.visible).toList();
    if (visible.isEmpty) return 'No phone calendars';
    final source = await getIt<SourceAdmin>().addDeviceSource(
      calendar: visible.first,
    );
    return 'Added ${source.name} · ${await _sync()}';
  }

  Future<String> _removeAll() async {
    final all = await getIt<SourceRepository>().all();
    for (final s in all) {
      await getIt<SourceAdmin>().delete(s.id);
    }
    return 'Removed ${all.length} sources · ${await _sync()}';
  }

  /// Counts by type over the newest rows, e.g. after a force stop:
  /// `Last 5 history rows: missedSystem 3, fired 2`.
  Future<String> _history() async {
    final recent = await getIt<AlertHistoryRepository>().recent(limit: 20);
    if (recent.isEmpty) return 'No alert history yet';
    final counts = <String, int>{};
    for (final e in recent) {
      counts.update(e.type.name, (n) => n + 1, ifAbsent: () => 1);
    }
    final parts = [for (final c in counts.entries) '${c.key} ${c.value}'];
    return 'Last ${recent.length} history rows: ${parts.join(', ')}';
  }

  Future<String> _background() async {
    await getIt<SyncPlatform>().requestSync(SyncTrigger.manual.name);
    return 'Background sync queued (headless engine)';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final enabled = !_busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: enabled ? () => _run(_fastAlarms) : null,
              child: const Text('Fast alarms'),
            ),
            OutlinedButton(
              onPressed: enabled ? () => _run(_clearFastAlarms) : null,
              child: const Text('Clear fast alarms'),
            ),
            FilledButton.tonal(
              onPressed: enabled ? () => _run(_sync) : null,
              child: const Text('Sync now'),
            ),
            TextButton(
              onPressed: enabled ? () => _run(_background) : null,
              child: const Text('Background sync'),
            ),
            TextButton(
              onPressed: enabled ? () => _run(_history) : null,
              child: const Text('History'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('icsLinkField'),
          controller: _link,
          // A link has to reach Add feed exactly as typed, so the keyboard must
          // neither autocorrect nor suggest.
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'ICS link (debug)',
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: enabled ? () => _run(_addFeed) : null,
              child: const Text('Add feed'),
            ),
            OutlinedButton(
              onPressed: enabled ? () => _run(_addPhoneCalendar) : null,
              child: const Text('Add phone calendar'),
            ),
            TextButton(
              onPressed: enabled ? () => _run(_removeAll) : null,
              child: const Text('Remove all sources'),
            ),
          ],
        ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_status!, style: textTheme.bodySmall),
          ),
      ],
    );
  }
}
