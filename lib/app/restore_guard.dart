import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

import '../core/model/source_config.dart';
import '../core/sources/source_admin.dart';
import '../core/storage/app_database.dart';
import '../core/storage/app_settings.dart';
import '../core/storage/cache_database.dart';
import '../core/storage/source_repository.dart';
import '../core/sync/sync_platform.dart';

enum RestoreOutcome {
  /// The database was written on this installation, or nothing could be told
  /// (no native side, no readable id, a failed check): the app starts as it is.
  /// A check that cannot tell while a restore is still [unsafe] reports
  /// [unsafe] again instead, because it has not found the database safe.
  ///
  /// Also the answer of a guard that found a restore, but whose transaction
  /// found the new id already stored: another guard finished the restore, so
  /// this one did nothing and claims nothing.
  normal,

  /// First Plan 5 start here: a fresh install, or an upgrade that keeps all.
  firstStart,

  /// The database came from a backup of another installation, and this call
  /// made it safe.
  restored,

  /// The database came from a backup of another installation, but making it
  /// safe failed and was rolled back. Its sources are still enabled, so nothing
  /// may plan or fetch from it until a later run of the guard finishes the
  /// restore. Callers skip their sync on this, and [RestoreGuard.unsafe]
  /// remembers it for the syncs that start later in the same process.
  unsafe,
}

/// Tells a restored backup from an upgrade (Plan 5 decision 4) and makes a
/// restored database safe: nothing in it may ring or fetch until the user has
/// re-linked feeds and re-picked phone calendars. Runs at the start of `main()`
/// (in `startServices`) and of every headless sync (decision 4), before
/// anything plans or fetches, and again before a sync the screens ask for while
/// a restore is [unsafe]. Never throws.
///
/// A database with another installation's id is a restore. So is one with
/// sources and no id at all (a backup made before the id existed) on a phone
/// where the app was never updated ([SyncPlatform.neverUpdated]) and where
/// onboarding was never done (that build had no onboarding flag). With an
/// update behind it that same database is an upgrade and stays as it is, and
/// so does one that has been through onboarding: it is this phone's own, whose
/// first start only failed to store the id. A restore that was found and could
/// not be made safe stays a restore for as long as this guard remembers it
/// ([unsafe]): onboarding done here since does not turn it into a first start.
///
/// On a restore it clears what described the old phone: the occurrence cache,
/// `alert_history`, `sync_log` and every `sync.*` setting. The three tables
/// are in the cache database, which is never backed up (Plan 6 decision 4), so
/// a backup holds them only as the `legacy_*` tables that a build before Plan 6
/// left in the main database. The transaction drops those (and deletes the
/// `sync.*` setting that held the expected alerts, now a cache value), and the
/// cache database itself is emptied after it. It deletes the debug source,
/// disables every other source, marks it as needing its link or its calendar
/// and forgets its sync state (last error, last success, validators, empty
/// streak), sets `ui.restorePending`, clears `ui.onboardingDone` and stores the
/// new id. Profiles, rules, overrides, meeting links, the quiet mode and every
/// other setting (skip filters, default profile, theme, merge switch) stay.
///
/// The changes to the main database are made in one transaction with the new id
/// last. A restore that fails leaves the database as it was (only the debug
/// source, which is deleted first, is gone) and is reported as
/// [RestoreOutcome.unsafe]. The next run tries it again: the next start, the
/// next headless sync, or the next sync or re-plan the open app is asked for,
/// which run the guard first while [unsafe] is set and do nothing until it
/// reports anything else.
///
/// Nothing before that transaction may open the cache database. Opening it
/// moves the legacy tables' rows into it (`LegacyCacheMove`), and a second
/// isolate could then copy a restored backup's meetings into the cache after
/// this guard has emptied it. So the debug source is removed without clearing
/// its cached events (the `clearCache` argument of `SourceAdmin.delete`), and
/// the cache is emptied only when this call has made the restore, after the
/// transaction has committed. That is safe because a restore leaves every
/// source disabled, so no sync in another isolate fills the cache again.
///
/// The app's guard and a headless sync's can find the same restore together.
/// The transaction therefore reads the id again before it changes anything:
/// when it already is the new one, the other guard has finished, its work (and
/// whatever the user has set up since) stands, and this guard does nothing and
/// reports [RestoreOutcome.normal].
class RestoreGuard {
  RestoreGuard({
    required this.db,
    required this.cache,
    required this.platform,
    required this.appSettings,
    required this.sources,
    required this.admin,
  });

  final AppDatabase db;

  /// Only touched after the restore's transaction has committed, and only by
  /// the call that made the restore (see above).
  final CacheDatabase cache;
  final SyncPlatform platform;
  final AppSettings appSettings;
  final SourceRepository sources;
  final SourceAdmin admin;

  /// True after a [run] that ended in [RestoreOutcome.unsafe], until a later run
  /// finds the database safe. A later check that fails, or gets no answer from
  /// the native side, has not found it safe: it leaves this set and reports
  /// [RestoreOutcome.unsafe] again. The app has one guard (it is registered
  /// once), so `startServices` and the syncs the screens ask for share this:
  /// while it is set, those syncs run the guard again first and plan and fetch
  /// nothing unless it then reports a database that is safe.
  bool get unsafe => _unsafe;
  bool _unsafe = false;

  /// What a check that could not tell reports: a normal start, unless a restore
  /// found earlier is still unsafe. A failed check does not make that database
  /// safe, so it must not let the syncs through.
  RestoreOutcome get _unanswered =>
      _unsafe ? RestoreOutcome.unsafe : RestoreOutcome.normal;

  /// Checks for a restore and makes the database safe if there is one. Never
  /// throws.
  Future<RestoreOutcome> run() async {
    final outcome = await _check();
    _unsafe = outcome == RestoreOutcome.unsafe;
    return outcome;
  }

  Future<RestoreOutcome> _check() async {
    final String id;
    try {
      try {
        id = await platform.installId();
      } on MissingPluginException {
        return _unanswered; // tests, desktop
      }
      // A missing id is no evidence of a restore, and a restore deletes data.
      if (id.isEmpty) return _unanswered;
      final stored = await appSettings.installId();
      if (stored == id) return RestoreOutcome.normal;
      // A restore found earlier is not a first start however the database looks
      // now: an old backup (no id) stays one after the user has done onboarding
      // here, and goes straight to being made safe.
      if (stored == null && !_unsafe && !await _isOldBackupOnFreshInstall()) {
        await _firstStart(id);
        return RestoreOutcome.firstStart;
      }
    } on PlatformException catch (e) {
      debugPrint('Restore check failed: ${e.code}');
      return _unanswered;
    } catch (e) {
      debugPrint('Restore check failed: ${e.runtimeType}');
      return _unanswered;
    }
    // A restore has been found. From here a failure is not a normal start: the
    // database still holds the old phone's sources, which would fetch and ring.
    try {
      return await _makeSafe(id);
    } on PlatformException catch (e) {
      debugPrint('Making a restored backup safe failed: ${e.code}');
    } catch (e) {
      debugPrint('Making a restored backup safe failed: ${e.runtimeType}');
    }
    return RestoreOutcome.unsafe;
  }

  /// A backup made before the install id existed holds sources but no id, and
  /// no onboarding flag either (that build had none). On a phone where the app
  /// was installed and never updated that is a restore (an upgrade is an
  /// update, which leaves the app's first install time behind its last update
  /// time). Once onboarding is done here it is not: a fresh install whose
  /// first start failed to store the id looks the same until then. Asks the
  /// native side last, so only when there are sources and onboarding is not
  /// done.
  Future<bool> _isOldBackupOnFreshInstall() async =>
      (await sources.all()).isNotEmpty &&
      !await appSettings.onboardingDone() &&
      await platform.neverUpdated();

  /// A fresh install or the first Plan 5 start after an upgrade: the id is
  /// stored and nothing else changes, except that an upgrade (it has sources)
  /// has done its onboarding already.
  Future<void> _firstStart(String id) => db.transaction(() async {
    if ((await sources.all()).isNotEmpty) {
      await appSettings.setOnboardingDone(true);
    }
    await appSettings.setInstallId(id);
  });

  /// [RestoreOutcome.restored] when this call made the database safe, and
  /// [RestoreOutcome.normal] when another guard had already finished.
  Future<RestoreOutcome> _makeSafe(String id) async {
    // The debug source belongs to the old installation's debug panel. Its
    // cached events are not removed here: that would open the cache database
    // before the transaction below (see the class comment). The emptying of the
    // cache after the transaction covers them.
    for (final s in await sources.all()) {
      if (s.kind == SourceKind.debug) {
        await admin.delete(s.id, clearCache: false);
      }
    }
    // One transaction with the new id last, so a restore is done completely or
    // not at all: a stored id always means the database is safe, and a start
    // that failed half way would otherwise disable the sources again after the
    // user had set them up.
    final outcome = await db.transaction(() async {
      // The app's guard and a headless sync's can reach this point together.
      // The transaction takes the write lock as it starts, so the one that
      // comes second finds the first one's finished work here. Doing it again
      // would disable the sources the user has linked since and clear what
      // the sync has filled in. The answer is the one a start gets when the id
      // already matches: this call did no restore, so it does not claim one.
      if (await appSettings.installId() == id) return RestoreOutcome.normal;
      // A backup made before Plan 6 holds the old phone's cached meetings in
      // the tables that schema 3 set aside. They go in the same commit as the
      // new id, so `CacheDatabase` finds nothing to move from them. A backup
      // made since has no such tables.
      await db.customStatement('DROP TABLE IF EXISTS legacy_occurrences');
      await db.customStatement('DROP TABLE IF EXISTS legacy_alert_history');
      await db.customStatement('DROP TABLE IF EXISTS legacy_sync_log');
      await (db.delete(db.settings)..where((s) => s.name.like('sync.%'))).go();
      for (final s in await sources.all()) {
        final setup = switch (s.kind) {
          SourceKind.ics => SourceSetup.needsLink,
          SourceKind.device => SourceSetup.needsCalendar,
          SourceKind.debug => null,
        };
        if (setup == null) continue;
        await sources.save(s.copyWith(enabled: false));
        await appSettings.setSourceSetup(s.id, setup);
        // What the last fetches on the old phone said (error, times,
        // validators, empty streak) says nothing about this one.
        await sources.updateSyncState(s.id, SourceSyncState());
      }
      await appSettings.setRestorePending(true);
      await appSettings.setOnboardingDone(false);
      await appSettings.setInstallId(id);
      return RestoreOutcome.restored;
    });
    if (outcome == RestoreOutcome.restored) await _clearCache();
    return outcome;
  }

  /// Empties the cache database: what it holds is no restore's to keep. A
  /// restored phone normally has no such file, because it is never backed up or
  /// transferred, but one that ran the app before the restore may have rows.
  /// Only for the call that has just committed the restore. Never before the
  /// transaction, and never when another guard did the restore: the cache then
  /// holds what a sync wrote since.
  ///
  /// The restore has committed and made the database safe, so a failure here is
  /// logged by type and does not make the outcome [RestoreOutcome.unsafe]: a
  /// later run would find the new id and not come back to this.
  Future<void> _clearCache() async {
    try {
      await cache.transaction(() async {
        await cache.delete(cache.occurrences).go();
        await cache.delete(cache.alertHistory).go();
        await cache.delete(cache.syncLog).go();
        await cache.delete(cache.cacheValues).go();
      });
    } catch (e) {
      debugPrint('Emptying the cache after a restore failed: ${e.runtimeType}');
    }
  }
}
