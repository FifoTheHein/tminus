import 'package:http/http.dart' as http;
import 'package:timezone/timezone.dart' as tz;

import '../model/source_config.dart';
import 'calendar_source.dart';
import 'device_calendar_api.dart';
import 'device_calendar_source.dart';
import 'fast_alarms.dart';
import 'feed_body_cache.dart';
import 'ics_feed_source.dart';
import 'source_secrets.dart';

/// Builds the [CalendarSource] for a stored [SourceConfig], once per sync.
class SourceFactory {
  SourceFactory({
    required this.client,
    required this.secrets,
    required this.bodies,
    required this.deviceCalendars,
    required this.fastAlarms,
  });

  final http.Client client;
  final SourceSecrets secrets;
  final FeedBodyCache bodies;
  final DeviceCalendarApi deviceCalendars;
  final FastAlarms fastAlarms;

  /// [state] supplies the ICS conditional-GET validators; [zone] is the
  /// device zone for floating and all-day times.
  CalendarSource create(
    SourceConfig config,
    SourceSyncState? state, {
    required tz.Location zone,
  }) => switch (config.kind) {
    SourceKind.ics => IcsFeedSource(
      config: config,
      previous: state,
      client: client,
      secrets: secrets,
      bodies: bodies,
      deviceZone: zone.name,
    ),
    SourceKind.device => DeviceCalendarSource(
      config: config,
      api: deviceCalendars,
      zone: zone,
    ),
    SourceKind.debug => FastAlarmsSource(
      config: config,
      fastAlarms: fastAlarms,
    ),
  };
}
