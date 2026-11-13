import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/sources/device_calendar_api.dart';
import 'package:tminus/features/sources/calendar_groups.dart';

// Every address here is invented. The owner addresses on Google's own domains
// have the shape the calendar provider uses for each kind of calendar.

const _google = 'com.google';
const _samsung = 'com.osp.app.signin';
const _outlook = 'com.microsoft.office.outlook.USER_ACCOUNT';
const _exchange = 'com.android.exchange';
const _local = 'LOCAL';
const _unknownType = 'com.example.sync';

const _alex = 'alex@example.com';
const _person = 'sam@example.com';
const _groupOwner = 'team@group.calendar.google.com';
const _importOwner = 'abc@import.calendar.google.com';
const _holidayOwner = 'en.za#holiday@group.v.calendar.google.com';
const _contactsOwner = 'abc#contacts@group.v.calendar.google.com';
const _birthdayAccount = 'local.samsungbirthday';

/// A phone calendar. What is not given is a synced, visible Google calendar of
/// [_alex] with no owner, no access level and no primary flag.
DeviceCalendar cal(
  String id, {
  String name = 'Calendar',
  String? account = _alex,
  String? type = _google,
  String? owner,
  int? access,
  bool? primary,
  bool sync = true,
  bool visible = true,
}) => DeviceCalendar(
  id: id,
  name: name,
  accountName: account,
  color: 0xFF6AA0F5,
  visible: visible,
  accountType: type,
  ownerAccount: owner,
  accessLevel: access,
  syncEvents: sync,
  primary: primary,
);

/// The one group that [c] makes when it is the only calendar.
CalendarGroup groupOf(DeviceCalendar c) {
  final groups = groupCalendars([c]);
  expect(groups, hasLength(1), reason: 'one calendar makes one group');
  expect(groups.single.calendars.map((x) => x.id), [c.id]);
  return groups.single;
}

CalendarGroupKind kindOf(DeviceCalendar c) => groupOf(c).kind;

/// The groups as one line each: kind, account name, then the ids of the rows.
List<String> outline(List<CalendarGroup> groups) => [
  for (final g in groups)
    '${g.kind.name} ${g.accountName ?? '-'}: '
        '${g.calendars.map((c) => c.id).join(' ')}',
];

void main() {
  group('kinds', () {
    test('each account type lands in its kind, with its account name', () {
      const kinds = {
        'com.google': CalendarGroupKind.google,
        'com.osp.app.signin': CalendarGroupKind.samsung,
        'com.microsoft.office.outlook.USER_ACCOUNT': CalendarGroupKind.outlook,
        'com.android.exchange': CalendarGroupKind.exchange,
        'com.google.android.gm.exchange': CalendarGroupKind.exchange,
        'com.samsung.android.exchange': CalendarGroupKind.exchange,
      };
      for (final MapEntry(key: type, value: kind) in kinds.entries) {
        final groups = groupCalendars([cal('1', type: type)]);
        expect(groups, hasLength(1), reason: type);
        expect(groups.single.kind, kind, reason: type);
        expect(groups.single.accountName, _alex, reason: type);
      }
    });

    test('an unknown account type and a null one land in other', () {
      // The second looks like a Google type but is not one.
      for (final type in const [_unknownType, 'com.google.example', null]) {
        final groups = groupCalendars([cal('1', type: type)]);
        expect(groups, hasLength(1), reason: '$type');
        expect(groups.single.kind, CalendarGroupKind.other, reason: '$type');
        expect(groups.single.accountName, _alex, reason: '$type');
      }
    });

    test('local calendars are phone only', () {
      final groups = groupCalendars([
        cal('1', type: _local, account: 'My calendar', name: 'My calendar'),
        cal('2', type: _local, account: 'Device', name: 'Reminders'),
        cal('3', type: _local, account: null, name: 'Notes'),
        cal('4', type: _local, account: '', name: 'Tasks'),
        // A person as owner does not make a calendar on the phone shared.
        cal('5', type: _local, account: 'Device', owner: _person, access: 200),
      ]);
      expect(groups, hasLength(1));
      expect(groups.single.kind, CalendarGroupKind.phoneOnly);
      expect(groups.single.accountName, isNull);
      expect(
        groups.single.calendars.map((c) => c.id),
        unorderedEquals(['1', '2', '3', '4', '5']),
      );
    });
  });

  test('same account name, different type, gives two groups', () {
    // The incident: a Samsung account and a Google account share an address,
    // and each holds a calendar called "My calendar".
    final groups = groupCalendars([
      cal('s', type: _samsung, name: 'My calendar'),
      cal('g', type: _google, name: 'My calendar'),
    ]);
    expect(outline(groups), [
      'google alex@example.com: g',
      'samsung alex@example.com: s',
    ]);
  });

  group('shared', () {
    test('a person is shared at any access level', () {
      for (final access in const [0, 200, 600, 700, null]) {
        expect(
          kindOf(cal('1', owner: _person, access: access)),
          CalendarGroupKind.shared,
          reason: 'access $access',
        );
      }
    });

    test('a group calendar is shared below owner access', () {
      for (final access in const [200, 600, 0, null]) {
        expect(
          kindOf(cal('1', owner: _groupOwner, access: access)),
          CalendarGroupKind.shared,
          reason: 'access $access',
        );
      }
    });

    test('a group calendar at owner access or above is not shared', () {
      // 700 is owner, 800 is root.
      for (final access in const [700, 800]) {
        expect(
          kindOf(cal('1', owner: _groupOwner, access: access)),
          CalendarGroupKind.google,
          reason: 'access $access',
        );
      }
    });

    test('a calendar subscribed by link is not shared', () {
      for (final access in const [200, 700, null]) {
        expect(
          kindOf(cal('1', owner: _importOwner, access: access)),
          CalendarGroupKind.google,
          reason: 'access $access',
        );
      }
    });

    test('an owner equal to the account is not shared, in any case', () {
      // Account first, then owner.
      const pairs = [
        (_alex, 'ALEX@EXAMPLE.COM'),
        ('Alex@Example.com', _alex),
        (_alex, ' alex@example.com '),
      ];
      for (final (account, owner) in pairs) {
        expect(
          kindOf(cal('1', account: account, owner: owner, access: 200)),
          CalendarGroupKind.google,
          reason: 'account "$account", owner "$owner"',
        );
      }
    });

    test('a null owner is not shared', () {
      expect(
        kindOf(cal('1', owner: null, access: 200)),
        CalendarGroupKind.google,
      );
    });

    test('a primary calendar is never shared, even with another owner', () {
      for (final owner in const [_person, _groupOwner]) {
        for (final access in const [200, 700, null]) {
          expect(
            kindOf(cal('1', owner: owner, access: access, primary: true)),
            CalendarGroupKind.google,
            reason: '$owner at $access',
          );
        }
      }
      // Only a true flag protects the calendar. A false one does not, and
      // neither does an unknown one when the owner is not the account.
      expect(
        kindOf(cal('1', owner: _person, primary: false)),
        CalendarGroupKind.shared,
      );
      expect(kindOf(cal('1', owner: _person)), CalendarGroupKind.shared);
    });

    test('an Outlook calendar at access 200 stays in outlook', () {
      // The Outlook app reports the account itself as the owner of every
      // calendar, a colleague's included, so both owners are tried.
      for (final owner in const [_alex, _person]) {
        expect(
          kindOf(cal('1', type: _outlook, owner: owner, access: 200)),
          CalendarGroupKind.outlook,
          reason: 'owner $owner',
        );
      }
    });

    test('only Google accounts have shared calendars', () {
      const kinds = <String?, CalendarGroupKind>{
        _outlook: CalendarGroupKind.outlook,
        _samsung: CalendarGroupKind.samsung,
        _exchange: CalendarGroupKind.exchange,
        _unknownType: CalendarGroupKind.other,
        null: CalendarGroupKind.other,
      };
      for (final MapEntry(key: type, value: kind) in kinds.entries) {
        for (final owner in const [_person, _groupOwner, _alex]) {
          expect(
            kindOf(cal('1', type: type, owner: owner, access: 200)),
            kind,
            reason: '$type with owner $owner',
          );
        }
      }
    });

    test(
      'a Google system calendar that is not a holiday list is not shared',
      () {
        // It ends with .calendar.google.com, so it is not a person's address,
        // and it is not an @group.calendar.google.com one either.
        expect(
          kindOf(
            cal(
              '1',
              owner: 'abc#weeknum@group.v.calendar.google.com',
              access: 200,
            ),
          ),
          CalendarGroupKind.google,
        );
      },
    );

    test('shared calendars of every Google account sit in one group', () {
      final groups = groupCalendars([
        cal('b', name: 'Sam', account: 'alex@work.example.com', owner: _person),
        cal('a', name: 'Pat', owner: 'pat@example.com'),
        cal('c', name: 'Mine', owner: _alex),
      ]);
      expect(outline(groups), ['google alex@example.com: c', 'shared -: a b']);
      expect(groups.last.accountName, isNull);
    });
  });

  group('holidays', () {
    test('a Google holiday calendar', () {
      final group = groupOf(cal('1', owner: _holidayOwner, access: 200));
      expect(group.kind, CalendarGroupKind.holidays);
      expect(group.accountName, isNull);
    });

    test('a Google contacts calendar', () {
      final group = groupOf(cal('1', owner: _contactsOwner, access: 200));
      expect(group.kind, CalendarGroupKind.holidays);
      expect(group.accountName, isNull);
    });

    test("Samsung's birthday calendar", () {
      final group = groupOf(
        cal('1', type: _local, account: _birthdayAccount, name: 'Dates'),
      );
      expect(group.kind, CalendarGroupKind.holidays);
      expect(group.accountName, isNull);
    });

    test('holidays and birthdays of every account sit in one group', () {
      final groups = groupCalendars([
        cal(
          'c',
          name: 'Samsung dates',
          type: _local,
          account: _birthdayAccount,
        ),
        cal(
          'b',
          name: 'Contacts',
          account: 'alex@work.example.com',
          owner: _contactsOwner,
        ),
        cal('a', name: 'Bank holidays', owner: _holidayOwner, access: 200),
        cal('d', name: 'Mine', owner: _alex),
      ]);
      expect(outline(groups), [
        'google alex@example.com: d',
        'holidays -: a b c',
      ]);
    });

    test('only the two Google owner endings and the Samsung account match', () {
      // A name is never read.
      expect(
        kindOf(cal('1', name: 'Public holidays', owner: _alex)),
        CalendarGroupKind.google,
      );
      expect(
        kindOf(cal('1', name: 'Birthdays', type: _outlook, owner: _alex)),
        CalendarGroupKind.outlook,
      );
      expect(
        kindOf(
          cal('1', name: 'Birthdays', type: _local, account: 'My calendar'),
        ),
        CalendarGroupKind.phoneOnly,
      );
      // No other account type is matched, whatever the owner.
      expect(
        kindOf(cal('1', type: _outlook, owner: _holidayOwner)),
        CalendarGroupKind.outlook,
      );
      expect(
        kindOf(cal('1', type: _samsung, owner: _contactsOwner)),
        CalendarGroupKind.samsung,
      );
      // The birthday account name counts on a LOCAL account only.
      expect(
        kindOf(cal('1', type: _google, account: _birthdayAccount)),
        CalendarGroupKind.google,
      );
    });
  });

  group('order', () {
    test('groups come in the documented order', () {
      final groups = groupCalendars([
        cal('p', type: _local, account: 'My calendar'),
        cal('h', owner: _holidayOwner),
        cal('s', owner: _person),
        cal('o', type: _unknownType, account: 'a@example.com'),
        cal('x', type: _exchange, account: 'a@example.com'),
        cal('l2', type: _outlook, account: 'b@example.com'),
        cal('l1', type: _outlook, account: 'a@example.com'),
        cal('m', type: _samsung, account: 'a@example.com'),
        cal('g2', account: 'b@example.com'),
        cal('g1', account: 'a@example.com'),
      ]);
      expect(outline(groups), [
        'google a@example.com: g1',
        'google b@example.com: g2',
        'samsung a@example.com: m',
        'outlook a@example.com: l1',
        'outlook b@example.com: l2',
        'exchange a@example.com: x',
        'other a@example.com: o',
        'shared -: s',
        'holidays -: h',
        'phoneOnly -: p',
      ]);
    });

    test('accounts of one kind sort by name, ignoring case', () {
      // In plain string order every capital sorts before every lower case
      // letter, which would put Bea and Zed ahead of amy.
      final groups = groupCalendars([
        cal('zed', account: 'Zed@example.com'),
        cal('amy', account: 'amy@example.com'),
        cal('bea', account: 'Bea@example.com'),
      ]);
      expect(outline(groups), [
        'google amy@example.com: amy',
        'google Bea@example.com: bea',
        'google Zed@example.com: zed',
      ]);
    });

    test('an account with no name sorts after the named ones of its kind', () {
      final groups = groupCalendars([
        cal('none', account: null),
        cal('zed', account: 'zed@example.com'),
        cal('amy', account: 'amy@example.com'),
        cal('samsung', type: _samsung, account: 'amy@example.com'),
      ]);
      expect(outline(groups), [
        'google amy@example.com: amy',
        'google zed@example.com: zed',
        'google -: none',
        'samsung amy@example.com: samsung',
      ]);
      expect(groups[2].accountName, isNull);
    });

    test(
      'an account with an empty name sorts after the named ones of its kind',
      () {
        final groups = groupCalendars([
          cal('blank', account: ''),
          cal('zed', account: 'zed@example.com'),
          cal('amy', account: 'amy@example.com'),
          cal('samsung', type: _samsung, account: 'amy@example.com'),
        ]);
        expect(
          [for (final g in groups) g.calendars.single.id],
          ['amy', 'zed', 'blank', 'samsung'],
        );
      },
    );

    test('names that differ only in case are two accounts', () {
      final groups = groupCalendars([
        cal('upper', account: 'Alex@example.com'),
        cal('zed', account: 'Zed@example.com'),
        cal('lower', account: 'alex@example.com'),
        cal('bea', account: 'bea@example.com'),
      ]);
      final ids = [for (final g in groups) g.calendars.single.id];
      expect(ids, hasLength(4));
      // Which of the two comes first is not part of the contract.
      expect(ids.take(2), unorderedEquals(['upper', 'lower']));
      expect(ids.skip(2), ['bea', 'zed']);
      expect(
        {for (final g in groups.take(2)) g.accountName},
        {'Alex@example.com', 'alex@example.com'},
      );
    });

    test('a primary calendar comes first', () {
      final rows = groupCalendars([
        cal('1', name: 'apple', primary: false),
        cal('2', name: 'Zebra', primary: true),
        cal('3', name: 'Banana'),
      ]).single.calendars;
      expect(rows.map((c) => c.id), ['2', '1', '3']);
    });

    test('an unknown primary flag falls back to owner equals account', () {
      final rows = groupCalendars([
        cal('1', name: 'apple'),
        // The owner is the account, in another case and with spaces.
        cal('2', name: 'Zebra', owner: ' Alex@Example.COM '),
        cal('3', name: 'Banana', owner: _importOwner),
        // A false flag is not overruled by the owner.
        cal('4', name: 'Yak', owner: _alex, primary: false),
      ]).single.calendars;
      expect(rows.map((c) => c.id), ['2', '1', '3', '4']);
    });

    test('rows sort by name ignoring case, then by id', () {
      final rows = groupCalendars([
        cal('d', name: 'Beta'),
        cal('c', name: 'Alpha'),
        cal('b', name: 'alpha'),
        cal('a', name: 'Beta'),
      ]).single.calendars;
      // Alpha and alpha are the same name, so the id decides: b before c,
      // although plain string order would put Alpha first.
      expect(rows.map((c) => c.id), ['b', 'c', 'a', 'd']);
    });

    // Beyond the spec's list: sync and visibility are not grouping facts, so a
    // row that is not synced or hidden sorts like any other.
    test('a calendar that is not synced or hidden keeps its place', () {
      final rows = groupCalendars([
        cal('1', name: 'Charlie', sync: false),
        cal('2', name: 'alpha', visible: false),
        cal('3', name: 'Bravo', sync: false, visible: false),
      ]).single.calendars;
      expect(rows.map((c) => c.id), ['2', '3', '1']);
    });

    // Beyond the spec's list: the rules leave no ties, so the input order
    // never shows in the result.
    test('the result does not depend on the order of the input', () {
      final bag = [
        cal('g1', account: 'a@example.com', name: 'Main', primary: true),
        cal('g2', account: 'a@example.com', name: 'Family'),
        cal('g3', account: 'b@example.com'),
        cal('s', owner: _person),
        cal('h', owner: _holidayOwner),
        cal('p', type: _local, account: 'My calendar'),
        cal('m', type: _samsung, account: 'a@example.com'),
        cal('l1', type: _outlook, account: 'c@example.com'),
        cal('l2', type: _outlook, account: 'c@example.com'),
      ];
      final expected = outline(groupCalendars(bag));
      expect(outline(groupCalendars(bag.reversed.toList())), expected);
      expect(
        outline(groupCalendars([...bag.skip(4), ...bag.take(4)])),
        expected,
      );
    });
  });

  group('shape', () {
    test('the account line shows only in shared and holidays', () {
      final shared = cal('shared', owner: _person);
      final holiday = cal('holiday', owner: _holidayOwner);
      final birthday = cal('birthday', type: _local, account: _birthdayAccount);
      final mine = cal('mine', owner: _alex);
      final phone = cal('phone', type: _local, account: 'My calendar');
      final groups = groupCalendars([shared, holiday, birthday, mine, phone]);

      void expectLine(CalendarGroupKind kind, DeviceCalendar c, bool shown) {
        final group = groups.singleWhere((g) => g.kind == kind);
        expect(group.calendars, contains(c), reason: '${c.id} is in $kind');
        expect(group.showAccountLineFor(c), shown, reason: c.id);
      }

      expectLine(CalendarGroupKind.shared, shared, true);
      expectLine(CalendarGroupKind.holidays, holiday, true);
      // A LOCAL account name means nothing to the user.
      expectLine(CalendarGroupKind.holidays, birthday, false);
      expectLine(CalendarGroupKind.google, mine, false);
      expectLine(CalendarGroupKind.phoneOnly, phone, false);
    });

    test('an account group never shows the account line', () {
      for (final type in const [
        _google,
        _samsung,
        _outlook,
        _exchange,
        _unknownType,
        null,
      ]) {
        final c = cal('1', type: type);
        expect(groupOf(c).showAccountLineFor(c), isFalse, reason: '$type');
      }
    });

    test('a calendar with no account name never shows the line', () {
      for (final account in const [null, '']) {
        final holiday = cal('1', account: account, owner: _holidayOwner);
        final group = groupOf(holiday);
        expect(group.kind, CalendarGroupKind.holidays);
        expect(group.showAccountLineFor(holiday), isFalse, reason: '$account');
      }
      final shared = cal('2', account: '', owner: _person);
      final group = groupOf(shared);
      expect(group.kind, CalendarGroupKind.shared);
      expect(group.showAccountLineFor(shared), isFalse);
    });

    test('a group with no calendars is left out', () {
      expect(groupCalendars([cal('1')]).map((g) => g.kind), [
        CalendarGroupKind.google,
      ]);
      // The only calendar of the account is a shared one: the account has
      // no group of its own.
      expect(groupCalendars([cal('1', owner: _person)]).map((g) => g.kind), [
        CalendarGroupKind.shared,
      ]);
    });

    test('an empty input gives no groups', () {
      expect(groupCalendars(const <DeviceCalendar>[]), isEmpty);
    });

    test('an account without a name is still an account group', () {
      final group = groupOf(cal('1', account: null));
      expect(group.kind, CalendarGroupKind.google);
      expect(group.accountName, isNull);
    });

    test('every calendar lands in exactly one group', () {
      final all = [
        cal('1'),
        cal('2', owner: _person),
        cal('3', owner: _groupOwner, access: 200),
        cal('4', owner: _groupOwner, access: 700),
        cal('5', owner: _holidayOwner),
        cal('6', owner: _contactsOwner),
        cal('7', owner: _importOwner),
        cal('8', type: _samsung),
        cal('9', type: _outlook, owner: _person, access: 200),
        cal('10', type: _local, account: 'My calendar'),
        cal('11', type: _local, account: _birthdayAccount),
        cal('12', type: null, account: null),
      ];
      final landed = [
        for (final g in groupCalendars(all)) ...g.calendars.map((c) => c.id),
      ];
      expect(landed, unorderedEquals(all.map((c) => c.id)));
    });

    // Beyond the spec's list: the picker passes its own state list, so
    // grouping must not sort it in place. An unmodifiable list throws if it does.
    test('it does not reorder the list it is given', () {
      final input = List<DeviceCalendar>.unmodifiable([
        cal('2', name: 'Zebra'),
        cal('1', name: 'Apple'),
        cal('3', account: 'zed@example.com'),
      ]);
      final groups = groupCalendars(input);
      expect(groups, hasLength(2));
      expect(input.map((c) => c.id), ['2', '1', '3']);
    });
  });
}
