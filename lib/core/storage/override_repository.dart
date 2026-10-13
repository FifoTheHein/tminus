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

  /// Rewrites the override that is in effect for a meeting (Plan 4b: the
  /// first of its lookup keys or series uids that has one) onto
  /// `targets.first`, and deletes the overrides on the other targets, in one
  /// transaction. [change] gets that effective override (null when there is
  /// none) and returns the new one, which must be for [scope] and
  /// `targets.first`: anything else throws an [ArgumentError], in release
  /// builds too, and changes nothing. So a field set on a copy key, a profile
  /// while merging was off, say, is carried over instead of being hidden behind
  /// the meeting key, and a cleared field cannot come back from a copy key
  /// (Plan 5 decision 9).
  ///
  /// [find] skips a row whose custom alerts cannot be read (decision 15), so
  /// such a row is never the effective one; it is still deleted from the other
  /// targets. A row with nothing set is not the effective one either: the rules
  /// drop it, so the lookup passes over it.
  Future<void> rewriteFor(
    OverrideScope scope,
    List<String> targets,
    EventOverride Function(EventOverride? effective) change,
  ) => _db.transaction(() async {
    final unique = targets.toSet().toList();
    EventOverride? effective;
    for (final t in unique) {
      final found = await find(scope, t);
      if (found != null && !found.isEmpty) {
        effective = found;
        break;
      }
    }
    final next = change(effective);
    if (next.scope != scope || next.target != unique.first) {
      throw ArgumentError(
        'rewriteFor: change must return an override for the scope and the '
        'first target',
      );
    }
    await save(next); // an empty override deletes the row
    for (final t in unique.skip(1)) {
      await delete(scope, t);
    }
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
