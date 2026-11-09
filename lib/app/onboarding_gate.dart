import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/storage/app_settings.dart';

/// Whether onboarding is done, for the router's redirect. Loaded before
/// `runApp`, then kept current from the database.
class OnboardingGate extends ChangeNotifier {
  OnboardingGate(this._settings);

  final AppSettings _settings;
  StreamSubscription<bool>? _sub;
  bool _done = false;

  bool get done => _done;

  /// Never throws. A database that cannot be read counts as done, so the
  /// user lands on the Agenda (which shows the problem) rather than being
  /// trapped in onboarding.
  Future<void> load() async {
    try {
      _done = await _settings.onboardingDone();
    } catch (e) {
      debugPrint('Reading onboarding state failed: ${e.runtimeType}');
      _done = true;
    }
    _sub ??= _settings.watchOnboardingDone().listen(
      (v) {
        if (v == _done) return;
        _done = v;
        notifyListeners();
      },
      onError: (Object e) =>
          debugPrint('Watching onboarding state failed: ${e.runtimeType}'),
    );
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _sub = null;
    super.dispose();
  }
}
