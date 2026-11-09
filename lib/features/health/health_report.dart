import '../../core/engine/engine_models.dart';
import '../../core/sync/source_status.dart';

/// How serious one Health row is. Declared worst last.
enum HealthLevel { ok, warning, problem }

/// What a row's Fix button does.
enum HealthFix {
  /// Opens a system settings screen: [HealthItem.permission].
  permission,

  /// Opens the source: [HealthItem.sourceId].
  source,

  /// Nothing to fix, or nothing the app can open.
  none,
}

/// One row of the Health checklist (spec §9, brief §6).
class HealthItem {
  const HealthItem({
    required this.id,
    required this.title,
    required this.detail,
    required this.level,
    this.fix = HealthFix.none,
    this.permission,
    this.sourceId,
  });

  /// `notifications`, `fullScreen`, `exactAlarms`, `battery`, `alarmChannel`,
  /// `engine` or `source:<id>`.
  final String id;

  /// The row's name as the brief writes it: `Notifications`,
  /// `Sync · Work Outlook`.
  final String title;

  /// The line under the title. The screen colours it unless the row is ok.
  final String detail;
  final HealthLevel level;
  final HealthFix fix;

  /// The settings screen [HealthFix.permission] opens.
  final PermissionKind? permission;

  /// The source a `source:` row is about; [HealthFix.source] opens it.
  final String? sourceId;
}

/// What the Health tab, the Agenda banner and the navigation dot show.
class HealthReport {
  const HealthReport({
    required this.items,
    required this.overall,
    required this.headline,
    required this.summary,
    this.upcoming = const [],
  });

  final List<HealthItem> items;

  /// The worst level among [items].
  final HealthLevel overall;

  /// `All good — alarms will ring`, `Alarms may be late` or
  /// `Alarms may not ring`.
  final String headline;

  /// `2 problems and 1 warning. Fix them below.`, empty when all is good.
  final String summary;

  /// The alerts the native engine has scheduled, soonest first.
  final List<UpcomingAlert> upcoming;

  /// A red item: the Agenda banner and the navigation dot.
  bool get hasProblem => overall == HealthLevel.problem;
}

/// Works out the Health checklist (spec §9). [engine] is null when the native
/// side could not be read. [sources] are every source's status: a disabled one
/// is left out, and one waiting for its link or calendar is listed.
HealthReport buildHealthReport(
  EngineHealth? engine,
  List<SourceStatus> sources,
) {
  final items = <HealthItem>[
    if (engine == null) _engineUnavailable else ..._engineItems(engine),
    for (final s in sources)
      if (s.health != SourceHealth.off) _sourceItem(s),
  ];
  final problems = items.where((i) => i.level == HealthLevel.problem).length;
  final warnings = items.where((i) => i.level == HealthLevel.warning).length;
  final overall = problems > 0
      ? HealthLevel.problem
      : warnings > 0
      ? HealthLevel.warning
      : HealthLevel.ok;
  return HealthReport(
    items: List.unmodifiable(items),
    overall: overall,
    headline: switch (overall) {
      HealthLevel.problem => 'Alarms may not ring',
      HealthLevel.warning => 'Alarms may be late',
      HealthLevel.ok => 'All good. Alarms will ring',
    },
    summary: _summary(problems, warnings),
    upcoming: List.unmodifiable(engine?.upcoming ?? const <UpcomingAlert>[]),
  );
}

/// Without a native side (or when `getHealth` failed) nothing else can be said
/// about the alarms, and there is nothing to open.
const _engineUnavailable = HealthItem(
  id: 'engine',
  title: 'Alarm engine',
  detail: 'Could not be checked',
  level: HealthLevel.warning,
);

List<HealthItem> _engineItems(EngineHealth e) => [
  _check(
    id: 'notifications',
    title: 'Notifications',
    allowed: e.notificationsEnabled,
    otherwise: HealthLevel.problem,
    okDetail: 'Allowed',
    detail: 'Off: no alerts can be shown',
    fix: PermissionKind.notifications,
  ),
  _check(
    id: 'fullScreen',
    title: 'Full-screen alarms',
    allowed: e.canUseFullScreenIntent,
    otherwise: HealthLevel.problem,
    okDetail: 'Allowed',
    detail: 'Off: alarms appear only as a notification',
    fix: PermissionKind.fullScreenIntent,
  ),
  _check(
    id: 'exactAlarms',
    title: 'Exact alarms',
    allowed: e.canScheduleExactAlarms,
    otherwise: HealthLevel.warning,
    okDetail: 'Allowed',
    detail: 'Off: alarms may ring a few minutes late',
    fix: PermissionKind.exactAlarm,
  ),
  _check(
    id: 'battery',
    title: 'Battery optimisation',
    allowed: e.ignoringBatteryOptimizations,
    otherwise: HealthLevel.warning,
    okDetail: 'Not optimised',
    detail: 'Optimised: Android may delay alarms',
    fix: PermissionKind.batteryOptimization,
  ),
  // A muted alarm volume is reported before a switched-off channel. Each is
  // fixed in its own settings screen, so once the first is fixed the row shows
  // the second.
  _check(
    id: 'alarmChannel',
    title: 'Alarm channel',
    allowed: !e.alarmStreamMuted && e.ringingChannelEnabled,
    otherwise: HealthLevel.problem,
    okDetail: 'Not muted',
    detail: e.alarmStreamMuted
        ? 'Alarm volume is muted'
        : 'The alarm notification channel is off',
    fix: e.alarmStreamMuted
        ? PermissionKind.alarmVolume
        : PermissionKind.notifications,
  ),
];

/// An ok row has nothing to fix. Any other opens [fix]'s settings screen.
HealthItem _check({
  required String id,
  required String title,
  required bool allowed,
  required HealthLevel otherwise,
  required String okDetail,
  required String detail,
  required PermissionKind fix,
}) => allowed
    ? HealthItem(id: id, title: title, detail: okDetail, level: HealthLevel.ok)
    : HealthItem(
        id: id,
        title: title,
        detail: detail,
        level: otherwise,
        fix: HealthFix.permission,
        permission: fix,
      );

HealthItem _sourceItem(SourceStatus s) {
  final level = switch (s.health) {
    SourceHealth.error || SourceHealth.needsSetup => HealthLevel.problem,
    SourceHealth.warning || SourceHealth.stale => HealthLevel.warning,
    SourceHealth.ok || SourceHealth.off => HealthLevel.ok,
  };
  return HealthItem(
    id: 'source:${s.config.id}',
    title: 'Sync · ${s.config.name}',
    detail: s.line,
    level: level,
    fix: level == HealthLevel.ok ? HealthFix.none : HealthFix.source,
    sourceId: s.config.id,
  );
}

String _summary(int problems, int warnings) {
  final parts = [
    if (problems > 0) problems == 1 ? '1 problem' : '$problems problems',
    if (warnings > 0) warnings == 1 ? '1 warning' : '$warnings warnings',
  ];
  return parts.isEmpty ? '' : '${parts.join(' and ')}. Fix them below.';
}
