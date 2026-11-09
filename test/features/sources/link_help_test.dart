import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tminus/app/di.dart';
import 'package:tminus/app/theme/tminus_theme.dart';
import 'package:tminus/core/storage/source_repository.dart';
import 'package:tminus/features/sources/link_help.dart';
import 'package:tminus/features/sources/problem_card.dart';

import '../harness.dart';
import 'source_test_support.dart';

/// Google's public holiday feed: a real Google link that is no one's secret.
const _googleLink =
    'https://calendar.google.com/calendar/ical/'
    'en.usa%23holiday%40group.v.calendar.google.com/public/basic.ics';

Finder _linkField() => find.byKey(const Key('icsLinkField'));

LinkProvider _shown(WidgetTester t) => t
    .widget<SegmentedButton<LinkProvider>>(
      find.byKey(const Key('linkProvider')),
    )
    .selected
    .single;

String _name(WidgetTester t) => t
    .widget<TextField>(find.byKey(const Key('newSourceName')))
    .controller!
    .text;

String? _hint(WidgetTester t) =>
    t.widget<TextField>(_linkField()).decoration!.hintText;

Future<void> _choose(WidgetTester t, LinkProvider p) async {
  await t.tap(find.byKey(Key('linkProvider-${p.name}')));
  await t.pumpAndSettle();
}

/// Every request a test's feed client was asked for.
http.Client _recording(List<Uri> requested) => MockClient((request) async {
  requested.add(request.url);
  return http.Response(weekFeed, 200);
});

void _mockClipboard(String text) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    return call.method == 'Clipboard.getData' ? {'text': text} : null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
}

void main() {
  group('providerForLink', () {
    test('knows Outlook and Google by host, nothing else', () {
      expect(providerForLink(secretLink), LinkProvider.outlook);
      expect(
        providerForLink('webcal://OUTLOOK.LIVE.COM/owa/calendar/x/c.ics'),
        LinkProvider.outlook,
      );
      expect(providerForLink(_googleLink), LinkProvider.google);
      expect(providerForLink('  $_googleLink  '), LinkProvider.google);
      // A masked link (no scheme) works too: the sheet uses one.
      expect(providerForLink(maskedSecretLink), LinkProvider.outlook);
      expect(providerForLink('https://example.test/c.ics'), isNull);
      // The host, not a path or a look-alike host that contains it.
      expect(
        providerForLink('https://evil.test/calendar.google.com/basic.ics'),
        isNull,
      );
      expect(providerForLink('https://calendar.google.com.evil.test/'), isNull);
      expect(providerForLink(''), isNull);
    });
  });

  group('the add panel', () {
    testWidgets('the toggle shows each provider\'s steps and drawing', (
      t,
    ) async {
      tallScreen(t);
      final h = await pumpApp(t, location: '/sources/add');

      // Outlook first.
      expect(_shown(t), LinkProvider.outlook);
      expect(find.byKey(const Key('illustration-outlook')), findsOneWidget);
      expect(find.text(LinkProvider.outlook.steps.first), findsOneWidget);
      expect(_hint(t), LinkProvider.outlook.hint);

      await _choose(t, LinkProvider.google);
      expect(_shown(t), LinkProvider.google);
      expect(find.byKey(const Key('illustration-google')), findsOneWidget);
      expect(find.byKey(const Key('illustration-outlook')), findsNothing);
      for (final step in LinkProvider.google.steps) {
        expect(find.text(step), findsOneWidget);
      }
      expect(find.text(LinkProvider.outlook.steps.first), findsNothing);
      expect(_hint(t), LinkProvider.google.hint);

      await _choose(t, LinkProvider.other);
      expect(find.byKey(const Key('illustration-other')), findsOneWidget);
      expect(find.text('Any .ics or webcal:// link works.'), findsOneWidget);
      // One link field throughout.
      expect(_linkField(), findsOneWidget);
      await h.dispose(t);
    });

    testWidgets('the default name follows the choice', (t) async {
      tallScreen(t);
      final h = await pumpApp(t, location: '/sources/add');

      expect(_name(t), 'Work Outlook');
      await _choose(t, LinkProvider.google);
      expect(_name(t), 'Google Calendar');
      await _choose(t, LinkProvider.other);
      expect(_name(t), 'Calendar');
      await _choose(t, LinkProvider.outlook);
      expect(_name(t), 'Work Outlook');

      // A name the user typed stays.
      await t.enterText(find.byKey(const Key('newSourceName')), 'Team rota');
      await _choose(t, LinkProvider.google);
      expect(_name(t), 'Team rota');
      await h.dispose(t);
    });

    testWidgets('a Google link added with an empty name is Google Calendar', (
      t,
    ) async {
      tallScreen(t);
      final h = await pumpApp(
        t,
        location: '/sources/add',
        feeds: _recording([]),
      );

      await t.enterText(_linkField(), _googleLink);
      await t.pump();
      await t.tap(find.byKey(const Key('checkLink')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('newSourceName')), ' ');
      await t.pump();
      await t.tap(find.byKey(const Key('addCalendar')));
      await t.pumpAndSettle();

      expect(
        (await getIt<SourceRepository>().all()).single.name,
        'Google Calendar',
      );
      await h.dispose(t);
    });

    testWidgets('a link from a known host switches the toggle', (t) async {
      tallScreen(t);
      final h = await pumpApp(t, location: '/sources/add');

      await t.enterText(_linkField(), _googleLink);
      await t.pump();
      expect(_shown(t), LinkProvider.google);
      expect(_name(t), 'Google Calendar');
      expect(find.byKey(const Key('illustration-google')), findsOneWidget);

      await t.enterText(_linkField(), secretLink);
      await t.pump();
      expect(_shown(t), LinkProvider.outlook);
      expect(_name(t), 'Work Outlook');

      // A host it does not know leaves the choice alone.
      await _choose(t, LinkProvider.other);
      await t.enterText(_linkField(), 'https://example.test/c.ics');
      await t.pump();
      expect(_shown(t), LinkProvider.other);
      await h.dispose(t);
    });

    testWidgets('the user\'s own choice outlasts a tap on the field', (
      t,
    ) async {
      tallScreen(t);
      final h = await pumpApp(t, location: '/sources/add');

      await t.enterText(_linkField(), _googleLink);
      await t.pump();
      await _choose(t, LinkProvider.other);
      // Focus and selection changes notify the controller too.
      await t.tap(_linkField());
      await t.pumpAndSettle();
      expect(_shown(t), LinkProvider.other);
      await h.dispose(t);
    });

    testWidgets('a pasted link switches the toggle and fetches nothing', (
      t,
    ) async {
      tallScreen(t);
      final requested = <Uri>[];
      final h = await pumpApp(
        t,
        location: '/sources/add',
        feeds: _recording(requested),
      );
      _mockClipboard(_googleLink);

      await t.tap(find.byTooltip('Paste'));
      await t.pumpAndSettle();

      expect(_shown(t), LinkProvider.google);
      expect(requested, isEmpty);
      await h.dispose(t);
    });
  });

  group('How to find it', () {
    Future<void> openSheet(WidgetTester t, {LinkProvider? initial}) async {
      await t.pumpWidget(
        MaterialApp(
          theme: TMinusTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => initial == null
                    ? showFindLinkSheet(context)
                    : showFindLinkSheet(context, initial: initial),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
    }

    testWidgets('has the same toggle, steps and drawings', (t) async {
      tallScreen(t);
      await openSheet(t);

      expect(find.text('How to find your calendar link'), findsOneWidget);
      expect(_shown(t), LinkProvider.outlook);
      expect(
        t.widget<Text>(find.byKey(const Key('findLinkPath'))).data,
        LinkProvider.outlook.path,
      );
      expect(find.byKey(const Key('illustration-outlook')), findsOneWidget);

      await _choose(t, LinkProvider.google);
      expect(_shown(t), LinkProvider.google);
      expect(
        t.widget<Text>(find.byKey(const Key('findLinkPath'))).data,
        LinkProvider.google.path,
      );
      expect(find.byKey(const Key('illustration-google')), findsOneWidget);
      expect(find.text(LinkProvider.google.steps.last), findsOneWidget);
    });

    testWidgets('starts on the provider it is given', (t) async {
      tallScreen(t);
      await openSheet(t, initial: LinkProvider.google);
      expect(_shown(t), LinkProvider.google);
    });
  });
}
