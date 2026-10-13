import 'dart:async';

import 'package:flutter/services.dart';

/// Which notification [SyncPlatform.postSourceNotice] posts (brief §10).
enum SourceNoticeKind {
  /// "Feed stale", with Sync now.
  stale,

  /// "Feed broken", with Fix.
  broken,
}

/// A quick-settings tile tap waiting in Kotlin (Plan 5 decision 3).
class QuietRequest {
  const QuietRequest({required this.mute, required this.atUtc});

  /// True: Mute today. False: end any quiet mode.
  final bool mute;
  final DateTime atUtc;
}

/// Typed client for the `tminus_sync` channel (Plan 4): the device zone, the
/// cross-isolate sync lock, WorkManager and pre-alarm scheduling, the source
/// notifications and the headless engine's finish signal. Plan 5 adds the
/// installation id, the tile's waiting request and the signal that tells the
/// UI a background sync finished.
class SyncPlatform {
  SyncPlatform({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'tminus_sync';

  final MethodChannel _channel;

  /// The device's IANA zone, e.g. `Africa/Johannesburg`. Null only if the
  /// native side gave no answer.
  Future<String?> deviceZone() => _channel.invokeMethod<String>('deviceZone');

  /// True when [owner] now holds the lock for [lease].
  Future<bool> acquireLock(String owner, Duration lease) async =>
      await _channel.invokeMethod<bool>('acquireLock', {
        'owner': owner,
        'leaseMs': lease.inMilliseconds,
      }) ??
      false;

  Future<void> releaseLock(String owner) =>
      _channel.invokeMethod<void>('releaseLock', {'owner': owner});

  /// This installation's id, created on first use and never backed up
  /// (Plan 5 decision 4). On every engine, so the headless sync can check it.
  Future<String> installId() async =>
      (await _channel.invokeMethod<String>('installId'))!;

  /// The tile's waiting request, removed from Kotlin as it is read; null when
  /// there is none, or when the answer is not a map with an `action` of `mute`
  /// or `end` and an integer `atMs` (the request is dropped rather than
  /// failing the sync that asked). The reply is read as a plain object and
  /// checked here: asking the channel for a typed map throws on any other
  /// shape.
  Future<QuietRequest?> takeQuietRequest() async {
    final raw = await _channel.invokeMethod<Object?>('takeQuietRequest');
    if (raw is! Map) return null;
    final action = raw['action'];
    final atMs = raw['atMs'];
    if ((action != 'mute' && action != 'end') || atMs is! int) return null;
    return QuietRequest(
      mute: action == 'mute',
      atUtc: DateTime.fromMillisecondsSinceEpoch(atMs, isUtc: true),
    );
  }

  /// After each sync: keeps the periodic sync, watches the phone calendar
  /// while a device source exists, stores the pre-alarm sync times and tells
  /// the quick-settings tile when quiet ends and what to show.
  Future<void> configure({
    required bool watchCalendars,
    required List<DateTime> preSyncTimes,
    DateTime? quietUntil,
    String? quietText,
  }) => _channel.invokeMethod<void>('configure', {
    'watchCalendars': watchCalendars,
    'preSyncTimesMs': [for (final t in preSyncTimes) t.millisecondsSinceEpoch],
    'quietUntilMs': quietUntil?.millisecondsSinceEpoch,
    'quietText': quietText,
  });

  Future<void> postSourceNotice({
    required SourceNoticeKind kind,
    required String sourceId,
    required String title,
    required String text,
  }) => _channel.invokeMethod<void>('postSourceNotice', {
    'kind': kind.name,
    'sourceId': sourceId,
    'title': title,
    'text': text,
  });

  Future<void> cancelSourceNotice({
    required SourceNoticeKind kind,
    required String sourceId,
  }) => _channel.invokeMethod<void>('cancelSourceNotice', {
    'kind': kind.name,
    'sourceId': sourceId,
  });

  /// Queues a background sync through WorkManager, which runs it in a
  /// headless engine (debug panel, device checks). [trigger] is a
  /// `SyncTrigger` name.
  Future<void> requestSync(String trigger) =>
      _channel.invokeMethod<void>('requestSync', {'trigger': trigger});

  /// Headless engine only: tells `HeadlessFlutterRunner` the outcome.
  Future<void> finished(String outcome) =>
      _channel.invokeMethod<void>('finished', {'outcome': outcome});

  StreamController<String>? _finished;

  /// The trigger name each time a headless sync finishes while this engine
  /// is the UI's (Plan 5 decision 6). The UI then re-reads the database,
  /// whose watchers never see another isolate's writes.
  Stream<String> get backgroundSyncFinished {
    final c = _finished ??= StreamController<String>.broadcast(
      onListen: () => _channel.setMethodCallHandler(_onCall),
      onCancel: () => _channel.setMethodCallHandler(null),
    );
    return c.stream;
  }

  Future<Object?> _onCall(MethodCall call) async {
    if (call.method == 'syncFinished') {
      final args = (call.arguments as Map?)?.cast<String, Object?>();
      _finished?.add(args?['trigger'] as String? ?? 'unknown');
    }
    return null;
  }
}
