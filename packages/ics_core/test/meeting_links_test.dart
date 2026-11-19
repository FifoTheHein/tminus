import 'package:ics_core/ics_core.dart';
import 'package:test/test.dart';

/// Outlook Safe Links around [encoded] (a percent-encoded link), as Outlook
/// writes it into a description.
String safeLinks(String encoded) =>
    'https://eur02.safelinks.protection.outlook.com/?url=$encoded'
    '&data=05%7C02%7Cuser%40example.com%7C0123abcd%7C0%7C0%7C638000000000000000%7CUnknown'
    '&sdata=abc%2Fdef%3D&reserved=0';

/// Google's redirect around [inner] (a plain or a percent-encoded link), as
/// Google Calendar writes it into a description.
String googleRedirect(String inner) =>
    'https://www.google.com/url?q=$inner'
    '&sa=D&source=calendar&usg=AOvVaw0abcdEFGH';

/// One row of the table that Kotlin's MeetingServiceTest shares: the text a
/// calendar holds ([input]), the link the app keeps once it is found and
/// decoded ([url]) and the service that link names ([service]; null for a link
/// that only looks like a join link).
class _Row {
  const _Row(this.label, this.input, this.url, this.service);

  /// A link that stands in the calendar text exactly as the app keeps it.
  const _Row.plain(String label, String url, MeetingService? service)
    : this(label, url, url, service);

  final String label;
  final String input;
  final String url;
  final MeetingService? service;

  /// What extractJoinUrl gives for [input].
  String? get found => service == null ? null : url;
}

/// The links of the shared table, in Kotlin's order, with each wrapped row
/// written as the wrapper and expected as the decoded link. The last two Meet
/// rows are finder inputs that Kotlin's table does not repeat, because their
/// decoded link is already a row there.
final _table = <_Row>[
  // Teams: both forms on teams.microsoft.com, the two newer hosts and a Safe
  // Links wrapper (its percent-encoded context query stays as it is).
  const _Row.plain(
    'Teams meetup-join',
    'https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0',
    MeetingService.teams,
  ),
  const _Row.plain(
    'Teams /meet/',
    'https://teams.microsoft.com/meet/1234567890123',
    MeetingService.teams,
  ),
  const _Row.plain(
    'Teams on teams.cloud.microsoft',
    'https://teams.cloud.microsoft/meet/1234567890123',
    MeetingService.teams,
  ),
  const _Row.plain(
    'Teams on teams.live.com',
    'https://teams.live.com/meet/1234567890123',
    MeetingService.teams,
  ),
  _Row(
    'Teams in Safe Links',
    safeLinks(
      'https%3A%2F%2Fteams.microsoft.com%2Fl%2Fmeetup-join%2F19%253ameeting_def%2540thread.v2%2F0'
      '%3Fcontext%3D%257b%2522Tid%2522%253a%252200000000-0000-0000-0000-000000000000%2522%257d',
    ),
    'https://teams.microsoft.com/l/meetup-join/19%3ameeting_def%40thread.v2/0'
        '?context=%7b%22Tid%22%3a%2200000000-0000-0000-0000-000000000000%22%7d',
    MeetingService.teams,
  ),

  // Google Meet.
  const _Row.plain(
    'Meet',
    'https://meet.google.com/abc-defg-hij',
    MeetingService.googleMeet,
  ),
  const _Row.plain(
    'Meet with ?authuser=0',
    'https://meet.google.com/abc-defg-hij?authuser=0',
    MeetingService.googleMeet,
  ),
  // The form that an accepted Google invite has in Outlook.
  const _Row.plain(
    'Meet with ?hs=224',
    'https://meet.google.com/abc-defg-hij?hs=224',
    MeetingService.googleMeet,
  ),
  _Row(
    'Meet in a Google redirect',
    googleRedirect('https%3A%2F%2Fmeet.google.com%2Fqrs-tuvw-xyz'),
    'https://meet.google.com/qrs-tuvw-xyz',
    MeetingService.googleMeet,
  ),
  const _Row(
    'Meet in an HTML href',
    'href="https://meet.google.com/abc-defg-hij">',
    'https://meet.google.com/abc-defg-hij',
    MeetingService.googleMeet,
  ),
  _Row(
    'Meet ?hs=224 in Safe Links',
    safeLinks('https%3A%2F%2Fmeet.google.com%2Fabc-defg-hij%3Fhs%3D224'),
    'https://meet.google.com/abc-defg-hij?hs=224',
    MeetingService.googleMeet,
  ),

  // Zoom.
  const _Row.plain(
    'Zoom us06web with a password',
    'https://us06web.zoom.us/j/12345678901?pwd=abc',
    MeetingService.zoom,
  ),
  const _Row.plain(
    'Zoom personal room',
    'https://zoom.us/my/someone',
    MeetingService.zoom,
  ),
  const _Row.plain(
    'Zoom on zoom.com',
    'https://zoom.com/j/12345678901',
    MeetingService.zoom,
  ),
  const _Row.plain(
    'Zoom webinar',
    'https://example.zoom.us/w/12345678901',
    MeetingService.zoom,
  ),
  _Row(
    'Zoom in Safe Links',
    safeLinks('https%3A%2F%2Fus02web.zoom.us%2Fj%2F98765432109%3Fpwd%3Ddef456'),
    'https://us02web.zoom.us/j/98765432109?pwd=def456',
    MeetingService.zoom,
  ),

  // Webex.
  const _Row.plain(
    'Webex join page',
    'https://example.webex.com/example/j.php?MTID=m0123abcd',
    MeetingService.webex,
  ),
  const _Row.plain(
    'Webex personal room',
    'https://example.webex.com/meet/someone',
    MeetingService.webex,
  ),
  const _Row.plain(
    'Webex join',
    'https://example.webex.com/join/someone',
    MeetingService.webex,
  ),

  // Links that only look like join links.
  const _Row.plain('Zoom download page', 'https://zoom.us/download', null),
  const _Row.plain('Webex home page', 'https://www.webex.com/', null),
  const _Row.plain('Meet without a code', 'https://meet.google.com/', null),
  // The "more phone numbers" link that Google puts next to a Meet link.
  const _Row.plain(
    'Meet phone numbers page',
    'https://tel.meet/abc-defg-hij?pin=1234',
    null,
  ),
];

/// One link per service, for tests that need "a link of each service".
const _samples = <MeetingService, String>{
  MeetingService.teams: 'https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0',
  MeetingService.googleMeet: 'https://meet.google.com/abc-defg-hij?authuser=0',
  MeetingService.zoom: 'https://us06web.zoom.us/j/12345678901?pwd=abc',
  MeetingService.webex:
      'https://example.webex.com/example/j.php?MTID=m0123abcd',
};

/// More links, with and without a query, to end in every way a link can end.
const _endLinks = [
  'https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0',
  'https://teams.microsoft.com/meet/1234567890123?p=AbCdEf',
  'https://meet.google.com/abc-defg-hij',
  'https://meet.google.com/abc-defg-hij?authuser=0',
  'https://us06web.zoom.us/j/12345678901?pwd=abc',
  'https://example.zoom.us/j/12345678901',
  'https://zoom.us/my/someone',
  'https://example.webex.com/example/j.php?MTID=m0123abcd',
  'https://example.webex.com/meet/someone',
  'https://example.webex.com/join/someone',
];

/// Pages on the four hosts that are not join links.
const _otherPages = [
  'https://zoom.us/',
  'https://zoom.us/j/',
  'https://example.webex.com/meet/',
  'https://meet.google.com/abcd-efgh-ijk',
  'https://meet.google.com/abc-defg-hijk',
  'https://meet.google.com/lookup/abc123',
  'https://teams.microsoft.com/meeting-options/?x=1',
  'https://teams.microsoft.com/l/channel/19%3aabc%40thread.tacv2/General',
];

/// Hosts that merely contain the name of a real one.
const _lookalikeHosts = [
  'https://evilzoom.us/j/123',
  'https://notzoom.com/j/12345678901',
  'https://zoom.us.evil.example/j/12345678901',
  'https://zoom.us@evil.example/j/12345678901',
  'https://evilwebex.com/meet/someone',
  'https://example.webex.com.evil.example/meet/someone',
  'https://meet.google.com.evil.example/abc-defg-hij',
  'https://evilmeet.google.com/abc-defg-hij',
  'https://teams.microsoft.com.evil.example/l/meetup-join/19%3ameeting_abc%40thread.v2/0',
  'https://evilteams.microsoft.com/meet/1234567890123',
  'https://teams.live.com.evil.example/meet/1234567890123',
];

/// Links written without the https:// that Outlook also shows as plain text.
const _noScheme = [
  'teams.microsoft.com/meet/1234567890123',
  'meet.google.com/abc-defg-hij',
  'zoom.us/j/12345678901',
  'example.webex.com/meet/someone',
];

/// A Webex join page link needs a non-empty MTID first in its query.
const _webexWithoutMtid = [
  'https://example.webex.com/example/j.php',
  'https://example.webex.com/example/j.php?MTID=',
  'https://example.webex.com/example/j.php?x=1&MTID=m1',
];

/// A word character glued to the end of a number or code gives no link.
const _glued = [
  'https://zoom.us/j/123abc',
  'https://zoom.us/j/12345678901x',
  'https://example.zoom.us/w/12345678901x',
  'https://meet.google.com/abc-defg-hijk',
  'https://teams.cloud.microsoft/meet/1234567890123abc',
  'https://teams.live.com/meet/1234567890123abc',
];

/// Text with no link in it, some of it malformed.
const _malformed = [
  'not a link',
  '%',
  '%zz',
  '%2',
  'https://',
  'https:///j/12345678901',
  'https://[',
  'https://zoom.us/j/%zz',
  'https%3A%2F%2F',
  'https%3A%2F%2F%zz',
];

/// Percent-encoded links, wrapped or not, with a broken escape inside. A
/// decoder must not throw on them, whatever the finder then decides.
const _brokenEncodings = [
  '%',
  '%zz',
  '%2',
  'https%3A%2F%2Fexample.zoom.us%2Fj%2F12345678901%3Fpwd%3D%zz',
  'https%3A%2F%2Fmeet.google.com%2Fabc-defg-hij%3Fx%3D%zz',
  'https%3A%2F%2Fexample.webex.com%2Fexample%2Fj.php%3FMTID%3D%zz',
  'https%3A%2F%2Fteams.microsoft.com%2Fmeet%2F3456789012345%3Fp%3D%zz',
  'https://eur02.safelinks.protection.outlook.com/?url=https%3A%2F%2Fexample.zoom.us%2Fj%2F12345678901%3Fpwd%3D%zz&data=05',
  'https://www.google.com/url?q=https://example.zoom.us/j/12345678901?pwd%3D%zz&sa=D',
  'https://www.google.com/url?q=https://example.zoom.us/j/12345678901?pwd%zz&sa=D',
  'https://example.zoom.us/j/12345678901?pwd=%zz',
];

/// [text] is no join link: the finder gives null wherever it stands, and no
/// service is named.
void _expectNoLink(String text) {
  expect(extractJoinUrl(text, null), isNull, reason: 'description: $text');
  expect(extractJoinUrl(null, text), isNull, reason: 'location: $text');
  expect(meetingServiceOf(text), isNull, reason: 'service of: $text');
}

void main() {
  group('MeetingService', () {
    test('has the four services, in this order', () {
      expect(MeetingService.values, [
        MeetingService.teams,
        MeetingService.googleMeet,
        MeetingService.zoom,
        MeetingService.webex,
      ]);
    });

    test('each service has the name the app shows', () {
      expect(MeetingService.teams.label, 'Teams');
      expect(MeetingService.googleMeet.label, 'Google Meet');
      expect(MeetingService.zoom.label, 'Zoom');
      expect(MeetingService.webex.label, 'Webex');
    });
  });

  group('the shared table', () {
    test('holds the shared rows and the two extra finder inputs', () {
      int count(MeetingService? service) =>
          _table.where((r) => r.service == service).length;
      expect(count(MeetingService.teams), 5);
      expect(count(MeetingService.googleMeet), 6);
      expect(count(MeetingService.zoom), 5);
      expect(count(MeetingService.webex), 3);
      expect(count(null), 4);
    });

    group('extractJoinUrl, text in the description', () {
      for (final row in _table) {
        test(row.label, () {
          expect(extractJoinUrl(row.input, null), row.found);
        });
      }
    });

    group('extractJoinUrl, text in the location', () {
      for (final row in _table) {
        test(row.label, () {
          expect(extractJoinUrl(null, row.input), row.found);
        });
      }
    });

    group('extractJoinUrl, text inside a sentence', () {
      for (final row in _table) {
        test(row.label, () {
          expect(
            extractJoinUrl('Join here: ${row.input} and bring a laptop', null),
            row.found,
          );
        });
      }
    });

    group('meetingServiceOf, the link as the app keeps it', () {
      for (final row in _table) {
        test(row.label, () {
          expect(meetingServiceOf(row.url), row.service);
        });
      }
    });
  });

  group('text that is no join link', () {
    const lists = <String, List<String>>{
      'other pages on the four hosts': _otherPages,
      'look-alike hosts': _lookalikeHosts,
      'links written without https://': _noScheme,
      'a Webex join page without an MTID in first place': _webexWithoutMtid,
      'malformed text': _malformed,
    };
    for (final list in lists.entries) {
      test(list.key, () {
        list.value.forEach(_expectNoLink);
      });
    }

    test('the http form of a valid link', () {
      for (final row in _table.where((r) => r.service != null)) {
        _expectNoLink(row.url.replaceFirst('https://', 'http://'));
      }
    });

    test('null, empty and blank text', () {
      expect(extractJoinUrl(null, null), isNull);
      expect(extractJoinUrl('', ''), isNull);
      expect(extractJoinUrl('  ', '\n'), isNull);
      expect(extractJoinUrl('', '', conference: ''), isNull);
      expect(meetingServiceOf(null), isNull);
      expect(meetingServiceOf(''), isNull);
      expect(meetingServiceOf('   '), isNull);
    });
  });

  group('hosts', () {
    test('the host is matched ignoring case', () {
      const mixedCase = <String, MeetingService>{
        'https://TEAMS.MICROSOFT.COM/l/meetup-join/19%3ameeting_abc%40thread.v2/0':
            MeetingService.teams,
        'https://Teams.Microsoft.com/meet/1234567890123': MeetingService.teams,
        'https://TEAMS.CLOUD.MICROSOFT/meet/1234567890123':
            MeetingService.teams,
        'https://Teams.Live.Com/meet/1234567890123': MeetingService.teams,
        'https://MEET.GOOGLE.COM/abc-defg-hij': MeetingService.googleMeet,
        'https://Meet.Google.com/abc-defg-hij?authuser=0':
            MeetingService.googleMeet,
        'https://US06WEB.ZOOM.US/j/12345678901?pwd=abc': MeetingService.zoom,
        'https://Zoom.Com/my/someone': MeetingService.zoom,
        'https://EXAMPLE.WEBEX.COM/example/j.php?MTID=m0123abcd':
            MeetingService.webex,
        'https://Example.Webex.com/join/someone': MeetingService.webex,
      };
      for (final link in mixedCase.entries) {
        // Only the match has to ignore case; the link may come back as written
        // or with its host in lower case.
        expect(
          extractJoinUrl(link.key, null),
          equalsIgnoringCase(link.key),
          reason: link.key,
        );
        expect(meetingServiceOf(link.key), link.value, reason: link.key);
      }
    });

    test('any subdomain of zoom.us, zoom.com and webex.com counts', () {
      const links = <String, MeetingService>{
        'https://us02web.zoom.com/j/12345678901': MeetingService.zoom,
        'https://example.eu.zoom.us/j/12345678901': MeetingService.zoom,
        'https://example.my.webex.com/meet/someone': MeetingService.webex,
        'https://a.b.webex.com/join/someone': MeetingService.webex,
      };
      for (final link in links.entries) {
        expect(extractJoinUrl(link.key, null), link.key, reason: link.key);
        expect(meetingServiceOf(link.key), link.value, reason: link.key);
      }
    });

    test(
      'meetingServiceOf checks the whole string, not text around a link',
      () {
        expect(meetingServiceOf('Join: https://zoom.us/j/12345678901'), isNull);
        expect(
          meetingServiceOf('https://zoom.us/j/12345678901 and more'),
          isNull,
        );
      },
    );
  });

  group('edge forms decided for both Dart and Kotlin', () {
    test('a bare webex.com is no Webex link, only a subdomain is', () {
      _expectNoLink('https://webex.com/meet/someone');
    });

    test('a port is not part of any recognised link', () {
      _expectNoLink('https://zoom.us:443/j/12345678901');
    });

    test('a trailing slash after a Meet code makes it something else', () {
      expect(meetingServiceOf('https://meet.google.com/abc-defg-hij/'), isNull);
    });

    test('a fragment right after the path is kept and still names Zoom', () {
      const link = 'https://zoom.us/j/12345678901#success';
      expect(extractJoinUrl(link, null), link);
      expect(extractJoinUrl('See $link now', null), link);
      expect(meetingServiceOf(link), MeetingService.zoom);
    });

    test('a Webex join page link needs a non-empty MTID first', () {
      _webexWithoutMtid.forEach(_expectNoLink);
      const link = 'https://example.webex.com/example/j.php?MTID=m1';
      expect(extractJoinUrl(link, null), link);
      expect(meetingServiceOf(link), MeetingService.webex);
    });
  });

  group('wrapped links are found and decoded', () {
    test('Safe Links around a Zoom link', () {
      final wrapped = safeLinks(
        'https%3A%2F%2Fus02web.zoom.us%2Fj%2F98765432109%3Fpwd%3Ddef456',
      );
      expect(
        extractJoinUrl(
          'Join Zoom Meeting<$wrapped>\nMeeting ID: 987 6543 2109',
          null,
        ),
        'https://us02web.zoom.us/j/98765432109?pwd=def456',
      );
    });

    test('Safe Links around the three kinds of Webex link', () {
      const links = <String, String>{
        'https%3A%2F%2Fexample.webex.com%2Fexample%2Fj.php%3FMTID%3Dm0123abcd':
            'https://example.webex.com/example/j.php?MTID=m0123abcd',
        'https%3A%2F%2Fexample.webex.com%2Fmeet%2Fsomeone':
            'https://example.webex.com/meet/someone',
        'https%3A%2F%2Fexample.webex.com%2Fjoin%2Fsomeone':
            'https://example.webex.com/join/someone',
      };
      for (final link in links.entries) {
        final wrapped = safeLinks(link.key);
        expect(
          extractJoinUrl('Join Webex meeting<$wrapped>\n', null),
          link.value,
          reason: link.key,
        );
      }
    });

    test('Safe Links around a Meet link keep its query', () {
      final wrapped = safeLinks(
        'https%3A%2F%2Fmeet.google.com%2Fabc-defg-hij%3Fhs%3D224',
      );
      expect(
        extractJoinUrl('<$wrapped>', null),
        'https://meet.google.com/abc-defg-hij?hs=224',
      );
    });

    test('a Google redirect around a percent-encoded link, per service', () {
      const links = <String, String>{
        'https%3A%2F%2Fteams.microsoft.com%2Fmeet%2F3456789012345%3Fp%3DAbCd':
            'https://teams.microsoft.com/meet/3456789012345?p=AbCd',
        'https%3A%2F%2Fmeet.google.com%2Fqrs-tuvw-xyz':
            'https://meet.google.com/qrs-tuvw-xyz',
        'https%3A%2F%2Fus02web.zoom.us%2Fj%2F81234567890%3Fpwd%3DabcXYZ':
            'https://us02web.zoom.us/j/81234567890?pwd=abcXYZ',
        'https%3A%2F%2Fexample.webex.com%2Fexample%2Fj.php%3FMTID%3Dm0123abcd':
            'https://example.webex.com/example/j.php?MTID=m0123abcd',
      };
      for (final link in links.entries) {
        final wrapped = googleRedirect(link.key);
        expect(
          extractJoinUrl('See $wrapped for details', null),
          link.value,
          reason: link.key,
        );
      }
    });

    test('a wrapper inside an HTML href ends at the closing quote', () {
      final wrapped = googleRedirect(
        'https%3A%2F%2Fmeet.google.com%2Fqrs-tuvw-xyz',
      );
      expect(
        extractJoinUrl('<a href="$wrapped">Join with Google Meet</a>', null),
        'https://meet.google.com/qrs-tuvw-xyz',
      );
    });

    test('the finder skips a wrapper around a page that is no join link', () {
      final telWrapped = safeLinks(
        'https%3A%2F%2Ftel.meet%2Fabc-defg-hij%3Fpin%3D1234567890',
      );
      final downloadWrapped = safeLinks('https%3A%2F%2Fzoom.us%2Fdownload');
      expect(
        extractJoinUrl('tel.meet/abc-defg-hij<$telWrapped>', null),
        isNull,
      );
      expect(extractJoinUrl('<$downloadWrapped>', null), isNull);
    });
  });

  group('a Google redirect around a plain link', () {
    test('Zoom: the link ends at the first &, and is decoded once', () {
      expect(
        extractJoinUrl(
          'https://www.google.com/url?q=https://us02web.zoom.us/j/81234567890?pwd%3DabcXYZ&sa=D&source=calendar&usg=x',
          null,
        ),
        'https://us02web.zoom.us/j/81234567890?pwd=abcXYZ',
      );
    });

    test('Meet: with and without a query', () {
      expect(
        extractJoinUrl(
          'https://www.google.com/url?q=https://meet.google.com/qrs-tuvw-xyz&sa=D&source=calendar&usg=x',
          null,
        ),
        'https://meet.google.com/qrs-tuvw-xyz',
      );
      expect(
        extractJoinUrl(
          'https://www.google.com/url?q=https://meet.google.com/qrs-tuvw-xyz?authuser%3D0&sa=D&source=calendar&usg=x',
          null,
        ),
        'https://meet.google.com/qrs-tuvw-xyz?authuser=0',
      );
    });

    test('Teams: a /meet/ link and a meetup-join link', () {
      expect(
        extractJoinUrl(
          'https://www.google.com/url?q=https://teams.microsoft.com/meet/3456789012345?p%3DAbCd&sa=D&source=calendar&usg=x',
          null,
        ),
        'https://teams.microsoft.com/meet/3456789012345?p=AbCd',
      );
      expect(
        extractJoinUrl(
          'https://www.google.com/url?q=https://teams.microsoft.com/l/meetup-join/19%253ameeting_abc%2540thread.v2/0?context%3D%257b%2522Tid%2522%253a%2522t%2522%257d&sa=D&source=calendar&usg=x',
          null,
        ),
        'https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%22Tid%22%3a%22t%22%7d',
      );
    });

    test('Webex: a link that needs no decoding ends at its own grammar', () {
      expect(
        extractJoinUrl(
          'https://www.google.com/url?q=https://example.webex.com/example/j.php?MTID=m0123abcd&sa=D&source=calendar&usg=x',
          null,
        ),
        'https://example.webex.com/example/j.php?MTID=m0123abcd',
      );
      expect(
        extractJoinUrl(
          'https://www.google.com/url?q=https://example.webex.com/meet/someone&sa=D&source=calendar&usg=x',
          null,
        ),
        'https://example.webex.com/meet/someone',
      );
    });

    test('the link is decoded once, not until nothing is left to decode', () {
      expect(
        extractJoinUrl(
          'https://www.google.com/url?q=https://us02web.zoom.us/j/81234567890?pwd%253DabcXYZ&sa=D&source=calendar&usg=x',
          null,
        ),
        'https://us02web.zoom.us/j/81234567890?pwd%3DabcXYZ',
      );
    });

    test('inside an HTML href, with a label after it', () {
      expect(
        extractJoinUrl(
          '<a href="https://www.google.com/url?q=https://us02web.zoom.us/j/81234567890?pwd%3DabcXYZ&sa=D&source=calendar&usg=x">Join Zoom Meeting</a>',
          null,
        ),
        'https://us02web.zoom.us/j/81234567890?pwd=abcXYZ',
      );
    });

    test('with nothing after the link', () {
      expect(
        extractJoinUrl(
          'https://www.google.com/url?q=https://meet.google.com/qrs-tuvw-xyz',
          null,
        ),
        'https://meet.google.com/qrs-tuvw-xyz',
      );
      expect(
        extractJoinUrl(
          'https://www.google.com/url?q=https://us02web.zoom.us/j/81234567890?pwd%3DabcXYZ',
          null,
        ),
        'https://us02web.zoom.us/j/81234567890?pwd=abcXYZ',
      );
    });
  });

  group('where a link ends', () {
    test('trailing sentence punctuation is trimmed', () {
      for (final link in _endLinks) {
        for (final mark in [')', ']', '.', ',', ';', ':', '!', '?']) {
          expect(
            extractJoinUrl('Join at $link$mark', null),
            link,
            reason: 'after $link comes $mark',
          );
        }
      }
    });

    test('a closing > is trimmed', () {
      for (final link in _endLinks) {
        expect(
          extractJoinUrl(
            'Click here to join the meeting<$link>\nMeeting ID: 1',
            null,
          ),
          link,
          reason: link,
        );
      }
    });

    test('whitespace ends a link', () {
      for (final link in _endLinks) {
        for (final space in [' ', '\n', '\r\n', '\t']) {
          expect(
            extractJoinUrl('Join at $link${space}and then more', null),
            link,
            reason: '$link, then ${space.codeUnits}',
          );
        }
      }
    });

    test('<, a double quote and a single quote end a link', () {
      for (final link in _endLinks) {
        expect(
          extractJoinUrl('<a href="$link">Join</a>', null),
          link,
          reason: 'double quotes around $link',
        );
        expect(
          extractJoinUrl("<a href='$link'>Join</a>", null),
          link,
          reason: 'single quotes around $link',
        );
        expect(
          extractJoinUrl('Join: $link</a>', null),
          link,
          reason: 'a closing tag after $link',
        );
        expect(
          extractJoinUrl('$link<br>Learn more', null),
          link,
          reason: 'a line break tag after $link',
        );
      }
    });

    test('a Zoom number ends at the first character that is not a digit', () {
      expect(
        extractJoinUrl('https://x.zoom.us/j/123&sa=D', null),
        'https://x.zoom.us/j/123',
      );
      expect(
        extractJoinUrl('https://us02web.zoom.us/j/81234567890&usg=x', null),
        'https://us02web.zoom.us/j/81234567890',
      );
      expect(
        extractJoinUrl('https://example.zoom.us/w/12345678901&sa=D', null),
        'https://example.zoom.us/w/12345678901',
      );
    });

    test('a Meet code ends where the code does', () {
      expect(
        extractJoinUrl('https://meet.google.com/abc-defg-hij&sa=D', null),
        'https://meet.google.com/abc-defg-hij',
      );
    });

    test('a query belongs to a link only when it starts with a ?', () {
      expect(
        extractJoinUrl('https://x.zoom.us/j/123?pwd=abc', null),
        'https://x.zoom.us/j/123?pwd=abc',
      );
      expect(
        extractJoinUrl('https://x.zoom.us/j/123&pwd=abc', null),
        'https://x.zoom.us/j/123',
      );
      expect(
        extractJoinUrl('https://meet.google.com/abc-defg-hij?authuser=0', null),
        'https://meet.google.com/abc-defg-hij?authuser=0',
      );
      expect(
        extractJoinUrl('https://meet.google.com/abc-defg-hij&authuser=0', null),
        'https://meet.google.com/abc-defg-hij',
      );
    });

    test('a glued word character gives no link, not a cut one', () {
      _glued.forEach(_expectNoLink);
    });

    test('a glued word character does not hide a later link', () {
      expect(
        extractJoinUrl(
          'https://zoom.us/j/123abc and https://zoom.us/j/456',
          null,
        ),
        'https://zoom.us/j/456',
      );
    });
  });

  group('which link is used', () {
    group('inside one text, the earliest link wins whatever its service', () {
      for (final first in MeetingService.values) {
        for (final second in MeetingService.values) {
          if (first == second) continue;
          test('${first.label} before ${second.label}', () {
            expect(
              extractJoinUrl(
                '${_samples[first]} and then ${_samples[second]}',
                null,
              ),
              _samples[first],
            );
          });
        }
      }

      test('the first of three, in Outlook angle brackets', () {
        expect(
          extractJoinUrl(
            'Webex<${_samples[MeetingService.webex]}>\n'
            'Teams<${_samples[MeetingService.teams]}>\n'
            'Zoom<${_samples[MeetingService.zoom]}>\n',
            null,
          ),
          _samples[MeetingService.webex],
        );
      });

      test('the same link twice gives that link', () {
        const link = 'https://meet.google.com/abc-defg-hij';
        expect(extractJoinUrl('$link\n$link', null), link);
      });

      test('a wrapped link counts at the place where its wrapper starts', () {
        final wrapped = safeLinks(
          'https%3A%2F%2Fus02web.zoom.us%2Fj%2F98765432109%3Fpwd%3Ddef456',
        );
        final teams = _samples[MeetingService.teams];
        expect(
          extractJoinUrl('Zoom <$wrapped> or Teams $teams', null),
          'https://us02web.zoom.us/j/98765432109?pwd=def456',
        );
        expect(extractJoinUrl('Teams $teams or Zoom <$wrapped>', null), teams);
      });

      test('a page that is no join link is not counted', () {
        expect(
          extractJoinUrl(
            'Get the app at https://zoom.us/download and join at ${_samples[MeetingService.zoom]}',
            null,
          ),
          _samples[MeetingService.zoom],
        );
        expect(
          extractJoinUrl(
            'More phone numbers: https://tel.meet/abc-defg-hij?pin=1234567890\n'
            'Join: https://meet.google.com/abc-defg-hij',
            null,
          ),
          'https://meet.google.com/abc-defg-hij',
        );
        expect(
          extractJoinUrl(
            'Channel: https://teams.microsoft.com/l/channel/19%3aabc%40thread.tacv2/General\n'
            'Join: ${_samples[MeetingService.teams]}',
            null,
          ),
          _samples[MeetingService.teams],
        );
      });

      test('a Google invite gives the Meet link, not its help links', () {
        const description =
            'Join with Google Meet: https://meet.google.com/abc-defg-hij\n'
            'More phone numbers: https://tel.meet/abc-defg-hij?pin=1234567890\n'
            'Learn more about Meet at: https://support.google.com/a/users/answer/9282720\n';
        expect(
          extractJoinUrl(description, null),
          'https://meet.google.com/abc-defg-hij',
        );
      });
    });

    group('the description is searched before the location', () {
      for (final inDescription in MeetingService.values) {
        for (final inLocation in MeetingService.values) {
          if (inDescription == inLocation) continue;
          test('${inDescription.label} in the description, '
              '${inLocation.label} in the location', () {
            expect(
              extractJoinUrl(_samples[inDescription], _samples[inLocation]),
              _samples[inDescription],
            );
          });
        }
      }

      test('the location is used when the description has no join link', () {
        for (final service in MeetingService.values) {
          final link = _samples[service];
          expect(extractJoinUrl(null, link), link);
          expect(extractJoinUrl('', link), link);
          expect(extractJoinUrl('Agenda: budget and hiring', link), link);
          expect(extractJoinUrl('https://zoom.us/download', link), link);
        }
      });
    });

    group('the conference value is searched before both', () {
      for (final service in MeetingService.values) {
        test('a ${service.label} link', () {
          final others = [
            for (final other in MeetingService.values)
              if (other != service) _samples[other]!,
          ];
          expect(
            extractJoinUrl(others[0], others[1], conference: _samples[service]),
            _samples[service],
          );
        });
      }

      test('it is searched like any other text', () {
        expect(
          extractJoinUrl(
            null,
            null,
            conference: 'Join: https://meet.google.com/abc-defg-hij\n',
          ),
          'https://meet.google.com/abc-defg-hij',
        );
      });

      test('a value with no join link is skipped', () {
        final zoom = _samples[MeetingService.zoom];
        final teams = _samples[MeetingService.teams];
        for (final conference in [
          null,
          '',
          '   ',
          'no link here',
          'https://hangouts.google.com/hangouts/_/abcdefghijklmnop',
          'https://zoom.us/download',
        ]) {
          expect(
            extractJoinUrl(zoom, teams, conference: conference),
            zoom,
            reason: 'description after: $conference',
          );
          expect(
            extractJoinUrl(null, teams, conference: conference),
            teams,
            reason: 'location after: $conference',
          );
        }
      });
    });
  });

  group('an accepted Google invite in Outlook', () {
    final meetWrapped = safeLinks(
      'https%3A%2F%2Fmeet.google.com%2Fabc-defg-hij%3Fhs%3D224',
    );
    final telWrapped = safeLinks(
      'https%3A%2F%2Ftel.meet%2Fabc-defg-hij%3Fpin%3D1234567890',
    );
    const plainLocation = 'https://meet.google.com/abc-defg-hij';

    test('the Safe Links form in the description beats the plain location', () {
      final description =
          'Join with Google Meet\n'
          'meet.google.com/abc-defg-hij<$meetWrapped>\n\n'
          'More phone numbers\n'
          'tel.meet/abc-defg-hij<$telWrapped>\n';
      expect(
        extractJoinUrl(description, plainLocation),
        'https://meet.google.com/abc-defg-hij?hs=224',
      );
    });

    test('bare text without https is ignored, so the location is used', () {
      const description =
          'Join with Google Meet\nmeet.google.com/abc-defg-hij\n';
      expect(extractJoinUrl(description, null), isNull);
      expect(extractJoinUrl(description, plainLocation), plainLocation);
    });

    test('the wrapper around the phone numbers page is not a join link', () {
      expect(
        extractJoinUrl('tel.meet/abc-defg-hij<$telWrapped>\n', null),
        isNull,
      );
    });
  });

  group('malformed text never throws', () {
    test('a broken percent escape, wrapped or not', () {
      for (final text in _brokenEncodings) {
        expect(
          () => extractJoinUrl(text, null),
          returnsNormally,
          reason: 'description: $text',
        );
        expect(
          () => extractJoinUrl(null, text),
          returnsNormally,
          reason: 'location: $text',
        );
        expect(
          () => extractJoinUrl(null, null, conference: text),
          returnsNormally,
          reason: 'conference: $text',
        );
        expect(
          () => meetingServiceOf(text),
          returnsNormally,
          reason: 'service of: $text',
        );
      }
    });

    test(
      'a candidate with a broken escape is skipped and the search goes on',
      () {
        const location = 'https://example.zoom.us/j/12345678901';
        for (final broken in [
          'https%3A%2F%2Fexample.zoom.us%2Fj%2F%zz',
          'https%3A%2F%2Fmeet.google.com%2F%zz',
          'https%3A%2F%2Fexample.webex.com%2Fmeet%2F%zz',
        ]) {
          expect(extractJoinUrl(broken, location), location, reason: broken);
        }
      },
    );
  });
}
