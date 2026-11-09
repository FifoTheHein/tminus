import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tminus/app/theme/tminus_theme.dart';
import 'package:tminus/core/sources/ics_link_probe.dart';
import 'package:tminus/features/sources/link_field.dart';

import '../../core/fixtures.dart' show initZones;
import 'source_test_support.dart';

Widget _host(Widget child) => MaterialApp(
  theme: TMinusTheme.dark(),
  home: Scaffold(body: child),
);

/// Answers `Clipboard.getData` with what [answer] returns (or throws).
void _mockClipboard(Object? Function() answer) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    return call.method == 'Clipboard.getData' ? answer() : null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'the link field is a URL field without autocorrect or suggestions',
    (t) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await t.pumpWidget(_host(LinkField(controller: controller)));

      final field = t.widget<TextField>(find.byKey(const Key('icsLinkField')));
      expect(field.keyboardType, TextInputType.url);
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);
      expect(field.maxLines, 1);
      expect(field.obscureText, isFalse);
      expect(field.smartDashesType, SmartDashesType.disabled);
      expect(field.smartQuotesType, SmartQuotesType.disabled);

      // Beyond the plan's list, each one a way for the link to leave the
      // field: null (not an empty list) turns autofill off, and the keyboard
      // is asked not to learn what is typed.
      expect(field.autofillHints, isNull);
      expect(field.enableIMEPersonalizedLearning, isFalse);
    },
  );

  // Beyond the plan's list.

  testWidgets(
    'the paste button fills the field with the trimmed clipboard text and '
    'does not submit it',
    (t) async {
      _mockClipboard(() => {'text': '  https://example.test/c.ics \n'});
      final controller = TextEditingController(text: 'old');
      addTearDown(controller.dispose);
      final submitted = <String>[];
      await t.pumpWidget(
        _host(LinkField(controller: controller, onSubmitted: submitted.add)),
      );

      await t.tap(find.byTooltip('Paste'));
      await t.pump();

      expect(controller.text, 'https://example.test/c.ics');
      // A paste only fills the field: submitting would start the check, and a
      // request must not go out before the user asks for one.
      expect(submitted, isEmpty);
    },
  );

  testWidgets('an empty clipboard changes nothing', (t) async {
    _mockClipboard(() => null);
    final controller = TextEditingController(text: 'old');
    addTearDown(controller.dispose);
    final submitted = <String>[];
    await t.pumpWidget(
      _host(LinkField(controller: controller, onSubmitted: submitted.add)),
    );

    await t.tap(find.byTooltip('Paste'));
    await t.pump();

    expect(controller.text, 'old');
    expect(submitted, isEmpty);
  });

  testWidgets('a clipboard that fails is logged by type and changes nothing', (
    t,
  ) async {
    final logs = captureLogs();
    _mockClipboard(
      () => throw PlatformException(
        code: 'clipboard',
        message: 'the user copied $secretLink',
      ),
    );
    final controller = TextEditingController(text: 'old');
    addTearDown(controller.dispose);
    final submitted = <String>[];
    await t.pumpWidget(
      _host(LinkField(controller: controller, onSubmitted: submitted.add)),
    );

    await t.tap(find.byTooltip('Paste'));
    await t.pump();

    expect(controller.text, 'old');
    expect(submitted, isEmpty);
    expect(logs.where((l) => l.startsWith('Pasting the link failed')), [
      'Pasting the link failed (PlatformException)',
    ]);
    expect(logs.join('\n'), isNot(contains(secretToken)));
    expect(logs.join('\n'), isNot(contains('copied')));
    releaseLogs();
  });

  test('the good news is counted in the singular and the plural', () {
    expect(foundText(23), 'Found 23 events this week');
    expect(foundText(1), 'Found 1 event this week');
    expect(foundText(0), 'Found 0 events this week');
  });

  group('LinkChecker', () {
    setUp(initZones);
    final now = DateTime.utc(2026, 10, 6, 7, 27);

    IcsLinkProbe probe(http.Client client) => IcsLinkProbe(
      client: client,
      deviceZone: () => 'Africa/Johannesburg',
      clock: () => now,
    );

    LinkChecker checkerFor(http.Client client) {
      final checker = LinkChecker(probe: probe(client));
      addTearDown(checker.dispose);
      return checker;
    }

    test(
      'a link that checks out is held until the text itself changes',
      () async {
        final checker = checkerFor(
          MockClient((_) async => http.Response(weekFeed, 200)),
        );
        checker.text.text = ' $secretLink ';

        await checker.check();

        expect(checker.state, LinkCheckState.found);
        expect(checker.found!.url, secretLink);
        expect(checker.found!.eventsThisWeek, 2);
        expect(checker.failure, isNull);

        // Moving the cursor is not an edit.
        checker.text.selection = const TextSelection.collapsed(offset: 3);
        expect(checker.state, LinkCheckState.found);

        // An edit forgets the result, so a link that was checked is never the
        // one that is saved after the field changed.
        checker.text.text = '$secretLink?x';
        expect(checker.state, LinkCheckState.idle);
        expect(checker.found, isNull);
      },
    );

    test('an answer for a link that was edited meanwhile is dropped', () async {
      final answer = Completer<http.Response>();
      final checker = checkerFor(MockClient((_) => answer.future));
      checker.text.text = secretLink;

      final pending = checker.check();
      expect(checker.state, LinkCheckState.checking);
      checker.text.text = 'https://other.test/c.ics';
      expect(checker.state, LinkCheckState.idle);
      answer.complete(http.Response(weekFeed, 200));
      await pending;

      expect(checker.state, LinkCheckState.idle);
      expect(checker.found, isNull);
    });

    test('a failing check keeps the probe\'s words', () async {
      final checker = checkerFor(
        MockClient((_) async => http.Response('', 404)),
      );
      checker.text.text = secretLink;

      await checker.check();

      expect(checker.state, LinkCheckState.failed);
      expect(
        checker.failure,
        'Link no longer works (HTTP 404). The calendar may have been '
        'unpublished.',
      );
      expect(checker.found, isNull);
    });

    test('nothing is fetched until a check is asked for', () async {
      var requests = 0;
      final checker = checkerFor(
        MockClient((_) async {
          requests++;
          return http.Response(weekFeed, 200);
        }),
      );
      // Every keystroke of a link would otherwise send the half-typed link to
      // whatever host it happens to name.
      for (final typed in ['h', 'https://', 'https://example.test/c.ics']) {
        checker.text.text = typed;
      }
      expect(requests, 0);
      expect(checker.state, LinkCheckState.idle);

      await checker.check();
      expect(requests, 1);
    });

    test('an empty field is not checked', () async {
      var requests = 0;
      final checker = checkerFor(
        MockClient((_) async {
          requests++;
          return http.Response(weekFeed, 200);
        }),
      );
      expect(checker.canCheck, isFalse);
      checker.text.text = '   ';
      expect(checker.canCheck, isFalse);

      await checker.check();

      expect(requests, 0);
      expect(checker.state, LinkCheckState.idle);
    });

    test('a check that is running is not started again', () async {
      var requests = 0;
      final answer = Completer<http.Response>();
      final checker = checkerFor(
        MockClient((_) {
          requests++;
          return answer.future;
        }),
      );
      checker.text.text = secretLink;

      final first = checker.check();
      final second = checker.check();
      answer.complete(http.Response(weekFeed, 200));
      await Future.wait([first, second]);

      expect(requests, 1);
      expect(checker.state, LinkCheckState.found);
    });

    test('clear forgets the link and its result', () async {
      final checker = checkerFor(
        MockClient((_) async => http.Response(weekFeed, 200)),
      );
      checker.text.text = secretLink;
      await checker.check();
      expect(checker.state, LinkCheckState.found);

      checker.clear();

      expect(checker.text.text, isEmpty);
      expect(checker.state, LinkCheckState.idle);
      expect(checker.found, isNull);
    });

    test('a check answered after clear leaves nothing found', () async {
      final answer = Completer<http.Response>();
      final checker = checkerFor(MockClient((_) => answer.future));
      checker.text.text = secretLink;

      final pending = checker.check();
      expect(checker.state, LinkCheckState.checking);
      checker.clear();
      answer.complete(http.Response(weekFeed, 200));
      await pending;

      // The answer was for a link that is gone: it must not bring it back.
      expect(checker.found, isNull);
      expect(checker.state, LinkCheckState.idle);
      expect(checker.text.text, isEmpty);
    });

    test('a check answered after dispose does not throw', () async {
      final answer = Completer<http.Response>();
      final checker = LinkChecker(
        probe: probe(MockClient((_) => answer.future)),
      );
      checker.text.text = secretLink;

      final pending = checker.check();
      // The dialog closed while the answer was on its way.
      checker.dispose();
      answer.complete(http.Response(weekFeed, 200));

      await expectLater(pending, completes);
    });
  });
}
