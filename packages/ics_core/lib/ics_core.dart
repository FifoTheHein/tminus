/// ICS text → event occurrences in a time window.
///
/// Pure Dart (no Flutter). The single entry point is [expandIcs].
///
/// Time zones: a TZID is resolved as a Windows zone name (CLDR windowsZones,
/// territory 001), then as an IANA name, then from the feed's own VTIMEZONE
/// ([IcsWarning.tzFromVtimezone]), then as the device zone
/// ([IcsWarning.tzFromDevice]). UTC values (`Z`) are UTC. Floating values
/// (no TZID, no `Z`) and all-day DATE values use the device zone, with no
/// warning. Recurrences are expanded in the event's own wall-clock zone, then
/// converted to UTC, so local meeting times survive DST changes.
library;

export 'src/event_fields.dart' show extractTeamsJoinUrl, isCancelledTitle;
export 'src/expand_ics.dart' show expandIcs;
export 'src/model.dart';
