import 'package:flutter/services.dart';

/// Runtime permissions the UI asks for (Plan 5 decision 12).
enum UiPermission { calendar, notifications }

/// `permanentlyDenied`: Android will not show the dialog again; the screen
/// offers **Open settings** instead.
enum PermissionResult { granted, denied, permanentlyDenied }

/// A tone from the system alarm-tone picker.
class PickedTone {
  const PickedTone({required this.uri, required this.title});

  /// Null = the system default alarm tone (`SoundSettings.toneUri` null).
  final String? uri;
  final String title;
}

class DeviceInfo {
  const DeviceInfo({
    required this.versionName,
    required this.versionCode,
    required this.manufacturer,
    required this.sdkInt,
  });

  factory DeviceInfo.fromJson(Map<String, Object?> j) => DeviceInfo(
    versionName: j['versionName'] as String,
    versionCode: (j['versionCode'] as num).toInt(),
    manufacturer: j['manufacturer'] as String,
    sdkInt: j['sdkInt'] as int,
  );

  final String versionName;
  final int versionCode;

  /// `Build.MANUFACTURER`, e.g. `samsung`; picks the Health phone-maker tip.
  final String manufacturer;
  final int sdkInt;
}

/// Typed client for the `tminus_ui` channel (Plan 5 decision 1). Exists only
/// on the UI engine. Callers catch [MissingPluginException] (tests, desktop)
/// and [PlatformException] (`busy`, `cancelled`, `no_activity`, `io_error`,
/// `too_large`), and log the code only.
class UiPlatform {
  UiPlatform({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'tminus_ui';
  static const defaultToneTitle = 'Default alarm tone';

  final MethodChannel _channel;

  Future<PermissionResult> requestPermission(UiPermission permission) async {
    final name = await _channel.invokeMethod<String>('requestPermission', {
      'kind': permission.name,
    });
    return PermissionResult.values.asNameMap()[name] ?? PermissionResult.denied;
  }

  /// Null when the user backed out of the picker.
  Future<PickedTone?> pickAlarmTone({String? current}) async {
    final raw = await _channel.invokeMapMethod<String, Object?>(
      'pickAlarmTone',
      {'current': current},
    );
    if (raw == null || raw['picked'] != true) return null;
    return PickedTone(
      uri: raw['uri'] as String?,
      title: raw['title'] as String? ?? defaultToneTitle,
    );
  }

  /// The tone's display name; [defaultToneTitle] for null or an unreadable one.
  Future<String> toneTitle(String? uri) async =>
      await _channel.invokeMethod<String>('toneTitle', {'uri': uri}) ??
      defaultToneTitle;

  /// Opens an `https` link (the Teams join link); false when nothing could.
  Future<bool> openUrl(String url) async =>
      await _channel.invokeMethod<bool>('openUrl', {'url': url}) ?? false;

  Future<void> openAppDetails() =>
      _channel.invokeMethod<void>('openAppDetails');

  /// Shows the system save dialog. False when the user cancelled.
  Future<bool> createDocument({
    required String name,
    required String text,
  }) async =>
      await _channel.invokeMethod<bool>('createDocument', {
        'name': name,
        'text': text,
      }) ??
      false;

  /// Shows the system open dialog. Null when the user cancelled.
  Future<String?> openDocument() =>
      _channel.invokeMethod<String>('openDocument');

  Future<DeviceInfo> deviceInfo() async => DeviceInfo.fromJson(
    (await _channel.invokeMapMethod<String, Object?>('deviceInfo'))!,
  );
}
