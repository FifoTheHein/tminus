import '../../core/sync/source_status.dart';
import 'status_tone.dart';

/// The status colour a source's health is shown in (brief §5). Only health
/// and sync state use the status colours.
StatusTone toneOf(SourceHealth h) => switch (h) {
  SourceHealth.ok => StatusTone.ok,
  SourceHealth.stale || SourceHealth.warning => StatusTone.warn,
  SourceHealth.error || SourceHealth.needsSetup => StatusTone.error,
  SourceHealth.off => StatusTone.neutral,
};
