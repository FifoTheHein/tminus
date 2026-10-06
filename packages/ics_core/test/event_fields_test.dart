import 'package:ics_core/ics_core.dart';
import 'package:ics_core/src/component.dart';
import 'package:ics_core/src/content_line.dart';
import 'package:ics_core/src/event_fields.dart';
import 'package:test/test.dart';

Component event(List<String> lines) => parseCalendar(
  [
    'BEGIN:VCALENDAR',
    'BEGIN:VEVENT',
    ...lines,
    'END:VEVENT',
    'END:VCALENDAR',
  ].join('\r\n'),
).children.single;

void main() {
  group('isCancelledTitle', () {
    test('matches Canceled:/Cancelled: in any case after trimming', () {
      for (final t in [
        'Canceled: Design review',
        'Cancelled: Budget',
        '  CANCELLED: Budget sync',
        'cancelled:lowercase',
      ]) {
        expect(isCancelledTitle(t), isTrue, reason: t);
      }
    });

    test('does not match other titles', () {
      for (final t in [
        'Cancellation policy review',
        'Re: Canceled: thing',
        'Canceled',
        '',
      ]) {
        expect(isCancelledTitle(t), isFalse, reason: t);
      }
    });
  });

  group('busyStatusOf', () {
    test('reads X-MICROSOFT-CDO-BUSYSTATUS', () {
      expect(
        busyStatusOf(event(['X-MICROSOFT-CDO-BUSYSTATUS:FREE'])),
        IcsBusyStatus.free,
      );
      expect(
        busyStatusOf(event(['X-MICROSOFT-CDO-BUSYSTATUS:TENTATIVE'])),
        IcsBusyStatus.tentative,
      );
      expect(
        busyStatusOf(event(['X-MICROSOFT-CDO-BUSYSTATUS:BUSY'])),
        IcsBusyStatus.busy,
      );
      expect(
        busyStatusOf(event(['X-MICROSOFT-CDO-BUSYSTATUS:OOF'])),
        IcsBusyStatus.oof,
      );
      expect(
        busyStatusOf(event(['X-MICROSOFT-CDO-BUSYSTATUS:WORKINGELSEWHERE'])),
        IcsBusyStatus.busy,
      );
    });

    test('the CDO value wins over TRANSP', () {
      expect(
        busyStatusOf(
          event(['TRANSP:TRANSPARENT', 'X-MICROSOFT-CDO-BUSYSTATUS:BUSY']),
        ),
        IcsBusyStatus.busy,
      );
    });

    test('falls back to TRANSP:TRANSPARENT → free, else unknown', () {
      expect(busyStatusOf(event(['TRANSP:TRANSPARENT'])), IcsBusyStatus.free);
      expect(busyStatusOf(event(['TRANSP:OPAQUE'])), IcsBusyStatus.unknown);
      expect(
        busyStatusOf(event(['X-MICROSOFT-CDO-BUSYSTATUS:ODD'])),
        IcsBusyStatus.unknown,
      );
    });
  });

  group('organizerOf', () {
    test('prefers the quoted CN', () {
      expect(
        organizerOf(
          parseContentLine(
            'ORGANIZER;CN="Thandi M.":mailto:thandi@example.com',
            1,
          ),
        ),
        'Thandi M.',
      );
    });

    test('else the address without mailto:', () {
      expect(
        organizerOf(parseContentLine('ORGANIZER:MAILTO:pieter@example.com', 1)),
        'pieter@example.com',
      );
      expect(organizerOf(null), isNull);
    });
  });

  group('textOf', () {
    test('unescapes and trims; blank is null', () {
      expect(
        textOf(parseContentLine(r'LOCATION: Room 4\; Building B ', 1)),
        'Room 4; Building B',
      );
      expect(textOf(parseContentLine('LOCATION:  ', 1)), isNull);
    });
  });

  group('extractTeamsJoinUrl', () {
    const url =
        'https://teams.microsoft.com/l/meetup-join/19%3ameeting_NjA1ZTI4%40thread.v2/0?context=%7b%22Tid%22%3a%22t%22%7d';

    test('finds the Outlook <...> link and strips the >', () {
      expect(
        extractTeamsJoinUrl(
          'Microsoft Teams meeting\nClick here to join the meeting<$url>\nMeeting ID: 1',
          null,
        ),
        url,
      );
    });

    test('strips trailing sentence punctuation', () {
      expect(extractTeamsJoinUrl('Join at $url.', null), url);
      expect(extractTeamsJoinUrl('(join: $url)', null), url);
    });

    test('decodes a link percent-encoded inside a Safe Links wrapper', () {
      expect(
        extractTeamsJoinUrl(
          '<https://eur01.safelinks.protection.outlook.com/?url=https%3A%2F%2Fteams.microsoft.com%2Fl%2Fmeetup-join%2F19%253ameeting_SAFE%2540thread.v2%2F0&data=05%7C01>',
          null,
        ),
        'https://teams.microsoft.com/l/meetup-join/19%3ameeting_SAFE%40thread.v2/0',
      );
    });

    test('skips a link with broken percent-encoding and keeps looking', () {
      expect(
        extractTeamsJoinUrl(
          'https%3A%2F%2Fteams.microsoft.com%2Fl%2Fmeetup-join%2F%zz',
          'https://teams.microsoft.com/l/meetup-join/loc',
        ),
        'https://teams.microsoft.com/l/meetup-join/loc',
      );
    });

    test('finds the newer /meet/ link', () {
      const meet = 'https://teams.microsoft.com/meet/3456789012345?p=AbCdEfGh';
      expect(
        extractTeamsJoinUrl(
          'Join the meeting now <$meet>\nMeeting ID: 345',
          null,
        ),
        meet,
      );
      expect(
        extractTeamsJoinUrl(
          '<https://eur01.safelinks.protection.outlook.com/?url=https%3A%2F%2Fteams.microsoft.com%2Fmeet%2F3456789012345%3Fp%3DAbCd&data=05>',
          null,
        ),
        'https://teams.microsoft.com/meet/3456789012345?p=AbCd',
      );
    });

    test('a Teams page that is not a join link is ignored', () {
      expect(
        extractTeamsJoinUrl(
          'Help: https://teams.microsoft.com/meeting-options/?x=1 and https://teams.microsoft.com/l/channel/19%3a1',
          null,
        ),
        isNull,
      );
    });

    test('DESCRIPTION first, then LOCATION', () {
      expect(extractTeamsJoinUrl('no link', '$url;'), url);
      expect(
        extractTeamsJoinUrl(
          url,
          'https://teams.microsoft.com/l/meetup-join/other',
        ),
        url,
      );
    });

    test('null when there is no Teams join link', () {
      expect(
        extractTeamsJoinUrl(
          'https://zoom.us/j/1 https://teams.microsoft.com/',
          'Microsoft Teams Meeting',
        ),
        isNull,
      );
      expect(extractTeamsJoinUrl(null, null), isNull);
    });
  });
}
