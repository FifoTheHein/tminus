import '../../core/sources/device_calendar_api.dart';

/// What a group of phone calendars is (spec §4). The declaration order is the
/// order the groups come in (spec §4.3).
enum CalendarGroupKind {
  /// One Google account.
  google,

  /// One Samsung account.
  samsung,

  /// One account of the Outlook app.
  outlook,

  /// One Exchange account.
  exchange,

  /// One account of any other type, or of none the app knows.
  other,

  /// Other people's Google calendars (spec §4.2). Holds calendars from
  /// several accounts.
  shared,

  /// Holiday and birthday calendars (spec §4.2). Holds calendars from several
  /// accounts.
  holidays,

  /// Calendars that live only on this phone (spec §4.2). Holds calendars from
  /// several accounts.
  phoneOnly,
}

/// The calendars that sit under one heading, in the order to show them (spec
/// §4.3).
///
/// The widget builds the heading text from [kind] and [accountName], so no
/// text the UI owns lives here.
class CalendarGroup {
  const CalendarGroup({
    required this.kind,
    this.accountName,
    required this.calendars,
  });

  final CalendarGroupKind kind;

  /// The account's name as the provider gave it, so it can be null or empty.
  /// Always null for [CalendarGroupKind.shared], [CalendarGroupKind.holidays]
  /// and [CalendarGroupKind.phoneOnly].
  final String? accountName;

  /// The primary calendar first, then by name, then by id (spec §4.3).
  final List<DeviceCalendar> calendars;

  /// Whether [c]'s row shows its account name under its own name (spec §4.3).
  ///
  /// Only the groups that mix accounts do: **Shared with you**, and **Holidays
  /// and birthdays** except for a LOCAL calendar, whose account name means
  /// nothing to the user. A row in an account group or in **On this phone
  /// only** leaves it out. A calendar with no account name has no line to show.
  bool showAccountLineFor(DeviceCalendar c) {
    final account = c.accountName;
    if (account == null || account.isEmpty) return false;
    return kind == CalendarGroupKind.shared ||
        (kind == CalendarGroupKind.holidays && c.accountType != _localType);
  }
}

/// Sorts the phone's calendars into groups (spec §4).
///
/// Each calendar lands in exactly one group, and the first rule that matches
/// decides which (spec §4.2): holidays and birthdays, then shared with you
/// (Google only), then on this phone only (every other LOCAL calendar), then
/// its account group (spec §4.1). An account is the pair of account type and
/// account name, matched exactly.
///
/// The groups come in [CalendarGroupKind] order, the accounts of one kind by
/// name; the rows by primary first, then name, then id (spec §4.3). Accounts
/// whose names differ only in case tie, and stay in the order their calendars
/// arrived in. A group with no calendars is left out, so an empty list gives
/// an empty list.
///
/// It reads [DeviceCalendar.ownerAccount] to decide, and neither keeps nor
/// shows it.
List<CalendarGroup> groupCalendars(List<DeviceCalendar> calendars) {
  final bySlot = <_Slot, List<DeviceCalendar>>{};
  for (final c in calendars) {
    bySlot.putIfAbsent(_slotOf(c), () => []).add(c);
  }
  // `sort` is not stable, so a tie is settled by the order the group arrived in.
  final slots = bySlot.keys.toList();
  final arrival = {for (var i = 0; i < slots.length; i++) slots[i]: i};
  slots.sort((a, b) {
    final bySortOrder = _compareSlots(a, b);
    return bySortOrder != 0 ? bySortOrder : arrival[a]!.compareTo(arrival[b]!);
  });
  return [
    for (final slot in slots)
      CalendarGroup(
        kind: slot.kind,
        accountName: slot.accountName,
        calendars: bySlot[slot]!..sort(_compareRows),
      ),
  ];
}

// Account types as `Calendars.ACCOUNT_TYPE` reports them (spec §4.1).
const _googleType = 'com.google';
const _localType = 'LOCAL';

/// The account Samsung keeps "Contacts' important dates" under (spec §4.2).
const _samsungBirthdayAccount = 'local.samsungbirthday';

/// The kind of each known account type; any other type, or none, is
/// [CalendarGroupKind.other]. `LOCAL` is not here because a LOCAL calendar
/// never reaches the account groups (spec §4.2).
const _kindByAccountType = <String, CalendarGroupKind>{
  _googleType: CalendarGroupKind.google,
  'com.osp.app.signin': CalendarGroupKind.samsung,
  'com.microsoft.office.outlook.USER_ACCOUNT': CalendarGroupKind.outlook,
  'com.android.exchange': CalendarGroupKind.exchange,
  'com.google.android.gm.exchange': CalendarGroupKind.exchange,
  'com.samsung.android.exchange': CalendarGroupKind.exchange,
};

// How a Google calendar's owner address tells a holiday or birthday calendar,
// a person, and a group calendar apart (spec §4.2).
const _holidayOwnerSuffixes = [
  '#holiday@group.v.calendar.google.com',
  '#contacts@group.v.calendar.google.com',
];
const _googleOwnerSuffix = '.calendar.google.com';
const _groupOwnerSuffix = '@group.calendar.google.com';

/// `CALENDAR_ACCESS_LEVEL` of a calendar's owner. Below it, the user can only
/// read or edit.
const _ownerAccessLevel = 700;

/// Where a calendar goes: the group's kind and, for an account group, the
/// account (type and name, matched exactly). The three special groups have no
/// account.
typedef _Slot = ({
  CalendarGroupKind kind,
  String? accountType,
  String? accountName,
});

_Slot _slotOf(DeviceCalendar c) {
  if (_isHoliday(c)) return _special(CalendarGroupKind.holidays);
  if (_isShared(c)) return _special(CalendarGroupKind.shared);
  // Every LOCAL calendar the holiday rule did not take.
  if (c.accountType == _localType) return _special(CalendarGroupKind.phoneOnly);
  return (
    kind: _kindByAccountType[c.accountType] ?? CalendarGroupKind.other,
    accountType: c.accountType,
    accountName: c.accountName,
  );
}

_Slot _special(CalendarGroupKind kind) =>
    (kind: kind, accountType: null, accountName: null);

/// Spec §4.2 rule 1: a Google holiday or contacts-birthday calendar, or
/// Samsung's birthday calendar.
bool _isHoliday(DeviceCalendar c) {
  final type = c.accountType;
  if (type == _googleType) {
    final owner = _clean(c.ownerAccount);
    return owner != null && _holidayOwnerSuffixes.any(owner.endsWith);
  }
  return type == _localType && c.accountName == _samsungBirthdayAccount;
}

/// Spec §4.2 rule 2: a Google calendar that belongs to someone else. With no
/// owner address nothing says so, and a primary calendar is never shared.
bool _isShared(DeviceCalendar c) {
  if (c.accountType != _googleType) return false;
  final owner = _clean(c.ownerAccount);
  if (owner == null || owner == _clean(c.accountName)) return false;
  if (_isPrimary(c)) return false;
  final person = owner.contains('@') && !owner.endsWith(_googleOwnerSuffix);
  final othersGroup =
      owner.endsWith(_groupOwnerSuffix) &&
      (c.accessLevel ?? 0) < _ownerAccessLevel;
  return person || othersGroup;
}

/// Whether this is its account's main calendar (spec §4.3). When the provider
/// does not say, a calendar owned by its own account stands in.
bool _isPrimary(DeviceCalendar c) {
  final primary = c.primary;
  if (primary != null) return primary;
  final owner = _clean(c.ownerAccount);
  return owner != null && owner == _clean(c.accountName);
}

/// [s] trimmed and lower-cased for comparing addresses; null when it is absent
/// or blank, since neither tells anything.
String? _clean(String? s) {
  final cleaned = s?.trim().toLowerCase();
  return cleaned == null || cleaned.isEmpty ? null : cleaned;
}

/// Groups by kind, then the accounts of a kind by name, the ones with no name
/// last (spec §4.3). Names that differ only in case compare equal.
int _compareSlots(_Slot a, _Slot b) {
  final byKind = a.kind.index.compareTo(b.kind.index);
  if (byKind != 0) return byKind;
  final aName = a.accountName ?? '';
  final bName = b.accountName ?? '';
  if (aName.isEmpty != bName.isEmpty) return aName.isEmpty ? 1 : -1;
  return aName.toLowerCase().compareTo(bName.toLowerCase());
}

/// Rows by primary first, then name, then id (spec §4.3).
int _compareRows(DeviceCalendar a, DeviceCalendar b) {
  final aPrimary = _isPrimary(a);
  if (aPrimary != _isPrimary(b)) return aPrimary ? -1 : 1;
  final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
  return byName != 0 ? byName : a.id.compareTo(b.id);
}
