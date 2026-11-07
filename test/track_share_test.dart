import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/social/data/social_repository.dart';
import 'package:mesting_music/features/social/domain/social_models.dart';
import 'package:mesting_music/features/social/domain/track_share.dart';
import 'package:mesting_music/features/social/presentation/track_share_sheet.dart';
import 'package:mesting_music/features/social/social_providers.dart';
import 'package:mesting_music/shared/models/track.dart';

void main() {
  const track = Track(
    id: 'shared-track',
    title: '分享给你听',
    artist: 'Mesting Artist',
    album: '心动歌单',
    duration: Duration(minutes: 3, seconds: 42),
    audioAsset: 'https://example.com/audio.mp3',
    coverAsset: 'https://example.com/cover.jpg',
    lyricsAsset: 'https://example.com/lyrics.lrc',
    source: TrackSource.netease,
    provider: '网易云音乐',
  );

  test('歌曲分享文本可通过现有文本消息完整往返', () {
    final message = encodeTrackShareMessage(track);
    final decoded = decodeTrackShareMessage(message);

    expect(message, startsWith('🎵 分享歌曲：《分享给你听》'));
    expect(message, contains(trackShareUriPrefix));
    expect(message.length, lessThan(2000));
    expect(decoded?.id, track.id);
    expect(decoded?.title, track.title);
    expect(decoded?.artist, track.artist);
    expect(decoded?.audioAsset, track.audioAsset);
    expect(decoded?.coverAsset, track.coverAsset);
    expect(decoded?.source, track.source);
    expect(decodeTrackShareMessage('普通聊天消息'), isNull);
  });

  test('歌曲分享只把远程地址交给消息媒体字段', () {
    expect(
      trackShareRemoteUrl('https://example.com/audio.mp3'),
      'https://example.com/audio.mp3',
    );
    expect(
      trackShareRemoteUrl('cloud://music/audio.mp3'),
      'cloud://music/audio.mp3',
    );
    expect(trackShareRemoteUrl('assets/audio/local.mp3'), isNull);
    expect(trackShareRemoteUrl('http://example.com/audio.mp3'), isNull);
  });

  testWidgets('歌曲分享面板只列出互相关注好友并返回选择结果', (tester) async {
    const friend = SocialUser(
      uid: 'friend',
      nickname: '好友小满',
      isFollowing: true,
      followsMe: true,
    );
    const followingOnly = SocialUser(
      uid: 'following-only',
      nickname: '单向关注',
      isFollowing: true,
    );
    SocialUser? selected;
    final repository = _TrackShareRepository([friend, followingOnly]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [socialRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async {
                    selected = await showTrackShareSheet(
                      context: context,
                      track: track,
                    );
                  },
                  child: const Text('打开分享'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开分享'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('track-share-sheet')), findsOneWidget);
    expect(find.text('分享给好友'), findsOneWidget);
    expect(find.text(track.title), findsOneWidget);
    expect(find.text('好友小满'), findsOneWidget);
    expect(find.text('单向关注'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('track-share-friend-friend')));
    await tester.pumpAndSettle();

    expect(selected, friend);
  });
}

class _TrackShareRepository extends Fake implements SocialRepository {
  _TrackShareRepository(this.connections);

  final List<SocialUser> connections;

  @override
  Future<List<SocialUser>> listConnections(SocialConnectionKind kind) async =>
      connections;
}
