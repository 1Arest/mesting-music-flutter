/// The concept API identifies an album recording with mixsongid, while audio
/// playback uses a hash. Keep these identities distinct and ignore zero IDs.
class PlatformSongIdentity {
  static String fromPayload(Object? value, [int depth = 0]) {
    // A generic audio_id can identify the work rather than its album recording.
    // Search every structured node for a real mixsongid before legacy aliases.
    final specific = _find(value, depth, false);
    return specific.isNotEmpty ? specific : _find(value, depth, true);
  }

  static String _find(Object? value, int depth, bool legacy) {
    if (depth > 7) return '';
    if (value is List) {
      for (final row in value) {
        final id = _find(row, depth + 1, legacy);
        if (id.isNotEmpty) return id;
      }
    } else if (value is Map) {
      for (final key in [
        'album_audio_id',
        'albumAudioId',
        'AlbumAudioID',
        'MixSongID',
        'mixsongid',
        'mix_song_id',
        'add_mixsongid',
        'album_audio_id2',
        if (legacy) 'Audioid',
        if (legacy) 'audio_id',
      ]) {
        final id = '${value[key] ?? ''}'.trim();
        if ((int.tryParse(id) ?? 0) > 0) return id;
      }
      for (final key in [
        'data',
        'audio_info',
        'base',
        'info',
        'list',
        'songs',
        'song_info',
        'audio',
        'album_info',
      ]) {
        final id = _find(value[key], depth + 1, legacy);
        if (id.isNotEmpty) return id;
      }
    }
    return '';
  }
}
