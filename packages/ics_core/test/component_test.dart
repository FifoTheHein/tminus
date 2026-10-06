import 'package:ics_core/ics_core.dart';
import 'package:ics_core/src/component.dart';
import 'package:test/test.dart';

void main() {
  test('builds the VCALENDAR tree with line numbers of the unfolded text', () {
    final cal = parseCalendar(
      [
        'BEGIN:VCALENDAR',
        'VERSION:2.0',
        'BEGIN:VTIMEZONE',
        'TZID:Custom',
        'BEGIN:STANDARD',
        'TZOFFSETTO:+0200',
        'END:STANDARD',
        'END:VTIMEZONE',
        'BEGIN:VEVENT',
        'SUMMARY:Folded',
        '  title',
        'UID:1',
        'END:VEVENT',
        'END:VCALENDAR',
      ].join('\r\n'),
    );
    expect(cal.name, 'VCALENDAR');
    expect(cal.first('VERSION')!.value, '2.0');
    expect(cal.children.map((c) => c.name), ['VTIMEZONE', 'VEVENT']);
    final tz = cal.children.first;
    expect(tz.children.single.name, 'STANDARD');
    expect(tz.children.single.first('TZOFFSETTO')!.value, '+0200');
    final event = cal.children.last;
    expect(event.line, 9);
    expect(event.first('SUMMARY')!.value, 'Folded title');
    expect(event.first('UID')!.line, 11);
    expect(event.terminated, isTrue);
  });

  test('all() returns every property with the name', () {
    final cal = parseCalendar(
      'BEGIN:VCALENDAR\nBEGIN:VEVENT\nEXDATE:20261012\nEXDATE:20261013\nEND:VEVENT\nEND:VCALENDAR',
    );
    expect(cal.children.single.all('EXDATE').map((p) => p.value), [
      '20261012',
      '20261013',
    ]);
  });

  test('a truncated feed keeps the unterminated VEVENT, marked as such', () {
    final cal = parseCalendar(
      'BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:ok\nEND:VEVENT\nBEGIN:VEVENT\nUID:cut',
    );
    expect(cal.children.map((c) => c.terminated), [true, false]);
  });

  test('a VEVENT missing END:VEVENT mid-feed does not swallow later ones', () {
    final cal = parseCalendar(
      [
        'BEGIN:VCALENDAR',
        'BEGIN:VEVENT',
        'UID:open',
        'BEGIN:VEVENT',
        'UID:second',
        'BEGIN:VALARM',
        'TRIGGER:-PT15M',
        'END:VALARM',
        'END:VEVENT',
        'BEGIN:VTIMEZONE',
        'TZID:Custom',
        'BEGIN:STANDARD',
        'TZOFFSETTO:+0200',
        'END:STANDARD',
        'END:VTIMEZONE',
        'BEGIN:VEVENT',
        'UID:third',
        'END:VEVENT',
        'END:VCALENDAR',
      ].join('\r\n'),
    );
    expect(cal.children.map((c) => c.name), [
      'VEVENT',
      'VEVENT',
      'VTIMEZONE',
      'VEVENT',
    ]);
    expect(cal.children.map((c) => c.first('UID')?.value), [
      'open',
      'second',
      null,
      'third',
    ]);
    expect(cal.children.map((c) => c.terminated), [false, true, true, true]);
    expect(cal.children[0].children, isEmpty);
    expect(cal.children[1].children.single.name, 'VALARM');
    expect(cal.children[2].children.single.name, 'STANDARD');
  });

  test('text before BEGIN:VCALENDAR is ignored', () {
    final cal = parseCalendar('garbage\nX:1\nBEGIN:VCALENDAR\nEND:VCALENDAR');
    expect(cal.properties, isEmpty);
  });

  test('text without BEGIN:VCALENDAR throws IcsFormatException', () {
    expect(
      () => parseCalendar('<html>Not found</html>'),
      throwsA(isA<IcsFormatException>()),
    );
    expect(() => parseCalendar(''), throwsA(isA<IcsFormatException>()));
  });
}
