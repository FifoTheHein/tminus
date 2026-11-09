import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../app/theme/tminus_theme.dart';
import '../../core/engine/alarm_engine.dart' show PermissionKind;
import '../common/guarded.dart';
import '../common/notice_banner.dart';
import '../common/section_card.dart';
import '../common/status_tone.dart';
import '../sources/add_source_panel.dart';
import 'onboarding_controller.dart';
import 'permission_row.dart';

// Fixed texts. A failure is only ever described by one of these: the error's
// own text can quote a feed link, a file path or a row's values.
const _permissionFailed = "Couldn't ask for the permission.";
const _settingsFailed = "Couldn't open the settings.";
const _testFailed = "Couldn't start the test alarm.";
const _finishFailed = "Couldn't finish the setup.";

/// The Add your calendar step after a restore: the calendars are in the
/// database already and wait for their links. Grammar follows the number.
String restoredText(int calendars) => calendars == 1
    ? "You have 1 calendar from your backup. You'll re-link it in Sources "
          'after setup.'
    : 'You have $calendars calendars from your backup. '
          "You'll re-link them in Sources after setup.";

/// The last step's line. Grammar follows the number.
String alarmedMeetingsText(int meetings) => switch (meetings) {
  0 => 'No meetings in the next 7 days have alarms.',
  1 => '1 meeting in the next 7 days has alarms.',
  _ => '$meetings meetings in the next 7 days have alarms.',
};

/// Onboarding (mockups 5a–5e, brief §1), shown at `/onboarding` until it is
/// done: Welcome, Add your calendar, Permissions, a real test alarm, and Done.
/// The router's gate moves on to the Agenda once the flag is stored.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _buttonHeight = 56.0;

  late final OnboardingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = OnboardingController(
      sources: getIt(),
      appSettings: getIt(),
      engine: getIt(),
      ui: getIt(),
      calendars: getIt(),
      monitor: getIt(),
      loader: getIt(),
      gate: getIt(),
    )..start();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Moves between steps with the keyboard put away.
  void _navigate(VoidCallback move) {
    FocusManager.instance.primaryFocus?.unfocus();
    move();
  }

  Future<void> _allowNotifications() => guarded<void>(
    context,
    _controller.allowNotifications,
    failure: _permissionFailed,
  );

  Future<void> _allowCalendar() => guarded<void>(
    context,
    _controller.allowCalendar,
    failure: _permissionFailed,
  );

  Future<void> _openSettings(PermissionKind kind) => guarded<void>(
    context,
    () => _controller.openSettingsFor(kind),
    failure: _settingsFailed,
  );

  Future<void> _ringTestAlarm() =>
      guarded<void>(context, _controller.ringTestAlarm, failure: _testFailed);

  /// Finishes onboarding. The Agenda exit needs nothing more: the gate sees the
  /// flag and the router moves. Health is another place, so it is gone to
  /// explicitly, after the gate has been told that onboarding is done (a `go`
  /// before that is sent back to onboarding).
  Future<void> _finish({required bool toHealth}) async {
    final router = GoRouter.of(context);
    final finished = await guarded<bool>(
      context,
      () => _controller.finish(gateNow: toHealth),
      failure: _finishFailed,
    );
    if (finished == true && toHealth) router.go('/health');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final c = _controller;
        return PopScope(
          // `/onboarding` is the only page, so the system Back button would
          // close the app from any step. It closes it from the first step
          // only; elsewhere it is blocked and does what the on-screen Back does
          // (`back` does nothing where that has no Back).
          canPop: c.backLeavesApp,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _navigate(c.back);
          },
          child: Scaffold(
            body: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (c.step != OnboardingStep.welcome)
                    _ProgressStrip(
                      step: c.stepNumber,
                      total: OnboardingController.stepCount,
                    ),
                  Expanded(child: _body(context)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      TMinusSpacing.lg,
                      TMinusSpacing.xs,
                      TMinusSpacing.lg,
                      TMinusSpacing.md,
                    ),
                    child: _actions(context),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context) {
    return switch (_controller.step) {
      OnboardingStep.welcome => _welcome(context),
      OnboardingStep.calendar => _calendar(context),
      OnboardingStep.permissions => _permissions(context),
      OnboardingStep.testAlarm => _testAlarm(context),
      OnboardingStep.done => _done(context),
    };
  }

  // ---- Welcome (5a) ----

  Widget _welcome(BuildContext context) {
    return _Page(
      key: const Key('step-welcome'),
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Ring(
            size: 96,
            value: 0.92,
            child: Text(
              'T−',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          const SizedBox(height: TMinusSpacing.xl),
          const _Heading("Meetings you can't miss", large: true),
          const SizedBox(height: TMinusSpacing.md),
          const _Muted(
            "T-Minus turns your calendar into alarms you can't miss, and can "
            'always stop.',
          ),
        ],
      ),
    );
  }

  // ---- Add your calendar (5b) ----

  Widget _calendar(BuildContext context) {
    return _Page(
      key: const Key('step-calendar'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Heading('Add your calendar'),
          const SizedBox(height: TMinusSpacing.xxs),
          const _Muted('You can add more later in Sources.'),
          const SizedBox(height: TMinusSpacing.lg),
          if (_controller.restored)
            _RestoredCard(calendars: _controller.sourceCount)
          else
            AddSourcePanel(
              key: const Key('addSourcePanel'),
              onboarding: true,
              // Continue follows the source list (the controller watches it),
              // so nothing is left to do when the panel reports an add.
              onAdded: (_) {},
            ),
        ],
      ),
    );
  }

  // ---- Permissions (5c) ----

  Widget _permissions(BuildContext context) {
    final c = _controller;
    return _Page(
      key: const Key('step-permissions'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Heading('Alarms need a few permissions.'),
          const SizedBox(height: TMinusSpacing.lg),
          SectionCard(
            children: [
              PermissionRow(
                id: 'notifications',
                icon: Icons.notifications_outlined,
                title: 'Notifications',
                reason: 'So alerts can appear.',
                allowed: c.notificationsAllowed,
                onAction: () => unawaited(_allowNotifications()),
              ),
              if (c.showFullScreen)
                PermissionRow(
                  id: 'fullScreen',
                  icon: Icons.fullscreen,
                  title: 'Full-screen alarms',
                  reason: 'So an alarm fills the screen, even when locked.',
                  allowed: false,
                  onAction: () =>
                      unawaited(_openSettings(PermissionKind.fullScreenIntent)),
                ),
              PermissionRow(
                id: 'battery',
                icon: Icons.battery_charging_full,
                title: 'Battery',
                reason: "So Android doesn't delay alarms.",
                allowed: c.batteryAllowed,
                onAction: () => unawaited(
                  _openSettings(PermissionKind.batteryOptimization),
                ),
              ),
              if (c.hasDeviceSource)
                PermissionRow(
                  id: 'calendar',
                  icon: Icons.calendar_month_outlined,
                  title: 'Calendar access',
                  reason: "So T-Minus can read your phone's calendars.",
                  allowed: c.calendarAccess == CalendarAccess.allowed,
                  actionLabel: c.calendarAccess == CalendarAccess.openSettings
                      ? 'Open settings'
                      : 'Allow',
                  onAction: () => unawaited(_allowCalendar()),
                ),
            ],
          ),
          if (c.notificationsOff) ...const [
            SizedBox(height: TMinusSpacing.md),
            NoticeBanner(
              key: Key('notificationsWarning'),
              tone: StatusTone.warn,
              icon: Icons.warning_amber_rounded,
              title: 'Without notifications no alarm can be shown.',
            ),
          ],
        ],
      ),
    );
  }

  // ---- Test alarm (5d) ----

  Widget _testAlarm(BuildContext context) {
    final c = _controller;
    final scheme = Theme.of(context).colorScheme;
    final seconds = OnboardingController.testDelay.inSeconds;
    final idle = c.testPhase == TestAlarmPhase.idle;
    final asking = c.testPhase == TestAlarmPhase.asking;
    return _Page(
      key: const Key('step-testAlarm'),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Heading("Let's make sure it rings", center: true),
          const SizedBox(height: TMinusSpacing.sm),
          _Muted(
            "We'll fire a real alarm in $seconds seconds so you know it works "
            'on this phone.',
            center: true,
          ),
          const SizedBox(height: TMinusSpacing.xl),
          _Ring(
            key: const Key('testRing'),
            size: 200,
            strokeWidth: 10,
            // Full while the alarm is on its way, and emptying with it.
            value: switch (c.testPhase) {
              TestAlarmPhase.counting => c.secondsLeft / seconds,
              _ => 0,
            },
            child: asking
                ? Icon(Icons.alarm_rounded, size: 64, color: scheme.primary)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${c.secondsLeft}',
                        key: const Key('testNumber'),
                        style: context.tminusType.countdownL,
                      ),
                      Text(
                        idle ? 'READY' : 'SECONDS',
                        style: context.tminusType.overline.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
          ),
          if (!idle) ...[
            const SizedBox(height: TMinusSpacing.lg),
            // Said aloud as it changes, for a screen reader.
            Semantics(
              liveRegion: true,
              child: Text(
                asking ? 'Did it ring?' : 'Ringing in $seconds seconds…',
                key: const Key('testStatus'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---- Done (5e) ----

  Widget _done(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final alarmed = _controller.alarmedMeetings;
    return _Page(
      key: const Key('step-done'),
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Ring(
            size: 96,
            value: 1,
            child: Icon(Icons.check, size: 40, color: scheme.primary),
          ),
          const SizedBox(height: TMinusSpacing.xl),
          const _Heading("You're set.", large: true),
          if (alarmed != null) ...[
            const SizedBox(height: TMinusSpacing.md),
            _Muted(alarmedMeetingsText(alarmed), key: const Key('alarmed')),
          ],
        ],
      ),
    );
  }

  // ---- The buttons at the bottom ----

  Widget _actions(BuildContext context) {
    final c = _controller;
    switch (c.step) {
      case OnboardingStep.welcome:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _primary(
              key: const Key('getStarted'),
              label: 'Get started',
              onPressed: () => _navigate(c.next),
            ),
            const SizedBox(height: TMinusSpacing.sm),
            const _PrivacyNote(),
          ],
        );
      case OnboardingStep.calendar:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _backAndPrimary(
              primary: _primary(
                key: const Key('continue'),
                label: 'Continue',
                onPressed: c.canContinue ? () => _navigate(c.next) : null,
              ),
            ),
            _skip(),
          ],
        );
      case OnboardingStep.permissions:
        return _backAndPrimary(
          primary: _primary(
            key: const Key('continue'),
            label: 'Continue',
            onPressed: () => _navigate(c.next),
          ),
        );
      case OnboardingStep.testAlarm:
        if (c.testPhase == TestAlarmPhase.asking) {
          return Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('itDidntRing'),
                  onPressed: c.finishing
                      ? null
                      : () => unawaited(_finish(toHealth: true)),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(_buttonHeight),
                  ),
                  child: const Text("It didn't ring"),
                ),
              ),
              const SizedBox(width: TMinusSpacing.sm),
              Expanded(
                child: _primary(
                  key: const Key('itRang'),
                  label: 'It rang',
                  onPressed: c.finishing ? null : () => _navigate(c.next),
                ),
              ),
            ],
          );
        }
        final idle = c.testPhase == TestAlarmPhase.idle;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _backAndPrimary(
              primary: _primary(
                key: const Key('ringTestAlarm'),
                label: 'Ring a test alarm',
                icon: Icons.alarm_rounded,
                onPressed: idle ? () => unawaited(_ringTestAlarm()) : null,
              ),
            ),
            if (idle) _skip(),
          ],
        );
      case OnboardingStep.done:
        return _primary(
          key: const Key('goToAgenda'),
          label: 'Go to Agenda',
          onPressed: c.finishing
              ? null
              : () => unawaited(_finish(toHealth: false)),
        );
    }
  }

  /// The wide button of a step.
  Widget _primary({
    required Key key,
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
  }) {
    final style = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(_buttonHeight),
    );
    if (icon == null) {
      return FilledButton(
        key: key,
        onPressed: onPressed,
        style: style,
        child: Text(label),
      );
    }
    return FilledButton.icon(
      key: key,
      onPressed: onPressed,
      style: style,
      icon: Icon(icon),
      label: Text(label),
    );
  }

  /// **Back** at the left, the step's button filling the rest (mockup 5b).
  Widget _backAndPrimary({required Widget primary}) {
    final c = _controller;
    return Row(
      children: [
        TextButton(
          key: const Key('back'),
          onPressed: c.canGoBack ? () => _navigate(c.back) : null,
          child: const Text('Back'),
        ),
        const SizedBox(width: TMinusSpacing.md),
        Expanded(child: primary),
      ],
    );
  }

  Widget _skip() => TextButton(
    key: const Key('skip'),
    onPressed: () => _navigate(_controller.skip),
    child: const Text('Skip for now'),
  );
}

/// "STEP 2 OF 5" over five segments: the steps done and the one the user is on
/// are filled.
class _ProgressStrip extends StatelessWidget {
  const _ProgressStrip({required this.step, required this.total});

  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TMinusSpacing.lg,
        TMinusSpacing.md,
        TMinusSpacing.lg,
        0,
      ),
      child: Semantics(
        label: 'Step $step of $total',
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'STEP $step OF $total',
                key: const Key('stepLabel'),
                style: context.tminusType.overline.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: TMinusSpacing.xs),
              Row(
                children: [
                  for (var i = 1; i <= total; i++) ...[
                    if (i > 1) const SizedBox(width: TMinusSpacing.xs),
                    Expanded(
                      child: Container(
                        key: Key('progress-$i'),
                        height: 4,
                        decoration: BoxDecoration(
                          color: i <= step
                              ? scheme.primary
                              : scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(TMinusRadii.pill),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A step's content: it scrolls (the add-calendar panel does not, and a large
/// font makes any step taller than the screen) and, given an [alignment], sits
/// there in the room it has, as the welcome and last steps do in the middle.
class _Page extends StatelessWidget {
  const _Page({super.key, required this.child, this.alignment});

  final Widget child;

  /// Where [child] sits in the room the page has; null keeps it at the top.
  final Alignment? alignment;

  static const _inset = EdgeInsets.fromLTRB(
    TMinusSpacing.lg,
    TMinusSpacing.xl,
    TMinusSpacing.lg,
    TMinusSpacing.md,
  );

  @override
  Widget build(BuildContext context) {
    final place = alignment;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: _inset,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: math.max(0.0, constraints.maxHeight - _inset.vertical),
          ),
          child: place == null ? child : Align(alignment: place, child: child),
        ),
      ),
    );
  }
}

/// A circle of [value] (1 is all the way round), with [child] in the middle:
/// the T− mark, the test alarm's countdown and the tick of the last step.
class _Ring extends StatelessWidget {
  const _Ring({
    super.key,
    required this.size,
    required this.value,
    required this.child,
    this.strokeWidth = 8,
  });

  final double size;
  final double value;
  final double strokeWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CircularProgressIndicator(
              value: value,
              strokeWidth: strokeWidth,
              strokeCap: StrokeCap.round,
              color: scheme.primary,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.large = false, this.center = false});

  final String text;
  final bool large;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      header: true,
      child: Text(
        text,
        textAlign: center ? TextAlign.center : null,
        style: large ? textTheme.headlineLarge : textTheme.headlineMedium,
      ),
    );
  }
}

/// The grey sentence under a heading.
class _Muted extends StatelessWidget {
  const _Muted(this.text, {super.key, this.center = false});

  final String text;
  final bool center;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: center ? TextAlign.center : null,
      style: Theme.of(context).textTheme.bodyLarge
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}

/// "Your calendar never leaves your phone." under the welcome button.
class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    final muted = context.tminusColors.tertiaryText;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock_outline, size: 16, color: muted),
        const SizedBox(width: TMinusSpacing.xxs),
        // On a narrow screen at a large text size the line wraps.
        Flexible(
          child: Text(
            'Your calendar never leaves your phone.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: muted),
          ),
        ),
      ],
    );
  }
}

/// What the Add your calendar step says after a restore, in place of the
/// panel.
class _RestoredCard extends StatelessWidget {
  const _RestoredCard({required this.calendars});

  final int calendars;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const Key('restoredCard'),
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(TMinusRadii.xl),
      child: Padding(
        padding: const EdgeInsets.all(TMinusSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.restore, color: scheme.primary),
            const SizedBox(width: TMinusSpacing.sm),
            Expanded(
              child: Text(
                restoredText(calendars),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
