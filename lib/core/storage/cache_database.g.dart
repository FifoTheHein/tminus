// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cache_database.dart';

// ignore_for_file: type=lint
class $OccurrencesTable extends Occurrences
    with TableInfo<$OccurrencesTable, OccurrenceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OccurrencesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _occurrenceKeyMeta = const VerificationMeta(
    'occurrenceKey',
  );
  @override
  late final GeneratedColumn<String> occurrenceKey = GeneratedColumn<String>(
    'occurrence_key',
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
  static const VerificationMeta _originalStartUtcMsMeta =
      const VerificationMeta('originalStartUtcMs');
  @override
  late final GeneratedColumn<int> originalStartUtcMs = GeneratedColumn<int>(
    'original_start_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seriesUidMeta = const VerificationMeta(
    'seriesUid',
  );
  @override
  late final GeneratedColumn<String> seriesUid = GeneratedColumn<String>(
    'series_uid',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _locationMeta = const VerificationMeta(
    'location',
  );
  @override
  late final GeneratedColumn<String> location = GeneratedColumn<String>(
    'location',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _organizerMeta = const VerificationMeta(
    'organizer',
  );
  @override
  late final GeneratedColumn<String> organizer = GeneratedColumn<String>(
    'organizer',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _joinUrlMeta = const VerificationMeta(
    'joinUrl',
  );
  @override
  late final GeneratedColumn<String> joinUrl = GeneratedColumn<String>(
    'join_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startUtcMsMeta = const VerificationMeta(
    'startUtcMs',
  );
  @override
  late final GeneratedColumn<int> startUtcMs = GeneratedColumn<int>(
    'start_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
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
  static const VerificationMeta _allDayMeta = const VerificationMeta('allDay');
  @override
  late final GeneratedColumn<bool> allDay = GeneratedColumn<bool>(
    'all_day',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("all_day" IN (0, 1))',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<BusyStatus, String> busyStatus =
      GeneratedColumn<String>(
        'busy_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<BusyStatus>($OccurrencesTable.$converterbusyStatus);
  static const VerificationMeta _declinedMeta = const VerificationMeta(
    'declined',
  );
  @override
  late final GeneratedColumn<bool> declined = GeneratedColumn<bool>(
    'declined',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("declined" IN (0, 1))',
    ),
  );
  static const VerificationMeta _cancelledMeta = const VerificationMeta(
    'cancelled',
  );
  @override
  late final GeneratedColumn<bool> cancelled = GeneratedColumn<bool>(
    'cancelled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("cancelled" IN (0, 1))',
    ),
  );
  static const VerificationMeta _calendarColorMeta = const VerificationMeta(
    'calendarColor',
  );
  @override
  late final GeneratedColumn<int> calendarColor = GeneratedColumn<int>(
    'calendar_color',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _warningsMeta = const VerificationMeta(
    'warnings',
  );
  @override
  late final GeneratedColumn<String> warnings = GeneratedColumn<String>(
    'warnings',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _icalUidMeta = const VerificationMeta(
    'icalUid',
  );
  @override
  late final GeneratedColumn<String> icalUid = GeneratedColumn<String>(
    'ical_uid',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    occurrenceKey,
    sourceId,
    uid,
    originalStartUtcMs,
    seriesUid,
    title,
    location,
    organizer,
    description,
    joinUrl,
    startUtcMs,
    endUtcMs,
    allDay,
    busyStatus,
    declined,
    cancelled,
    calendarColor,
    warnings,
    icalUid,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'occurrences';
  @override
  VerificationContext validateIntegrity(
    Insertable<OccurrenceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('occurrence_key')) {
      context.handle(
        _occurrenceKeyMeta,
        occurrenceKey.isAcceptableOrUnknown(
          data['occurrence_key']!,
          _occurrenceKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_occurrenceKeyMeta);
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
    if (data.containsKey('original_start_utc_ms')) {
      context.handle(
        _originalStartUtcMsMeta,
        originalStartUtcMs.isAcceptableOrUnknown(
          data['original_start_utc_ms']!,
          _originalStartUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originalStartUtcMsMeta);
    }
    if (data.containsKey('series_uid')) {
      context.handle(
        _seriesUidMeta,
        seriesUid.isAcceptableOrUnknown(data['series_uid']!, _seriesUidMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('location')) {
      context.handle(
        _locationMeta,
        location.isAcceptableOrUnknown(data['location']!, _locationMeta),
      );
    }
    if (data.containsKey('organizer')) {
      context.handle(
        _organizerMeta,
        organizer.isAcceptableOrUnknown(data['organizer']!, _organizerMeta),
      );
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('join_url')) {
      context.handle(
        _joinUrlMeta,
        joinUrl.isAcceptableOrUnknown(data['join_url']!, _joinUrlMeta),
      );
    }
    if (data.containsKey('start_utc_ms')) {
      context.handle(
        _startUtcMsMeta,
        startUtcMs.isAcceptableOrUnknown(
          data['start_utc_ms']!,
          _startUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startUtcMsMeta);
    }
    if (data.containsKey('end_utc_ms')) {
      context.handle(
        _endUtcMsMeta,
        endUtcMs.isAcceptableOrUnknown(data['end_utc_ms']!, _endUtcMsMeta),
      );
    } else if (isInserting) {
      context.missing(_endUtcMsMeta);
    }
    if (data.containsKey('all_day')) {
      context.handle(
        _allDayMeta,
        allDay.isAcceptableOrUnknown(data['all_day']!, _allDayMeta),
      );
    } else if (isInserting) {
      context.missing(_allDayMeta);
    }
    if (data.containsKey('declined')) {
      context.handle(
        _declinedMeta,
        declined.isAcceptableOrUnknown(data['declined']!, _declinedMeta),
      );
    } else if (isInserting) {
      context.missing(_declinedMeta);
    }
    if (data.containsKey('cancelled')) {
      context.handle(
        _cancelledMeta,
        cancelled.isAcceptableOrUnknown(data['cancelled']!, _cancelledMeta),
      );
    } else if (isInserting) {
      context.missing(_cancelledMeta);
    }
    if (data.containsKey('calendar_color')) {
      context.handle(
        _calendarColorMeta,
        calendarColor.isAcceptableOrUnknown(
          data['calendar_color']!,
          _calendarColorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_calendarColorMeta);
    }
    if (data.containsKey('warnings')) {
      context.handle(
        _warningsMeta,
        warnings.isAcceptableOrUnknown(data['warnings']!, _warningsMeta),
      );
    }
    if (data.containsKey('ical_uid')) {
      context.handle(
        _icalUidMeta,
        icalUid.isAcceptableOrUnknown(data['ical_uid']!, _icalUidMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {occurrenceKey};
  @override
  OccurrenceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OccurrenceRow(
      occurrenceKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}occurrence_key'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      )!,
      uid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uid'],
      )!,
      originalStartUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}original_start_utc_ms'],
      )!,
      seriesUid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}series_uid'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      location: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location'],
      ),
      organizer: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organizer'],
      ),
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      joinUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}join_url'],
      ),
      startUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_utc_ms'],
      )!,
      endUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_utc_ms'],
      )!,
      allDay: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}all_day'],
      )!,
      busyStatus: $OccurrencesTable.$converterbusyStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}busy_status'],
        )!,
      ),
      declined: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}declined'],
      )!,
      cancelled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}cancelled'],
      )!,
      calendarColor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}calendar_color'],
      )!,
      warnings: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}warnings'],
      )!,
      icalUid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ical_uid'],
      ),
    );
  }

  @override
  $OccurrencesTable createAlias(String alias) {
    return $OccurrencesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<BusyStatus, String, String> $converterbusyStatus =
      const EnumNameConverter<BusyStatus>(BusyStatus.values);
}

class OccurrenceRow extends DataClass implements Insertable<OccurrenceRow> {
  final String occurrenceKey;
  final String sourceId;
  final String uid;
  final int originalStartUtcMs;
  final String? seriesUid;
  final String title;
  final String? location;
  final String? organizer;
  final String? description;
  final String? joinUrl;
  final int startUtcMs;
  final int endUtcMs;
  final bool allDay;
  final BusyStatus busyStatus;
  final bool declined;
  final bool cancelled;
  final int calendarColor;

  /// Comma-separated [OccurrenceWarning] names; empty for none.
  final String warnings;

  /// The event's iCalendar UID where the source has one; null otherwise and
  /// for rows cached before schema 2 of `tminus.sqlite`. Declared last, because
  /// a column added by a migration is appended to the table, and the rows moved
  /// here from the old table keep that order.
  final String? icalUid;
  const OccurrenceRow({
    required this.occurrenceKey,
    required this.sourceId,
    required this.uid,
    required this.originalStartUtcMs,
    this.seriesUid,
    required this.title,
    this.location,
    this.organizer,
    this.description,
    this.joinUrl,
    required this.startUtcMs,
    required this.endUtcMs,
    required this.allDay,
    required this.busyStatus,
    required this.declined,
    required this.cancelled,
    required this.calendarColor,
    required this.warnings,
    this.icalUid,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['occurrence_key'] = Variable<String>(occurrenceKey);
    map['source_id'] = Variable<String>(sourceId);
    map['uid'] = Variable<String>(uid);
    map['original_start_utc_ms'] = Variable<int>(originalStartUtcMs);
    if (!nullToAbsent || seriesUid != null) {
      map['series_uid'] = Variable<String>(seriesUid);
    }
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || location != null) {
      map['location'] = Variable<String>(location);
    }
    if (!nullToAbsent || organizer != null) {
      map['organizer'] = Variable<String>(organizer);
    }
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || joinUrl != null) {
      map['join_url'] = Variable<String>(joinUrl);
    }
    map['start_utc_ms'] = Variable<int>(startUtcMs);
    map['end_utc_ms'] = Variable<int>(endUtcMs);
    map['all_day'] = Variable<bool>(allDay);
    {
      map['busy_status'] = Variable<String>(
        $OccurrencesTable.$converterbusyStatus.toSql(busyStatus),
      );
    }
    map['declined'] = Variable<bool>(declined);
    map['cancelled'] = Variable<bool>(cancelled);
    map['calendar_color'] = Variable<int>(calendarColor);
    map['warnings'] = Variable<String>(warnings);
    if (!nullToAbsent || icalUid != null) {
      map['ical_uid'] = Variable<String>(icalUid);
    }
    return map;
  }

  OccurrencesCompanion toCompanion(bool nullToAbsent) {
    return OccurrencesCompanion(
      occurrenceKey: Value(occurrenceKey),
      sourceId: Value(sourceId),
      uid: Value(uid),
      originalStartUtcMs: Value(originalStartUtcMs),
      seriesUid: seriesUid == null && nullToAbsent
          ? const Value.absent()
          : Value(seriesUid),
      title: Value(title),
      location: location == null && nullToAbsent
          ? const Value.absent()
          : Value(location),
      organizer: organizer == null && nullToAbsent
          ? const Value.absent()
          : Value(organizer),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      joinUrl: joinUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(joinUrl),
      startUtcMs: Value(startUtcMs),
      endUtcMs: Value(endUtcMs),
      allDay: Value(allDay),
      busyStatus: Value(busyStatus),
      declined: Value(declined),
      cancelled: Value(cancelled),
      calendarColor: Value(calendarColor),
      warnings: Value(warnings),
      icalUid: icalUid == null && nullToAbsent
          ? const Value.absent()
          : Value(icalUid),
    );
  }

  factory OccurrenceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OccurrenceRow(
      occurrenceKey: serializer.fromJson<String>(json['occurrenceKey']),
      sourceId: serializer.fromJson<String>(json['sourceId']),
      uid: serializer.fromJson<String>(json['uid']),
      originalStartUtcMs: serializer.fromJson<int>(json['originalStartUtcMs']),
      seriesUid: serializer.fromJson<String?>(json['seriesUid']),
      title: serializer.fromJson<String>(json['title']),
      location: serializer.fromJson<String?>(json['location']),
      organizer: serializer.fromJson<String?>(json['organizer']),
      description: serializer.fromJson<String?>(json['description']),
      joinUrl: serializer.fromJson<String?>(json['joinUrl']),
      startUtcMs: serializer.fromJson<int>(json['startUtcMs']),
      endUtcMs: serializer.fromJson<int>(json['endUtcMs']),
      allDay: serializer.fromJson<bool>(json['allDay']),
      busyStatus: $OccurrencesTable.$converterbusyStatus.fromJson(
        serializer.fromJson<String>(json['busyStatus']),
      ),
      declined: serializer.fromJson<bool>(json['declined']),
      cancelled: serializer.fromJson<bool>(json['cancelled']),
      calendarColor: serializer.fromJson<int>(json['calendarColor']),
      warnings: serializer.fromJson<String>(json['warnings']),
      icalUid: serializer.fromJson<String?>(json['icalUid']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'occurrenceKey': serializer.toJson<String>(occurrenceKey),
      'sourceId': serializer.toJson<String>(sourceId),
      'uid': serializer.toJson<String>(uid),
      'originalStartUtcMs': serializer.toJson<int>(originalStartUtcMs),
      'seriesUid': serializer.toJson<String?>(seriesUid),
      'title': serializer.toJson<String>(title),
      'location': serializer.toJson<String?>(location),
      'organizer': serializer.toJson<String?>(organizer),
      'description': serializer.toJson<String?>(description),
      'joinUrl': serializer.toJson<String?>(joinUrl),
      'startUtcMs': serializer.toJson<int>(startUtcMs),
      'endUtcMs': serializer.toJson<int>(endUtcMs),
      'allDay': serializer.toJson<bool>(allDay),
      'busyStatus': serializer.toJson<String>(
        $OccurrencesTable.$converterbusyStatus.toJson(busyStatus),
      ),
      'declined': serializer.toJson<bool>(declined),
      'cancelled': serializer.toJson<bool>(cancelled),
      'calendarColor': serializer.toJson<int>(calendarColor),
      'warnings': serializer.toJson<String>(warnings),
      'icalUid': serializer.toJson<String?>(icalUid),
    };
  }

  OccurrenceRow copyWith({
    String? occurrenceKey,
    String? sourceId,
    String? uid,
    int? originalStartUtcMs,
    Value<String?> seriesUid = const Value.absent(),
    String? title,
    Value<String?> location = const Value.absent(),
    Value<String?> organizer = const Value.absent(),
    Value<String?> description = const Value.absent(),
    Value<String?> joinUrl = const Value.absent(),
    int? startUtcMs,
    int? endUtcMs,
    bool? allDay,
    BusyStatus? busyStatus,
    bool? declined,
    bool? cancelled,
    int? calendarColor,
    String? warnings,
    Value<String?> icalUid = const Value.absent(),
  }) => OccurrenceRow(
    occurrenceKey: occurrenceKey ?? this.occurrenceKey,
    sourceId: sourceId ?? this.sourceId,
    uid: uid ?? this.uid,
    originalStartUtcMs: originalStartUtcMs ?? this.originalStartUtcMs,
    seriesUid: seriesUid.present ? seriesUid.value : this.seriesUid,
    title: title ?? this.title,
    location: location.present ? location.value : this.location,
    organizer: organizer.present ? organizer.value : this.organizer,
    description: description.present ? description.value : this.description,
    joinUrl: joinUrl.present ? joinUrl.value : this.joinUrl,
    startUtcMs: startUtcMs ?? this.startUtcMs,
    endUtcMs: endUtcMs ?? this.endUtcMs,
    allDay: allDay ?? this.allDay,
    busyStatus: busyStatus ?? this.busyStatus,
    declined: declined ?? this.declined,
    cancelled: cancelled ?? this.cancelled,
    calendarColor: calendarColor ?? this.calendarColor,
    warnings: warnings ?? this.warnings,
    icalUid: icalUid.present ? icalUid.value : this.icalUid,
  );
  OccurrenceRow copyWithCompanion(OccurrencesCompanion data) {
    return OccurrenceRow(
      occurrenceKey: data.occurrenceKey.present
          ? data.occurrenceKey.value
          : this.occurrenceKey,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      uid: data.uid.present ? data.uid.value : this.uid,
      originalStartUtcMs: data.originalStartUtcMs.present
          ? data.originalStartUtcMs.value
          : this.originalStartUtcMs,
      seriesUid: data.seriesUid.present ? data.seriesUid.value : this.seriesUid,
      title: data.title.present ? data.title.value : this.title,
      location: data.location.present ? data.location.value : this.location,
      organizer: data.organizer.present ? data.organizer.value : this.organizer,
      description: data.description.present
          ? data.description.value
          : this.description,
      joinUrl: data.joinUrl.present ? data.joinUrl.value : this.joinUrl,
      startUtcMs: data.startUtcMs.present
          ? data.startUtcMs.value
          : this.startUtcMs,
      endUtcMs: data.endUtcMs.present ? data.endUtcMs.value : this.endUtcMs,
      allDay: data.allDay.present ? data.allDay.value : this.allDay,
      busyStatus: data.busyStatus.present
          ? data.busyStatus.value
          : this.busyStatus,
      declined: data.declined.present ? data.declined.value : this.declined,
      cancelled: data.cancelled.present ? data.cancelled.value : this.cancelled,
      calendarColor: data.calendarColor.present
          ? data.calendarColor.value
          : this.calendarColor,
      warnings: data.warnings.present ? data.warnings.value : this.warnings,
      icalUid: data.icalUid.present ? data.icalUid.value : this.icalUid,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OccurrenceRow(')
          ..write('occurrenceKey: $occurrenceKey, ')
          ..write('sourceId: $sourceId, ')
          ..write('uid: $uid, ')
          ..write('originalStartUtcMs: $originalStartUtcMs, ')
          ..write('seriesUid: $seriesUid, ')
          ..write('title: $title, ')
          ..write('location: $location, ')
          ..write('organizer: $organizer, ')
          ..write('description: $description, ')
          ..write('joinUrl: $joinUrl, ')
          ..write('startUtcMs: $startUtcMs, ')
          ..write('endUtcMs: $endUtcMs, ')
          ..write('allDay: $allDay, ')
          ..write('busyStatus: $busyStatus, ')
          ..write('declined: $declined, ')
          ..write('cancelled: $cancelled, ')
          ..write('calendarColor: $calendarColor, ')
          ..write('warnings: $warnings, ')
          ..write('icalUid: $icalUid')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    occurrenceKey,
    sourceId,
    uid,
    originalStartUtcMs,
    seriesUid,
    title,
    location,
    organizer,
    description,
    joinUrl,
    startUtcMs,
    endUtcMs,
    allDay,
    busyStatus,
    declined,
    cancelled,
    calendarColor,
    warnings,
    icalUid,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OccurrenceRow &&
          other.occurrenceKey == this.occurrenceKey &&
          other.sourceId == this.sourceId &&
          other.uid == this.uid &&
          other.originalStartUtcMs == this.originalStartUtcMs &&
          other.seriesUid == this.seriesUid &&
          other.title == this.title &&
          other.location == this.location &&
          other.organizer == this.organizer &&
          other.description == this.description &&
          other.joinUrl == this.joinUrl &&
          other.startUtcMs == this.startUtcMs &&
          other.endUtcMs == this.endUtcMs &&
          other.allDay == this.allDay &&
          other.busyStatus == this.busyStatus &&
          other.declined == this.declined &&
          other.cancelled == this.cancelled &&
          other.calendarColor == this.calendarColor &&
          other.warnings == this.warnings &&
          other.icalUid == this.icalUid);
}

class OccurrencesCompanion extends UpdateCompanion<OccurrenceRow> {
  final Value<String> occurrenceKey;
  final Value<String> sourceId;
  final Value<String> uid;
  final Value<int> originalStartUtcMs;
  final Value<String?> seriesUid;
  final Value<String> title;
  final Value<String?> location;
  final Value<String?> organizer;
  final Value<String?> description;
  final Value<String?> joinUrl;
  final Value<int> startUtcMs;
  final Value<int> endUtcMs;
  final Value<bool> allDay;
  final Value<BusyStatus> busyStatus;
  final Value<bool> declined;
  final Value<bool> cancelled;
  final Value<int> calendarColor;
  final Value<String> warnings;
  final Value<String?> icalUid;
  final Value<int> rowid;
  const OccurrencesCompanion({
    this.occurrenceKey = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.uid = const Value.absent(),
    this.originalStartUtcMs = const Value.absent(),
    this.seriesUid = const Value.absent(),
    this.title = const Value.absent(),
    this.location = const Value.absent(),
    this.organizer = const Value.absent(),
    this.description = const Value.absent(),
    this.joinUrl = const Value.absent(),
    this.startUtcMs = const Value.absent(),
    this.endUtcMs = const Value.absent(),
    this.allDay = const Value.absent(),
    this.busyStatus = const Value.absent(),
    this.declined = const Value.absent(),
    this.cancelled = const Value.absent(),
    this.calendarColor = const Value.absent(),
    this.warnings = const Value.absent(),
    this.icalUid = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OccurrencesCompanion.insert({
    required String occurrenceKey,
    required String sourceId,
    required String uid,
    required int originalStartUtcMs,
    this.seriesUid = const Value.absent(),
    required String title,
    this.location = const Value.absent(),
    this.organizer = const Value.absent(),
    this.description = const Value.absent(),
    this.joinUrl = const Value.absent(),
    required int startUtcMs,
    required int endUtcMs,
    required bool allDay,
    required BusyStatus busyStatus,
    required bool declined,
    required bool cancelled,
    required int calendarColor,
    this.warnings = const Value.absent(),
    this.icalUid = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : occurrenceKey = Value(occurrenceKey),
       sourceId = Value(sourceId),
       uid = Value(uid),
       originalStartUtcMs = Value(originalStartUtcMs),
       title = Value(title),
       startUtcMs = Value(startUtcMs),
       endUtcMs = Value(endUtcMs),
       allDay = Value(allDay),
       busyStatus = Value(busyStatus),
       declined = Value(declined),
       cancelled = Value(cancelled),
       calendarColor = Value(calendarColor);
  static Insertable<OccurrenceRow> custom({
    Expression<String>? occurrenceKey,
    Expression<String>? sourceId,
    Expression<String>? uid,
    Expression<int>? originalStartUtcMs,
    Expression<String>? seriesUid,
    Expression<String>? title,
    Expression<String>? location,
    Expression<String>? organizer,
    Expression<String>? description,
    Expression<String>? joinUrl,
    Expression<int>? startUtcMs,
    Expression<int>? endUtcMs,
    Expression<bool>? allDay,
    Expression<String>? busyStatus,
    Expression<bool>? declined,
    Expression<bool>? cancelled,
    Expression<int>? calendarColor,
    Expression<String>? warnings,
    Expression<String>? icalUid,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (occurrenceKey != null) 'occurrence_key': occurrenceKey,
      if (sourceId != null) 'source_id': sourceId,
      if (uid != null) 'uid': uid,
      if (originalStartUtcMs != null)
        'original_start_utc_ms': originalStartUtcMs,
      if (seriesUid != null) 'series_uid': seriesUid,
      if (title != null) 'title': title,
      if (location != null) 'location': location,
      if (organizer != null) 'organizer': organizer,
      if (description != null) 'description': description,
      if (joinUrl != null) 'join_url': joinUrl,
      if (startUtcMs != null) 'start_utc_ms': startUtcMs,
      if (endUtcMs != null) 'end_utc_ms': endUtcMs,
      if (allDay != null) 'all_day': allDay,
      if (busyStatus != null) 'busy_status': busyStatus,
      if (declined != null) 'declined': declined,
      if (cancelled != null) 'cancelled': cancelled,
      if (calendarColor != null) 'calendar_color': calendarColor,
      if (warnings != null) 'warnings': warnings,
      if (icalUid != null) 'ical_uid': icalUid,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OccurrencesCompanion copyWith({
    Value<String>? occurrenceKey,
    Value<String>? sourceId,
    Value<String>? uid,
    Value<int>? originalStartUtcMs,
    Value<String?>? seriesUid,
    Value<String>? title,
    Value<String?>? location,
    Value<String?>? organizer,
    Value<String?>? description,
    Value<String?>? joinUrl,
    Value<int>? startUtcMs,
    Value<int>? endUtcMs,
    Value<bool>? allDay,
    Value<BusyStatus>? busyStatus,
    Value<bool>? declined,
    Value<bool>? cancelled,
    Value<int>? calendarColor,
    Value<String>? warnings,
    Value<String?>? icalUid,
    Value<int>? rowid,
  }) {
    return OccurrencesCompanion(
      occurrenceKey: occurrenceKey ?? this.occurrenceKey,
      sourceId: sourceId ?? this.sourceId,
      uid: uid ?? this.uid,
      originalStartUtcMs: originalStartUtcMs ?? this.originalStartUtcMs,
      seriesUid: seriesUid ?? this.seriesUid,
      title: title ?? this.title,
      location: location ?? this.location,
      organizer: organizer ?? this.organizer,
      description: description ?? this.description,
      joinUrl: joinUrl ?? this.joinUrl,
      startUtcMs: startUtcMs ?? this.startUtcMs,
      endUtcMs: endUtcMs ?? this.endUtcMs,
      allDay: allDay ?? this.allDay,
      busyStatus: busyStatus ?? this.busyStatus,
      declined: declined ?? this.declined,
      cancelled: cancelled ?? this.cancelled,
      calendarColor: calendarColor ?? this.calendarColor,
      warnings: warnings ?? this.warnings,
      icalUid: icalUid ?? this.icalUid,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (occurrenceKey.present) {
      map['occurrence_key'] = Variable<String>(occurrenceKey.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (uid.present) {
      map['uid'] = Variable<String>(uid.value);
    }
    if (originalStartUtcMs.present) {
      map['original_start_utc_ms'] = Variable<int>(originalStartUtcMs.value);
    }
    if (seriesUid.present) {
      map['series_uid'] = Variable<String>(seriesUid.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (location.present) {
      map['location'] = Variable<String>(location.value);
    }
    if (organizer.present) {
      map['organizer'] = Variable<String>(organizer.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (joinUrl.present) {
      map['join_url'] = Variable<String>(joinUrl.value);
    }
    if (startUtcMs.present) {
      map['start_utc_ms'] = Variable<int>(startUtcMs.value);
    }
    if (endUtcMs.present) {
      map['end_utc_ms'] = Variable<int>(endUtcMs.value);
    }
    if (allDay.present) {
      map['all_day'] = Variable<bool>(allDay.value);
    }
    if (busyStatus.present) {
      map['busy_status'] = Variable<String>(
        $OccurrencesTable.$converterbusyStatus.toSql(busyStatus.value),
      );
    }
    if (declined.present) {
      map['declined'] = Variable<bool>(declined.value);
    }
    if (cancelled.present) {
      map['cancelled'] = Variable<bool>(cancelled.value);
    }
    if (calendarColor.present) {
      map['calendar_color'] = Variable<int>(calendarColor.value);
    }
    if (warnings.present) {
      map['warnings'] = Variable<String>(warnings.value);
    }
    if (icalUid.present) {
      map['ical_uid'] = Variable<String>(icalUid.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OccurrencesCompanion(')
          ..write('occurrenceKey: $occurrenceKey, ')
          ..write('sourceId: $sourceId, ')
          ..write('uid: $uid, ')
          ..write('originalStartUtcMs: $originalStartUtcMs, ')
          ..write('seriesUid: $seriesUid, ')
          ..write('title: $title, ')
          ..write('location: $location, ')
          ..write('organizer: $organizer, ')
          ..write('description: $description, ')
          ..write('joinUrl: $joinUrl, ')
          ..write('startUtcMs: $startUtcMs, ')
          ..write('endUtcMs: $endUtcMs, ')
          ..write('allDay: $allDay, ')
          ..write('busyStatus: $busyStatus, ')
          ..write('declined: $declined, ')
          ..write('cancelled: $cancelled, ')
          ..write('calendarColor: $calendarColor, ')
          ..write('warnings: $warnings, ')
          ..write('icalUid: $icalUid, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AlertHistoryTable extends AlertHistory
    with TableInfo<$AlertHistoryTable, AlertHistoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AlertHistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<AlertEventType, String> type =
      GeneratedColumn<String>(
        'type',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<AlertEventType>($AlertHistoryTable.$convertertype);
  static const VerificationMeta _alertIdMeta = const VerificationMeta(
    'alertId',
  );
  @override
  late final GeneratedColumn<String> alertId = GeneratedColumn<String>(
    'alert_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _occurrenceKeyMeta = const VerificationMeta(
    'occurrenceKey',
  );
  @override
  late final GeneratedColumn<String> occurrenceKey = GeneratedColumn<String>(
    'occurrence_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startUtcMsMeta = const VerificationMeta(
    'startUtcMs',
  );
  @override
  late final GeneratedColumn<int> startUtcMs = GeneratedColumn<int>(
    'start_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _atUtcMsMeta = const VerificationMeta(
    'atUtcMs',
  );
  @override
  late final GeneratedColumn<int> atUtcMs = GeneratedColumn<int>(
    'at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snoozeUntilUtcMsMeta = const VerificationMeta(
    'snoozeUntilUtcMs',
  );
  @override
  late final GeneratedColumn<int> snoozeUntilUtcMs = GeneratedColumn<int>(
    'snooze_until_utc_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    type,
    alertId,
    occurrenceKey,
    startUtcMs,
    atUtcMs,
    snoozeUntilUtcMs,
    title,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'alert_history';
  @override
  VerificationContext validateIntegrity(
    Insertable<AlertHistoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('alert_id')) {
      context.handle(
        _alertIdMeta,
        alertId.isAcceptableOrUnknown(data['alert_id']!, _alertIdMeta),
      );
    } else if (isInserting) {
      context.missing(_alertIdMeta);
    }
    if (data.containsKey('occurrence_key')) {
      context.handle(
        _occurrenceKeyMeta,
        occurrenceKey.isAcceptableOrUnknown(
          data['occurrence_key']!,
          _occurrenceKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_occurrenceKeyMeta);
    }
    if (data.containsKey('start_utc_ms')) {
      context.handle(
        _startUtcMsMeta,
        startUtcMs.isAcceptableOrUnknown(
          data['start_utc_ms']!,
          _startUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startUtcMsMeta);
    }
    if (data.containsKey('at_utc_ms')) {
      context.handle(
        _atUtcMsMeta,
        atUtcMs.isAcceptableOrUnknown(data['at_utc_ms']!, _atUtcMsMeta),
      );
    } else if (isInserting) {
      context.missing(_atUtcMsMeta);
    }
    if (data.containsKey('snooze_until_utc_ms')) {
      context.handle(
        _snoozeUntilUtcMsMeta,
        snoozeUntilUtcMs.isAcceptableOrUnknown(
          data['snooze_until_utc_ms']!,
          _snoozeUntilUtcMsMeta,
        ),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {type, alertId, atUtcMs},
  ];
  @override
  AlertHistoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AlertHistoryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      type: $AlertHistoryTable.$convertertype.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}type'],
        )!,
      ),
      alertId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}alert_id'],
      )!,
      occurrenceKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}occurrence_key'],
      )!,
      startUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_utc_ms'],
      )!,
      atUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}at_utc_ms'],
      )!,
      snoozeUntilUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}snooze_until_utc_ms'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
    );
  }

  @override
  $AlertHistoryTable createAlias(String alias) {
    return $AlertHistoryTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<AlertEventType, String, String> $convertertype =
      const EnumNameConverter<AlertEventType>(AlertEventType.values);
}

class AlertHistoryRow extends DataClass implements Insertable<AlertHistoryRow> {
  final int id;
  final AlertEventType type;
  final String alertId;
  final String occurrenceKey;
  final int startUtcMs;
  final int atUtcMs;
  final int? snoozeUntilUtcMs;

  /// Event title at the time, so Health's timeline survives cache pruning.
  final String? title;
  const AlertHistoryRow({
    required this.id,
    required this.type,
    required this.alertId,
    required this.occurrenceKey,
    required this.startUtcMs,
    required this.atUtcMs,
    this.snoozeUntilUtcMs,
    this.title,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    {
      map['type'] = Variable<String>(
        $AlertHistoryTable.$convertertype.toSql(type),
      );
    }
    map['alert_id'] = Variable<String>(alertId);
    map['occurrence_key'] = Variable<String>(occurrenceKey);
    map['start_utc_ms'] = Variable<int>(startUtcMs);
    map['at_utc_ms'] = Variable<int>(atUtcMs);
    if (!nullToAbsent || snoozeUntilUtcMs != null) {
      map['snooze_until_utc_ms'] = Variable<int>(snoozeUntilUtcMs);
    }
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    return map;
  }

  AlertHistoryCompanion toCompanion(bool nullToAbsent) {
    return AlertHistoryCompanion(
      id: Value(id),
      type: Value(type),
      alertId: Value(alertId),
      occurrenceKey: Value(occurrenceKey),
      startUtcMs: Value(startUtcMs),
      atUtcMs: Value(atUtcMs),
      snoozeUntilUtcMs: snoozeUntilUtcMs == null && nullToAbsent
          ? const Value.absent()
          : Value(snoozeUntilUtcMs),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
    );
  }

  factory AlertHistoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AlertHistoryRow(
      id: serializer.fromJson<int>(json['id']),
      type: $AlertHistoryTable.$convertertype.fromJson(
        serializer.fromJson<String>(json['type']),
      ),
      alertId: serializer.fromJson<String>(json['alertId']),
      occurrenceKey: serializer.fromJson<String>(json['occurrenceKey']),
      startUtcMs: serializer.fromJson<int>(json['startUtcMs']),
      atUtcMs: serializer.fromJson<int>(json['atUtcMs']),
      snoozeUntilUtcMs: serializer.fromJson<int?>(json['snoozeUntilUtcMs']),
      title: serializer.fromJson<String?>(json['title']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'type': serializer.toJson<String>(
        $AlertHistoryTable.$convertertype.toJson(type),
      ),
      'alertId': serializer.toJson<String>(alertId),
      'occurrenceKey': serializer.toJson<String>(occurrenceKey),
      'startUtcMs': serializer.toJson<int>(startUtcMs),
      'atUtcMs': serializer.toJson<int>(atUtcMs),
      'snoozeUntilUtcMs': serializer.toJson<int?>(snoozeUntilUtcMs),
      'title': serializer.toJson<String?>(title),
    };
  }

  AlertHistoryRow copyWith({
    int? id,
    AlertEventType? type,
    String? alertId,
    String? occurrenceKey,
    int? startUtcMs,
    int? atUtcMs,
    Value<int?> snoozeUntilUtcMs = const Value.absent(),
    Value<String?> title = const Value.absent(),
  }) => AlertHistoryRow(
    id: id ?? this.id,
    type: type ?? this.type,
    alertId: alertId ?? this.alertId,
    occurrenceKey: occurrenceKey ?? this.occurrenceKey,
    startUtcMs: startUtcMs ?? this.startUtcMs,
    atUtcMs: atUtcMs ?? this.atUtcMs,
    snoozeUntilUtcMs: snoozeUntilUtcMs.present
        ? snoozeUntilUtcMs.value
        : this.snoozeUntilUtcMs,
    title: title.present ? title.value : this.title,
  );
  AlertHistoryRow copyWithCompanion(AlertHistoryCompanion data) {
    return AlertHistoryRow(
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      alertId: data.alertId.present ? data.alertId.value : this.alertId,
      occurrenceKey: data.occurrenceKey.present
          ? data.occurrenceKey.value
          : this.occurrenceKey,
      startUtcMs: data.startUtcMs.present
          ? data.startUtcMs.value
          : this.startUtcMs,
      atUtcMs: data.atUtcMs.present ? data.atUtcMs.value : this.atUtcMs,
      snoozeUntilUtcMs: data.snoozeUntilUtcMs.present
          ? data.snoozeUntilUtcMs.value
          : this.snoozeUntilUtcMs,
      title: data.title.present ? data.title.value : this.title,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AlertHistoryRow(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('alertId: $alertId, ')
          ..write('occurrenceKey: $occurrenceKey, ')
          ..write('startUtcMs: $startUtcMs, ')
          ..write('atUtcMs: $atUtcMs, ')
          ..write('snoozeUntilUtcMs: $snoozeUntilUtcMs, ')
          ..write('title: $title')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    type,
    alertId,
    occurrenceKey,
    startUtcMs,
    atUtcMs,
    snoozeUntilUtcMs,
    title,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AlertHistoryRow &&
          other.id == this.id &&
          other.type == this.type &&
          other.alertId == this.alertId &&
          other.occurrenceKey == this.occurrenceKey &&
          other.startUtcMs == this.startUtcMs &&
          other.atUtcMs == this.atUtcMs &&
          other.snoozeUntilUtcMs == this.snoozeUntilUtcMs &&
          other.title == this.title);
}

class AlertHistoryCompanion extends UpdateCompanion<AlertHistoryRow> {
  final Value<int> id;
  final Value<AlertEventType> type;
  final Value<String> alertId;
  final Value<String> occurrenceKey;
  final Value<int> startUtcMs;
  final Value<int> atUtcMs;
  final Value<int?> snoozeUntilUtcMs;
  final Value<String?> title;
  const AlertHistoryCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.alertId = const Value.absent(),
    this.occurrenceKey = const Value.absent(),
    this.startUtcMs = const Value.absent(),
    this.atUtcMs = const Value.absent(),
    this.snoozeUntilUtcMs = const Value.absent(),
    this.title = const Value.absent(),
  });
  AlertHistoryCompanion.insert({
    this.id = const Value.absent(),
    required AlertEventType type,
    required String alertId,
    required String occurrenceKey,
    required int startUtcMs,
    required int atUtcMs,
    this.snoozeUntilUtcMs = const Value.absent(),
    this.title = const Value.absent(),
  }) : type = Value(type),
       alertId = Value(alertId),
       occurrenceKey = Value(occurrenceKey),
       startUtcMs = Value(startUtcMs),
       atUtcMs = Value(atUtcMs);
  static Insertable<AlertHistoryRow> custom({
    Expression<int>? id,
    Expression<String>? type,
    Expression<String>? alertId,
    Expression<String>? occurrenceKey,
    Expression<int>? startUtcMs,
    Expression<int>? atUtcMs,
    Expression<int>? snoozeUntilUtcMs,
    Expression<String>? title,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (alertId != null) 'alert_id': alertId,
      if (occurrenceKey != null) 'occurrence_key': occurrenceKey,
      if (startUtcMs != null) 'start_utc_ms': startUtcMs,
      if (atUtcMs != null) 'at_utc_ms': atUtcMs,
      if (snoozeUntilUtcMs != null) 'snooze_until_utc_ms': snoozeUntilUtcMs,
      if (title != null) 'title': title,
    });
  }

  AlertHistoryCompanion copyWith({
    Value<int>? id,
    Value<AlertEventType>? type,
    Value<String>? alertId,
    Value<String>? occurrenceKey,
    Value<int>? startUtcMs,
    Value<int>? atUtcMs,
    Value<int?>? snoozeUntilUtcMs,
    Value<String?>? title,
  }) {
    return AlertHistoryCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      alertId: alertId ?? this.alertId,
      occurrenceKey: occurrenceKey ?? this.occurrenceKey,
      startUtcMs: startUtcMs ?? this.startUtcMs,
      atUtcMs: atUtcMs ?? this.atUtcMs,
      snoozeUntilUtcMs: snoozeUntilUtcMs ?? this.snoozeUntilUtcMs,
      title: title ?? this.title,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(
        $AlertHistoryTable.$convertertype.toSql(type.value),
      );
    }
    if (alertId.present) {
      map['alert_id'] = Variable<String>(alertId.value);
    }
    if (occurrenceKey.present) {
      map['occurrence_key'] = Variable<String>(occurrenceKey.value);
    }
    if (startUtcMs.present) {
      map['start_utc_ms'] = Variable<int>(startUtcMs.value);
    }
    if (atUtcMs.present) {
      map['at_utc_ms'] = Variable<int>(atUtcMs.value);
    }
    if (snoozeUntilUtcMs.present) {
      map['snooze_until_utc_ms'] = Variable<int>(snoozeUntilUtcMs.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AlertHistoryCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('alertId: $alertId, ')
          ..write('occurrenceKey: $occurrenceKey, ')
          ..write('startUtcMs: $startUtcMs, ')
          ..write('atUtcMs: $atUtcMs, ')
          ..write('snoozeUntilUtcMs: $snoozeUntilUtcMs, ')
          ..write('title: $title')
          ..write(')'))
        .toString();
  }
}

class $SyncLogTable extends SyncLog with TableInfo<$SyncLogTable, SyncLogRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncLogTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _atUtcMsMeta = const VerificationMeta(
    'atUtcMs',
  );
  @override
  late final GeneratedColumn<int> atUtcMs = GeneratedColumn<int>(
    'at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncOutcome, String> outcome =
      GeneratedColumn<String>(
        'outcome',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<SyncOutcome>($SyncLogTable.$converteroutcome);
  static const VerificationMeta _messageMeta = const VerificationMeta(
    'message',
  );
  @override
  late final GeneratedColumn<String> message = GeneratedColumn<String>(
    'message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _occurrenceCountMeta = const VerificationMeta(
    'occurrenceCount',
  );
  @override
  late final GeneratedColumn<int> occurrenceCount = GeneratedColumn<int>(
    'occurrence_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sourceId,
    atUtcMs,
    outcome,
    message,
    occurrenceCount,
    durationMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_log';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncLogRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    }
    if (data.containsKey('at_utc_ms')) {
      context.handle(
        _atUtcMsMeta,
        atUtcMs.isAcceptableOrUnknown(data['at_utc_ms']!, _atUtcMsMeta),
      );
    } else if (isInserting) {
      context.missing(_atUtcMsMeta);
    }
    if (data.containsKey('message')) {
      context.handle(
        _messageMeta,
        message.isAcceptableOrUnknown(data['message']!, _messageMeta),
      );
    }
    if (data.containsKey('occurrence_count')) {
      context.handle(
        _occurrenceCountMeta,
        occurrenceCount.isAcceptableOrUnknown(
          data['occurrence_count']!,
          _occurrenceCountMeta,
        ),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncLogRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncLogRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      ),
      atUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}at_utc_ms'],
      )!,
      outcome: $SyncLogTable.$converteroutcome.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}outcome'],
        )!,
      ),
      message: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message'],
      ),
      occurrenceCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}occurrence_count'],
      ),
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
    );
  }

  @override
  $SyncLogTable createAlias(String alias) {
    return $SyncLogTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<SyncOutcome, String, String> $converteroutcome =
      const EnumNameConverter<SyncOutcome>(SyncOutcome.values);
}

class SyncLogRow extends DataClass implements Insertable<SyncLogRow> {
  final int id;

  /// Null for a whole-run entry (e.g. "applyPlan failed").
  final String? sourceId;
  final int atUtcMs;
  final SyncOutcome outcome;
  final String? message;
  final int? occurrenceCount;
  final int? durationMs;
  const SyncLogRow({
    required this.id,
    this.sourceId,
    required this.atUtcMs,
    required this.outcome,
    this.message,
    this.occurrenceCount,
    this.durationMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || sourceId != null) {
      map['source_id'] = Variable<String>(sourceId);
    }
    map['at_utc_ms'] = Variable<int>(atUtcMs);
    {
      map['outcome'] = Variable<String>(
        $SyncLogTable.$converteroutcome.toSql(outcome),
      );
    }
    if (!nullToAbsent || message != null) {
      map['message'] = Variable<String>(message);
    }
    if (!nullToAbsent || occurrenceCount != null) {
      map['occurrence_count'] = Variable<int>(occurrenceCount);
    }
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    return map;
  }

  SyncLogCompanion toCompanion(bool nullToAbsent) {
    return SyncLogCompanion(
      id: Value(id),
      sourceId: sourceId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceId),
      atUtcMs: Value(atUtcMs),
      outcome: Value(outcome),
      message: message == null && nullToAbsent
          ? const Value.absent()
          : Value(message),
      occurrenceCount: occurrenceCount == null && nullToAbsent
          ? const Value.absent()
          : Value(occurrenceCount),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
    );
  }

  factory SyncLogRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncLogRow(
      id: serializer.fromJson<int>(json['id']),
      sourceId: serializer.fromJson<String?>(json['sourceId']),
      atUtcMs: serializer.fromJson<int>(json['atUtcMs']),
      outcome: $SyncLogTable.$converteroutcome.fromJson(
        serializer.fromJson<String>(json['outcome']),
      ),
      message: serializer.fromJson<String?>(json['message']),
      occurrenceCount: serializer.fromJson<int?>(json['occurrenceCount']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sourceId': serializer.toJson<String?>(sourceId),
      'atUtcMs': serializer.toJson<int>(atUtcMs),
      'outcome': serializer.toJson<String>(
        $SyncLogTable.$converteroutcome.toJson(outcome),
      ),
      'message': serializer.toJson<String?>(message),
      'occurrenceCount': serializer.toJson<int?>(occurrenceCount),
      'durationMs': serializer.toJson<int?>(durationMs),
    };
  }

  SyncLogRow copyWith({
    int? id,
    Value<String?> sourceId = const Value.absent(),
    int? atUtcMs,
    SyncOutcome? outcome,
    Value<String?> message = const Value.absent(),
    Value<int?> occurrenceCount = const Value.absent(),
    Value<int?> durationMs = const Value.absent(),
  }) => SyncLogRow(
    id: id ?? this.id,
    sourceId: sourceId.present ? sourceId.value : this.sourceId,
    atUtcMs: atUtcMs ?? this.atUtcMs,
    outcome: outcome ?? this.outcome,
    message: message.present ? message.value : this.message,
    occurrenceCount: occurrenceCount.present
        ? occurrenceCount.value
        : this.occurrenceCount,
    durationMs: durationMs.present ? durationMs.value : this.durationMs,
  );
  SyncLogRow copyWithCompanion(SyncLogCompanion data) {
    return SyncLogRow(
      id: data.id.present ? data.id.value : this.id,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      atUtcMs: data.atUtcMs.present ? data.atUtcMs.value : this.atUtcMs,
      outcome: data.outcome.present ? data.outcome.value : this.outcome,
      message: data.message.present ? data.message.value : this.message,
      occurrenceCount: data.occurrenceCount.present
          ? data.occurrenceCount.value
          : this.occurrenceCount,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncLogRow(')
          ..write('id: $id, ')
          ..write('sourceId: $sourceId, ')
          ..write('atUtcMs: $atUtcMs, ')
          ..write('outcome: $outcome, ')
          ..write('message: $message, ')
          ..write('occurrenceCount: $occurrenceCount, ')
          ..write('durationMs: $durationMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sourceId,
    atUtcMs,
    outcome,
    message,
    occurrenceCount,
    durationMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncLogRow &&
          other.id == this.id &&
          other.sourceId == this.sourceId &&
          other.atUtcMs == this.atUtcMs &&
          other.outcome == this.outcome &&
          other.message == this.message &&
          other.occurrenceCount == this.occurrenceCount &&
          other.durationMs == this.durationMs);
}

class SyncLogCompanion extends UpdateCompanion<SyncLogRow> {
  final Value<int> id;
  final Value<String?> sourceId;
  final Value<int> atUtcMs;
  final Value<SyncOutcome> outcome;
  final Value<String?> message;
  final Value<int?> occurrenceCount;
  final Value<int?> durationMs;
  const SyncLogCompanion({
    this.id = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.atUtcMs = const Value.absent(),
    this.outcome = const Value.absent(),
    this.message = const Value.absent(),
    this.occurrenceCount = const Value.absent(),
    this.durationMs = const Value.absent(),
  });
  SyncLogCompanion.insert({
    this.id = const Value.absent(),
    this.sourceId = const Value.absent(),
    required int atUtcMs,
    required SyncOutcome outcome,
    this.message = const Value.absent(),
    this.occurrenceCount = const Value.absent(),
    this.durationMs = const Value.absent(),
  }) : atUtcMs = Value(atUtcMs),
       outcome = Value(outcome);
  static Insertable<SyncLogRow> custom({
    Expression<int>? id,
    Expression<String>? sourceId,
    Expression<int>? atUtcMs,
    Expression<String>? outcome,
    Expression<String>? message,
    Expression<int>? occurrenceCount,
    Expression<int>? durationMs,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sourceId != null) 'source_id': sourceId,
      if (atUtcMs != null) 'at_utc_ms': atUtcMs,
      if (outcome != null) 'outcome': outcome,
      if (message != null) 'message': message,
      if (occurrenceCount != null) 'occurrence_count': occurrenceCount,
      if (durationMs != null) 'duration_ms': durationMs,
    });
  }

  SyncLogCompanion copyWith({
    Value<int>? id,
    Value<String?>? sourceId,
    Value<int>? atUtcMs,
    Value<SyncOutcome>? outcome,
    Value<String?>? message,
    Value<int?>? occurrenceCount,
    Value<int?>? durationMs,
  }) {
    return SyncLogCompanion(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      atUtcMs: atUtcMs ?? this.atUtcMs,
      outcome: outcome ?? this.outcome,
      message: message ?? this.message,
      occurrenceCount: occurrenceCount ?? this.occurrenceCount,
      durationMs: durationMs ?? this.durationMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (atUtcMs.present) {
      map['at_utc_ms'] = Variable<int>(atUtcMs.value);
    }
    if (outcome.present) {
      map['outcome'] = Variable<String>(
        $SyncLogTable.$converteroutcome.toSql(outcome.value),
      );
    }
    if (message.present) {
      map['message'] = Variable<String>(message.value);
    }
    if (occurrenceCount.present) {
      map['occurrence_count'] = Variable<int>(occurrenceCount.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncLogCompanion(')
          ..write('id: $id, ')
          ..write('sourceId: $sourceId, ')
          ..write('atUtcMs: $atUtcMs, ')
          ..write('outcome: $outcome, ')
          ..write('message: $message, ')
          ..write('occurrenceCount: $occurrenceCount, ')
          ..write('durationMs: $durationMs')
          ..write(')'))
        .toString();
  }
}

class $CacheValuesTable extends CacheValues
    with TableInfo<$CacheValuesTable, CacheValueRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CacheValuesTable(this.attachedDatabase, [this._alias]);
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
  static const String $name = 'cache_values';
  @override
  VerificationContext validateIntegrity(
    Insertable<CacheValueRow> instance, {
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
  CacheValueRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CacheValueRow(
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
  $CacheValuesTable createAlias(String alias) {
    return $CacheValuesTable(attachedDatabase, alias);
  }
}

class CacheValueRow extends DataClass implements Insertable<CacheValueRow> {
  final String name;
  final String value;
  const CacheValueRow({required this.name, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['name'] = Variable<String>(name);
    map['value'] = Variable<String>(value);
    return map;
  }

  CacheValuesCompanion toCompanion(bool nullToAbsent) {
    return CacheValuesCompanion(name: Value(name), value: Value(value));
  }

  factory CacheValueRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CacheValueRow(
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

  CacheValueRow copyWith({String? name, String? value}) =>
      CacheValueRow(name: name ?? this.name, value: value ?? this.value);
  CacheValueRow copyWithCompanion(CacheValuesCompanion data) {
    return CacheValueRow(
      name: data.name.present ? data.name.value : this.name,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CacheValueRow(')
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
      (other is CacheValueRow &&
          other.name == this.name &&
          other.value == this.value);
}

class CacheValuesCompanion extends UpdateCompanion<CacheValueRow> {
  final Value<String> name;
  final Value<String> value;
  final Value<int> rowid;
  const CacheValuesCompanion({
    this.name = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CacheValuesCompanion.insert({
    required String name,
    required String value,
    this.rowid = const Value.absent(),
  }) : name = Value(name),
       value = Value(value);
  static Insertable<CacheValueRow> custom({
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

  CacheValuesCompanion copyWith({
    Value<String>? name,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return CacheValuesCompanion(
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
    return (StringBuffer('CacheValuesCompanion(')
          ..write('name: $name, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$CacheDatabase extends GeneratedDatabase {
  _$CacheDatabase(QueryExecutor e) : super(e);
  $CacheDatabaseManager get managers => $CacheDatabaseManager(this);
  late final $OccurrencesTable occurrences = $OccurrencesTable(this);
  late final $AlertHistoryTable alertHistory = $AlertHistoryTable(this);
  late final $SyncLogTable syncLog = $SyncLogTable(this);
  late final $CacheValuesTable cacheValues = $CacheValuesTable(this);
  late final Index occurrencesStart = Index(
    'occurrences_start',
    'CREATE INDEX IF NOT EXISTS occurrences_start ON occurrences (start_utc_ms)',
  );
  late final Index occurrencesSource = Index(
    'occurrences_source',
    'CREATE INDEX IF NOT EXISTS occurrences_source ON occurrences (source_id)',
  );
  late final Index alertHistoryStart = Index(
    'alert_history_start',
    'CREATE INDEX IF NOT EXISTS alert_history_start ON alert_history (start_utc_ms)',
  );
  late final Index syncLogAt = Index(
    'sync_log_at',
    'CREATE INDEX IF NOT EXISTS sync_log_at ON sync_log (at_utc_ms)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    occurrences,
    alertHistory,
    syncLog,
    cacheValues,
    occurrencesStart,
    occurrencesSource,
    alertHistoryStart,
    syncLogAt,
  ];
}

typedef $$OccurrencesTableCreateCompanionBuilder =
    OccurrencesCompanion Function({
      required String occurrenceKey,
      required String sourceId,
      required String uid,
      required int originalStartUtcMs,
      Value<String?> seriesUid,
      required String title,
      Value<String?> location,
      Value<String?> organizer,
      Value<String?> description,
      Value<String?> joinUrl,
      required int startUtcMs,
      required int endUtcMs,
      required bool allDay,
      required BusyStatus busyStatus,
      required bool declined,
      required bool cancelled,
      required int calendarColor,
      Value<String> warnings,
      Value<String?> icalUid,
      Value<int> rowid,
    });
typedef $$OccurrencesTableUpdateCompanionBuilder =
    OccurrencesCompanion Function({
      Value<String> occurrenceKey,
      Value<String> sourceId,
      Value<String> uid,
      Value<int> originalStartUtcMs,
      Value<String?> seriesUid,
      Value<String> title,
      Value<String?> location,
      Value<String?> organizer,
      Value<String?> description,
      Value<String?> joinUrl,
      Value<int> startUtcMs,
      Value<int> endUtcMs,
      Value<bool> allDay,
      Value<BusyStatus> busyStatus,
      Value<bool> declined,
      Value<bool> cancelled,
      Value<int> calendarColor,
      Value<String> warnings,
      Value<String?> icalUid,
      Value<int> rowid,
    });

class $$OccurrencesTableFilterComposer
    extends Composer<_$CacheDatabase, $OccurrencesTable> {
  $$OccurrencesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get occurrenceKey => $composableBuilder(
    column: $table.occurrenceKey,
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

  ColumnFilters<int> get originalStartUtcMs => $composableBuilder(
    column: $table.originalStartUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get seriesUid => $composableBuilder(
    column: $table.seriesUid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get organizer => $composableBuilder(
    column: $table.organizer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get joinUrl => $composableBuilder(
    column: $table.joinUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startUtcMs => $composableBuilder(
    column: $table.startUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endUtcMs => $composableBuilder(
    column: $table.endUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get allDay => $composableBuilder(
    column: $table.allDay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<BusyStatus, BusyStatus, String>
  get busyStatus => $composableBuilder(
    column: $table.busyStatus,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<bool> get declined => $composableBuilder(
    column: $table.declined,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get cancelled => $composableBuilder(
    column: $table.cancelled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get calendarColor => $composableBuilder(
    column: $table.calendarColor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get warnings => $composableBuilder(
    column: $table.warnings,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get icalUid => $composableBuilder(
    column: $table.icalUid,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OccurrencesTableOrderingComposer
    extends Composer<_$CacheDatabase, $OccurrencesTable> {
  $$OccurrencesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get occurrenceKey => $composableBuilder(
    column: $table.occurrenceKey,
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

  ColumnOrderings<int> get originalStartUtcMs => $composableBuilder(
    column: $table.originalStartUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get seriesUid => $composableBuilder(
    column: $table.seriesUid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get organizer => $composableBuilder(
    column: $table.organizer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get joinUrl => $composableBuilder(
    column: $table.joinUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startUtcMs => $composableBuilder(
    column: $table.startUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endUtcMs => $composableBuilder(
    column: $table.endUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get allDay => $composableBuilder(
    column: $table.allDay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get busyStatus => $composableBuilder(
    column: $table.busyStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get declined => $composableBuilder(
    column: $table.declined,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get cancelled => $composableBuilder(
    column: $table.cancelled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get calendarColor => $composableBuilder(
    column: $table.calendarColor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get warnings => $composableBuilder(
    column: $table.warnings,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get icalUid => $composableBuilder(
    column: $table.icalUid,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OccurrencesTableAnnotationComposer
    extends Composer<_$CacheDatabase, $OccurrencesTable> {
  $$OccurrencesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get occurrenceKey => $composableBuilder(
    column: $table.occurrenceKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get uid =>
      $composableBuilder(column: $table.uid, builder: (column) => column);

  GeneratedColumn<int> get originalStartUtcMs => $composableBuilder(
    column: $table.originalStartUtcMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get seriesUid =>
      $composableBuilder(column: $table.seriesUid, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get location =>
      $composableBuilder(column: $table.location, builder: (column) => column);

  GeneratedColumn<String> get organizer =>
      $composableBuilder(column: $table.organizer, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get joinUrl =>
      $composableBuilder(column: $table.joinUrl, builder: (column) => column);

  GeneratedColumn<int> get startUtcMs => $composableBuilder(
    column: $table.startUtcMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get endUtcMs =>
      $composableBuilder(column: $table.endUtcMs, builder: (column) => column);

  GeneratedColumn<bool> get allDay =>
      $composableBuilder(column: $table.allDay, builder: (column) => column);

  GeneratedColumnWithTypeConverter<BusyStatus, String> get busyStatus =>
      $composableBuilder(
        column: $table.busyStatus,
        builder: (column) => column,
      );

  GeneratedColumn<bool> get declined =>
      $composableBuilder(column: $table.declined, builder: (column) => column);

  GeneratedColumn<bool> get cancelled =>
      $composableBuilder(column: $table.cancelled, builder: (column) => column);

  GeneratedColumn<int> get calendarColor => $composableBuilder(
    column: $table.calendarColor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get warnings =>
      $composableBuilder(column: $table.warnings, builder: (column) => column);

  GeneratedColumn<String> get icalUid =>
      $composableBuilder(column: $table.icalUid, builder: (column) => column);
}

class $$OccurrencesTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $OccurrencesTable,
          OccurrenceRow,
          $$OccurrencesTableFilterComposer,
          $$OccurrencesTableOrderingComposer,
          $$OccurrencesTableAnnotationComposer,
          $$OccurrencesTableCreateCompanionBuilder,
          $$OccurrencesTableUpdateCompanionBuilder,
          (
            OccurrenceRow,
            BaseReferences<_$CacheDatabase, $OccurrencesTable, OccurrenceRow>,
          ),
          OccurrenceRow,
          PrefetchHooks Function()
        > {
  $$OccurrencesTableTableManager(_$CacheDatabase db, $OccurrencesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OccurrencesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OccurrencesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OccurrencesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> occurrenceKey = const Value.absent(),
                Value<String> sourceId = const Value.absent(),
                Value<String> uid = const Value.absent(),
                Value<int> originalStartUtcMs = const Value.absent(),
                Value<String?> seriesUid = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> location = const Value.absent(),
                Value<String?> organizer = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String?> joinUrl = const Value.absent(),
                Value<int> startUtcMs = const Value.absent(),
                Value<int> endUtcMs = const Value.absent(),
                Value<bool> allDay = const Value.absent(),
                Value<BusyStatus> busyStatus = const Value.absent(),
                Value<bool> declined = const Value.absent(),
                Value<bool> cancelled = const Value.absent(),
                Value<int> calendarColor = const Value.absent(),
                Value<String> warnings = const Value.absent(),
                Value<String?> icalUid = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OccurrencesCompanion(
                occurrenceKey: occurrenceKey,
                sourceId: sourceId,
                uid: uid,
                originalStartUtcMs: originalStartUtcMs,
                seriesUid: seriesUid,
                title: title,
                location: location,
                organizer: organizer,
                description: description,
                joinUrl: joinUrl,
                startUtcMs: startUtcMs,
                endUtcMs: endUtcMs,
                allDay: allDay,
                busyStatus: busyStatus,
                declined: declined,
                cancelled: cancelled,
                calendarColor: calendarColor,
                warnings: warnings,
                icalUid: icalUid,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String occurrenceKey,
                required String sourceId,
                required String uid,
                required int originalStartUtcMs,
                Value<String?> seriesUid = const Value.absent(),
                required String title,
                Value<String?> location = const Value.absent(),
                Value<String?> organizer = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String?> joinUrl = const Value.absent(),
                required int startUtcMs,
                required int endUtcMs,
                required bool allDay,
                required BusyStatus busyStatus,
                required bool declined,
                required bool cancelled,
                required int calendarColor,
                Value<String> warnings = const Value.absent(),
                Value<String?> icalUid = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OccurrencesCompanion.insert(
                occurrenceKey: occurrenceKey,
                sourceId: sourceId,
                uid: uid,
                originalStartUtcMs: originalStartUtcMs,
                seriesUid: seriesUid,
                title: title,
                location: location,
                organizer: organizer,
                description: description,
                joinUrl: joinUrl,
                startUtcMs: startUtcMs,
                endUtcMs: endUtcMs,
                allDay: allDay,
                busyStatus: busyStatus,
                declined: declined,
                cancelled: cancelled,
                calendarColor: calendarColor,
                warnings: warnings,
                icalUid: icalUid,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OccurrencesTable, OccurrenceRow>(table),
                  BaseReferences<
                    _$CacheDatabase,
                    $OccurrencesTable,
                    OccurrenceRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OccurrencesTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $OccurrencesTable,
      OccurrenceRow,
      $$OccurrencesTableFilterComposer,
      $$OccurrencesTableOrderingComposer,
      $$OccurrencesTableAnnotationComposer,
      $$OccurrencesTableCreateCompanionBuilder,
      $$OccurrencesTableUpdateCompanionBuilder,
      (
        OccurrenceRow,
        BaseReferences<_$CacheDatabase, $OccurrencesTable, OccurrenceRow>,
      ),
      OccurrenceRow,
      PrefetchHooks Function()
    >;
typedef $$AlertHistoryTableCreateCompanionBuilder =
    AlertHistoryCompanion Function({
      Value<int> id,
      required AlertEventType type,
      required String alertId,
      required String occurrenceKey,
      required int startUtcMs,
      required int atUtcMs,
      Value<int?> snoozeUntilUtcMs,
      Value<String?> title,
    });
typedef $$AlertHistoryTableUpdateCompanionBuilder =
    AlertHistoryCompanion Function({
      Value<int> id,
      Value<AlertEventType> type,
      Value<String> alertId,
      Value<String> occurrenceKey,
      Value<int> startUtcMs,
      Value<int> atUtcMs,
      Value<int?> snoozeUntilUtcMs,
      Value<String?> title,
    });

class $$AlertHistoryTableFilterComposer
    extends Composer<_$CacheDatabase, $AlertHistoryTable> {
  $$AlertHistoryTableFilterComposer({
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

  ColumnWithTypeConverterFilters<AlertEventType, AlertEventType, String>
  get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get alertId => $composableBuilder(
    column: $table.alertId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get occurrenceKey => $composableBuilder(
    column: $table.occurrenceKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startUtcMs => $composableBuilder(
    column: $table.startUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get atUtcMs => $composableBuilder(
    column: $table.atUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get snoozeUntilUtcMs => $composableBuilder(
    column: $table.snoozeUntilUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AlertHistoryTableOrderingComposer
    extends Composer<_$CacheDatabase, $AlertHistoryTable> {
  $$AlertHistoryTableOrderingComposer({
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

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get alertId => $composableBuilder(
    column: $table.alertId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get occurrenceKey => $composableBuilder(
    column: $table.occurrenceKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startUtcMs => $composableBuilder(
    column: $table.startUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get atUtcMs => $composableBuilder(
    column: $table.atUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get snoozeUntilUtcMs => $composableBuilder(
    column: $table.snoozeUntilUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AlertHistoryTableAnnotationComposer
    extends Composer<_$CacheDatabase, $AlertHistoryTable> {
  $$AlertHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<AlertEventType, String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get alertId =>
      $composableBuilder(column: $table.alertId, builder: (column) => column);

  GeneratedColumn<String> get occurrenceKey => $composableBuilder(
    column: $table.occurrenceKey,
    builder: (column) => column,
  );

  GeneratedColumn<int> get startUtcMs => $composableBuilder(
    column: $table.startUtcMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get atUtcMs =>
      $composableBuilder(column: $table.atUtcMs, builder: (column) => column);

  GeneratedColumn<int> get snoozeUntilUtcMs => $composableBuilder(
    column: $table.snoozeUntilUtcMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);
}

class $$AlertHistoryTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $AlertHistoryTable,
          AlertHistoryRow,
          $$AlertHistoryTableFilterComposer,
          $$AlertHistoryTableOrderingComposer,
          $$AlertHistoryTableAnnotationComposer,
          $$AlertHistoryTableCreateCompanionBuilder,
          $$AlertHistoryTableUpdateCompanionBuilder,
          (
            AlertHistoryRow,
            BaseReferences<
              _$CacheDatabase,
              $AlertHistoryTable,
              AlertHistoryRow
            >,
          ),
          AlertHistoryRow,
          PrefetchHooks Function()
        > {
  $$AlertHistoryTableTableManager(_$CacheDatabase db, $AlertHistoryTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AlertHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AlertHistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AlertHistoryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<AlertEventType> type = const Value.absent(),
                Value<String> alertId = const Value.absent(),
                Value<String> occurrenceKey = const Value.absent(),
                Value<int> startUtcMs = const Value.absent(),
                Value<int> atUtcMs = const Value.absent(),
                Value<int?> snoozeUntilUtcMs = const Value.absent(),
                Value<String?> title = const Value.absent(),
              }) => AlertHistoryCompanion(
                id: id,
                type: type,
                alertId: alertId,
                occurrenceKey: occurrenceKey,
                startUtcMs: startUtcMs,
                atUtcMs: atUtcMs,
                snoozeUntilUtcMs: snoozeUntilUtcMs,
                title: title,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required AlertEventType type,
                required String alertId,
                required String occurrenceKey,
                required int startUtcMs,
                required int atUtcMs,
                Value<int?> snoozeUntilUtcMs = const Value.absent(),
                Value<String?> title = const Value.absent(),
              }) => AlertHistoryCompanion.insert(
                id: id,
                type: type,
                alertId: alertId,
                occurrenceKey: occurrenceKey,
                startUtcMs: startUtcMs,
                atUtcMs: atUtcMs,
                snoozeUntilUtcMs: snoozeUntilUtcMs,
                title: title,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AlertHistoryTable, AlertHistoryRow>(table),
                  BaseReferences<
                    _$CacheDatabase,
                    $AlertHistoryTable,
                    AlertHistoryRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AlertHistoryTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $AlertHistoryTable,
      AlertHistoryRow,
      $$AlertHistoryTableFilterComposer,
      $$AlertHistoryTableOrderingComposer,
      $$AlertHistoryTableAnnotationComposer,
      $$AlertHistoryTableCreateCompanionBuilder,
      $$AlertHistoryTableUpdateCompanionBuilder,
      (
        AlertHistoryRow,
        BaseReferences<_$CacheDatabase, $AlertHistoryTable, AlertHistoryRow>,
      ),
      AlertHistoryRow,
      PrefetchHooks Function()
    >;
typedef $$SyncLogTableCreateCompanionBuilder = SyncLogCompanion Function({
  Value<int> id,
  Value<String?> sourceId,
  required int atUtcMs,
  required SyncOutcome outcome,
  Value<String?> message,
  Value<int?> occurrenceCount,
  Value<int?> durationMs,
});
typedef $$SyncLogTableUpdateCompanionBuilder = SyncLogCompanion Function({
  Value<int> id,
  Value<String?> sourceId,
  Value<int> atUtcMs,
  Value<SyncOutcome> outcome,
  Value<String?> message,
  Value<int?> occurrenceCount,
  Value<int?> durationMs,
});

class $$SyncLogTableFilterComposer
    extends Composer<_$CacheDatabase, $SyncLogTable> {
  $$SyncLogTableFilterComposer({
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

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get atUtcMs => $composableBuilder(
    column: $table.atUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<SyncOutcome, SyncOutcome, String>
  get outcome => $composableBuilder(
    column: $table.outcome,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get occurrenceCount => $composableBuilder(
    column: $table.occurrenceCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncLogTableOrderingComposer
    extends Composer<_$CacheDatabase, $SyncLogTable> {
  $$SyncLogTableOrderingComposer({
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

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get atUtcMs => $composableBuilder(
    column: $table.atUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get outcome => $composableBuilder(
    column: $table.outcome,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get occurrenceCount => $composableBuilder(
    column: $table.occurrenceCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncLogTableAnnotationComposer
    extends Composer<_$CacheDatabase, $SyncLogTable> {
  $$SyncLogTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<int> get atUtcMs =>
      $composableBuilder(column: $table.atUtcMs, builder: (column) => column);

  GeneratedColumnWithTypeConverter<SyncOutcome, String> get outcome =>
      $composableBuilder(column: $table.outcome, builder: (column) => column);

  GeneratedColumn<String> get message =>
      $composableBuilder(column: $table.message, builder: (column) => column);

  GeneratedColumn<int> get occurrenceCount => $composableBuilder(
    column: $table.occurrenceCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );
}

class $$SyncLogTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $SyncLogTable,
          SyncLogRow,
          $$SyncLogTableFilterComposer,
          $$SyncLogTableOrderingComposer,
          $$SyncLogTableAnnotationComposer,
          $$SyncLogTableCreateCompanionBuilder,
          $$SyncLogTableUpdateCompanionBuilder,
          (
            SyncLogRow,
            BaseReferences<_$CacheDatabase, $SyncLogTable, SyncLogRow>,
          ),
          SyncLogRow,
          PrefetchHooks Function()
        > {
  $$SyncLogTableTableManager(_$CacheDatabase db, $SyncLogTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncLogTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncLogTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncLogTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> sourceId = const Value.absent(),
                Value<int> atUtcMs = const Value.absent(),
                Value<SyncOutcome> outcome = const Value.absent(),
                Value<String?> message = const Value.absent(),
                Value<int?> occurrenceCount = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
              }) => SyncLogCompanion(
                id: id,
                sourceId: sourceId,
                atUtcMs: atUtcMs,
                outcome: outcome,
                message: message,
                occurrenceCount: occurrenceCount,
                durationMs: durationMs,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> sourceId = const Value.absent(),
                required int atUtcMs,
                required SyncOutcome outcome,
                Value<String?> message = const Value.absent(),
                Value<int?> occurrenceCount = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
              }) => SyncLogCompanion.insert(
                id: id,
                sourceId: sourceId,
                atUtcMs: atUtcMs,
                outcome: outcome,
                message: message,
                occurrenceCount: occurrenceCount,
                durationMs: durationMs,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncLogTable, SyncLogRow>(table),
                  BaseReferences<_$CacheDatabase, $SyncLogTable, SyncLogRow>(
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

typedef $$SyncLogTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $SyncLogTable,
      SyncLogRow,
      $$SyncLogTableFilterComposer,
      $$SyncLogTableOrderingComposer,
      $$SyncLogTableAnnotationComposer,
      $$SyncLogTableCreateCompanionBuilder,
      $$SyncLogTableUpdateCompanionBuilder,
      (SyncLogRow, BaseReferences<_$CacheDatabase, $SyncLogTable, SyncLogRow>),
      SyncLogRow,
      PrefetchHooks Function()
    >;
typedef $$CacheValuesTableCreateCompanionBuilder =
    CacheValuesCompanion Function({
      required String name,
      required String value,
      Value<int> rowid,
    });
typedef $$CacheValuesTableUpdateCompanionBuilder =
    CacheValuesCompanion Function({
      Value<String> name,
      Value<String> value,
      Value<int> rowid,
    });

class $$CacheValuesTableFilterComposer
    extends Composer<_$CacheDatabase, $CacheValuesTable> {
  $$CacheValuesTableFilterComposer({
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

class $$CacheValuesTableOrderingComposer
    extends Composer<_$CacheDatabase, $CacheValuesTable> {
  $$CacheValuesTableOrderingComposer({
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

class $$CacheValuesTableAnnotationComposer
    extends Composer<_$CacheDatabase, $CacheValuesTable> {
  $$CacheValuesTableAnnotationComposer({
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

class $$CacheValuesTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $CacheValuesTable,
          CacheValueRow,
          $$CacheValuesTableFilterComposer,
          $$CacheValuesTableOrderingComposer,
          $$CacheValuesTableAnnotationComposer,
          $$CacheValuesTableCreateCompanionBuilder,
          $$CacheValuesTableUpdateCompanionBuilder,
          (
            CacheValueRow,
            BaseReferences<_$CacheDatabase, $CacheValuesTable, CacheValueRow>,
          ),
          CacheValueRow,
          PrefetchHooks Function()
        > {
  $$CacheValuesTableTableManager(_$CacheDatabase db, $CacheValuesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CacheValuesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CacheValuesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CacheValuesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> name = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => CacheValuesCompanion(name: name, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String name,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => CacheValuesCompanion.insert(
                name: name,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CacheValuesTable, CacheValueRow>(table),
                  BaseReferences<
                    _$CacheDatabase,
                    $CacheValuesTable,
                    CacheValueRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CacheValuesTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $CacheValuesTable,
      CacheValueRow,
      $$CacheValuesTableFilterComposer,
      $$CacheValuesTableOrderingComposer,
      $$CacheValuesTableAnnotationComposer,
      $$CacheValuesTableCreateCompanionBuilder,
      $$CacheValuesTableUpdateCompanionBuilder,
      (
        CacheValueRow,
        BaseReferences<_$CacheDatabase, $CacheValuesTable, CacheValueRow>,
      ),
      CacheValueRow,
      PrefetchHooks Function()
    >;

class $CacheDatabaseManager {
  final _$CacheDatabase _db;
  $CacheDatabaseManager(this._db);
  $$OccurrencesTableTableManager get occurrences =>
      $$OccurrencesTableTableManager(_db, _db.occurrences);
  $$AlertHistoryTableTableManager get alertHistory =>
      $$AlertHistoryTableTableManager(_db, _db.alertHistory);
  $$SyncLogTableTableManager get syncLog =>
      $$SyncLogTableTableManager(_db, _db.syncLog);
  $$CacheValuesTableTableManager get cacheValues =>
      $$CacheValuesTableTableManager(_db, _db.cacheValues);
}
