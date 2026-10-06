/// What to do with a source's new fetch result (spec §9: "Feed returns 0
/// events where it previously had some → remove alarms only after two
/// consecutive empty results").
enum EmptyFeedAction {
  /// Replace the cached occurrences with the new result.
  accept,

  /// Keep the cached occurrences; the empty result may be a glitch.
  keepPrevious,
}

class EmptyFeedVerdict {
  const EmptyFeedVerdict(this.action, this.consecutiveEmpty);

  final EmptyFeedAction action;

  /// The counter to store for the source until its next fetch.
  final int consecutiveEmpty;

  @override
  bool operator ==(Object other) =>
      other is EmptyFeedVerdict &&
      other.action == action &&
      other.consecutiveEmpty == consecutiveEmpty;

  @override
  int get hashCode => Object.hash(action, consecutiveEmpty);

  @override
  String toString() => 'EmptyFeedVerdict(${action.name}, $consecutiveEmpty)';
}

/// Pure decision. Plan 4 calls [EmptyFeedGuard.evaluate] per source after a
/// successful fetch and stores [EmptyFeedVerdict.consecutiveEmpty] in
/// `sources.empty_streak`.
abstract final class EmptyFeedGuard {
  /// Empty results in a row needed before cached occurrences are dropped.
  static const emptyResultsBeforeClearing = 2;

  /// [previousCount]: occurrences currently cached for the source.
  /// [newCount]: occurrences in the new result.
  /// [consecutiveEmpty]: the stored counter.
  static EmptyFeedVerdict evaluate({
    required int previousCount,
    required int newCount,
    required int consecutiveEmpty,
  }) {
    if (newCount > 0 || previousCount == 0) {
      return const EmptyFeedVerdict(EmptyFeedAction.accept, 0);
    }
    final streak = consecutiveEmpty + 1;
    if (streak >= emptyResultsBeforeClearing) {
      return const EmptyFeedVerdict(EmptyFeedAction.accept, 0);
    }
    return EmptyFeedVerdict(EmptyFeedAction.keepPrevious, streak);
  }
}
