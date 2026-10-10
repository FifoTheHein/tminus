import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/sources/ics_url.dart';

void main() {
  const outlook =
      'https://outlook.office365.com/owa/calendar/abc123@example.com/s3cr3t/calendar.ics';
  const google =
      'https://calendar.google.com/calendar/ical/me%40gmail.com/private-0a1b2c3d4e5f/basic.ics';

  String accepted(String input, {bool insecure = false}) {
    final r = IcsUrl.check(input);
    expect(r, isA<IcsUrlAccepted>(), reason: input);
    expect((r as IcsUrlAccepted).insecure, insecure, reason: input);
    return r.url;
  }

  String rejected(String input) {
    final r = IcsUrl.check(input);
    expect(r, isA<IcsUrlRejected>(), reason: input);
    return (r as IcsUrlRejected).message;
  }

  test('an https .ics link is accepted as it is, trimmed', () {
    expect(accepted('  $outlook \n'), outlook);
  });

  test('webcal:// becomes https://', () {
    expect(
      accepted('webcal://outlook.office365.com/owa/calendar/x/calendar.ics'),
      'https://outlook.office365.com/owa/calendar/x/calendar.ics',
    );
    expect(accepted('WEBCAL://example.com/a.ics'), 'https://example.com/a.ics');
  });

  test('http:// is accepted but flagged insecure', () {
    expect(
      accepted('http://example.com/cal.ics', insecure: true),
      'http://example.com/cal.ics',
    );
  });

  test(
    'the .html web page link is rejected with a pointer to the .ics one',
    () {
      expect(
        rejected('https://outlook.office365.com/owa/calendar/x/calendar.html'),
        contains('.ics'),
      );
    },
  );

  test('empty text, other schemes and host-less links are rejected', () {
    expect(rejected('   '), 'Paste the calendar link.');
    expect(rejected('ftp://example.com/a.ics'), contains('https://'));
    expect(rejected('calendar.ics'), contains('https://'));
    expect(rejected('https:///a.ics'), contains('https://'));
  });

  test('mask keeps the host and the last segment only', () {
    expect(IcsUrl.mask(outlook), 'outlook.office365.com/…/calendar.ics');
    expect(IcsUrl.mask('https://example.com/cal.ics'), 'example.com/cal.ics');
    expect(IcsUrl.mask('https://example.com/'), 'example.com');
    expect(
      IcsUrl.mask('https://example.com/a/b.ics?token=s3cr3t'),
      'example.com/…/b.ics',
    );
    expect(IcsUrl.mask(google), 'calendar.google.com/…/basic.ics');
    expect(
      IcsUrl.mask('https://example.com/a/CAL.ICS'),
      'example.com/…/CAL.ICS',
    );
    expect(IcsUrl.mask('not a link'), '…');
    expect(IcsUrl.mask(outlook), isNot(contains('s3cr3t')));
    expect(IcsUrl.mask(google), isNot(contains('0a1b2c3d4e5f')));
  });

  test('mask never shows a last segment that is not the .ics file name', () {
    // iCloud puts the secret token in the last path segment.
    const icloud = 'https://p59-caldav.icloud.com/published/2/MTIzNDU2c2VjcmV0';
    expect(IcsUrl.mask(icloud), 'p59-caldav.icloud.com/…');
    expect(IcsUrl.mask(icloud), isNot(contains('MTIzNDU2c2VjcmV0')));
    expect(IcsUrl.mask('https://example.com/s3cr3t'), 'example.com/…');
    expect(IcsUrl.mask('https://example.com/feed?file=a.ics'), 'example.com/…');
  });
}
