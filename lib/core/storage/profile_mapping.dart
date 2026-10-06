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

AlertProfile profileFromRow(ProfileRow r) => AlertProfile(
  id: r.id,
  name: r.name,
  alerts: alertsFromJson(jsonDecode(r.alertsJson) as List<Object?>),
  sound: SoundSettings.fromJson(
    (jsonDecode(r.soundJson) as Map).cast<String, Object?>(),
  ),
  ringsInQuietMode: r.ringsInQuietMode,
  builtIn: r.builtIn,
);
