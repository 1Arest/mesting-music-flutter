import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/social/domain/listen_together.dart';
import 'package:mesting_music/features/social/domain/social_models.dart';
import 'package:mesting_music/shared/models/track.dart';

void main() {
  const track = Track(
    id: 'together-track',
    title: '心动歌曲',
    artist: 'Mesting',
    album: '一起听',
    duration: Duration(minutes: 3),
    audioAsset: 'https://cdn.example/audio.mp3',
    coverAsset: 'https://cdn.example/cover.jpg',
    lyricsAsset: '',
    source: TrackSource.netease,
    provider: '网易云音乐',
  );

  test('一起听邀请链接可以无损编解码', () {
    const invite = ListenTogetherInvite(
      invitationId: 'invite-1',
      sessionId: 'session-1',
      trackTitle: '心动歌曲',
      trackArtist: 'Mesting',
    );

    final decoded = decodeListenTogetherInvite(
      encodeListenTogetherInvite(invite),
    );
    expect(decoded?.invitationId, invite.invitationId);
    expect(decoded?.sessionId, invite.sessionId);
    expect(decoded?.trackTitle, invite.trackTitle);
    expect(decoded?.trackArtist, invite.trackArtist);
    expect(decodeListenTogetherInvite('普通聊天消息'), isNull);
  });

  test('播放位置使用服务端时间基准并限制在歌曲时长内', () {
    final fetchedAt = DateTime(2026, 7, 27, 12);
    final session = ListenTogetherSession(
      id: 'session-1',
      invitationId: 'invite-1',
      status: ListenTogetherStatus.active,
      inviterUid: 'me',
      inviteeUid: 'friend',
      peer: const SocialUser(uid: 'friend', nickname: '好友'),
      playback: ListenTogetherPlayback(
        queue: const [track],
        playing: true,
        position: const Duration(seconds: 20),
        updatedAt: DateTime(2026, 7, 27, 11, 59, 58),
        revision: 3,
        lastActorUid: 'friend',
      ),
      accumulatedDuration: const Duration(minutes: 8),
      bothPresent: true,
      createdAt: fetchedAt,
      acceptedAt: fetchedAt,
      endedAt: null,
      serverNow: fetchedAt,
      fetchedAt: fetchedAt,
    );

    expect(
      session.playbackPositionAt(
        fetchedAt.add(const Duration(milliseconds: 500)),
      ),
      const Duration(milliseconds: 22500),
    );
    expect(
      session.accumulatedDurationAt(fetchedAt.add(const Duration(seconds: 2))),
      const Duration(minutes: 8, seconds: 2),
    );
  });

  test('队列签名与播放偏差用于识别需要同步的状态', () {
    const alternate = Track(
      id: 'alternate',
      title: '下一首',
      artist: '好友',
      album: '',
      duration: Duration(minutes: 2),
      audioAsset: 'https://cdn.example/next.mp3',
      coverAsset: '',
      lyricsAsset: '',
      source: TrackSource.netease,
    );

    expect(
      listenTogetherQueueSignature(const [track, alternate]),
      isNot(listenTogetherQueueSignature(const [alternate, track])),
    );
    expect(
      listenTogetherPlaybackDrift(
        const Duration(seconds: 8),
        const Duration(milliseconds: 6250),
      ),
      const Duration(milliseconds: 1750),
    );
  });
}
