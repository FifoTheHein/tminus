import 'package:flutter/services.dart';

import '../engine/alarm_engine.dart';

/// One calendar on the phone (`queryDeviceCalendars`).
class DeviceCalendar {
  const DeviceCalendar({
    required this.id,
    required this.name,
    this.accountName,
    required this.color,
    required this.visible,
  });

  factory DeviceCalendar.fromJson(Map<String, Object?> j) => DeviceCalendar(
    id: j['id'] as String,
    name: j['name'] as String,
    accountName: j['accountName'] as String?,
    color: j['color'] as int,
    visible: j['visible'] as bool,
  );

  final String id;
  final String name;
  final String? accountName;

  /// Opaque ARGB; pre-fills the colour when the user adds the source.
  final int color;
  final bool visible;
}

/// One row of `CalendarContract.Instances` (`queryInstances`).
class DeviceInstance {
  const DeviceInstance({
    required this.eventId,
    required this.calendarId,
    required this.beginMs,
    required this.endMs,
    required this.allDay,
    this.title,
    this.location,
    this.description,
    this.organizer,
    required this.availability,
    required this.selfAttendeeStatus,
    this.status,
    this.originalId,
    this.originalInstanceTimeMs,
    required this.recurring,
  });

  factory DeviceInstance.fromJson(Map<String, Object?> j) => DeviceInstance(
    eventId: j['eventId'] as String,
    calendarId: j['calendarId'] as String,
    beginMs: j['beginMs'] as int,
    endMs: j['endMs'] as int,
    allDay: j['allDay'] as bool,
    title: j['title'] as String?,
    location: j['location'] as String?,
    description: j['description'] as String?,
    organizer: j['organizer'] as String?,
    availability: j['availability'] as int,
    selfAttendeeStatus: j['selfAttendeeStatus'] as int,
    status: j['status'] as int?,
    originalId: j['originalId'] as String?,
    originalInstanceTimeMs: j['originalInstanceTimeMs'] as int?,
    recurring: j['recurring'] as bool,
  );

  static const availabilityBusy = 0;
  static const availabilityFree = 1;
  static const availabilityTentative = 2;
  static const attendeeDeclined = 2;
  static const statusCancelled = 2;

  final String eventId;
  final String calendarId;

  /// UTC ms. For all-day events these are UTC midnights of the dates.
  final int beginMs;
  final int endMs;
  final bool allDay;
  final String? title;
  final String? location;
  final String? description;
  final String? organizer;
  final int availability;
  final int selfAttendeeStatus;
  final int? status;

  /// Set on a moved or edited instance of a series: the series' event id and
  /// the instance's original start.
  final String? originalId;
  final int? originalInstanceTimeMs;

  /// The event has an RRULE or RDATE.
  final bool recurring;
}

/// The device-calendar calls Plan 4 adds to the `alarm_engine` channel
/// (roadmap §3). Errors arrive as [PlatformException]s with code
/// [permissionDenied] or [calendarMissing].
class DeviceCalendarApi {
  DeviceCalendarApi({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(AlarmEngine.methodChannelName);

  static const permissionDenied = 'permission_denied';
  static const calendarMissing = 'calendar_missing';

  final MethodChannel _channel;

  Future<List<DeviceCalendar>> calendars() async {
    final raw =
        await _channel.invokeListMethod<Object?>('queryDeviceCalendars') ??
        const [];
    return [
      for (final c in raw)
        DeviceCalendar.fromJson((c! as Map).cast<String, Object?>()),
    ];
  }

  Future<List<DeviceInstance>> instances({
    required List<String> calendarIds,
    required DateTime fromUtc,
    required DateTime toUtc,
  }) async {
    final raw =
        await _channel.invokeListMethod<Object?>('queryInstances', {
          'calendarIds': calendarIds,
          'fromUtcMs': fromUtc.millisecondsSinceEpoch,
          'toUtcMs': toUtc.millisecondsSinceEpoch,
        }) ??
        const [];
    return [
      for (final i in raw)
        DeviceInstance.fromJson((i! as Map).cast<String, Object?>()),
    ];
  }
}
