import 'dart:convert';

/// A server playback command is distinct from room/member metadata. Keep wire
/// decoding separate from controller ordering and audio mutations; missing
/// state must never turn an unrelated room response into an implicit play.
class TogetherPlaybackCommand {
  const TogetherPlaybackCommand({
    required this.songId,
    required this.userId,
    required this.token,
    required this.sequence,
    required this.playing,
    required this.position,
  });
  final String songId, userId, token;
  final int? sequence;
  final bool playing;
  final Duration? position;

  static TogetherPlaybackCommand? parse(
    Map<String, dynamic> data,
    String room,
  ) {
    Object? raw =
        data['commandInfo'] ?? data['playCommand'] ?? data['playingInfo'];
    if (raw is String && raw.length <= 32768) {
      try {
        raw = jsonDecode(raw);
      } on FormatException {
        return null;
      }
    }
    if (raw is! Map) return null;
    final sequence = raw['serverSeq'] ?? raw['version'] ?? data['serverSeq'];
    final song = '${raw['targetSongId'] ?? raw['songId'] ?? ''}';
    if (sequence == null ||
        '$sequence'.length > 128 ||
        !RegExp(r'^[1-9][0-9]*$').hasMatch(song)) {
      return null;
    }
    final state = raw['playStatus'] ?? raw['commandType'];
    if (state != 'PLAY' && state != 'PAUSE') return null;
    final progress = int.tryParse('${raw['progress']}');
    return TogetherPlaybackCommand(
      songId: song,
      userId: '${raw['userId'] ?? ''}',
      token: '$room:$sequence',
      sequence: int.tryParse('$sequence'),
      playing: state == 'PLAY',
      position: progress != null && progress >= 0
          ? Duration(milliseconds: progress)
          : null,
    );
  }
}
