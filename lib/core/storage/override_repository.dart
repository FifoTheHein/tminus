import 'dart:convert';

import 'package:drift/drift.dart';

import '../model/alert_profile.dart';
import '../model/event_override.dart';
import 'app_database.dart';

class OverrideRepository {
  OverrideRepository(this._db);

  final AppDatabase _db;

  Future<List<EventOverride>> all() =>
      _db.select(_db.overrides).map(_fromRow).get();

  Stream<List<EventOverride>> watchAll() =>
      _db.select(_db.overrides).map(_fromRow).watch();

  Future<EventOverride?> find(OverrideScope scope, String target) =>
      (_db.select(
            _db.overrides,
          )..where((o) => o.scope.equalsValue(scope) & o.target.equals(target)))
          .map(_fromRow)
          .getSingleOrNull();

  /// Upserts; an empty override (nothing set) deletes the row instead.
  Future<void> save(EventOverride o) {
    if (o.isEmpty) return delete(o.scope, o.target);
    return _db
        .into(_db.overrides)
        .insertOnConflictUpdate(
          OverridesCompanion.insert(
            scope: o.scope,
            target: o.target,
            profileId: Value(o.profileId),
            customAlertsJson: Value(
              o.customAlerts == null
                  ? null
                  : jsonEncode(alertsToJson(o.customAlerts!)),
            ),
            enabled: Value(o.enabled),
          ),
        );
  }

  Future<void> delete(OverrideScope scope, String target) => (_db.delete(
    _db.overrides,
  )..where((o) => o.scope.equalsValue(scope) & o.target.equals(target))).go();

  /// The Agenda toggle: sets or clears `enabled` on the occurrence override
  /// for [occurrenceKey], keeping any profile or custom alerts it has.
  Future<void> setOccurrenceEnabled(String occurrenceKey, bool? enabled) =>
      _db.transaction(() async {
        final existing = await find(OverrideScope.occurrence, occurrenceKey);
        await save(
          EventOverride(
            scope: OverrideScope.occurrence,
            target: occurrenceKey,
            profileId: existing?.profileId,
            customAlerts: existing?.customAlerts,
            enabled: enabled,
          ),
        );
      });

  static EventOverride _fromRow(OverrideRow r) => EventOverride(
    scope: r.scope,
    target: r.target,
    profileId: r.profileId,
    customAlerts: r.customAlertsJson == null
        ? null
        : alertsFromJson(jsonDecode(r.customAlertsJson!) as List<Object?>),
    enabled: r.enabled,
  );
}
