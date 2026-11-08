import 'dart:async';
import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../app/di.dart';
import '../../app/replan_scheduler.dart';
import '../../app/theme/tminus_theme.dart';
import '../../core/model/alert_profile.dart';
import '../../core/model/keyword_rule.dart';
import '../../core/model/local_date.dart';
import '../../core/storage/profile_repository.dart';
import '../../core/storage/rule_repository.dart';
import '../../core/text/time_text.dart';
import '../agenda/agenda_model.dart';
import '../common/guarded.dart';
import '../common/ids.dart';
import 'rule_text.dart';

/// The rule editor (mockup 3d). A null [ruleId] makes a new rule.
class RuleEditorScreen extends StatelessWidget {
  const RuleEditorScreen({super.key, this.ruleId});

  final String? ruleId;

  // Keyed by the id: the router keeps one page for every rule id, so a
  // location with another id reaches the editor as an update of the same
  // widget, and the form has to start again from that rule.
  @override
  Widget build(BuildContext context) =>
      _RuleEditor(key: ValueKey(ruleId), ruleId: ruleId);
}

enum _Stage { loading, ready, gone, failed }

class _RuleEditor extends StatefulWidget {
  const _RuleEditor({super.key, required this.ruleId});

  final String? ruleId;

  @override
  State<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<_RuleEditor> {
  /// How many of the matching meetings the preview lists.
  static const _listed = 5;

  final _pattern = TextEditingController();

  _Stage _stage = _Stage.loading;

  /// The rule as stored; null for a new one.
  KeywordRule? _original;
  late String _id;
  RuleField _field = RuleField.title;
  bool _regex = false;
  String _profileId = BuiltInProfiles.quickId;
  List<AlertProfile> _profiles = const [];

  /// The meetings the Agenda shows that have not ended, read once when the
  /// editor opens. Null until they are there.
  List<AgendaItem>? _upcoming;
  bool _previewFailed = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void dispose() {
    _pattern.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    var profiles = const <AlertProfile>[];
    KeywordRule? stored;
    try {
      profiles = await getIt<ProfileRepository>().all();
      final id = widget.ruleId;
      if (id != null) {
        stored = (await getIt<RuleRepository>().all())
            .where((r) => r.id == id)
            .firstOrNull;
      }
    } catch (e) {
      debugPrint('Could not open the rule (${e.runtimeType})');
      if (mounted) setState(() => _stage = _Stage.failed);
      return;
    }
    if (!mounted) return;
    if (widget.ruleId != null && stored == null) {
      setState(() => _stage = _Stage.gone);
      return;
    }
    final existing = stored;
    setState(() {
      _profiles = profiles;
      _original = existing;
      _id = existing?.id ?? newId('r');
      if (existing != null) {
        _field = existing.field;
        _regex = existing.match == RuleMatch.regex;
        _pattern.text = existing.pattern;
        _profileId = existing.profileId;
      }
      _stage = _Stage.ready;
    });
    unawaited(_loadPreview());
  }

  Future<void> _loadPreview() async {
    try {
      final snapshot = await getIt<AgendaLoader>().load();
      if (mounted) setState(() => _upcoming = snapshot.upcoming);
    } catch (e) {
      debugPrint('Could not load the preview (${e.runtimeType})');
      if (mounted) setState(() => _previewFailed = true);
    }
  }

  /// The rule as the form describes it. A Teams-link rule has no pattern.
  KeywordRule _draft() {
    final teams = _field == RuleField.hasJoinLink;
    return KeywordRule(
      id: _id,
      position: _original?.position ?? 0,
      field: _field,
      match: !teams && _regex ? RuleMatch.regex : RuleMatch.contains,
      pattern: teams ? '' : _pattern.text,
      profileId: _profileId,
    );
  }

  bool _canSave(KeywordRule draft) =>
      _stage == _Stage.ready &&
      !_saving &&
      draft.isValid &&
      (draft.field == RuleField.hasJoinLink ||
          draft.pattern.trim().isNotEmpty) &&
      _profiles.any((p) => p.id == draft.profileId);

  Future<void> _save() async {
    final draft = _draft();
    if (!_canSave(draft)) return;
    setState(() => _saving = true);
    final saved = await guarded(context, () async {
      final repo = getIt<RuleRepository>();
      var rule = draft;
      if (_original == null) {
        // A new rule runs after the others.
        final last = (await repo.all()).fold<int>(
          -1,
          (m, r) => max(m, r.position),
        );
        rule = draft.copyWith(position: last + 1);
      }
      await repo.save(rule);
      return true;
    }, failure: 'Could not save the rule.');
    if (!mounted) return;
    if (saved == true) {
      getIt<ReplanScheduler>().request();
      _leave();
      return;
    }
    setState(() => _saving = false);
  }

  Future<void> _delete() async {
    final original = _original;
    if (original == null) return;
    final deleted = await guarded(context, () async {
      await getIt<RuleRepository>().delete(original.id);
      return true;
    }, failure: 'Could not delete the rule.');
    if (deleted != true || !mounted) return;
    getIt<ReplanScheduler>().request();
    _leave();
  }

  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/alerts');
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = _stage == _Stage.ready ? _draft() : null;
    final body = switch (_stage) {
      _Stage.loading => const SizedBox.shrink(),
      _Stage.gone => const _Notice('This rule was removed.'),
      _Stage.failed => const _Notice('Could not open the rule.'),
      _Stage.ready => _form(context, draft!),
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rule'),
        actions: [
          if (draft != null)
            Padding(
              padding: const EdgeInsets.only(right: TMinusSpacing.sm),
              child: FilledButton(
                key: const Key('saveRule'),
                onPressed: _canSave(draft) ? _save : null,
                child: const Text('Save'),
              ),
            ),
        ],
      ),
      body: body,
    );
  }

  Widget _form(BuildContext context, KeywordRule draft) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final teams = _field == RuleField.hasJoinLink;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        TMinusSpacing.md,
        TMinusSpacing.md,
        TMinusSpacing.md,
        TMinusSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'When',
              border: OutlineInputBorder(),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<RuleField>(
                key: const Key('ruleField'),
                isExpanded: true,
                isDense: true,
                value: _field,
                items: [
                  for (final f in RuleField.values)
                    DropdownMenuItem(value: f, child: Text(ruleFieldLabel(f))),
                ],
                onChanged: (f) {
                  if (f != null) setState(() => _field = f);
                },
              ),
            ),
          ),
          if (!teams) ...[
            const SizedBox(height: TMinusSpacing.xs),
            SwitchListTile(
              key: const Key('ruleRegex'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Advanced: regular expression'),
              value: _regex,
              onChanged: (on) => setState(() => _regex = on),
            ),
            const SizedBox(height: TMinusSpacing.xs),
            TextField(
              key: const Key('rulePattern'),
              controller: _pattern,
              autocorrect: false,
              enableSuggestions: false,
              style: context.tminusType.timeLarge,
              decoration: InputDecoration(
                labelText: _regex ? 'Pattern' : 'Text',
                border: const OutlineInputBorder(),
                errorText: draft.isValid
                    ? null
                    : 'This pattern is not a valid regular expression.',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: TMinusSpacing.lg),
          Text(
            'Use profile',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: TMinusSpacing.xs),
          Wrap(
            spacing: TMinusSpacing.xs,
            runSpacing: TMinusSpacing.xs,
            children: [
              for (final p in _profiles)
                ChoiceChip(
                  key: Key('ruleProfile-${p.id}'),
                  label: Text(p.name),
                  selected: p.id == _profileId,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _profileId = p.id),
                ),
            ],
          ),
          const SizedBox(height: TMinusSpacing.xl),
          _preview(context, draft),
          if (_original != null) ...[
            const SizedBox(height: TMinusSpacing.xl),
            TextButton.icon(
              key: const Key('deleteRule'),
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete rule'),
              style: TextButton.styleFrom(
                foregroundColor: scheme.error,
                minimumSize: const Size.fromHeight(TMinusSpacing.minTap),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// How many of the upcoming meetings the rule as edited matches, whatever
  /// rules run before it, and the first few of them (mockup 3d). It reads what
  /// was loaded when the editor opened, so each edit updates it at once.
  Widget _preview(BuildContext context, KeywordRule draft) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final colors = context.tminusColors;
    if (_previewFailed) {
      return Text(
        'The preview is not available.',
        style: text.bodyMedium?.copyWith(color: colors.tertiaryText),
      );
    }
    final upcoming = _upcoming;
    if (upcoming == null) return const SizedBox.shrink();
    final matches = [
      for (final item in upcoming)
        if (draft.matches(item.meeting)) item,
    ];
    final count = matches.length;
    final zone = tz.local;
    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(TMinusRadii.lg),
      child: Padding(
        padding: const EdgeInsets.all(TMinusSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.visibility_outlined, color: scheme.onSurfaceVariant),
                const SizedBox(width: TMinusSpacing.sm),
                Expanded(
                  child: Text(
                    'Matches $count upcoming ${count == 1 ? 'event' : 'events'}',
                    key: const Key('rulePreviewCount'),
                    style: text.titleMedium,
                  ),
                ),
                const SizedBox(width: TMinusSpacing.sm),
                Text(
                  'NEXT 7 DAYS',
                  style: context.tminusType.overline.copyWith(
                    color: colors.tertiaryText,
                  ),
                ),
              ],
            ),
            if (count > 0) ...[
              const SizedBox(height: TMinusSpacing.xs),
              Divider(height: 1, color: scheme.outlineVariant),
            ],
            for (final item in matches.take(_listed))
              _PreviewRow(item: item, zone: zone),
          ],
        ),
      ),
    );
  }
}

/// One matching meeting: when it starts, then its title.
class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.item, required this.zone});

  final AgendaItem item;
  final tz.Location zone;

  @override
  Widget build(BuildContext context) {
    final meeting = item.meeting;
    final day = TimeText.day(LocalDate.of(meeting.startUtc, zone));
    final when = meeting.allDay
        ? '$day all day'
        : '$day ${TimeText.hm(meeting.startUtc, zone)}';
    return Padding(
      padding: const EdgeInsets.only(top: TMinusSpacing.sm),
      child: Row(
        children: [
          Text(
            when,
            style: context.tminusType.time.copyWith(
              color: context.tminusColors.tertiaryText,
            ),
          ),
          const SizedBox(width: TMinusSpacing.sm),
          Expanded(
            child: Text(
              meeting.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }
}

/// A line of fixed text for a rule that is gone or could not be read.
class _Notice extends StatelessWidget {
  const _Notice(this.text);

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
