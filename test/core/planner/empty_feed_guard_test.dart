import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/planner/empty_feed_guard.dart';

void main() {
  EmptyFeedVerdict eval(int previous, int next, int streak) =>
      EmptyFeedGuard.evaluate(
        previousCount: previous,
        newCount: next,
        consecutiveEmpty: streak,
      );

  const accept0 = EmptyFeedVerdict(EmptyFeedAction.accept, 0);

  test('non-empty result is accepted and resets the counter', () {
    expect(eval(5, 3, 0), accept0);
    expect(eval(5, 3, 1), accept0);
    expect(eval(0, 3, 0), accept0);
  });

  test('empty after empty cache is accepted (nothing to lose)', () {
    expect(eval(0, 0, 0), accept0);
  });

  test('first empty result after some keeps the old occurrences', () {
    expect(
      eval(5, 0, 0),
      const EmptyFeedVerdict(EmptyFeedAction.keepPrevious, 1),
    );
  });

  test('second consecutive empty result clears', () {
    expect(eval(5, 0, 1), accept0);
  });

  test('a non-empty result in between restarts the count', () {
    var v = eval(5, 0, 0); // keep, streak 1
    v = eval(5, 4, v.consecutiveEmpty); // accept, streak 0
    v = eval(4, 0, v.consecutiveEmpty); // keep again
    expect(v, const EmptyFeedVerdict(EmptyFeedAction.keepPrevious, 1));
  });
}
