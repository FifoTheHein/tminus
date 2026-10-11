import '../model/event_occurrence.dart';
import '../model/meeting_link.dart';
import '../model/meeting_occurrence.dart';
import '../model/source_config.dart';

/// What the merger knows about a source when it ranks that source's copies.
class SourceRank {
  const SourceRank({required this.kind, required this.failing});

  final SourceKind kind;

  /// The source's last fetch failed (`SourceSyncState.lastError != null`).
  /// Its copies rank after every healthy source's, so a phone calendar whose
  /// access was revoked cannot hold a frozen time over a fresh feed.
  final bool failing;
}

/// The meetings made from the enabled sources' copies, and the changes to
/// make to the stored links.
class MergeResult {
  const MergeResult({
    required this.meetings,
    required this.upsert,
    required this.delete,
    required this.timeSource,
  });

  /// Plain copies and [MeetingOccurrence]s, in key order. Every copy is in
  /// exactly one of them, and their keys are unique.
  final List<EventOccurrence> meetings;

  /// Links to write, in copy key order: one per copy of every meeting that
  /// has, or had, two or more copies.
  final List<MeetingLink> upsert;

  /// Copy keys whose stored links are dropped, in key order. A key that is
  /// upserted is never in here.
  final Set<String> delete;

  /// Meeting key → the source id of the copy that decides its time. Every
  /// meeting has an entry, plain copies included.
  final Map<String, String> timeSource;

  /// The number of meetings with two or more copies.
  int get merged => meetings
      .where((m) => m is MeetingOccurrence && m.copies.length >= 2)
      .length;
}

/// Turns the copies of the enabled sources, and the stored links, into
/// meetings (spec §13).
///
/// Pure: no I/O and no clock. The result is the same for the same copies and
/// links in any order, because the copies are put in rank order and then key
/// order before anything else is decided, and every choice after that is made
/// with a total order.
abstract final class MeetingMerger {
  /// Merges [copies] (enabled sources only). [links] are the stored
  /// `meeting_links`; [sources] says how to rank each source's copies.
  ///
  /// 1. With [enabled] false the copies are returned as they are.
  /// 2. Seed meetings from the links. A copy belongs to the meeting its own
  ///    link names, else the meeting whose key is the copy's own key, else, for
  ///    a one-off, the meeting its (source, uid) was linked to. A meeting keeps
  ///    one copy per source; the others are turned away.
  /// 3. Match the copies still on their own, in rank order, to a meeting or to
  ///    each other by iCal UID and original start, or by [fingerprint]. Only
  ///    copies of different sources merge, a value shared by two copies of one
  ///    source is not used, and a copy that fits more than one meeting joins
  ///    none.
  /// 4. Rank each meeting's copies, take its key (a seeded meeting keeps the
  ///    key it had, a new one takes its top-ranked copy's key) and fill its
  ///    fields as the spec's table says.
  /// 5. Write a link for every copy of a meeting that has, or had, two or more
  ///    copies.
  ///
  /// A copy on its own with no stored link comes back as the plain copy
  /// itself, and keeps its own key. So does a copy that holds its meeting's
  /// key. A single copy kept under a key that is not its own comes back as a
  /// [MeetingOccurrence], so that it plans under the meeting key.
  ///
  /// Where the spec leaves a choice open:
  /// - With [enabled] false the copies come back in key order, once each.
  /// - A source missing from [sources] ranks after every listed source.
  /// - A copy repeated under one key (the cache cannot hold that) is kept
  ///   once, so that meeting keys stay unique for any input.
  /// - A copy turned away from a meeting goes on to the next meeting that the
  ///   links allow it, and is matched like an unlinked copy only when there is
  ///   none. Its link to the meeting that turned it away is dropped.
  /// - A copy that fits more than one meeting stays alone, and later copies
  ///   cannot join it either.
  /// - A value counts as shared when any two copies of one source have it, even
  ///   if one of them is already linked.
  /// - A link is written for a linked meeting's copies on every run, so that
  ///   their end times stay current. A link is dropped only when its copy is
  ///   present and no longer belongs to a meeting that has a link.
  static MergeResult merge({
    required List<EventOccurrence> copies,
    required List<MeetingLink> links,
    required Map<String, SourceRank> sources,
    bool enabled = true,
  }) {
    final ordered = _inRankOrder(copies, sources);
    if (!enabled) {
      final byKey = [...ordered]..sort((a, b) => a.key.compareTo(b.key));
      return MergeResult(
        meetings: [for (final c in byKey) c.copy],
        upsert: const [],
        delete: const {},
        timeSource: {for (final c in byKey) c.key: c.sourceId},
      );
    }
    return _Merge(ordered, links).run();
  }

  /// Equal for copies that are probably the same meeting: the original start,
  /// the all-day flag and the normalised title. The title is trimmed, loses a
  /// leading `Canceled:` or `Cancelled:` (any case), has its whitespace
  /// collapsed and is lower-cased. Null for an untitled copy (empty or
  /// `(No title)`), which never matches on its title.
  ///
  /// The original start is used, not the current one, so that a moved instance
  /// of a series still matches while the published feed lags behind the phone.
  /// The title comes last in the string, so no title can run into the fields
  /// before it.
  static String? fingerprint(EventOccurrence c) {
    final title = _normalisedTitle(c.title);
    if (title.isEmpty || title == _noTitle) return null;
    return '${c.originalStartUtc.toIso8601String()}|${c.allDay}|$title';
  }
}

final _canceledPrefix = RegExp(r'^cancell?ed:', caseSensitive: false);
final _whitespace = RegExp(r'\s+');

/// What a phone copy without a title is called, in lower case.
const _noTitle = '(no title)';

/// [title] trimmed, without a leading `Canceled:` or `Cancelled:` (any case),
/// with every run of whitespace made one space, and lower-cased.
String _normalisedTitle(String title) {
  final trimmed = title.trim();
  final withoutCancelled = trimmed.replaceFirst(_canceledPrefix, '');
  final collapsed = withoutCancelled.replaceAll(_whitespace, ' ').trim();
  return collapsed.toLowerCase();
}

/// Stands in for a source that has no rank: after every listed source.
const _unranked = SourceRank(kind: SourceKind.debug, failing: true);

/// Phone calendars are fresher than published feeds, which lag (spec §13).
int _kindOrder(SourceKind kind) => switch (kind) {
  SourceKind.device => 0,
  SourceKind.ics => 1,
  SourceKind.debug => 2,
};

/// The strong key: the iCal UID with the original start. Null when the copy
/// has no UID, or an empty one, which would match every other empty one.
String? _strongKey(EventOccurrence c) {
  final uid = c.icalUid;
  if (uid == null || uid.isEmpty) return null;
  return '$uid|${c.originalStartUtc.millisecondsSinceEpoch}';
}

/// One copy, with what the algorithm works out about it once.
class _Copy {
  _Copy(this.copy, this.rank) : key = copy.key;

  final EventOccurrence copy;
  final String key;
  final SourceRank rank;

  String get sourceId => copy.sourceId;

  /// What can tell this copy's meeting from another. Each is null when the copy
  /// has none, and when another copy of its source has the same value, because
  /// then the value cannot tell those two copies apart.
  String? strongKey;
  String? fingerprint;

  /// The meetings the stored links put this copy in, best first, and how many
  /// of them have turned it away.
  final options = <String>[];
  var turnedAway = 0;

  /// True while a meeting from the links still has a place for this copy.
  bool get seeded => turnedAway < options.length;
}

/// A meeting being built.
class _Group {
  _Group(this.meetingKey);

  /// The sticky key of a meeting the links gave. Null for a new one, which
  /// takes its top-ranked copy's key.
  final String? meetingKey;
  final members = <_Copy>[];

  /// The members the links placed here. The others were matched this run.
  final placed = <_Copy>{};
  final _sourceIds = <String>{};

  bool hasSource(String sourceId) => _sourceIds.contains(sourceId);

  void add(_Copy c, {bool byLink = false}) {
    members.add(c);
    _sourceIds.add(c.sourceId);
    if (byLink) placed.add(c);
  }
}

/// Rank order (spec §13): healthy before failing, then phone before feed
/// before debug, then the copy that holds [meetingKey], then source id, then
/// key.
int _compareRanked(_Copy a, _Copy b, String? meetingKey) {
  if (a.rank.failing != b.rank.failing) return a.rank.failing ? 1 : -1;
  final byKind = _kindOrder(a.rank.kind).compareTo(_kindOrder(b.rank.kind));
  if (byKind != 0) return byKind;
  final aHolds = a.key == meetingKey;
  final bHolds = b.key == meetingKey;
  if (aHolds != bHolds) return aHolds ? -1 : 1;
  final bySource = a.sourceId.compareTo(b.sourceId);
  if (bySource != 0) return bySource;
  return a.key.compareTo(b.key);
}

/// The order the copies are worked in. Twins (one key twice) are put in order
/// by their content, so that the one kept does not depend on the input order.
int _compareArrival(_Copy a, _Copy b) {
  final byRank = _compareRanked(a, b, null);
  if (byRank != 0) return byRank;
  final byStart = a.copy.startUtc.compareTo(b.copy.startUtc);
  if (byStart != 0) return byStart;
  final byEnd = a.copy.endUtc.compareTo(b.copy.endUtc);
  if (byEnd != 0) return byEnd;
  return a.copy.title.compareTo(b.copy.title);
}

List<_Copy> _inRankOrder(
  List<EventOccurrence> copies,
  Map<String, SourceRank> sources,
) {
  final sorted = [
    for (final c in copies) _Copy(c, sources[c.sourceId] ?? _unranked),
  ]..sort(_compareArrival);
  final seen = <String>{};
  return [
    for (final c in sorted)
      if (seen.add(c.key)) c,
  ];
}

/// The links in the order that decides between several for one copy or one
/// one-off: the earliest end, then the lowest meeting key.
int _compareLinks(MeetingLink a, MeetingLink b) {
  final byEnd = a.endUtc.compareTo(b.endUtc);
  if (byEnd != 0) return byEnd;
  return a.meetingKey.compareTo(b.meetingKey);
}

/// A meeting ready to hand back, with the source that decides its time.
typedef _Emitted = ({String key, EventOccurrence meeting, String timeSource});

/// One merge of copies that are already in rank order, one per key.
class _Merge {
  _Merge(this._copies, List<MeetingLink> links) {
    final sorted = [...links]..sort(_compareLinks);
    for (final l in sorted) {
      _linkOf.putIfAbsent(l.copyKey, () => l);
      _meetingKeys.add(l.meetingKey);
      if (l.oneOff) _oneOffLinkOf.putIfAbsent((l.sourceId, l.uid), () => l);
    }
    for (final c in _copies) {
      c.strongKey = _strongKey(c.copy);
      c.fingerprint = MeetingMerger.fingerprint(c.copy);
    }
    final sharedStrong = _sharedBySource((c) => c.strongKey);
    final sharedFingerprint = _sharedBySource((c) => c.fingerprint);
    for (final c in _copies) {
      final strong = c.strongKey;
      if (strong != null && sharedStrong.contains((c.sourceId, strong))) {
        c.strongKey = null;
      }
      final fingerprint = c.fingerprint;
      if (fingerprint != null &&
          sharedFingerprint.contains((c.sourceId, fingerprint))) {
        c.fingerprint = null;
      }
    }
  }

  final List<_Copy> _copies;

  /// The link of each copy key; the stored links have one row per copy.
  final _linkOf = <String, MeetingLink>{};

  /// Every meeting key a link names.
  final _meetingKeys = <String>{};

  /// The one-off link of each (source id, uid) that decides which meeting a
  /// moved one-off belongs to.
  final _oneOffLinkOf = <(String, String), MeetingLink>{};

  MergeResult run() {
    final groups = _seed();
    _match(groups);
    return _emit(groups);
  }

  /// The (source id, value) pairs that two copies of one source have in
  /// common.
  Set<(String, String)> _sharedBySource(String? Function(_Copy) valueOf) {
    final seen = <(String, String)>{};
    final shared = <(String, String)>{};
    for (final c in _copies) {
      final value = valueOf(c);
      if (value != null && !seen.add((c.sourceId, value))) {
        shared.add((c.sourceId, value));
      }
    }
    return shared;
  }

  /// Puts each copy in the meeting its links name. A meeting keeps one copy
  /// per source: the one whose key is the meeting key, then the one with a
  /// link to the meeting, then the lowest key. The others go on to the next
  /// meeting they could belong to, and are matched like unlinked copies if
  /// there is none.
  List<_Group> _seed() {
    for (final c in _copies) {
      void offer(String? meetingKey) {
        if (meetingKey != null && !c.options.contains(meetingKey)) {
          c.options.add(meetingKey);
        }
      }

      offer(_linkOf[c.key]?.meetingKey);
      if (_meetingKeys.contains(c.key)) offer(c.key);
      if (c.copy.seriesUid == null) {
        offer(_oneOffLinkOf[(c.sourceId, c.copy.uid)]?.meetingKey);
      }
    }

    while (true) {
      final byMeeting = <String, List<_Copy>>{};
      for (final c in _copies) {
        if (c.seeded) (byMeeting[c.options[c.turnedAway]] ??= []).add(c);
      }
      var turnedAnyAway = false;
      for (final entry in byMeeting.entries) {
        final bySource = <String, List<_Copy>>{};
        for (final c in entry.value) {
          (bySource[c.sourceId] ??= []).add(c);
        }
        for (final sameSource in bySource.values) {
          if (sameSource.length < 2) continue;
          sameSource.sort((a, b) => _compareToKeep(a, b, entry.key));
          for (final loser in sameSource.skip(1)) {
            loser.turnedAway++;
            turnedAnyAway = true;
          }
        }
      }
      if (turnedAnyAway) continue;

      final groups = <_Group>[];
      for (final entry in byMeeting.entries) {
        final group = _Group(entry.key);
        for (final c in entry.value) {
          group.add(c, byLink: true);
        }
        groups.add(group);
      }
      return groups;
    }
  }

  /// The order that decides which of two copies of one source stays in the
  /// meeting [meetingKey]: the one whose key it is, then the one with a link
  /// to it, then the lowest key.
  int _compareToKeep(_Copy x, _Copy y, String meetingKey) {
    final xIsKey = x.key == meetingKey;
    final yIsKey = y.key == meetingKey;
    if (xIsKey != yIsKey) return xIsKey ? -1 : 1;
    final xLinked = _linkOf[x.key]?.meetingKey == meetingKey;
    final yLinked = _linkOf[y.key]?.meetingKey == meetingKey;
    if (xLinked != yLinked) return xLinked ? -1 : 1;
    return x.key.compareTo(y.key);
  }

  /// Matches the copies no link placed, in rank order. Each joins the one
  /// meeting that has no copy from its source and has a copy with the same
  /// strong key or fingerprint, else it starts a new meeting. A copy that fits
  /// more than one meeting stays alone.
  void _match(List<_Group> groups) {
    final byStrongKey = <String, Set<_Group>>{};
    final byFingerprint = <String, Set<_Group>>{};

    void index(_Group g, _Copy c) {
      final strong = c.strongKey;
      if (strong != null) (byStrongKey[strong] ??= {}).add(g);
      final fingerprint = c.fingerprint;
      if (fingerprint != null) (byFingerprint[fingerprint] ??= {}).add(g);
    }

    for (final g in groups) {
      for (final c in g.members) {
        index(g, c);
      }
    }

    for (final c in _copies) {
      if (c.seeded) continue;
      final found = <_Group>{};
      final strong = c.strongKey;
      if (strong != null) {
        found.addAll(byStrongKey[strong] ?? const <_Group>{});
      }
      final fingerprint = c.fingerprint;
      if (fingerprint != null) {
        found.addAll(byFingerprint[fingerprint] ?? const <_Group>{});
      }
      found.removeWhere((g) => g.hasSource(c.sourceId));

      if (found.length == 1) {
        final joined = found.single;
        joined.add(c);
        index(joined, c);
      } else {
        final g = _Group(null)..add(c);
        groups.add(g);
        if (found.isEmpty) index(g, c);
      }
    }
  }

  MergeResult _emit(List<_Group> groups) {
    final emitted = <_Emitted>[];
    final upsert = <MeetingLink>[];
    final linked = <String>{};

    for (final g in groups) {
      final ranked = [...g.members]
        ..sort((a, b) => _compareRanked(a, b, g.meetingKey));
      final top = ranked.first;
      final key = g.meetingKey ?? top.key;
      emitted.add((
        key: key,
        meeting: (ranked.length == 1 && top.key == key)
            ? top.copy
            : _meetingOf(key, ranked),
        timeSource: top.sourceId,
      ));

      // Links are only kept for meetings that have, or had, two or more
      // copies: a lone copy with no stored link gets none.
      if (g.meetingKey == null && ranked.length < 2) continue;
      for (final c in ranked) {
        linked.add(c.key);
        upsert.add(
          MeetingLink(
            copyKey: c.key,
            meetingKey: key,
            sourceId: c.sourceId,
            uid: c.copy.uid,
            oneOff: c.copy.seriesUid == null,
            endUtc: c.copy.endUtc,
            matchedBy: _matchedBy(c, g),
          ),
        );
      }
    }

    emitted.sort((a, b) => a.key.compareTo(b.key));
    upsert.sort((a, b) => a.copyKey.compareTo(b.copyKey));
    final delete = [
      for (final c in _copies)
        if (_linkOf.containsKey(c.key) && !linked.contains(c.key)) c.key,
    ]..sort();
    return MergeResult(
      meetings: [for (final e in emitted) e.meeting],
      upsert: upsert,
      delete: {...delete},
      timeSource: {for (final e in emitted) e.key: e.timeSource},
    );
  }

  /// How [c] came to be in [g]: remembered if a link placed it there, else the
  /// UID if another member has its strong key, else the fingerprint.
  MeetingMatch _matchedBy(_Copy c, _Group g) {
    if (g.placed.contains(c)) return MeetingMatch.remembered;
    final strong = c.strongKey;
    if (strong != null &&
        g.members.any((o) => !identical(o, c) && o.strongKey == strong)) {
      return MeetingMatch.uid;
    }
    return MeetingMatch.fingerprint;
  }

  /// The merged fields of [ranked] (best first), planned under [key].
  MeetingOccurrence _meetingOf(String key, List<_Copy> ranked) {
    final top = ranked.first.copy;

    String? firstOf(String? Function(EventOccurrence) field) {
      for (final c in ranked) {
        final value = field(c.copy);
        if (value != null) return value;
      }
      return null;
    }

    return MeetingOccurrence(
      sourceId: top.sourceId,
      uid: top.uid,
      originalStartUtc: top.originalStartUtc,
      seriesUid: top.seriesUid,
      icalUid: top.icalUid,
      title: top.title,
      location: firstOf((c) => c.location),
      organizer: firstOf((c) => c.organizer),
      description: firstOf((c) => c.description),
      joinUrl: firstOf((c) => c.joinUrl),
      startUtc: top.startUtc,
      endUtc: top.endUtc,
      allDay: top.allDay,
      busyStatus: ranked
          .map((c) => c.copy.busyStatus)
          .firstWhere(
            (status) => status != BusyStatus.unknown,
            orElse: () => BusyStatus.unknown,
          ),
      declined: ranked.any((c) => c.copy.declined),
      cancelled: ranked.any((c) => c.copy.cancelled),
      calendarColor: top.calendarColor,
      warnings: top.warnings,
      meetingKey: key,
      copies: [for (final c in ranked) c.copy],
      timeSourceId: top.sourceId,
    );
  }
}
