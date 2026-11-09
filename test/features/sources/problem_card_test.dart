import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/app/theme/tminus_theme.dart';
import 'package:tminus/core/engine/engine_models.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/model/sync_log_entry.dart';
import 'package:tminus/core/storage/app_settings.dart';
import 'package:tminus/core/sync/source_status.dart';
import 'package:tminus/core/sync/sync_service.dart';
import 'package:tminus/features/common/status_tone.dart';
import 'package:tminus/features/sources/problem_card.dart';

import 'source_test_support.dart';

// Beyond the plan's list: the plan names the card's titles and the Sync now
// texts, but tests them only through the screen.

Widget _host(Widget child) => MaterialApp(
  theme: TMinusTheme.dark(),
  home: Scaffold(body: child),
);

void main() {
  final now = DateTime.utc(2026, 10, 6, 7, 27);

  /// An ICS source whose latest sync ended in [outcome] (null: no log row).
  SourceStatus failing(
    SyncOutcome? outcome, {
    SourceSetup setup = SourceSetup.ready,
  }) => sourceStatusOf(
    config: icsSource(),
    state: SourceSyncState(lastError: 'The calendar could not be read.'),
    latest: outcome == null
        ? null
        : SyncLogEntry(sourceId: 'ics-1', atUtc: now, outcome: outcome),
    setup: setup,
    now: now,
  );

  test('the title follows the latest outcome', () {
    const titles = {
      SyncOutcome.httpError: 'Link no longer works',
      SyncOutcome.linkMissing: 'Link no longer works',
      SyncOutcome.parseError: 'The feed could not be read',
      SyncOutcome.networkError: "Can't reach the calendar",
      SyncOutcome.serverError: "Can't reach the calendar",
      SyncOutcome.calendarAccessDenied: 'Calendar access is off',
      SyncOutcome.calendarMissing: 'Calendar was removed',
      SyncOutcome.otherError: 'Something went wrong',
    };
    for (final MapEntry(key: outcome, value: title) in titles.entries) {
      expect(problemTitle(failing(outcome)), title, reason: outcome.name);
    }
    // An error that has no log row (a restore clears the log).
    expect(problemTitle(failing(null)), 'Something went wrong');
  });

  test('a source that waits for its link or calendar says what to do', () {
    expect(
      problemTitle(
        failing(SyncOutcome.httpError, setup: SourceSetup.needsLink),
      ),
      "Paste this calendar's link",
    );
    expect(
      problemTitle(
        failing(SyncOutcome.httpError, setup: SourceSetup.needsCalendar),
      ),
      'Choose this calendar on this phone',
    );
  });

  test('only a warning, an error or a missing setup gets a card', () {
    expect(
      {
        for (final h in SourceHealth.values)
          if (hasProblem(h)) h,
      },
      {SourceHealth.warning, SourceHealth.error, SourceHealth.needsSetup},
    );
  });

  group('what a sync tells about one source', () {
    /// A run whose alarms were applied unless [applied] says otherwise.
    SyncReport report(
      List<SourceSyncResult> sources, {
      SyncRunOutcome outcome = SyncRunOutcome.ok,
      bool applied = true,
    }) => SyncReport(
      trigger: SyncTrigger.manual,
      outcome: outcome,
      sources: sources,
      applied: applied
          ? const ApplyResult(armed: 1, cancelled: 0, kept: 0)
          : null,
    );

    test('Synced. when this source came through and the plan was applied', () {
      expect(
        sourceSyncMessage(
          report([const SourceSyncResult('ics-1', SyncOutcome.success)]),
          'ics-1',
        ),
        'Synced.',
      );
      // Another source's failure is not this source's.
      expect(
        sourceSyncMessage(
          report(const [
            SourceSyncResult('other', SyncOutcome.httpError, 'Not this one.'),
            SourceSyncResult('ics-1', SyncOutcome.success),
          ]),
          'ics-1',
        ),
        'Synced.',
      );
      // A source that came through with a note is still synced.
      expect(
        sourceSyncMessage(
          report(const [
            SourceSyncResult(
              'ics-1',
              SyncOutcome.emptyKept,
              'The calendar came back empty; kept its events.',
            ),
          ]),
          'ics-1',
        ),
        'Synced.',
      );
    });

    test('the failure of this source, with its words or without', () {
      expect(
        sourceSyncMessage(
          report(const [
            SourceSyncResult('other', SyncOutcome.httpError, 'Not this one.'),
            SourceSyncResult('ics-1', SyncOutcome.networkError, 'Offline.'),
          ], outcome: SyncRunOutcome.retry),
          'ics-1',
        ),
        'Offline.',
      );
      // A failure with no words still says something.
      expect(
        sourceSyncMessage(
          report(const [SourceSyncResult('ics-1', SyncOutcome.otherError)]),
          'ics-1',
        ),
        'This calendar could not be read.',
      );
    });

    test('the busy text when another sync held the lock', () {
      expect(
        sourceSyncMessage(
          report(const [], outcome: SyncRunOutcome.busy, applied: false),
          'ics-1',
        ),
        'Another sync is running. Try again in a minute.',
      );
    });

    test('a calendar that was read but whose alarms were not updated', () {
      // `applied` is null when the engine refused the plan: the calendar was
      // read, but nothing it said reached the alarms.
      expect(
        sourceSyncMessage(
          report(
            const [SourceSyncResult('ics-1', SyncOutcome.success)],
            outcome: SyncRunOutcome.retry,
            applied: false,
          ),
          'ics-1',
        ),
        'Synced, but the alarms could not be updated.',
      );
      // The source's own failure is the more useful thing to say.
      expect(
        sourceSyncMessage(
          report(
            const [
              SourceSyncResult('ics-1', SyncOutcome.httpError, 'Link is gone.'),
            ],
            outcome: SyncRunOutcome.retry,
            applied: false,
          ),
          'ics-1',
        ),
        'Link is gone.',
      );
    });

    test('a source the run did not report was not synced', () {
      // Off, or added after the run started: nothing was fetched for it.
      expect(
        sourceSyncMessage(
          report(const [SourceSyncResult('other', SyncOutcome.success)]),
          'ics-1',
        ),
        'Could not sync this calendar.',
      );
      expect(
        sourceSyncMessage(report(const []), 'ics-1'),
        'Could not sync this calendar.',
      );
    });
  });

  testWidgets('the card shows what is wrong, when it worked and what to do', (
    t,
  ) async {
    final pressed = <String>[];
    await t.pumpWidget(
      _host(
        ProblemCard(
          tone: StatusTone.error,
          icon: Icons.link_off,
          title: 'Link no longer works',
          body: 'It may have been reset in Outlook.',
          detail: 'Last worked Sun 4 Oct 18:02',
          actions: [
            ProblemAction(
              key: const Key('first'),
              label: 'Paste new link',
              onPressed: () => pressed.add('first'),
            ),
            ProblemAction(
              key: const Key('second'),
              label: 'How to find it',
              onPressed: () => pressed.add('second'),
            ),
          ],
        ),
      ),
    );

    expect(find.text('Link no longer works'), findsOneWidget);
    expect(find.text('It may have been reset in Outlook.'), findsOneWidget);
    expect(find.text('Last worked Sun 4 Oct 18:02'), findsOneWidget);
    // The first action is the filled one; the others are quieter.
    expect(
      find.descendant(
        of: find.byType(FilledButton),
        matching: find.text('Paste new link'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(TextButton),
        matching: find.text('How to find it'),
      ),
      findsOneWidget,
    );
    await t.tap(find.byKey(const Key('first')));
    await t.tap(find.byKey(const Key('second')));
    expect(pressed, ['first', 'second']);

    // Theme colours only: an error card sits on the error container.
    final scheme = Theme.of(t.element(find.byKey(const Key('problemCard'))))
        .colorScheme;
    final card = t.widget<Container>(find.byKey(const Key('problemCard')));
    expect((card.decoration! as BoxDecoration).color, scheme.errorContainer);
  });

  testWidgets('a warning card sits on the amber container', (t) async {
    await t.pumpWidget(
      _host(
        const ProblemCard(
          tone: StatusTone.warn,
          icon: Icons.cloud_off,
          title: "Can't reach the calendar",
          body: 'Could not reach the calendar server.',
        ),
      ),
    );

    final colors = TMinusColors.dark; // the host's theme is TMinusTheme.dark()
    final card = t.widget<Container>(find.byKey(const Key('problemCard')));
    expect(
      (card.decoration! as BoxDecoration).color,
      colors.statusWarnContainer,
    );
    // No detail and no actions: neither is drawn.
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
  });
}
