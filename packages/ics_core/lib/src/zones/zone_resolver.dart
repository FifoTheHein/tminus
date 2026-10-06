import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../component.dart';
import '../model.dart';
import '../values.dart';
import 'wall_zone.dart';
import 'windows_zones.g.dart';

/// A zone plus the warning its resolution earned, if any.
class ResolvedZone {
  const ResolvedZone(this.zone, [this.warning]);

  final WallZone zone;
  final IcsWarning? warning;
}

/// Loads the full IANA database (`latest_all`) unless it is already loaded.
///
/// `latest_all` is needed because CLDR maps some Windows zones to old link
/// names such as `Asia/Calcutta`, which the smaller `latest` database lacks.
/// The check looks for such a link rather than keeping a flag, so it reloads
/// if other code later replaces the global database with a smaller one.
void ensureTimeZonesLoaded() {
  if (!tz.timeZoneDatabase.locations.containsKey('Asia/Calcutta')) {
    tzdata.initializeTimeZones();
  }
}

/// Picks the zone for each DATE-TIME in a feed.
///
/// Resolution order for a TZID:
/// 1. A Windows zone name (CLDR windowsZones, territory 001) → its IANA zone.
/// 2. An IANA zone name used directly.
/// 3. The feed's own VTIMEZONE with that TZID → [IcsWarning.tzFromVtimezone].
/// 4. The device zone → [IcsWarning.tzFromDevice].
///
/// Values ending in `Z` are UTC. Floating values (no TZID, no `Z`) and DATE
/// values use the device zone with no warning.
class ZoneResolver {
  ZoneResolver({required String deviceZone, required this.vtimezones})
    : device = IanaZone(_location(deviceZone));

  /// The feed's VTIMEZONE components by TZID.
  final Map<String, Component> vtimezones;
  final Map<String, ResolvedZone> _cache = {};

  /// The viewer's zone.
  final IanaZone device;

  static tz.Location _location(String deviceZone) {
    ensureTimeZonesLoaded();
    try {
      return tz.getLocation(deviceZone);
    } on tz.LocationNotFoundException {
      throw ArgumentError.value(
        deviceZone,
        'deviceZone',
        'is not an IANA time zone name',
      );
    }
  }

  /// The zone for one parsed value.
  ResolvedZone forTime(IcsTime time) {
    if (time.isUtc) {
      return const ResolvedZone(UtcZone());
    }
    if (time.isDate || time.tzid == null) {
      return ResolvedZone(device);
    }
    return resolve(time.tzid!);
  }

  /// The zone for a TZID, following the resolution order above.
  ResolvedZone resolve(String tzid) =>
      _cache.putIfAbsent(tzid, () => _resolveUncached(tzid.trim()));

  ResolvedZone _resolveUncached(String tzid) {
    final iana = windowsToIana[tzid] ?? tzid;
    try {
      return ResolvedZone(IanaZone(tz.getLocation(iana)));
    } on tz.LocationNotFoundException {
      // Not a known name; try the feed's definition.
    }
    final vtimezone = vtimezones[tzid];
    if (vtimezone != null) {
      try {
        return ResolvedZone(
          VtimezoneZone.fromComponent(vtimezone),
          IcsWarning.tzFromVtimezone,
        );
      } on FormatException {
        // Unusable definition; fall through to the device zone.
      }
    }
    return ResolvedZone(device, IcsWarning.tzFromDevice);
  }
}
