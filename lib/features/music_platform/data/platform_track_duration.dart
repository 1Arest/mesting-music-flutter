/// Kugou catalogue endpoints use several duration aliases and mixed units.
/// Keep parsing in one place so recommendation, search and metadata agree.
class PlatformTrackDuration {
  static Duration? fromFields(Map<dynamic, dynamic> fields) {
    for (final key in [
      'durationMs',
      'duration_ms',
      // /audio returned 261276, 257252 and 279196 ms in live host probes.
      // Treat short clips correctly too; 9800 here means 9.8 s, not 163 min.
      'timelength',
      'timelength_ms',
      'time_length_ms',
    ]) {
      final value = _positive(fields[key]);
      if (value != null) return Duration(milliseconds: value.round());
    }
    for (final key in [
      'duration',
      'Duration',
      'TimeLength',
      'TimeLen',
      'time_len',
      'timeLen',
      'time_length',
      'song_duration',
    ]) {
      final raw = fields[key];
      if (raw is String && raw.contains(':')) {
        final parts = raw.split(':').map(num.tryParse).toList();
        if (parts.length >= 2 &&
            parts.length <= 3 &&
            parts.every((p) => p != null && p >= 0 && p.isFinite)) {
          num seconds = 0;
          for (final part in parts) {
            seconds = seconds * 60 + part!;
          }
          if (seconds > 0) {
            return Duration(milliseconds: (seconds * 1000).round());
          }
        }
      }
      final value = _positive(raw);
      if (value == null) continue;
      // Existing search uses seconds; audio/cloud endpoints also return the
      // same aliases in milliseconds. Preserve sub-second precision here.
      return Duration(
        milliseconds:
            (key == 'Duration' || value <= 10000 ? value * 1000 : value)
                .round(),
      );
    }
    return null;
  }

  static num? _positive(Object? value) {
    final parsed = value is num ? value : num.tryParse('$value');
    return parsed != null && parsed.isFinite && parsed > 0 ? parsed : null;
  }
}
