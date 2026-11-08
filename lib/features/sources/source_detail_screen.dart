import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../app/di.dart';
import '../../app/replan_scheduler.dart';
import '../../app/sync_runner.dart';
import '../../app/theme/tminus_theme.dart';
import '../../core/model/alert.dart';
import '../../core/model/alert_profile.dart';
import '../../core/model/local_date.dart';
import '../../core/model/source_config.dart';
import '../../core/model/sync_log_entry.dart';
import '../../core/platform/ui_platform.dart';
import '../../core/sources/device_calendar_api.dart';
import '../../core/sources/ics_url.dart';
import '../../core/sources/source_admin.dart';
import '../../core/sources/source_secrets.dart';
import '../../core/storage/app_database.dart';
import '../../core/storage/app_settings.dart';
import '../../core/storage/profile_repository.dart';
import '../../core/storage/settings_repository.dart';
import '../../core/sync/source_status.dart';
import '../../core/sync/sync_service.dart';
import '../../core/text/time_text.dart';
import '../common/alert_chips.dart';
import '../common/color_palette_picker.dart';
import '../common/guarded.dart';
import '../common/source_tone.dart';
import 'calendar_picker.dart';
import 'problem_card.dart';
import 'relink_dialog.dart';

/// Shown where the link would be when secure storage has none (or cannot be
/// read).
const linkMissingText = 'Link missing';

/// Shown for a phone source whose calendar is not among this phone's.
const calendarGoneText = 'Not on this phone';

/// What a failure may say in the log: a platform error's code, else the type.
/// Never the message: it can carry a feed link or a row's values.
String _tag(Object error) =>
    error is PlatformException ? error.code : '${error.runtimeType}';

/// Loads one source for its detail screen and does what its buttons ask.
///
/// The ICS link is read from secure storage only to be masked
/// ([IcsUrl.mask]); the full link is not kept, and nothing here can show it.
class SourceDetailController extends ChangeNotifier {
  SourceDetailController({
    required this.sourceId,
    required this.db,
    required this.statuses,
    required this.profiles,
    required this.settings,
    required this.admin,
    required this.secrets,
    required this.deviceCalendars,
    required this.ui,
    required this.replan,
    required this.runSync,
  });

  final String sourceId;
  final AppDatabase db;
  final SourceStatusLoader statuses;
  final ProfileRepository profiles;
  final SettingsRepository settings;
  final SourceAdmin admin;
  final SourceSecrets secrets;
  final DeviceCalendarApi deviceCalendars;
  final UiPlatform ui;
  final ReplanScheduler replan;
  final SyncRunner runSync;

  /// Where a short message for the user goes (a snackbar); set by the screen.
  /// Used when a sync that follows a change finds another one running.
  void Function(String message)? onNotice;

  SourceStatus? _status;
  List<AlertProfile> _profiles = const [];
  AlertProfile _globalProfile = BuiltInProfiles.meeting;
  String? _maskedLink;
  String? _calendarLine;
  PermissionResult? _permission;
  bool _loaded = false;
  bool _gone = false;
  bool _loadFailed = false;
  bool _syncing = false;

  /// Set when the source is being removed: nothing is loaded after that, so
  /// the screen does not flash "removed" on its way out.
  bool _closing = false;
  bool _disposed = false;
  bool _loading = false;
  bool _again = false;

  /// The link and the phone calendar are read again only when something may
  /// have changed them, not on every database write.
  bool _extrasStale = true;
  StreamSubscription<Object?>? _updates;

  /// Null until loaded, and when the source does not exist.
  SourceStatus? get status => _status;

  /// The first load has finished (successfully or not).
  bool get loaded => _loaded;

  /// There is no source with this id (it was removed).
  bool get gone => _gone;

  /// The last load failed and there is nothing to show.
  bool get loadFailed => _loadFailed;
  List<AlertProfile> get profileList => _profiles;

  /// The profile that a source without a default of its own uses.
  AlertProfile get globalProfile => _globalProfile;

  /// `outlook.office365.com/…/calendar.ics`, or [linkMissingText]; ICS only.
  String? get maskedLink => _maskedLink;

  /// The phone calendar's name and account, or [calendarGoneText]; phone only.
  String? get calendarLine => _calendarLine;

  /// What the last **Allow access** got.
  PermissionResult? get permission => _permission;
  bool get syncing => _syncing;

  void start() {
    _updates ??= db.tableUpdates().listen((_) => unawaited(reload()));
    unawaited(reload());
  }

  /// A change that arrives while a load is running makes one more load, not
  /// several.
  Future<void> reload() async {
    if (_disposed || _closing) return;
    if (_loading) {
      _again = true;
      return;
    }
    _loading = true;
    try {
      do {
        _again = false;
        await _load();
      } while (_again && !_disposed && !_closing);
    } finally {
      _loading = false;
    }
  }

  Future<void> _load() async {
    try {
      final found = await statuses.byId(sourceId);
      if (_disposed || _closing) return;
      if (found == null) {
        _status = null;
        _gone = true;
        _loadFailed = false;
        _loaded = true;
        notifyListeners();
        return;
      }
      final known = await profiles.all();
      final globalId = await settings.globalDefaultProfileId();
      if (_extrasStale) {
        _extrasStale = false;
        await _loadExtras(found.config);
      }
      if (_disposed || _closing) return;
      _status = found;
      _gone = false;
      _profiles = known;
      _globalProfile = known.firstWhere(
        (p) => p.id == globalId,
        orElse: () => BuiltInProfiles.meeting,
      );
      _loadFailed = false;
    } catch (e) {
      debugPrint('Loading a source failed (${_tag(e)})');
      if (_disposed || _closing) return;
      _loadFailed = _status == null;
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _loadExtras(SourceConfig config) async {
    switch (config.kind) {
      case SourceKind.ics:
        _maskedLink = await _readMaskedLink(config);
      case SourceKind.device:
        _calendarLine = await _readCalendarLine(config);
      case SourceKind.debug:
        break;
    }
  }

  /// The one place the link is read. It leaves here only through
  /// [IcsUrl.mask].
  Future<String> _readMaskedLink(SourceConfig config) async {
    final key = config.secureStorageKey;
    if (key == null) return linkMissingText;
    try {
      final url = await secrets.readUrl(key);
      if (url == null || url.isEmpty) return linkMissingText;
      return IcsUrl.mask(url);
    } catch (e) {
      debugPrint('Reading the saved link failed (${_tag(e)})');
      return linkMissingText;
    }
  }

  Future<String> _readCalendarLine(SourceConfig config) async {
    try {
      final all = await deviceCalendars.calendars();
      for (final calendar in all) {
        if (calendar.id != config.deviceCalendarId) continue;
        final account = calendar.accountName;
        return account == null || account.isEmpty
            ? calendar.name
            : '${calendar.name} · $account';
      }
      return calendarGoneText;
    } on PlatformException catch (e) {
      debugPrint('Reading the phone calendars failed (${e.code})');
      // Without access nobody can tell whether the calendar is still there.
      return e.code == DeviceCalendarApi.permissionDenied
          ? 'Calendar access is off'
          : calendarGoneText;
    } catch (e) {
      debugPrint('Reading the phone calendars failed (${e.runtimeType})');
      return calendarGoneText;
    }
  }

  // Edits. Each one that changes what rings asks for a re-plan: the name
  // feeds the "source default" reason, and the colour is on the meetings.

  Future<bool> rename(String name) async {
    await admin.edit(sourceId, name: name);
    replan.request();
    return true;
  }

  Future<bool> setColor(int color) async {
    await admin.edit(sourceId, color: color);
    replan.request();
    return true;
  }

  /// `null` goes back to the global default profile.
  Future<bool> setDefaultProfile(String? profileId) async {
    await admin.edit(
      sourceId,
      defaultProfileId: profileId,
      clearDefaultProfile: profileId == null,
    );
    replan.request();
    return true;
  }

  /// Throws while the source waits for its link or calendar (the switch is
  /// locked then). Switching on fetches, because the source was not fetched
  /// while it was off; switching off re-plans from the cache.
  Future<bool> setEnabled(bool on) async {
    await admin.setEnabled(sourceId, on);
    if (on) {
      await _syncQuietly();
    } else {
      replan.request();
    }
    return true;
  }

  /// **Sync now**. Throws what the sync throws.
  Future<SyncReport> syncNow() async {
    _setSyncing(true);
    try {
      final report = await runSync(SyncTrigger.manual);
      _extrasStale = true;
      return report;
    } finally {
      _setSyncing(false);
    }
  }

  /// After the dialog saved a new link: shows the new mask, and fetches.
  Future<void> afterRelink() async {
    _extrasStale = true;
    await reload();
    await _syncQuietly();
  }

  /// **Allow access**: asks for READ_CALENDAR, and syncs when it is granted.
  Future<PermissionResult> allowAccess() async {
    final result = await ui.requestPermission(UiPermission.calendar);
    _permission = result;
    if (!_disposed) notifyListeners();
    if (result == PermissionResult.granted) {
      _extrasStale = true;
      await _syncQuietly();
    }
    return result;
  }

  /// Points a restored (or orphaned) phone source at [calendar], which also
  /// switches it on, and fetches it.
  Future<bool> chooseCalendar(DeviceCalendar calendar) async {
    await admin.updateDeviceCalendar(sourceId, calendar);
    _extrasStale = true;
    _permission = null;
    await reload();
    await _syncQuietly();
    return true;
  }

  /// Removes the source (its alarms are cancelled by the re-plan).
  Future<bool> remove() async {
    _closing = true;
    try {
      await admin.delete(sourceId);
    } catch (_) {
      _closing = false;
      rethrow;
    }
    replan.request();
    return true;
  }

  /// A sync that follows a change the user made. The change is saved either
  /// way, so a sync that fails only goes to the log (by type). One that finds
  /// another sync running, and one that throws, planned nothing: the plan is
  /// asked to follow the change from the cache (choosing a calendar has wiped
  /// the old one's events, whose alarms would otherwise stay armed), and for a
  /// busy sync the user is told.
  Future<void> _syncQuietly() async {
    _setSyncing(true);
    try {
      final report = await runSync(SyncTrigger.manual);
      if (report.outcome == SyncRunOutcome.busy) {
        replan.request();
        onNotice?.call(syncBusyText);
      }
    } catch (e) {
      debugPrint('Syncing a source failed (${_tag(e)})');
      replan.request();
    } finally {
      _setSyncing(false);
    }
  }

  void _setSyncing(bool value) {
    if (_syncing == value || _disposed) return;
    _syncing = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_updates?.cancel());
    _updates = null;
    super.dispose();
  }
}

/// One source (mockup 4b): what is wrong with it and how to fix that, then its
/// name, link (masked), colour, default profile, On switch, **Sync now** and
/// **Remove**.
class SourceDetailScreen extends StatefulWidget {
  const SourceDetailScreen({super.key, required this.sourceId});

  final String sourceId;

  @override
  State<SourceDetailScreen> createState() => _SourceDetailScreenState();
}

class _SourceDetailScreenState extends State<SourceDetailScreen> {
  late SourceDetailController _controller;
  final _name = TextEditingController();
  final _nameFocus = FocusNode();

  /// The name last sent to be saved, so submitting and then losing focus
  /// saves once.
  String? _lastCommitted;

  @override
  void initState() {
    super.initState();
    _nameFocus.addListener(_onNameFocus);
    _controller = _createController();
  }

  /// Starts loading at once; the controller first notifies after its first
  /// await, never while a widget tree is being built.
  SourceDetailController _createController() {
    return SourceDetailController(
        sourceId: widget.sourceId,
        db: getIt(),
        statuses: getIt(),
        profiles: getIt(),
        settings: getIt(),
        admin: getIt(),
        secrets: getIt(),
        deviceCalendars: getIt(),
        ui: getIt(),
        replan: getIt(),
        runSync: getIt<SyncRunner>(),
      )
      ..onNotice = _say
      ..addListener(_showSavedName)
      ..start();
  }

  /// A short message for the user: a sync that follows a change found another
  /// one running.
  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void didUpdateWidget(SourceDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // go_router keeps this page, and so this State, for every `/sources/<id>`:
    // another id (a Fix notification for another source) is the same widget
    // with a new id.
    if (oldWidget.sourceId == widget.sourceId) return;
    _controller
      ..removeListener(_showSavedName)
      ..dispose();
    _name.clear();
    _lastCommitted = null;
    _controller = _createController();
  }

  @override
  void dispose() {
    _nameFocus.removeListener(_onNameFocus);
    _controller
      ..removeListener(_showSavedName)
      ..dispose();
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  /// Puts the saved name in the field, unless the user is typing in it.
  void _showSavedName() {
    final saved = _controller.status?.config.name;
    if (saved == null) return;
    // The name that was sent is the saved one now: it can be sent again.
    if (saved == _lastCommitted) _lastCommitted = null;
    if (_nameFocus.hasFocus || _name.text == saved) return;
    _name.text = saved;
  }

  void _onNameFocus() {
    if (!_nameFocus.hasFocus) unawaited(_commitName());
  }

  // Every action below that waits for something (a dialog, a sheet, a save)
  // keeps the source it started on: go_router keeps this State when another
  // source is opened (see didUpdateWidget), and `_controller` is then another
  // source's. An action that would change a source does nothing when the
  // screen has moved on to another one meanwhile.

  Future<void> _commitName() async {
    final controller = _controller;
    final id = widget.sourceId;
    final current = controller.status?.config.name;
    if (current == null) return;
    final typed = _name.text.trim();
    if (typed.isEmpty) {
      _name.text = current;
      return;
    }
    if (typed == current || typed == _lastCommitted) return;
    _lastCommitted = typed;
    final saved = await guarded<bool>(
      context,
      () => controller.rename(typed),
      failure: 'Could not save the change.',
    );
    // On another source, the field is that source's now.
    if (!mounted || widget.sourceId != id || saved == true) return;
    _lastCommitted = null;
    _name.text = controller.status?.config.name ?? current;
  }

  Future<void> _edit(Future<bool> Function() action) async {
    await guarded<bool>(context, action, failure: 'Could not save the change.');
  }

  Future<void> _syncNow() async {
    final controller = _controller;
    final id = widget.sourceId;
    final report = await guarded<SyncReport>(
      context,
      controller.syncNow,
      failure: 'Could not sync this calendar.',
    );
    if (!mounted || report == null || widget.sourceId != id) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(sourceSyncMessage(report, id))));
  }

  Future<void> _relink() async {
    final controller = _controller;
    final id = widget.sourceId;
    final saved = await showRelinkDialog(
      context,
      sourceId: id,
      sourceName: controller.status?.config.name ?? 'this calendar',
    );
    if (!mounted || !saved) return;
    // The dialog saved the link of the source it was opened for, which may not
    // be the one on screen any more: its controller still fetches it.
    await controller.afterRelink();
  }

  Future<void> _allowAccess() async {
    await guarded<PermissionResult>(
      context,
      _controller.allowAccess,
      failure: 'Could not ask for calendar access.',
    );
  }

  Future<void> _openSettings() async {
    await guarded<void>(
      context,
      () => getIt<UiPlatform>().openAppDetails(),
      failure: 'Could not open Settings.',
    );
  }

  Future<void> _chooseCalendar() async {
    final controller = _controller;
    final id = widget.sourceId;
    final taken = await guarded<Set<String>>(
      context,
      () => takenCalendarIds(exceptSourceId: id),
      failure: 'Could not read the calendars.',
    );
    if (taken == null || !mounted || widget.sourceId != id) return;
    final calendar = await showModalBottomSheet<DeviceCalendar>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ChooseCalendarSheet(taken: taken),
    );
    // The calendar was picked for the source the sheet was opened for.
    if (calendar == null || !mounted || widget.sourceId != id) return;
    await guarded<bool>(
      context,
      () => controller.chooseCalendar(calendar),
      failure: 'Could not use that calendar.',
    );
  }

  Future<void> _remove() async {
    final controller = _controller;
    final id = widget.sourceId;
    final name = controller.status?.config.name ?? 'this calendar';
    final scheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove $name?'),
        content: const Text('Its alarms are cancelled now.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirmRemove'),
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    // The dialog names the source it was opened for. If another one is on
    // screen by now, nothing is removed: the user confirmed a different one.
    if (confirmed != true || !mounted || widget.sourceId != id) return;
    final removed = await guarded<bool>(
      context,
      controller.remove,
      failure: 'Could not remove the calendar.',
    );
    // Moved on to another source while it was removed: stay there.
    if (!mounted || removed != true || widget.sourceId != id) return;
    context.go('/sources');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(_controller.status?.config.name ?? 'Source'),
        ),
        body: _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final c = _controller;
    if (c.gone) {
      return Center(
        key: const Key('sourceGone'),
        child: Padding(
          padding: const EdgeInsets.all(TMinusSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'This source was removed.',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: TMinusSpacing.md),
              FilledButton(
                onPressed: () => context.go('/sources'),
                child: const Text('Back to Sources'),
              ),
            ],
          ),
        ),
      );
    }
    final status = c.status;
    if (status == null) {
      if (!c.loadFailed) return const SizedBox.shrink();
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Couldn't load this source."),
            TextButton(
              onPressed: () => unawaited(c.reload()),
              child: const Text('Try again'),
            ),
          ],
        ),
      );
    }
    return _content(context, c, status);
  }

  Widget _content(
    BuildContext context,
    SourceDetailController c,
    SourceStatus status,
  ) {
    final config = status.config;
    final scheme = Theme.of(context).colorScheme;
    // A source that waits for its link or calendar cannot be switched on: it
    // would only fail.
    final locked = status.setup != SourceSetup.ready;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        TMinusSpacing.lg,
        TMinusSpacing.xs,
        TMinusSpacing.lg,
        TMinusSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasProblem(status.health)) ...[
            _problemCard(context, c, status),
            const SizedBox(height: TMinusSpacing.md),
          ],
          TextField(
            key: const Key('sourceNameField'),
            controller: _name,
            focusNode: _nameFocus,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => unawaited(_commitName()),
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(TMinusRadii.sm),
              ),
              labelText: 'Name',
            ),
          ),
          if (config.kind == SourceKind.ics) ...[
            const _Label('Link'),
            _ValueBox(
              icon: Icons.link,
              child: Text(
                c.maskedLink ?? linkMissingText,
                key: const Key('maskedLink'),
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(fontFamily: TMinusFonts.mono),
              ),
            ),
          ],
          if (config.kind == SourceKind.device) ...[
            const _Label('Calendar'),
            _ValueBox(
              icon: Icons.phone_android,
              child: Text(
                c.calendarLine ?? calendarGoneText,
                key: const Key('calendarLine'),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ],
          const _Label('Colour'),
          ColorPalettePicker(
            selected: config.color,
            onChanged: (color) => unawaited(_edit(() => c.setColor(color))),
          ),
          const _Label('Default profile'),
          _DefaultProfileField(
            profiles: c.profileList,
            globalProfile: c.globalProfile,
            selectedId: config.defaultProfileId,
            onChanged: (id) => unawaited(_edit(() => c.setDefaultProfile(id))),
          ),
          const SizedBox(height: TMinusSpacing.md),
          Material(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(TMinusRadii.md),
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile(
              key: const Key('enabledSwitch'),
              title: const Text('On'),
              subtitle: locked
                  ? const Text('Finish setting it up first')
                  : null,
              value: config.enabled,
              onChanged: locked
                  ? null
                  : (on) => unawaited(_edit(() => c.setEnabled(on))),
            ),
          ),
          const SizedBox(height: TMinusSpacing.xl),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('syncNow'),
                  // A source that is off is not fetched, so there is nothing
                  // to sync.
                  onPressed: config.enabled && !c.syncing
                      ? () => unawaited(_syncNow())
                      : null,
                  icon: c.syncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(c.syncing ? 'Syncing…' : 'Sync now'),
                ),
              ),
              const SizedBox(width: TMinusSpacing.md),
              Expanded(
                child: TextButton.icon(
                  key: const Key('removeSource'),
                  style: TextButton.styleFrom(foregroundColor: scheme.error),
                  onPressed: () => unawaited(_remove()),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _problemCard(
    BuildContext context,
    SourceDetailController c,
    SourceStatus status,
  ) {
    final config = status.config;
    final cause = status.latest?.outcome;
    final lastWorked = status.state?.lastSuccessUtc;
    final accessOff =
        cause == SyncOutcome.calendarAccessDenied &&
        c.permission == PermissionResult.permanentlyDenied;
    final actions = <ProblemAction>[];
    switch (config.kind) {
      case SourceKind.ics:
        actions.addAll([
          ProblemAction(
            key: const Key('pasteNewLink'),
            label: 'Paste new link',
            onPressed: () => unawaited(_relink()),
          ),
          ProblemAction(
            key: const Key('howToFindIt'),
            label: 'How to find it',
            onPressed: () => unawaited(showFindLinkSheet(context)),
          ),
        ]);
      case SourceKind.device:
        if (status.setup == SourceSetup.needsCalendar ||
            cause == SyncOutcome.calendarMissing) {
          actions.add(
            ProblemAction(
              key: const Key('chooseCalendar'),
              label: 'Choose calendar',
              onPressed: () => unawaited(_chooseCalendar()),
            ),
          );
        } else if (cause == SyncOutcome.calendarAccessDenied) {
          actions.add(
            accessOff
                ? ProblemAction(
                    key: const Key('openSettings'),
                    label: 'Open settings',
                    onPressed: () => unawaited(_openSettings()),
                  )
                : ProblemAction(
                    key: const Key('allowAccess'),
                    label: 'Allow access',
                    onPressed: () => unawaited(_allowAccess()),
                  ),
          );
        }
      case SourceKind.debug:
        break;
    }
    return ProblemCard(
      tone: toneOf(status.health),
      icon: problemIcon(status),
      title: problemTitle(status),
      body: accessOff ? calendarAccessOffText : status.line,
      detail: lastWorked == null
          ? null
          : 'Last worked ${_workedAt(lastWorked)}',
      actions: actions,
    );
  }

  /// `Sun 4 Oct 18:02`, in the device zone.
  String _workedAt(DateTime utc) {
    final zone = tz.local;
    return '${TimeText.day(LocalDate.of(utc, zone))} '
        '${TimeText.hm(utc, zone)}';
  }
}

/// A small label over a field (`Link`, `Colour`, `Default profile`).
class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(
      top: TMinusSpacing.lg,
      bottom: TMinusSpacing.xs,
    ),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

/// A read-only value on a rounded surface, after an icon.
class _ValueBox extends StatelessWidget {
  const _ValueBox({required this.icon, required this.child});

  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: TMinusSpacing.md,
        vertical: TMinusSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(TMinusRadii.md),
      ),
      child: Row(
        children: [
          Icon(icon, color: scheme.onSurfaceVariant),
          const SizedBox(width: TMinusSpacing.sm),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// `Default profile (Meeting)` first, then every profile; the closed field
/// shows the choice with its alert chips (mockup 4b).
class _DefaultProfileField extends StatelessWidget {
  const _DefaultProfileField({
    required this.profiles,
    required this.globalProfile,
    required this.selectedId,
    required this.onChanged,
  });

  /// The value of the first entry. No profile has an empty id.
  static const _global = '';

  final List<AlertProfile> profiles;
  final AlertProfile globalProfile;
  final String? selectedId;

  /// A profile id, or null for the global default.
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final known = selectedId != null && profiles.any((p) => p.id == selectedId);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(TMinusRadii.md),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: TMinusSpacing.md),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: const Key('defaultProfile'),
            isExpanded: true,
            value: known ? selectedId : _global,
            borderRadius: BorderRadius.circular(TMinusRadii.md),
            items: [
              DropdownMenuItem(
                value: _global,
                child: _ProfileLine(
                  name: 'Default profile (${globalProfile.name})',
                  alerts: globalProfile.alerts,
                ),
              ),
              for (final p in profiles)
                DropdownMenuItem(
                  value: p.id,
                  child: _ProfileLine(name: p.name, alerts: p.alerts),
                ),
            ],
            onChanged: (value) {
              if (value != null) onChanged(value == _global ? null : value);
            },
          ),
        ),
      ),
    );
  }
}

class _ProfileLine extends StatelessWidget {
  const _ProfileLine({required this.name, required this.alerts});

  final String name;
  final List<AlertSpec> alerts;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            name,
            style: textTheme.bodyLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: TMinusSpacing.sm),
        if (alerts.isEmpty)
          Text(
            'No alerts',
            style: textTheme.bodySmall?.copyWith(
              color: context.tminusColors.tertiaryText,
            ),
          )
        else
          AlertChips(alerts),
      ],
    );
  }
}

/// The sheet that **Choose calendar** opens: the phone's calendars, and the
/// tapped one is the answer.
class _ChooseCalendarSheet extends StatelessWidget {
  const _ChooseCalendarSheet({required this.taken});

  final Set<String> taken;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
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
            'Choose a calendar',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: TMinusSpacing.sm),
          CalendarPicker.pickOne(
            takenIds: taken,
            onPick: (calendar) => Navigator.of(context).pop(calendar),
          ),
        ],
      ),
    ),
  );
}
