import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/engine/engine_models.dart';
import 'package:tminus/core/model/alert.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/model/sync_log_entry.dart';
import 'package:tminus/core/storage/app_settings.dart';
import 'package:tminus/core/sync/source_status.dart';
import 'package:tminus/features/health/health_report.dart';

void main() {
  final now = DateTime.utc(2026, 10, 6, 9, 27);
  const work = SourceConfig(
    id: 'w',
    name: 'Work Outlook',
    color: 0xFF6AA0F5,
    kind: SourceKind.ics,
    secureStorageKey: 'ics-url.w',
  );
  const phone = SourceConfig(
    id: 'p',
    name: 'Personal',
    color: 0xFF5BC489,
    kind: SourceKind.device,
    deviceCalendarId: '3',
  );

  /// Everything fine unless a test turns one thing off.
  EngineHealth engineHealth({
    bool notificationsEnabled = true,
    bool ringingChannelEnabled = true,
    bool canUseFullScreenIntent = true,
    bool canScheduleExactAlarms = true,
    bool ignoringBatteryOptimizations = true,
    bool alarmStreamMuted = false,
    List<UpcomingAlert> upcoming = const [],
  }) => EngineHealth(
    notificationsEnabled: notificationsEnabled,
    ringingChannelEnabled: ringingChannelEnabled,
    canUseFullScreenIntent: canUseFullScreenIntent,
    canScheduleExactAlarms: canScheduleExactAlarms,
    ignoringBatteryOptimizations: ignoringBatteryOptimizations,
    alarmStreamMuted: alarmStreamMuted,
    upcoming: upcoming,
  );

  SourceStatus status(
    SourceConfig config, {
    SourceSyncState? state,
    SyncLogEntry? latest,
    SourceSetup setup = SourceSetup.ready,
  }) => sourceStatusOf(
    config: config,
    state: state,
    latest: latest,
    setup: setup,
    now: now,
  );

  /// Synced 4 minutes ago: ok.
  SourceStatus synced(SourceConfig config) => status(
    config,
    state: SourceSyncState(
      lastSuccessUtc: now.subtract(const Duration(minutes: 4)),
    ),
  );

  /// The last attempt ended in [outcome] and left [message] on the source.
  SourceStatus failed(
    SourceConfig config,
    SyncOutcome outcome,
    String message,
  ) => status(
    config,
    state: SourceSyncState(
      lastSuccessUtc: now.subtract(const Duration(days: 2)),
      lastError: message,
    ),
    latest: SyncLogEntry(sourceId: config.id, atUtc: now, outcome: outcome),
  );

  HealthItem engineRow(String id, EngineHealth engine) =>
      buildHealthReport(engine, const []).items.singleWhere((i) => i.id == id);

  HealthItem sourceRow(SourceStatus s) =>
      buildHealthReport(engineHealth(), [s]).items.last;

  test('Notifications is a problem when off, and its fix opens the '
      'notification settings', () {
    final off = engineRow(
      'notifications',
      engineHealth(notificationsEnabled: false),
    );
    expect(off.title, 'Notifications');
    expect(off.level, HealthLevel.problem);
    expect(off.detail, 'Off — no alerts can be shown');
    expect(off.fix, HealthFix.permission);
    expect(off.permission, PermissionKind.notifications);

    final on = engineRow('notifications', engineHealth());
    expect(on.level, HealthLevel.ok);
    expect(on.detail, 'Allowed');
    expect(on.fix, HealthFix.none);
    expect(on.permission, isNull);
  });

  test('Full-screen alarms is a problem when off, and its fix opens the '
      'full-screen settings', () {
    final off = engineRow(
      'fullScreen',
      engineHealth(canUseFullScreenIntent: false),
    );
    expect(off.title, 'Full-screen alarms');
    expect(off.level, HealthLevel.problem);
    expect(off.detail, 'Off — alarms appear only as a notification');
    expect(off.fix, HealthFix.permission);
    expect(off.permission, PermissionKind.fullScreenIntent);

    final on = engineRow('fullScreen', engineHealth());
    expect(on.level, HealthLevel.ok);
    expect(on.detail, 'Allowed');
    expect(on.fix, HealthFix.none);
  });

  test('Exact alarms is only a warning when off, and its fix opens the '
      'exact-alarm settings', () {
    final off = engineRow(
      'exactAlarms',
      engineHealth(canScheduleExactAlarms: false),
    );
    expect(off.title, 'Exact alarms');
    expect(off.level, HealthLevel.warning);
    expect(off.detail, 'Off — alarms may ring a few minutes late');
    expect(off.fix, HealthFix.permission);
    expect(off.permission, PermissionKind.exactAlarm);

    final on = engineRow('exactAlarms', engineHealth());
    expect(on.level, HealthLevel.ok);
    expect(on.detail, 'Allowed');
    expect(on.fix, HealthFix.none);
  });

  test('Battery optimisation is only a warning when optimised, and its fix '
      'opens the battery settings', () {
    final optimised = engineRow(
      'battery',
      engineHealth(ignoringBatteryOptimizations: false),
    );
    expect(optimised.title, 'Battery optimisation');
    expect(optimised.level, HealthLevel.warning);
    expect(optimised.detail, 'Optimised — Android may delay alarms');
    expect(optimised.fix, HealthFix.permission);
    expect(optimised.permission, PermissionKind.batteryOptimization);

    final fine = engineRow('battery', engineHealth());
    expect(fine.level, HealthLevel.ok);
    expect(fine.detail, 'Not optimised');
    expect(fine.fix, HealthFix.none);
  });

  test('Alarm channel is a problem when the alarm volume is muted or the '
      'channel is off, each with its own fix', () {
    final muted = engineRow(
      'alarmChannel',
      engineHealth(alarmStreamMuted: true),
    );
    expect(muted.title, 'Alarm channel');
    expect(muted.level, HealthLevel.problem);
    expect(muted.detail, 'Alarm volume is muted');
    expect(muted.fix, HealthFix.permission);
    expect(muted.permission, PermissionKind.alarmVolume);

    final channelOff = engineRow(
      'alarmChannel',
      engineHealth(ringingChannelEnabled: false),
    );
    expect(channelOff.level, HealthLevel.problem);
    expect(channelOff.detail, 'The alarm notification channel is off');
    expect(channelOff.fix, HealthFix.permission);
    expect(channelOff.permission, PermissionKind.notifications);

    // Both at once: one row, so the muted volume is shown first, as the
    // checklist lists it. Fixing it shows the channel next.
    final both = engineRow(
      'alarmChannel',
      engineHealth(alarmStreamMuted: true, ringingChannelEnabled: false),
    );
    expect(both.level, HealthLevel.problem);
    expect(both.detail, 'Alarm volume is muted');
    expect(both.permission, PermissionKind.alarmVolume);

    final fine = engineRow('alarmChannel', engineHealth());
    expect(fine.level, HealthLevel.ok);
    expect(fine.detail, 'Not muted');
    expect(fine.fix, HealthFix.none);
  });

  test('Sync rows take their level from the source: errors and a missing '
      'setup are problems, amber and stale are warnings', () {
    final error = sourceRow(
      failed(
        work,
        SyncOutcome.httpError,
        'The link no longer works (HTTP 404).',
      ),
    );
    expect(error.id, 'source:w');
    expect(error.title, 'Sync · Work Outlook');
    expect(error.detail, 'The link no longer works (HTTP 404).');
    expect(error.level, HealthLevel.problem);
    expect(error.fix, HealthFix.source);
    expect(error.sourceId, 'w');
    expect(error.permission, isNull);

    final needsLink = sourceRow(
      status(work.copyWith(enabled: false), setup: SourceSetup.needsLink),
    );
    expect(needsLink.level, HealthLevel.problem);
    expect(needsLink.detail, 'Needs its link');
    expect(needsLink.fix, HealthFix.source);
    expect(needsLink.sourceId, 'w');

    final amber = sourceRow(
      failed(work, SyncOutcome.networkError, 'No connection.'),
    );
    expect(amber.level, HealthLevel.warning);
    expect(amber.detail, 'No connection.');
    expect(amber.fix, HealthFix.source);
    expect(amber.sourceId, 'w');

    final stale = sourceRow(
      status(
        work,
        state: SourceSyncState(
          lastSuccessUtc: now.subtract(const Duration(minutes: 61)),
        ),
      ),
    );
    expect(stale.level, HealthLevel.warning);
    expect(stale.detail, 'Feed stale · synced 1 h ago');
    expect(stale.fix, HealthFix.source);
    expect(stale.sourceId, 'w');

    final fine = sourceRow(synced(phone));
    expect(fine.id, 'source:p');
    expect(fine.title, 'Sync · Personal');
    expect(fine.level, HealthLevel.ok);
    expect(fine.detail, 'Synced 4 min ago');
    expect(fine.fix, HealthFix.none);
  });

  test('the engine rows come first in the brief\'s order, then each source '
      'in the order given', () {
    final report = buildHealthReport(engineHealth(), [
      synced(phone),
      synced(work),
    ]);

    expect(report.items.map((i) => i.id), [
      'notifications',
      'fullScreen',
      'exactAlarms',
      'battery',
      'alarmChannel',
      'source:p',
      'source:w',
    ]);
    expect(report.items.map((i) => i.title), [
      'Notifications',
      'Full-screen alarms',
      'Exact alarms',
      'Battery optimisation',
      'Alarm channel',
      'Sync · Personal',
      'Sync · Work Outlook',
    ]);
  });

  test('the overall level is the worst item', () {
    final good = buildHealthReport(engineHealth(), [synced(work)]);
    expect(good.overall, HealthLevel.ok);
    expect(good.headline, 'All good — alarms will ring');
    expect(good.hasProblem, isFalse);

    final amber = buildHealthReport(
      engineHealth(ignoringBatteryOptimizations: false),
      [synced(work)],
    );
    expect(amber.overall, HealthLevel.warning);
    expect(amber.headline, 'Alarms may be late');
    expect(amber.hasProblem, isFalse);

    final red = buildHealthReport(
      engineHealth(
        ignoringBatteryOptimizations: false,
        canUseFullScreenIntent: false,
      ),
      [synced(work)],
    );
    expect(red.overall, HealthLevel.problem);
    expect(red.headline, 'Alarms may not ring');
    expect(red.hasProblem, isTrue);

    // A source alone can make it red.
    final brokenFeed = buildHealthReport(engineHealth(), [
      failed(
        work,
        SyncOutcome.httpError,
        'The link no longer works (HTTP 404).',
      ),
    ]);
    expect(brokenFeed.overall, HealthLevel.problem);
    expect(brokenFeed.hasProblem, isTrue);
  });

  test('the summary counts problems and warnings with singulars', () {
    String summary(EngineHealth e, [List<SourceStatus> s = const []]) =>
        buildHealthReport(e, s).summary;

    // Mockup 4d: Full-screen off, Battery optimised, a feed that stopped.
    expect(
      summary(
        engineHealth(
          canUseFullScreenIntent: false,
          ignoringBatteryOptimizations: false,
        ),
        [
          failed(
            work,
            SyncOutcome.httpError,
            'The link no longer works (HTTP 404).',
          ),
        ],
      ),
      '2 problems and 1 warning. Fix them below.',
    );
    expect(
      summary(
        engineHealth(
          notificationsEnabled: false,
          canScheduleExactAlarms: false,
          ignoringBatteryOptimizations: false,
        ),
      ),
      '1 problem and 2 warnings. Fix them below.',
    );
    expect(
      summary(engineHealth(ignoringBatteryOptimizations: false)),
      '1 warning. Fix them below.',
    );
    expect(
      summary(
        engineHealth(
          notificationsEnabled: false,
          canUseFullScreenIntent: false,
          alarmStreamMuted: true,
        ),
      ),
      '3 problems. Fix them below.',
    );
    expect(summary(engineHealth()), isEmpty);
  });

  test('a disabled source is not listed but one needing setup is', () {
    final off = status(work.copyWith(enabled: false));
    final waiting = status(
      phone.copyWith(enabled: false),
      setup: SourceSetup.needsCalendar,
    );
    expect(off.health, SourceHealth.off);
    expect(waiting.health, SourceHealth.needsSetup);

    final report = buildHealthReport(engineHealth(), [off, waiting]);

    final rows = report.items.where((i) => i.id.startsWith('source:'));
    expect(rows.map((i) => i.id), ['source:p']);
    expect(rows.single.detail, 'Choose its calendar on this phone');
    expect(rows.single.level, HealthLevel.problem);
  });

  test('no engine report gives one warning and no crash', () {
    final report = buildHealthReport(null, const []);

    final only = report.items.single;
    expect(only.id, 'engine');
    expect(only.title, 'Alarm engine');
    expect(only.detail, 'Could not be checked');
    expect(only.level, HealthLevel.warning);
    expect(only.fix, HealthFix.none);
    expect(only.permission, isNull);
    expect(only.sourceId, isNull);
    expect(report.overall, HealthLevel.warning);
    expect(report.headline, 'Alarms may be late');
    expect(report.hasProblem, isFalse);
    expect(report.upcoming, isEmpty);

    // The sources are still checked.
    final withSource = buildHealthReport(null, [synced(work)]);
    expect(withSource.items.map((i) => i.id), ['engine', 'source:w']);
  });

  test('the engine\'s upcoming alarms ride on the report', () {
    final upcoming = [
      UpcomingAlert(
        id: 'a',
        fireAtUtc: now,
        strength: AlertStrength.alarm,
        title: 'Sprint planning',
      ),
      UpcomingAlert(
        id: 'b',
        fireAtUtc: now.add(const Duration(minutes: 10)),
        strength: AlertStrength.headsUp,
        title: 'Client demo',
      ),
    ];

    final report = buildHealthReport(
      engineHealth(upcoming: upcoming),
      const [],
    );

    expect(report.upcoming, upcoming);
  });
}
