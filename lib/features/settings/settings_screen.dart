import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:go_router/go_router.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../app/di.dart';
import '../../app/replan_scheduler.dart';
import '../../app/theme/tminus_theme.dart';
import '../../app/theme_mode_controller.dart';
import '../../core/model/alert_profile.dart';
import '../../core/model/local_date.dart';
import '../../core/platform/ui_platform.dart';
import '../../core/rules/rules_engine.dart' show UtcClock, systemUtcNow;
import '../../core/storage/app_settings.dart';
import '../../core/storage/profile_repository.dart';
import '../../core/storage/settings_repository.dart';
import '../../core/transfer/settings_transfer.dart';
import '../common/guarded.dart';
import '../common/profile_radio_list.dart';
import '../common/section_card.dart';

// Fixed texts. A failure is only ever described by one of these: the error's
// own text can quote a profile name, a rule pattern or a file path.
const _exportFailed = 'Could not export the settings.';
const _importFailed = 'Could not import the settings.';
const _settingFailed = 'Could not change this setting.';
const _defaultProfileFailed = 'Could not change the default profile.';

/// The sentence in the dialog that asks before an import replaces anything.
/// The counts are the file's: its profiles (built-in ones included), its
/// rules, and the calendars it adds (ICS and phone ones together). Grammar
/// follows the numbers, and a file with no calendars says nothing about them.
String importConfirmText(TransferSummary s) {
  final calendars = s.icsSources + s.phoneSources;
  final head =
      "Replace your profiles, rules and settings with this file's "
      '${_count(s.profiles, 'profile')} and ${_count(s.rules, 'rule')}?';
  final adds = switch (calendars) {
    0 => '',
    1 =>
      ' It adds 1 calendar, which needs its link or calendar before it syncs.',
    _ =>
      ' It adds $calendars calendars, which need their link or calendar before '
          'they sync.',
  };
  return '$head$adds Your current calendars stay.';
}

/// The snackbar after an import. It points at Sources only when the import
/// added calendars there.
String importedText(TransferSummary s) {
  final calendars = s.icsSources + s.phoneSources;
  if (calendars == 0) return 'Settings imported.';
  return 'Settings imported. Finish setting up the new '
      '${calendars == 1 ? 'calendar' : 'calendars'} in Sources.';
}

String _count(int n, String noun) => n == 1 ? '1 $noun' : '$n ${noun}s';

/// What a failure is logged as: a platform error's code, anything else by its
/// type. Never the message.
String _kind(Object error) =>
    error is PlatformException ? error.code : '${error.runtimeType}';

/// What reading the file the user picked came to.
sealed class ImportPick {
  const ImportPick();
}

/// A file that can be imported.
final class PickedFile extends ImportPick {
  const PickedFile(this.file);

  final TransferFile file;
}

/// A file that cannot be imported, and the fixed text that says why.
final class PickProblem extends ImportPick {
  const PickProblem(this.message);

  final String message;
}

/// What the Settings screen shows and does. The screen builds one from
/// `getIt`; a test builds one on the same services, with its own clock if it
/// needs one.
///
/// Export and import are the only things that run for long, and a second one
/// must not start while one is running: an import that is confirmed twice adds
/// the file's calendars twice (Plan 5 decision 5). [runExclusive] enforces
/// that, and the Backup rows follow [busy].
class SettingsController extends ChangeNotifier {
  SettingsController({
    required this.profiles,
    required this.settings,
    required this.appSettings,
    required this.transfer,
    required this.ui,
    required this.theme,
    required this.replan,
    UtcClock? clock,
    tz.Location Function()? zone,
  }) : clock = clock ?? systemUtcNow,
       zone = zone ?? (() => tz.local);

  /// The text of a file the system dialog refused to hand over.
  static const tooLargeMessage =
      'That file is too large to be a settings file.';

  final ProfileRepository profiles;
  final SettingsRepository settings;
  final AppSettings appSettings;
  final SettingsTransfer transfer;
  final UiPlatform ui;
  final ThemeModeController theme;
  final ReplanScheduler replan;

  /// The clock and the zone that give the date in an export's file name: the
  /// date on the phone, not the date in UTC.
  final UtcClock clock;
  final tz.Location Function() zone;

  List<AlertProfile> _choices = const [];
  String _defaultId = BuiltInProfiles.defaultId;
  bool _merge = true;
  String? _version;
  bool _busy = false;
  bool _disposed = false;
  int _loads = 0;

  /// Every profile the default can be chosen from, in display order.
  List<AlertProfile> get profileChoices => _choices;

  /// The profile that is used when no rule matches. When the stored one is
  /// gone the rules engine falls back to Meeting, so that is what shows.
  AlertProfile? get defaultProfile {
    for (final id in [_defaultId, BuiltInProfiles.defaultId]) {
      for (final p in _choices) {
        if (p.id == id) return p;
      }
    }
    return null;
  }

  bool get mergeEnabled => _merge;

  /// `v1.0.0 (42)`; null until the device has answered, or when it cannot.
  String? get version => _version;

  /// True while an export or an import is running.
  bool get busy => _busy;

  /// Reads everything the screen shows. Never throws: what cannot be read
  /// keeps its last value.
  Future<void> load() async {
    final generation = ++_loads;
    try {
      final all = await profiles.all();
      final defaultId = await settings.globalDefaultProfileId();
      final merge = await appSettings.mergeEnabled();
      // A later load started while this one read; its answer is the newer.
      if (generation != _loads) return;
      _choices = all;
      _defaultId = defaultId;
      _merge = merge;
      _notify();
    } catch (e) {
      debugPrint('Loading the settings failed: ${_kind(e)}');
    }
    if (_version != null) return;
    try {
      final info = await ui.deviceInfo();
      _version = 'v${info.versionName} (${info.versionCode})';
      _notify();
    } catch (e) {
      debugPrint('Reading the app version failed: ${_kind(e)}');
    }
  }

  /// Makes [id] the default profile and re-plans. Choosing the one that is
  /// already stored writes nothing.
  Future<void> setDefaultProfile(String id) async {
    if (id == _defaultId) return;
    await settings.setGlobalDefaultProfileId(id);
    _defaultId = id;
    _notify();
    replan.request();
  }

  /// Turns merging on or off and re-plans (Plan 5 decision 15). The switch
  /// moves at once and goes back if the write fails.
  Future<void> setMerge(bool on) async {
    final before = _merge;
    _merge = on;
    _notify();
    try {
      await appSettings.setMergeEnabled(on);
    } catch (_) {
      _merge = before;
      _notify();
      rethrow;
    }
    replan.request();
  }

  /// Runs one of the Backup actions. The call is ignored when one is already
  /// running, and the Backup rows are off until it ends. The flag is set
  /// before anything is awaited, so two taps in one frame start one run.
  Future<void> runExclusive(Future<void> Function() action) async {
    if (_busy) return;
    _busy = true;
    _notify();
    try {
      await action();
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Writes the settings to a file the user names in the system save dialog.
  /// True when a file was written, false when the user backed out. A failure
  /// throws; the screen says so in fixed text.
  Future<bool> exportSettings() async {
    final now = clock();
    final text = await transfer.exportJson(nowUtc: now);
    final name = SettingsTransfer.fileName(LocalDate.of(now, zone()));
    return ui.createDocument(name: name, text: text);
  }

  /// Opens the system file dialog and reads what it hands back. Null when the
  /// user backed out. A file the system refuses as too large, and one that is
  /// not a settings file, come back as a [PickProblem] with fixed text:
  /// [SettingsTransfer.parse] is the only source of the message shown, and it
  /// only ever throws one of its two fixed texts. Any other failure throws.
  Future<ImportPick?> pickImport() async {
    final String? text;
    try {
      text = await ui.openDocument();
    } on PlatformException catch (e) {
      if (e.code != 'too_large') rethrow;
      return const PickProblem(tooLargeMessage);
    }
    if (text == null) return null;
    try {
      return PickedFile(SettingsTransfer.parse(text));
    } on FormatException catch (e) {
      return PickProblem(e.message);
    }
  }

  /// Replaces the profiles, rules and settings with [file]'s and adds its
  /// calendars, then does what [SettingsTransfer.import] leaves to its caller:
  /// the theme mode goes to the theme controller and a re-plan is requested.
  /// Nothing after the import runs when it fails. Call it through
  /// [runExclusive].
  Future<bool> importFile(TransferFile file) async {
    await transfer.import(file);
    final mode = ThemeMode.values.asNameMap()[file.themeMode];
    if (mode != null) theme.mode = mode;
    replan.request();
    await load();
    return true;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Settings (mockup 5f): the default profile, merging, the theme, export and
/// import of the settings, and what the app is. It is `/settings`, opened from
/// the Agenda's overflow menu.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final SettingsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SettingsController(
      profiles: getIt(),
      settings: getIt(),
      appSettings: getIt(),
      transfer: getIt(),
      ui: getIt(),
      theme: getIt(),
      replan: getIt(),
    );
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          TMinusSpacing.md,
          0,
          TMinusSpacing.md,
          TMinusSpacing.xxl,
        ),
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionCard(
                title: 'Alerts',
                children: [_defaultProfileTile(context)],
              ),
              SectionCard(title: 'Calendars', children: [_mergeTile(context)]),
              SectionCard(
                title: 'Appearance',
                children: [_ThemeChoice(theme: _controller.theme)],
              ),
              SectionCard(
                title: 'Backup',
                children: [_exportTile(), _importTile()],
              ),
              SectionCard(
                title: 'About & privacy',
                children: [_AboutCard(version: _controller.version)],
              ),
              if (kDebugMode)
                SectionCard(
                  title: 'Developer',
                  children: [_developerToolsTile(context)],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _defaultProfileTile(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = _controller.defaultProfile?.name;
    return ListTile(
      key: const Key('defaultProfileTile'),
      title: const Text('Default profile'),
      subtitle: const Text('Used when no rule matches'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (name != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          const SizedBox(width: TMinusSpacing.xxs),
          Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        ],
      ),
      onTap: _controller.profileChoices.isEmpty ? null : _chooseDefaultProfile,
    );
  }

  Widget _mergeTile(BuildContext context) {
    return SwitchListTile(
      key: const Key('mergeSwitch'),
      title: const Text('Merge meetings found in more than one calendar'),
      subtitle: const Text(
        'A meeting in both your Outlook feed and your phone calendar rings '
        'once.',
      ),
      value: _controller.mergeEnabled,
      onChanged: (on) => unawaited(
        guarded(
          context,
          () => _controller.setMerge(on),
          failure: _settingFailed,
        ),
      ),
    );
  }

  Widget _exportTile() {
    return ListTile(
      key: const Key('exportTile'),
      enabled: !_controller.busy,
      leading: const Icon(Icons.file_upload_outlined),
      title: const Text('Export settings'),
      subtitle: const Text('Profiles, rules and sources — without their links'),
      onTap: _export,
    );
  }

  Widget _importTile() {
    return ListTile(
      key: const Key('importTile'),
      enabled: !_controller.busy,
      leading: const Icon(Icons.file_download_outlined),
      title: const Text('Import settings'),
      subtitle: const Text("You'll paste links again after import"),
      onTap: _import,
    );
  }

  Widget _developerToolsTile(BuildContext context) {
    return ListTile(
      key: const Key('developerTools'),
      leading: const Icon(Icons.build_outlined),
      title: const Text('Developer tools'),
      trailing: Icon(
        Icons.chevron_right,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      onTap: _openDeveloperTools,
    );
  }

  Future<void> _chooseDefaultProfile() async {
    final chosen = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Default profile'),
        contentPadding: const EdgeInsets.fromLTRB(
          TMinusSpacing.sm,
          TMinusSpacing.md,
          TMinusSpacing.sm,
          TMinusSpacing.xs,
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: ProfileRadioList(
              profiles: _controller.profileChoices,
              selectedId: _controller.defaultProfile?.id,
              onSelected: (id) => Navigator.pop(dialogContext, id),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (chosen == null) return;
    if (!mounted) return;
    await guarded(
      context,
      () => _controller.setDefaultProfile(chosen),
      failure: _defaultProfileFailed,
    );
  }

  Future<void> _export() => _controller.runExclusive(() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final exported = await guarded(
      context,
      _controller.exportSettings,
      failure: _exportFailed,
    );
    // Null is a failure, which `guarded` has already said; false is the user
    // backing out of the save dialog, which says nothing.
    if (exported == true) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Settings exported.')),
      );
    }
  });

  Future<void> _import() => _controller.runExclusive(_runImport);

  Future<void> _runImport() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final pick = await guarded(
      context,
      _controller.pickImport,
      failure: _importFailed,
    );
    // Null: the user backed out, or the failure has been said.
    if (pick == null) return;
    if (!mounted) return;
    switch (pick) {
      case PickProblem(:final message):
        await _showProblem(message);
      case PickedFile(:final file):
        await _confirmAndImport(file, messenger);
    }
  }

  Future<void> _confirmAndImport(
    TransferFile file,
    ScaffoldMessengerState? messenger,
  ) async {
    final summary = SettingsTransfer.summarize(file);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Replace your settings?'),
        content: Text(importConfirmText(summary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    final done = await guarded(
      context,
      () => _controller.importFile(file),
      failure: _importFailed,
    );
    if (done == true) {
      messenger?.showSnackBar(SnackBar(content: Text(importedText(summary))));
    }
  }

  Future<void> _showProblem(String message) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Cannot import this file'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('OK'),
        ),
      ],
    ),
  );

  Future<void> _openDeveloperTools() async {
    await context.push<void>('/settings/developer');
    // The debug panels can change the merge switch behind this screen.
    if (mounted) unawaited(_controller.load());
  }
}

/// System / Dark / Light (mockup 5f). The controller keeps the choice in
/// settings, so it is also what the next start opens with.
class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({required this.theme});

  final ThemeModeController theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(TMinusSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Theme', style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: TMinusSpacing.sm),
          ListenableBuilder(
            listenable: theme,
            builder: (context, _) => SegmentedButton<ThemeMode>(
              key: const Key('themeSelector'),
              showSelectedIcon: false,
              expandedInsets: EdgeInsets.zero,
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto_outlined),
                  label: Text('System'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_outlined),
                  label: Text('Dark'),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_outlined),
                  label: Text('Light'),
                ),
              ],
              selected: {theme.mode},
              onSelectionChanged: (selection) => theme.mode = selection.single,
            ),
          ),
        ],
      ),
    );
  }
}

/// The privacy promise, then the app's name and version with the licences.
class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.version});

  final String? version;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final versionText = version;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(TMinusSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock, color: scheme.primary),
              const SizedBox(width: TMinusSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your calendar never leaves your phone.',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: TMinusSpacing.xxs),
                    Text(
                      'No account, no servers, no analytics. Feeds are '
                      'fetched directly from Outlook and stored only on this '
                      'device.',
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Divider(
          height: 1,
          thickness: 1,
          indent: TMinusSpacing.md,
          endIndent: TMinusSpacing.md,
          color: scheme.outlineVariant,
        ),
        Padding(
          padding: const EdgeInsets.all(TMinusSpacing.md),
          child: Row(
            children: [
              const _Logo(),
              const SizedBox(width: TMinusSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('T-Minus', style: textTheme.titleMedium),
                    if (versionText != null)
                      Text(
                        versionText,
                        key: const Key('appVersion'),
                        style: context.tminusType.time.copyWith(
                          color: context.tminusColors.tertiaryText,
                        ),
                      ),
                  ],
                ),
              ),
              TextButton(
                key: const Key('licencesButton'),
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: 'T-Minus',
                ),
                child: const Text('Licences'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The T− mark: a ring round the name's first letter and a minus.
class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: scheme.primary, width: 2),
        ),
        child: Text(
          'T−',
          style: context.tminusType.time.copyWith(
            color: scheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
