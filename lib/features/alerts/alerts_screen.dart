import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../app/replan_scheduler.dart';
import '../../app/theme/tminus_theme.dart';
import '../../core/model/alert_profile.dart';
import '../../core/model/keyword_rule.dart';
import '../../core/model/skip_filters.dart';
import '../../core/storage/profile_repository.dart';
import '../../core/storage/rule_repository.dart';
import '../../core/storage/settings_repository.dart';
import '../common/alert_chips.dart';
import '../common/guarded.dart';
import '../common/section_card.dart';
import 'rule_text.dart';

/// Room under the last row, so the floating button never covers it.
const _listBottomInset = 96.0;

/// What the Alerts tab shows, kept current from the database.
///
/// A change the user makes here (a switch, a dragged rule) is shown at once and
/// then confirmed by the database's own answer. If the write fails the stored
/// value is shown again.
class AlertsController extends ChangeNotifier {
  AlertsController({
    required this.profiles,
    required this.rules,
    required this.settings,
    required this.replan,
  }) {
    _subscriptions.addAll([
      profiles.watchAll().listen(
        (v) => _set(() => _profiles = v),
        onError: _onError,
      ),
      rules.watchAll().listen((v) => _set(() => _rules = v), onError: _onError),
      settings
          .watchString(SettingsRepository.globalDefaultKey)
          .listen(
            (v) => _set(() {
              _defaultId = v;
              _defaultSeen = true;
            }),
            onError: _onError,
          ),
      settings.watchSkipFilters().listen(
        (v) => _set(() => _skip = v),
        onError: _onError,
      ),
    ]);
  }

  final ProfileRepository profiles;
  final RuleRepository rules;
  final SettingsRepository settings;
  final ReplanScheduler replan;

  final _subscriptions = <StreamSubscription<Object?>>[];
  List<AlertProfile>? _profiles;
  List<KeywordRule>? _rules;
  SkipFilters? _skip;
  String? _defaultId;
  bool _defaultSeen = false;
  bool _failed = false;
  bool _disposed = false;

  /// Every list has arrived at least once.
  bool get loaded =>
      _profiles != null && _rules != null && _skip != null && _defaultSeen;

  /// A read from the database failed. The tabs then say so.
  bool get failed => _failed;

  /// In display order: the built-ins, then the user's own.
  List<AlertProfile> get profileList => _profiles ?? const [];

  /// In the order the rules run.
  List<KeywordRule> get ruleList => _rules ?? const [];

  SkipFilters get skipFilters => _skip ?? const SkipFilters();

  /// The profile that events with no other choice use. Meeting until the user
  /// picks another one in Settings.
  String get defaultProfileId => _defaultId ?? BuiltInProfiles.defaultId;

  /// The name a rule row shows for the profile the rule picks. A profile whose
  /// row cannot be read is not in the list.
  String profileName(String id) {
    for (final p in profileList) {
      if (p.id == id) return p.name;
    }
    return 'Unknown profile';
  }

  int rulesUsing(String profileId) =>
      ruleList.where((r) => r.profileId == profileId).length;

  /// Changes the skip filters and asks for a re-plan.
  Future<void> setSkipFilters(
    SkipFilters Function(SkipFilters current) change,
  ) async {
    final next = change(_skip ?? await settings.skipFilters());
    _set(() => _skip = next);
    try {
      await settings.setSkipFilters(next);
    } catch (_) {
      final stored = await settings.skipFilters();
      _set(() => _skip = stored);
      rethrow;
    }
    replan.request();
  }

  /// Moves the rule at [oldIndex] to [newIndex], the place it ends up at (not
  /// the place `ReorderableListView` counts before the rule is taken out), then
  /// saves the order and asks for a re-plan.
  Future<void> moveRule(int oldIndex, int newIndex) async {
    final current = _rules;
    if (current == null ||
        oldIndex == newIndex ||
        oldIndex < 0 ||
        newIndex < 0 ||
        oldIndex >= current.length ||
        newIndex >= current.length) {
      return;
    }
    final next = [...current];
    next.insert(newIndex, next.removeAt(oldIndex));
    _set(() => _rules = next);
    try {
      await rules.reorder([for (final r in next) r.id]);
    } catch (_) {
      final stored = await rules.all();
      _set(() => _rules = stored);
      rethrow;
    }
    replan.request();
  }

  void _set(void Function() change) {
    if (_disposed) return;
    change();
    notifyListeners();
  }

  void _onError(Object error) {
    // The type only: a message can carry a row's values.
    debugPrint(
      'The Alerts tab could not read the database (${error.runtimeType})',
    );
    _set(() => _failed = true);
  }

  @override
  void dispose() {
    _disposed = true;
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    super.dispose();
  }
}

enum _AlertsMenu { settings }

/// The Alerts tab: the alert profiles and the rules that pick them (mockups 3a
/// and 3c).
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final AlertsController _controller;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _controller = AlertsController(
      profiles: getIt(),
      rules: getIt(),
      settings: getIt(),
      replan: getIt(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts'),
        actions: [
          PopupMenuButton<_AlertsMenu>(
            key: const Key('alertsMenu'),
            onSelected: (_) => context.push('/settings'),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _AlertsMenu.settings,
                child: Text('Settings'),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Profiles'),
            Tab(text: 'Rules'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _ProfilesTab(controller: _controller),
          _RulesTab(controller: _controller),
        ],
      ),
      floatingActionButton: ListenableBuilder(
        listenable: _tabs,
        builder: (context, _) => _tabs.index == 0
            ? FloatingActionButton.extended(
                key: const Key('newProfile'),
                heroTag: null,
                onPressed: () => context.push('/alerts/profiles/new'),
                icon: const Icon(Icons.add),
                label: const Text('New profile'),
              )
            : FloatingActionButton.extended(
                key: const Key('newRule'),
                heroTag: null,
                onPressed: () => context.push('/alerts/rules/new'),
                icon: const Icon(Icons.add),
                label: const Text('New rule'),
              ),
      ),
    );
  }
}

class _ProfilesTab extends StatelessWidget {
  const _ProfilesTab({required this.controller});

  final AlertsController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.failed) {
          return const _LoadFailed('Could not load the profiles.');
        }
        if (!controller.loaded) return const SizedBox.shrink();
        return ListView(
          primary: false,
          padding: const EdgeInsets.fromLTRB(
            TMinusSpacing.sm,
            TMinusSpacing.sm,
            TMinusSpacing.sm,
            _listBottomInset,
          ),
          children: [
            for (final p in controller.profileList)
              _ProfileRow(
                profile: p,
                isDefault: p.id == controller.defaultProfileId,
                rulesUsing: controller.rulesUsing(p.id),
              ),
          ],
        );
      },
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.profile,
    required this.isDefault,
    required this.rulesUsing,
  });

  final AlertProfile profile;
  final bool isDefault;
  final int rulesUsing;

  /// "Used by 2 rules · rings in quiet mode" (mockup 3a). Null when there is
  /// nothing to say.
  String? get _detail {
    final silent = profile.id == BuiltInProfiles.silentId;
    final parts = [
      if (!profile.builtIn) 'Your profile',
      if (silent) 'Shown in Agenda only',
      if (rulesUsing > 0)
        'Used by $rulesUsing ${rulesUsing == 1 ? 'rule' : 'rules'}',
      if (profile.ringsInQuietMode && !silent) 'Rings in quiet mode',
    ];
    if (parts.isEmpty) return null;
    return [
      for (final (i, part) in parts.indexed)
        i == 0 ? part : '${part[0].toLowerCase()}${part.substring(1)}',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final detail = _detail;
    return Padding(
      padding: const EdgeInsets.only(bottom: TMinusSpacing.xs),
      child: Material(
        key: Key('profileRow-${profile.id}'),
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(TMinusRadii.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(
            '/alerts/profiles/${Uri.encodeComponent(profile.id)}',
          ),
          child: Padding(
            padding: const EdgeInsets.all(TMinusSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              profile.name,
                              style: text.titleMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isDefault) ...[
                            const SizedBox(width: TMinusSpacing.xs),
                            const _DefaultBadge(),
                          ],
                        ],
                      ),
                      const SizedBox(height: TMinusSpacing.xs),
                      if (profile.alerts.isEmpty)
                        Text(
                          'No alerts',
                          style: text.bodyMedium?.copyWith(
                            color: context.tminusColors.tertiaryText,
                          ),
                        )
                      else
                        AlertChips(profile.alerts),
                      if (detail != null) ...[
                        const SizedBox(height: TMinusSpacing.xs),
                        Text(
                          detail,
                          style: text.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The small "Default" label beside the global default profile's name.
class _DefaultBadge extends StatelessWidget {
  const _DefaultBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('defaultBadge'),
      padding: const EdgeInsets.symmetric(
        horizontal: TMinusSpacing.xs,
        vertical: TMinusSpacing.xxs / 2,
      ),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(TMinusRadii.sm),
      ),
      child: Text(
        'Default',
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: scheme.onSecondaryContainer),
      ),
    );
  }
}

class _RulesTab extends StatelessWidget {
  const _RulesTab({required this.controller});

  final AlertsController controller;

  Future<void> _move(BuildContext context, int oldIndex, int newIndex) async {
    await guarded(
      context,
      () => controller.moveRule(oldIndex, newIndex),
      failure: 'Could not save the new order.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.failed) {
          return const _LoadFailed('Could not load the rules.');
        }
        if (!controller.loaded) return const SizedBox.shrink();
        final rules = controller.ruleList;
        return ReorderableListView.builder(
          primary: false,
          padding: const EdgeInsets.fromLTRB(
            TMinusSpacing.sm,
            TMinusSpacing.sm,
            TMinusSpacing.sm,
            _listBottomInset,
          ),
          buildDefaultDragHandles: false,
          header: _RulesHeader(controller: controller),
          footer: rules.isEmpty ? const _NoRules() : null,
          itemCount: rules.length,
          onReorderItem: (oldIndex, newIndex) =>
              _move(context, oldIndex, newIndex),
          itemBuilder: (context, i) => _RuleRow(
            key: ValueKey('rule-${rules[i].id}'),
            index: i,
            rule: rules[i],
            profileName: controller.profileName(rules[i].profileId),
          ),
        );
      },
    );
  }
}

/// The skip filters, then the title of the rule list (mockup 3c).
class _RulesHeader extends StatelessWidget {
  const _RulesHeader({required this.controller});

  final AlertsController controller;

  @override
  Widget build(BuildContext context) {
    final filters = controller.skipFilters;
    final text = Theme.of(context).textTheme;

    Widget filter(
      String key,
      String title,
      bool value,
      SkipFilters Function(SkipFilters current, bool on) change, {
      String? subtitle,
    }) {
      return SwitchListTile(
        key: Key(key),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        value: value,
        onChanged: (on) => guarded(
          context,
          () => controller.setSkipFilters((current) => change(current, on)),
          failure: 'Could not save the change.',
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: 'Skip these events',
          children: [
            filter(
              'skip-allDay',
              'All-day events',
              filters.allDay,
              (current, on) => current.copyWith(allDay: on),
            ),
            filter(
              'skip-free',
              'Free',
              filters.free,
              (current, on) => current.copyWith(free: on),
            ),
            filter(
              'skip-tentative',
              'Tentative',
              filters.tentative,
              (current, on) => current.copyWith(tentative: on),
            ),
            filter(
              'skip-cancelled',
              'Cancelled',
              filters.cancelled,
              (current, on) => current.copyWith(cancelled: on),
            ),
            filter(
              'skip-declined',
              'Declined',
              filters.declined,
              (current, on) => current.copyWith(declined: on),
              subtitle: 'Phone calendars only',
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            TMinusSpacing.xs,
            TMinusSpacing.xl,
            TMinusSpacing.xs,
            TMinusSpacing.xs,
          ),
          child: Row(
            children: [
              Text('Keyword rules', style: text.titleSmall),
              const SizedBox(width: TMinusSpacing.sm),
              Expanded(
                child: Text(
                  'First match wins · drag to reorder',
                  textAlign: TextAlign.end,
                  style: text.bodySmall?.copyWith(
                    color: context.tminusColors.tertiaryText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One rule as a sentence, with its place in the order and a drag handle.
class _RuleRow extends StatelessWidget {
  const _RuleRow({
    super.key,
    required this.index,
    required this.rule,
    required this.profileName,
  });

  final int index;
  final KeywordRule rule;
  final String profileName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: TMinusSpacing.xs),
      child: Material(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(TMinusRadii.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () =>
              context.push('/alerts/rules/${Uri.encodeComponent(rule.id)}'),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  // Opaque, so that the whole square starts a drag and not only
                  // the glyph in the middle of it.
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      key: Key('ruleHandle-${rule.id}'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: TMinusSpacing.sm,
                        vertical: TMinusSpacing.md,
                      ),
                      child: Icon(
                        Icons.drag_indicator,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 24),
                  child: Text(
                    '${index + 1}',
                    style: context.tminusType.time.copyWith(
                      color: context.tminusColors.tertiaryText,
                    ),
                  ),
                ),
                const SizedBox(width: TMinusSpacing.xs),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: TMinusSpacing.xs,
                    ),
                    child: Text(
                      ruleText(rule, profileName),
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                const SizedBox(width: TMinusSpacing.xs),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoRules extends StatelessWidget {
  const _NoRules();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(TMinusSpacing.md),
      child: Text(
        'No rules yet. Rules pick a profile by title, location, organiser or '
        'Teams link.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: context.tminusColors.tertiaryText),
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(TMinusSpacing.xl),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}
