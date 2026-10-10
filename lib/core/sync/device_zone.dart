import 'package:flutter/services.dart';
import 'package:timezone/timezone.dart' as tz;

import 'sync_platform.dart';

/// Sets `tz.local` to the device zone (Plan 2 left it at UTC). Without a
/// native side (tests, desktop), without an answer, or for a zone the
/// database does not know, `tz.local` stays as it is. Returns the zone now in
/// use. The time-zone database must already be loaded
/// (`configureDependencies` does it). Runs at startup and at the start of
/// every sync (decision 28), so it never throws.
Future<String> initDeviceZone(SyncPlatform platform) async {
  try {
    final id = await platform.deviceZone();
    if (id != null) tz.setLocalLocation(tz.getLocation(id));
  } on MissingPluginException {
    // Keep the current zone.
  } on PlatformException {
    // Keep the current zone.
  } on tz.LocationNotFoundException {
    // Keep the current zone.
  }
  return tz.local.name;
}
