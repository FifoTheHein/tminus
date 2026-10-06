import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Loads the full IANA database (`latest_all`) unless it is already loaded.
void ensureTimeZonesLoaded() {
  if (!tz.timeZoneDatabase.locations.containsKey('Asia/Calcutta')) {
    tzdata.initializeTimeZones();
  }
}
