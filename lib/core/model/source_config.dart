import 'utc.dart';

/// Stored by name, so appending is safe; never rename one.
enum SourceKind {
  ics,
  device,

  /// Debug builds only: the "fast alarms" source (spec §11, Plan 4).
  debug,
}

/// A configured calendar source as stored in drift.
///
/// Never holds an ICS URL: a published ICS link works like a password
/// (spec §3, §10). The URL lives in flutter_secure_storage (Plan 4) under
/// [secureStorageKey]; this record only keeps that key.
class SourceConfig {
  const SourceConfig({
    required this.id,
    required this.name,
    required this.color,
    required this.kind,
    this.deviceCalendarId,
    this.secureStorageKey,
    this.defaultProfileId,
    this.enabled = true,
  });

  final String id;
  final String name;

  /// ARGB, e.g. 0xFF6AA0F5.
  final int color;
  final SourceKind kind;

  /// Android calendar id; set only for [SourceKind.device].
  final String? deviceCalendarId;

  /// Key of the ICS URL in secure storage; set only for [SourceKind.ics].
  final String? secureStorageKey;

  /// Resolution step 5 (spec §6); null = use the global default.
  final String? defaultProfileId;
  final bool enabled;

  SourceConfig copyWith({
    String? name,
    int? color,
    String? deviceCalendarId,
    String? secureStorageKey,
    String? defaultProfileId,
    bool clearDefaultProfile = false,
    bool? enabled,
  }) => SourceConfig(
    id: id,
    name: name ?? this.name,
    color: color ?? this.color,
    kind: kind,
    deviceCalendarId: deviceCalendarId ?? this.deviceCalendarId,
    secureStorageKey: secureStorageKey ?? this.secureStorageKey,
    defaultProfileId: clearDefaultProfile
        ? null
        : (defaultProfileId ?? this.defaultProfileId),
    enabled: enabled ?? this.enabled,
  );

  @override
  bool operator ==(Object other) =>
      other is SourceConfig &&
      other.id == id &&
      other.name == name &&
      other.color == color &&
      other.kind == kind &&
      other.deviceCalendarId == deviceCalendarId &&
      other.secureStorageKey == secureStorageKey &&
      other.defaultProfileId == defaultProfileId &&
      other.enabled == enabled;

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
  );

  @override
  String toString() => 'SourceConfig($id, $name, ${kind.name})';
}

/// Per-source sync bookkeeping, kept next to [SourceConfig] in the same row.
/// Plan 4 writes it; Plan 5 shows it ("Synced 4 min ago", red/amber state).
/// Instants are normalised with [plainUtc] like every other model class
/// (decision 25), so the constructor isn't const.
class SourceSyncState {
  SourceSyncState({
    DateTime? lastAttemptUtc,
    DateTime? lastSuccessUtc,
    this.lastError,
    this.httpEtag,
    this.httpLastModified,
    this.emptyStreak = 0,
  }) : lastAttemptUtc = lastAttemptUtc == null
           ? null
           : plainUtc(lastAttemptUtc),
       lastSuccessUtc = lastSuccessUtc == null
           ? null
           : plainUtc(lastSuccessUtc);

  final DateTime? lastAttemptUtc;
  final DateTime? lastSuccessUtc;

  /// Human-readable, never contains the URL. Null after a success.
  final String? lastError;

  /// Conditional-GET validators from the last 200 response (spec §5).
  final String? httpEtag;
  final String? httpLastModified;

  /// Consecutive empty results while the cache still had occurrences;
  /// input to `EmptyFeedGuard.evaluate` (spec §9).
  final int emptyStreak;

  @override
  bool operator ==(Object other) =>
      other is SourceSyncState &&
      other.lastAttemptUtc == lastAttemptUtc &&
      other.lastSuccessUtc == lastSuccessUtc &&
      other.lastError == lastError &&
      other.httpEtag == httpEtag &&
      other.httpLastModified == httpLastModified &&
      other.emptyStreak == emptyStreak;

  @override
  int get hashCode => Object.hash(
    lastAttemptUtc,
    lastSuccessUtc,
    lastError,
    httpEtag,
    httpLastModified,
    emptyStreak,
  );
}
