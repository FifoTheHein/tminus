import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../app/replan_scheduler.dart';
import '../../app/theme/tminus_theme.dart';
import '../../core/model/alert.dart';
import '../../core/model/alert_profile.dart';
import '../../core/platform/ui_platform.dart';
import '../../core/storage/profile_repository.dart';
import '../common/alert_list_editor.dart';
import '../common/guarded.dart';
import '../common/ids.dart';
import '../common/section_card.dart';

/// The profile editor (mockup 3b). A null [profileId] makes a new profile.
class ProfileEditorScreen extends StatelessWidget {
  const ProfileEditorScreen({super.key, this.profileId});

  final String? profileId;

  // Keyed by the id: the router keeps one page for every profile id, so a
  // location with another id reaches the editor as an update of the same
  // widget, and the form has to start again from that profile.
  @override
  Widget build(BuildContext context) =>
      _ProfileEditor(key: ValueKey(profileId), profileId: profileId);
}

enum _Stage { loading, ready, gone, failed }

class _ProfileEditor extends StatefulWidget {
  const _ProfileEditor({super.key, required this.profileId});

  final String? profileId;

  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  /// The ring timeouts the dropdown offers, in minutes. A stored timeout that
  /// is none of these is listed as well (an imported file can carry any value
  /// from 1 to 3600 seconds), so the dropdown always has the value it shows.
  static const _timeoutMinutes = [1, 2, 3, 5];
  static const _shortestTimeout = Duration(seconds: 1);
  static const _longestTimeout = Duration(hours: 1);

  final _name = TextEditingController();

  _Stage _stage = _Stage.loading;

  /// The profile as stored; null for a new one.
  AlertProfile? _original;
  late String _id;
  List<AlertSpec> _alerts = const [];
  String? _toneUri;
  String _toneTitle = UiPlatform.defaultToneTitle;
  bool _vibrate = true;
  bool _gradualVolume = true;
  Duration _ringTimeout = const Duration(minutes: 2);
  bool _ringsInQuietMode = false;

  /// The other profiles' names, trimmed and in lower case, for the uniqueness
  /// check.
  Set<String> _otherNames = const {};
  bool _nameTouched = false;
  bool _saving = false;

  bool get _builtIn => _original?.builtIn ?? false;
  bool get _silent => _id == BuiltInProfiles.silentId;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  static String _key(String name) => name.trim().toLowerCase();

  static Duration _clampTimeout(Duration d) {
    if (d < _shortestTimeout) return _shortestTimeout;
    if (d > _longestTimeout) return _longestTimeout;
    return d;
  }

  Future<void> _open() async {
    final List<AlertProfile> all;
    try {
      all = await getIt<ProfileRepository>().all();
    } catch (e) {
      debugPrint('Could not open the profile (${e.runtimeType})');
      if (mounted) setState(() => _stage = _Stage.failed);
      return;
    }
    if (!mounted) return;
    final id = widget.profileId;
    final existing = id == null
        ? null
        : all.where((p) => p.id == id).firstOrNull;
    if (id != null && existing == null) {
      setState(() => _stage = _Stage.gone);
      return;
    }
    final base =
        existing ??
        AlertProfile(
          id: newId('p'),
          name: '',
          alerts: const [
            AlertSpec(10, AlertStrength.headsUp),
            AlertSpec(1, AlertStrength.alarm),
          ],
        );
    setState(() {
      _original = existing;
      _id = base.id;
      _name.text = base.name;
      _alerts = base.alerts;
      _toneUri = base.sound.toneUri;
      _vibrate = base.sound.vibrate;
      _gradualVolume = base.sound.gradualVolume;
      _ringTimeout = _clampTimeout(base.sound.ringTimeout);
      _ringsInQuietMode = base.ringsInQuietMode;
      _otherNames = {
        for (final p in all)
          if (p.id != base.id) _key(p.name),
      };
      _stage = _Stage.ready;
    });
    unawaited(_loadToneTitle(base.sound.toneUri));
  }

  Future<void> _loadToneTitle(String? uri) async {
    String title;
    try {
      title = await getIt<UiPlatform>().toneTitle(uri);
    } on PlatformException catch (e) {
      debugPrint('Could not read the tone name (${e.code})');
      title = UiPlatform.defaultToneTitle;
    } catch (e) {
      debugPrint('Could not read the tone name (${e.runtimeType})');
      title = UiPlatform.defaultToneTitle;
    }
    // A tone picked in the meantime has its own title.
    if (mounted && _toneUri == uri) setState(() => _toneTitle = title);
  }

  Future<void> _pickTone() async {
    final picked = await guarded<PickedTone?>(
      context,
      () => getIt<UiPlatform>().pickAlarmTone(current: _toneUri),
      failure: 'Could not open the tone picker.',
    );
    // Null: the user backed out, or the picker could not open. Either way
    // nothing changes.
    if (picked == null || !mounted) return;
    setState(() {
      _toneUri = picked.uri;
      _toneTitle = picked.title;
    });
  }

  String? get _nameError {
    if (_builtIn) return null;
    final name = _key(_name.text);
    if (_nameTouched && name.isEmpty) return 'Enter a name.';
    if (_otherNames.contains(name)) return 'Another profile has this name.';
    return null;
  }

  bool get _canSave {
    if (_stage != _Stage.ready || _saving) return false;
    if (_builtIn) return true;
    final name = _key(_name.text);
    return name.isNotEmpty && !_otherNames.contains(name);
  }

  AlertProfile _draft() {
    final original = _original;
    return AlertProfile(
      id: _id,
      // A built-in keeps its name, whatever the field holds.
      name: original != null && original.builtIn
          ? original.name
          : _name.text.trim(),
      alerts: _silent ? const [] : _alerts,
      sound: SoundSettings(
        toneUri: _toneUri,
        vibrate: _vibrate,
        gradualVolume: _gradualVolume,
        ringTimeout: _ringTimeout,
      ),
      ringsInQuietMode: !_silent && _ringsInQuietMode,
      builtIn: original?.builtIn ?? false,
    );
  }

  /// False when another profile has the name by now.
  Future<bool> _store() async {
    final repo = getIt<ProfileRepository>();
    final profile = _draft();
    if (!profile.builtIn) {
      final others = {
        for (final p in await repo.all())
          if (p.id != profile.id) _key(p.name),
      };
      _otherNames = others;
      if (others.contains(_key(profile.name))) return false;
    }
    await repo.save(profile);
    return true;
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    final saved = await guarded(
      context,
      _store,
      failure: 'Could not save the profile.',
    );
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
    if (original == null || original.builtIn) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${original.name}?'),
        content: const Text(
          'Rules that use it are deleted, and calendars and events that use '
          'it go back to the default.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('confirmDeleteProfile'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final deleted = await guarded(context, () async {
      await getIt<ProfileRepository>().delete(original.id);
      return true;
    }, failure: 'Could not delete the profile.');
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

  /// The timeouts to choose from: the offered ones and the stored one.
  List<Duration> get _timeoutChoices {
    final offered = [for (final m in _timeoutMinutes) Duration(minutes: m)];
    if (offered.contains(_ringTimeout)) return offered;
    return [...offered, _ringTimeout]..sort();
  }

  static String _timeoutLabel(Duration d) =>
      d.inSeconds % 60 == 0 ? '${d.inMinutes} min' : '${d.inSeconds} s';

  @override
  Widget build(BuildContext context) {
    final body = switch (_stage) {
      _Stage.loading => const SizedBox.shrink(),
      _Stage.gone => const _Notice('This profile was removed.'),
      _Stage.failed => const _Notice('Could not open the profile.'),
      _Stage.ready => _form(context),
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          if (_stage == _Stage.ready)
            Padding(
              padding: const EdgeInsets.only(right: TMinusSpacing.sm),
              child: FilledButton(
                key: const Key('saveProfile'),
                onPressed: _canSave ? _save : null,
                child: const Text('Save'),
              ),
            ),
        ],
      ),
      body: body,
    );
  }

  Widget _form(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final colors = context.tminusColors;
    final original = _original;
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
          TextField(
            key: const Key('profileName'),
            controller: _name,
            readOnly: _builtIn,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Name',
              helperText: _builtIn
                  ? "Built-in profile names can't change"
                  : null,
              errorText: _nameError,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() => _nameTouched = true),
          ),
          const SizedBox(height: TMinusSpacing.xl),
          Row(
            children: [
              Text('Alerts', style: text.titleSmall),
              if (!_silent) ...[
                const SizedBox(width: TMinusSpacing.sm),
                Expanded(
                  child: Text(
                    'minutes before start',
                    textAlign: TextAlign.end,
                    style: text.bodySmall?.copyWith(color: colors.tertiaryText),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: TMinusSpacing.xs),
          if (_silent)
            Text(
              'Silent never rings.',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            )
          else
            AlertListEditor(
              alerts: _alerts,
              onChanged: (alerts) => setState(() => _alerts = alerts),
            ),
          const SizedBox(height: TMinusSpacing.xl),
          SectionCard(
            title: 'Sound',
            children: [
              ListTile(
                key: const Key('profileTone'),
                title: const Text('Tone'),
                subtitle: Text(_toneTitle),
                trailing: Icon(
                  Icons.chevron_right,
                  color: scheme.onSurfaceVariant,
                ),
                onTap: _pickTone,
              ),
              SwitchListTile(
                key: const Key('profileVibrate'),
                title: const Text('Vibrate'),
                value: _vibrate,
                onChanged: (on) => setState(() => _vibrate = on),
              ),
              SwitchListTile(
                key: const Key('profileGradual'),
                title: const Text('Gradual volume'),
                value: _gradualVolume,
                onChanged: (on) => setState(() => _gradualVolume = on),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: TMinusSpacing.md,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Ring timeout', style: text.bodyLarge),
                      ),
                      DropdownButtonHideUnderline(
                        child: DropdownButton<Duration>(
                          key: const Key('ringTimeout'),
                          value: _ringTimeout,
                          items: [
                            for (final d in _timeoutChoices)
                              DropdownMenuItem(
                                value: d,
                                child: Text(_timeoutLabel(d)),
                              ),
                          ],
                          onChanged: (d) {
                            if (d != null) setState(() => _ringTimeout = d);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (!_silent) ...[
            const SizedBox(height: TMinusSpacing.md),
            SectionCard(
              children: [
                SwitchListTile(
                  key: const Key('ringsInQuietMode'),
                  title: const Text('Rings during quiet mode'),
                  value: _ringsInQuietMode,
                  onChanged: (on) => setState(() => _ringsInQuietMode = on),
                ),
              ],
            ),
          ],
          if (original != null && !original.builtIn) ...[
            const SizedBox(height: TMinusSpacing.xl),
            TextButton.icon(
              key: const Key('deleteProfile'),
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete profile'),
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
}

/// A line of fixed text for a profile that is gone or could not be read.
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
