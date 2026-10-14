import 'dart:convert';
import 'dart:math';

import '../model/alert.dart';
import '../model/alert_profile.dart';
import '../model/keyword_rule.dart';
import '../model/local_date.dart';
import '../model/skip_filters.dart';
import '../model/source_config.dart';
import '../sources/source_secrets.dart';
import '../storage/app_database.dart';
import '../storage/app_settings.dart';
import '../storage/profile_repository.dart';
import '../storage/rule_repository.dart';
import '../storage/settings_repository.dart';
import '../storage/source_repository.dart';

// Fixed texts. A message built from a file could quote a name, a pattern or a
// path, so a file that cannot be used is only ever described by these.
const _notOursMessage = 'This is not a T-Minus settings file.';
const _newerMessage = 'This file is from a newer version of T-Minus.';

/// Where the theme mode is stored (`ThemeModeController.settingsKey`). The app
/// layer owns the key and `core` does not import it; a test pins that the two
/// agree.
const _themeModeKey = 'ui.themeMode';
const _themeModes = {'system', 'dark', 'light'};

/// The longest lead time a file may carry, a year. The alert editor stops at a
/// day, so this only keeps out a number too large for a date, which would make
/// every plan fail.
const _maxOffsetMinutes = 365 * 24 * 60;

/// The ring timeout a file may carry, in seconds. The profile editor offers one
/// to five minutes.
const _minRingSeconds = 1;
const _maxRingSeconds = 60 * 60;

/// The tone pickers hand out content URIs. A tone with another scheme, `https:`
/// say, would have the alarm fetch it from the network when it rings.
const _toneScheme = 'content://';

/// What a profile or rule id from a file may be made of. The Alerts tab opens
/// them as route paths, so an id with a `/`, a `?` or a `%` in it could lead to
/// another screen. Every id the app makes fits: `p-` or `r-` and twelve hex
/// digits, and the built-in names.
final _idPattern = RegExp(r'^[A-Za-z0-9-]{1,64}$');

/// The route that makes a new profile or rule. An id of that name would open
/// the editor for a new one instead of the one it names.
const _newRouteId = 'new';

final _builtInIds = {for (final b in BuiltInProfiles.all) b.id};

/// A settings file that [SettingsTransfer.parse] has read and checked.
///
/// Profile and rule ids are unique, are made of letters, digits and hyphens
/// only (1 to 64 of them), and are not `new`. Every profile that a rule, a
/// source or the default names is in [profiles] or is a built-in one, and no
/// source is a debug source. Nothing in it identifies a link, a secure-storage
/// key, an Android calendar id or a sync state: a file never has them.
class TransferFile {
  TransferFile({
    required List<AlertProfile> profiles,
    required List<KeywordRule> rules,
    required this.skipFilters,
    required this.globalDefaultProfileId,
    required this.mergeEnabled,
    required List<TransferSource> sources,
    this.themeMode,
  }) : profiles = List.unmodifiable(profiles),
       rules = List.unmodifiable(rules),
       sources = List.unmodifiable(sources);

  final List<AlertProfile> profiles;
  final List<KeywordRule> rules;
  final SkipFilters skipFilters;
  final String globalDefaultProfileId;

  /// `system`, `dark` or `light`; null when the file says nothing about it.
  final String? themeMode;
  final bool mergeEnabled;
  final List<TransferSource> sources;
}

/// A source as a file describes it: a name, a colour, a kind and a default
/// profile. No id, link, storage key, calendar id or sync state.
class TransferSource {
  const TransferSource({
    required this.name,
    required this.color,
    required this.kind,
    this.defaultProfileId,
  });

  final String name;

  /// ARGB, as in [SourceConfig.color].
  final int color;

  /// [SourceKind.ics] or [SourceKind.device].
  final SourceKind kind;
  final String? defaultProfileId;

  @override
  bool operator ==(Object other) =>
      other is TransferSource &&
      other.name == name &&
      other.color == color &&
      other.kind == kind &&
      other.defaultProfileId == defaultProfileId;

  @override
  int get hashCode => Object.hash(name, color, kind, defaultProfileId);

  @override
  String toString() => 'TransferSource($name, ${kind.name})';
}

/// What an import is about to do, for the confirmation dialog.
class TransferSummary {
  const TransferSummary({
    required this.profiles,
    required this.rules,
    required this.icsSources,
    required this.phoneSources,
  });

  /// Every profile in the file, built-in ones included.
  final int profiles;
  final int rules;
  final int icsSources;
  final int phoneSources;

  @override
  bool operator ==(Object other) =>
      other is TransferSummary &&
      other.profiles == profiles &&
      other.rules == rules &&
      other.icsSources == icsSources &&
      other.phoneSources == phoneSources;

  @override
  int get hashCode => Object.hash(profiles, rules, icsSources, phoneSources);

  @override
  String toString() =>
      'TransferSummary(profiles: $profiles, rules: $rules, '
      'icsSources: $icsSources, phoneSources: $phoneSources)';
}

/// Exports profiles, rules, skip filters and a few settings as JSON, and reads
/// such a file back in (spec §10).
///
/// A file never holds a link, a secure-storage key, an Android calendar id or
/// a sync state: [exportJson] builds each source from four named fields, so
/// nothing else can get into it. Importing adds the file's sources as new,
/// disabled ones that wait for their link or calendar. No secret is written.
///
/// Nothing here logs. A file that cannot be used is a [FormatException] with
/// fixed text, never one that quotes the file.
class SettingsTransfer {
  /// Every repository must write to [db], so that an import's writes join its
  /// transaction. [random] is for tests; without it new source ids come from a
  /// secure source.
  SettingsTransfer({
    required this._db,
    required this._profiles,
    required this._rules,
    required this._settings,
    required this._sources,
    required this._appSettings,
    Random? random,
  }) : _random = random ?? Random.secure();

  static const format = 'tminus-settings';
  static const version = 1;

  final AppDatabase _db;
  final ProfileRepository _profiles;
  final RuleRepository _rules;
  final SettingsRepository _settings;
  final SourceRepository _sources;
  final AppSettings _appSettings;
  final Random _random;

  /// Every profile (the built-in ones can be edited), every rule, the skip
  /// filters, the default profile, the theme mode, the merge switch, and the
  /// phone and ICS sources. Pretty-printed.
  ///
  /// The file is made to import. It is read in one transaction, so a sync or an
  /// edit cannot come between two reads, and what the rules engine already
  /// ignores on this phone is left out: a rule that names a profile that is
  /// missing or cannot be read, a source default that does (none is written),
  /// and a default profile that does (Meeting is written). [parse] refuses a
  /// file that names a profile it does not hold.
  Future<String> exportJson({required DateTime nowUtc}) async {
    final document = await _db.transaction(() async {
      final profiles = await _profiles.all();
      final rules = await _rules.all();
      final skipFilters = await _settings.skipFilters();
      final globalDefault = await _settings.globalDefaultProfileId();
      final theme = await _settings.getString(_themeModeKey);
      final mergeEnabled = await _appSettings.mergeEnabled();
      final sources = await _sources.all();

      // What a rule or a default may name: the profiles in the file, and the
      // built-in ones, which every phone has. A profile whose row cannot be
      // read is not in the file, and so it is not named.
      final known = {for (final p in profiles) p.id, ..._builtInIds};
      return <String, Object?>{
        'format': format,
        'version': version,
        'exportedAtUtc': nowUtc.toUtc().toIso8601String(),
        'profiles': [for (final p in profiles) _profileToJson(p)],
        'rules': [
          for (final r in rules)
            if (known.contains(r.profileId)) _ruleToJson(r),
        ],
        'skipFilters': skipFilters.toJson(),
        'globalDefaultProfileId': known.contains(globalDefault)
            ? globalDefault
            : BuiltInProfiles.defaultId,
        // A stored value this build does not know would make the file unusable.
        'themeMode': _themeModes.contains(theme) ? theme : null,
        'mergeEnabled': mergeEnabled,
        'sources': [
          for (final s in sources)
            if (s.kind == SourceKind.ics || s.kind == SourceKind.device)
              _sourceToJson(s, known),
        ],
      };
    });
    return const JsonEncoder.withIndent('  ').convert(document);
  }

  /// `tminus-settings-2026-10-11.json`. [today] is the date on the phone.
  static String fileName(LocalDate today) =>
      'tminus-settings-${today.toIso()}.json';

  /// Reads and checks a file. Throws a [FormatException] with fixed text: the
  /// newer-version text for a file made by a later version, and "not a
  /// settings file" for everything else. Never the offending value.
  static TransferFile parse(String text) {
    try {
      final root = _readObject(jsonDecode(text));
      if (root['format'] != format) _refuse();
      final fileVersion = root['version'];
      if (fileVersion is! int || fileVersion < 1) _refuse();
      // A later version may be laid out differently, so it is told apart
      // before any other field is read.
      if (fileVersion > version) throw const _NewerVersion();
      final theme = root['themeMode'];
      final file = TransferFile(
        profiles: [
          for (final p in _readList(root['profiles'])) _readProfile(p),
        ],
        rules: [for (final r in _readList(root['rules'])) _readRule(r)],
        skipFilters: SkipFilters.tryFromJson(root['skipFilters']) ?? _refuse(),
        globalDefaultProfileId: _readId(root['globalDefaultProfileId']),
        themeMode: theme == null ? null : _readString(theme),
        mergeEnabled: _readBool(root['mergeEnabled']),
        sources: [for (final s in _readList(root['sources'])) _readSource(s)],
      );
      _check(file);
      return file;
    } on _NewerVersion {
      rethrow;
    } on FormatException {
      throw const FormatException(_notOursMessage);
    } on TypeError {
      throw const FormatException(_notOursMessage);
    }
  }

  static TransferSummary summarize(TransferFile f) => TransferSummary(
    profiles: f.profiles.length,
    rules: f.rules.length,
    icsSources: f.sources.where((s) => s.kind == SourceKind.ics).length,
    phoneSources: f.sources.where((s) => s.kind == SourceKind.device).length,
  );

  /// Replaces the profiles, rules, skip filters, default profile, theme mode
  /// and merge switch with the file's, and adds its sources, all in one
  /// transaction: it either happens completely or not at all. The file is
  /// checked first, as [parse] checks one, whether or not it came from there.
  ///
  /// User profiles that are not in the file are deleted with every reference
  /// to them, one whose row cannot be read too. Existing sources, overrides,
  /// history, the cache and the meeting links are left alone. A built-in
  /// profile keeps its name, and a tone that is not a content URI is dropped
  /// for the default tone. The caller re-plans afterwards and sets the theme
  /// mode on the theme controller.
  Future<void> import(TransferFile file) async {
    _check(file);
    await _db.transaction(() async {
      final inFile = {for (final p in file.profiles) p.id};
      for (final id in await _storedUserProfileIds()) {
        if (!inFile.contains(id)) await _profiles.delete(id);
      }
      for (final p in file.profiles) {
        await _profiles.save(_asStored(p));
      }

      for (final r in await _rules.all()) {
        await _rules.delete(r.id);
      }
      for (final r in file.rules) {
        await _rules.save(r);
      }

      await _settings.setSkipFilters(file.skipFilters);
      await _settings.setGlobalDefaultProfileId(file.globalDefaultProfileId);
      final theme = file.themeMode;
      if (theme != null) await _settings.setString(_themeModeKey, theme);
      await _appSettings.setMergeEnabled(file.mergeEnabled);

      for (final s in file.sources) {
        final ics = s.kind == SourceKind.ics;
        final id = await _freshSourceId(ics ? 'ics' : 'device');
        await _sources.save(
          SourceConfig(
            id: id,
            name: s.name,
            color: s.color,
            kind: s.kind,
            // Only the key a link will be stored under. The link is not in the
            // file, so nothing is written to secure storage.
            secureStorageKey: ics ? SourceSecrets.keyFor(id) : null,
            defaultProfileId: s.defaultProfileId,
            enabled: false,
          ),
        );
        await _appSettings.setSourceSetup(
          id,
          ics ? SourceSetup.needsLink : SourceSetup.needsCalendar,
        );
      }
    });
  }

  /// The ids of the user profiles in the table, whether their rows can be read
  /// or not. [ProfileRepository.all] leaves out a row it cannot read, and an
  /// import that went by that list would keep such a profile for good.
  Future<List<String>> _storedUserProfileIds() async {
    final p = _db.profiles;
    final rows = await (_db.selectOnly(p)..addColumns([p.id, p.builtIn])).get();
    return [
      for (final row in rows)
        if (row.read(p.builtIn) == false) row.read(p.id)!,
    ];
  }

  /// What is stored for a profile of the file. A built-in profile keeps its own
  /// name: the editor never changes it and the explanations quote it. A tone
  /// that is not a content URI becomes the default tone, so a file cannot make
  /// the alarm fetch its tone from the network when it rings.
  static AlertProfile _asStored(AlertProfile p) {
    var stored = p;
    for (final b in BuiltInProfiles.all) {
      if (b.id == p.id) stored = stored.copyWith(name: b.name);
    }
    final tone = p.sound.toneUri;
    if (tone != null && !tone.startsWith(_toneScheme)) {
      stored = stored.copyWith(
        sound: SoundSettings(
          vibrate: p.sound.vibrate,
          gradualVolume: p.sound.gradualVolume,
          ringTimeout: p.sound.ringTimeout,
        ),
      );
    }
    return stored;
  }

  /// An id no source has. [SourceRepository.save] replaces a row with the same
  /// id, so a collision must never reach it.
  Future<String> _freshSourceId(String prefix) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      final hex = [
        for (var i = 0; i < 6; i++)
          _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ].join();
      final id = '$prefix-$hex';
      if (await _sources.byId(id) == null) return id;
    }
    throw StateError('No unused source id');
  }

  /// What [parse] and [import] both require of a file, beyond the types of its
  /// fields: ids that can be used in a route and are not repeated, profiles
  /// that exist, and values the app can run with. Throws the fixed "not a
  /// settings file" error.
  static void _check(TransferFile f) {
    final profileIds = <String>{};
    for (final p in f.profiles) {
      if (!_isUsableId(p.id) || !profileIds.add(p.id)) _refuse();
      for (final a in p.alerts) {
        if (a.offsetMinutes < 0 || a.offsetMinutes > _maxOffsetMinutes) {
          _refuse();
        }
      }
      final ringSeconds = p.sound.ringTimeout.inSeconds;
      if (ringSeconds < _minRingSeconds || ringSeconds > _maxRingSeconds) {
        _refuse();
      }
    }
    final known = {...profileIds, ..._builtInIds};

    final ruleIds = <String>{};
    for (final r in f.rules) {
      if (!_isUsableId(r.id) ||
          !ruleIds.add(r.id) ||
          !known.contains(r.profileId)) {
        _refuse();
      }
    }

    for (final s in f.sources) {
      // A debug source would put the fast-alarms source on a real phone.
      if (s.kind != SourceKind.ics && s.kind != SourceKind.device) _refuse();
      final profileId = s.defaultProfileId;
      if (profileId != null && !known.contains(profileId)) _refuse();
    }

    if (!known.contains(f.globalDefaultProfileId)) _refuse();
    final theme = f.themeMode;
    if (theme != null && !_themeModes.contains(theme)) _refuse();
  }

  static Map<String, Object?> _profileToJson(AlertProfile p) => {
    'id': p.id,
    'name': p.name,
    'alerts': alertsToJson(p.alerts),
    'sound': p.sound.toJson(),
    'ringsInQuietMode': p.ringsInQuietMode,
  };

  static Map<String, Object?> _ruleToJson(KeywordRule r) => {
    'id': r.id,
    'position': r.position,
    'field': r.field.name,
    'match': r.match.name,
    'pattern': r.pattern,
    'profileId': r.profileId,
  };

  /// The four fields a file may say about a source, and nothing else. Do not
  /// add the id, [SourceConfig.secureStorageKey], the calendar id or the sync
  /// state here. A default profile that is not in [known] is written as none.
  static Map<String, Object?> _sourceToJson(
    SourceConfig s,
    Set<String> known,
  ) => {
    'name': s.name,
    'color': s.color,
    'kind': s.kind.name,
    'defaultProfileId': known.contains(s.defaultProfileId)
        ? s.defaultProfileId
        : null,
  };
}

/// A file made by a later version. A [FormatException] too, so it travels the
/// same way, but [SettingsTransfer.parse] lets it through unchanged.
class _NewerVersion extends FormatException {
  const _NewerVersion() : super(_newerMessage);
}

/// Throws the fixed error for a file that cannot be used.
Never _refuse() => throw const FormatException(_notOursMessage);

/// Whether a profile or rule id may be stored: it is made of the allowed
/// characters and is not the route that makes a new one.
bool _isUsableId(String id) => id != _newRouteId && _idPattern.hasMatch(id);

Map<String, Object?> _readObject(Object? raw) =>
    raw is Map<String, Object?> ? raw : _refuse();

List<Object?> _readList(Object? raw) => raw is List<Object?> ? raw : _refuse();

String _readString(Object? raw) => raw is String ? raw : _refuse();

/// A string that is not empty.
String _readId(Object? raw) =>
    raw is String && raw.isNotEmpty ? raw : _refuse();

int _readInt(Object? raw) => raw is int ? raw : _refuse();

bool _readBool(Object? raw) => raw is bool ? raw : _refuse();

/// An enum value by its name.
T _readEnum<T extends Enum>(List<T> values, Object? raw) =>
    (raw is String ? values.asNameMap()[raw] : null) ?? _refuse();

AlertProfile _readProfile(Object? raw) {
  final j = _readObject(raw);
  final id = _readId(j['id']);
  return AlertProfile(
    id: id,
    name: _readString(j['name']),
    alerts: alertsFromJson(j['alerts']),
    sound: _readSound(j['sound']),
    ringsInQuietMode: _readBool(j['ringsInQuietMode']),
    builtIn: _builtInIds.contains(id),
  );
}

/// The checks that reading a stored profile makes of its sound settings.
SoundSettings _readSound(Object? raw) {
  if (raw is Map<String, Object?> &&
      raw['toneUri'] is String? &&
      raw['vibrate'] is bool &&
      raw['gradualVolume'] is bool &&
      raw['ringTimeoutSec'] is int) {
    return SoundSettings.fromJson(raw);
  }
  return _refuse();
}

KeywordRule _readRule(Object? raw) {
  final j = _readObject(raw);
  return KeywordRule(
    id: _readId(j['id']),
    position: _readInt(j['position']),
    field: _readEnum(RuleField.values, j['field']),
    match: _readEnum(RuleMatch.values, j['match']),
    pattern: _readString(j['pattern']),
    profileId: _readId(j['profileId']),
  );
}

TransferSource _readSource(Object? raw) {
  final j = _readObject(raw);
  final profileId = j['defaultProfileId'];
  return TransferSource(
    name: _readString(j['name']),
    color: _readInt(j['color']),
    kind: _readEnum(SourceKind.values, j['kind']),
    defaultProfileId: profileId == null ? null : _readId(profileId),
  );
}
