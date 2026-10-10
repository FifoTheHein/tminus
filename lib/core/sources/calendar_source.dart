import '../model/event_occurrence.dart';
import '../model/sync_log_entry.dart';
import '../model/utc.dart';

/// The span a sync fetches: now − 1 h to now + 7 days (spec §5).
class FetchWindow {
  FetchWindow(DateTime startUtc, DateTime endUtc)
    : startUtc = plainUtc(startUtc),
      endUtc = plainUtc(endUtc);

  /// The spec §5 window around [now].
  factory FetchWindow.around(DateTime now) =>
      FetchWindow(now.subtract(lookBehind), now.add(lookAhead));

  static const lookBehind = Duration(hours: 1);
  static const lookAhead = Duration(days: 7);

  final DateTime startUtc;
  final DateTime endUtc;

  @override
  bool operator ==(Object other) =>
      other is FetchWindow &&
      other.startUtc == startUtc &&
      other.endUtc == endUtc;

  @override
  int get hashCode => Object.hash(startUtc, endUtc);

  @override
  String toString() => 'FetchWindow($startUtc – $endUtc)';
}

/// One configured calendar, ready to fetch (spec §5). Implementations never
/// throw: every failure comes back as a [SourceFailed].
abstract interface class CalendarSource {
  String get id;
  Future<SourceResult> fetch(FetchWindow window);
}

sealed class SourceResult {
  const SourceResult();
}

/// The source answered with its current events.
class SourceFetched extends SourceResult {
  const SourceFetched(
    this.occurrences, {
    this.issues = const [],
    this.notModified = false,
    this.httpEtag,
    this.httpLastModified,
  });

  /// Occurrences overlapping the window, all with this source's id.
  final List<EventOccurrence> occurrences;

  /// Events that were skipped or looked odd; never contains a URL.
  final List<String> issues;

  /// The feed answered 304 and its stored copy was expanded again.
  final bool notModified;

  /// Conditional-GET validators to keep for the next fetch (ICS only).
  final String? httpEtag;
  final String? httpLastModified;
}

/// The source could not be read. The cached occurrences stay as they are.
class SourceFailed extends SourceResult {
  const SourceFailed(this.outcome, this.message)
    : assert(outcome != SyncOutcome.success);

  final SyncOutcome outcome;

  /// Shown in Sources and Health. Never contains an ICS URL (spec §10).
  final String message;
}
