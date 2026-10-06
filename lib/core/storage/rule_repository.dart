import 'package:drift/drift.dart';

import '../model/keyword_rule.dart';
import 'app_database.dart';

class RuleRepository {
  RuleRepository(this._db);

  final AppDatabase _db;

  /// Sorted by position, then id.
  Future<List<KeywordRule>> all() => _ordered().map(_fromRow).get();

  Stream<List<KeywordRule>> watchAll() => _ordered().map(_fromRow).watch();

  Future<void> save(KeywordRule rule) =>
      _db.into(_db.keywordRules).insertOnConflictUpdate(_toCompanion(rule));

  Future<void> delete(String id) =>
      (_db.delete(_db.keywordRules)..where((r) => r.id.equals(id))).go();

  /// Sets each rule's position to its index in [idsInOrder] (drag to
  /// reorder). Ids not listed keep their position; unknown ids are ignored.
  Future<void> reorder(List<String> idsInOrder) => _db.transaction(() async {
    for (final (i, id) in idsInOrder.indexed) {
      await (_db.update(_db.keywordRules)..where((r) => r.id.equals(id))).write(
        KeywordRulesCompanion(position: Value(i)),
      );
    }
  });

  SimpleSelectStatement<$KeywordRulesTable, RuleRow> _ordered() =>
      _db.select(_db.keywordRules)..orderBy([
        (r) => OrderingTerm.asc(r.position),
        (r) => OrderingTerm.asc(r.id),
      ]);

  static KeywordRulesCompanion _toCompanion(KeywordRule r) =>
      KeywordRulesCompanion.insert(
        id: r.id,
        position: r.position,
        field: r.field,
        matchType: r.match,
        pattern: r.pattern,
        profileId: r.profileId,
      );

  static KeywordRule _fromRow(RuleRow r) => KeywordRule(
    id: r.id,
    position: r.position,
    field: r.field,
    match: r.matchType,
    pattern: r.pattern,
    profileId: r.profileId,
  );
}
