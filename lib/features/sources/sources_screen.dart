import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../app/theme/tminus_theme.dart';
import '../../core/model/alert_profile.dart';
import '../../core/model/source_config.dart';
import '../../core/storage/app_database.dart';
import '../../core/storage/app_settings.dart';
import '../../core/storage/profile_repository.dart';
import '../../core/storage/settings_repository.dart';
import '../../core/sync/source_status.dart';
import '../common/notice_banner.dart';
import '../common/source_tone.dart';
import '../common/status_tone.dart';

/// One row of the list: the source with its health, and the name of the
/// profile its alerts come from.
class SourceListItem {
  const SourceListItem({required this.status, required this.profileName});

  final SourceStatus status;

  /// The source's own default profile, else the global default's name.
  final String profileName;
}

/// Loads the list, and again whenever anything in the database changes (a sync
/// finished, a source was edited, the app came back from a background sync).
/// Clears the restore marker once no source waits for its link or calendar.
class SourcesController extends ChangeNotifier {
  SourcesController({
    required this.db,
    required this.statuses,
    required this.appSettings,
    required this.profiles,
    required this.settings,
    this.showDebug = kDebugMode,
  });

  final AppDatabase db;
  final SourceStatusLoader statuses;
  final AppSettings appSettings;
  final ProfileRepository profiles;
  final SettingsRepository settings;

  /// Debug builds list the fast-alarms source too (spec §11).
  final bool showDebug;

  List<SourceListItem>? _items;
  bool _failed = false;
  bool _restorePending = false;
  bool _disposed = false;
  bool _loading = false;
  bool _again = false;
  StreamSubscription<Object?>? _updates;

  /// Null until the first load has finished.
  List<SourceListItem>? get items => _items;

  /// The last load failed.
  bool get failed => _failed;

  /// The banner "Restored from a backup" is up.
  bool get restorePending => _restorePending;

  void start() {
    _updates ??= db.tableUpdates().listen((_) => unawaited(reload()));
    unawaited(reload());
  }

  /// A change that arrives while a load is running makes one more load, not
  /// several.
  Future<void> reload() async {
    if (_disposed) return;
    if (_loading) {
      _again = true;
      return;
    }
    _loading = true;
    try {
      do {
        _again = false;
        await _load();
      } while (_again && !_disposed);
    } finally {
      _loading = false;
    }
  }

  Future<void> _load() async {
    try {
      // The marker is read before the sources. A restore that lands between
      // the two reads sets it after this read, so it is kept and shown on the
      // next load, and is never cleared on the strength of sources that were
      // read before the restore marked them.
      var pending = await appSettings.restorePending();
      final all = await statuses.all();
      final known = await profiles.all();
      final globalId = await settings.globalDefaultProfileId();
      if (pending && all.every((s) => s.setup == SourceSetup.ready)) {
        // Everything the restore left to do is done.
        await appSettings.setRestorePending(false);
        pending = false;
      }
      if (_disposed) return;
      final names = {for (final p in known) p.id: p.name};
      final globalName = names[globalId] ?? BuiltInProfiles.meeting.name;
      _items = [
        for (final s in all)
          if (showDebug || s.config.kind != SourceKind.debug)
            SourceListItem(
              status: s,
              profileName: names[s.config.defaultProfileId] ?? globalName,
            ),
      ];
      _restorePending = pending;
      _failed = false;
    } catch (e) {
      debugPrint('Loading the sources failed (${e.runtimeType})');
      _failed = true;
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_updates?.cancel());
    _updates = null;
    super.dispose();
  }
}

/// The Sources tab (mockup 4a): every calendar with its health, and the way to
/// add one. Links are never shown here; the detail shows one masked.
class SourcesScreen extends StatefulWidget {
  const SourcesScreen({super.key});

  @override
  State<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends State<SourcesScreen> {
  late final SourcesController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SourcesController(
      db: getIt(),
      statuses: getIt(),
      appSettings: getIt(),
      profiles: getIt(),
      settings: getIt(),
    )..start();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sources'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (_) => context.push('/settings'),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'settings', child: Text('Settings')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/sources/add'),
        icon: const Icon(Icons.add),
        label: const Text('Add source'),
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final items = _controller.items;
    if (items == null) {
      // Nothing to show before the first load, and nothing to wait for after
      // a failed one but a retry.
      if (!_controller.failed) return const SizedBox.shrink();
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Couldn't load the sources."),
            TextButton(
              onPressed: () => unawaited(_controller.reload()),
              child: const Text('Try again'),
            ),
          ],
        ),
      );
    }
    if (items.isEmpty) return const _EmptyState();
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        TMinusSpacing.lg,
        TMinusSpacing.xs,
        TMinusSpacing.lg,
        TMinusSpacing.xxl * 3,
      ),
      children: [
        if (_controller.restorePending) ...const [
          NoticeBanner(
            key: Key('restoreBanner'),
            tone: StatusTone.neutral,
            icon: Icons.restore,
            title: 'Restored from a backup',
            text: 'Re-link each feed and choose each phone calendar.',
          ),
          SizedBox(height: TMinusSpacing.sm),
        ],
        for (final item in items) ...[
          _SourceRow(key: Key('source-${item.status.config.id}'), item: item),
          const SizedBox(height: TMinusSpacing.xs),
        ],
        const _MaskedNote(),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(TMinusSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'No calendars yet.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: TMinusSpacing.md),
          FilledButton(
            onPressed: () => context.push('/sources/add'),
            child: const Text('Add a calendar'),
          ),
        ],
      ),
    ),
  );
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({super.key, required this.item});

  final SourceListItem item;

  @override
  Widget build(BuildContext context) {
    final status = item.status;
    final config = status.config;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tone = toneOf(status.health);
    // Grey while all is well; the status colours are for trouble.
    final lineColor = tone == StatusTone.ok
        ? scheme.onSurfaceVariant
        : toneColor(context, tone);
    return Material(
      color: scheme.surfaceContainer,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TMinusRadii.xl),
        side: tone == StatusTone.error
            ? BorderSide(color: scheme.error.withValues(alpha: 0.5))
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => context.push('/sources/${Uri.encodeComponent(config.id)}'),
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
                        // The calendar's own colour is data, not a theme colour.
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Color(config.color),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: TMinusSpacing.sm),
                        Flexible(
                          child: Text(
                            config.name,
                            style: textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: TMinusSpacing.xs),
                        Icon(
                          switch (config.kind) {
                            SourceKind.ics => Icons.link,
                            SourceKind.device => Icons.phone_android,
                            SourceKind.debug => Icons.bug_report_outlined,
                          },
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                    const SizedBox(height: TMinusSpacing.xs),
                    Row(
                      children: [
                        StatusDot(tone),
                        const SizedBox(width: TMinusSpacing.xs),
                        Expanded(
                          child: Text(
                            status.line,
                            style: textTheme.bodyMedium?.copyWith(
                              color: lineColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: TMinusSpacing.xxs),
                    Text(
                      'Default profile · ${item.profileName}',
                      style: textTheme.bodySmall?.copyWith(
                        color: context.tminusColors.tertiaryText,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Under the list (mockup 4a): where the links are and how they show.
class _MaskedNote extends StatelessWidget {
  const _MaskedNote();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(TMinusSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: TMinusSpacing.sm),
          Expanded(
            child: Text(
              'Links are stored on this phone only and always shown masked.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
