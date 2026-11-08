import 'package:flutter/foundation.dart';

import '../../app/replan_scheduler.dart';
import '../../core/model/alert.dart';
import '../../core/model/alert_profile.dart';
import '../../core/model/event_override.dart';
import '../../core/platform/ui_platform.dart';
import '../../core/storage/override_repository.dart';
import '../../core/storage/profile_repository.dart';
import 'agenda_model.dart';

/// Which overrides the sheet edits (Plan 5 decision 9).
enum SheetScope { occurrence, series }

/// The id of the "Custom" row: an event's own alert list, with no profile. The
/// row is made up by the sheet and never stored.
const customProfileId = 'custom';

class EventSheetController extends ChangeNotifier {
  EventSheetController({
    required this.item,
    required this.overrides,
    required this.profiles,
    required this.replan,
    required this.ui,
  });

  /// The meeting as the Agenda had it when the sheet opened. The sheet never
  /// resolves it again: the Agenda reloads behind the sheet after a write.
  final AgendaItem item;
  final OverrideRepository overrides;
  final ProfileRepository profiles;
  final ReplanScheduler replan;
  final UiPlatform ui;

  SheetScope _scope = SheetScope.occurrence;
  List<AlertProfile> allProfiles = const [];

  /// False until [load] has read the profiles once.
  bool loaded = false;

  /// The override in effect in this scope when it sets a profile or custom
  /// alerts; null when there is none, or it only holds the toggle. "In effect"
  /// is the first row among the lookup targets, which is how the rules engine
  /// and `OverrideRepository.rewriteFor` read them, so a profile on a later
  /// copy key that a row on an earlier one hides is not shown.
  EventOverride? current;

  /// True once a write went through. The WHY card then says it is out of date.
  bool changed = false;

  /// Per scope: whether the override in effect when the scope was first read
  /// named a profile. Then `item.resolved.profile` is that profile and not what
  /// the rules pick, so after a reset the sheet cannot say which profile is
  /// automatic (it does not resolve again) and marks none.
  final _openedWithProfile = <SheetScope, bool>{};

  bool _disposed = false;

  SheetScope get scope => _scope;

  bool get canUseSeries => item.meeting.seriesUid != null;

  /// The radio selection: 'custom' whenever the override has an alert list of
  /// its own, because that list is what rings, whatever profile the override
  /// names (it keeps the profile for the sound). Else the override's profile,
  /// else what resolution picked when the sheet opened. Null when that is not
  /// known any more (see [_openedWithProfile]).
  String? get selectedProfileId {
    final c = current;
    if (c?.customAlerts?.isNotEmpty ?? false) return customProfileId;
    if (c?.profileId != null) return c!.profileId;
    return (_openedWithProfile[_scope] ?? false)
        ? null
        : item.resolved.profile.id;
  }

  /// The rows to list: a "Custom" row first, showing the list that rings,
  /// whenever the override has an alert list of its own, then every profile.
  List<AlertProfile> get choices {
    final own = current?.customAlerts;
    return [
      if (own != null && own.isNotEmpty)
        AlertProfile(id: customProfileId, name: 'Custom', alerts: own),
      ...allProfiles,
    ];
  }

  /// What "Customise" starts from: the event's own alerts, else the chosen
  /// profile's, else those of the profile resolution picked.
  List<AlertSpec> get customiseSeed {
    final own = current?.customAlerts;
    if (own != null && own.isNotEmpty) return own;
    final id = selectedProfileId;
    for (final p in allProfiles) {
      if (p.id == id) return p.alerts;
    }
    return item.resolved.profile.alerts;
  }

  OverrideScope _overrideScope(SheetScope s) => s == SheetScope.occurrence
      ? OverrideScope.occurrence
      : OverrideScope.series;

  /// Every target an override in scope [s] may sit on, best first (Plan 4b
  /// note). The first is where a new override goes: the meeting key, or the
  /// time source's series uid.
  List<String> _lookup(SheetScope s) => <String>{
    if (s == SheetScope.occurrence) ...[
      item.meeting.key,
      ...item.meeting.lookupKeys,
    ] else ...[
      item.meeting.seriesUid!,
      ...item.meeting.lookupSeriesUids,
    ],
  }.toList();

  Future<EventOverride?> _effective(SheetScope s) async {
    for (final target in _lookup(s)) {
      final found = await overrides.find(_overrideScope(s), target);
      if (found != null && !found.isEmpty) return found;
    }
    return null;
  }

  Future<void> load() async {
    final readFor = _scope;
    final all = await profiles.all();
    final effective = await _effective(readFor);
    allProfiles = all;
    // The user moved to the other scope while this was reading. That scope's own
    // load follows and tells the sheet.
    if (readFor != _scope) return;
    final matters =
        effective != null &&
        (effective.profileId != null ||
            (effective.customAlerts?.isNotEmpty ?? false));
    current = matters ? effective : null;
    _openedWithProfile.putIfAbsent(readFor, () => current?.profileId != null);
    loaded = true;
    _notify();
  }

  Future<void> setScope(SheetScope s) async {
    if (s == SheetScope.series && !canUseSeries) return;
    _scope = s;
    await load();
  }

  /// A profile row also clears the event's own alert list, so that the alerts
  /// the row shows are the ones that ring.
  Future<void> chooseProfile(String profileId) =>
      _rewrite((_) => (profileId: profileId, customAlerts: null));

  /// Keeps the profile the override in effect names, if any, for its sound. The
  /// sheet then marks the Custom row, not that profile.
  Future<void> setCustomAlerts(List<AlertSpec> alerts) =>
      _rewrite((e) => (profileId: e?.profileId, customAlerts: alerts));

  /// "Reset to automatic": drops profile and custom alerts in this scope on
  /// every lookup target; an Agenda toggle (`enabled`) stays.
  Future<void> reset() =>
      _rewrite((_) => (profileId: null, customAlerts: null));

  /// Every write goes through `OverrideRepository.rewriteFor`: it starts from
  /// the override in effect, writes the result on the first lookup target and
  /// deletes the others (Plan 5 decision 9). [change] says what the profile
  /// and the custom alerts become; the toggle is the effective one, wherever it
  /// sat.
  Future<void> _rewrite(
    ({String? profileId, List<AlertSpec>? customAlerts}) Function(
      EventOverride? effective,
    )
    change,
  ) async {
    // Fixed now: the user may move to the other scope while this runs.
    final overrideScope = _overrideScope(_scope);
    final lookup = _lookup(_scope);
    await overrides.rewriteFor(overrideScope, lookup, (effective) {
      final next = change(effective);
      return EventOverride(
        scope: overrideScope,
        target: lookup.first,
        profileId: next.profileId,
        customAlerts: next.customAlerts,
        enabled: effective?.enabled,
      );
    });
    changed = true;
    replan.request();
    await load();
  }

  /// False when nothing could open the link.
  Future<bool> join() async {
    final url = item.meeting.joinUrl;
    return url != null && await ui.openUrl(url);
  }

  /// A write can finish after the sheet was closed.
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
