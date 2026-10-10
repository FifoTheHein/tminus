import 'package:flutter/services.dart';

/// Which notification [SyncPlatform.postSourceNotice] posts (brief §10).
enum SourceNoticeKind {
  /// "Feed stale", with Sync now.
  stale,

  /// "Feed broken", with Fix.
  broken,
}

/// Typed client for the `tminus_sync` channel (Plan 4): the device zone, the
/// cross-isolate sync lock, WorkManager and pre-alarm scheduling, the source
/// notifications and the headless engine's finish signal.
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

  /// After each sync: keeps the periodic sync, watches the phone calendar
  /// while a device source exists, and stores the pre-alarm sync times.
  Future<void> configure({
    required bool watchCalendars,
    required List<DateTime> preSyncTimes,
  }) => _channel.invokeMethod<void>('configure', {
    'watchCalendars': watchCalendars,
    'preSyncTimesMs': [for (final t in preSyncTimes) t.millisecondsSinceEpoch],
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
}
