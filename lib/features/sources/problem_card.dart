import 'package:flutter/material.dart';

import '../../app/theme/tminus_theme.dart';
import '../../core/model/sync_log_entry.dart';
import '../../core/storage/app_settings.dart';
import '../../core/sync/outcome_severity.dart';
import '../../core/sync/source_status.dart';
import '../../core/sync/sync_service.dart';
import '../common/status_tone.dart';
import 'link_field.dart' show outlookLinkPath;

/// What a sync that found another one running says (decision 21).
const syncBusyText = 'Another sync is running. Try again in a minute.';

/// What **Sync now** and the syncs after a change tell the user about
/// [sourceId] (a snackbar). In this order: the busy text; a source the run did
/// not report (it was not fetched, so nothing can be said of it); this source's
/// own failure text; that the calendar was read but the engine could not take
/// the new plan (`applied` is null then); else `Synced.`. Every text is fixed or
/// comes from the sync, which never puts a link in one.
String sourceSyncMessage(SyncReport report, String sourceId) {
  if (report.outcome == SyncRunOutcome.busy) return syncBusyText;
  SourceSyncResult? mine;
  for (final result in report.sources) {
    if (result.sourceId == sourceId) mine = result;
  }
  if (mine == null) return 'Could not sync this calendar.';
  if (mine.outcome.severity != OutcomeSeverity.ok) {
    return mine.message ?? 'This calendar could not be read.';
  }
  if (report.applied == null) {
    return 'Synced, but the alarms could not be updated.';
  }
  return 'Synced.';
}

/// The states that get a [ProblemCard]: a warning, an error, or a source that
/// waits for its link or calendar.
bool hasProblem(SourceHealth health) => switch (health) {
  SourceHealth.warning || SourceHealth.error || SourceHealth.needsSetup => true,
  SourceHealth.ok || SourceHealth.stale || SourceHealth.off => false,
};

/// The card's title: the setup that is missing, else the latest outcome.
String problemTitle(SourceStatus status) {
  switch (status.setup) {
    case SourceSetup.needsLink:
      return "Paste this calendar's link";
    case SourceSetup.needsCalendar:
      return 'Choose this calendar on this phone';
    case SourceSetup.ready:
      break;
  }
  return switch (status.latest?.outcome) {
    SyncOutcome.httpError || SyncOutcome.linkMissing => 'Link no longer works',
    SyncOutcome.parseError => 'The feed could not be read',
    SyncOutcome.networkError ||
    SyncOutcome.serverError => "Can't reach the calendar",
    SyncOutcome.calendarAccessDenied => 'Calendar access is off',
    SyncOutcome.calendarMissing => 'Calendar was removed',
    _ => 'Something went wrong',
  };
}

IconData problemIcon(SourceStatus status) {
  if (status.setup == SourceSetup.needsLink) return Icons.link_off;
  if (status.setup == SourceSetup.needsCalendar) return Icons.event_busy;
  return switch (status.latest?.outcome) {
    SyncOutcome.httpError ||
    SyncOutcome.linkMissing ||
    SyncOutcome.parseError => Icons.link_off,
    SyncOutcome.networkError || SyncOutcome.serverError => Icons.cloud_off,
    SyncOutcome.calendarAccessDenied => Icons.lock_outline,
    SyncOutcome.calendarMissing => Icons.event_busy,
    _ => Icons.error_outline,
  };
}

/// A button on a [ProblemCard]. The first one is the filled one.
class ProblemAction {
  const ProblemAction({required this.label, this.onPressed, this.key});

  final String label;
  final VoidCallback? onPressed;
  final Key? key;
}

/// The card at the top of a source that has a problem (mockup 4b): what is
/// wrong, why, when it last worked, and what to do about it.
class ProblemCard extends StatelessWidget {
  const ProblemCard({
    super.key,
    required this.tone,
    required this.icon,
    required this.title,
    required this.body,
    this.detail,
    this.actions = const [],
  });

  final StatusTone tone;
  final IconData icon;
  final String title;

  /// The explanation: the status line, which never holds a link.
  final String body;

  /// A smaller line in the numeral type, e.g. `Last worked Sun 4 Oct 18:02`.
  final String? detail;
  final List<ProblemAction> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = context.tminusColors;
    final textTheme = Theme.of(context).textTheme;
    final (background, foreground, accent) = switch (tone) {
      StatusTone.ok => (
        colors.statusOkContainer,
        colors.onStatusOkContainer,
        colors.statusOk,
      ),
      StatusTone.warn => (
        colors.statusWarnContainer,
        colors.onStatusWarnContainer,
        colors.statusWarn,
      ),
      StatusTone.error => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        scheme.error,
      ),
      StatusTone.neutral => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        scheme.primary,
      ),
    };
    final extra = detail;
    return Container(
      key: const Key('problemCard'),
      padding: const EdgeInsets.all(TMinusSpacing.md),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(TMinusRadii.xl),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent),
          const SizedBox(width: TMinusSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.titleMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: TMinusSpacing.xxs),
                Text(
                  body,
                  style: textTheme.bodyMedium?.copyWith(color: foreground),
                ),
                if (extra != null)
                  Padding(
                    padding: const EdgeInsets.only(top: TMinusSpacing.xxs),
                    child: Text(
                      extra,
                      style: context.tminusType.time.copyWith(
                        color: foreground.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                if (actions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: TMinusSpacing.sm),
                    child: Wrap(
                      spacing: TMinusSpacing.xs,
                      runSpacing: TMinusSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final (i, action) in actions.indexed)
                          if (i == 0)
                            FilledButton(
                              key: action.key,
                              onPressed: action.onPressed,
                              style: FilledButton.styleFrom(
                                backgroundColor: accent,
                                foregroundColor: background,
                              ),
                              child: Text(action.label),
                            )
                          else
                            TextButton(
                              key: action.key,
                              onPressed: action.onPressed,
                              style: TextButton.styleFrom(
                                foregroundColor: foreground,
                              ),
                              child: Text(action.label),
                            ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// **How to find it**: brief §1's path to the ICS link in Outlook.
Future<void> showFindLinkSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (context) {
      final textTheme = Theme.of(context).textTheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            TMinusSpacing.lg,
            0,
            TMinusSpacing.lg,
            TMinusSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'How to find your calendar link',
                style: textTheme.titleLarge,
              ),
              const SizedBox(height: TMinusSpacing.md),
              Text(
                outlookLinkPath,
                key: const Key('findLinkPath'),
                style: textTheme.bodyLarge,
              ),
              const SizedBox(height: TMinusSpacing.sm),
              Text(
                'Copy the link that ends in .ics.',
                style: textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    },
  );
}
