enum AlertStrength { headsUp, alarm }

class AlertSpec {
  const AlertSpec(this.offsetMinutes, this.strength) : assert(offsetMinutes >= 0);
  final int offsetMinutes; // minutes before start
  final AlertStrength strength;

  @override
  bool operator ==(Object other) =>
      other is AlertSpec && other.offsetMinutes == offsetMinutes && other.strength == strength;
  @override
  int get hashCode => Object.hash(offsetMinutes, strength);
}

class SoundSettings {
  const SoundSettings({
    this.toneUri,
    this.vibrate = true,
    this.gradualVolume = true,
    this.ringTimeout = const Duration(minutes: 2),
  });
  final String? toneUri; // null = system default alarm tone
  final bool vibrate;
  final bool gradualVolume;
  final Duration ringTimeout;

  Map<String, Object?> toJson() => {
        'toneUri': toneUri,
        'vibrate': vibrate,
        'gradualVolume': gradualVolume,
        'ringTimeoutSec': ringTimeout.inSeconds,
      };

  factory SoundSettings.fromJson(Map<String, Object?> j) => SoundSettings(
        toneUri: j['toneUri'] as String?,
        vibrate: j['vibrate'] as bool,
        gradualVolume: j['gradualVolume'] as bool,
        ringTimeout: Duration(seconds: j['ringTimeoutSec'] as int),
      );

  @override
  bool operator ==(Object other) =>
      other is SoundSettings &&
      other.toneUri == toneUri &&
      other.vibrate == vibrate &&
      other.gradualVolume == gradualVolume &&
      other.ringTimeout == ringTimeout;
  @override
  int get hashCode => Object.hash(toneUri, vibrate, gradualVolume, ringTimeout);
}
