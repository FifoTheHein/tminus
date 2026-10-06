import 'dart:convert';

import 'package:drift/drift.dart';

import '../model/alert.dart';
import '../model/alert_profile.dart';
import '../model/event_override.dart';
import 'app_database.dart';

class OverrideRepository {
  OverrideRepository(this._db);

  final AppDatabase _db;

  /// Rows whose custom alerts can't be read are left out (decision 15).
  Future<List<EventOverride>> all() async =>
      _readable(await _db.select(_db.overrides).get());

  Stream<List<EventOverride>> watchAll() =>
      _db.select(_db.overrides).watch().map(_readable);

  /// Null when there is no row, or its custom alerts can't be read.
  Future<EventOverride?> find(OverrideScope scope, String target) async {
    final row =
        await (_db.select(_db.overrides)..where(
              (o) => o.scope.equalsValue(scope) & o.target.equals(target),
            ))
            .getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

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

  static List<EventOverride> _readable(List<OverrideRow> rows) => [
    for (final r in rows) ?_fromRow(r),
  ];

  /// Null when the custom alerts can't be read.
  static EventOverride? _fromRow(OverrideRow r) {
    final List<AlertSpec>? customAlerts;
    try {
      customAlerts = r.customAlertsJson == null
          ? null
          : alertsFromJson(jsonDecode(r.customAlertsJson!));
    } on FormatException {
      return null;
    }
    return EventOverride(
      scope: r.scope,
      target: r.target,
      profileId: r.profileId,
      customAlerts: customAlerts,
      enabled: r.enabled,
    );
  }
}
