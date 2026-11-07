import '../../../shared/models/track.dart';
import 'social_models.dart';

const listenTogetherInviteScheme = 'mesting-together';
const listenTogetherInviteHost = 'v1';

enum ListenTogetherStatus { pending, active, ended, declined, expired }

class ListenTogetherInvite {
  const ListenTogetherInvite({
    required this.invitationId,
    required this.sessionId,
    required this.trackTitle,
    required this.trackArtist,
  });

  final String invitationId;
  final String sessionId;
  final String trackTitle;
  final String trackArtist;
}

String encodeListenTogetherInvite(ListenTogetherInvite invite) {
  return Uri(
    scheme: listenTogetherInviteScheme,
    host: listenTogetherInviteHost,
    queryParameters: {
      'invitation': invite.invitationId,
      'session': invite.sessionId,
      'title': invite.trackTitle,
      'artist': invite.trackArtist,
    },
  ).toString();
}

ListenTogetherInvite? decodeListenTogetherInvite(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.scheme != listenTogetherInviteScheme ||
      uri.host != listenTogetherInviteHost) {
    return null;
  }
  final invitationId = uri.queryParameters['invitation']?.trim() ?? '';
  final sessionId = uri.queryParameters['session']?.trim() ?? '';
  if (invitationId.isEmpty || sessionId.isEmpty) return null;
  return ListenTogetherInvite(
    invitationId: invitationId,
    sessionId: sessionId,
    trackTitle: uri.queryParameters['title']?.trim() ?? '一起听音乐',
    trackArtist: uri.queryParameters['artist']?.trim() ?? '',
  );
}

class ListenTogetherPlayback {
  const ListenTogetherPlayback({
    required this.queue,
    required this.playing,
    required this.position,
    required this.updatedAt,
    required this.revision,
    required this.lastActorUid,
  });

  final List<Track> queue;
  final bool playing;
  final Duration position;
  final DateTime updatedAt;
  final int revision;
  final String lastActorUid;

  Track? get currentTrack => queue.firstOrNull;

  factory ListenTogetherPlayback.fromJson(Map<String, Object?> json) {
    final queue = _listValue(json['queue'])
        .map(_mapValue)
        .map(Track.fromJson)
        .where((track) => track.isPlayable)
        .toList(growable: false);
    return ListenTogetherPlayback(
      queue: queue,
      playing: json['playing'] as bool? ?? false,
      position: Duration(milliseconds: _intValue(json['position_ms'])),
      updatedAt: _dateValue(json['updated_at']),
      revision: _intValue(json['revision']),
      lastActorUid: json['last_actor_uid'] as String? ?? '',
    );
  }

  Map<String, Object?> toRequest({required int baseRevision}) => {
    'base_revision': baseRevision,
    'queue': queue.map((track) => track.toJson()).toList(growable: false),
    'playing': playing,
    'position_ms': position.inMilliseconds,
  };
}

class ListenTogetherSession {
  ListenTogetherSession({
    required this.id,
    required this.invitationId,
    required this.status,
    required this.inviterUid,
    required this.inviteeUid,
    required this.peer,
    required this.playback,
    required this.accumulatedDuration,
    required this.bothPresent,
    required this.createdAt,
    required this.acceptedAt,
    required this.endedAt,
    required this.serverNow,
    DateTime? fetchedAt,
  }) : fetchedAt = fetchedAt ?? DateTime.now();

  final String id;
  final String invitationId;
  final ListenTogetherStatus status;
  final String inviterUid;
  final String inviteeUid;
  final SocialUser peer;
  final ListenTogetherPlayback playback;
  final Duration accumulatedDuration;
  final bool bothPresent;
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final DateTime? endedAt;
  final DateTime serverNow;
  final DateTime fetchedAt;

  bool get isActive => status == ListenTogetherStatus.active;
  bool get isPending => status == ListenTogetherStatus.pending;
  bool get canShowHistory =>
      status == ListenTogetherStatus.active ||
      status == ListenTogetherStatus.ended;

  bool invitationMatches(String value) =>
      invitationId.isNotEmpty && invitationId == value;

  bool isInviter(String uid) => inviterUid == uid;

  Duration playbackPositionAt([DateTime? now]) {
    final trackDuration =
        playback.currentTrack?.duration ?? const Duration(days: 365);
    var milliseconds = playback.position.inMilliseconds;
    if (playback.playing) {
      final atFetch = serverNow.difference(playback.updatedAt).inMilliseconds;
      final sinceFetch = (now ?? DateTime.now())
          .difference(fetchedAt)
          .inMilliseconds;
      milliseconds += atFetch.clamp(0, 30000) + sinceFetch.clamp(0, 30000);
    }
    return Duration(
      milliseconds: milliseconds.clamp(0, trackDuration.inMilliseconds),
    );
  }

  Duration accumulatedDurationAt([DateTime? now]) {
    if (!isActive || !bothPresent) return accumulatedDuration;
    final sinceFetch = (now ?? DateTime.now())
        .difference(fetchedAt)
        .inMilliseconds
        .clamp(0, 5000);
    return accumulatedDuration + Duration(milliseconds: sinceFetch);
  }

  factory ListenTogetherSession.fromJson(Map<String, Object?> json) {
    return ListenTogetherSession(
      id: json['id'] as String? ?? '',
      invitationId: json['invitation_id'] as String? ?? '',
      status: ListenTogetherStatus.values.firstWhere(
        (value) => value.name == json['status'],
        orElse: () => ListenTogetherStatus.ended,
      ),
      inviterUid: json['inviter_uid'] as String? ?? '',
      inviteeUid: json['invitee_uid'] as String? ?? '',
      peer: SocialUser.fromJson(_mapValue(json['peer'])),
      playback: ListenTogetherPlayback.fromJson(_mapValue(json['playback'])),
      accumulatedDuration: Duration(
        milliseconds: _intValue(json['accumulated_ms']),
      ),
      bothPresent: json['both_present'] as bool? ?? false,
      createdAt: _dateValue(json['created_at']),
      acceptedAt: _optionalDateValue(json['accepted_at']),
      endedAt: _optionalDateValue(json['ended_at']),
      serverNow: _dateValue(json['server_now']),
    );
  }
}

class ListenTogetherTrackRecord {
  const ListenTogetherTrackRecord({
    required this.track,
    required this.playCount,
    required this.lastListenedAt,
  });

  final Track track;
  final int playCount;
  final DateTime lastListenedAt;

  factory ListenTogetherTrackRecord.fromJson(Map<String, Object?> json) {
    return ListenTogetherTrackRecord(
      track: Track.fromJson(_mapValue(json['track'])),
      playCount: _intValue(json['play_count']),
      lastListenedAt: _dateValue(json['last_listened_at']),
    );
  }
}

String listenTogetherQueueSignature(Iterable<Track> tracks) {
  return tracks
      .map((track) => '${track.id}\u0001${track.audioAsset}')
      .join('\u0002');
}

Duration listenTogetherPlaybackDrift(
  Duration localPosition,
  Duration expectedPosition,
) {
  return Duration(
    milliseconds:
        (localPosition.inMilliseconds - expectedPosition.inMilliseconds).abs(),
  );
}

int _intValue(Object? value) => switch (value) {
  int number => number,
  num number => number.toInt(),
  String text => int.tryParse(text) ?? 0,
  _ => 0,
};

Map<String, Object?> _mapValue(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  return const {};
}

List<Object?> _listValue(Object? value) {
  return value is List ? value.cast<Object?>() : const [];
}

DateTime _dateValue(Object? value) {
  if (value is DateTime) return value.toLocal();
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value).toLocal();
  }
  return DateTime.tryParse(value?.toString() ?? '')?.toLocal() ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

DateTime? _optionalDateValue(Object? value) {
  if (value == null || value.toString().trim().isEmpty) return null;
  return _dateValue(value);
}
