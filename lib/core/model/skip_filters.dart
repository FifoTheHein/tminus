/// Resolution step 3 (spec §6): matching events resolve to Silent.
/// Every filter defaults to on (roadmap §5.3).
class SkipFilters {
  const SkipFilters({
    this.allDay = true,
    this.free = true,
    this.tentative = true,
    this.cancelled = true,
    this.declined = true,
  });

  final bool allDay;
  final bool free;
  final bool tentative;
  final bool cancelled;
  final bool declined;

  SkipFilters copyWith({
    bool? allDay,
    bool? free,
    bool? tentative,
    bool? cancelled,
    bool? declined,
  }) => SkipFilters(
    allDay: allDay ?? this.allDay,
    free: free ?? this.free,
    tentative: tentative ?? this.tentative,
    cancelled: cancelled ?? this.cancelled,
    declined: declined ?? this.declined,
  );

  Map<String, Object?> toJson() => {
    'allDay': allDay,
    'free': free,
    'tentative': tentative,
    'cancelled': cancelled,
    'declined': declined,
  };

  /// A missing key falls back to on, so JSON from older builds stays valid.
  factory SkipFilters.fromJson(Map<String, Object?> j) => SkipFilters(
    allDay: j['allDay'] as bool? ?? true,
    free: j['free'] as bool? ?? true,
    tentative: j['tentative'] as bool? ?? true,
    cancelled: j['cancelled'] as bool? ?? true,
    declined: j['declined'] as bool? ?? true,
  );

  /// [fromJson] for JSON that may not be a skip-filter object (decision 15):
  /// null unless [j] is an object whose known keys are booleans or missing.
  static SkipFilters? tryFromJson(Object? j) {
    if (j is! Map<String, Object?>) return null;
    const keys = ['allDay', 'free', 'tentative', 'cancelled', 'declined'];
    if (keys.any((k) => j[k] != null && j[k] is! bool)) return null;
    return SkipFilters.fromJson(j);
  }

  @override
  bool operator ==(Object other) =>
      other is SkipFilters &&
      other.allDay == allDay &&
      other.free == free &&
      other.tentative == tentative &&
      other.cancelled == cancelled &&
      other.declined == declined;

  @override
  int get hashCode => Object.hash(allDay, free, tentative, cancelled, declined);
}
