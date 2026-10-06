import 'alert.dart';
import 'alert_profile.dart';

enum OverrideScope { occurrence, series }

/// A per-occurrence or per-series override (spec §5, §6).
///
/// [target] is an `EventOccurrence.key` for [OverrideScope.occurrence] and a
/// `seriesUid` for [OverrideScope.series]. [profileId], [customAlerts] and
/// [enabled] are independent; an override with all three null has no effect.
/// The Agenda toggle writes an occurrence override with only [enabled] set.
///
/// Named `EventOverride`, not `Override`, so it never reads like `@override`.
class EventOverride {
  const EventOverride({
    required this.scope,
    required this.target,
    this.profileId,
    this.customAlerts,
    this.enabled,
  });

  final OverrideScope scope;
  final String target;
  final String? profileId;

  /// Replaces the profile's alert list when non-empty; an empty list counts
  /// as none (decision 17).
  final List<AlertSpec>? customAlerts;

  /// true = turned on, false = turned off, null = not set.
  final bool? enabled;

  bool get isEmpty =>
      profileId == null && customAlerts == null && enabled == null;

  @override
  bool operator ==(Object other) =>
      other is EventOverride &&
      other.scope == scope &&
      other.target == target &&
      other.profileId == profileId &&
      other.enabled == enabled &&
      sameAlerts(other.customAlerts, customAlerts);

  @override
  int get hashCode => Object.hash(
    scope,
    target,
    profileId,
    enabled,
    customAlerts == null ? null : Object.hashAll(customAlerts!),
  );

  @override
  String toString() =>
      'EventOverride(${scope.name}:$target, profile: $profileId, '
      'custom: $customAlerts, enabled: $enabled)';
}
