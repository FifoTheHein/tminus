import 'dart:convert';

import '../model/event_occurrence.dart';
import '../model/source_config.dart';
import '../storage/settings_repository.dart';
import '../storage/source_repository.dart';
import 'calendar_source.dart';

/// Debug-only "fast alarms" (spec §11): fake events a minute or two ahead
/// that go through the real sync, rules, plan and `applyPlan` path. Their
/// times are stored when created, so later syncs do not move them.
///
/// With the Meeting profile: two events start at +2 min (one coalesced alarm
/// at +1 min) and one with a Teams link starts at +12 min (heads-up at +2 min,
/// alarm at +11 min).
class FastAlarms {
  FastAlarms({required this.sources, required this.settings});

  static const sourceId = 'debug-fast-alarms';
  static const settingsKey = 'debug.fastAlarms';

  /// calendarOrange (dark), so fake events stand out from real calendars.
  static const color = 0xFFE89A5B;

  final SourceRepository sources;
  final SettingsRepository settings;

  /// Replaces any earlier fast alarms with three new events relative to [now].
  Future<void> create(DateTime now) async {
    final base = DateTime.fromMillisecondsSinceEpoch(
      now.millisecondsSinceEpoch ~/ 1000 * 1000,
      isUtc: true,
    );
    final soon = base.add(const Duration(minutes: 2));
    final later = base.add(const Duration(minutes: 12));
    final stamp = base.millisecondsSinceEpoch;
    final events = [
      _event('fast-$stamp-1', 'Fast alarm: standup', soon),
      _event('fast-$stamp-2', 'Fast alarm: 1:1', soon),
      _event(
        'fast-$stamp-3',
        'Fast alarm: Teams call',
        later,
        joinUrl: 'https://teams.microsoft.com/l/meetup-join/fast-alarms-test',
      ),
    ];
    await sources.save(
      const SourceConfig(
        id: sourceId,
        name: 'Fast alarms',
        color: color,
        kind: SourceKind.debug,
      ),
    );
    await settings.setString(settingsKey, jsonEncode(events));
  }

  /// Removes the source; its cached occurrences go with it.
  Future<void> clear() async {
    await sources.delete(sourceId);
    await settings.setString(settingsKey, '[]');
  }

  /// The stored events as occurrences of [source].
  Future<List<EventOccurrence>> occurrences(SourceConfig source) async {
    final json = await settings.getString(settingsKey);
    if (json == null) return const [];
    return [
      for (final e in jsonDecode(json) as List<Object?>)
        _occurrence((e! as Map).cast<String, Object?>(), source),
    ];
  }

  static Map<String, Object?> _event(
    String uid,
    String title,
    DateTime start, {
    String? joinUrl,
  }) => {
    'uid': uid,
    'title': title,
    'startUtcMs': start.millisecondsSinceEpoch,
    'endUtcMs': start.add(const Duration(minutes: 30)).millisecondsSinceEpoch,
    'joinUrl': joinUrl,
  };

  static EventOccurrence _occurrence(
    Map<String, Object?> e,
    SourceConfig source,
  ) {
    final start = DateTime.fromMillisecondsSinceEpoch(
      e['startUtcMs'] as int,
      isUtc: true,
    );
    return EventOccurrence(
      sourceId: source.id,
      uid: e['uid'] as String,
      originalStartUtc: start,
      title: e['title'] as String,
      joinUrl: e['joinUrl'] as String?,
      startUtc: start,
      endUtc: DateTime.fromMillisecondsSinceEpoch(
        e['endUtcMs'] as int,
        isUtc: true,
      ),
      busyStatus: BusyStatus.busy,
      calendarColor: source.color,
    );
  }
}

/// The fast-alarms events as a [CalendarSource].
class FastAlarmsSource implements CalendarSource {
  FastAlarmsSource({required this.config, required this.fastAlarms});

  final SourceConfig config;
  final FastAlarms fastAlarms;

  @override
  String get id => config.id;

  @override
  Future<SourceResult> fetch(FetchWindow window) async {
    final all = await fastAlarms.occurrences(config);
    return SourceFetched([
      for (final o in all)
        if (o.endUtc.isAfter(window.startUtc) &&
            o.startUtc.isBefore(window.endUtc))
          o,
    ]);
  }
}
