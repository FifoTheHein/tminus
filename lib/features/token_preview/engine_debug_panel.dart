import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/di.dart';
import '../../core/engine/alarm_engine.dart';
import '../../core/model/alert.dart';

/// Debug-only controls for the native alarm engine, so it can be exercised on a
/// device before the Health screen (Plan 5) and real sources (Plan 4) exist.
class EngineDebugPanel extends StatefulWidget {
  const EngineDebugPanel({super.key = const Key('engineDebugPanel')});

  @override
  State<EngineDebugPanel> createState() => _EngineDebugPanelState();
}

class _EngineDebugPanelState extends State<EngineDebugPanel>
    with WidgetsBindingObserver {
  static const _delays = <Duration>[
    Duration(seconds: 5),
    Duration(minutes: 1),
    Duration(minutes: 3),
  ];

  final AlarmEngine _engine = getIt<AlarmEngine>();
  late Future<EngineHealth> _health = _loadHealth();
  Duration _delay = _delays.first;
  String? _status;
  StreamSubscription<EngineEvent>? _events;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_events?.cancel());
    super.dispose();
  }

  /// Coming back to the app (e.g. from an alarm screen) shows what is scheduled now.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  /// The FutureBuilder subscribes only on the next frame; `ignore()` keeps an error that
  /// arrives before then from being reported as unhandled. The builder still sees it.
  Future<EngineHealth> _loadHealth() {
    final health = _engine.getHealth();
    // Live events only once the engine has answered: without the native side
    // (desktop, plain widget tests) the event stream would report an error.
    health.then((_) => _listenToEngine(), onError: (Object _) {});
    return health..ignore();
  }

  /// Every engine event (fired, snoozed, dismissed …) changes what is scheduled.
  void _listenToEngine() {
    if (_events != null || !mounted) return;
    _events = _engine.events.listen((_) => _reload(), onError: (Object _) {});
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _health = _loadHealth();
    });
  }

  /// Runs [action], shows its message (or the failure) and refreshes the health readout.
  Future<void> _run(Future<String> Function() action) async {
    String status;
    try {
      status = await action();
    } on PlatformException catch (e) {
      status = 'Failed: ${e.message ?? e.code}';
    } on MissingPluginException {
      status = 'Engine not available on this platform';
    }
    if (!mounted) return;
    setState(() {
      _status = status;
      _health = _loadHealth();
    });
  }

  Future<String> _test(AlertStrength strength) async {
    await _engine.testAlarm(strength, delay: _delay);
    return '${strength == AlertStrength.alarm ? 'Alarm' : 'Heads-up'} in ${_label(_delay)}';
  }

  Future<String> _drain() async {
    final events = await _engine.drainEvents();
    if (events.isEmpty) return 'No new engine events';
    return 'Drained ${events.length}: ${events.map((e) => e.type.name).join(', ')}';
  }

  Future<String> _notificationSettings() async {
    await _engine.openPermissionSettings(PermissionKind.notifications);
    return 'Opened notification settings';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<Duration>(
          segments: [
            for (final d in _delays)
              ButtonSegment(value: d, label: Text(_label(d))),
          ],
          selected: {_delay},
          onSelectionChanged: (selection) =>
              setState(() => _delay = selection.single),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonal(
              onPressed: () => _run(() => _test(AlertStrength.headsUp)),
              child: const Text('Test heads-up'),
            ),
            FilledButton(
              onPressed: () => _run(() => _test(AlertStrength.alarm)),
              child: const Text('Test alarm'),
            ),
            OutlinedButton(
              onPressed: () => _run(_notificationSettings),
              child: const Text('Notification settings'),
            ),
            TextButton(
              onPressed: () => _run(_drain),
              child: const Text('Drain events'),
            ),
          ],
        ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_status!, style: textTheme.bodySmall),
          ),
        const SizedBox(height: 12),
        Text('Next 5 scheduled', style: textTheme.titleMedium),
        const SizedBox(height: 4),
        FutureBuilder<EngineHealth>(
          future: _health,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text('Engine unavailable', style: textTheme.bodySmall);
            }
            final health = snapshot.data;
            if (health == null) {
              return Text('Loading…', style: textTheme.bodySmall);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (health.upcoming.isEmpty)
                  Text('Nothing scheduled', style: textTheme.bodySmall),
                for (final u in health.upcoming)
                  Text(
                    '${_when(u.fireAtUtc)} · ${u.strength == AlertStrength.alarm ? 'Alarm' : 'Heads-up'} · ${u.title}',
                    style: textTheme.bodyMedium,
                  ),
                const SizedBox(height: 4),
                Text(_flags(health), style: textTheme.bodySmall),
              ],
            );
          },
        ),
        TextButton(onPressed: _reload, child: const Text('Refresh')),
      ],
    );
  }

  static String _label(Duration d) =>
      d.inMinutes >= 1 ? '${d.inMinutes} min' : '${d.inSeconds} s';

  static String _when(DateTime utc) {
    final l = utc.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
  }

  static String _flags(EngineHealth h) => [
    'notifications ${h.notificationsEnabled ? 'on' : 'OFF'}',
    'full-screen ${h.canUseFullScreenIntent ? 'on' : 'OFF'}',
    'exact alarms ${h.canScheduleExactAlarms ? 'on' : 'OFF'}',
    'battery ${h.ignoringBatteryOptimizations ? 'unrestricted' : 'optimised'}',
    'alarm volume ${h.alarmStreamMuted ? 'MUTED' : 'on'}',
  ].join(' · ');
}
