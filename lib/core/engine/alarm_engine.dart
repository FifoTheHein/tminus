import 'dart:async';

import 'package:flutter/services.dart';

import '../model/alert.dart';
import '../model/planned_alert.dart';
import 'engine_models.dart';

export 'engine_models.dart';

/// Typed client for the native `alarm_engine` channel (roadmap §3).
///
/// Each engine event reaches Dart once per [AlarmEngine]: whichever of [events]
/// or [drainEvents] sees an event first delivers it, and the other drops it
/// (de-duplicated on type, alertId and atUtcMs).
class AlarmEngine {
  AlarmEngine({MethodChannel? methodChannel, EventChannel? eventChannel})
    : _method = methodChannel ?? const MethodChannel(methodChannelName),
      _eventChannel = eventChannel ?? const EventChannel(eventChannelName);

  static const methodChannelName = 'alarm_engine';
  static const eventChannelName = 'alarm_engine/events';
  static const planVersion = 1;
  static const _rememberedEvents = 1000;

  final MethodChannel _method;
  final EventChannel _eventChannel;
  final Set<String> _seen =
      <String>{}; // insertion-ordered, so the oldest key goes first
  StreamController<EngineEvent>? _controller;
  StreamSubscription<Object?>? _subscription;

  Future<ApplyResult> applyPlan(List<PlannedAlert> alerts) async {
    final raw = await _method.invokeMapMethod<String, Object?>('applyPlan', {
      'version': planVersion,
      'alerts': [for (final a in alerts) a.toJson()],
    });
    return ApplyResult.fromJson(raw!);
  }

  Future<EngineHealth> getHealth() async {
    final raw = await _method.invokeMapMethod<String, Object?>('getHealth');
    return EngineHealth.fromJson(raw!);
  }

  Future<void> testAlarm(
    AlertStrength strength, {
    Duration delay = const Duration(seconds: 5),
  }) => _method.invokeMethod<void>('testAlarm', {
    'strength': strength.name,
    'delaySec': delay.inSeconds,
  });

  Future<void> openPermissionSettings(PermissionKind kind) =>
      _method.invokeMethod<void>('openPermissionSettings', {'kind': kind.name});

  /// Events queued natively that this instance has not delivered yet. Clears the native queue.
  Future<List<EngineEvent>> drainEvents() async {
    final raw =
        await _method.invokeListMethod<Object?>('drainEvents') ??
        const <Object?>[];
    return [
      for (final event in raw.map(_parse))
        if (_firstSeen(event)) event,
    ];
  }

  /// Live events. Every listener shares one native subscription, so de-duplication runs once.
  Stream<EngineEvent> get events {
    final controller = _controller ??= StreamController<EngineEvent>.broadcast(
      onListen: _listen,
      onCancel: _cancel,
    );
    return controller.stream;
  }

  void _listen() {
    _subscription = _eventChannel.receiveBroadcastStream().listen(
      (raw) {
        final event = _parse(raw);
        if (_firstSeen(event)) _controller!.add(event);
      },
      onError: (Object error, StackTrace stack) =>
          _controller!.addError(error, stack),
    );
  }

  Future<void> _cancel() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  static EngineEvent _parse(Object? raw) =>
      EngineEvent.fromJson((raw! as Map).cast<String, Object?>());

  bool _firstSeen(EngineEvent event) {
    if (!_seen.add(event.dedupKey)) return false;
    if (_seen.length > _rememberedEvents) _seen.remove(_seen.first);
    return true;
  }
}
