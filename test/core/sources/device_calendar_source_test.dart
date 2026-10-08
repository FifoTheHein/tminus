import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/engine/alarm_engine.dart';
import 'package:tminus/core/model/event_occurrence.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/model/sync_log_entry.dart';
import 'package:tminus/core/sources/calendar_source.dart';
import 'package:tminus/core/sources/device_calendar_api.dart';
import 'package:tminus/core/sources/device_calendar_source.dart';

import '../fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(AlarmEngine.methodChannelName);
  final calls = <MethodCall>[];

  const phone = SourceConfig(
    id: 'phone',
    name: 'Work calendar',
    color: 0xFF33AA66,
    kind: SourceKind.device,
    deviceCalendarId: '3',
  );
  final window = FetchWindow(
    DateTime.utc(2026, 10, 6, 7),
    DateTime.utc(2026, 10, 13, 7),
  );

  Map<String, Object?> row({
    String eventId = '10',
    int beginMs = 1791273600000, // 2026-10-06 08:00 UTC
    int endMs = 1791275400000, // 08:30
    bool allDay = false,
    String? title = 'Sprint planning',
    String? location,
    String? description,
    int availability = DeviceInstance.availabilityBusy,
    int selfAttendeeStatus = 1,
    int? status,
    String? originalId,
    int? originalInstanceTimeMs,
    bool recurring = false,
  }) => {
    'eventId': eventId,
    'calendarId': '3',
    'beginMs': beginMs,
    'endMs': endMs,
    'allDay': allDay,
    'title': title,
    'location': location,
    'description': description,
    'organizer': 'thandi@example.com',
    'availability': availability,
    'selfAttendeeStatus': selfAttendeeStatus,
    'status': status,
    'originalId': originalId,
    'originalInstanceTimeMs': originalInstanceTimeMs,
    'recurring': recurring,
  };

  void answer(Object? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return handler(call);
    });
  }

  DeviceCalendarSource source({SourceConfig config = phone}) =>
      DeviceCalendarSource(
        config: config,
        api: DeviceCalendarApi(),
        zone: johannesburg,
      );

  Future<List<EventOccurrence>> fetched(List<Map<String, Object?>> rows) async {
    answer((_) => rows);
    final r = await source().fetch(window);
    return (r as SourceFetched).occurrences;
  }

  tearDown(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('asks for this calendar over the fetch window', () async {
    await fetched([]);
    expect(calls.single.method, 'queryInstances');
    expect(calls.single.arguments, {
      'calendarIds': ['3'],
      'fromUtcMs': window.startUtc.millisecondsSinceEpoch,
      'toUtcMs': window.endUtc.millisecondsSinceEpoch,
    });
  });

  test('a one-off instance maps like an ICS one-off', () async {
    final o = (await fetched([
      row(
        location: 'Room 4',
        description: 'Join: https://teams.microsoft.com/l/meetup-join/abc',
      ),
    ])).single;
    expect(o.key, 'phone|10|2026-10-06T08:00:00.000Z');
    expect(o.seriesUid, isNull);
    expect(o.title, 'Sprint planning');
    expect(o.organizer, 'thandi@example.com');
    expect(o.joinUrl, 'https://teams.microsoft.com/l/meetup-join/abc');
    expect(o.startUtc, DateTime.utc(2026, 10, 6, 8));
    expect(o.endUtc, DateTime.utc(2026, 10, 6, 8, 30));
    expect(o.busyStatus, BusyStatus.busy);
    expect(o.declined, isFalse);
    expect(o.cancelled, isFalse);
    expect(o.calendarColor, 0xFF33AA66);
  });

  test('a moved instance of a series keeps the series key', () async {
    final series = (await fetched([row(recurring: true)])).single;
    final moved = (await fetched([
      row(
        eventId: '12',
        beginMs: 1791277200000, // moved to 09:00
        endMs: 1791279000000,
        originalId: '10',
        originalInstanceTimeMs: 1791273600000,
      ),
    ])).single;
    expect(series.seriesUid, '10');
    expect(moved.seriesUid, '10');
    expect(moved.key, series.key);
    expect(moved.startUtc, DateTime.utc(2026, 10, 6, 9));
  });

  test(
    'availability, declined and cancelled map to the skip-filter fields',
    () async {
      final rows = await fetched([
        row(eventId: '1', availability: DeviceInstance.availabilityFree),
        row(eventId: '2', availability: DeviceInstance.availabilityTentative),
        row(eventId: '3', availability: 9),
        row(eventId: '4', selfAttendeeStatus: DeviceInstance.attendeeDeclined),
        row(eventId: '5', status: DeviceInstance.statusCancelled),
      ]);
      expect(rows.map((o) => o.busyStatus).take(3), [
        BusyStatus.free,
        BusyStatus.tentative,
        BusyStatus.unknown,
      ]);
      expect(rows[3].declined, isTrue);
      expect(rows[4].cancelled, isTrue);
    },
  );

  test('an all-day instance starts at local midnight', () async {
    final o = (await fetched([
      row(
        allDay: true,
        beginMs: DateTime.utc(2026, 10, 7).millisecondsSinceEpoch,
        endMs: DateTime.utc(2026, 10, 8).millisecondsSinceEpoch,
      ),
    ])).single;
    expect(o.allDay, isTrue);
    expect(o.startUtc, DateTime.utc(2026, 10, 6, 22)); // 00:00 in Johannesburg
    expect(o.endUtc, DateTime.utc(2026, 10, 7, 22));
    expect(o.originalStartUtc, o.startUtc);
  });

  test(
    'a blank title reads "(No title)" and blank fields are dropped',
    () async {
      final o = (await fetched([row(title: '  ', location: ' ')])).single;
      expect(o.title, '(No title)');
      expect(o.location, isNull);
    },
  );

  test('a revoked permission and a removed calendar are reported', () async {
    answer((_) => throw PlatformException(code: 'permission_denied'));
    final denied = await source().fetch(window) as SourceFailed;
    expect(denied.outcome, SyncOutcome.calendarAccessDenied);

    answer((_) => throw PlatformException(code: 'calendar_missing'));
    final missing = await source().fetch(window) as SourceFailed;
    expect(missing.outcome, SyncOutcome.calendarMissing);

    answer((_) => throw PlatformException(code: 'engine_error'));
    expect(
      (await source().fetch(window) as SourceFailed).outcome,
      SyncOutcome.otherError,
    );
  });

  test('a source without a calendar id fails without a call', () async {
    answer((_) => []);
    final r = await source(
      config: const SourceConfig(
        id: 'phone',
        name: 'x',
        color: 0,
        kind: SourceKind.device,
      ),
    ).fetch(window);
    expect((r as SourceFailed).outcome, SyncOutcome.calendarMissing);
    expect(calls, isEmpty);
  });

  test('calendars() lists the phone calendars', () async {
    answer(
      (_) => [
        {
          'id': '3',
          'name': 'Work',
          'accountName': 'me@example.com',
          'color': 0xFF6AA0F5,
          'visible': true,
        },
      ],
    );
    final c = (await DeviceCalendarApi().calendars()).single;
    expect(calls.single.method, 'queryDeviceCalendars');
    expect(
      (c.id, c.name, c.accountName, c.color, c.visible),
      ('3', 'Work', 'me@example.com', 0xFF6AA0F5, true),
    );
  });
}
