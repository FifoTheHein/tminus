import 'dart:convert';

import 'package:drift/drift.dart';

import '../model/alert_profile.dart';
import '../model/local_date.dart';
import '../model/quiet_state.dart';
import '../model/skip_filters.dart';
import 'app_database.dart';

/// Skip filters, the global default profile, the quiet mode and free-form
/// string settings.
class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  static const skipFiltersKey = 'skipFilters';
  static const globalDefaultKey = 'globalDefaultProfileId';

  Future<String?> getString(String name) => _byName(name).getSingleOrNull();

  Stream<String?> watchString(String name) => _byName(name).watchSingleOrNull();

  Future<void> setString(String name, String value) => _db
      .into(_db.settings)
      .insertOnConflictUpdate(
        SettingsCompanion.insert(name: name, value: value),
      );

  Future<SkipFilters> skipFilters() async =>
      _decodeSkip(await getString(skipFiltersKey));

  Stream<SkipFilters> watchSkipFilters() =>
      watchString(skipFiltersKey).map(_decodeSkip);

  Future<void> setSkipFilters(SkipFilters filters) =>
      setString(skipFiltersKey, jsonEncode(filters.toJson()));

  /// Meeting unless the user picked another default.
  Future<String> globalDefaultProfileId() async =>
      await getString(globalDefaultKey) ?? BuiltInProfiles.defaultId;

  Future<void> setGlobalDefaultProfileId(String profileId) =>
      setString(globalDefaultKey, profileId);

  Future<QuietState> quietState() async =>
      _decodeQuiet(await _quietRow().getSingleOrNull());

  Stream<QuietState> watchQuietState() =>
      _quietRow().watchSingleOrNull().map(_decodeQuiet);

  Future<void> setQuietState(QuietState state) {
    final row = switch (state) {
      QuietNone() => QuietStatesCompanion.insert(
        id: const Value(1),
        kind: QuietKind.none,
      ),
      MuteToday(:final untilUtc) => QuietStatesCompanion.insert(
        id: const Value(1),
        kind: QuietKind.muteToday,
        untilUtcMs: Value(untilUtc.millisecondsSinceEpoch),
      ),
      PausedUntil(:final untilUtc) => QuietStatesCompanion.insert(
        id: const Value(1),
        kind: QuietKind.pausedUntil,
        untilUtcMs: Value(untilUtc.millisecondsSinceEpoch),
      ),
      Vacation(:final firstDay, :final lastDay) => QuietStatesCompanion.insert(
        id: const Value(1),
        kind: QuietKind.vacation,
        firstDay: Value(firstDay.toIso()),
        lastDay: Value(lastDay.toIso()),
      ),
    };
    return _db
        .into(_db.quietStates)
        .insert(row, mode: InsertMode.insertOrReplace);
  }

  Selectable<String> _byName(String name) => (_db.select(
    _db.settings,
  )..where((s) => s.name.equals(name))).map((r) => r.value);

  SimpleSelectStatement<$QuietStatesTable, QuietStateRow> _quietRow() =>
      _db.select(_db.quietStates)..where((q) => q.id.equals(1));

  static SkipFilters _decodeSkip(String? json) => json == null
      ? const SkipFilters()
      : SkipFilters.fromJson((jsonDecode(json) as Map).cast<String, Object?>());

  /// A row that can't be read (e.g. a vacation with no dates) counts as
  /// "no quiet mode" rather than crashing the sync.
  static QuietState _decodeQuiet(QuietStateRow? r) {
    DateTime? until() => r?.untilUtcMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(r!.untilUtcMs!, isUtc: true);
    switch (r?.kind) {
      case QuietKind.muteToday when until() != null:
        return MuteToday(until()!);
      case QuietKind.pausedUntil when until() != null:
        return PausedUntil(until()!);
      case QuietKind.vacation when r!.firstDay != null && r.lastDay != null:
        try {
          final first = LocalDate.parse(r.firstDay!);
          final last = LocalDate.parse(r.lastDay!);
          if (first <= last) return Vacation(first, last);
        } on FormatException {
          // Fall through to none.
        }
        return const QuietNone();
      default:
        return const QuietNone();
    }
  }
}
