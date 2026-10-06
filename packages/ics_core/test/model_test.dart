import 'package:ics_core/ics_core.dart';
import 'package:test/test.dart';

void main() {
  IcsOccurrence sample({Set<IcsWarning> warnings = const {}}) => IcsOccurrence(
    uid: 'u1',
    originalStartUtc: DateTime.utc(2026, 10, 12, 7),
    recurring: true,
    title: 'Standup',
    location: 'Room 1',
    organizer: 'Thandi M.',
    description: 'Daily',
    joinUrl: 'https://teams.microsoft.com/l/meetup-join/abc',
    startUtc: DateTime.utc(2026, 10, 12, 7),
    endUtc: DateTime.utc(2026, 10, 12, 7, 15),
    allDay: false,
    busyStatus: IcsBusyStatus.busy,
    warnings: warnings,
  );

  test('IcsOccurrence has value equality, including warnings in any order', () {
    final a = sample(
      warnings: {IcsWarning.tzFromDevice, IcsWarning.tzFromVtimezone},
    );
    final b = sample(
      warnings: {IcsWarning.tzFromVtimezone, IcsWarning.tzFromDevice},
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(sample(), isNot(a));
  });

  test('IcsOccurrence defaults to no warnings', () {
    expect(sample().warnings, isEmpty);
  });

  test('IcsIssue has value equality', () {
    expect(
      const IcsIssue(uid: 'x', line: 3, message: 'bad'),
      const IcsIssue(uid: 'x', line: 3, message: 'bad'),
    );
    expect(const IcsIssue(line: 3, message: 'bad').uid, isNull);
  });

  test('IcsFormatException carries its message', () {
    const e = IcsFormatException('nope');
    expect(e.message, 'nope');
    expect(e.toString(), contains('nope'));
  });

  test('enums match the roadmap contract', () {
    expect(IcsBusyStatus.values.map((v) => v.name), [
      'free',
      'tentative',
      'busy',
      'oof',
      'unknown',
    ]);
    expect(IcsWarning.values.map((v) => v.name), [
      'tzFromVtimezone',
      'tzFromDevice',
    ]);
  });
}
