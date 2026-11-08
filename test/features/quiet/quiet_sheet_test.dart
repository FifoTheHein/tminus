import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/app/di.dart';
import 'package:tminus/core/model/local_date.dart';
import 'package:tminus/core/model/quiet_state.dart';
import 'package:tminus/core/storage/settings_repository.dart';
import 'package:tminus/features/quiet/quiet_sheet.dart';

import '../../core/fixtures.dart';
import '../harness.dart';

/// The clock of the tests that name none: 09:27 in Johannesburg on Tue 6 Oct
/// 2026 (the harness's own default, passed on so that these tests do not rely
/// on it).
final _now = DateTime.utc(2026, 10, 6, 7, 27);

/// Boots the app on a phone-sized screen (the mockups' 420 x 880), so that the
/// whole sheet is on it.
Future<Harness> boot(
  WidgetTester t, {
  DateTime? now,
  Future<void> Function(Harness h)? seed,
}) {
  t.view.physicalSize = const Size(840, 1760);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  return pumpApp(t, now: now ?? _now, seed: seed);
}

/// Opens the sheet from a test host: the Agenda's moon button is another job's.
Future<void> openSheet(WidgetTester t) async {
  unawaited(showQuietSheet(t.element(find.byType(Scaffold).first)));
  await t.pumpAndSettle();
}

/// Lets a choice finish: the save, the re-plan timer and the sheet leaving.
Future<void> settle(WidgetTester t) async {
  await t.pumpAndSettle();
  await t.pump(const Duration(milliseconds: 1));
}

Future<void> tapKey(WidgetTester t, String key) async {
  final target = find.byKey(Key(key));
  await t.ensureVisible(target);
  await t.pump();
  await t.tap(target);
}

/// [what] inside the sheet only, so that nothing the screen behind it shows can
/// match.
Finder inSheet(Finder what) =>
    find.descendant(of: find.byType(QuietSheet), matching: what);

/// The stored quiet mode and the time it was last set, read outside the test's
/// fake clock.
Future<QuietState> storedState(WidgetTester t) async =>
    (await t.runAsync(() => getIt<SettingsRepository>().quietState()))!;

Future<DateTime?> storedChange(WidgetTester t) async => await t
    .runAsync<DateTime?>(() => getIt<SettingsRepository>().quietChangedAt());

/// A seed that stores [state] before the first frame, set at [at] (the
/// harness's clock when not given).
Future<void> Function(Harness) storing(QuietState state, {DateTime? at}) =>
    (h) => getIt<SettingsRepository>().setQuietStateAt(
      state,
      changedAtUtc: at ?? h.now,
    );

/// A settings repository whose quiet writes fail, with a message that must
/// never reach the screen or the log.
class _FailingSettings extends SettingsRepository {
  _FailingSettings(super.db);

  @override
  Future<void> setQuietStateAt(
    QuietState state, {
    required DateTime changedAtUtc,
  }) => throw StateError('https://secret.example/calendar.ics');
}

/// A settings repository that holds every quiet write until [gate] is
/// completed, and counts the writes that started.
class _SlowSettings extends SettingsRepository {
  _SlowSettings(super.db);

  final started = <QuietState>[];
  final gate = Completer<void>();

  @override
  Future<void> setQuietStateAt(
    QuietState state, {
    required DateTime changedAtUtc,
  }) async {
    started.add(state);
    await gate.future;
    await super.setQuietStateAt(state, changedAtUtc: changedAtUtc);
  }
}

void main() {
  group('pauseUntil', () {
    TimeOfDay at(int hour, int minute) => TimeOfDay(hour: hour, minute: minute);

    // The results are compared with plain UTC instants: a DateTime never equals
    // a TZDateTime, so these also pin that the result is a plain UTC instant.

    test('a time later today is today', () {
      expect(
        pauseUntil(at(14, 0), _now, johannesburg),
        DateTime.utc(2026, 10, 6, 12),
      );
    });

    test('a time that has passed is tomorrow', () {
      expect(
        pauseUntil(at(8, 0), _now, johannesburg),
        DateTime.utc(2026, 10, 7, 6),
      );
    });

    test('exactly now is tomorrow', () {
      expect(
        pauseUntil(at(9, 27), _now, johannesburg),
        DateTime.utc(2026, 10, 7, 7, 27),
      );
    });

    test('seconds count: the minute 30 s behind is tomorrow, 30 s ahead is '
        'today', () {
      expect(
        pauseUntil(
          at(9, 27),
          DateTime.utc(2026, 10, 6, 7, 27, 30),
          johannesburg,
        ),
        DateTime.utc(2026, 10, 7, 7, 27),
      );
      expect(
        pauseUntil(
          at(9, 27),
          DateTime.utc(2026, 10, 6, 7, 26, 30),
          johannesburg,
        ),
        DateTime.utc(2026, 10, 6, 7, 27),
      );
    });

    test('tomorrow after the last day of a month or a year is the 1st', () {
      // 22:00 on 31 Oct and on 31 Dec in Johannesburg.
      expect(
        pauseUntil(at(9, 0), DateTime.utc(2026, 10, 31, 20), johannesburg),
        DateTime.utc(2026, 11, 1, 7),
      );
      expect(
        pauseUntil(at(9, 0), DateTime.utc(2026, 12, 31, 20), johannesburg),
        DateTime.utc(2027, 1, 1, 7),
      );
    });

    test('a London DST change: the clocks going forward overnight', () {
      // Sat 28 Mar 2026 20:00 in London (GMT); the clocks go forward at 01:00
      // that night, so 09:00 on Sunday is 08:00 UTC, not 09:00.
      expect(
        pauseUntil(at(9, 0), DateTime.utc(2026, 3, 28, 20), london),
        DateTime.utc(2026, 3, 29, 8),
      );
    });

    test('a London DST change: the clocks going back overnight', () {
      // Sat 24 Oct 2026 21:00 in London (BST); the clocks go back at 02:00
      // that night, so 09:00 on Sunday is 09:00 UTC, not 08:00.
      expect(
        pauseUntil(at(9, 0), DateTime.utc(2026, 10, 24, 20), london),
        DateTime.utc(2026, 10, 25, 9),
      );
    });
  });

  group('the quiet sheet', () {
    testWidgets('Mute today writes MuteToday and asks for a re-plan', (
      t,
    ) async {
      final h = await boot(t);
      await openSheet(t);

      await tapKey(t, 'quiet-mute');
      await settle(t);

      // 07:00 the next local day: 05:00 UTC on the 7th in Johannesburg.
      expect(await storedState(t), MuteToday(DateTime.utc(2026, 10, 7, 5)));
      // Written with the time of the choice, so that an older tile tap loses.
      expect(await storedChange(t), _now);
      expect(h.replans, 1);
      expect(find.byType(QuietSheet), findsNothing);
      await h.dispose(t);
    });

    for (final hours in [1, 2, 4]) {
      testWidgets('$hours h pauses until now + $hours h', (t) async {
        final h = await boot(t);
        await openSheet(t);

        await tapKey(t, 'quiet-pause-${hours}h');
        await settle(t);

        expect(
          await storedState(t),
          PausedUntil(_now.add(Duration(hours: hours))),
        );
        expect(await storedChange(t), _now);
        expect(h.replans, 1);
        expect(find.byType(QuietSheet), findsNothing);
        await h.dispose(t);
      });
    }

    testWidgets('End is shown only while a mode is active, and ends it', (
      t,
    ) async {
      final h = await boot(
        t,
        seed: storing(PausedUntil(DateTime.utc(2026, 10, 6, 12))),
      );
      await openSheet(t);
      expect(find.byKey(const Key('quiet-end')), findsOneWidget);
      expect(inSheet(find.text('End quiet mode')), findsOneWidget);

      // The tap is a later moment than the sheet opening.
      h.now = DateTime.utc(2026, 10, 6, 7, 40);
      await tapKey(t, 'quiet-end');
      await settle(t);

      expect(await storedState(t), const QuietNone());
      expect(await storedChange(t), DateTime.utc(2026, 10, 6, 7, 40));
      expect(h.replans, 1);
      expect(find.byType(QuietSheet), findsNothing);

      // With no mode on, there is nothing to end.
      await openSheet(t);
      expect(find.byType(QuietSheet), findsOneWidget);
      expect(find.byKey(const Key('quiet-end')), findsNothing);
      expect(inSheet(find.text('End quiet mode')), findsNothing);
      await h.dispose(t);
    });

    testWidgets('the note is shown', (t) async {
      final h = await boot(t);
      await openSheet(t);

      expect(
        inSheet(find.text('Important events still ring (except Vacation).')),
        findsOneWidget,
      );
      await h.dispose(t);
    });

    // Beyond the plan's list. Each test below names the one-line change to
    // quiet_sheet.dart that must make it fail.

    // Change: any word of this copy.
    testWidgets('the sheet reads as the plan says', (t) async {
      final h = await boot(t);
      await openSheet(t);

      for (final copy in [
        'Quiet modes',
        'Mute today',
        'Until 07:00 tomorrow',
        'Pause until…',
        '1 h',
        '2 h',
        '4 h',
        'Pick a time',
        'Vacation',
        'Everything stays silent',
      ]) {
        expect(inSheet(find.text(copy)), findsOneWidget, reason: copy);
      }
      await h.dispose(t);
    });

    // Change: put a check on every card, on none, or on the wrong one; or
    // change the line each card shows for the mode that is on.
    final modesOn =
        <
          ({
            String name,
            QuietState state,
            String check,
            String status,
            String detail,
          })
        >[
          (
            name: 'Mute today',
            state: MuteToday(DateTime.utc(2026, 10, 7, 5)),
            check: 'mute',
            status: 'On · muted until tomorrow 07:00',
            detail: 'Until 07:00 tomorrow',
          ),
          (
            name: 'a pause',
            state: PausedUntil(DateTime.utc(2026, 10, 6, 12)),
            check: 'pause',
            status: 'On · paused until 14:00',
            detail: 'Resumes at 14:00',
          ),
          (
            name: 'a vacation',
            state: Vacation(LocalDate(2026, 10, 12), LocalDate(2026, 10, 16)),
            check: 'vacation',
            status: 'On · vacation Mon 12 Oct – Fri 16 Oct',
            detail: 'Mon 12 Oct – Fri 16 Oct',
          ),
        ];
    for (final mode in modesOn) {
      testWidgets('${mode.name} that is on has the check mark and is named', (
        t,
      ) async {
        final h = await boot(t, seed: storing(mode.state));
        await openSheet(t);

        for (final id in ['mute', 'pause', 'vacation']) {
          expect(
            find.byKey(Key('quiet-check-$id')),
            id == mode.check ? findsOneWidget : findsNothing,
            reason: 'the check mark of $id',
          );
        }
        expect(inSheet(find.byIcon(Icons.check_circle)), findsOneWidget);
        expect(
          t.widget<Text>(find.byKey(const Key('quiet-status'))).data,
          mode.status,
        );
        expect(inSheet(find.text(mode.detail)), findsOneWidget);
        expect(find.byKey(const Key('quiet-end')), findsOneWidget);
        await h.dispose(t);
      });
    }

    // Change: the 'Off' text, or the two lines that invite a choice.
    testWidgets('with no mode on the sheet says Off and marks nothing', (
      t,
    ) async {
      final h = await boot(t);
      await openSheet(t);

      expect(t.widget<Text>(find.byKey(const Key('quiet-status'))).data, 'Off');
      expect(inSheet(find.text('Choose how long')), findsOneWidget);
      expect(inSheet(find.text('Choose dates')), findsOneWidget);
      expect(inSheet(find.byIcon(Icons.check_circle)), findsNothing);
      expect(find.byKey(const Key('quiet-end')), findsNothing);
      await h.dispose(t);
    });

    // Change: stop calling isActive, so a stored mode counts however old.
    final modesOver = <({String name, QuietState state})>[
      (name: 'a mute', state: MuteToday(DateTime.utc(2026, 10, 6, 5))),
      (name: 'a pause', state: PausedUntil(DateTime.utc(2026, 10, 6, 7))),
      (
        name: 'a vacation',
        state: Vacation(LocalDate(2026, 10, 1), LocalDate(2026, 10, 5)),
      ),
    ];
    for (final mode in modesOver) {
      testWidgets('${mode.name} that has ended is not shown as on', (t) async {
        final h = await boot(t, seed: storing(mode.state));
        await openSheet(t);

        expect(inSheet(find.byIcon(Icons.check_circle)), findsNothing);
        expect(find.byKey(const Key('quiet-end')), findsNothing);
        expect(
          t.widget<Text>(find.byKey(const Key('quiet-status'))).data,
          'Off',
        );
        await h.dispose(t);
      });
    }

    // Change: leave out `useRootNavigator: true`. The sheet is opened from the
    // Agenda's own Scaffold, which is inside the Agenda tab's navigator.
    testWidgets('the sheet opens on the root navigator, over the tab bar', (
      t,
    ) async {
      final h = await boot(t);
      final host = t.element(find.byType(Scaffold).last);
      expect(
        Navigator.of(host),
        isNot(same(Navigator.of(host, rootNavigator: true))),
        reason: 'the host must be inside a tab for this test to mean anything',
      );

      unawaited(showQuietSheet(host));
      await t.pumpAndSettle();

      final inSheet = t.element(find.byType(QuietSheet));
      expect(
        Navigator.of(inSheet),
        same(Navigator.of(inSheet, rootNavigator: true)),
      );
      await h.dispose(t);
    });

    // Change: drop `alwaysUse24HourFormat: true` from the picker's builder.
    testWidgets('Pick a time opens a 24-hour picker, and cancelling it '
        'changes nothing', (t) async {
      final h = await boot(t);
      await openSheet(t);

      await tapKey(t, 'quiet-pause-pick');
      await t.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      expect(
        MediaQuery.alwaysUse24HourFormatOf(
          t.element(find.byType(TimePickerDialog)),
        ),
        isTrue,
      );

      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();

      expect(find.byType(TimePickerDialog), findsNothing);
      expect(find.byType(QuietSheet), findsOneWidget);
      expect(await storedState(t), const QuietNone());
      expect(await storedChange(t), isNull);
      expect(h.replans, 0);
      await h.dispose(t);
    });

    // Change: store `now + 1 h` instead of the picked time, or save without
    // the zone. The clock has seconds, so that the two differ.
    testWidgets('Pick a time pauses until the picked minute comes round', (
      t,
    ) async {
      // 09:27:30 in Johannesburg: the picker starts at 10:27.
      final now = DateTime.utc(2026, 10, 6, 7, 27, 30);
      final h = await boot(t, now: now);
      await openSheet(t);

      await tapKey(t, 'quiet-pause-pick');
      await t.pumpAndSettle();
      await t.tap(find.text('OK'));
      await settle(t);

      expect(
        await storedState(t),
        PausedUntil(DateTime.utc(2026, 10, 6, 8, 27)),
      );
      expect(await storedChange(t), now);
      expect(h.replans, 1);
      expect(find.byType(TimePickerDialog), findsNothing);
      expect(find.byType(QuietSheet), findsNothing);
      await h.dispose(t);
    });

    // Change: take the window from the UTC date, or a different length.
    testWidgets('Vacation opens a range picker from today in local days to a '
        'year ahead', (t) async {
      // 00:30 on the 7th in Johannesburg, still the 6th in UTC.
      final h = await boot(t, now: DateTime.utc(2026, 10, 6, 22, 30));
      await openSheet(t);

      await tapKey(t, 'quiet-vacation');
      await t.pumpAndSettle();

      final picker = t.widget<DateRangePickerDialog>(
        find.byType(DateRangePickerDialog),
      );
      expect(picker.firstDate, DateTime(2026, 10, 7));
      expect(picker.lastDate, DateTime(2027, 10, 7));
      expect(picker.currentDate, DateTime(2026, 10, 7));
      expect(picker.initialDateRange, isNull);
      await h.dispose(t);
    });

    // Change: hand the stored range to the picker as it is (it starts before
    // the first allowed day, which the picker asserts), or read the picked days
    // with an offset.
    testWidgets('saving the range picker stores its days, from today when the '
        'vacation began earlier', (t) async {
      final h = await boot(
        t,
        seed: storing(
          Vacation(LocalDate(2026, 10, 3), LocalDate(2026, 10, 9)),
          at: DateTime.utc(2026, 10, 1),
        ),
      );
      await openSheet(t);

      await tapKey(t, 'quiet-vacation');
      await t.pumpAndSettle();
      final picker = t.widget<DateRangePickerDialog>(
        find.byType(DateRangePickerDialog),
      );
      expect(
        picker.initialDateRange,
        DateTimeRange(start: DateTime(2026, 10, 6), end: DateTime(2026, 10, 9)),
      );

      await t.tap(find.text('Save'));
      await settle(t);

      expect(
        await storedState(t),
        Vacation(LocalDate(2026, 10, 6), LocalDate(2026, 10, 9)),
      );
      expect(await storedChange(t), _now);
      expect(h.replans, 1);
      expect(find.byType(QuietSheet), findsNothing);
      await h.dispose(t);
    });

    // Change: save when the picker is closed without a range.
    testWidgets('closing the range picker changes nothing', (t) async {
      final vacation = Vacation(
        LocalDate(2026, 10, 12),
        LocalDate(2026, 10, 16),
      );
      final earlier = DateTime.utc(2026, 10, 1);
      final h = await boot(t, seed: storing(vacation, at: earlier));
      await openSheet(t);

      await tapKey(t, 'quiet-vacation');
      await t.pumpAndSettle();
      await t.tap(find.byType(CloseButton));
      await t.pumpAndSettle();

      expect(find.byType(DateRangePickerDialog), findsNothing);
      expect(find.byType(QuietSheet), findsOneWidget);
      expect(await storedState(t), vacation);
      expect(await storedChange(t), earlier);
      expect(h.replans, 0);
      await h.dispose(t);
    });

    // Change: hand the failure to something that prints the error, or ask for
    // the re-plan whether or not the write worked.
    testWidgets('a failed save shows fixed text, logs only the type and plans '
        'nothing', (t) async {
      final h = await boot(
        t,
        seed: (h) async {
          await getIt.unregister<SettingsRepository>();
          getIt.registerSingleton<SettingsRepository>(_FailingSettings(h.db));
        },
      );
      await openSheet(t);

      // debugPrint goes back as soon as the choice is over, because
      // testWidgets checks it when the test body ends.
      final logged = <String>[];
      final realDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) => logged.add(message ?? '');
      try {
        await tapKey(t, 'quiet-mute');
        await settle(t);
      } finally {
        debugPrint = realDebugPrint;
      }

      expect(find.text('Could not change the quiet mode.'), findsOneWidget);
      expect(find.textContaining('secret'), findsNothing);
      expect(logged, contains('Could not change the quiet mode. (StateError)'));
      expect(logged.where((line) => line.contains('secret')), isEmpty);
      expect(h.replans, 0);
      expect(await storedState(t), const QuietNone());
      // The sheet closes, so that the message is not left behind it.
      expect(find.byType(QuietSheet), findsNothing);
      await h.dispose(t);
    });

    // Change: delete the `_busy` checks.
    testWidgets('a second tap while a save is under way saves nothing more', (
      t,
    ) async {
      late _SlowSettings slow;
      final h = await boot(
        t,
        seed: (h) async {
          await getIt.unregister<SettingsRepository>();
          slow = _SlowSettings(h.db);
          getIt.registerSingleton<SettingsRepository>(slow);
        },
      );
      await openSheet(t);

      await tapKey(t, 'quiet-mute');
      expect(slow.started, hasLength(1));
      await tapKey(t, 'quiet-mute');
      expect(slow.started, hasLength(1));

      slow.gate.complete();
      await settle(t);

      expect(slow.started, hasLength(1));
      expect(await storedState(t), MuteToday(DateTime.utc(2026, 10, 7, 5)));
      expect(h.replans, 1);
      expect(find.byType(QuietSheet), findsNothing);
      await h.dispose(t);
    });
  });
}
