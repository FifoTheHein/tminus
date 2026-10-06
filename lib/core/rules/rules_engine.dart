import 'package:timezone/timezone.dart' as tz;

import '../model/alert.dart';
import '../model/alert_profile.dart';
import '../model/event_occurrence.dart';
import '../model/event_override.dart';
import '../model/keyword_rule.dart';
import 'resolved_occurrence.dart';
import 'rule_set.dart';

/// Returns the current instant in UTC. Injected so tests are deterministic.
typedef UtcClock = DateTime Function();

DateTime systemUtcNow() => DateTime.now().toUtc();

/// Profile resolution, quiet modes and explanations (spec §6, roadmap §4).
///
/// Resolution order, first match wins:
/// 1. occurrence override, 2. series override, 3. skip filters,
/// 4. keyword rules by position, 5. source default, 6. global default.
/// Quiet modes are applied afterwards.
class RulesEngine {
  RulesEngine({required this.zone, UtcClock? clock})
    : clock = clock ?? systemUtcNow;

  /// The device's local zone; used for "Mute today", vacation days and the
  /// "Paused until HH:mm" text.
  final tz.Location zone;
  final UtcClock clock;

  List<ResolvedOccurrence> resolveAll(
    Iterable<EventOccurrence> occurrences,
    RuleSet rules,
  ) => [for (final o in occurrences) resolve(o, rules)];

  ResolvedOccurrence resolve(EventOccurrence o, RuleSet rules) {
    final occ = rules.occurrenceOverride(o.key);
    final ser = rules.seriesOverride(o.seriesUid);
    return _decide(o, rules, occ, ser).toResolved(o);
  }

  _Decision _decide(
    EventOccurrence o,
    RuleSet rules,
    EventOverride? occ,
    EventOverride? ser,
  ) {
    if (occ != null) {
      final d = _fromOverride(
        occ,
        'this event',
        ResolutionStep.occurrenceOverride,
        o,
        rules,
        lower: () => _decide(o, rules, null, ser),
      );
      if (d != null) return d;
    }
    if (ser != null) {
      final d = _fromOverride(
        ser,
        'series',
        ResolutionStep.seriesOverride,
        o,
        rules,
        lower: () => _decide(o, rules, null, null),
      );
      if (d != null) return d;
    }
    return _skipFilter(o, rules) ?? _fromRulesAndDefaults(o, rules);
  }

  /// Null when the override decides nothing (e.g. it names a deleted profile
  /// and sets nothing else), so resolution falls through to the next step.
  _Decision? _fromOverride(
    EventOverride ov,
    String reason,
    ResolutionStep step,
    EventOccurrence o,
    RuleSet rules, {
    required _Decision Function() lower,
  }) {
    if (ov.enabled == false) {
      return _Decision(BuiltInProfiles.silent, const [], step, 'Off · $reason');
    }
    final named = ov.profileId == null ? null : rules.profile(ov.profileId!);
    if (named != null) {
      return _Decision(
        named,
        ov.customAlerts ?? named.alerts,
        step,
        '${named.name} · $reason',
      );
    }
    if (ov.customAlerts != null) {
      final base = ov.enabled == true
          ? _turnedOnProfile(o, rules)
          : lower().profile;
      return _Decision(base, ov.customAlerts!, step, 'Custom · $reason');
    }
    if (ov.enabled == true) {
      final p = _turnedOnProfile(o, rules);
      return _Decision(p, p.alerts, step, '${p.name} · $reason');
    }
    return null;
  }

  /// An event switched on without naming a profile skips the skip filters
  /// and takes the first candidate that actually has alerts: matching rules,
  /// then the source default, then the global default, then Meeting.
  AlertProfile _turnedOnProfile(EventOccurrence o, RuleSet rules) {
    final candidates = <String?>[
      for (final r in rules.rules)
        if (r.matches(o)) r.profileId,
      rules.sourceDefaults[o.sourceId],
      rules.globalDefaultProfileId,
    ];
    for (final id in candidates) {
      final p = id == null ? null : rules.profile(id);
      if (p != null && p.alerts.isNotEmpty) return p;
    }
    return BuiltInProfiles.meeting;
  }

  _Decision? _skipFilter(EventOccurrence o, RuleSet rules) {
    final f = rules.skipFilters;
    final reason = switch (o) {
      _ when f.allDay && o.allDay => 'all-day',
      _ when f.free && o.busyStatus == BusyStatus.free => 'free',
      _ when f.tentative && o.busyStatus == BusyStatus.tentative => 'tentative',
      _ when f.cancelled && o.cancelled => 'cancelled',
      _ when f.declined && o.declined => 'declined',
      _ => null,
    };
    if (reason == null) return null;
    final silent = rules.profile(BuiltInProfiles.silentId)!;
    return _Decision(
      silent,
      silent.alerts,
      ResolutionStep.skipFilter,
      '${silent.name} · $reason',
    );
  }

  _Decision _fromRulesAndDefaults(EventOccurrence o, RuleSet rules) {
    for (final r in rules.rules) {
      final p = rules.profile(r.profileId);
      if (p != null && r.matches(o)) {
        final what = r.field == RuleField.hasJoinLink
            ? 'Teams link'
            : '"${r.pattern}"';
        return _Decision(
          p,
          p.alerts,
          ResolutionStep.keywordRule,
          '${p.name} · rule: $what',
        );
      }
    }
    final sourceDefault = rules.sourceDefaults[o.sourceId];
    final sp = sourceDefault == null ? null : rules.profile(sourceDefault);
    if (sp != null) {
      return _Decision(
        sp,
        sp.alerts,
        ResolutionStep.sourceDefault,
        '${sp.name} · source default',
      );
    }
    final gp =
        rules.profile(rules.globalDefaultProfileId) ??
        rules.profile(BuiltInProfiles.defaultId)!;
    return _Decision(
      gp,
      gp.alerts,
      ResolutionStep.globalDefault,
      '${gp.name} · default',
    );
  }
}

class _Decision {
  _Decision(this.profile, this.alerts, this.step, this.explanation);

  final AlertProfile profile;
  final List<AlertSpec> alerts;
  final ResolutionStep step;
  final String explanation;

  ResolvedOccurrence toResolved(EventOccurrence o) => ResolvedOccurrence(
    occurrence: o,
    profile: profile,
    alerts: List.unmodifiable(alerts),
    explanation: explanation,
    silenced: false,
    step: step,
  );
}
