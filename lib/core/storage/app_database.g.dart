// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $SourcesTable extends Sources with TableInfo<$SourcesTable, SourceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SourcesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<int> color = GeneratedColumn<int>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SourceKind, String> kind =
      GeneratedColumn<String>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<SourceKind>($SourcesTable.$converterkind);
  static const VerificationMeta _deviceCalendarIdMeta = const VerificationMeta(
    'deviceCalendarId',
  );
  @override
  late final GeneratedColumn<String> deviceCalendarId = GeneratedColumn<String>(
    'device_calendar_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _secureStorageKeyMeta = const VerificationMeta(
    'secureStorageKey',
  );
  @override
  late final GeneratedColumn<String> secureStorageKey = GeneratedColumn<String>(
    'secure_storage_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _defaultProfileIdMeta = const VerificationMeta(
    'defaultProfileId',
  );
  @override
  late final GeneratedColumn<String> defaultProfileId = GeneratedColumn<String>(
    'default_profile_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _lastAttemptUtcMsMeta = const VerificationMeta(
    'lastAttemptUtcMs',
  );
  @override
  late final GeneratedColumn<int> lastAttemptUtcMs = GeneratedColumn<int>(
    'last_attempt_utc_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSuccessUtcMsMeta = const VerificationMeta(
    'lastSuccessUtcMs',
  );
  @override
  late final GeneratedColumn<int> lastSuccessUtcMs = GeneratedColumn<int>(
    'last_success_utc_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _httpEtagMeta = const VerificationMeta(
    'httpEtag',
  );
  @override
  late final GeneratedColumn<String> httpEtag = GeneratedColumn<String>(
    'http_etag',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _httpLastModifiedMeta = const VerificationMeta(
    'httpLastModified',
  );
  @override
  late final GeneratedColumn<String> httpLastModified = GeneratedColumn<String>(
    'http_last_modified',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _emptyStreakMeta = const VerificationMeta(
    'emptyStreak',
  );
  @override
  late final GeneratedColumn<int> emptyStreak = GeneratedColumn<int>(
    'empty_streak',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    color,
    kind,
    deviceCalendarId,
    secureStorageKey,
    defaultProfileId,
    enabled,
    lastAttemptUtcMs,
    lastSuccessUtcMs,
    lastError,
    httpEtag,
    httpLastModified,
    emptyStreak,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sources';
  @override
  VerificationContext validateIntegrity(
    Insertable<SourceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    } else if (isInserting) {
      context.missing(_colorMeta);
    }
    if (data.containsKey('device_calendar_id')) {
      context.handle(
        _deviceCalendarIdMeta,
        deviceCalendarId.isAcceptableOrUnknown(
          data['device_calendar_id']!,
          _deviceCalendarIdMeta,
        ),
      );
    }
    if (data.containsKey('secure_storage_key')) {
      context.handle(
        _secureStorageKeyMeta,
        secureStorageKey.isAcceptableOrUnknown(
          data['secure_storage_key']!,
          _secureStorageKeyMeta,
        ),
      );
    }
    if (data.containsKey('default_profile_id')) {
      context.handle(
        _defaultProfileIdMeta,
        defaultProfileId.isAcceptableOrUnknown(
          data['default_profile_id']!,
          _defaultProfileIdMeta,
        ),
      );
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('last_attempt_utc_ms')) {
      context.handle(
        _lastAttemptUtcMsMeta,
        lastAttemptUtcMs.isAcceptableOrUnknown(
          data['last_attempt_utc_ms']!,
          _lastAttemptUtcMsMeta,
        ),
      );
    }
    if (data.containsKey('last_success_utc_ms')) {
      context.handle(
        _lastSuccessUtcMsMeta,
        lastSuccessUtcMs.isAcceptableOrUnknown(
          data['last_success_utc_ms']!,
          _lastSuccessUtcMsMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('http_etag')) {
      context.handle(
        _httpEtagMeta,
        httpEtag.isAcceptableOrUnknown(data['http_etag']!, _httpEtagMeta),
      );
    }
    if (data.containsKey('http_last_modified')) {
      context.handle(
        _httpLastModifiedMeta,
        httpLastModified.isAcceptableOrUnknown(
          data['http_last_modified']!,
          _httpLastModifiedMeta,
        ),
      );
    }
    if (data.containsKey('empty_streak')) {
      context.handle(
        _emptyStreakMeta,
        emptyStreak.isAcceptableOrUnknown(
          data['empty_streak']!,
          _emptyStreakMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SourceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SourceRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color'],
      )!,
      kind: $SourcesTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        )!,
      ),
      deviceCalendarId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_calendar_id'],
      ),
      secureStorageKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}secure_storage_key'],
      ),
      defaultProfileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}default_profile_id'],
      ),
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      lastAttemptUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_attempt_utc_ms'],
      ),
      lastSuccessUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_success_utc_ms'],
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      httpEtag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}http_etag'],
      ),
      httpLastModified: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}http_last_modified'],
      ),
      emptyStreak: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}empty_streak'],
      )!,
    );
  }

  @override
  $SourcesTable createAlias(String alias) {
    return $SourcesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<SourceKind, String, String> $converterkind =
      const EnumNameConverter<SourceKind>(SourceKind.values);
}

class SourceRow extends DataClass implements Insertable<SourceRow> {
  final String id;
  final String name;
  final int color;
  final SourceKind kind;
  final String? deviceCalendarId;
  final String? secureStorageKey;
  final String? defaultProfileId;
  final bool enabled;
  final int? lastAttemptUtcMs;
  final int? lastSuccessUtcMs;
  final String? lastError;
  final String? httpEtag;
  final String? httpLastModified;
  final int emptyStreak;
  const SourceRow({
    required this.id,
    required this.name,
    required this.color,
    required this.kind,
    this.deviceCalendarId,
    this.secureStorageKey,
    this.defaultProfileId,
    required this.enabled,
    this.lastAttemptUtcMs,
    this.lastSuccessUtcMs,
    this.lastError,
    this.httpEtag,
    this.httpLastModified,
    required this.emptyStreak,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['color'] = Variable<int>(color);
    {
      map['kind'] = Variable<String>($SourcesTable.$converterkind.toSql(kind));
    }
    if (!nullToAbsent || deviceCalendarId != null) {
      map['device_calendar_id'] = Variable<String>(deviceCalendarId);
    }
    if (!nullToAbsent || secureStorageKey != null) {
      map['secure_storage_key'] = Variable<String>(secureStorageKey);
    }
    if (!nullToAbsent || defaultProfileId != null) {
      map['default_profile_id'] = Variable<String>(defaultProfileId);
    }
    map['enabled'] = Variable<bool>(enabled);
    if (!nullToAbsent || lastAttemptUtcMs != null) {
      map['last_attempt_utc_ms'] = Variable<int>(lastAttemptUtcMs);
    }
    if (!nullToAbsent || lastSuccessUtcMs != null) {
      map['last_success_utc_ms'] = Variable<int>(lastSuccessUtcMs);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    if (!nullToAbsent || httpEtag != null) {
      map['http_etag'] = Variable<String>(httpEtag);
    }
    if (!nullToAbsent || httpLastModified != null) {
      map['http_last_modified'] = Variable<String>(httpLastModified);
    }
    map['empty_streak'] = Variable<int>(emptyStreak);
    return map;
  }

  SourcesCompanion toCompanion(bool nullToAbsent) {
    return SourcesCompanion(
      id: Value(id),
      name: Value(name),
      color: Value(color),
      kind: Value(kind),
      deviceCalendarId: deviceCalendarId == null && nullToAbsent
          ? const Value.absent()
          : Value(deviceCalendarId),
      secureStorageKey: secureStorageKey == null && nullToAbsent
          ? const Value.absent()
          : Value(secureStorageKey),
      defaultProfileId: defaultProfileId == null && nullToAbsent
          ? const Value.absent()
          : Value(defaultProfileId),
      enabled: Value(enabled),
      lastAttemptUtcMs: lastAttemptUtcMs == null && nullToAbsent
          ? const Value.absent()
          : Value(lastAttemptUtcMs),
      lastSuccessUtcMs: lastSuccessUtcMs == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSuccessUtcMs),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      httpEtag: httpEtag == null && nullToAbsent
          ? const Value.absent()
          : Value(httpEtag),
      httpLastModified: httpLastModified == null && nullToAbsent
          ? const Value.absent()
          : Value(httpLastModified),
      emptyStreak: Value(emptyStreak),
    );
  }

  factory SourceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SourceRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      color: serializer.fromJson<int>(json['color']),
      kind: $SourcesTable.$converterkind.fromJson(
        serializer.fromJson<String>(json['kind']),
      ),
      deviceCalendarId: serializer.fromJson<String?>(json['deviceCalendarId']),
      secureStorageKey: serializer.fromJson<String?>(json['secureStorageKey']),
      defaultProfileId: serializer.fromJson<String?>(json['defaultProfileId']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      lastAttemptUtcMs: serializer.fromJson<int?>(json['lastAttemptUtcMs']),
      lastSuccessUtcMs: serializer.fromJson<int?>(json['lastSuccessUtcMs']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      httpEtag: serializer.fromJson<String?>(json['httpEtag']),
      httpLastModified: serializer.fromJson<String?>(json['httpLastModified']),
      emptyStreak: serializer.fromJson<int>(json['emptyStreak']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'color': serializer.toJson<int>(color),
      'kind': serializer.toJson<String>(
        $SourcesTable.$converterkind.toJson(kind),
      ),
      'deviceCalendarId': serializer.toJson<String?>(deviceCalendarId),
      'secureStorageKey': serializer.toJson<String?>(secureStorageKey),
      'defaultProfileId': serializer.toJson<String?>(defaultProfileId),
      'enabled': serializer.toJson<bool>(enabled),
      'lastAttemptUtcMs': serializer.toJson<int?>(lastAttemptUtcMs),
      'lastSuccessUtcMs': serializer.toJson<int?>(lastSuccessUtcMs),
      'lastError': serializer.toJson<String?>(lastError),
      'httpEtag': serializer.toJson<String?>(httpEtag),
      'httpLastModified': serializer.toJson<String?>(httpLastModified),
      'emptyStreak': serializer.toJson<int>(emptyStreak),
    };
  }

  SourceRow copyWith({
    String? id,
    String? name,
    int? color,
    SourceKind? kind,
    Value<String?> deviceCalendarId = const Value.absent(),
    Value<String?> secureStorageKey = const Value.absent(),
    Value<String?> defaultProfileId = const Value.absent(),
    bool? enabled,
    Value<int?> lastAttemptUtcMs = const Value.absent(),
    Value<int?> lastSuccessUtcMs = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
    Value<String?> httpEtag = const Value.absent(),
    Value<String?> httpLastModified = const Value.absent(),
    int? emptyStreak,
  }) => SourceRow(
    id: id ?? this.id,
    name: name ?? this.name,
    color: color ?? this.color,
    kind: kind ?? this.kind,
    deviceCalendarId: deviceCalendarId.present
        ? deviceCalendarId.value
        : this.deviceCalendarId,
    secureStorageKey: secureStorageKey.present
        ? secureStorageKey.value
        : this.secureStorageKey,
    defaultProfileId: defaultProfileId.present
        ? defaultProfileId.value
        : this.defaultProfileId,
    enabled: enabled ?? this.enabled,
    lastAttemptUtcMs: lastAttemptUtcMs.present
        ? lastAttemptUtcMs.value
        : this.lastAttemptUtcMs,
    lastSuccessUtcMs: lastSuccessUtcMs.present
        ? lastSuccessUtcMs.value
        : this.lastSuccessUtcMs,
    lastError: lastError.present ? lastError.value : this.lastError,
    httpEtag: httpEtag.present ? httpEtag.value : this.httpEtag,
    httpLastModified: httpLastModified.present
        ? httpLastModified.value
        : this.httpLastModified,
    emptyStreak: emptyStreak ?? this.emptyStreak,
  );
  SourceRow copyWithCompanion(SourcesCompanion data) {
    return SourceRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      color: data.color.present ? data.color.value : this.color,
      kind: data.kind.present ? data.kind.value : this.kind,
      deviceCalendarId: data.deviceCalendarId.present
          ? data.deviceCalendarId.value
          : this.deviceCalendarId,
      secureStorageKey: data.secureStorageKey.present
          ? data.secureStorageKey.value
          : this.secureStorageKey,
      defaultProfileId: data.defaultProfileId.present
          ? data.defaultProfileId.value
          : this.defaultProfileId,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      lastAttemptUtcMs: data.lastAttemptUtcMs.present
          ? data.lastAttemptUtcMs.value
          : this.lastAttemptUtcMs,
      lastSuccessUtcMs: data.lastSuccessUtcMs.present
          ? data.lastSuccessUtcMs.value
          : this.lastSuccessUtcMs,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      httpEtag: data.httpEtag.present ? data.httpEtag.value : this.httpEtag,
      httpLastModified: data.httpLastModified.present
          ? data.httpLastModified.value
          : this.httpLastModified,
      emptyStreak: data.emptyStreak.present
          ? data.emptyStreak.value
          : this.emptyStreak,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SourceRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('kind: $kind, ')
          ..write('deviceCalendarId: $deviceCalendarId, ')
          ..write('secureStorageKey: $secureStorageKey, ')
          ..write('defaultProfileId: $defaultProfileId, ')
          ..write('enabled: $enabled, ')
          ..write('lastAttemptUtcMs: $lastAttemptUtcMs, ')
          ..write('lastSuccessUtcMs: $lastSuccessUtcMs, ')
          ..write('lastError: $lastError, ')
          ..write('httpEtag: $httpEtag, ')
          ..write('httpLastModified: $httpLastModified, ')
          ..write('emptyStreak: $emptyStreak')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    color,
    kind,
    deviceCalendarId,
    secureStorageKey,
    defaultProfileId,
    enabled,
    lastAttemptUtcMs,
    lastSuccessUtcMs,
    lastError,
    httpEtag,
    httpLastModified,
    emptyStreak,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SourceRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.color == this.color &&
          other.kind == this.kind &&
          other.deviceCalendarId == this.deviceCalendarId &&
          other.secureStorageKey == this.secureStorageKey &&
          other.defaultProfileId == this.defaultProfileId &&
          other.enabled == this.enabled &&
          other.lastAttemptUtcMs == this.lastAttemptUtcMs &&
          other.lastSuccessUtcMs == this.lastSuccessUtcMs &&
          other.lastError == this.lastError &&
          other.httpEtag == this.httpEtag &&
          other.httpLastModified == this.httpLastModified &&
          other.emptyStreak == this.emptyStreak);
}

class SourcesCompanion extends UpdateCompanion<SourceRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> color;
  final Value<SourceKind> kind;
  final Value<String?> deviceCalendarId;
  final Value<String?> secureStorageKey;
  final Value<String?> defaultProfileId;
  final Value<bool> enabled;
  final Value<int?> lastAttemptUtcMs;
  final Value<int?> lastSuccessUtcMs;
  final Value<String?> lastError;
  final Value<String?> httpEtag;
  final Value<String?> httpLastModified;
  final Value<int> emptyStreak;
  final Value<int> rowid;
  const SourcesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.color = const Value.absent(),
    this.kind = const Value.absent(),
    this.deviceCalendarId = const Value.absent(),
    this.secureStorageKey = const Value.absent(),
    this.defaultProfileId = const Value.absent(),
    this.enabled = const Value.absent(),
    this.lastAttemptUtcMs = const Value.absent(),
    this.lastSuccessUtcMs = const Value.absent(),
    this.lastError = const Value.absent(),
    this.httpEtag = const Value.absent(),
    this.httpLastModified = const Value.absent(),
    this.emptyStreak = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SourcesCompanion.insert({
    required String id,
    required String name,
    required int color,
    required SourceKind kind,
    this.deviceCalendarId = const Value.absent(),
    this.secureStorageKey = const Value.absent(),
    this.defaultProfileId = const Value.absent(),
    this.enabled = const Value.absent(),
    this.lastAttemptUtcMs = const Value.absent(),
    this.lastSuccessUtcMs = const Value.absent(),
    this.lastError = const Value.absent(),
    this.httpEtag = const Value.absent(),
    this.httpLastModified = const Value.absent(),
    this.emptyStreak = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       color = Value(color),
       kind = Value(kind);
  static Insertable<SourceRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? color,
    Expression<String>? kind,
    Expression<String>? deviceCalendarId,
    Expression<String>? secureStorageKey,
    Expression<String>? defaultProfileId,
    Expression<bool>? enabled,
    Expression<int>? lastAttemptUtcMs,
    Expression<int>? lastSuccessUtcMs,
    Expression<String>? lastError,
    Expression<String>? httpEtag,
    Expression<String>? httpLastModified,
    Expression<int>? emptyStreak,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (color != null) 'color': color,
      if (kind != null) 'kind': kind,
      if (deviceCalendarId != null) 'device_calendar_id': deviceCalendarId,
      if (secureStorageKey != null) 'secure_storage_key': secureStorageKey,
      if (defaultProfileId != null) 'default_profile_id': defaultProfileId,
      if (enabled != null) 'enabled': enabled,
      if (lastAttemptUtcMs != null) 'last_attempt_utc_ms': lastAttemptUtcMs,
      if (lastSuccessUtcMs != null) 'last_success_utc_ms': lastSuccessUtcMs,
      if (lastError != null) 'last_error': lastError,
      if (httpEtag != null) 'http_etag': httpEtag,
      if (httpLastModified != null) 'http_last_modified': httpLastModified,
      if (emptyStreak != null) 'empty_streak': emptyStreak,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SourcesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int>? color,
    Value<SourceKind>? kind,
    Value<String?>? deviceCalendarId,
    Value<String?>? secureStorageKey,
    Value<String?>? defaultProfileId,
    Value<bool>? enabled,
    Value<int?>? lastAttemptUtcMs,
    Value<int?>? lastSuccessUtcMs,
    Value<String?>? lastError,
    Value<String?>? httpEtag,
    Value<String?>? httpLastModified,
    Value<int>? emptyStreak,
    Value<int>? rowid,
  }) {
    return SourcesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      kind: kind ?? this.kind,
      deviceCalendarId: deviceCalendarId ?? this.deviceCalendarId,
      secureStorageKey: secureStorageKey ?? this.secureStorageKey,
      defaultProfileId: defaultProfileId ?? this.defaultProfileId,
      enabled: enabled ?? this.enabled,
      lastAttemptUtcMs: lastAttemptUtcMs ?? this.lastAttemptUtcMs,
      lastSuccessUtcMs: lastSuccessUtcMs ?? this.lastSuccessUtcMs,
      lastError: lastError ?? this.lastError,
      httpEtag: httpEtag ?? this.httpEtag,
      httpLastModified: httpLastModified ?? this.httpLastModified,
      emptyStreak: emptyStreak ?? this.emptyStreak,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (color.present) {
      map['color'] = Variable<int>(color.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(
        $SourcesTable.$converterkind.toSql(kind.value),
      );
    }
    if (deviceCalendarId.present) {
      map['device_calendar_id'] = Variable<String>(deviceCalendarId.value);
    }
    if (secureStorageKey.present) {
      map['secure_storage_key'] = Variable<String>(secureStorageKey.value);
    }
    if (defaultProfileId.present) {
      map['default_profile_id'] = Variable<String>(defaultProfileId.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (lastAttemptUtcMs.present) {
      map['last_attempt_utc_ms'] = Variable<int>(lastAttemptUtcMs.value);
    }
    if (lastSuccessUtcMs.present) {
      map['last_success_utc_ms'] = Variable<int>(lastSuccessUtcMs.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (httpEtag.present) {
      map['http_etag'] = Variable<String>(httpEtag.value);
    }
    if (httpLastModified.present) {
      map['http_last_modified'] = Variable<String>(httpLastModified.value);
    }
    if (emptyStreak.present) {
      map['empty_streak'] = Variable<int>(emptyStreak.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SourcesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('kind: $kind, ')
          ..write('deviceCalendarId: $deviceCalendarId, ')
          ..write('secureStorageKey: $secureStorageKey, ')
          ..write('defaultProfileId: $defaultProfileId, ')
          ..write('enabled: $enabled, ')
          ..write('lastAttemptUtcMs: $lastAttemptUtcMs, ')
          ..write('lastSuccessUtcMs: $lastSuccessUtcMs, ')
          ..write('lastError: $lastError, ')
          ..write('httpEtag: $httpEtag, ')
          ..write('httpLastModified: $httpLastModified, ')
          ..write('emptyStreak: $emptyStreak, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OverridesTable extends Overrides
    with TableInfo<$OverridesTable, OverrideRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OverridesTable(this.attachedDatabase, [this._alias]);
  @override
  late final GeneratedColumnWithTypeConverter<OverrideScope, String> scope =
      GeneratedColumn<String>(
        'scope',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<OverrideScope>($OverridesTable.$converterscope);
  static const VerificationMeta _targetMeta = const VerificationMeta('target');
  @override
  late final GeneratedColumn<String> target = GeneratedColumn<String>(
    'target',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profile_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _customAlertsJsonMeta = const VerificationMeta(
    'customAlertsJson',
  );
  @override
  late final GeneratedColumn<String> customAlertsJson = GeneratedColumn<String>(
    'custom_alerts_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    scope,
    target,
    profileId,
    customAlertsJson,
    enabled,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'overrides';
  @override
  VerificationContext validateIntegrity(
    Insertable<OverrideRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('target')) {
      context.handle(
        _targetMeta,
        target.isAcceptableOrUnknown(data['target']!, _targetMeta),
      );
    } else if (isInserting) {
      context.missing(_targetMeta);
    }
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    }
    if (data.containsKey('custom_alerts_json')) {
      context.handle(
        _customAlertsJsonMeta,
        customAlertsJson.isAcceptableOrUnknown(
          data['custom_alerts_json']!,
          _customAlertsJsonMeta,
        ),
      );
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {scope, target};
  @override
  OverrideRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OverrideRow(
      scope: $OverridesTable.$converterscope.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}scope'],
        )!,
      ),
      target: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target'],
      )!,
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      ),
      customAlertsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}custom_alerts_json'],
      ),
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      ),
    );
  }

  @override
  $OverridesTable createAlias(String alias) {
    return $OverridesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<OverrideScope, String, String> $converterscope =
      const EnumNameConverter<OverrideScope>(OverrideScope.values);
}

class OverrideRow extends DataClass implements Insertable<OverrideRow> {
  final OverrideScope scope;
  final String target;
  final String? profileId;

  /// Alert list JSON (see `alertsToJson`), null = use the profile's list.
  final String? customAlertsJson;
  final bool? enabled;
  const OverrideRow({
    required this.scope,
    required this.target,
    this.profileId,
    this.customAlertsJson,
    this.enabled,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    {
      map['scope'] = Variable<String>(
        $OverridesTable.$converterscope.toSql(scope),
      );
    }
    map['target'] = Variable<String>(target);
    if (!nullToAbsent || profileId != null) {
      map['profile_id'] = Variable<String>(profileId);
    }
    if (!nullToAbsent || customAlertsJson != null) {
      map['custom_alerts_json'] = Variable<String>(customAlertsJson);
    }
    if (!nullToAbsent || enabled != null) {
      map['enabled'] = Variable<bool>(enabled);
    }
    return map;
  }

  OverridesCompanion toCompanion(bool nullToAbsent) {
    return OverridesCompanion(
      scope: Value(scope),
      target: Value(target),
      profileId: profileId == null && nullToAbsent
          ? const Value.absent()
          : Value(profileId),
      customAlertsJson: customAlertsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(customAlertsJson),
      enabled: enabled == null && nullToAbsent
          ? const Value.absent()
          : Value(enabled),
    );
  }

  factory OverrideRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OverrideRow(
      scope: $OverridesTable.$converterscope.fromJson(
        serializer.fromJson<String>(json['scope']),
      ),
      target: serializer.fromJson<String>(json['target']),
      profileId: serializer.fromJson<String?>(json['profileId']),
      customAlertsJson: serializer.fromJson<String?>(json['customAlertsJson']),
      enabled: serializer.fromJson<bool?>(json['enabled']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'scope': serializer.toJson<String>(
        $OverridesTable.$converterscope.toJson(scope),
      ),
      'target': serializer.toJson<String>(target),
      'profileId': serializer.toJson<String?>(profileId),
      'customAlertsJson': serializer.toJson<String?>(customAlertsJson),
      'enabled': serializer.toJson<bool?>(enabled),
    };
  }

  OverrideRow copyWith({
    OverrideScope? scope,
    String? target,
    Value<String?> profileId = const Value.absent(),
    Value<String?> customAlertsJson = const Value.absent(),
    Value<bool?> enabled = const Value.absent(),
  }) => OverrideRow(
    scope: scope ?? this.scope,
    target: target ?? this.target,
    profileId: profileId.present ? profileId.value : this.profileId,
    customAlertsJson: customAlertsJson.present
        ? customAlertsJson.value
        : this.customAlertsJson,
    enabled: enabled.present ? enabled.value : this.enabled,
  );
  OverrideRow copyWithCompanion(OverridesCompanion data) {
    return OverrideRow(
      scope: data.scope.present ? data.scope.value : this.scope,
      target: data.target.present ? data.target.value : this.target,
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      customAlertsJson: data.customAlertsJson.present
          ? data.customAlertsJson.value
          : this.customAlertsJson,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OverrideRow(')
          ..write('scope: $scope, ')
          ..write('target: $target, ')
          ..write('profileId: $profileId, ')
          ..write('customAlertsJson: $customAlertsJson, ')
          ..write('enabled: $enabled')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(scope, target, profileId, customAlertsJson, enabled);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OverrideRow &&
          other.scope == this.scope &&
          other.target == this.target &&
          other.profileId == this.profileId &&
          other.customAlertsJson == this.customAlertsJson &&
          other.enabled == this.enabled);
}

class OverridesCompanion extends UpdateCompanion<OverrideRow> {
  final Value<OverrideScope> scope;
  final Value<String> target;
  final Value<String?> profileId;
  final Value<String?> customAlertsJson;
  final Value<bool?> enabled;
  final Value<int> rowid;
  const OverridesCompanion({
    this.scope = const Value.absent(),
    this.target = const Value.absent(),
    this.profileId = const Value.absent(),
    this.customAlertsJson = const Value.absent(),
    this.enabled = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OverridesCompanion.insert({
    required OverrideScope scope,
    required String target,
    this.profileId = const Value.absent(),
    this.customAlertsJson = const Value.absent(),
    this.enabled = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : scope = Value(scope),
       target = Value(target);
  static Insertable<OverrideRow> custom({
    Expression<String>? scope,
    Expression<String>? target,
    Expression<String>? profileId,
    Expression<String>? customAlertsJson,
    Expression<bool>? enabled,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (scope != null) 'scope': scope,
      if (target != null) 'target': target,
      if (profileId != null) 'profile_id': profileId,
      if (customAlertsJson != null) 'custom_alerts_json': customAlertsJson,
      if (enabled != null) 'enabled': enabled,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OverridesCompanion copyWith({
    Value<OverrideScope>? scope,
    Value<String>? target,
    Value<String?>? profileId,
    Value<String?>? customAlertsJson,
    Value<bool?>? enabled,
    Value<int>? rowid,
  }) {
    return OverridesCompanion(
      scope: scope ?? this.scope,
      target: target ?? this.target,
      profileId: profileId ?? this.profileId,
      customAlertsJson: customAlertsJson ?? this.customAlertsJson,
      enabled: enabled ?? this.enabled,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (scope.present) {
      map['scope'] = Variable<String>(
        $OverridesTable.$converterscope.toSql(scope.value),
      );
    }
    if (target.present) {
      map['target'] = Variable<String>(target.value);
    }
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (customAlertsJson.present) {
      map['custom_alerts_json'] = Variable<String>(customAlertsJson.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OverridesCompanion(')
          ..write('scope: $scope, ')
          ..write('target: $target, ')
          ..write('profileId: $profileId, ')
          ..write('customAlertsJson: $customAlertsJson, ')
          ..write('enabled: $enabled, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProfilesTable extends Profiles
    with TableInfo<$ProfilesTable, ProfileRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _alertsJsonMeta = const VerificationMeta(
    'alertsJson',
  );
  @override
  late final GeneratedColumn<String> alertsJson = GeneratedColumn<String>(
    'alerts_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _soundJsonMeta = const VerificationMeta(
    'soundJson',
  );
  @override
  late final GeneratedColumn<String> soundJson = GeneratedColumn<String>(
    'sound_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ringsInQuietModeMeta = const VerificationMeta(
    'ringsInQuietMode',
  );
  @override
  late final GeneratedColumn<bool> ringsInQuietMode = GeneratedColumn<bool>(
    'rings_in_quiet_mode',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("rings_in_quiet_mode" IN (0, 1))',
    ),
  );
  static const VerificationMeta _builtInMeta = const VerificationMeta(
    'builtIn',
  );
  @override
  late final GeneratedColumn<bool> builtIn = GeneratedColumn<bool>(
    'built_in',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("built_in" IN (0, 1))',
    ),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    alertsJson,
    soundJson,
    ringsInQuietMode,
    builtIn,
    position,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'profiles';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProfileRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('alerts_json')) {
      context.handle(
        _alertsJsonMeta,
        alertsJson.isAcceptableOrUnknown(data['alerts_json']!, _alertsJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_alertsJsonMeta);
    }
    if (data.containsKey('sound_json')) {
      context.handle(
        _soundJsonMeta,
        soundJson.isAcceptableOrUnknown(data['sound_json']!, _soundJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_soundJsonMeta);
    }
    if (data.containsKey('rings_in_quiet_mode')) {
      context.handle(
        _ringsInQuietModeMeta,
        ringsInQuietMode.isAcceptableOrUnknown(
          data['rings_in_quiet_mode']!,
          _ringsInQuietModeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ringsInQuietModeMeta);
    }
    if (data.containsKey('built_in')) {
      context.handle(
        _builtInMeta,
        builtIn.isAcceptableOrUnknown(data['built_in']!, _builtInMeta),
      );
    } else if (isInserting) {
      context.missing(_builtInMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProfileRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProfileRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      alertsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}alerts_json'],
      )!,
      soundJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sound_json'],
      )!,
      ringsInQuietMode: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}rings_in_quiet_mode'],
      )!,
      builtIn: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}built_in'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
    );
  }

  @override
  $ProfilesTable createAlias(String alias) {
    return $ProfilesTable(attachedDatabase, alias);
  }
}

class ProfileRow extends DataClass implements Insertable<ProfileRow> {
  final String id;
  final String name;
  final String alertsJson;
  final String soundJson;
  final bool ringsInQuietMode;
  final bool builtIn;

  /// Display order in the Alerts tab.
  final int position;
  const ProfileRow({
    required this.id,
    required this.name,
    required this.alertsJson,
    required this.soundJson,
    required this.ringsInQuietMode,
    required this.builtIn,
    required this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['alerts_json'] = Variable<String>(alertsJson);
    map['sound_json'] = Variable<String>(soundJson);
    map['rings_in_quiet_mode'] = Variable<bool>(ringsInQuietMode);
    map['built_in'] = Variable<bool>(builtIn);
    map['position'] = Variable<int>(position);
    return map;
  }

  ProfilesCompanion toCompanion(bool nullToAbsent) {
    return ProfilesCompanion(
      id: Value(id),
      name: Value(name),
      alertsJson: Value(alertsJson),
      soundJson: Value(soundJson),
      ringsInQuietMode: Value(ringsInQuietMode),
      builtIn: Value(builtIn),
      position: Value(position),
    );
  }

  factory ProfileRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProfileRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      alertsJson: serializer.fromJson<String>(json['alertsJson']),
      soundJson: serializer.fromJson<String>(json['soundJson']),
      ringsInQuietMode: serializer.fromJson<bool>(json['ringsInQuietMode']),
      builtIn: serializer.fromJson<bool>(json['builtIn']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'alertsJson': serializer.toJson<String>(alertsJson),
      'soundJson': serializer.toJson<String>(soundJson),
      'ringsInQuietMode': serializer.toJson<bool>(ringsInQuietMode),
      'builtIn': serializer.toJson<bool>(builtIn),
      'position': serializer.toJson<int>(position),
    };
  }

  ProfileRow copyWith({
    String? id,
    String? name,
    String? alertsJson,
    String? soundJson,
    bool? ringsInQuietMode,
    bool? builtIn,
    int? position,
  }) => ProfileRow(
    id: id ?? this.id,
    name: name ?? this.name,
    alertsJson: alertsJson ?? this.alertsJson,
    soundJson: soundJson ?? this.soundJson,
    ringsInQuietMode: ringsInQuietMode ?? this.ringsInQuietMode,
    builtIn: builtIn ?? this.builtIn,
    position: position ?? this.position,
  );
  ProfileRow copyWithCompanion(ProfilesCompanion data) {
    return ProfileRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      alertsJson: data.alertsJson.present
          ? data.alertsJson.value
          : this.alertsJson,
      soundJson: data.soundJson.present ? data.soundJson.value : this.soundJson,
      ringsInQuietMode: data.ringsInQuietMode.present
          ? data.ringsInQuietMode.value
          : this.ringsInQuietMode,
      builtIn: data.builtIn.present ? data.builtIn.value : this.builtIn,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProfileRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('alertsJson: $alertsJson, ')
          ..write('soundJson: $soundJson, ')
          ..write('ringsInQuietMode: $ringsInQuietMode, ')
          ..write('builtIn: $builtIn, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    alertsJson,
    soundJson,
    ringsInQuietMode,
    builtIn,
    position,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProfileRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.alertsJson == this.alertsJson &&
          other.soundJson == this.soundJson &&
          other.ringsInQuietMode == this.ringsInQuietMode &&
          other.builtIn == this.builtIn &&
          other.position == this.position);
}

class ProfilesCompanion extends UpdateCompanion<ProfileRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> alertsJson;
  final Value<String> soundJson;
  final Value<bool> ringsInQuietMode;
  final Value<bool> builtIn;
  final Value<int> position;
  final Value<int> rowid;
  const ProfilesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.alertsJson = const Value.absent(),
    this.soundJson = const Value.absent(),
    this.ringsInQuietMode = const Value.absent(),
    this.builtIn = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProfilesCompanion.insert({
    required String id,
    required String name,
    required String alertsJson,
    required String soundJson,
    required bool ringsInQuietMode,
    required bool builtIn,
    required int position,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       alertsJson = Value(alertsJson),
       soundJson = Value(soundJson),
       ringsInQuietMode = Value(ringsInQuietMode),
       builtIn = Value(builtIn),
       position = Value(position);
  static Insertable<ProfileRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? alertsJson,
    Expression<String>? soundJson,
    Expression<bool>? ringsInQuietMode,
    Expression<bool>? builtIn,
    Expression<int>? position,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (alertsJson != null) 'alerts_json': alertsJson,
      if (soundJson != null) 'sound_json': soundJson,
      if (ringsInQuietMode != null) 'rings_in_quiet_mode': ringsInQuietMode,
      if (builtIn != null) 'built_in': builtIn,
      if (position != null) 'position': position,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProfilesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? alertsJson,
    Value<String>? soundJson,
    Value<bool>? ringsInQuietMode,
    Value<bool>? builtIn,
    Value<int>? position,
    Value<int>? rowid,
  }) {
    return ProfilesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      alertsJson: alertsJson ?? this.alertsJson,
      soundJson: soundJson ?? this.soundJson,
      ringsInQuietMode: ringsInQuietMode ?? this.ringsInQuietMode,
      builtIn: builtIn ?? this.builtIn,
      position: position ?? this.position,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (alertsJson.present) {
      map['alerts_json'] = Variable<String>(alertsJson.value);
    }
    if (soundJson.present) {
      map['sound_json'] = Variable<String>(soundJson.value);
    }
    if (ringsInQuietMode.present) {
      map['rings_in_quiet_mode'] = Variable<bool>(ringsInQuietMode.value);
    }
    if (builtIn.present) {
      map['built_in'] = Variable<bool>(builtIn.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProfilesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('alertsJson: $alertsJson, ')
          ..write('soundJson: $soundJson, ')
          ..write('ringsInQuietMode: $ringsInQuietMode, ')
          ..write('builtIn: $builtIn, ')
          ..write('position: $position, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $KeywordRulesTable extends KeywordRules
    with TableInfo<$KeywordRulesTable, RuleRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KeywordRulesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<RuleField, String> field =
      GeneratedColumn<String>(
        'field',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<RuleField>($KeywordRulesTable.$converterfield);
  @override
  late final GeneratedColumnWithTypeConverter<RuleMatch, String> matchType =
      GeneratedColumn<String>(
        'match_type',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<RuleMatch>($KeywordRulesTable.$convertermatchType);
  static const VerificationMeta _patternMeta = const VerificationMeta(
    'pattern',
  );
  @override
  late final GeneratedColumn<String> pattern = GeneratedColumn<String>(
    'pattern',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profile_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    position,
    field,
    matchType,
    pattern,
    profileId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'rules';
  @override
  VerificationContext validateIntegrity(
    Insertable<RuleRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('pattern')) {
      context.handle(
        _patternMeta,
        pattern.isAcceptableOrUnknown(data['pattern']!, _patternMeta),
      );
    } else if (isInserting) {
      context.missing(_patternMeta);
    }
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_profileIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RuleRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RuleRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      field: $KeywordRulesTable.$converterfield.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}field'],
        )!,
      ),
      matchType: $KeywordRulesTable.$convertermatchType.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}match_type'],
        )!,
      ),
      pattern: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pattern'],
      )!,
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      )!,
    );
  }

  @override
  $KeywordRulesTable createAlias(String alias) {
    return $KeywordRulesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<RuleField, String, String> $converterfield =
      const EnumNameConverter<RuleField>(RuleField.values);
  static JsonTypeConverter2<RuleMatch, String, String> $convertermatchType =
      const EnumNameConverter<RuleMatch>(RuleMatch.values);
}

class RuleRow extends DataClass implements Insertable<RuleRow> {
  final String id;
  final int position;
  final RuleField field;

  /// `match` is an SQL keyword, hence the longer name.
  final RuleMatch matchType;
  final String pattern;
  final String profileId;
  const RuleRow({
    required this.id,
    required this.position,
    required this.field,
    required this.matchType,
    required this.pattern,
    required this.profileId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['position'] = Variable<int>(position);
    {
      map['field'] = Variable<String>(
        $KeywordRulesTable.$converterfield.toSql(field),
      );
    }
    {
      map['match_type'] = Variable<String>(
        $KeywordRulesTable.$convertermatchType.toSql(matchType),
      );
    }
    map['pattern'] = Variable<String>(pattern);
    map['profile_id'] = Variable<String>(profileId);
    return map;
  }

  KeywordRulesCompanion toCompanion(bool nullToAbsent) {
    return KeywordRulesCompanion(
      id: Value(id),
      position: Value(position),
      field: Value(field),
      matchType: Value(matchType),
      pattern: Value(pattern),
      profileId: Value(profileId),
    );
  }

  factory RuleRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RuleRow(
      id: serializer.fromJson<String>(json['id']),
      position: serializer.fromJson<int>(json['position']),
      field: $KeywordRulesTable.$converterfield.fromJson(
        serializer.fromJson<String>(json['field']),
      ),
      matchType: $KeywordRulesTable.$convertermatchType.fromJson(
        serializer.fromJson<String>(json['matchType']),
      ),
      pattern: serializer.fromJson<String>(json['pattern']),
      profileId: serializer.fromJson<String>(json['profileId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'position': serializer.toJson<int>(position),
      'field': serializer.toJson<String>(
        $KeywordRulesTable.$converterfield.toJson(field),
      ),
      'matchType': serializer.toJson<String>(
        $KeywordRulesTable.$convertermatchType.toJson(matchType),
      ),
      'pattern': serializer.toJson<String>(pattern),
      'profileId': serializer.toJson<String>(profileId),
    };
  }

  RuleRow copyWith({
    String? id,
    int? position,
    RuleField? field,
    RuleMatch? matchType,
    String? pattern,
    String? profileId,
  }) => RuleRow(
    id: id ?? this.id,
    position: position ?? this.position,
    field: field ?? this.field,
    matchType: matchType ?? this.matchType,
    pattern: pattern ?? this.pattern,
    profileId: profileId ?? this.profileId,
  );
  RuleRow copyWithCompanion(KeywordRulesCompanion data) {
    return RuleRow(
      id: data.id.present ? data.id.value : this.id,
      position: data.position.present ? data.position.value : this.position,
      field: data.field.present ? data.field.value : this.field,
      matchType: data.matchType.present ? data.matchType.value : this.matchType,
      pattern: data.pattern.present ? data.pattern.value : this.pattern,
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RuleRow(')
          ..write('id: $id, ')
          ..write('position: $position, ')
          ..write('field: $field, ')
          ..write('matchType: $matchType, ')
          ..write('pattern: $pattern, ')
          ..write('profileId: $profileId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, position, field, matchType, pattern, profileId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RuleRow &&
          other.id == this.id &&
          other.position == this.position &&
          other.field == this.field &&
          other.matchType == this.matchType &&
          other.pattern == this.pattern &&
          other.profileId == this.profileId);
}

class KeywordRulesCompanion extends UpdateCompanion<RuleRow> {
  final Value<String> id;
  final Value<int> position;
  final Value<RuleField> field;
  final Value<RuleMatch> matchType;
  final Value<String> pattern;
  final Value<String> profileId;
  final Value<int> rowid;
  const KeywordRulesCompanion({
    this.id = const Value.absent(),
    this.position = const Value.absent(),
    this.field = const Value.absent(),
    this.matchType = const Value.absent(),
    this.pattern = const Value.absent(),
    this.profileId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  KeywordRulesCompanion.insert({
    required String id,
    required int position,
    required RuleField field,
    required RuleMatch matchType,
    required String pattern,
    required String profileId,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       position = Value(position),
       field = Value(field),
       matchType = Value(matchType),
       pattern = Value(pattern),
       profileId = Value(profileId);
  static Insertable<RuleRow> custom({
    Expression<String>? id,
    Expression<int>? position,
    Expression<String>? field,
    Expression<String>? matchType,
    Expression<String>? pattern,
    Expression<String>? profileId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (position != null) 'position': position,
      if (field != null) 'field': field,
      if (matchType != null) 'match_type': matchType,
      if (pattern != null) 'pattern': pattern,
      if (profileId != null) 'profile_id': profileId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  KeywordRulesCompanion copyWith({
    Value<String>? id,
    Value<int>? position,
    Value<RuleField>? field,
    Value<RuleMatch>? matchType,
    Value<String>? pattern,
    Value<String>? profileId,
    Value<int>? rowid,
  }) {
    return KeywordRulesCompanion(
      id: id ?? this.id,
      position: position ?? this.position,
      field: field ?? this.field,
      matchType: matchType ?? this.matchType,
      pattern: pattern ?? this.pattern,
      profileId: profileId ?? this.profileId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (field.present) {
      map['field'] = Variable<String>(
        $KeywordRulesTable.$converterfield.toSql(field.value),
      );
    }
    if (matchType.present) {
      map['match_type'] = Variable<String>(
        $KeywordRulesTable.$convertermatchType.toSql(matchType.value),
      );
    }
    if (pattern.present) {
      map['pattern'] = Variable<String>(pattern.value);
    }
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KeywordRulesCompanion(')
          ..write('id: $id, ')
          ..write('position: $position, ')
          ..write('field: $field, ')
          ..write('matchType: $matchType, ')
          ..write('pattern: $pattern, ')
          ..write('profileId: $profileId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $QuietStatesTable extends QuietStates
    with TableInfo<$QuietStatesTable, QuietStateRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $QuietStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<QuietKind, String> kind =
      GeneratedColumn<String>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<QuietKind>($QuietStatesTable.$converterkind);
  static const VerificationMeta _untilUtcMsMeta = const VerificationMeta(
    'untilUtcMs',
  );
  @override
  late final GeneratedColumn<int> untilUtcMs = GeneratedColumn<int>(
    'until_utc_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _firstDayMeta = const VerificationMeta(
    'firstDay',
  );
  @override
  late final GeneratedColumn<String> firstDay = GeneratedColumn<String>(
    'first_day',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastDayMeta = const VerificationMeta(
    'lastDay',
  );
  @override
  late final GeneratedColumn<String> lastDay = GeneratedColumn<String>(
    'last_day',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    kind,
    untilUtcMs,
    firstDay,
    lastDay,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'quiet_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<QuietStateRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('until_utc_ms')) {
      context.handle(
        _untilUtcMsMeta,
        untilUtcMs.isAcceptableOrUnknown(
          data['until_utc_ms']!,
          _untilUtcMsMeta,
        ),
      );
    }
    if (data.containsKey('first_day')) {
      context.handle(
        _firstDayMeta,
        firstDay.isAcceptableOrUnknown(data['first_day']!, _firstDayMeta),
      );
    }
    if (data.containsKey('last_day')) {
      context.handle(
        _lastDayMeta,
        lastDay.isAcceptableOrUnknown(data['last_day']!, _lastDayMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  QuietStateRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return QuietStateRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      kind: $QuietStatesTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        )!,
      ),
      untilUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}until_utc_ms'],
      ),
      firstDay: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}first_day'],
      ),
      lastDay: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_day'],
      ),
    );
  }

  @override
  $QuietStatesTable createAlias(String alias) {
    return $QuietStatesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<QuietKind, String, String> $converterkind =
      const EnumNameConverter<QuietKind>(QuietKind.values);
}

class QuietStateRow extends DataClass implements Insertable<QuietStateRow> {
  /// Always 1; `SettingsRepository` is the only writer.
  final int id;
  final QuietKind kind;
  final int? untilUtcMs;

  /// `yyyy-MM-dd`, local dates, inclusive.
  final String? firstDay;
  final String? lastDay;
  const QuietStateRow({
    required this.id,
    required this.kind,
    this.untilUtcMs,
    this.firstDay,
    this.lastDay,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    {
      map['kind'] = Variable<String>(
        $QuietStatesTable.$converterkind.toSql(kind),
      );
    }
    if (!nullToAbsent || untilUtcMs != null) {
      map['until_utc_ms'] = Variable<int>(untilUtcMs);
    }
    if (!nullToAbsent || firstDay != null) {
      map['first_day'] = Variable<String>(firstDay);
    }
    if (!nullToAbsent || lastDay != null) {
      map['last_day'] = Variable<String>(lastDay);
    }
    return map;
  }

  QuietStatesCompanion toCompanion(bool nullToAbsent) {
    return QuietStatesCompanion(
      id: Value(id),
      kind: Value(kind),
      untilUtcMs: untilUtcMs == null && nullToAbsent
          ? const Value.absent()
          : Value(untilUtcMs),
      firstDay: firstDay == null && nullToAbsent
          ? const Value.absent()
          : Value(firstDay),
      lastDay: lastDay == null && nullToAbsent
          ? const Value.absent()
          : Value(lastDay),
    );
  }

  factory QuietStateRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return QuietStateRow(
      id: serializer.fromJson<int>(json['id']),
      kind: $QuietStatesTable.$converterkind.fromJson(
        serializer.fromJson<String>(json['kind']),
      ),
      untilUtcMs: serializer.fromJson<int?>(json['untilUtcMs']),
      firstDay: serializer.fromJson<String?>(json['firstDay']),
      lastDay: serializer.fromJson<String?>(json['lastDay']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'kind': serializer.toJson<String>(
        $QuietStatesTable.$converterkind.toJson(kind),
      ),
      'untilUtcMs': serializer.toJson<int?>(untilUtcMs),
      'firstDay': serializer.toJson<String?>(firstDay),
      'lastDay': serializer.toJson<String?>(lastDay),
    };
  }

  QuietStateRow copyWith({
    int? id,
    QuietKind? kind,
    Value<int?> untilUtcMs = const Value.absent(),
    Value<String?> firstDay = const Value.absent(),
    Value<String?> lastDay = const Value.absent(),
  }) => QuietStateRow(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    untilUtcMs: untilUtcMs.present ? untilUtcMs.value : this.untilUtcMs,
    firstDay: firstDay.present ? firstDay.value : this.firstDay,
    lastDay: lastDay.present ? lastDay.value : this.lastDay,
  );
  QuietStateRow copyWithCompanion(QuietStatesCompanion data) {
    return QuietStateRow(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      untilUtcMs: data.untilUtcMs.present
          ? data.untilUtcMs.value
          : this.untilUtcMs,
      firstDay: data.firstDay.present ? data.firstDay.value : this.firstDay,
      lastDay: data.lastDay.present ? data.lastDay.value : this.lastDay,
    );
  }

  @override
  String toString() {
    return (StringBuffer('QuietStateRow(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('untilUtcMs: $untilUtcMs, ')
          ..write('firstDay: $firstDay, ')
          ..write('lastDay: $lastDay')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, kind, untilUtcMs, firstDay, lastDay);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is QuietStateRow &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.untilUtcMs == this.untilUtcMs &&
          other.firstDay == this.firstDay &&
          other.lastDay == this.lastDay);
}

class QuietStatesCompanion extends UpdateCompanion<QuietStateRow> {
  final Value<int> id;
  final Value<QuietKind> kind;
  final Value<int?> untilUtcMs;
  final Value<String?> firstDay;
  final Value<String?> lastDay;
  const QuietStatesCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.untilUtcMs = const Value.absent(),
    this.firstDay = const Value.absent(),
    this.lastDay = const Value.absent(),
  });
  QuietStatesCompanion.insert({
    this.id = const Value.absent(),
    required QuietKind kind,
    this.untilUtcMs = const Value.absent(),
    this.firstDay = const Value.absent(),
    this.lastDay = const Value.absent(),
  }) : kind = Value(kind);
  static Insertable<QuietStateRow> custom({
    Expression<int>? id,
    Expression<String>? kind,
    Expression<int>? untilUtcMs,
    Expression<String>? firstDay,
    Expression<String>? lastDay,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (untilUtcMs != null) 'until_utc_ms': untilUtcMs,
      if (firstDay != null) 'first_day': firstDay,
      if (lastDay != null) 'last_day': lastDay,
    });
  }

  QuietStatesCompanion copyWith({
    Value<int>? id,
    Value<QuietKind>? kind,
    Value<int?>? untilUtcMs,
    Value<String?>? firstDay,
    Value<String?>? lastDay,
  }) {
    return QuietStatesCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      untilUtcMs: untilUtcMs ?? this.untilUtcMs,
      firstDay: firstDay ?? this.firstDay,
      lastDay: lastDay ?? this.lastDay,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(
        $QuietStatesTable.$converterkind.toSql(kind.value),
      );
    }
    if (untilUtcMs.present) {
      map['until_utc_ms'] = Variable<int>(untilUtcMs.value);
    }
    if (firstDay.present) {
      map['first_day'] = Variable<String>(firstDay.value);
    }
    if (lastDay.present) {
      map['last_day'] = Variable<String>(lastDay.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('QuietStatesCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('untilUtcMs: $untilUtcMs, ')
          ..write('firstDay: $firstDay, ')
          ..write('lastDay: $lastDay')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings
    with TableInfo<$SettingsTable, SettingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [name, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<SettingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {name};
  @override
  SettingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingRow(
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class SettingRow extends DataClass implements Insertable<SettingRow> {
  final String name;
  final String value;
  const SettingRow({required this.name, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['name'] = Variable<String>(name);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(name: Value(name), value: Value(value));
  }

  factory SettingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingRow(
      name: serializer.fromJson<String>(json['name']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'name': serializer.toJson<String>(name),
      'value': serializer.toJson<String>(value),
    };
  }

  SettingRow copyWith({String? name, String? value}) =>
      SettingRow(name: name ?? this.name, value: value ?? this.value);
  SettingRow copyWithCompanion(SettingsCompanion data) {
    return SettingRow(
      name: data.name.present ? data.name.value : this.name,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingRow(')
          ..write('name: $name, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(name, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingRow &&
          other.name == this.name &&
          other.value == this.value);
}

class SettingsCompanion extends UpdateCompanion<SettingRow> {
  final Value<String> name;
  final Value<String> value;
  final Value<int> rowid;
  const SettingsCompanion({
    this.name = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String name,
    required String value,
    this.rowid = const Value.absent(),
  }) : name = Value(name),
       value = Value(value);
  static Insertable<SettingRow> custom({
    Expression<String>? name,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (name != null) 'name': name,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? name,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      name: name ?? this.name,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('name: $name, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MeetingLinksTable extends MeetingLinks
    with TableInfo<$MeetingLinksTable, MeetingLinkRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MeetingLinksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _copyKeyMeta = const VerificationMeta(
    'copyKey',
  );
  @override
  late final GeneratedColumn<String> copyKey = GeneratedColumn<String>(
    'copy_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _meetingKeyMeta = const VerificationMeta(
    'meetingKey',
  );
  @override
  late final GeneratedColumn<String> meetingKey = GeneratedColumn<String>(
    'meeting_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _uidMeta = const VerificationMeta('uid');
  @override
  late final GeneratedColumn<String> uid = GeneratedColumn<String>(
    'uid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _oneOffMeta = const VerificationMeta('oneOff');
  @override
  late final GeneratedColumn<bool> oneOff = GeneratedColumn<bool>(
    'one_off',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("one_off" IN (0, 1))',
    ),
  );
  static const VerificationMeta _endUtcMsMeta = const VerificationMeta(
    'endUtcMs',
  );
  @override
  late final GeneratedColumn<int> endUtcMs = GeneratedColumn<int>(
    'end_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<MeetingMatch, String> matchedBy =
      GeneratedColumn<String>(
        'matched_by',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<MeetingMatch>($MeetingLinksTable.$convertermatchedBy);
  @override
  List<GeneratedColumn> get $columns => [
    copyKey,
    meetingKey,
    sourceId,
    uid,
    oneOff,
    endUtcMs,
    matchedBy,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'meeting_links';
  @override
  VerificationContext validateIntegrity(
    Insertable<MeetingLinkRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('copy_key')) {
      context.handle(
        _copyKeyMeta,
        copyKey.isAcceptableOrUnknown(data['copy_key']!, _copyKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_copyKeyMeta);
    }
    if (data.containsKey('meeting_key')) {
      context.handle(
        _meetingKeyMeta,
        meetingKey.isAcceptableOrUnknown(data['meeting_key']!, _meetingKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_meetingKeyMeta);
    }
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('uid')) {
      context.handle(
        _uidMeta,
        uid.isAcceptableOrUnknown(data['uid']!, _uidMeta),
      );
    } else if (isInserting) {
      context.missing(_uidMeta);
    }
    if (data.containsKey('one_off')) {
      context.handle(
        _oneOffMeta,
        oneOff.isAcceptableOrUnknown(data['one_off']!, _oneOffMeta),
      );
    } else if (isInserting) {
      context.missing(_oneOffMeta);
    }
    if (data.containsKey('end_utc_ms')) {
      context.handle(
        _endUtcMsMeta,
        endUtcMs.isAcceptableOrUnknown(data['end_utc_ms']!, _endUtcMsMeta),
      );
    } else if (isInserting) {
      context.missing(_endUtcMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {copyKey};
  @override
  MeetingLinkRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MeetingLinkRow(
      copyKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}copy_key'],
      )!,
      meetingKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}meeting_key'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      )!,
      uid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uid'],
      )!,
      oneOff: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}one_off'],
      )!,
      endUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_utc_ms'],
      )!,
      matchedBy: $MeetingLinksTable.$convertermatchedBy.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}matched_by'],
        )!,
      ),
    );
  }

  @override
  $MeetingLinksTable createAlias(String alias) {
    return $MeetingLinksTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<MeetingMatch, String, String> $convertermatchedBy =
      const EnumNameConverter<MeetingMatch>(MeetingMatch.values);
}

class MeetingLinkRow extends DataClass implements Insertable<MeetingLinkRow> {
  /// `EventOccurrence.key` of the copy.
  final String copyKey;

  /// The sticky key the meeting is planned under.
  final String meetingKey;

  /// The copy's source. Not a reference, see above.
  final String sourceId;

  /// The copy's uid, to find a one-off again after it moved.
  final String uid;

  /// The copy has no series uid.
  final bool oneOff;

  /// The copy's end, for pruning.
  final int endUtcMs;
  final MeetingMatch matchedBy;
  const MeetingLinkRow({
    required this.copyKey,
    required this.meetingKey,
    required this.sourceId,
    required this.uid,
    required this.oneOff,
    required this.endUtcMs,
    required this.matchedBy,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['copy_key'] = Variable<String>(copyKey);
    map['meeting_key'] = Variable<String>(meetingKey);
    map['source_id'] = Variable<String>(sourceId);
    map['uid'] = Variable<String>(uid);
    map['one_off'] = Variable<bool>(oneOff);
    map['end_utc_ms'] = Variable<int>(endUtcMs);
    {
      map['matched_by'] = Variable<String>(
        $MeetingLinksTable.$convertermatchedBy.toSql(matchedBy),
      );
    }
    return map;
  }

  MeetingLinksCompanion toCompanion(bool nullToAbsent) {
    return MeetingLinksCompanion(
      copyKey: Value(copyKey),
      meetingKey: Value(meetingKey),
      sourceId: Value(sourceId),
      uid: Value(uid),
      oneOff: Value(oneOff),
      endUtcMs: Value(endUtcMs),
      matchedBy: Value(matchedBy),
    );
  }

  factory MeetingLinkRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MeetingLinkRow(
      copyKey: serializer.fromJson<String>(json['copyKey']),
      meetingKey: serializer.fromJson<String>(json['meetingKey']),
      sourceId: serializer.fromJson<String>(json['sourceId']),
      uid: serializer.fromJson<String>(json['uid']),
      oneOff: serializer.fromJson<bool>(json['oneOff']),
      endUtcMs: serializer.fromJson<int>(json['endUtcMs']),
      matchedBy: $MeetingLinksTable.$convertermatchedBy.fromJson(
        serializer.fromJson<String>(json['matchedBy']),
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'copyKey': serializer.toJson<String>(copyKey),
      'meetingKey': serializer.toJson<String>(meetingKey),
      'sourceId': serializer.toJson<String>(sourceId),
      'uid': serializer.toJson<String>(uid),
      'oneOff': serializer.toJson<bool>(oneOff),
      'endUtcMs': serializer.toJson<int>(endUtcMs),
      'matchedBy': serializer.toJson<String>(
        $MeetingLinksTable.$convertermatchedBy.toJson(matchedBy),
      ),
    };
  }

  MeetingLinkRow copyWith({
    String? copyKey,
    String? meetingKey,
    String? sourceId,
    String? uid,
    bool? oneOff,
    int? endUtcMs,
    MeetingMatch? matchedBy,
  }) => MeetingLinkRow(
    copyKey: copyKey ?? this.copyKey,
    meetingKey: meetingKey ?? this.meetingKey,
    sourceId: sourceId ?? this.sourceId,
    uid: uid ?? this.uid,
    oneOff: oneOff ?? this.oneOff,
    endUtcMs: endUtcMs ?? this.endUtcMs,
    matchedBy: matchedBy ?? this.matchedBy,
  );
  MeetingLinkRow copyWithCompanion(MeetingLinksCompanion data) {
    return MeetingLinkRow(
      copyKey: data.copyKey.present ? data.copyKey.value : this.copyKey,
      meetingKey: data.meetingKey.present
          ? data.meetingKey.value
          : this.meetingKey,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      uid: data.uid.present ? data.uid.value : this.uid,
      oneOff: data.oneOff.present ? data.oneOff.value : this.oneOff,
      endUtcMs: data.endUtcMs.present ? data.endUtcMs.value : this.endUtcMs,
      matchedBy: data.matchedBy.present ? data.matchedBy.value : this.matchedBy,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MeetingLinkRow(')
          ..write('copyKey: $copyKey, ')
          ..write('meetingKey: $meetingKey, ')
          ..write('sourceId: $sourceId, ')
          ..write('uid: $uid, ')
          ..write('oneOff: $oneOff, ')
          ..write('endUtcMs: $endUtcMs, ')
          ..write('matchedBy: $matchedBy')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    copyKey,
    meetingKey,
    sourceId,
    uid,
    oneOff,
    endUtcMs,
    matchedBy,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MeetingLinkRow &&
          other.copyKey == this.copyKey &&
          other.meetingKey == this.meetingKey &&
          other.sourceId == this.sourceId &&
          other.uid == this.uid &&
          other.oneOff == this.oneOff &&
          other.endUtcMs == this.endUtcMs &&
          other.matchedBy == this.matchedBy);
}

class MeetingLinksCompanion extends UpdateCompanion<MeetingLinkRow> {
  final Value<String> copyKey;
  final Value<String> meetingKey;
  final Value<String> sourceId;
  final Value<String> uid;
  final Value<bool> oneOff;
  final Value<int> endUtcMs;
  final Value<MeetingMatch> matchedBy;
  final Value<int> rowid;
  const MeetingLinksCompanion({
    this.copyKey = const Value.absent(),
    this.meetingKey = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.uid = const Value.absent(),
    this.oneOff = const Value.absent(),
    this.endUtcMs = const Value.absent(),
    this.matchedBy = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MeetingLinksCompanion.insert({
    required String copyKey,
    required String meetingKey,
    required String sourceId,
    required String uid,
    required bool oneOff,
    required int endUtcMs,
    required MeetingMatch matchedBy,
    this.rowid = const Value.absent(),
  }) : copyKey = Value(copyKey),
       meetingKey = Value(meetingKey),
       sourceId = Value(sourceId),
       uid = Value(uid),
       oneOff = Value(oneOff),
       endUtcMs = Value(endUtcMs),
       matchedBy = Value(matchedBy);
  static Insertable<MeetingLinkRow> custom({
    Expression<String>? copyKey,
    Expression<String>? meetingKey,
    Expression<String>? sourceId,
    Expression<String>? uid,
    Expression<bool>? oneOff,
    Expression<int>? endUtcMs,
    Expression<String>? matchedBy,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (copyKey != null) 'copy_key': copyKey,
      if (meetingKey != null) 'meeting_key': meetingKey,
      if (sourceId != null) 'source_id': sourceId,
      if (uid != null) 'uid': uid,
      if (oneOff != null) 'one_off': oneOff,
      if (endUtcMs != null) 'end_utc_ms': endUtcMs,
      if (matchedBy != null) 'matched_by': matchedBy,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MeetingLinksCompanion copyWith({
    Value<String>? copyKey,
    Value<String>? meetingKey,
    Value<String>? sourceId,
    Value<String>? uid,
    Value<bool>? oneOff,
    Value<int>? endUtcMs,
    Value<MeetingMatch>? matchedBy,
    Value<int>? rowid,
  }) {
    return MeetingLinksCompanion(
      copyKey: copyKey ?? this.copyKey,
      meetingKey: meetingKey ?? this.meetingKey,
      sourceId: sourceId ?? this.sourceId,
      uid: uid ?? this.uid,
      oneOff: oneOff ?? this.oneOff,
      endUtcMs: endUtcMs ?? this.endUtcMs,
      matchedBy: matchedBy ?? this.matchedBy,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (copyKey.present) {
      map['copy_key'] = Variable<String>(copyKey.value);
    }
    if (meetingKey.present) {
      map['meeting_key'] = Variable<String>(meetingKey.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (uid.present) {
      map['uid'] = Variable<String>(uid.value);
    }
    if (oneOff.present) {
      map['one_off'] = Variable<bool>(oneOff.value);
    }
    if (endUtcMs.present) {
      map['end_utc_ms'] = Variable<int>(endUtcMs.value);
    }
    if (matchedBy.present) {
      map['matched_by'] = Variable<String>(
        $MeetingLinksTable.$convertermatchedBy.toSql(matchedBy.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MeetingLinksCompanion(')
          ..write('copyKey: $copyKey, ')
          ..write('meetingKey: $meetingKey, ')
          ..write('sourceId: $sourceId, ')
          ..write('uid: $uid, ')
          ..write('oneOff: $oneOff, ')
          ..write('endUtcMs: $endUtcMs, ')
          ..write('matchedBy: $matchedBy, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $SourcesTable sources = $SourcesTable(this);
  late final $OverridesTable overrides = $OverridesTable(this);
  late final $ProfilesTable profiles = $ProfilesTable(this);
  late final $KeywordRulesTable keywordRules = $KeywordRulesTable(this);
  late final $QuietStatesTable quietStates = $QuietStatesTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final $MeetingLinksTable meetingLinks = $MeetingLinksTable(this);
  late final Index meetingLinksSourceUid = Index(
    'meeting_links_source_uid',
    'CREATE INDEX IF NOT EXISTS meeting_links_source_uid ON meeting_links (source_id, uid)',
  );
  late final Index meetingLinksMeetingKey = Index(
    'meeting_links_meeting_key',
    'CREATE INDEX IF NOT EXISTS meeting_links_meeting_key ON meeting_links (meeting_key)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    sources,
    overrides,
    profiles,
    keywordRules,
    quietStates,
    settings,
    meetingLinks,
    meetingLinksSourceUid,
    meetingLinksMeetingKey,
  ];
}

typedef $$SourcesTableCreateCompanionBuilder = SourcesCompanion Function({
  required String id,
  required String name,
  required int color,
  required SourceKind kind,
  Value<String?> deviceCalendarId,
  Value<String?> secureStorageKey,
  Value<String?> defaultProfileId,
  Value<bool> enabled,
  Value<int?> lastAttemptUtcMs,
  Value<int?> lastSuccessUtcMs,
  Value<String?> lastError,
  Value<String?> httpEtag,
  Value<String?> httpLastModified,
  Value<int> emptyStreak,
  Value<int> rowid,
});
typedef $$SourcesTableUpdateCompanionBuilder = SourcesCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<int> color,
  Value<SourceKind> kind,
  Value<String?> deviceCalendarId,
  Value<String?> secureStorageKey,
  Value<String?> defaultProfileId,
  Value<bool> enabled,
  Value<int?> lastAttemptUtcMs,
  Value<int?> lastSuccessUtcMs,
  Value<String?> lastError,
  Value<String?> httpEtag,
  Value<String?> httpLastModified,
  Value<int> emptyStreak,
  Value<int> rowid,
});

class $$SourcesTableFilterComposer
    extends Composer<_$AppDatabase, $SourcesTable> {
  $$SourcesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<SourceKind, SourceKind, String> get kind =>
      $composableBuilder(
        column: $table.kind,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get deviceCalendarId => $composableBuilder(
    column: $table.deviceCalendarId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get secureStorageKey => $composableBuilder(
    column: $table.secureStorageKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get defaultProfileId => $composableBuilder(
    column: $table.defaultProfileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastAttemptUtcMs => $composableBuilder(
    column: $table.lastAttemptUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastSuccessUtcMs => $composableBuilder(
    column: $table.lastSuccessUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get httpEtag => $composableBuilder(
    column: $table.httpEtag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get httpLastModified => $composableBuilder(
    column: $table.httpLastModified,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get emptyStreak => $composableBuilder(
    column: $table.emptyStreak,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SourcesTableOrderingComposer
    extends Composer<_$AppDatabase, $SourcesTable> {
  $$SourcesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceCalendarId => $composableBuilder(
    column: $table.deviceCalendarId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get secureStorageKey => $composableBuilder(
    column: $table.secureStorageKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get defaultProfileId => $composableBuilder(
    column: $table.defaultProfileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastAttemptUtcMs => $composableBuilder(
    column: $table.lastAttemptUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastSuccessUtcMs => $composableBuilder(
    column: $table.lastSuccessUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get httpEtag => $composableBuilder(
    column: $table.httpEtag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get httpLastModified => $composableBuilder(
    column: $table.httpLastModified,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get emptyStreak => $composableBuilder(
    column: $table.emptyStreak,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SourcesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SourcesTable> {
  $$SourcesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumnWithTypeConverter<SourceKind, String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get deviceCalendarId => $composableBuilder(
    column: $table.deviceCalendarId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get secureStorageKey => $composableBuilder(
    column: $table.secureStorageKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get defaultProfileId => $composableBuilder(
    column: $table.defaultProfileId,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<int> get lastAttemptUtcMs => $composableBuilder(
    column: $table.lastAttemptUtcMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastSuccessUtcMs => $composableBuilder(
    column: $table.lastSuccessUtcMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<String> get httpEtag =>
      $composableBuilder(column: $table.httpEtag, builder: (column) => column);

  GeneratedColumn<String> get httpLastModified => $composableBuilder(
    column: $table.httpLastModified,
    builder: (column) => column,
  );

  GeneratedColumn<int> get emptyStreak => $composableBuilder(
    column: $table.emptyStreak,
    builder: (column) => column,
  );
}

class $$SourcesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SourcesTable,
          SourceRow,
          $$SourcesTableFilterComposer,
          $$SourcesTableOrderingComposer,
          $$SourcesTableAnnotationComposer,
          $$SourcesTableCreateCompanionBuilder,
          $$SourcesTableUpdateCompanionBuilder,
          (SourceRow, BaseReferences<_$AppDatabase, $SourcesTable, SourceRow>),
          SourceRow,
          PrefetchHooks Function()
        > {
  $$SourcesTableTableManager(_$AppDatabase db, $SourcesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SourcesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SourcesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SourcesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> color = const Value.absent(),
                Value<SourceKind> kind = const Value.absent(),
                Value<String?> deviceCalendarId = const Value.absent(),
                Value<String?> secureStorageKey = const Value.absent(),
                Value<String?> defaultProfileId = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<int?> lastAttemptUtcMs = const Value.absent(),
                Value<int?> lastSuccessUtcMs = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<String?> httpEtag = const Value.absent(),
                Value<String?> httpLastModified = const Value.absent(),
                Value<int> emptyStreak = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SourcesCompanion(
                id: id,
                name: name,
                color: color,
                kind: kind,
                deviceCalendarId: deviceCalendarId,
                secureStorageKey: secureStorageKey,
                defaultProfileId: defaultProfileId,
                enabled: enabled,
                lastAttemptUtcMs: lastAttemptUtcMs,
                lastSuccessUtcMs: lastSuccessUtcMs,
                lastError: lastError,
                httpEtag: httpEtag,
                httpLastModified: httpLastModified,
                emptyStreak: emptyStreak,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required int color,
                required SourceKind kind,
                Value<String?> deviceCalendarId = const Value.absent(),
                Value<String?> secureStorageKey = const Value.absent(),
                Value<String?> defaultProfileId = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<int?> lastAttemptUtcMs = const Value.absent(),
                Value<int?> lastSuccessUtcMs = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<String?> httpEtag = const Value.absent(),
                Value<String?> httpLastModified = const Value.absent(),
                Value<int> emptyStreak = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SourcesCompanion.insert(
                id: id,
                name: name,
                color: color,
                kind: kind,
                deviceCalendarId: deviceCalendarId,
                secureStorageKey: secureStorageKey,
                defaultProfileId: defaultProfileId,
                enabled: enabled,
                lastAttemptUtcMs: lastAttemptUtcMs,
                lastSuccessUtcMs: lastSuccessUtcMs,
                lastError: lastError,
                httpEtag: httpEtag,
                httpLastModified: httpLastModified,
                emptyStreak: emptyStreak,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SourcesTable, SourceRow>(table),
                  BaseReferences<_$AppDatabase, $SourcesTable, SourceRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SourcesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SourcesTable,
      SourceRow,
      $$SourcesTableFilterComposer,
      $$SourcesTableOrderingComposer,
      $$SourcesTableAnnotationComposer,
      $$SourcesTableCreateCompanionBuilder,
      $$SourcesTableUpdateCompanionBuilder,
      (SourceRow, BaseReferences<_$AppDatabase, $SourcesTable, SourceRow>),
      SourceRow,
      PrefetchHooks Function()
    >;
typedef $$OverridesTableCreateCompanionBuilder = OverridesCompanion Function({
  required OverrideScope scope,
  required String target,
  Value<String?> profileId,
  Value<String?> customAlertsJson,
  Value<bool?> enabled,
  Value<int> rowid,
});
typedef $$OverridesTableUpdateCompanionBuilder = OverridesCompanion Function({
  Value<OverrideScope> scope,
  Value<String> target,
  Value<String?> profileId,
  Value<String?> customAlertsJson,
  Value<bool?> enabled,
  Value<int> rowid,
});

class $$OverridesTableFilterComposer
    extends Composer<_$AppDatabase, $OverridesTable> {
  $$OverridesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnWithTypeConverterFilters<OverrideScope, OverrideScope, String>
  get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get target => $composableBuilder(
    column: $table.target,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customAlertsJson => $composableBuilder(
    column: $table.customAlertsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OverridesTableOrderingComposer
    extends Composer<_$AppDatabase, $OverridesTable> {
  $$OverridesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get target => $composableBuilder(
    column: $table.target,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customAlertsJson => $composableBuilder(
    column: $table.customAlertsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OverridesTableAnnotationComposer
    extends Composer<_$AppDatabase, $OverridesTable> {
  $$OverridesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumnWithTypeConverter<OverrideScope, String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<String> get target =>
      $composableBuilder(column: $table.target, builder: (column) => column);

  GeneratedColumn<String> get profileId =>
      $composableBuilder(column: $table.profileId, builder: (column) => column);

  GeneratedColumn<String> get customAlertsJson => $composableBuilder(
    column: $table.customAlertsJson,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);
}

class $$OverridesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OverridesTable,
          OverrideRow,
          $$OverridesTableFilterComposer,
          $$OverridesTableOrderingComposer,
          $$OverridesTableAnnotationComposer,
          $$OverridesTableCreateCompanionBuilder,
          $$OverridesTableUpdateCompanionBuilder,
          (
            OverrideRow,
            BaseReferences<_$AppDatabase, $OverridesTable, OverrideRow>,
          ),
          OverrideRow,
          PrefetchHooks Function()
        > {
  $$OverridesTableTableManager(_$AppDatabase db, $OverridesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OverridesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OverridesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OverridesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<OverrideScope> scope = const Value.absent(),
                Value<String> target = const Value.absent(),
                Value<String?> profileId = const Value.absent(),
                Value<String?> customAlertsJson = const Value.absent(),
                Value<bool?> enabled = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OverridesCompanion(
                scope: scope,
                target: target,
                profileId: profileId,
                customAlertsJson: customAlertsJson,
                enabled: enabled,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required OverrideScope scope,
                required String target,
                Value<String?> profileId = const Value.absent(),
                Value<String?> customAlertsJson = const Value.absent(),
                Value<bool?> enabled = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OverridesCompanion.insert(
                scope: scope,
                target: target,
                profileId: profileId,
                customAlertsJson: customAlertsJson,
                enabled: enabled,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OverridesTable, OverrideRow>(table),
                  BaseReferences<_$AppDatabase, $OverridesTable, OverrideRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OverridesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OverridesTable,
      OverrideRow,
      $$OverridesTableFilterComposer,
      $$OverridesTableOrderingComposer,
      $$OverridesTableAnnotationComposer,
      $$OverridesTableCreateCompanionBuilder,
      $$OverridesTableUpdateCompanionBuilder,
      (
        OverrideRow,
        BaseReferences<_$AppDatabase, $OverridesTable, OverrideRow>,
      ),
      OverrideRow,
      PrefetchHooks Function()
    >;
typedef $$ProfilesTableCreateCompanionBuilder = ProfilesCompanion Function({
  required String id,
  required String name,
  required String alertsJson,
  required String soundJson,
  required bool ringsInQuietMode,
  required bool builtIn,
  required int position,
  Value<int> rowid,
});
typedef $$ProfilesTableUpdateCompanionBuilder = ProfilesCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> alertsJson,
  Value<String> soundJson,
  Value<bool> ringsInQuietMode,
  Value<bool> builtIn,
  Value<int> position,
  Value<int> rowid,
});

class $$ProfilesTableFilterComposer
    extends Composer<_$AppDatabase, $ProfilesTable> {
  $$ProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get alertsJson => $composableBuilder(
    column: $table.alertsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get soundJson => $composableBuilder(
    column: $table.soundJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get ringsInQuietMode => $composableBuilder(
    column: $table.ringsInQuietMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get builtIn => $composableBuilder(
    column: $table.builtIn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProfilesTableOrderingComposer
    extends Composer<_$AppDatabase, $ProfilesTable> {
  $$ProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get alertsJson => $composableBuilder(
    column: $table.alertsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get soundJson => $composableBuilder(
    column: $table.soundJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get ringsInQuietMode => $composableBuilder(
    column: $table.ringsInQuietMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get builtIn => $composableBuilder(
    column: $table.builtIn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProfilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProfilesTable> {
  $$ProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get alertsJson => $composableBuilder(
    column: $table.alertsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get soundJson =>
      $composableBuilder(column: $table.soundJson, builder: (column) => column);

  GeneratedColumn<bool> get ringsInQuietMode => $composableBuilder(
    column: $table.ringsInQuietMode,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get builtIn =>
      $composableBuilder(column: $table.builtIn, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);
}

class $$ProfilesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProfilesTable,
          ProfileRow,
          $$ProfilesTableFilterComposer,
          $$ProfilesTableOrderingComposer,
          $$ProfilesTableAnnotationComposer,
          $$ProfilesTableCreateCompanionBuilder,
          $$ProfilesTableUpdateCompanionBuilder,
          (
            ProfileRow,
            BaseReferences<_$AppDatabase, $ProfilesTable, ProfileRow>,
          ),
          ProfileRow,
          PrefetchHooks Function()
        > {
  $$ProfilesTableTableManager(_$AppDatabase db, $ProfilesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> alertsJson = const Value.absent(),
                Value<String> soundJson = const Value.absent(),
                Value<bool> ringsInQuietMode = const Value.absent(),
                Value<bool> builtIn = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProfilesCompanion(
                id: id,
                name: name,
                alertsJson: alertsJson,
                soundJson: soundJson,
                ringsInQuietMode: ringsInQuietMode,
                builtIn: builtIn,
                position: position,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String alertsJson,
                required String soundJson,
                required bool ringsInQuietMode,
                required bool builtIn,
                required int position,
                Value<int> rowid = const Value.absent(),
              }) => ProfilesCompanion.insert(
                id: id,
                name: name,
                alertsJson: alertsJson,
                soundJson: soundJson,
                ringsInQuietMode: ringsInQuietMode,
                builtIn: builtIn,
                position: position,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ProfilesTable, ProfileRow>(table),
                  BaseReferences<_$AppDatabase, $ProfilesTable, ProfileRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProfilesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProfilesTable,
      ProfileRow,
      $$ProfilesTableFilterComposer,
      $$ProfilesTableOrderingComposer,
      $$ProfilesTableAnnotationComposer,
      $$ProfilesTableCreateCompanionBuilder,
      $$ProfilesTableUpdateCompanionBuilder,
      (ProfileRow, BaseReferences<_$AppDatabase, $ProfilesTable, ProfileRow>),
      ProfileRow,
      PrefetchHooks Function()
    >;
typedef $$KeywordRulesTableCreateCompanionBuilder =
    KeywordRulesCompanion Function({
      required String id,
      required int position,
      required RuleField field,
      required RuleMatch matchType,
      required String pattern,
      required String profileId,
      Value<int> rowid,
    });
typedef $$KeywordRulesTableUpdateCompanionBuilder =
    KeywordRulesCompanion Function({
      Value<String> id,
      Value<int> position,
      Value<RuleField> field,
      Value<RuleMatch> matchType,
      Value<String> pattern,
      Value<String> profileId,
      Value<int> rowid,
    });

class $$KeywordRulesTableFilterComposer
    extends Composer<_$AppDatabase, $KeywordRulesTable> {
  $$KeywordRulesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<RuleField, RuleField, String> get field =>
      $composableBuilder(
        column: $table.field,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<RuleMatch, RuleMatch, String> get matchType =>
      $composableBuilder(
        column: $table.matchType,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get pattern => $composableBuilder(
    column: $table.pattern,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$KeywordRulesTableOrderingComposer
    extends Composer<_$AppDatabase, $KeywordRulesTable> {
  $$KeywordRulesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get field => $composableBuilder(
    column: $table.field,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get matchType => $composableBuilder(
    column: $table.matchType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pattern => $composableBuilder(
    column: $table.pattern,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$KeywordRulesTableAnnotationComposer
    extends Composer<_$AppDatabase, $KeywordRulesTable> {
  $$KeywordRulesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumnWithTypeConverter<RuleField, String> get field =>
      $composableBuilder(column: $table.field, builder: (column) => column);

  GeneratedColumnWithTypeConverter<RuleMatch, String> get matchType =>
      $composableBuilder(column: $table.matchType, builder: (column) => column);

  GeneratedColumn<String> get pattern =>
      $composableBuilder(column: $table.pattern, builder: (column) => column);

  GeneratedColumn<String> get profileId =>
      $composableBuilder(column: $table.profileId, builder: (column) => column);
}

class $$KeywordRulesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $KeywordRulesTable,
          RuleRow,
          $$KeywordRulesTableFilterComposer,
          $$KeywordRulesTableOrderingComposer,
          $$KeywordRulesTableAnnotationComposer,
          $$KeywordRulesTableCreateCompanionBuilder,
          $$KeywordRulesTableUpdateCompanionBuilder,
          (RuleRow, BaseReferences<_$AppDatabase, $KeywordRulesTable, RuleRow>),
          RuleRow,
          PrefetchHooks Function()
        > {
  $$KeywordRulesTableTableManager(_$AppDatabase db, $KeywordRulesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$KeywordRulesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$KeywordRulesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$KeywordRulesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<RuleField> field = const Value.absent(),
                Value<RuleMatch> matchType = const Value.absent(),
                Value<String> pattern = const Value.absent(),
                Value<String> profileId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => KeywordRulesCompanion(
                id: id,
                position: position,
                field: field,
                matchType: matchType,
                pattern: pattern,
                profileId: profileId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required int position,
                required RuleField field,
                required RuleMatch matchType,
                required String pattern,
                required String profileId,
                Value<int> rowid = const Value.absent(),
              }) => KeywordRulesCompanion.insert(
                id: id,
                position: position,
                field: field,
                matchType: matchType,
                pattern: pattern,
                profileId: profileId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$KeywordRulesTable, RuleRow>(table),
                  BaseReferences<_$AppDatabase, $KeywordRulesTable, RuleRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$KeywordRulesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $KeywordRulesTable,
      RuleRow,
      $$KeywordRulesTableFilterComposer,
      $$KeywordRulesTableOrderingComposer,
      $$KeywordRulesTableAnnotationComposer,
      $$KeywordRulesTableCreateCompanionBuilder,
      $$KeywordRulesTableUpdateCompanionBuilder,
      (RuleRow, BaseReferences<_$AppDatabase, $KeywordRulesTable, RuleRow>),
      RuleRow,
      PrefetchHooks Function()
    >;
typedef $$QuietStatesTableCreateCompanionBuilder =
    QuietStatesCompanion Function({
      Value<int> id,
      required QuietKind kind,
      Value<int?> untilUtcMs,
      Value<String?> firstDay,
      Value<String?> lastDay,
    });
typedef $$QuietStatesTableUpdateCompanionBuilder =
    QuietStatesCompanion Function({
      Value<int> id,
      Value<QuietKind> kind,
      Value<int?> untilUtcMs,
      Value<String?> firstDay,
      Value<String?> lastDay,
    });

class $$QuietStatesTableFilterComposer
    extends Composer<_$AppDatabase, $QuietStatesTable> {
  $$QuietStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<QuietKind, QuietKind, String> get kind =>
      $composableBuilder(
        column: $table.kind,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get untilUtcMs => $composableBuilder(
    column: $table.untilUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get firstDay => $composableBuilder(
    column: $table.firstDay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastDay => $composableBuilder(
    column: $table.lastDay,
    builder: (column) => ColumnFilters(column),
  );
}

class $$QuietStatesTableOrderingComposer
    extends Composer<_$AppDatabase, $QuietStatesTable> {
  $$QuietStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get untilUtcMs => $composableBuilder(
    column: $table.untilUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get firstDay => $composableBuilder(
    column: $table.firstDay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastDay => $composableBuilder(
    column: $table.lastDay,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$QuietStatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $QuietStatesTable> {
  $$QuietStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<QuietKind, String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get untilUtcMs => $composableBuilder(
    column: $table.untilUtcMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get firstDay =>
      $composableBuilder(column: $table.firstDay, builder: (column) => column);

  GeneratedColumn<String> get lastDay =>
      $composableBuilder(column: $table.lastDay, builder: (column) => column);
}

class $$QuietStatesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $QuietStatesTable,
          QuietStateRow,
          $$QuietStatesTableFilterComposer,
          $$QuietStatesTableOrderingComposer,
          $$QuietStatesTableAnnotationComposer,
          $$QuietStatesTableCreateCompanionBuilder,
          $$QuietStatesTableUpdateCompanionBuilder,
          (
            QuietStateRow,
            BaseReferences<_$AppDatabase, $QuietStatesTable, QuietStateRow>,
          ),
          QuietStateRow,
          PrefetchHooks Function()
        > {
  $$QuietStatesTableTableManager(_$AppDatabase db, $QuietStatesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$QuietStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$QuietStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$QuietStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<QuietKind> kind = const Value.absent(),
                Value<int?> untilUtcMs = const Value.absent(),
                Value<String?> firstDay = const Value.absent(),
                Value<String?> lastDay = const Value.absent(),
              }) => QuietStatesCompanion(
                id: id,
                kind: kind,
                untilUtcMs: untilUtcMs,
                firstDay: firstDay,
                lastDay: lastDay,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required QuietKind kind,
                Value<int?> untilUtcMs = const Value.absent(),
                Value<String?> firstDay = const Value.absent(),
                Value<String?> lastDay = const Value.absent(),
              }) => QuietStatesCompanion.insert(
                id: id,
                kind: kind,
                untilUtcMs: untilUtcMs,
                firstDay: firstDay,
                lastDay: lastDay,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$QuietStatesTable, QuietStateRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $QuietStatesTable,
                    QuietStateRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$QuietStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $QuietStatesTable,
      QuietStateRow,
      $$QuietStatesTableFilterComposer,
      $$QuietStatesTableOrderingComposer,
      $$QuietStatesTableAnnotationComposer,
      $$QuietStatesTableCreateCompanionBuilder,
      $$QuietStatesTableUpdateCompanionBuilder,
      (
        QuietStateRow,
        BaseReferences<_$AppDatabase, $QuietStatesTable, QuietStateRow>,
      ),
      QuietStateRow,
      PrefetchHooks Function()
    >;
typedef $$SettingsTableCreateCompanionBuilder = SettingsCompanion Function({
  required String name,
  required String value,
  Value<int> rowid,
});
typedef $$SettingsTableUpdateCompanionBuilder = SettingsCompanion Function({
  Value<String> name,
  Value<String> value,
  Value<int> rowid,
});

class $$SettingsTableFilterComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SettingsTable,
          SettingRow,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (
            SettingRow,
            BaseReferences<_$AppDatabase, $SettingsTable, SettingRow>,
          ),
          SettingRow,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$AppDatabase db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> name = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => SettingsCompanion(name: name, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String name,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion.insert(
                name: name,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SettingsTable, SettingRow>(table),
                  BaseReferences<_$AppDatabase, $SettingsTable, SettingRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SettingsTable,
      SettingRow,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (SettingRow, BaseReferences<_$AppDatabase, $SettingsTable, SettingRow>),
      SettingRow,
      PrefetchHooks Function()
    >;
typedef $$MeetingLinksTableCreateCompanionBuilder =
    MeetingLinksCompanion Function({
      required String copyKey,
      required String meetingKey,
      required String sourceId,
      required String uid,
      required bool oneOff,
      required int endUtcMs,
      required MeetingMatch matchedBy,
      Value<int> rowid,
    });
typedef $$MeetingLinksTableUpdateCompanionBuilder =
    MeetingLinksCompanion Function({
      Value<String> copyKey,
      Value<String> meetingKey,
      Value<String> sourceId,
      Value<String> uid,
      Value<bool> oneOff,
      Value<int> endUtcMs,
      Value<MeetingMatch> matchedBy,
      Value<int> rowid,
    });

class $$MeetingLinksTableFilterComposer
    extends Composer<_$AppDatabase, $MeetingLinksTable> {
  $$MeetingLinksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get copyKey => $composableBuilder(
    column: $table.copyKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get meetingKey => $composableBuilder(
    column: $table.meetingKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get uid => $composableBuilder(
    column: $table.uid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get oneOff => $composableBuilder(
    column: $table.oneOff,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endUtcMs => $composableBuilder(
    column: $table.endUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<MeetingMatch, MeetingMatch, String>
  get matchedBy => $composableBuilder(
    column: $table.matchedBy,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );
}

class $$MeetingLinksTableOrderingComposer
    extends Composer<_$AppDatabase, $MeetingLinksTable> {
  $$MeetingLinksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get copyKey => $composableBuilder(
    column: $table.copyKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get meetingKey => $composableBuilder(
    column: $table.meetingKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uid => $composableBuilder(
    column: $table.uid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get oneOff => $composableBuilder(
    column: $table.oneOff,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endUtcMs => $composableBuilder(
    column: $table.endUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get matchedBy => $composableBuilder(
    column: $table.matchedBy,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MeetingLinksTableAnnotationComposer
    extends Composer<_$AppDatabase, $MeetingLinksTable> {
  $$MeetingLinksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get copyKey =>
      $composableBuilder(column: $table.copyKey, builder: (column) => column);

  GeneratedColumn<String> get meetingKey => $composableBuilder(
    column: $table.meetingKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get uid =>
      $composableBuilder(column: $table.uid, builder: (column) => column);

  GeneratedColumn<bool> get oneOff =>
      $composableBuilder(column: $table.oneOff, builder: (column) => column);

  GeneratedColumn<int> get endUtcMs =>
      $composableBuilder(column: $table.endUtcMs, builder: (column) => column);

  GeneratedColumnWithTypeConverter<MeetingMatch, String> get matchedBy =>
      $composableBuilder(column: $table.matchedBy, builder: (column) => column);
}

class $$MeetingLinksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MeetingLinksTable,
          MeetingLinkRow,
          $$MeetingLinksTableFilterComposer,
          $$MeetingLinksTableOrderingComposer,
          $$MeetingLinksTableAnnotationComposer,
          $$MeetingLinksTableCreateCompanionBuilder,
          $$MeetingLinksTableUpdateCompanionBuilder,
          (
            MeetingLinkRow,
            BaseReferences<_$AppDatabase, $MeetingLinksTable, MeetingLinkRow>,
          ),
          MeetingLinkRow,
          PrefetchHooks Function()
        > {
  $$MeetingLinksTableTableManager(_$AppDatabase db, $MeetingLinksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MeetingLinksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MeetingLinksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MeetingLinksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> copyKey = const Value.absent(),
                Value<String> meetingKey = const Value.absent(),
                Value<String> sourceId = const Value.absent(),
                Value<String> uid = const Value.absent(),
                Value<bool> oneOff = const Value.absent(),
                Value<int> endUtcMs = const Value.absent(),
                Value<MeetingMatch> matchedBy = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MeetingLinksCompanion(
                copyKey: copyKey,
                meetingKey: meetingKey,
                sourceId: sourceId,
                uid: uid,
                oneOff: oneOff,
                endUtcMs: endUtcMs,
                matchedBy: matchedBy,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String copyKey,
                required String meetingKey,
                required String sourceId,
                required String uid,
                required bool oneOff,
                required int endUtcMs,
                required MeetingMatch matchedBy,
                Value<int> rowid = const Value.absent(),
              }) => MeetingLinksCompanion.insert(
                copyKey: copyKey,
                meetingKey: meetingKey,
                sourceId: sourceId,
                uid: uid,
                oneOff: oneOff,
                endUtcMs: endUtcMs,
                matchedBy: matchedBy,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MeetingLinksTable, MeetingLinkRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $MeetingLinksTable,
                    MeetingLinkRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MeetingLinksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MeetingLinksTable,
      MeetingLinkRow,
      $$MeetingLinksTableFilterComposer,
      $$MeetingLinksTableOrderingComposer,
      $$MeetingLinksTableAnnotationComposer,
      $$MeetingLinksTableCreateCompanionBuilder,
      $$MeetingLinksTableUpdateCompanionBuilder,
      (
        MeetingLinkRow,
        BaseReferences<_$AppDatabase, $MeetingLinksTable, MeetingLinkRow>,
      ),
      MeetingLinkRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$SourcesTableTableManager get sources =>
      $$SourcesTableTableManager(_db, _db.sources);
  $$OverridesTableTableManager get overrides =>
      $$OverridesTableTableManager(_db, _db.overrides);
  $$ProfilesTableTableManager get profiles =>
      $$ProfilesTableTableManager(_db, _db.profiles);
  $$KeywordRulesTableTableManager get keywordRules =>
      $$KeywordRulesTableTableManager(_db, _db.keywordRules);
  $$QuietStatesTableTableManager get quietStates =>
      $$QuietStatesTableTableManager(_db, _db.quietStates);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
  $$MeetingLinksTableTableManager get meetingLinks =>
      $$MeetingLinksTableTableManager(_db, _db.meetingLinks);
}
