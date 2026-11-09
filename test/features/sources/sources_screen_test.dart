import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/app/di.dart';
import 'package:tminus/app/theme/tminus_theme.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/model/sync_log_entry.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/app_settings.dart';
import 'package:tminus/core/storage/profile_repository.dart';
import 'package:tminus/core/storage/settings_repository.dart';
import 'package:tminus/core/storage/source_repository.dart';
import 'package:tminus/core/storage/sync_log_repository.dart';
import 'package:tminus/core/sync/source_status.dart';
import 'package:tminus/features/common/status_tone.dart';
import 'package:tminus/features/settings/settings_screen.dart';
import 'package:tminus/features/sources/add_source_screen.dart';
import 'package:tminus/features/sources/source_detail_screen.dart';
import 'package:tminus/features/sources/sources_screen.dart';

import '../../core/fixtures.dart' show blue;
import '../../core/storage/test_database.dart';
import '../harness.dart';
import 'source_test_support.dart';

/// A loader that reads the sources, and then a restore lands: it returns the
/// sources as they were before the restore marked them, with the marker set.
class _RestoreLandsAfterRead extends SourceStatusLoader {
  _RestoreLandsAfterRead({
    required super.sources,
    required super.syncLog,
    required super.appSettings,
  });

  @override
  Future<List<SourceStatus>> all() async {
    final before = await super.all();
    await appSettings.setRestorePending(true);
    return before;
  }
}

void main() {
  Finder row(String id) => find.byKey(Key('source-$id'));

  testWidgets(
    'rows show the status line and dot for ok, stale, red, off and needs-link '
    'sources',
    (t) async {
      tallScreen(t);
      final now = DateTime.utc(2026, 10, 6, 7, 27);
      const redError =
          'Link no longer works (HTTP 404). The calendar may have been '
          'unpublished.';
      final h = await pumpApp(
        t,
        location: '/sources',
        now: now,
        seed: (h) async {
          final sources = getIt<SourceRepository>();
          Future<void> add(SourceConfig s, {SourceSyncState? state}) async {
            await sources.save(s);
            if (state != null) await sources.updateSyncState(s.id, state);
          }

          await add(
            icsSource(id: 'ok', name: 'A fine'),
            state: SourceSyncState(
              lastSuccessUtc: now.subtract(const Duration(minutes: 4)),
            ),
          );
          await add(
            icsSource(id: 'stale', name: 'B stale'),
            state: SourceSyncState(
              lastSuccessUtc: now.subtract(const Duration(hours: 3)),
            ),
          );
          await add(
            icsSource(id: 'red', name: 'C red'),
            state: SourceSyncState(
              lastSuccessUtc: now.subtract(const Duration(days: 2)),
              lastError: redError,
            ),
          );
          await getIt<SyncLogRepository>().add(
            SyncLogEntry(
              sourceId: 'red',
              atUtc: now,
              outcome: SyncOutcome.httpError,
              message: redError,
            ),
          );
          await add(icsSource(id: 'off', name: 'D off', enabled: false));
          await add(icsSource(id: 'new', name: 'E new', enabled: false));
          await getIt<AppSettings>().setSourceSetup(
            'new',
            SourceSetup.needsLink,
          );
          await add(
            phoneSource(id: 'phone', name: 'F phone'),
            state: SourceSyncState(
              lastSuccessUtc: now.subtract(const Duration(minutes: 1)),
            ),
          );
        },
      );

      // Each row: its name, its status line, and the dot of that line's tone.
      const expected = {
        'ok': ('A fine', 'Synced 4 min ago', StatusTone.ok),
        'stale': ('B stale', 'Feed stale · synced 3 h ago', StatusTone.warn),
        'red': ('C red', redError, StatusTone.error),
        'off': ('D off', 'Off', StatusTone.neutral),
        'new': ('E new', 'Needs its link', StatusTone.error),
        'phone': ('F phone', 'Synced 1 min ago', StatusTone.ok),
      };
      for (final MapEntry(key: id, value: (name, line, tone))
          in expected.entries) {
        expect(
          find.descendant(of: row(id), matching: find.text(name)),
          findsOneWidget,
          reason: id,
        );
        expect(
          find.descendant(of: row(id), matching: find.text(line)),
          findsOneWidget,
          reason: id,
        );
        final dot = t.widget<StatusDot>(
          find.descendant(of: row(id), matching: find.byType(StatusDot)),
        );
        expect(dot.tone, tone, reason: id);
      }

      // The line is grey while all is well and in the status colour when not.
      final theme = Theme.of(t.element(row('ok')));
      final colors = theme.extension<TMinusColors>()!;
      Color? lineColor(String id, String line) => t
          .widget<Text>(find.descendant(of: row(id), matching: find.text(line)))
          .style
          ?.color;
      expect(
        lineColor('ok', 'Synced 4 min ago'),
        theme.colorScheme.onSurfaceVariant,
      );
      expect(
        lineColor('stale', 'Feed stale · synced 3 h ago'),
        colors.statusWarn,
      );
      expect(lineColor('red', redError), colors.statusError);
      expect(lineColor('off', 'Off'), colors.tertiaryText);
      expect(lineColor('new', 'Needs its link'), colors.statusError);

      // A link for an ICS source, a phone for a phone calendar; and the rows
      // follow the repository's name order.
      expect(
        find.descendant(of: row('ok'), matching: find.byIcon(Icons.link)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row('phone'),
          matching: find.byIcon(Icons.phone_android),
        ),
        findsOneWidget,
      );
      final tops = [for (final id in expected.keys) t.getTopLeft(row(id)).dy];
      expect(tops, orderedEquals([...tops]..sort()));

      // Under the list: the note that links show masked.
      expect(
        find.text(
          'Links are stored on this phone only and always shown masked.',
        ),
        findsOneWidget,
      );
      await h.dispose(t);
    },
  );

  // Beyond the plan's list.

  testWidgets('a row opens its source, and Back returns to the list', (
    t,
  ) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources',
      seed: (h) => getIt<SourceRepository>().save(icsSource()),
    );

    await t.tap(row('ics-1'));
    await t.pumpAndSettle();
    expect(
      t.widget<SourceDetailScreen>(find.byType(SourceDetailScreen)).sourceId,
      'ics-1',
    );

    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.byType(SourceDetailScreen), findsNothing);
    expect(row('ics-1'), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('the Add source button opens Add source', (t) async {
    tallScreen(t);
    final h = await pumpApp(t, location: '/sources');

    await t.tap(find.text('Add source'));
    await t.pumpAndSettle();

    expect(find.byType(AddSourceScreen), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('the overflow menu opens Settings', (t) async {
    tallScreen(t);
    final h = await pumpApp(t, location: '/sources');

    await t.tap(find.byType(PopupMenuButton<String>));
    await t.pumpAndSettle();
    await t.tap(find.text('Settings'));
    await t.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('with no sources the list says so and offers Add a calendar', (
    t,
  ) async {
    tallScreen(t);
    final h = await pumpApp(t, location: '/sources');

    expect(find.text('No calendars yet.'), findsOneWidget);
    expect(
      find.text('Links are stored on this phone only and always shown masked.'),
      findsNothing,
    );
    await t.tap(find.text('Add a calendar'));
    await t.pumpAndSettle();

    expect(find.byType(AddSourceScreen), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets(
    'a source shows its own default profile, else the global default\'s',
    (t) async {
      tallScreen(t);
      final h = await pumpApp(
        t,
        location: '/sources',
        seed: (h) async {
          final sources = getIt<SourceRepository>();
          await sources.save(
            icsSource(id: 'a', name: 'A own', defaultProfileId: 'quick'),
          );
          await sources.save(icsSource(id: 'b', name: 'B global'));
        },
      );

      Finder profileLine(String id, String name) => find.descendant(
        of: row(id),
        matching: find.text('Default profile · $name'),
      );
      expect(profileLine('a', 'Quick'), findsOneWidget);
      expect(profileLine('b', 'Meeting'), findsOneWidget);

      // The global default changes: only the source without its own follows.
      await getIt<SettingsRepository>().setGlobalDefaultProfileId('important');
      await t.pumpAndSettle();

      expect(profileLine('a', 'Quick'), findsOneWidget);
      expect(profileLine('b', 'Important'), findsOneWidget);
      await h.dispose(t);
    },
  );

  testWidgets('the list follows the database', (t) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources',
      seed: (h) => getIt<SourceRepository>().save(icsSource()),
    );
    expect(row('late'), findsNothing);

    // A source that appears (a sync, an import, another screen), and one that
    // goes.
    await getIt<SourceRepository>().save(
      icsSource(id: 'late', name: 'Late arrival'),
    );
    await t.pumpAndSettle();
    expect(row('late'), findsOneWidget);

    await getIt<SourceRepository>().delete('ics-1');
    await t.pumpAndSettle();
    expect(row('ics-1'), findsNothing);
    expect(row('late'), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('the restore banner goes away once no source needs setup', (
    t,
  ) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources',
      seed: (h) async {
        await getIt<SourceRepository>().save(icsSource(enabled: false));
        await getIt<AppSettings>().setSourceSetup(
          'ics-1',
          SourceSetup.needsLink,
        );
        await getIt<AppSettings>().setRestorePending(true);
      },
    );
    expect(find.byKey(const Key('restoreBanner')), findsOneWidget);
    expect(find.text('Restored from a backup'), findsOneWidget);
    expect(
      find.text('Re-link each feed and choose each phone calendar.'),
      findsOneWidget,
    );
    expect(find.text('Needs its link'), findsOneWidget);

    // The feed is linked again: the source is on and its marker is gone.
    await getIt<SourceRepository>().save(icsSource());
    await getIt<AppSettings>().setSourceSetup('ics-1', SourceSetup.ready);
    await t.pumpAndSettle();

    expect(find.byKey(const Key('restoreBanner')), findsNothing);
    expect(await getIt<AppSettings>().restorePending(), isFalse);
    await h.dispose(t);
  });

  testWidgets('the restore banner stays while one source still needs setup', (
    t,
  ) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources',
      seed: (h) async {
        final sources = getIt<SourceRepository>();
        await sources.save(icsSource(id: 'a', name: 'A feed', enabled: false));
        await sources.save(
          phoneSource(id: 'b', name: 'B phone', enabled: false),
        );
        final app = getIt<AppSettings>();
        await app.setSourceSetup('a', SourceSetup.needsLink);
        await app.setSourceSetup('b', SourceSetup.needsCalendar);
        await app.setRestorePending(true);
      },
    );

    // One of the two is done.
    await getIt<SourceRepository>().save(icsSource(id: 'a', name: 'A feed'));
    await getIt<AppSettings>().setSourceSetup('a', SourceSetup.ready);
    await t.pumpAndSettle();

    expect(find.byKey(const Key('restoreBanner')), findsOneWidget);
    expect(await getIt<AppSettings>().restorePending(), isTrue);
    expect(find.text('Choose its calendar on this phone'), findsOneWidget);

    // The other one too.
    await getIt<SourceRepository>().save(phoneSource(id: 'b', name: 'B phone'));
    await getIt<AppSettings>().setSourceSetup('b', SourceSetup.ready);
    await t.pumpAndSettle();

    expect(find.byKey(const Key('restoreBanner')), findsNothing);
    expect(await getIt<AppSettings>().restorePending(), isFalse);
    await h.dispose(t);
  });

  group('SourcesController', () {
    late AppDatabase db;
    setUp(() => db = openTestDatabase());
    tearDown(() => db.close());

    SourcesController controller({bool showDebug = false}) {
      final settings = SettingsRepository(db);
      final appSettings = AppSettings(settings);
      return SourcesController(
        db: db,
        statuses: SourceStatusLoader(
          sources: SourceRepository(db),
          syncLog: SyncLogRepository(db),
          appSettings: appSettings,
        ),
        appSettings: appSettings,
        profiles: ProfileRepository(db),
        settings: settings,
        showDebug: showDebug,
      );
    }

    Future<List<String>> idsOf(SourcesController c) async {
      await c.reload();
      return [for (final item in c.items!) item.status.config.id];
    }

    test('the fast-alarms source is listed only in debug builds', () async {
      final sources = SourceRepository(db);
      await sources.save(icsSource());
      await sources.save(
        const SourceConfig(
          id: 'debug-fast',
          name: 'Fast alarms',
          color: blue,
          kind: SourceKind.debug,
        ),
      );
      final release = controller();
      final debug = controller(showDebug: true);
      addTearDown(release.dispose);
      addTearDown(debug.dispose);

      expect(await idsOf(release), ['ics-1']);
      expect(await idsOf(debug), ['debug-fast', 'ics-1']);
    });

    test('a restore marker with nothing left to set up is cleared', () async {
      // A restored database that held no calendars: the banner has nothing to
      // ask for.
      await AppSettings(SettingsRepository(db)).setRestorePending(true);
      final c = controller();
      addTearDown(c.dispose);

      await c.reload();

      expect(c.restorePending, isFalse);
      expect(
        await AppSettings(SettingsRepository(db)).restorePending(),
        isFalse,
      );
    });

    test('a restore that lands while the list loads keeps its marker', () async {
      await SourceRepository(db).save(icsSource());
      final settings = SettingsRepository(db);
      final appSettings = AppSettings(settings);
      final c = SourcesController(
        db: db,
        statuses: _RestoreLandsAfterRead(
          sources: SourceRepository(db),
          syncLog: SyncLogRepository(db),
          appSettings: appSettings,
        ),
        appSettings: appSettings,
        profiles: ProfileRepository(db),
        settings: settings,
      );
      addTearDown(c.dispose);

      await c.reload();

      // The marker was set after it was read, so it is neither shown yet nor
      // cleared on the strength of sources read before the restore marked them.
      expect(await appSettings.restorePending(), isTrue);
    });

    test('the marker stays for a source that waits for its calendar', () async {
      await SourceRepository(db).save(phoneSource(enabled: false));
      final app = AppSettings(SettingsRepository(db));
      await app.setSourceSetup('device-1', SourceSetup.needsCalendar);
      await app.setRestorePending(true);
      final c = controller();
      addTearDown(c.dispose);

      await c.reload();

      expect(c.restorePending, isTrue);
      expect(await app.restorePending(), isTrue);
    });
  });
}
