import 'dart:convert';

import '../model/alert.dart';
import '../model/alert_profile.dart';
import 'app_database.dart';

/// Row ↔ domain mapping for profiles. Shared by [AppDatabase] seeding and
/// `ProfileRepository`.
ProfilesCompanion profileToCompanion(AlertProfile p, {required int position}) =>
    ProfilesCompanion.insert(
      id: p.id,
      name: p.name,
      alertsJson: jsonEncode(alertsToJson(p.alerts)),
      soundJson: jsonEncode(p.sound.toJson()),
      ringsInQuietMode: p.ringsInQuietMode,
      builtIn: p.builtIn,
      position: position,
    );

/// Throws [FormatException] when [r]'s alert or sound JSON can't be read.
AlertProfile profileFromRow(ProfileRow r) => AlertProfile(
  id: r.id,
  name: r.name,
  alerts: alertsFromJson(jsonDecode(r.alertsJson)),
  sound: _soundFromJson(jsonDecode(r.soundJson)),
  ringsInQuietMode: r.ringsInQuietMode,
  builtIn: r.builtIn,
);

/// [profileFromRow] for reads that must not fail (decision 15): a row that
/// can't be read gives the built-in definition for a built-in id, and null
/// (leave it out) for any other profile.
AlertProfile? readableProfileFromRow(ProfileRow r) {
  try {
    return profileFromRow(r);
  } on FormatException {
    for (final p in BuiltInProfiles.all) {
      if (p.id == r.id) return p;
    }
    return null;
  }
}

SoundSettings _soundFromJson(Object? j) {
  if (j is Map<String, Object?> &&
      j['toneUri'] is String? &&
      j['vibrate'] is bool &&
      j['gradualVolume'] is bool &&
      j['ringTimeoutSec'] is int) {
    return SoundSettings.fromJson(j);
  }
  throw FormatException('Not sound settings', j);
}
