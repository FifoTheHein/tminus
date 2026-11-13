import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/app/theme/tminus_theme.dart';
import 'package:tminus/core/engine/alarm_engine.dart';
import 'package:tminus/features/sources/calendar_picker.dart';

import '../harness.dart';
import 'source_test_support.dart';

// Every address here is invented. The owner addresses on Google's own domains
// have the shape the calendar provider uses for each kind of calendar.

const _google = 'com.google';
const _samsung = 'com.osp.app.signin';
const _outlook = 'com.microsoft.office.outlook.USER_ACCOUNT';
const _exchange = 'com.android.exchange';
const _local = 'LOCAL';
const _unknownType = 'com.example.sync';

const _alex = 'alex@example.com';
const _work = 'alex@work.example.com';
const _corp = 'alex@corp.example.com';
const _notes = 'notes@example.com';
const _sam = 'sam@example.com';
const _pat = 'pat@example.com';
const _holidayOwner = 'en.za#holiday@group.v.calendar.google.com';
const _birthdayAccount = 'local.samsungbirthday';

const _footnote =
    'Calendars marked Not synced have no events on this phone. Turn on sync '
    'for them in their calendar app, then come back.';

/// A calendar of the Google account [account]. Its owner is the account itself
/// unless [owner] says otherwise, which is how an account's own calendars read.
/// It is not the account's main calendar unless [primary] says so.
Map<String, Object?> _googleCalendar(
  String id,
  String name, {
  String account = _alex,
  String? owner,
  int? access,
  bool syncEvents = true,
  bool primary = false,
}) => phoneCalendar(
  id,
  name,
  account: account,
  accountType: _google,
  owner: owner ?? account,
  access: access,
  syncEvents: syncEvents,
  primary: primary,
);

/// One calendar of every group, listed out of order on purpose: the picker
/// puts the groups in their own order.
List<Map<String, Object?>> _everyKind() => [
  phoneCalendar('phone', 'Reminders', account: 'Device', accountType: _local),
  _googleCalendar(
    'holiday',
    'Bank holidays',
    owner: _holidayOwner,
    access: 200,
  ),
  _googleCalendar('shared', 'Sam Lee', owner: _sam, access: 200),
  phoneCalendar('other', 'Notes', account: _notes, accountType: _unknownType),
  phoneCalendar(
    'exchange',
    'Team calendar',
    account: _corp,
    accountType: _exchange,
  ),
  phoneCalendar(
    'outlook',
    'Calendar',
    account: _corp,
    accountType: _outlook,
    owner: _corp,
  ),
  phoneCalendar(
    'samsung',
    'My calendar',
    account: _alex,
    accountType: _samsung,
  ),
  _googleCalendar('work', 'Team planning', account: _work, primary: true),
  _googleCalendar('book', 'Book club'),
  _googleCalendar('home', 'Family', primary: true),
];

/// What [_everyKind] looks like: each heading and, under it, its rows. In the
/// first group the main calendar comes before 'Book club', which sorts first by
/// name.
const _everyKindOutline = <(String, List<String>)>[
  ('GOOGLE · $_alex', ['home', 'book']),
  ('GOOGLE · $_work', ['work']),
  ('SAMSUNG ACCOUNT · $_alex', ['samsung']),
  ('OUTLOOK · $_corp', ['outlook']),
  ('EXCHANGE · $_corp', ['exchange']),
  ('OTHER · $_notes', ['other']),
  ('SHARED WITH YOU', ['shared']),
  ('HOLIDAYS AND BIRTHDAYS', ['holiday']),
  ('ON THIS PHONE ONLY', ['phone']),
];

/// Boots the app's services, with [calendars] as what the phone answers. The
/// picker is shown by [_show].
Future<Harness> _boot(WidgetTester t, List<Map<String, Object?>> calendars) {
  tallScreen(t);
  return pumpApp(t, seed: (h) async => h.deviceCalendars = calendars);
}

/// The picker that chooses several calendars. [added] collects the ids that
/// each Add selected handed over.
Widget _many({Set<String> taken = const {}, List<List<String>>? added}) =>
    CalendarPicker.pickMany(
      takenIds: taken,
      onAdd: (calendars) async {
        added?.add([for (final c in calendars) c.id]);
        return true;
      },
    );

/// The picker that chooses one calendar. [picked] collects the ids chosen.
Widget _one({Set<String> taken = const {}, required List<String> picked}) =>
    CalendarPicker.pickOne(takenIds: taken, onPick: (c) => picked.add(c.id));

/// Shows [picker] on a screen of its own, in the app's theme. Call after
/// [_boot], which sets up the services it uses.
Future<void> _show(WidgetTester t, Widget picker) async {
  // The picker reads the phone when it starts, so one left from before must go
  // first, or it would not read again.
  await t.pumpWidget(const SizedBox());
  await t.pumpWidget(
    MaterialApp(
      theme: TMinusTheme.light(),
      home: Scaffold(body: SingleChildScrollView(child: picker)),
    ),
  );
  await t.pumpAndSettle();
}

/// Makes `queryDeviceCalendars` fail with [code]. The harness puts its own
/// handlers back at the end of the test.
void _failCalendarRead(String code) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel(AlarmEngine.methodChannelName),
        (call) async {
          if (call.method == 'queryDeviceCalendars') {
            throw PlatformException(code: code);
          }
          return null;
        },
      );
}

Finder _row(String id) => find.byKey(Key('calendar-$id'));

/// What is inside the row [id] and matches [matching].
Finder _inRow(String id, Finder matching) =>
    find.descendant(of: _row(id), matching: matching);

Checkbox _boxOf(WidgetTester t, String id) =>
    t.widget<Checkbox>(_inRow(id, find.byType(Checkbox)));

bool _canAddSelected(WidgetTester t) =>
    t.widget<FilledButton>(find.byKey(const Key('addSelected'))).onPressed !=
    null;

/// Checks that the picker is, from top to bottom, [outline]: each heading with
/// its rows under it, in that order. Everything in it must be on screen once.
void _expectOutline(WidgetTester t, List<(String, List<String>)> outline) {
  final names = <String>[];
  final tops = <double>[];
  for (final (heading, ids) in outline) {
    expect(find.text(heading), findsOneWidget, reason: heading);
    names.add(heading);
    tops.add(t.getTopLeft(find.text(heading)).dy);
    for (final id in ids) {
      expect(_row(id), findsOneWidget, reason: 'row $id');
      names.add('row $id');
      tops.add(t.getTopLeft(_row(id)).dy);
    }
  }
  for (var i = 1; i < tops.length; i++) {
    expect(
      tops[i],
      greaterThan(tops[i - 1]),
      reason: '${names[i - 1]} comes before ${names[i]}',
    );
  }
}

/// What the semantics tree says of the row [id]: the node that its [text] ends
/// up in, which is the whole row when the parts of the row are merged. Needs
/// semantics on.
SemanticsData _rowSemantics(WidgetTester t, String id, String text) =>
    t.getSemantics(_inRow(id, find.text(text))).getSemanticsData();

void main() {
  testWidgets('headings follow the group order', (t) async {
    final h = await _boot(t, _everyKind());
    await _show(t, _many());

    _expectOutline(t, _everyKindOutline);
    await h.dispose(t);
  });

  testWidgets('headings are announced as headers', (t) async {
    final stopSemantics = watchSemantics(t);
    final h = await _boot(t, _everyKind());
    await _show(t, _many());

    // The upper case text is for the eye. What is read out is the sentence
    // form, on a node that screen readers can jump to as a heading.
    const spoken = {
      'GOOGLE · $_alex': 'Google, $_alex',
      'GOOGLE · $_work': 'Google, $_work',
      'SAMSUNG ACCOUNT · $_alex': 'Samsung account, $_alex',
      'OUTLOOK · $_corp': 'Outlook, $_corp',
      'EXCHANGE · $_corp': 'Exchange, $_corp',
      'OTHER · $_notes': 'Other, $_notes',
      'SHARED WITH YOU': 'Shared with you',
      'HOLIDAYS AND BIRTHDAYS': 'Holidays and birthdays',
      'ON THIS PHONE ONLY': 'On this phone only',
    };
    final everything = semanticsText(t);
    for (final MapEntry(key: shown, value: label) in spoken.entries) {
      final node = t.getSemantics(find.text(shown)).getSemanticsData();
      expect(node.flagsCollection.isHeader, isTrue, reason: shown);
      expect(node.label, label, reason: shown);
      expect(everything, isNot(contains(shown)), reason: shown);
    }
    stopSemantics();
    await h.dispose(t);
  });

  testWidgets('a heading with no account name shows the kind only', (t) async {
    final stopSemantics = watchSemantics(t);
    final h = await _boot(t, [
      phoneCalendar('notes', 'Notes', accountType: _unknownType),
      // An empty name is as good as none.
      phoneCalendar('team', 'Team planning', account: '', accountType: _google),
      phoneCalendar('mine', 'My calendar', accountType: _samsung),
      phoneCalendar('inbox', 'Calendar', account: _corp, accountType: _outlook),
    ]);
    await _show(t, _many());

    // No dot and no name after the kind, so the text is the kind word alone.
    // The Outlook one is there to show what the others leave out.
    _expectOutline(t, [
      ('GOOGLE', ['team']),
      ('SAMSUNG ACCOUNT', ['mine']),
      ('OUTLOOK · $_corp', ['inbox']),
      ('OTHER', ['notes']),
    ]);
    const spoken = {
      'GOOGLE': 'Google',
      'SAMSUNG ACCOUNT': 'Samsung account',
      'OUTLOOK · $_corp': 'Outlook, $_corp',
      'OTHER': 'Other',
    };
    for (final MapEntry(key: shown, value: label) in spoken.entries) {
      final node = t.getSemantics(find.text(shown)).getSemanticsData();
      expect(node.flagsCollection.isHeader, isTrue, reason: shown);
      expect(node.label, label, reason: shown);
    }
    stopSemantics();
    await h.dispose(t);
  });

  testWidgets('the two My calendars sit under different headings', (t) async {
    // The incident. The Samsung account has the same address as a Google
    // account, and a calendar that lives only on the phone has the Samsung
    // calendar's name.
    final h = await _boot(t, [
      phoneCalendar(
        'samsung',
        'My calendar',
        account: _alex,
        accountType: _samsung,
        owner: _alex,
        primary: true,
      ),
      phoneCalendar(
        'phone',
        'My calendar',
        account: 'My calendar',
        accountType: _local,
      ),
      _googleCalendar('family', 'Family', primary: true),
    ]);
    await _show(t, _many());

    _expectOutline(t, [
      ('GOOGLE · $_alex', ['family']),
      ('SAMSUNG ACCOUNT · $_alex', ['samsung']),
      ('ON THIS PHONE ONLY', ['phone']),
    ]);
    // Each row has the name once. The row that lives on the phone has an
    // account called the same, which would make three if it were shown.
    expect(find.text('My calendar'), findsNWidgets(2));
    expect(_inRow('samsung', find.text('My calendar')), findsOneWidget);
    expect(_inRow('phone', find.text('My calendar')), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('only shared and holiday rows show their account', (t) async {
    final h = await _boot(t, [
      _googleCalendar('mine', 'Personal', primary: true),
      _googleCalendar('shared', 'Sam Lee', owner: _sam, access: 200),
      _googleCalendar(
        'holiday',
        'Public holidays',
        owner: _holidayOwner,
        access: 200,
      ),
      phoneCalendar(
        'dates',
        'Important dates',
        account: _birthdayAccount,
        accountType: _local,
      ),
      phoneCalendar(
        'reminders',
        'Reminders',
        account: 'Device',
        accountType: _local,
      ),
      phoneCalendar(
        'samsung',
        'Samsung calendar',
        account: 'lee@example.com',
        accountType: _samsung,
      ),
      phoneCalendar(
        'outlook',
        'Outlook calendar',
        account: _corp,
        accountType: _outlook,
        owner: _corp,
      ),
      phoneCalendar(
        'exchange',
        'Exchange calendar',
        account: 'alex@mail.example.com',
        accountType: _exchange,
      ),
      phoneCalendar(
        'other',
        'Other calendar',
        account: _notes,
        accountType: _unknownType,
      ),
    ]);
    await _show(t, _many());

    // These two come from several accounts, so the account is under the name.
    for (final id in ['shared', 'holiday']) {
      expect(_inRow(id, find.text(_alex)), findsOneWidget, reason: id);
    }
    // Everywhere else the heading says it, and the line would only repeat it.
    // A calendar that lives on the phone has an account name that means
    // nothing to the user, in the holidays group too.
    const bare = {
      'mine': _alex,
      'dates': _birthdayAccount,
      'reminders': 'Device',
      'samsung': 'lee@example.com',
      'outlook': _corp,
      'exchange': 'alex@mail.example.com',
      'other': _notes,
    };
    for (final MapEntry(key: id, value: account) in bare.entries) {
      expect(_row(id), findsOneWidget, reason: id);
      expect(_inRow(id, find.text(account)), findsNothing, reason: id);
      // No account stands alone anywhere on the screen.
      if (account != _alex) {
        expect(find.text(account), findsNothing, reason: id);
      }
    }
    expect(find.text(_alex), findsNWidgets(2));
    await h.dispose(t);
  });

  testWidgets('a not-synced calendar cannot be added', (t) async {
    final stopSemantics = watchSemantics(t);
    final h = await _boot(t, [
      _googleCalendar('family', 'Family', primary: true),
      _googleCalendar('planning', 'Team planning', syncEvents: false),
      _googleCalendar('sam', 'Sam Lee', owner: _sam, access: 200),
      _googleCalendar(
        'pat',
        'Pat Kim',
        owner: _pat,
        access: 200,
        syncEvents: false,
      ),
    ]);
    final added = <List<String>>[];
    await _show(t, _many(added: added));

    // The two with no events are marked, unticked and cannot be ticked. The
    // others can.
    for (final id in ['planning', 'pat']) {
      expect(_inRow(id, find.text('Not synced')), findsOneWidget, reason: id);
      expect(_boxOf(t, id).value, isFalse, reason: id);
      expect(_boxOf(t, id).onChanged, isNull, reason: id);
    }
    for (final id in ['family', 'sam']) {
      expect(_inRow(id, find.text('Not synced')), findsNothing, reason: id);
      expect(_boxOf(t, id).onChanged, isNotNull, reason: id);
    }

    // One node says it all to a screen reader: the name, that it is not synced,
    // and that nothing can be done with it.
    final blocked = _rowSemantics(t, 'planning', 'Team planning');
    expect(blocked.label.toLowerCase(), contains('team planning'));
    expect(blocked.label.toLowerCase(), contains('not synced'));
    expect(blocked.flagsCollection.isEnabled.toBoolOrNull(), isNot(isTrue));
    final open = _rowSemantics(t, 'family', 'Family');
    expect(open.label.toLowerCase(), isNot(contains('not synced')));

    // Tapping them does nothing: nothing is ticked, and Add selected stays off.
    for (final id in ['planning', 'pat']) {
      await t.tap(_row(id));
      await t.pump();
      expect(_boxOf(t, id).value, isFalse, reason: id);
    }
    expect(_canAddSelected(t), isFalse);

    // With the others ticked, Add selected hands over those and only those.
    for (final id in ['family', 'sam']) {
      await t.tap(_row(id));
      await t.pump();
    }
    expect(_canAddSelected(t), isTrue);
    await t.tap(find.byKey(const Key('addSelected')));
    await t.pumpAndSettle();

    expect(added, hasLength(1));
    expect(added.single, unorderedEquals(['family', 'sam']));
    stopSemantics();
    await h.dispose(t);
  });

  testWidgets('the footnote shows only with a not-synced calendar', (t) async {
    final h = await _boot(t, []);
    final note = find.byKey(const Key('notSyncedNote'));
    final synced = [
      _googleCalendar('family', 'Family', primary: true),
      _googleCalendar('book', 'Book club'),
    ];
    final notSynced = _googleCalendar(
      'planning',
      'Team planning',
      syncEvents: false,
    );

    // A calendar with no events on the phone: the line is there, with its
    // words, under the list and above the button.
    h.deviceCalendars = [...synced, notSynced];
    await _show(t, _many());
    expect(
      find.ancestor(of: find.text(_footnote), matching: note, matchRoot: true),
      findsOneWidget,
    );
    expect(
      t.getTopLeft(note).dy,
      greaterThan(t.getTopLeft(_row('planning')).dy),
      reason: 'under the list',
    );
    expect(
      t.getTopLeft(note).dy,
      lessThan(t.getTopLeft(find.byKey(const Key('addSelected'))).dy),
      reason: 'above Add selected',
    );

    // Every calendar has events: the list is there, and no line.
    h.deviceCalendars = synced;
    await _show(t, _many());
    expect(_row('book'), findsOneWidget);
    expect(note, findsNothing);
    expect(find.text(_footnote), findsNothing);

    // Nothing on the phone.
    h.deviceCalendars = [];
    await _show(t, _many());
    expect(find.text('No calendars found on this phone.'), findsOneWidget);
    expect(note, findsNothing);
    expect(find.text(_footnote), findsNothing);

    // Calendar access refused, with a calendar with no events on the phone.
    h.deviceCalendars = [...synced, notSynced];
    h.ui['requestPermission'] = (_) => 'denied';
    await _show(t, _many());
    expect(
      find.text(
        "T-Minus needs calendar access to read this phone's calendars.",
      ),
      findsOneWidget,
    );
    expect(note, findsNothing);
    expect(find.text(_footnote), findsNothing);

    // Access given, but the phone cannot answer.
    h.ui['requestPermission'] = (_) => 'granted';
    _failCalendarRead('boom');
    await _show(t, _many());
    expect(find.text("Could not read this phone's calendars."), findsOneWidget);
    expect(note, findsNothing);
    expect(find.text(_footnote), findsNothing);
    await h.dispose(t);
  });

  testWidgets('already added and not synced says both', (t) async {
    final h = await _boot(t, [
      _googleCalendar('family', 'Family', primary: true),
      _googleCalendar('planning', 'Team planning', syncEvents: false),
      _googleCalendar('book', 'Book club', syncEvents: false),
      _googleCalendar('reading', 'Reading list'),
    ]);
    await _show(t, _many(taken: {'family', 'planning'}));

    // One label each, and the one that is both is not two labels. A calendar
    // that is neither has none.
    const labels = ['Already added', 'Not synced', 'Already added, not synced'];
    const expected = {
      'family': 'Already added',
      'planning': 'Already added, not synced',
      'book': 'Not synced',
      'reading': null,
    };
    for (final MapEntry(key: id, value: shown) in expected.entries) {
      for (final label in labels) {
        expect(
          _inRow(id, find.text(label)),
          label == shown ? findsOneWidget : findsNothing,
          reason: '$id, $label',
        );
      }
    }

    // Already added wins for the box: ticked, and it cannot be unticked.
    expect(_boxOf(t, 'planning').value, isTrue);
    expect(_boxOf(t, 'planning').onChanged, isNull);
    // A calendar that is only not synced is unticked and cannot be ticked.
    expect(_boxOf(t, 'book').value, isFalse);
    expect(_boxOf(t, 'book').onChanged, isNull);
    expect(_boxOf(t, 'reading').onChanged, isNotNull);
    await h.dispose(t);
  });

  testWidgets('pickOne ignores a not-synced calendar', (t) async {
    final stopSemantics = watchSemantics(t);
    final h = await _boot(t, [
      _googleCalendar('family', 'Family', primary: true),
      _googleCalendar('planning', 'Team planning', syncEvents: false),
    ]);
    final picked = <String>[];
    await _show(t, _one(picked: picked));

    // The same groups, with the calendar that has no events marked.
    _expectOutline(t, [
      ('GOOGLE · $_alex', ['family', 'planning']),
    ]);
    expect(_inRow('planning', find.text('Not synced')), findsOneWidget);

    // A row that cannot be chosen is read out as not enabled here too, where
    // there is no checkbox to say so, and one that can be chosen as enabled.
    final blocked = _rowSemantics(t, 'planning', 'Team planning');
    expect(blocked.flagsCollection.isEnabled.toBoolOrNull(), isNot(isTrue));
    final open = _rowSemantics(t, 'family', 'Family');
    expect(open.flagsCollection.isEnabled.toBoolOrNull(), isTrue);

    await t.tap(_row('planning'));
    await t.pumpAndSettle();
    expect(picked, isEmpty);

    // The control: a calendar with events is chosen by the same tap.
    await t.tap(_row('family'));
    await t.pumpAndSettle();
    expect(picked, ['family']);
    stopSemantics();
    await h.dispose(t);
  });

  testWidgets('the phone choice says Google, Samsung, Outlook and other '
      'accounts', (t) async {
    tallScreen(t);
    final h = await pumpApp(t, location: '/sources/add');

    expect(find.text('Use a calendar on this phone'), findsOneWidget);
    expect(
      find.text('Google, Samsung, Outlook and other accounts'),
      findsOneWidget,
    );
    expect(find.text('Google, Samsung, Exchange accounts'), findsNothing);
    await h.dispose(t);
  });
}
