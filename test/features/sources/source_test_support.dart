import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/storage/app_database.dart';

import '../../core/fixtures.dart' show blue;
import '../harness.dart';

/// The secret link of the tests. Everything that must never show it looks for
/// [secretToken], its one unusual path segment.
const secretLink =
    'https://outlook.office365.com/owa/calendar/s3cr3t/calendar.ics';
const secretToken = 's3cr3t';

/// What the link shows as, everywhere it may show at all (`IcsUrl.mask`).
const maskedSecretLink = 'outlook.office365.com/…/calendar.ics';

/// [secretLink] over http, which the check flags as not encrypted.
const secretHttpLink =
    'http://outlook.office365.com/owa/calendar/s3cr3t/calendar.ics';

/// A second link, for what a re-link brings. Another host and another file
/// name, so its mask differs from [maskedSecretLink]: a screen that still shows
/// the old mask has not read the new link.
const freshLink = 'https://fresh.example.test/owa/calendar/fr3sh/work.ics';
const freshToken = 'fr3sh';
const maskedFreshLink = 'fresh.example.test/…/work.ics';

/// The platform channel that flutter_secure_storage 11 talks to. The harness
/// mocks it with a map; a test that needs a failing store mocks it again.
const secureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// Two events in the week after the harness's default clock (6 Oct 07:27 UTC)
/// and one far beyond it, so a probe reads "Found 2 events this week".
const weekFeed = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:a
DTSTART:20261006T100000Z
DTEND:20261006T103000Z
SUMMARY:Sprint planning
END:VEVENT
BEGIN:VEVENT
UID:b
DTSTART:20261007T080000Z
DTEND:20261007T083000Z
SUMMARY:Standup
END:VEVENT
BEGIN:VEVENT
UID:c
DTSTART:20261120T080000Z
DTEND:20261120T083000Z
SUMMARY:Later
END:VEVENT
END:VCALENDAR
''';

/// A surface tall enough that nothing a test taps is below the fold.
void tallScreen(WidgetTester t) {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

/// Secure storage whose writes wait for [release]: the app is caught in the
/// middle of a save. Reads and deletes go on working on the harness's map.
/// Mocks the channel again, so call it after `pumpApp` has set the harness up
/// (in its `seed`); the harness puts its own handler back at the end.
class HeldSecureWrites {
  HeldSecureWrites(Harness h) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
          final arguments = call.arguments as Map?;
          final key = arguments?['key'] as String?;
          switch (call.method) {
            case 'write':
              writes++;
              await _gate.future;
              h.secrets[key!] = arguments!['value'] as String;
              return null;
            case 'read':
              return h.secrets[key];
            case 'delete':
              h.secrets.remove(key);
              return null;
            case 'containsKey':
              return h.secrets.containsKey(key);
            default:
              return null;
          }
        });
  }

  final _gate = Completer<void>();

  /// How many writes were asked for, held or let through.
  int writes = 0;

  /// Lets the held writes (and later ones) through.
  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }
}

/// Everything the semantics tree says: each node's label, value, hint and
/// tooltip. Needs `t.ensureSemantics()`; dispose its handle before the test
/// ends.
String semanticsText(WidgetTester t) {
  final out = StringBuffer();
  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    out
      ..writeln(data.label)
      ..writeln(data.value)
      ..writeln(data.hint)
      ..writeln(data.tooltip);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  final root = t.binding.rootPipelineOwner.semanticsOwner?.rootSemanticsNode;
  if (root != null) visit(root);
  return out.toString();
}

/// Turns semantics on for the test and answers the function that turns it off.
/// Call that at the end of the test body: the test binding checks that no
/// handle is left, before any tear-down runs. A tear-down turns it off for a
/// test that failed on the way.
void Function() watchSemantics(WidgetTester t) {
  final handle = t.ensureSemantics();
  var off = false;
  void stop() {
    if (off) return;
    off = true;
    handle.dispose();
  }

  addTearDown(stop);
  return stop;
}

/// The message of every Tooltip in the tree, on screen or not.
String tooltipText(WidgetTester t) => [
  for (final tip in t.widgetList<Tooltip>(
    find.byType(Tooltip, skipOffstage: false),
  ))
    tip.message ?? tip.richMessage?.toPlainText() ?? '',
].join('\n');

/// Records every call on `SystemChannels.platform` (the clipboard, system UI)
/// for the rest of the test, and answers a clipboard read with [clipboard].
List<MethodCall> recordPlatformCalls({String? clipboard}) {
  final calls = <MethodCall>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    calls.add(call);
    if (call.method == 'Clipboard.getData' && clipboard != null) {
      return <String, Object?>{'text': clipboard};
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return calls;
}

void Function()? _putPrinterBack;

/// Collects what the app writes with `debugPrint`.
///
/// Call [releaseLogs] at the end of the test body, after the last look at the
/// list. The test binding checks that a test left `debugPrint` as it found it
/// when the body ends, which is before any `addTearDown` callback runs; the
/// tear-down here only covers a test that failed on the way.
List<String> captureLogs() {
  final logs = <String>[];
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) => logs.add(message ?? '');
  _putPrinterBack = () => debugPrint = original;
  addTearDown(releaseLogs);
  return logs;
}

/// Puts `debugPrint` back after [captureLogs].
void releaseLogs() {
  _putPrinterBack?.call();
  _putPrinterBack = null;
}

/// Every row of every table, as text.
Future<String> dumpDatabase(AppDatabase db) async {
  final out = StringBuffer();
  final tables = await db
      .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
      .get();
  for (final table in tables) {
    final name = table.read<String>('name');
    for (final row in await db.customSelect('SELECT * FROM "$name"').get()) {
      out.writeln('$name: ${row.data}');
    }
  }
  return out.toString();
}

/// Where the router is, as a path. Only for a location reached with `go`: the
/// uri of a pushed page is not part of it.
String pathOf(Harness h) =>
    h.router.routerDelegate.currentConfiguration.uri.path;

SourceConfig icsSource({
  String id = 'ics-1',
  String name = 'Work Outlook',
  int color = blue,
  bool enabled = true,
  String? defaultProfileId,
}) => SourceConfig(
  id: id,
  name: name,
  color: color,
  kind: SourceKind.ics,
  secureStorageKey: 'ics-url.$id',
  defaultProfileId: defaultProfileId,
  enabled: enabled,
);

SourceConfig phoneSource({
  String id = 'device-1',
  String name = 'Personal',
  int color = 0xFF5BC48A,
  String calendarId = '4',
  bool enabled = true,
}) => SourceConfig(
  id: id,
  name: name,
  color: color,
  kind: SourceKind.device,
  deviceCalendarId: calendarId,
  enabled: enabled,
);

/// One calendar as `queryDeviceCalendars` answers.
Map<String, Object?> phoneCalendar(
  String id,
  String name, {
  String? account,
  int color = 0xFF5BC48A,
}) => {
  'id': id,
  'name': name,
  'accountName': account,
  'color': color,
  'visible': true,
};
