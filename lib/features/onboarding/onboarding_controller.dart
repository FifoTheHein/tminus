import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;

import '../../app/health_monitor.dart';
import '../../app/onboarding_gate.dart';
import '../../core/engine/alarm_engine.dart';
import '../../core/model/alert.dart';
import '../../core/model/source_config.dart';
import '../../core/platform/ui_platform.dart';
import '../../core/sources/device_calendar_api.dart';
import '../../core/storage/app_settings.dart';
import '../../core/storage/source_repository.dart';
import '../agenda/agenda_model.dart';
import '../health/health_report.dart';

/// The five steps, in the order the user sees them.
enum OnboardingStep { welcome, calendar, permissions, testAlarm, done }

/// Where the test alarm is on its step.
enum TestAlarmPhase {
  /// Nothing has been asked of the engine yet.
  idle,

  /// The engine is being asked.
  starting,

  /// The engine has the alarm; it rings when the countdown ends.
  counting,

  /// The countdown is over: the user says whether it rang.
  asking,
}

/// What the Calendar access row offers.
enum CalendarAccess {
  /// The phone's calendars can be read: a tick.
  allowed,

  /// **Allow** asks for the permission.
  ask,

  /// Android will not ask again: **Open settings**.
  openSettings,
}

/// What a failure is logged as: a platform error's code, anything else by its
/// type. Never the message, which can carry a feed link or a row's values.
String _kind(Object error) =>
    error is PlatformException ? error.code : '${error.runtimeType}';

/// What the onboarding screen shows and does. It owns the step the user is on,
/// follows the sources and the Health report, and runs the permission requests,
/// the test alarm and the finish. The screen builds one from `getIt`; a test
/// builds one on the same services.
///
/// It never holds a calendar link: the add-calendar panel does that work and
/// hands back only the source it added.
class OnboardingController extends ChangeNotifier {
  OnboardingController({
    required this.sources,
    required this.appSettings,
    required this.engine,
    required this.ui,
    required this.calendars,
    required this.monitor,
    required this.loader,
    required this.gate,
  });

  /// How long after the request the test alarm rings.
  static const testDelay = Duration(seconds: 5);

  /// The first Android that has the notification permission to ask for. Below
  /// it a refusal means the switch in the app's notification settings is off.
  static const _runtimeNotificationSdk = 33;

  final SourceRepository sources;
  final AppSettings appSettings;
  final AlarmEngine engine;
  final UiPlatform ui;
  final DeviceCalendarApi calendars;
  final HealthMonitor monitor;
  final AgendaLoader loader;
  final OnboardingGate gate;

  OnboardingStep _step = OnboardingStep.welcome;
  List<SourceConfig> _sources = const [];
  bool _restorePending = false;
  bool _calendarAllowed = false;
  bool _calendarBlocked = false;
  TestAlarmPhase _phase = TestAlarmPhase.idle;
  int _secondsLeft = testDelay.inSeconds;
  int? _alarmed;
  bool _finishing = false;
  bool _disposed = false;
  int _summaryLoads = 0;
  StreamSubscription<List<SourceConfig>>? _sourceUpdates;
  StreamSubscription<bool>? _restoreUpdates;
  AppLifecycleListener? _lifecycle;
  Timer? _countdown;

  OnboardingStep get step => _step;

  /// The step as the progress strip counts it: 1 to [stepCount].
  int get stepNumber => _step.index + 1;

  static int get stepCount => OnboardingStep.values.length;

  /// How many sources exist, switched on or not.
  int get sourceCount => _sources.length;

  /// Any source exists: the Add your calendar step can be continued.
  bool get hasSource => _sources.isNotEmpty;

  /// A phone calendar is a source: the Calendar access row is shown.
  bool get hasDeviceSource => _sources.any((s) => s.kind == SourceKind.device);

  /// The app was restored from a backup, which left its calendars here waiting
  /// to be re-linked. With no calendars to speak of the step is the ordinary
  /// one.
  bool get restored => _restorePending && _sources.isNotEmpty;

  /// Add your calendar waits for a source (or a restored backup that holds
  /// some); every other step can be continued at any time.
  bool get canContinue => _step != OnboardingStep.calendar || hasSource;

  /// Back goes to the step before. Not from the first step or the last one, and
  /// not while a test alarm is on its way: leaving then would lose the answer.
  bool get canGoBack =>
      _step.index > 0 &&
      _step != OnboardingStep.done &&
      (_step != OnboardingStep.testAlarm || _phase == TestAlarmPhase.idle);

  /// The system Back button closes the app from the first step, and only
  /// there. On every other step it does what the on-screen Back does
  /// ([canGoBack]): one step back, or nothing where there is no Back, which is
  /// while the test alarm is asked for, counting down or waiting for its
  /// answer, and on the last step. Closing the app there would throw the setup
  /// away just as it is complete, so Done stays until **Go to Agenda**.
  bool get backLeavesApp => _step == OnboardingStep.welcome;

  /// The app-wide Health report (null until the first one has been made).
  HealthReport? get report => monitor.report;

  /// Notifications are off, as the report says. Not said while it is unknown.
  bool get notificationsOff => _allowed('notifications') == false;

  bool get notificationsAllowed => _allowed('notifications') == true;

  /// Full-screen alarms are offered only while they are not allowed.
  bool get showFullScreen => _allowed('fullScreen') == false;

  bool get batteryAllowed => _allowed('battery') == true;

  CalendarAccess get calendarAccess => _calendarAllowed
      ? CalendarAccess.allowed
      : _calendarBlocked
      ? CalendarAccess.openSettings
      : CalendarAccess.ask;

  TestAlarmPhase get testPhase => _phase;

  /// The countdown of the test alarm, in whole seconds: the whole delay until
  /// the alarm has been asked for, and 0 once the countdown is over.
  int get secondsLeft => _secondsLeft;

  /// How many of the next 7 days' meetings have alarms; null until counted.
  int? get alarmedMeetings => _alarmed;

  /// The finish is being written; its buttons are off.
  bool get finishing => _finishing;

  /// Follows the sources and the restore marker, and reads the permissions
  /// again whenever the app comes back to the front.
  void start() {
    if (_disposed || _lifecycle != null) return;
    _sourceUpdates = sources.watchAll().listen(
      (all) {
        _sources = all;
        _notify();
      },
      onError: (Object e) =>
          debugPrint('Watching the sources failed (${_kind(e)})'),
    );
    _restoreUpdates = appSettings.watchRestorePending().listen(
      (pending) {
        _restorePending = pending;
        _notify();
      },
      onError: (Object e) =>
          debugPrint('Watching the restore marker failed (${_kind(e)})'),
    );
    monitor.addListener(_notify);
    _lifecycle = AppLifecycleListener(onResume: _onResume);
  }

  /// Moves on if the step allows it (the buttons are off otherwise).
  void next() {
    if (canContinue) _go(_step.index + 1);
  }

  /// **Skip for now**: moves on whatever the step is waiting for.
  void skip() => _go(_step.index + 1);

  void back() {
    if (canGoBack) _go(_step.index - 1);
  }

  void _go(int index) {
    if (index < 0 || index >= OnboardingStep.values.length) return;
    final to = OnboardingStep.values[index];
    if (to == _step) return;
    if (_step == OnboardingStep.testAlarm) {
      // Leaving the test: its countdown goes, and the step starts afresh.
      _countdown?.cancel();
      _countdown = null;
      _phase = TestAlarmPhase.idle;
      _secondsLeft = testDelay.inSeconds;
    }
    _step = to;
    switch (to) {
      case OnboardingStep.permissions:
        unawaited(refreshPermissions());
      case OnboardingStep.done:
        unawaited(_loadSummary());
      case OnboardingStep.welcome ||
          OnboardingStep.calendar ||
          OnboardingStep.testAlarm:
        break;
    }
    _notify();
  }

  void _onResume() {
    // The settings screens the rows open are other activities: what the user
    // changed there shows when the app comes back.
    if (_step == OnboardingStep.permissions) unawaited(refreshPermissions());
  }

  /// Reads the Health report again, and the phone-calendar access when a phone
  /// calendar is a source. Never throws.
  Future<void> refreshPermissions() async {
    await monitor.refresh();
    if (hasDeviceSource) await _probeCalendar();
  }

  /// Whether the phone's calendars can be read, without asking: the list is
  /// refused while the permission is missing. Only a refusal for that reason
  /// means "not allowed".
  Future<void> _probeCalendar() async {
    try {
      await calendars.calendars();
      _calendarAllowed = true;
      _calendarBlocked = false;
    } on PlatformException catch (e) {
      if (e.code == DeviceCalendarApi.permissionDenied) {
        _calendarAllowed = false;
      } else {
        debugPrint('Reading the phone calendars failed (${e.code})');
      }
    } on MissingPluginException {
      // No native side (tests, desktop): the row keeps what it knows.
    } catch (e) {
      debugPrint('Reading the phone calendars failed (${e.runtimeType})');
    }
    _notify();
  }

  /// **Allow** on Notifications: the runtime permission. A refusal that Android
  /// will not ask again about, and a refusal below Android 13 (where the
  /// permission is only a switch), send the user to the app's notification
  /// settings. Throws on a platform failure; the screen says so in fixed text.
  Future<void> allowNotifications() async {
    final result = await ui.requestPermission(UiPermission.notifications);
    final toSettings = switch (result) {
      PermissionResult.granted => false,
      PermissionResult.permanentlyDenied => true,
      PermissionResult.denied =>
        (await ui.deviceInfo()).sdkInt < _runtimeNotificationSdk,
    };
    if (toSettings) {
      await engine.openPermissionSettings(PermissionKind.notifications);
    }
    await monitor.refresh();
  }

  /// **Allow** on Full-screen alarms and Battery: a system settings screen.
  Future<void> openSettingsFor(PermissionKind kind) async {
    await engine.openPermissionSettings(kind);
    await monitor.refresh();
  }

  /// The Calendar access row's button: asks, or, when Android will not ask
  /// again, opens the app's settings.
  Future<void> allowCalendar() async {
    if (_calendarBlocked) {
      await ui.openAppDetails();
      return;
    }
    switch (await ui.requestPermission(UiPermission.calendar)) {
      case PermissionResult.granted:
        _calendarAllowed = true;
        _calendarBlocked = false;
      case PermissionResult.denied:
        break;
      case PermissionResult.permanentlyDenied:
        _calendarBlocked = true;
    }
    _notify();
  }

  /// **Ring a test alarm**: asks the engine for a real alarm in [testDelay] and
  /// starts the countdown. A failure puts the step back as it was and throws;
  /// the screen says so in fixed text.
  Future<void> ringTestAlarm() async {
    if (_step != OnboardingStep.testAlarm || _phase != TestAlarmPhase.idle) {
      return;
    }
    _phase = TestAlarmPhase.starting;
    _notify();
    try {
      await engine.testAlarm(AlertStrength.alarm, delay: testDelay);
    } catch (_) {
      _phase = TestAlarmPhase.idle;
      _notify();
      rethrow;
    }
    if (_disposed || _step != OnboardingStep.testAlarm) return;
    _secondsLeft = testDelay.inSeconds;
    _phase = TestAlarmPhase.counting;
    _countdown = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _notify();
  }

  void _tick() {
    _secondsLeft -= 1;
    if (_secondsLeft <= 0) {
      _secondsLeft = 0;
      _countdown?.cancel();
      _countdown = null;
      _phase = TestAlarmPhase.asking;
    }
    _notify();
  }

  /// Counts the next 7 days' meetings that have alarms, for the last step. A
  /// failure leaves the count out; the step does not depend on it.
  Future<void> _loadSummary() async {
    final mine = ++_summaryLoads;
    _alarmed = null;
    try {
      final snapshot = await loader.load();
      if (_disposed || mine != _summaryLoads) return;
      _alarmed = snapshot.upcoming.where((i) => i.on).length;
      _notify();
    } catch (e) {
      debugPrint('Counting the meetings failed (${_kind(e)})');
    }
  }

  /// Marks onboarding as done. The router's [OnboardingGate] follows the stored
  /// flag by itself and moves to the Agenda. A caller that navigates somewhere
  /// else right after passes [gateNow]: the gate learns of the flag from a
  /// database stream a moment after the write, and a `go` made before that is
  /// sent back to onboarding, so the gate reads the flag again first.
  ///
  /// False when a finish is already running (that one does the work); throws
  /// when the flag cannot be written.
  Future<bool> finish({bool gateNow = false}) async {
    if (_finishing) return false;
    _finishing = true;
    _notify();
    try {
      await appSettings.setOnboardingDone(true);
      if (gateNow) await gate.load();
      return true;
    } finally {
      _finishing = false;
      _notify();
    }
  }

  /// Whether the Health report says [id] is in order; null when it does not say.
  bool? _allowed(String id) {
    final items = monitor.report?.items;
    if (items == null) return null;
    for (final item in items) {
      if (item.id == id) return item.level == HealthLevel.ok;
    }
    return null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_sourceUpdates?.cancel());
    unawaited(_restoreUpdates?.cancel());
    monitor.removeListener(_notify);
    _lifecycle?.dispose();
    _lifecycle = null;
    _countdown?.cancel();
    _countdown = null;
    super.dispose();
  }
}
