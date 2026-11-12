/// Playback-log fields established by the official Android core music path.
/// `time` follows playback speed; `realtime` measures audible wall time. Neither
/// includes seeking/buffering. Original dates must come from the saved event,
/// never from the retry date or a monthly aggregate.
Map<String, Object?> neteasePlaybackLog({
  required String id,
  required bool started,
  required int mediaSeconds,
  required int realSeconds,
  required DateTime startedAt,
  String sourceId = '0',
}) {
  if (!RegExp(r'^\d+$').hasMatch(id) || mediaSeconds < 0 || realSeconds < 0) {
    throw ArgumentError('Invalid measured playback event');
  }
  return {
    'action': started ? 'startplay' : 'play',
    'json': {
      'id': id,
      'type': 'song',
      'mainsite': '1',
      'mainsiteWeb': '1',
      'content': 'id=$sourceId',
      'startlogtime': startedAt.millisecondsSinceEpoch ~/ 1000,
      if (!started) ...{
        'time': mediaSeconds,
        'realtime': realSeconds,
        'end': 'playend',
        'wifi': 0,
        'download': 0,
        'source': 'list',
        'sourceId': sourceId,
      },
    },
  };
}
