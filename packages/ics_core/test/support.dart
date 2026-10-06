import 'dart:io';

import 'package:ics_core/ics_core.dart';

/// Reads `test/fixtures/<name>` (tests run from the package root).
String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

/// Expands a fixture for a viewer in Johannesburg (UTC+2, no DST).
IcsResult expandFixture(
  String name, {
  required DateTime from,
  required DateTime to,
  String deviceZone = 'Africa/Johannesburg',
}) => expandIcs(
  fixture(name),
  windowStartUtc: from,
  windowEndUtc: to,
  deviceZone: deviceZone,
);

/// Wraps VEVENT lines in a minimal VCALENDAR.
String calendar(String body) =>
    'BEGIN:VCALENDAR\r\nVERSION:2.0\r\n${body.trim().replaceAll('\n', '\r\n')}\r\nEND:VCALENDAR\r\n';

/// The occurrences of one UID.
List<IcsOccurrence> byUid(IcsResult r, String uid) =>
    r.occurrences.where((o) => o.uid == uid).toList();

/// Start times of one UID, as UTC ISO strings, for compact assertions.
List<String> startsOf(IcsResult r, String uid) => [
  for (final o in byUid(r, uid)) o.startUtc.toIso8601String(),
];
