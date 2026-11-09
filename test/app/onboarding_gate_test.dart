import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/app/onboarding_gate.dart';
import 'package:tminus/core/storage/app_settings.dart';

/// Only what the gate uses; the rest of AppSettings is never called.
class _FakeSettings implements AppSettings {
  _FakeSettings({
    this.stored = false,
    this.readFails = false,
    Stream<bool>? changes,
  }) : changes = changes ?? const Stream<bool>.empty();

  /// What the stored flag reads as.
  bool stored;

  /// When set, reading the flag throws. The message names a feed link on
  /// purpose: a failure must only ever be logged by its type.
  final bool readFails;

  /// What the database tells the gate about later changes.
  final Stream<bool> changes;

  @override
  Future<bool> onboardingDone() async {
    if (readFails) {
      throw StateError('no read for https://calendar.example/s3cr3t/feed.ics');
    }
    return stored;
  }

  @override
  Stream<bool> watchOnboardingDone() => changes;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  /// Captures what the code under test logs until the test ends.
  List<String> captureLog() {
    final logged = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) =>
        logged.add(message ?? '');
    addTearDown(() => debugPrint = original);
    return logged;
  }

  test('a gate that cannot read counts as done', () async {
    final logged = captureLog();
    final gate = OnboardingGate(_FakeSettings(readFails: true));
    addTearDown(gate.dispose);
    expect(gate.done, isFalse); // until it has loaded

    // It does not throw, and the user lands on the Agenda (which shows the
    // problem) instead of being trapped in onboarding.
    await gate.load();

    expect(gate.done, isTrue);
    // Only the type is logged, never the message with the link in it.
    expect(logged.join('\n'), contains('StateError'));
    expect(logged.join('\n'), isNot(contains('s3cr3t')));
  });

  test('the gate reads the stored flag, then follows the database', () async {
    final changes = StreamController<bool>();
    final gate = OnboardingGate(
      _FakeSettings(stored: true, changes: changes.stream),
    );
    addTearDown(gate.dispose);
    var told = 0;
    gate.addListener(() => told++);

    await gate.load();
    expect(gate.done, isTrue);
    expect(told, 0); // loading tells nobody: the router is not built yet

    // The database repeating what the gate knows is not a change.
    changes.add(true);
    await pumpEventQueue();
    expect(told, 0);

    changes.add(false);
    await pumpEventQueue();
    expect(gate.done, isFalse);
    expect(told, 1);

    changes.add(true);
    await pumpEventQueue();
    expect(gate.done, isTrue);
    expect(told, 2);
  });

  test('loading again reads the flag again but listens only once', () async {
    var listens = 0;
    final changes = StreamController<bool>(onListen: () => listens++);
    final settings = _FakeSettings(changes: changes.stream);
    final gate = OnboardingGate(settings);
    addTearDown(gate.dispose);

    await gate.load();
    expect(gate.done, isFalse);
    settings.stored = true;
    await gate.load();

    expect(gate.done, isTrue);
    expect(listens, 1);
  });

  test('a watch that fails is logged by its type and the gate keeps '
      'following', () async {
    final logged = captureLog();
    final changes = StreamController<bool>();
    final gate = OnboardingGate(_FakeSettings(changes: changes.stream));
    addTearDown(gate.dispose);
    await gate.load();

    changes.addError(
      StateError('no watch for https://calendar.example/s3cr3t/feed.ics'),
    );
    await pumpEventQueue();
    expect(logged.join('\n'), contains('StateError'));
    expect(logged.join('\n'), isNot(contains('s3cr3t')));
    expect(gate.done, isFalse);

    changes.add(true);
    await pumpEventQueue();
    expect(gate.done, isTrue);
  });

  test('a disposed gate stops listening to the database', () async {
    final changes = StreamController<bool>();
    final gate = OnboardingGate(_FakeSettings(changes: changes.stream));
    await gate.load();
    expect(changes.hasListener, isTrue);

    gate.dispose();
    await pumpEventQueue();

    expect(changes.hasListener, isFalse);
  });
}
