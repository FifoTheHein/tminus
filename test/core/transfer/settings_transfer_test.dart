import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart'
    show QueryExecutor, QueryInterceptor, TransactionExecutor;
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/app/theme_mode_controller.dart';
import 'package:tminus/core/model/alert.dart';
import 'package:tminus/core/model/alert_profile.dart';
import 'package:tminus/core/model/event_override.dart';
import 'package:tminus/core/model/keyword_rule.dart';
import 'package:tminus/core/model/local_date.dart';
import 'package:tminus/core/model/skip_filters.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/sources/source_secrets.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/app_settings.dart';
import 'package:tminus/core/storage/override_repository.dart';
import 'package:tminus/core/storage/profile_repository.dart';
import 'package:tminus/core/storage/rule_repository.dart';
import 'package:tminus/core/storage/settings_repository.dart';
import 'package:tminus/core/storage/source_repository.dart';
import 'package:tminus/core/transfer/settings_transfer.dart';
import 'package:tminus/features/common/ids.dart';

import '../fixtures.dart';
import '../storage/test_database.dart';

const _notOurs = 'This is not a T-Minus settings file.';
const _newer = 'This file is from a newer version of T-Minus.';

const _focus = AlertProfile(
  id: 'p-focus',
  name: 'Focus',
  alerts: [
    AlertSpec(3, AlertStrength.alarm),
    AlertSpec(15, AlertStrength.headsUp),
  ],
  sound: SoundSettings(
    toneUri: 'content://tone/2',
    vibrate: false,
    gradualVolume: false,
    ringTimeout: Duration(minutes: 5),
  ),
  ringsInQuietMode: true,
);

const _work = SourceConfig(
  id: 'ics-3f9a1c',
  name: 'Work Outlook',
  color: 0xFF6AA0F5,
  kind: SourceKind.ics,
  secureStorageKey: 'ics-url.x',
  defaultProfileId: 'p-focus',
);

const _phone = SourceConfig(
  id: 'device-77aa20',
  name: 'Phone',
  color: 0xFF5BC489,
  kind: SourceKind.device,
  deviceCalendarId: '7',
);

const _fastAlarms = SourceConfig(
  id: 'debug-fast',
  name: 'Fast alarms',
  color: 0xFFEF5350,
  kind: SourceKind.debug,
);

/// A local profile that a file without it deletes.
const _old = AlertProfile(
  id: 'p-old',
  name: 'Old',
  alerts: [AlertSpec(5, AlertStrength.headsUp)],
);

/// A source that is on this phone before an import, and stays.
const _keep = SourceConfig(
  id: 'ics-keep',
  name: 'Keep me',
  color: 0xFF111111,
  kind: SourceKind.ics,
  secureStorageKey: 'ics-url.ics-keep',
);

KeywordRule ruleOf(
  String id,
  int position,
  String profileId, {
  RuleField field = RuleField.title,
  RuleMatch match = RuleMatch.contains,
  String pattern = 'standup',
}) => KeywordRule(
  id: id,
  position: position,
  field: field,
  match: match,
  pattern: pattern,
  profileId: profileId,
);

Map<String, Object?> profileJson(
  String id, {
  String? name,
  List<AlertSpec> alerts = const [AlertSpec(10, AlertStrength.headsUp)],
  SoundSettings sound = const SoundSettings(),
  bool ringsInQuietMode = false,
}) => {
  'id': id,
  'name': name ?? 'Profile $id',
  'alerts': alertsToJson(alerts),
  'sound': sound.toJson(),
  'ringsInQuietMode': ringsInQuietMode,
};

Map<String, Object?> ruleJson(
  String id,
  int position,
  String profileId, {
  String field = 'title',
  String match = 'contains',
  String pattern = 'standup',
}) => {
  'id': id,
  'position': position,
  'field': field,
  'match': match,
  'pattern': pattern,
  'profileId': profileId,
};

Map<String, Object?> sourceJson(
  String name,
  String kind, {
  String? defaultProfileId,
  int color = 0xFF6AA0F5,
}) => {
  'name': name,
  'color': color,
  'kind': kind,
  'defaultProfileId': defaultProfileId,
};

Map<String, Object?> docJson({
  List<Map<String, Object?>> profiles = const [],
  List<Map<String, Object?>> rules = const [],
  List<Map<String, Object?>> sources = const [],
  SkipFilters skipFilters = const SkipFilters(),
  String globalDefault = 'meeting',
  String? themeMode,
  bool mergeEnabled = true,
}) => {
  'format': 'tminus-settings',
  'version': 1,
  'exportedAtUtc': '2026-10-11T08:00:00.000Z',
  'profiles': profiles,
  'rules': rules,
  'skipFilters': skipFilters.toJson(),
  'globalDefaultProfileId': globalDefault,
  'themeMode': themeMode,
  'mergeEnabled': mergeEnabled,
  'sources': sources,
};

TransferFile fileOf(Map<String, Object?> doc) =>
    SettingsTransfer.parse(jsonEncode(doc));

/// A file with every kind of field filled in, as plain JSON that a test can
/// change one part of. A test that breaks a part writes LEAK into it, so a
/// message that quoted the file would show.
dynamic fullDoc() => jsonDecode(
  jsonEncode(
    docJson(
      profiles: [
        profileJson(
          'p-focus',
          name: 'Focus',
          alerts: const [
            AlertSpec(3, AlertStrength.alarm),
            AlertSpec(15, AlertStrength.headsUp),
          ],
          sound: const SoundSettings(
            toneUri: 'content://tone/2',
            vibrate: false,
            gradualVolume: false,
            ringTimeout: Duration(minutes: 5),
          ),
          ringsInQuietMode: true,
        ),
        profileJson('p-two', name: 'Two'),
      ],
      rules: [
        ruleJson('r-1', 0, 'p-focus'),
        ruleJson('r-2', 1, 'quick', field: 'hasJoinLink', pattern: ''),
      ],
      skipFilters: const SkipFilters(tentative: false),
      globalDefault: 'p-focus',
      themeMode: 'dark',
      mergeEnabled: false,
      sources: [
        sourceJson('Work Outlook', 'ics', defaultProfileId: 'p-focus'),
        sourceJson('Phone', 'device', color: 0xFF5BC489),
      ],
    ),
  ),
);

/// [SettingsTransfer.parse] must refuse [text] with [message] and nothing else:
/// no source text, and nothing of the file in what it says.
void expectRefused(String text, {String message = _notOurs, String? reason}) {
  expect(
    () => SettingsTransfer.parse(text),
    throwsA(
      isA<FormatException>()
          .having((e) => e.message, 'message', message)
          .having((e) => e.source, 'source', isNull)
          .having((e) => e.toString(), 'text', isNot(contains('LEAK'))),
    ),
    reason: reason,
  );
}

/// A rule store that fails on its second save, as a full disk would.
class _FailsOnSecondSave extends RuleRepository {
  _FailsOnSecondSave(super.db);

  var _saves = 0;

  @override
  Future<void> save(KeywordRule rule) async {
    if (++_saves == 2) throw StateError('disk full');
    await super.save(rule);
  }
}

/// A source store that cannot save, so that every write before it is done.
class _CannotSaveSources extends SourceRepository {
  _CannotSaveSources(super.db);

  @override
  Future<void> save(SourceConfig s) async => throw StateError('disk full');
}

/// Notes, in the order they happen, when a transaction begins, when one
/// commits and when a select runs.
class _StatementLog extends QueryInterceptor {
  final events = <String>[];

  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    events.add('begin');
    return super.beginTransaction(parent);
  }

  @override
  Future<void> commitTransaction(TransactionExecutor inner) {
    events.add('commit');
    return super.commitTransaction(inner);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    events.add('select');
    return super.runSelect(executor, statement, args);
  }
}

/// A random source that plays back fixed numbers.
class _Replay implements Random {
  _Replay(this._values);

  final List<int> _values;
  var _next = 0;

  @override
  int nextInt(int max) => _values[_next++];

  @override
  double nextDouble() => 0;

  @override
  bool nextBool() => false;
}

void main() {
  final now = DateTime.utc(2026, 10, 11, 8);

  late AppDatabase db;
  late ProfileRepository profiles;
  late RuleRepository rules;
  late SettingsRepository settings;
  late SourceRepository sources;
  late OverrideRepository overrides;
  late AppSettings appSettings;
  late SettingsTransfer transfer;

  SettingsTransfer buildTransfer({
    RuleRepository? ruleRepo,
    SourceRepository? sourceRepo,
    Random? random,
  }) => SettingsTransfer(
    db: db,
    profiles: profiles,
    rules: ruleRepo ?? rules,
    settings: settings,
    sources: sourceRepo ?? sources,
    appSettings: appSettings,
    random: random,
  );

  setUp(() {
    db = openTestDatabase();
    profiles = ProfileRepository(db);
    rules = RuleRepository(db);
    settings = SettingsRepository(db);
    sources = SourceRepository(db);
    overrides = OverrideRepository(db);
    appSettings = AppSettings(settings);
    transfer = buildTransfer();
  });
  tearDown(() => db.close());

  /// Every row of the tables an import writes to, as the database holds them.
  Future<Map<String, List<Map<String, Object?>>>> dump() async {
    final tables = <String, List<Map<String, Object?>>>{};
    for (final table in const [
      'profiles',
      'rules',
      'sources',
      'settings',
      'overrides',
    ]) {
      final rows = await db
          .customSelect('SELECT * FROM $table ORDER BY 1, 2')
          .get();
      tables[table] = [for (final row in rows) row.data];
    }
    return tables;
  }

  /// A user profile whose alerts cannot be read. The repository leaves such a
  /// row out of every list, so only the table itself shows it.
  Future<void> insertUnreadableProfile(String id) => db
      .into(db.profiles)
      .insert(
        ProfilesCompanion.insert(
          id: id,
          name: 'Unreadable',
          alertsJson: 'garbage',
          soundJson: jsonEncode(const SoundSettings().toJson()),
          ringsInQuietMode: false,
          builtIn: false,
          position: 90,
        ),
      );

  /// The ids in the profiles table itself, readable or not.
  Future<List<String>> storedProfileIds() async => [
    for (final row
        in await db.customSelect('SELECT id FROM profiles ORDER BY id').get())
      row.read<String>('id'),
  ];

  group('export', () {
    test('an export holds no link and no storage key', () async {
      await profiles.save(_focus);
      await sources.save(_work);
      await sources.save(_phone);
      // The sync state sits in the same row as the source. None of it may go.
      // The error quotes a link, which is what a leak would look like, so the
      // checks below for a link can fail.
      await sources.updateSyncState(
        _work.id,
        SourceSyncState(
          lastAttemptUtc: DateTime.utc(2026, 10, 11, 7),
          lastSuccessUtc: DateTime.utc(2026, 10, 11, 6),
          lastError:
              'https://outlook.office365.com/owa/calendar/s3cr3t/calendar.ics '
              'failed (HTTP 404).',
          httpEtag: 'etag-5c1f',
          httpLastModified: 'Sun, 11 Oct 2026 06:00:00 GMT',
          emptyStreak: 2,
        ),
      );

      final text = await transfer.exportJson(nowUtc: now);

      for (final forbidden in [
        'ics-url',
        'secureStorageKey',
        'deviceCalendarId',
        '"7"',
        'https://',
        'http://',
        'webcal',
        'office365',
        's3cr3t',
        'calendar.ics',
        _work.id,
        _phone.id,
        'etag-5c1f',
        'GMT',
        'HTTP 404',
        'lastError',
        'lastSuccess',
        'emptyStreak',
      ]) {
        expect(text, isNot(contains(forbidden)), reason: forbidden);
      }
      // A source is exactly these four fields.
      final doc = jsonDecode(text) as Map<String, dynamic>;
      final exported = (doc['sources'] as List).cast<Map<String, dynamic>>();
      expect(exported, hasLength(2));
      for (final s in exported) {
        expect(
          s.keys,
          unorderedEquals(['name', 'color', 'kind', 'defaultProfileId']),
        );
      }
    });

    test(
      'export then parse round-trips profiles, rules and settings',
      () async {
        await profiles.save(_focus);
        // A built-in can be edited, so it is exported with its edit.
        await profiles.save(
          BuiltInProfiles.quick.copyWith(
            alerts: const [AlertSpec(2, AlertStrength.alarm)],
            ringsInQuietMode: true,
          ),
        );
        await rules.save(ruleOf('r-1', 0, 'quick'));
        await rules.save(
          ruleOf(
            'r-2',
            1,
            'p-focus',
            field: RuleField.location,
            match: RuleMatch.regex,
            pattern: r'^Room (A|B)',
          ),
        );
        await rules.save(
          ruleOf(
            'r-3',
            2,
            'important',
            field: RuleField.hasJoinLink,
            pattern: '',
          ),
        );
        await settings.setSkipFilters(
          const SkipFilters(tentative: false, declined: false),
        );
        await settings.setGlobalDefaultProfileId('p-focus');
        await settings.setString(ThemeModeController.settingsKey, 'dark');
        await appSettings.setMergeEnabled(false);
        await sources.save(_work);
        await sources.save(_phone);

        final text = await transfer.exportJson(nowUtc: now);

        final doc = jsonDecode(text) as Map<String, dynamic>;
        expect(doc.keys, [
          'format',
          'version',
          'exportedAtUtc',
          'profiles',
          'rules',
          'skipFilters',
          'globalDefaultProfileId',
          'themeMode',
          'mergeEnabled',
          'sources',
        ]);
        expect(doc['format'], 'tminus-settings');
        expect(doc['version'], 1);
        expect(doc['exportedAtUtc'], '2026-10-11T08:00:00.000Z');
        expect(text, contains('\n  "profiles": ['), reason: 'pretty-printed');

        final file = SettingsTransfer.parse(text);
        expect(file.profiles, await profiles.all());
        expect(file.rules, await rules.all());
        expect(
          file.skipFilters,
          const SkipFilters(tentative: false, declined: false),
        );
        expect(file.globalDefaultProfileId, 'p-focus');
        expect(file.themeMode, 'dark');
        expect(file.mergeEnabled, isFalse);
        // By name, so the phone comes first.
        expect(file.sources, const [
          TransferSource(
            name: 'Phone',
            color: 0xFF5BC489,
            kind: SourceKind.device,
          ),
          TransferSource(
            name: 'Work Outlook',
            color: 0xFF6AA0F5,
            kind: SourceKind.ics,
            defaultProfileId: 'p-focus',
          ),
        ]);
      },
    );

    test('debug sources are not exported', () async {
      await profiles.save(_focus); // the Work source's default profile
      await sources.save(_fastAlarms);
      await sources.save(_work);

      final text = await transfer.exportJson(nowUtc: now);

      expect(text, isNot(contains('Fast alarms')));
      expect(text, isNot(contains('debug')));
      expect(SettingsTransfer.parse(text).sources.map((s) => s.name), [
        'Work Outlook',
      ]);
    });

    test('an export whose rules, source default and default name an '
        'unreadable profile can still be imported', () async {
      await profiles.save(_focus);
      await insertUnreadableProfile('p-bad');
      expect(await profiles.byId('p-bad'), isNull, reason: 'unreadable');
      // Everything that names the unreadable profile, and a rule and a source
      // default that name a profile that is not there at all. The rules engine
      // ignores each of them on this phone, and the file must not carry them.
      await rules.save(ruleOf('r-bad', 0, 'p-bad'));
      await rules.save(ruleOf('r-gone', 1, 'p-gone'));
      await rules.save(ruleOf('r-focus', 2, 'p-focus'));
      await rules.save(ruleOf('r-quick', 3, 'quick'));
      await sources.save(
        const SourceConfig(
          id: 'ics-bad',
          name: 'A bad default',
          color: 1,
          kind: SourceKind.ics,
          secureStorageKey: 'ics-url.ics-bad',
          defaultProfileId: 'p-bad',
        ),
      );
      await sources.save(
        const SourceConfig(
          id: 'ics-gone',
          name: 'B lost default',
          color: 2,
          kind: SourceKind.ics,
          secureStorageKey: 'ics-url.ics-gone',
          defaultProfileId: 'p-gone',
        ),
      );
      await sources.save(
        const SourceConfig(
          id: 'device-quick',
          name: 'Phone',
          color: 3,
          kind: SourceKind.device,
          deviceCalendarId: '7',
          defaultProfileId: 'quick',
        ),
      );
      await sources.save(_work); // its default, p-focus, can be read
      await settings.setGlobalDefaultProfileId('p-bad');

      final file = SettingsTransfer.parse(
        await transfer.exportJson(nowUtc: now),
      );

      // What the rules engine ignores is gone, and what it uses is not.
      expect(file.profiles.map((p) => p.id), [
        'meeting',
        'quick',
        'important',
        'silent',
        'p-focus',
      ]);
      expect(file.rules.map((r) => r.id), ['r-focus', 'r-quick']);
      expect(file.sources.map((s) => (s.name, s.defaultProfileId)), [
        ('A bad default', null),
        ('B lost default', null),
        ('Phone', 'quick'),
        ('Work Outlook', 'p-focus'),
      ]);
      expect(file.globalDefaultProfileId, 'meeting');

      // A default that names a profile the file holds travels as it is, a
      // built-in one included. One that names nothing there is Meeting.
      for (final (stored, written) in [
        ('p-gone', 'meeting'),
        ('p-focus', 'p-focus'),
        ('silent', 'silent'),
      ]) {
        await settings.setGlobalDefaultProfileId(stored);
        final text = await transfer.exportJson(nowUtc: now);
        expect(
          SettingsTransfer.parse(text).globalDefaultProfileId,
          written,
          reason: stored,
        );
      }

      await transfer.import(file);
      expect(await rules.all(), file.rules);
    });

    test('the export reads in one transaction', () async {
      await profiles.save(_focus);
      await rules.save(ruleOf('r-1', 0, 'p-focus'));
      await sources.save(_work);
      final log = _StatementLog();

      await db.runWithInterceptor(
        () => transfer.exportJson(nowUtc: now),
        interceptor: log,
      );

      // One transaction begins before the first read and commits after the
      // last, so a sync or an edit cannot come between two reads.
      expect(log.events.where((e) => e == 'select'), isNotEmpty);
      expect(log.events.first, 'begin');
      expect(log.events.last, 'commit');
      expect(log.events.where((e) => e == 'begin'), hasLength(1));
      expect(log.events.where((e) => e == 'commit'), hasLength(1));
    });

    test('the file name uses the local date', () {
      // 23:30 UTC on 11 October is already 12 October in Johannesburg.
      final instant = DateTime.utc(2026, 10, 11, 23, 30);

      expect(
        SettingsTransfer.fileName(LocalDate.of(instant, johannesburg)),
        'tminus-settings-2026-10-12.json',
      );
      expect(
        SettingsTransfer.fileName(LocalDate(2026, 10, 11)),
        'tminus-settings-2026-10-11.json',
      );
    });

    test('the theme mode travels only when there is one', () async {
      // Nothing stored: the key is there and null.
      var doc = jsonDecode(await transfer.exportJson(nowUtc: now));
      expect(doc.containsKey('themeMode'), isTrue);
      expect(doc['themeMode'], isNull);

      // A stored value this build does not know would make the file unusable.
      await settings.setString(ThemeModeController.settingsKey, 'sepia');
      final text = await transfer.exportJson(nowUtc: now);
      expect(jsonDecode(text)['themeMode'], isNull);
      expect(SettingsTransfer.parse(text).themeMode, isNull);

      await settings.setString(ThemeModeController.settingsKey, 'light');
      doc = jsonDecode(await transfer.exportJson(nowUtc: now));
      expect(doc['themeMode'], 'light');

      // A file that says nothing leaves the stored mode alone.
      await transfer.import(fileOf(docJson()));
      expect(
        await settings.getString(ThemeModeController.settingsKey),
        'light',
      );
    });
  });

  group('parse', () {
    test('a newer version is refused with its own message', () {
      for (final version in [2, 3, 100]) {
        final d = fullDoc();
        d['version'] = version;
        expectRefused(jsonEncode(d), message: _newer, reason: 'v$version');
      }
      // A later version may lay its fields out differently. It is still
      // reported as newer, not as unreadable.
      expectRefused(
        jsonEncode({
          'format': 'tminus-settings',
          'version': 2,
          'profiles': 'another layout',
        }),
        message: _newer,
      );
      // Another program's file is not "newer".
      expectRefused(jsonEncode({'format': 'other-app', 'version': 2}));
    });

    test('garbage, a wrong format, a bad enum, a negative offset and a rule '
        'naming an unknown profile are all refused, and the message never '
        'quotes the file', () {
      final valid = jsonEncode(fullDoc());
      expect(() => SettingsTransfer.parse(valid), returnsNormally);

      final texts = {
        'empty text': '',
        'text that is not JSON': 'LEAK this is not json',
        'a truncated file': valid.substring(0, valid.length ~/ 2),
        'an unclosed object': '{',
        'a list': '[]',
        'null': 'null',
        'a number': '42',
        'a string': '"LEAK"',
      };
      texts.forEach((name, text) => expectRefused(text, reason: name));

      final edits = <String, void Function(dynamic d)>{
        // The envelope.
        'another format': (d) => d['format'] = 'LEAK-format',
        'no format': (d) => d.remove('format'),
        'version zero': (d) => d['version'] = 0,
        'a negative version': (d) => d['version'] = -1,
        'a version that is text': (d) => d['version'] = '1',
        'a version with a fraction': (d) => d['version'] = 1.5,
        'no version': (d) => d.remove('version'),
        // Enums are read by name.
        'a rule field nobody knows': (d) =>
            d['rules'][0]['field'] = 'LEAK-field',
        'a rule match nobody knows': (d) =>
            d['rules'][0]['match'] = 'LEAK-match',
        'an alert strength nobody knows': (d) =>
            d['profiles'][0]['alerts'][0]['strength'] = 'LEAK-strength',
        'a source kind nobody knows': (d) =>
            d['sources'][0]['kind'] = 'LEAK-kind',
        // An alert cannot start before it is due.
        'a negative offset': (d) =>
            d['profiles'][0]['alerts'][0]['offsetMinutes'] = -5,
        // A rule needs a profile to pick.
        'a rule naming an unknown profile': (d) =>
            d['rules'][0]['profileId'] = 'LEAK-profile',
        // Every field has the type it should.
        'profiles that are not a list': (d) => d['profiles'] = {'LEAK': 1},
        'a profile that is not an object': (d) => d['profiles'][0] = 'LEAK',
        'a profile name that is not text': (d) => d['profiles'][0]['name'] = 5,
        'alerts that are not a list': (d) =>
            d['profiles'][0]['alerts'] = 'LEAK',
        'an offset that is text': (d) =>
            d['profiles'][0]['alerts'][0]['offsetMinutes'] = '5',
        'a profile with no sound': (d) => d['profiles'][0].remove('sound'),
        'a vibrate flag that is text': (d) =>
            d['profiles'][0]['sound']['vibrate'] = 'LEAK',
        'a ring timeout that is text': (d) =>
            d['profiles'][0]['sound']['ringTimeoutSec'] = '120',
        'a quiet-mode flag that is a number': (d) =>
            d['profiles'][0]['ringsInQuietMode'] = 1,
        'rules that are not a list': (d) => d['rules'] = 'LEAK',
        'a rule position that is text': (d) => d['rules'][0]['position'] = '0',
        'a rule pattern that is a number': (d) => d['rules'][0]['pattern'] = 5,
        'skip filters of the wrong type': (d) =>
            d['skipFilters'] = {'allDay': 'LEAK'},
        'no skip filters': (d) => d.remove('skipFilters'),
        'a default profile that is a number': (d) =>
            d['globalDefaultProfileId'] = 5,
        'a theme that is a number': (d) => d['themeMode'] = 5,
        'a merge flag that is text': (d) => d['mergeEnabled'] = 'LEAK',
        'no merge flag': (d) => d.remove('mergeEnabled'),
        'sources that are not a list': (d) => d['sources'] = 'LEAK',
        'a source name that is a number': (d) => d['sources'][0]['name'] = 5,
        'a source colour that is text': (d) =>
            d['sources'][0]['color'] = '0xFF6AA0F5',
        'a source colour with a fraction': (d) =>
            d['sources'][0]['color'] = 1.5,
        // Every part of a list is checked, not only the list.
        'a rule that is not an object': (d) => d['rules'][0] = 'LEAK',
        'a source that is not an object': (d) => d['sources'][0] = 'LEAK',
        'an alert that is not an object': (d) =>
            d['profiles'][0]['alerts'][0] = 'LEAK',
        'sound that is not an object': (d) =>
            d['profiles'][0]['sound'] = 'LEAK',
        'skip filters that are not an object': (d) => d['skipFilters'] = 'LEAK',
        // Ids, names and enums are text, whatever else they look like.
        'a profile id that is a number': (d) => d['profiles'][0]['id'] = 5,
        'a rule id that is a number': (d) => d['rules'][0]['id'] = 5,
        'a rule field that is a number': (d) => d['rules'][0]['field'] = 5,
        'a rule profile that is a number': (d) =>
            d['rules'][0]['profileId'] = 5,
        'an alert strength that is a number': (d) =>
            d['profiles'][0]['alerts'][0]['strength'] = 5,
        'a source kind that is a number': (d) => d['sources'][0]['kind'] = 5,
        'a source default that is a number': (d) =>
            d['sources'][0]['defaultProfileId'] = 5,
        'no default profile': (d) => d.remove('globalDefaultProfileId'),
        // The sound settings, field by field.
        'a tone that is a number': (d) =>
            d['profiles'][0]['sound']['toneUri'] = 5,
        'a gradual-volume flag that is text': (d) =>
            d['profiles'][0]['sound']['gradualVolume'] = 'LEAK',
      };
      edits.forEach((name, edit) {
        final d = fullDoc();
        edit(d);
        expectRefused(jsonEncode(d), reason: name);
      });
    });

    test('a file the app cannot run with is refused, and the limits '
        'themselves are accepted', () {
      final edits = <String, void Function(dynamic d)>{
        // A debug source would put the fast-alarms source on a real phone.
        'a debug source': (d) => d['sources'][0]['kind'] = 'debug',
        'a profile with no id': (d) => d['profiles'][0]['id'] = '',
        'two profiles with one id': (d) => d['profiles'][1]['id'] = 'p-focus',
        'a rule with no id': (d) => d['rules'][0]['id'] = '',
        'two rules with one id': (d) => d['rules'][1]['id'] = 'r-1',
        // A lead time too large for a date would make every plan fail.
        'a lead time beyond a year': (d) =>
            d['profiles'][0]['alerts'][0]['offsetMinutes'] = 525601,
        'a lead time too large for a date': (d) =>
            d['profiles'][0]['alerts'][0]['offsetMinutes'] = 1000000000000000,
        'a ring timeout of zero': (d) =>
            d['profiles'][0]['sound']['ringTimeoutSec'] = 0,
        'a ring timeout of a day': (d) =>
            d['profiles'][0]['sound']['ringTimeoutSec'] = 86400,
        'a source default naming an unknown profile': (d) =>
            d['sources'][0]['defaultProfileId'] = 'p-LEAK',
        'a default profile that is not in the file': (d) =>
            d['globalDefaultProfileId'] = 'p-LEAK',
        'a theme nobody knows': (d) => d['themeMode'] = 'LEAK-theme',
      };
      edits.forEach((name, edit) {
        final d = fullDoc();
        edit(d);
        expectRefused(jsonEncode(d), reason: name);
      });

      // The limits are inclusive.
      final d = fullDoc();
      d['profiles'][0]['alerts'][0]['offsetMinutes'] = 525600;
      d['profiles'][0]['alerts'][1]['offsetMinutes'] = 0;
      d['profiles'][0]['sound']['ringTimeoutSec'] = 3600;
      d['profiles'][1]['sound']['ringTimeoutSec'] = 1;
      d['profiles'][1]['sound']['toneUri'] = null;
      expect(() => SettingsTransfer.parse(jsonEncode(d)), returnsNormally);
      // Every theme, none at all, a source with no default, and the built-ins
      // by id without being in the file.
      for (final theme in ['system', 'dark', 'light', null]) {
        d['themeMode'] = theme;
        expect(
          SettingsTransfer.parse(jsonEncode(d)).themeMode,
          theme,
          reason: '$theme',
        );
      }
      d['sources'][1].remove('defaultProfileId');
      d['globalDefaultProfileId'] = 'silent';
      d['rules'][0]['profileId'] = 'important';
      final file = SettingsTransfer.parse(jsonEncode(d));
      expect(file.sources[1].defaultProfileId, isNull);
      expect(file.globalDefaultProfileId, 'silent');
    });

    test('a profile or rule id outside [A-Za-z0-9-]{1,64}, or "new", is '
        'refused', () async {
      // The Alerts tab opens an id as a route path. A `/` or a `?` in one could
      // lead to another screen, and `new` is the screen that makes a profile or
      // a rule.
      final tooLong = 'LEAK'.padRight(65, 'x');
      for (final id in [
        'new',
        'a/b',
        'x?y',
        'a.b',
        'a_b',
        'a b',
        'a%2Fb',
        tooLong,
      ]) {
        final inProfile = fullDoc();
        inProfile['profiles'][1]['id'] = id; // p-two, which nothing names
        expectRefused(jsonEncode(inProfile), reason: 'profile id $id');

        final inRule = fullDoc();
        inRule['rules'][1]['id'] = id;
        expectRefused(jsonEncode(inRule), reason: 'rule id $id');
      }

      // An import checks as well, for a file that did not come from parse.
      final before = await dump();
      for (final unusable in [
        TransferFile(
          profiles: const [AlertProfile(id: 'a/b', name: 'Bad', alerts: [])],
          rules: const [],
          skipFilters: const SkipFilters(),
          globalDefaultProfileId: 'meeting',
          mergeEnabled: true,
          sources: const [],
        ),
        TransferFile(
          profiles: const [],
          rules: [ruleOf('new', 0, 'quick')],
          skipFilters: const SkipFilters(),
          globalDefaultProfileId: 'meeting',
          mergeEnabled: true,
          sources: const [],
        ),
      ]) {
        await expectLater(
          transfer.import(unusable),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              _notOurs,
            ),
          ),
        );
        expect(await dump(), before);
      }

      // Every id the app makes is accepted, and so are the limits. Only the
      // name `new` is kept back, not what merely starts or ends with it.
      final random = Random(7);
      final profileIds = [
        for (final b in BuiltInProfiles.all) b.id,
        for (var i = 0; i < 10; i++) newId('p', random),
        'p-0123456789ab',
        'P-ABC-xyz-09',
        'news',
        'x' * 64,
      ];
      final ruleIds = [
        for (var i = 0; i < 10; i++) newId('r', random),
        'r-fedcba987654',
        'R-1',
        'renew',
        'x' * 64,
      ];
      final file = fileOf(
        docJson(
          profiles: [for (final id in profileIds) profileJson(id)],
          rules: [
            for (final (i, id) in ruleIds.indexed) ruleJson(id, i, 'quick'),
          ],
        ),
      );
      expect(file.profiles.map((p) => p.id), profileIds);
      expect(file.rules.map((r) => r.id), ruleIds);
    });

    test('a profile id of exactly "custom" is refused', () async {
      // The event sheet adds a Custom row, with that id, to its list of
      // profiles. A profile with the same id would make two rows with one id,
      // and the list would crash.
      final inProfile = fullDoc();
      inProfile['profiles'][1]['id'] = 'custom'; // p-two, which nothing names
      expectRefused(jsonEncode(inProfile), reason: 'profile id custom');

      // An import checks as well, for a file that did not come from parse, and
      // changes nothing when it refuses.
      final before = await dump();
      await expectLater(
        transfer.import(
          TransferFile(
            profiles: const [
              AlertProfile(id: 'custom', name: 'Custom', alerts: []),
            ],
            rules: const [],
            skipFilters: const SkipFilters(),
            globalDefaultProfileId: 'meeting',
            mergeEnabled: true,
            sources: const [],
          ),
        ),
        throwsA(
          isA<FormatException>().having((e) => e.message, 'message', _notOurs),
        ),
      );
      expect(await dump(), before);

      // Only that exact id. Names that merely contain it, or differ in case,
      // are profiles like any other, and a rule may be called `custom`: the
      // Custom row is in the list of profiles, not in the list of rules.
      final file = fileOf(
        docJson(
          profiles: [
            profileJson('customer'),
            profileJson('custom-1'),
            profileJson('my-custom'),
            profileJson('Custom'),
          ],
          rules: [ruleJson('custom', 0, 'quick')],
        ),
      );
      expect(file.profiles.map((p) => p.id), [
        'customer',
        'custom-1',
        'my-custom',
        'Custom',
      ]);
      expect(file.rules.single.id, 'custom');
    });

    test('summarize counts profiles, rules and sources by kind', () {
      final file = fileOf(
        docJson(
          profiles: [
            profileJson('p-a'),
            profileJson('p-b'),
            profileJson('quick'),
          ],
          rules: [ruleJson('r-1', 0, 'p-a'), ruleJson('r-2', 1, 'p-b')],
          sources: [
            sourceJson('A', 'ics'),
            sourceJson('B', 'ics'),
            sourceJson('C', 'device'),
          ],
        ),
      );

      expect(
        SettingsTransfer.summarize(file),
        const TransferSummary(
          profiles: 3,
          rules: 2,
          icsSources: 2,
          phoneSources: 1,
        ),
      );
    });
  });

  group('import', () {
    test(
      'import replaces profiles and rules and keeps existing sources',
      () async {
        const phoneKeep = SourceConfig(
          id: 'device-keep',
          name: 'Phone',
          color: 0xFF222222,
          kind: SourceKind.device,
          deviceCalendarId: '3',
        );
        await profiles.save(_old);
        await rules.save(ruleOf('r-local', 0, 'p-old'));
        // Rules whose profile stays: only replacing the rules can remove the
        // first, and the second has the id of a rule in the file.
        await rules.save(ruleOf('r-extra', 1, 'important', pattern: 'review'));
        await rules.save(ruleOf('r-1', 5, 'important', pattern: 'old'));
        await settings.setGlobalDefaultProfileId('p-old');
        await settings.setString(ThemeModeController.settingsKey, 'dark');
        await sources.save(_keep);
        await sources.save(phoneKeep);

        final file = fileOf(
          docJson(
            profiles: [
              profileJson(
                'meeting',
                name: 'Meeting',
                alerts: const [AlertSpec(7, AlertStrength.alarm)],
                ringsInQuietMode: true,
              ),
              // Silent never has alerts, whatever a file says.
              profileJson(
                'silent',
                name: 'Silent',
                alerts: const [AlertSpec(5, AlertStrength.headsUp)],
              ),
              profileJson(
                'p-new',
                name: 'New',
                alerts: const [AlertSpec(20, AlertStrength.headsUp)],
                sound: const SoundSettings(
                  toneUri: 'content://tone/9',
                  vibrate: false,
                ),
              ),
            ],
            rules: [
              ruleJson('r-1', 0, 'quick'),
              ruleJson(
                'r-2',
                1,
                'p-new',
                field: 'location',
                match: 'regex',
                pattern: r'^Room \d$',
              ),
            ],
            skipFilters: const SkipFilters(tentative: false, declined: false),
            globalDefault: 'p-new',
            themeMode: 'light',
            mergeEnabled: false,
          ),
        );
        await transfer.import(file);

        // Profiles: the file's, the built-ins it does not mention untouched.
        expect((await profiles.all()).map((p) => p.id), [
          'meeting',
          'quick',
          'important',
          'silent',
          'p-new',
        ]);
        expect(
          await profiles.byId('meeting'),
          BuiltInProfiles.meeting.copyWith(
            alerts: const [AlertSpec(7, AlertStrength.alarm)],
            ringsInQuietMode: true,
          ),
        );
        expect(await profiles.byId('quick'), BuiltInProfiles.quick);
        expect((await profiles.byId('silent'))!.alerts, isEmpty);
        expect(await profiles.byId('p-new'), file.profiles[2]);
        expect(await profiles.byId('p-old'), isNull);
        // Rules: the file's, none of the old ones.
        expect(await rules.all(), file.rules);
        expect((await rules.all()).map((r) => r.id), ['r-1', 'r-2']);
        // Settings.
        expect(
          await settings.skipFilters(),
          const SkipFilters(tentative: false, declined: false),
        );
        expect(await settings.globalDefaultProfileId(), 'p-new');
        expect(
          await settings.getString(ThemeModeController.settingsKey),
          'light',
        );
        expect(await appSettings.mergeEnabled(), isFalse);
        // Sources: the two that were here are as they were, and need nothing.
        expect(await sources.all(), [_keep, phoneKeep]);
        expect(await appSettings.sourceSetup(_keep.id), SourceSetup.ready);
        expect(await appSettings.sourceSetup(phoneKeep.id), SourceSetup.ready);
      },
    );

    test('an imported user profile that rules point at survives; a local one '
        'not in the file is deleted with its references', () async {
      const gone = AlertProfile(
        id: 'p-gone',
        name: 'Gone',
        alerts: [AlertSpec(5, AlertStrength.headsUp)],
      );
      const stay = AlertProfile(
        id: 'p-stay',
        name: 'Stay',
        alerts: [AlertSpec(5, AlertStrength.headsUp)],
      );
      await profiles.save(gone);
      await profiles.save(stay);
      await rules.save(ruleOf('r-gone', 0, 'p-gone'));
      await sources.save(
        const SourceConfig(
          id: 'ics-keep',
          name: 'Keep',
          color: 1,
          kind: SourceKind.ics,
          secureStorageKey: 'ics-url.ics-keep',
          defaultProfileId: 'p-gone',
        ),
      );
      await sources.save(
        const SourceConfig(
          id: 'device-keep',
          name: 'Phone',
          color: 2,
          kind: SourceKind.device,
          deviceCalendarId: '3',
          defaultProfileId: 'p-stay',
        ),
      );
      await overrides.save(
        const EventOverride(
          scope: OverrideScope.occurrence,
          target: 'k1',
          profileId: 'p-gone',
          enabled: false,
        ),
      );
      await overrides.save(
        const EventOverride(
          scope: OverrideScope.occurrence,
          target: 'k2',
          profileId: 'p-gone',
        ),
      );
      await overrides.save(
        const EventOverride(
          scope: OverrideScope.occurrence,
          target: 'k3',
          profileId: 'p-stay',
        ),
      );
      await settings.setGlobalDefaultProfileId('p-gone');

      final file = fileOf(
        docJson(
          profiles: [
            profileJson(
              'p-stay',
              name: 'Stay v2',
              alerts: const [AlertSpec(1, AlertStrength.alarm)],
            ),
            profileJson('p-new', name: 'New'),
          ],
          rules: [
            ruleJson('r-new', 0, 'p-new'),
            ruleJson('r-stay', 1, 'p-stay', pattern: 'review'),
          ],
          globalDefault: 'p-new',
        ),
      );
      await transfer.import(file);

      // The profile the file lacks is gone, and so is every reference to it:
      // the source default, the profile of an override (k1 keeps its switch,
      // k2 had nothing else and is gone) and the default profile.
      expect(await profiles.byId('p-gone'), isNull);
      expect((await sources.byId('ics-keep'))!.defaultProfileId, isNull);
      expect(await overrides.find(OverrideScope.occurrence, 'k2'), isNull);
      // A profile that is in the file is updated where it is, so what points at
      // it keeps pointing at it.
      expect(
        await overrides.all(),
        unorderedEquals(const [
          EventOverride(
            scope: OverrideScope.occurrence,
            target: 'k1',
            enabled: false,
          ),
          EventOverride(
            scope: OverrideScope.occurrence,
            target: 'k3',
            profileId: 'p-stay',
          ),
        ]),
      );
      expect((await sources.byId('device-keep'))!.defaultProfileId, 'p-stay');
      // The profiles the file has, and the rules that point at them.
      expect(await profiles.byId('p-stay'), file.profiles[0]);
      expect(await profiles.byId('p-new'), file.profiles[1]);
      expect((await rules.all()).map((r) => (r.id, r.profileId)), [
        ('r-new', 'p-new'),
        ('r-stay', 'p-stay'),
      ]);
      expect(await settings.globalDefaultProfileId(), 'p-new');
    });

    test('an unreadable user profile that is not in the file is deleted by '
        'import', () async {
      // The repository lists only the profiles it can read, so an import that
      // went by that list would keep this one for good.
      await insertUnreadableProfile('p-bad');
      await sources.save(_keep.copyWith(defaultProfileId: 'p-bad'));
      await overrides.save(
        const EventOverride(
          scope: OverrideScope.occurrence,
          target: 'k1',
          profileId: 'p-bad',
          enabled: false,
        ),
      );
      // A built-in whose row cannot be read stays, as every built-in does.
      await db.customStatement(
        'UPDATE profiles SET alerts_json = ? WHERE id = ?',
        ['garbage', 'important'],
      );
      expect(await profiles.byId('p-bad'), isNull, reason: 'unreadable');
      expect(await storedProfileIds(), [
        'important',
        'meeting',
        'p-bad',
        'quick',
        'silent',
      ]);

      await transfer.import(fileOf(docJson()));

      expect(await storedProfileIds(), [
        'important',
        'meeting',
        'quick',
        'silent',
      ]);
      // It went as a profile goes, so nothing is left pointing at it.
      expect((await sources.byId('ics-keep'))!.defaultProfileId, isNull);
      expect(await overrides.all(), const [
        EventOverride(
          scope: OverrideScope.occurrence,
          target: 'k1',
          enabled: false,
        ),
      ]);
    });

    test('imported sources are disabled and need their link or calendar', () async {
      final file = fileOf(
        docJson(
          sources: [
            sourceJson('Work Outlook', 'ics', defaultProfileId: 'quick'),
            sourceJson('Personal', 'ics', color: 0xFF5BC489),
            sourceJson('Phone', 'device', color: 0xFFE8A33D),
          ],
        ),
      );
      await transfer.import(file);

      final added = await sources.all(); // by name
      expect(added.map((s) => s.name), ['Personal', 'Phone', 'Work Outlook']);
      expect(added.map((s) => s.id).toSet(), hasLength(3));
      expect(added.map((s) => s.color), [0xFF5BC489, 0xFFE8A33D, 0xFF6AA0F5]);
      expect(added.map((s) => s.defaultProfileId), [null, null, 'quick']);
      for (final s in added) {
        expect(s.enabled, isFalse, reason: s.name);
        expect(
          await sources.syncState(s.id),
          SourceSyncState(),
          reason: s.name,
        );
        switch (s.kind) {
          case SourceKind.ics:
            expect(s.id, matches(RegExp(r'^ics-[0-9a-f]{12}$')));
            // The key a link will be stored under; the link itself is not here.
            expect(s.secureStorageKey, SourceSecrets.keyFor(s.id));
            expect(s.deviceCalendarId, isNull);
            expect(await appSettings.sourceSetup(s.id), SourceSetup.needsLink);
          case SourceKind.device:
            expect(s.id, matches(RegExp(r'^device-[0-9a-f]{12}$')));
            expect(s.secureStorageKey, isNull);
            expect(s.deviceCalendarId, isNull);
            expect(
              await appSettings.sourceSetup(s.id),
              SourceSetup.needsCalendar,
            );
          case SourceKind.debug:
            fail('a debug source was imported');
        }
      }
    });

    test('imported sources get ids that no existing source has', () async {
      const taken = SourceConfig(
        id: 'ics-010203040506',
        name: 'Taken',
        color: 1,
        kind: SourceKind.ics,
        secureStorageKey: 'ics-url.ics-010203040506',
      );
      await sources.save(taken);
      // The first two ids this gives are the one that is taken.
      final replay = _Replay([
        1,
        2,
        3,
        4,
        5,
        6,
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        12,
      ]);

      await buildTransfer(random: replay)
          .import(fileOf(docJson(sources: [sourceJson('New', 'ics')])));

      expect(await sources.byId('ics-010203040506'), taken);
      expect((await sources.byId('ics-0708090a0b0c'))!.name, 'New');
      expect(await sources.all(), hasLength(2));
    });

    test('a file holding one source twice adds two sources with different '
        'ids', () async {
      // The first two ids this gives are the same, as chance could make them.
      const sameSix = [1, 2, 3, 4, 5, 6];
      final replay = _Replay([...sameSix, ...sameSix, 7, 8, 9, 10, 11, 12]);
      final source = sourceJson(
        'Work Outlook',
        'ics',
        defaultProfileId: 'quick',
      );

      await buildTransfer(random: replay)
          .import(fileOf(docJson(sources: [source, source])));

      // By name, then id: the one added first is first, and it is as the file
      // said. The second took the next id instead of replacing it.
      final first = SourceConfig(
        id: 'ics-010203040506',
        name: 'Work Outlook',
        color: 0xFF6AA0F5,
        kind: SourceKind.ics,
        secureStorageKey: SourceSecrets.keyFor('ics-010203040506'),
        defaultProfileId: 'quick',
        enabled: false,
      );
      final second = SourceConfig(
        id: 'ics-0708090a0b0c',
        name: 'Work Outlook',
        color: 0xFF6AA0F5,
        kind: SourceKind.ics,
        secureStorageKey: SourceSecrets.keyFor('ics-0708090a0b0c'),
        defaultProfileId: 'quick',
        enabled: false,
      );
      expect(await sources.all(), [first, second]);
      expect(await appSettings.sourceSetup(first.id), SourceSetup.needsLink);
      expect(await appSettings.sourceSetup(second.id), SourceSetup.needsLink);
    });

    test('a built-in profile keeps its name when a file renames it', () async {
      final file = fileOf(
        docJson(
          profiles: [
            profileJson(
              'meeting',
              name: 'Standup time',
              alerts: const [AlertSpec(7, AlertStrength.alarm)],
            ),
          ],
        ),
      );
      await transfer.import(file);

      final meeting = (await profiles.byId('meeting'))!;
      expect(meeting.name, 'Meeting');
      expect(meeting.alerts, const [AlertSpec(7, AlertStrength.alarm)]);
      expect(meeting.builtIn, isTrue);
    });

    test(
      'a tone that is not a content URI is stored as the default tone',
      () async {
        final file = fileOf(
          docJson(
            profiles: [
              // The alarm would fetch these when it rings.
              profileJson(
                'p-web',
                sound: const SoundSettings(
                  toneUri: 'https://example.com/tone.mp3',
                  vibrate: false,
                  ringTimeout: Duration(minutes: 3),
                ),
              ),
              profileJson(
                'p-file',
                sound: const SoundSettings(toneUri: 'file:///sdcard/tone.mp3'),
              ),
              profileJson(
                'p-phone',
                sound: const SoundSettings(
                  toneUri: 'content://media/internal/audio/media/7',
                ),
              ),
            ],
          ),
        );
        // The file is read as it is; what is stored is another matter.
        expect(file.profiles[0].sound.toneUri, 'https://example.com/tone.mp3');

        await transfer.import(file);

        // Only the tone goes. The rest of the sound settings stay.
        expect(
          (await profiles.byId('p-web'))!.sound,
          const SoundSettings(
            vibrate: false,
            ringTimeout: Duration(minutes: 3),
          ),
        );
        expect((await profiles.byId('p-file'))!.sound, const SoundSettings());
        expect(
          (await profiles.byId('p-phone'))!.sound.toneUri,
          'content://media/internal/audio/media/7',
        );
      },
    );

    test('import checks a file that did not come from parse, before it '
        'writes anything', () async {
      final before = await dump();
      final broken = <String, TransferFile>{
        // The profile would be written first.
        'a rule naming an unknown profile': TransferFile(
          profiles: [_focus],
          rules: [ruleOf('r-1', 0, 'p-missing')],
          skipFilters: const SkipFilters(),
          globalDefaultProfileId: 'meeting',
          mergeEnabled: true,
          sources: const [],
        ),
        'a debug source': TransferFile(
          profiles: [_focus],
          rules: const [],
          skipFilters: const SkipFilters(),
          globalDefaultProfileId: 'meeting',
          mergeEnabled: true,
          sources: const [
            TransferSource(
              name: 'Fast alarms',
              color: 1,
              kind: SourceKind.debug,
            ),
          ],
        ),
      };

      for (final entry in broken.entries) {
        await expectLater(
          transfer.import(entry.value),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              _notOurs,
            ),
          ),
          reason: entry.key,
        );
        expect(await dump(), before, reason: entry.key);
      }
    });

    test('a failure halfway leaves everything as it was', () async {
      await profiles.save(_old);
      await rules.save(ruleOf('r-local', 0, 'p-old'));
      await settings.setGlobalDefaultProfileId('p-old');
      await settings.setString(ThemeModeController.settingsKey, 'dark');
      await sources.save(_keep);
      final before = await dump();

      final file = fileOf(
        docJson(
          profiles: [profileJson('p-new', name: 'New')],
          rules: [ruleJson('r-1', 0, 'p-new'), ruleJson('r-2', 1, 'quick')],
          skipFilters: const SkipFilters(tentative: false),
          globalDefault: 'p-new',
          themeMode: 'light',
          mergeEnabled: false,
          sources: [sourceJson('Imported', 'ics')],
        ),
      );

      // The second rule fails: the old profile was deleted, the new one saved,
      // the old rule deleted and the first new rule saved by then.
      await expectLater(
        buildTransfer(ruleRepo: _FailsOnSecondSave(db)).import(file),
        throwsStateError,
      );
      expect(await dump(), before);
      expect((await profiles.all()).map((p) => p.id), isNot(contains('p-new')));
      expect(await profiles.byId('p-old'), _old);
      expect((await rules.all()).map((r) => r.id), ['r-local']);

      // The source fails: the settings were written by then too.
      await expectLater(
        buildTransfer(sourceRepo: _CannotSaveSources(db)).import(file),
        throwsStateError,
      );
      expect(await dump(), before);
      expect(await settings.globalDefaultProfileId(), 'p-old');
      expect(await settings.skipFilters(), const SkipFilters());
      expect(await settings.getString(ThemeModeController.settingsKey), 'dark');
      expect(await appSettings.mergeEnabled(), isTrue);

      // And the same file goes in once nothing fails.
      await transfer.import(file);
      expect((await rules.all()).map((r) => r.id), ['r-1', 'r-2']);
      expect(await sources.all(), hasLength(2));
    });
  });
}
