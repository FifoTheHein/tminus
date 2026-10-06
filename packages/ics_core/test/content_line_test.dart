import 'package:ics_core/src/content_line.dart';
import 'package:test/test.dart';

void main() {
  group('unfoldLines', () {
    test('joins CRLF + space continuations', () {
      expect(unfoldLines('SUMMARY:Quarterly pl\r\n anning\r\nUID:1\r\n'), [
        'SUMMARY:Quarterly planning',
        'UID:1',
        '',
      ]);
    });

    test(
      'joins LF + tab continuations and removes only one whitespace char',
      () {
        expect(unfoldLines('DESCRIPTION:a\n\t b\nUID:1'), [
          'DESCRIPTION:a b',
          'UID:1',
        ]);
      },
    );

    test('accepts bare CR line breaks and drops a byte-order mark', () {
      expect(unfoldLines('\uFEFFBEGIN:VCALENDAR\rEND:VCALENDAR'), [
        'BEGIN:VCALENDAR',
        'END:VCALENDAR',
      ]);
    });
  });

  group('parseContentLine', () {
    test('splits name, parameters and value', () {
      final l = parseContentLine(
        'DTSTART;TZID=South Africa Standard Time:20261012T084500',
        7,
      )!;
      expect(l.name, 'DTSTART');
      expect(l.params, {'TZID': 'South Africa Standard Time'});
      expect(l.value, '20261012T084500');
      expect(l.line, 7);
    });

    test('quoted parameter values may contain ; and :', () {
      final l = parseContentLine(
        'ORGANIZER;CN="Thandi M.; Ops: SA";SENT-BY="mailto:pa@example.com":mailto:thandi@example.com',
        1,
      )!;
      expect(l.params['CN'], 'Thandi M.; Ops: SA');
      expect(l.params['SENT-BY'], 'mailto:pa@example.com');
      expect(l.value, 'mailto:thandi@example.com');
    });

    test(
      'names and parameter keys are upper-cased; the value keeps colons',
      () {
        final l = parseContentLine('location;x-param=1:http://x:80/a', 1)!;
        expect(l.name, 'LOCATION');
        expect(l.params, {'X-PARAM': '1'});
        expect(l.value, 'http://x:80/a');
      },
    );

    test('blank and colon-less lines are null', () {
      expect(parseContentLine('', 1), isNull);
      expect(parseContentLine('JUSTTEXT', 1), isNull);
      expect(parseContentLine(':novalue', 1), isNull);
    });
  });

  group('unescapeText', () {
    test(r'handles \\ \; \, \n \N', () {
      expect(unescapeText(r'a\\b\;c\,d\ne\Nf'), 'a\\b;c,d\ne\nf');
    });

    test('leaves unknown escapes and a trailing backslash alone', () {
      expect(unescapeText(r'C:\temp\'), r'C:\temp\');
    });
  });
}
