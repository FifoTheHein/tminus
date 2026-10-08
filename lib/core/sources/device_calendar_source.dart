import 'package:flutter/services.dart';
import 'package:timezone/timezone.dart' as tz;

import '../model/source_config.dart';
import '../model/sync_log_entry.dart';
import 'calendar_source.dart';
import 'device_calendar_api.dart';
import 'occurrence_mapping.dart';

/// One Android calendar, read through `queryInstances` (spec §5).
class DeviceCalendarSource implements CalendarSource {
  DeviceCalendarSource({
    required this.config,
    required this.api,
    required this.zone,
  });

  final SourceConfig config;
  final DeviceCalendarApi api;

  /// The device zone, for all-day instances.
  final tz.Location zone;

  @override
  String get id => config.id;

  @override
  Future<SourceResult> fetch(FetchWindow window) async {
    final calendarId = config.deviceCalendarId;
    if (calendarId == null) {
      return const SourceFailed(
        SyncOutcome.calendarMissing,
        'No phone calendar is chosen for this source.',
      );
    }
    try {
      final instances = await api.instances(
        calendarIds: [calendarId],
        fromUtc: window.startUtc,
        toUtc: window.endUtc,
      );
      return SourceFetched([
        for (final i in instances) occurrenceFromDevice(i, config, zone),
      ]);
    } on PlatformException catch (e) {
      return switch (e.code) {
        DeviceCalendarApi.permissionDenied => const SourceFailed(
          SyncOutcome.calendarAccessDenied,
          'Calendar access was turned off.',
        ),
        DeviceCalendarApi.calendarMissing => const SourceFailed(
          SyncOutcome.calendarMissing,
          'This calendar was removed from the phone.',
        ),
        _ => SourceFailed(
          SyncOutcome.otherError,
          'Could not read the phone calendar (${e.code}).',
        ),
      };
    } on MissingPluginException {
      return const SourceFailed(
        SyncOutcome.otherError,
        'Phone calendars are not available on this platform.',
      );
    }
  }
}
