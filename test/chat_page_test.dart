import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mesting_music/features/auth/auth_providers.dart';
import 'package:mesting_music/features/auth/domain/auth_models.dart';
import 'package:mesting_music/features/social/data/social_repository.dart';
import 'package:mesting_music/features/social/domain/listen_together.dart';
import 'package:mesting_music/features/social/domain/social_models.dart';
import 'package:mesting_music/features/social/domain/track_share.dart';
import 'package:mesting_music/features/social/presentation/chat_page.dart';
import 'package:mesting_music/features/social/social_providers.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/shared/widgets/artwork_image.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

void main() {
  const currentUser = AuthUser(uid: 'me', nickname: 'Mesting');
  const friend = SocialUser(
    uid: 'friend',
    nickname: 'Mest',
    isFollowing: true,
    followsMe: true,
  );

  Widget app(_ChatRepository repository) {
    return ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(currentUser),
        socialRepositoryProvider.overrideWithValue(repository),
      ],
      child: const MaterialApp(
        home: Scaffold(body: ChatPage(uid: 'friend')),
      ),
    );
  }

  Widget routedApp(_ChatRepository repository) {
    final router = GoRouter(
      initialLocation: '/chat',
      routes: [
        GoRoute(
          path: '/chat',
          builder: (_, _) => const Scaffold(body: ChatPage(uid: 'friend')),
        ),
        GoRoute(
          path: '/profile',
          builder: (_, _) => const Scaffold(
            body: SizedBox(key: ValueKey('current-profile-page')),
          ),
        ),
        GoRoute(
          path: '/social/users/:uid',
          builder: (_, state) => Scaffold(
            body: SizedBox(
              key: ValueKey('public-profile-${state.pathParameters['uid']}'),
            ),
          ),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(currentUser),
        socialRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  test('emoji insertion follows the current selection', () {
    expect(
      insertChatEmoji(
        const TextEditingValue(
          text: '你好世界',
          selection: TextSelection(baseOffset: 2, extentOffset: 4),
        ),
        '🥰',
      ),
      TextEditingValue(
        text: '你好🥰',
        selection: TextSelection.collapsed(offset: 2 + '🥰'.length),
      ),
    );
    expect(
      insertChatEmoji(const TextEditingValue(text: '你好'), '😀'),
      TextEditingValue(
        text: '你好😀',
        selection: TextSelection.collapsed(offset: 2 + '😀'.length),
      ),
    );
  });

  testWidgets('emoji is inserted into the composer and sent explicitly', (
    tester,
  ) async {
    final repository = _ChatRepository(friend);
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();
    final routeBarrierCount = find.byType(ModalBarrier).evaluate().length;

    await tester.tap(find.text('表情'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('chat-inline-emoji-panel')),
      findsOneWidget,
    );
    expect(find.byType(ModalBarrier), findsNWidgets(routeBarrierCount));

    await tester.tap(find.byKey(const ValueKey('chat-emoji-category-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('🥰'));
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '🥰',
    );
    expect(repository.sendCalls, 0);
    expect(_messageTextFinder('🥰'), findsNothing);
    expect(_deliveryFinder('chat-message-sending-'), findsNothing);
    expect(find.text('点按插入输入框'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat-emoji-🥹')));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '🥰🥹',
    );
    expect(repository.sendCalls, 0);

    await tester.tap(find.byTooltip('发送'));
    await tester.pump();

    expect(repository.sendCalls, 1);
    expect(repository.lastKind, SocialMessageKind.text);
    expect(repository.lastText, '🥰🥹');
    expect(_deliveryFinder('chat-message-sending-'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byTooltip('发送'),
        matching: find.byIcon(Icons.arrow_upward_rounded),
      ),
      findsOneWidget,
    );

    repository.sendGate.complete(
      SocialMessage(
        id: 'server-message-1',
        senderUid: 'me',
        receiverUid: 'friend',
        kind: SocialMessageKind.text,
        text: '🥰🥹',
        sentAt: DateTime.now(),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(_deliveryFinder('chat-message-sending-'), findsNothing);
    expect(find.text('🥰🥹'), findsOneWidget);
  });

  testWidgets(
    'a delayed poll keeps a just-sent message and its avatar visible',
    (tester) async {
      final repository = _ChatRepository(friend);
      await tester.pumpWidget(app(repository));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '轮询期间也要保留');
      await tester.tap(find.byTooltip('发送'));
      await tester.pump();
      repository.sendGate.complete(
        SocialMessage(
          id: 'server-message-kept',
          senderUid: currentUser.uid,
          receiverUid: friend.uid,
          kind: SocialMessageKind.text,
          text: '轮询期间也要保留',
          sentAt: DateTime.now(),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('轮询期间也要保留'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('chat-message-avatar-server-message-kept')),
        findsOneWidget,
      );

      // The fake backend deliberately keeps returning an empty snapshot. The
      // client must not treat that short read lag as a deletion.
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(find.text('轮询期间也要保留'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('chat-message-avatar-server-message-kept')),
        findsOneWidget,
      );
    },
  );

  testWidgets('chat entry uses a branded curve loader instead of a spinner', (
    tester,
  ) async {
    final repository = _PendingChatRepository(friend);
    await tester.pumpWidget(app(repository));
    await tester.pump();

    expect(find.byKey(const ValueKey('chat-curve-loader')), findsOneWidget);
    expect(find.text('正在进入会话'), findsNothing);
    expect(find.text('正在同步好友与消息'), findsNothing);
    expect(find.bySemanticsLabel('正在进入好友会话'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    repository.messages.complete(const []);
    await tester.pumpAndSettle();
  });

  testWidgets(
    'history remains hidden until the first viewport jump reaches the latest message',
    (tester) async {
      final repository = _PendingChatRepository(friend);
      await tester.pumpWidget(app(repository));
      await tester.pump();

      repository.messages.complete([
        for (var index = 0; index < 12; index++)
          SocialMessage(
            id: 'history-$index',
            senderUid: index.isEven ? currentUser.uid : friend.uid,
            receiverUid: index.isEven ? friend.uid : currentUser.uid,
            kind: SocialMessageKind.text,
            text: '历史消息 $index',
            sentAt: DateTime.now().subtract(Duration(minutes: 12 - index)),
          ),
      ]);
      await tester.pump();

      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const ValueKey('chat-message-list-reveal')),
            )
            .opacity,
        0,
      );

      await tester.pump();
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const ValueKey('chat-message-list-reveal')),
            )
            .opacity,
        1,
      );
    },
  );

  testWidgets('好友分享的歌曲显示为可播放音乐卡片而不是编码文本', (tester) async {
    const track = Track(
      id: 'friend-shared-track',
      title: '好友分享歌曲',
      artist: 'Mesting Artist',
      album: '分享专辑',
      duration: Duration(minutes: 3),
      audioAsset: 'https://example.com/shared.mp3',
      coverAsset: 'assets/images/theme_gallery/shinchan-avatar-v2.png',
      lyricsAsset: '',
      source: TrackSource.netease,
    );
    final repository = _ChatRepository(
      friend,
      initialMessages: [
        SocialMessage(
          id: 'shared-track-message',
          senderUid: friend.uid,
          receiverUid: currentUser.uid,
          kind: SocialMessageKind.text,
          text: encodeTrackShareMessage(track),
          sentAt: DateTime.now(),
        ),
      ],
    );

    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('chat-shared-track-shared-track-message')),
      findsOneWidget,
    );
    expect(find.text(track.title), findsOneWidget);
    expect(find.text(track.artist), findsOneWidget);
    expect(find.textContaining(trackShareUriPrefix), findsNothing);
    expect(
      find.byKey(const ValueKey('chat-shared-track-play-shared-track-message')),
      findsOneWidget,
    );
  });

  testWidgets('好友一起听邀请显示为可接受卡片而不是内部链接', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const invite = ListenTogetherInvite(
      invitationId: 'invite-message-1',
      sessionId: 'session-message-1',
      trackTitle: '今晚一起听',
      trackArtist: 'Mesting Artist',
    );
    final repository = _ChatRepository(
      friend,
      initialMessages: [
        SocialMessage(
          id: 'together-message',
          senderUid: friend.uid,
          receiverUid: currentUser.uid,
          kind: SocialMessageKind.text,
          text: encodeListenTogetherInvite(invite),
          sentAt: DateTime.now(),
        ),
      ],
    );

    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('chat-listen-together-together-message')),
      findsOneWidget,
    );
    expect(find.text('好友一起听'), findsOneWidget);
    expect(find.text(invite.trackTitle), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('chat-listen-together-accept-together-message'),
      ),
      findsOneWidget,
    );
    final acceptButton = find.byKey(
      const ValueKey('chat-listen-together-accept-together-message'),
    );
    final declineButton = find.byKey(
      const ValueKey('chat-listen-together-decline-together-message'),
    );
    expect(tester.getSize(acceptButton).height, 48);
    expect(tester.getSize(declineButton).height, 48);
    final acceptLabel = tester.widget<Text>(find.text('加入一起听'));
    expect(acceptLabel.maxLines, 1);
    expect(acceptLabel.softWrap, isFalse);
    expect(find.textContaining('$listenTogetherInviteScheme://'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('平板聊天使用居中会话面板并限制消息气泡宽度', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _ChatRepository(
      friend,
      initialMessages: [
        SocialMessage(
          id: 'tablet-message',
          senderUid: 'friend',
          receiverUid: 'me',
          kind: SocialMessageKind.text,
          text: '这是一条用于验证平板消息宽度的测试内容',
          sentAt: DateTime(2026, 7, 26, 12),
        ),
      ],
    );

    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();

    final tabletSurface = find.byKey(const ValueKey('chat-tablet-surface'));
    expect(tabletSurface, findsOneWidget);
    expect(tester.getSize(tabletSurface).width, lessThanOrEqualTo(920));
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('chat-message-bubble-tablet-message')),
          )
          .width,
      lessThanOrEqualTo(520),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('voice toggle sits before the message field and send control', (
    tester,
  ) async {
    final repository = _ChatRepository(friend);
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();

    final voice = find.byKey(const ValueKey('chat-voice-toggle'));
    final field = find.byKey(const ValueKey('chat-message-field-surface'));
    final send = find.byKey(const ValueKey('chat-send-button'));
    expect(voice, findsOneWidget);
    expect(field, findsOneWidget);
    expect(send, findsOneWidget);
    expect(tester.getCenter(voice).dx, lessThan(tester.getCenter(field).dx));
    expect(tester.getCenter(field).dx, lessThan(tester.getCenter(send).dx));
  });

  testWidgets('message field paints a complete foreground outline', (
    tester,
  ) async {
    final repository = _ChatRepository(friend);
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();

    final surface = tester.widget<Container>(
      find.byKey(const ValueKey('chat-message-field-surface')),
    );
    final decoration = surface.foregroundDecoration as BoxDecoration;
    final border = decoration.border! as Border;
    expect(surface.clipBehavior, Clip.antiAlias);
    expect(border.top.width, greaterThanOrEqualTo(1));
    expect(border.right, border.top);
    expect(border.bottom, border.top);
    expect(border.left, border.top);
    expect(border.top.color.a, greaterThan(.3));
  });

  testWidgets('chat entry remains anchored to the latest message', (
    tester,
  ) async {
    final messages = [
      for (var index = 0; index < 7; index++)
        SocialMessage(
          id: 'history-image-$index',
          senderUid: index.isEven ? 'friend' : 'me',
          receiverUid: index.isEven ? 'me' : 'friend',
          kind: SocialMessageKind.image,
          mediaUrl: 'assets/images/theme_playlists/shinchan/cover-01.jpg',
          sentAt: DateTime(2026, 7, 25, 8, index),
        ),
      SocialMessage(
        id: 'latest-message',
        senderUid: 'friend',
        receiverUid: 'me',
        kind: SocialMessageKind.text,
        text: '这是最新一条消息',
        sentAt: DateTime(2026, 7, 25, 9),
      ),
    ];
    final repository = _ChatRepository(friend, initialMessages: messages);
    await tester.pumpWidget(app(repository));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();

    expect(find.text('这是最新一条消息'), findsOneWidget);
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const ValueKey('chat-message-list')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scrollable.position.extentAfter, lessThan(.5));
  });

  testWidgets('emoji panel switches categories and closes when typing', (
    tester,
  ) async {
    final repository = _ChatRepository(friend);
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('表情'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-emoji-category-2')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat-emoji-🎸')), findsOneWidget);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-inline-emoji-panel')), findsNothing);
  });

  testWidgets('message avatars replace the header avatar and open profiles', (
    tester,
  ) async {
    final repository = _ChatRepository(
      friend,
      initialMessages: [
        SocialMessage(
          id: 'peer-message',
          senderUid: 'friend',
          receiverUid: 'me',
          kind: SocialMessageKind.text,
          text: '你好',
          sentAt: DateTime(2026, 7, 25, 8),
        ),
        SocialMessage(
          id: 'mine-message',
          senderUid: 'me',
          receiverUid: 'friend',
          kind: SocialMessageKind.text,
          text: '你好呀',
          sentAt: DateTime(2026, 7, 25, 8, 1),
        ),
      ],
    );
    await tester.pumpWidget(routedApp(repository));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('chat-message-avatar-peer-message')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('chat-message-avatar-mine-message')),
      findsOneWidget,
    );
    expect(find.byTooltip('查看Mest的个人主页'), findsOneWidget);
    expect(find.byTooltip('查看我的个人主页'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('chat-message-avatar-peer-message')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('public-profile-friend')), findsOneWidget);

    await tester.pumpWidget(routedApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('chat-message-avatar-mine-message')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('current-profile-page')), findsOneWidget);
  });

  testWidgets('failed delivery is shown to the left and can be retried', (
    tester,
  ) async {
    final repository = _ChatRepository(friend);
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '重试这条消息');
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();
    repository.sendGate.completeError(const SocialRequestException('发送暂时失败'));
    await tester.pump();
    await tester.pump();

    expect(find.text('重试这条消息'), findsOneWidget);
    expect(_deliveryFinder('chat-message-failed-'), findsOneWidget);
    expect(find.byTooltip('发送失败，点按重试'), findsOneWidget);

    await tester.tap(_deliveryFinder('chat-message-failed-'));
    await tester.pump();
    expect(repository.sendCalls, 2);
  });

  testWidgets('portrait image keeps its ratio and opens a zoomable preview', (
    tester,
  ) async {
    final repository = _ChatRepository(
      friend,
      initialMessages: [
        SocialMessage(
          id: 'portrait-image',
          senderUid: 'me',
          receiverUid: 'friend',
          kind: SocialMessageKind.image,
          // Test-only portrait: old login illustrations were removed in 1.0.26.
          mediaUrl: File(
            'test/fixtures/chat-portrait.png',
          ).absolute.uri.toString(),
          sentAt: DateTime.now(),
        ),
      ],
    );
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pump(const Duration(milliseconds: 240));

    final preview = find.byKey(
      const ValueKey('chat-image-preview-portrait-image'),
    );
    // Wait for the exact resized FileImage rather than a timing guess. The
    // synthetic portrait is test-only and does not belong to the app bundle.
    final portrait = find.descendant(
      of: find.byKey(const ValueKey('chat-image-content-portrait-image')),
      matching: find.byType(Image),
    );
    var portraitReady = false;
    Object? portraitError;
    await tester.runAsync(() async {
      unawaited(
        precacheImage(
          tester.widget<Image>(portrait).image,
          tester.element(portrait),
          onError: (failure, _) => portraitError = failure,
        ).then((_) => portraitReady = true),
      );
    });
    for (var frame = 0; frame < 50 && !portraitReady; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(portraitError, isNull);
    expect(portraitReady, isTrue);
    await tester.pump(const Duration(milliseconds: 240));
    expect(preview, findsOneWidget);
    final imageBubble = tester.widget<Container>(
      find.byKey(const ValueKey('chat-message-bubble-portrait-image')),
    );
    expect(imageBubble.padding, EdgeInsets.zero);
    expect(imageBubble.decoration, isNull);
    final previewSize = tester.getSize(preview);
    final artwork = tester.widget<ArtworkImage>(
      find.byKey(const ValueKey('chat-image-content-portrait-image')),
    );
    expect(artwork.fit, BoxFit.contain);
    expect(artwork.decodeHeight, isNull);
    expect(previewSize.width, lessThanOrEqualTo(260));
    expect(previewSize.height, lessThanOrEqualTo(360));
    expect(previewSize.aspectRatio, closeTo(168 / 374, .01));
    expect(
      find.descendant(of: preview, matching: find.byType(ColoredBox)),
      findsNothing,
    );
    expect(
      find.descendant(of: preview, matching: find.byType(Stack)),
      findsNothing,
    );

    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getSize(preview), previewSize);

    await tester.tap(preview);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat-image-viewer')), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byTooltip('关闭图片预览'), findsOneWidget);
    final viewerRect = tester.getRect(
      find.byKey(const ValueKey('chat-image-viewer')),
    );
    final canvasRect = tester.getRect(
      find.byKey(const ValueKey('chat-image-viewer-canvas')),
    );
    expect(canvasRect.size, viewerRect.size);
    expect(canvasRect.center, viewerRect.center);
    expect(
      tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .constrained,
      isFalse,
    );
    final viewerArtwork = tester.widget<ArtworkImage>(
      find.byKey(const ValueKey('chat-image-viewer-content')),
    );
    expect(viewerArtwork.fit, BoxFit.contain);
    expect(viewerArtwork.decodeHeight, isNull);
    expect(viewerArtwork.width, viewerRect.width);
    expect(viewerArtwork.height, viewerRect.height);
    expect(
      tester.getCenter(find.byKey(const ValueKey('chat-image-viewer-content'))),
      viewerRect.center,
    );
    final closeRect = tester.getRect(find.byTooltip('关闭图片预览'));
    expect(closeRect.width, lessThanOrEqualTo(48));
    expect(closeRect.top, lessThan(viewerRect.height * .15));
  });

  test('video control icon follows the actual playback state', () {
    expect(chatVideoPlaybackIcon(true), Icons.pause_rounded);
    expect(chatVideoPlaybackIcon(false), Icons.play_arrow_rounded);
  });

  test('video duration uses stable second, minute and hour labels', () {
    expect(formatChatVideoDuration(const Duration(seconds: 9)), '00:09');
    expect(
      formatChatVideoDuration(const Duration(minutes: 1, seconds: 5)),
      '01:05',
    );
    expect(
      formatChatVideoDuration(const Duration(hours: 1, minutes: 1, seconds: 5)),
      '01:01:05',
    );
  });

  test('voice duration metadata uses readable labels', () {
    expect(chatVoiceDurationFromText('850'), const Duration(milliseconds: 850));
    expect(chatVoiceDurationFromText('invalid'), Duration.zero);
    expect(formatChatVoiceDuration(const Duration(milliseconds: 850)), '1″');
    expect(formatChatVoiceDuration(const Duration(seconds: 9)), '9″');
    expect(
      formatChatVoiceDuration(const Duration(minutes: 1, seconds: 5)),
      '1:05',
    );
  });

  testWidgets('voice composer and message bubble expose the recording flow', (
    tester,
  ) async {
    final repository = _ChatRepository(
      friend,
      initialMessages: [
        SocialMessage(
          id: 'voice-message',
          senderUid: 'friend',
          receiverUid: 'me',
          kind: SocialMessageKind.voice,
          text: '5200',
          mediaUrl: 'https://example.com/voice.m4a',
          sentAt: DateTime.now(),
        ),
      ],
    );
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat-voice-toggle')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('chat-voice-message-voice-message')),
      findsOneWidget,
    );
    expect(find.text('6″'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat-voice-toggle')));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.keyboard_alt_rounded), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-hold-to-record')), findsOneWidget);
    expect(find.text('按住说话'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('long pressing a voice message exposes transcript and deletion', (
    tester,
  ) async {
    final repository = _ChatRepository(
      friend,
      initialMessages: [
        SocialMessage(
          id: 'voice-actions',
          senderUid: 'friend',
          receiverUid: 'me',
          kind: SocialMessageKind.voice,
          text: '3200',
          mediaUrl: 'https://example.com/voice.m4a',
          sentAt: DateTime.now(),
        ),
      ],
    );
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
    await tester.longPress(
      find.byKey(const ValueKey('chat-voice-message-voice-actions')),
    );
    await tester.pumpAndSettle();

    expect(find.text('转文字'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    expect(find.text('撤回消息'), findsNothing);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isFalse,
    );

    await tester.tap(find.text('转文字'));
    await tester.pumpAndSettle();

    expect(find.text('语音转文字尚未配置'), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isFalse,
    );
  });

  testWidgets('voice actions enter quote and multi-select modes', (
    tester,
  ) async {
    final repository = _ChatRepository(
      friend,
      initialMessages: [
        SocialMessage(
          id: 'voice-quote-actions',
          senderUid: 'friend',
          receiverUid: 'me',
          kind: SocialMessageKind.voice,
          text: '3200',
          mediaUrl: 'https://example.com/voice.m4a',
          sentAt: DateTime.now(),
        ),
      ],
    );
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();

    final voiceMessage = find.byKey(
      const ValueKey('chat-voice-message-voice-quote-actions'),
    );
    await tester.longPress(voiceMessage);
    await tester.pumpAndSettle();

    expect(find.text('收藏'), findsOneWidget);
    expect(find.text('引用'), findsOneWidget);
    expect(find.text('多选'), findsOneWidget);
    await tester.tap(find.text('引用'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-quote-draft')), findsOneWidget);
    expect(find.text('回复：Mest：语音消息'), findsOneWidget);

    await tester.longPress(voiceMessage);
    await tester.pumpAndSettle();
    await tester.tap(find.text('多选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 项'), findsOneWidget);
    expect(find.text('收藏'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    final marker = find.byKey(
      const ValueKey('chat-message-selection-marker-voice-quote-actions'),
    );
    expect(marker, findsOneWidget);
    expect(
      tester.getCenter(marker).dx,
      lessThan(tester.getCenter(voiceMessage).dx),
    );
  });

  testWidgets(
    'received flattened quotes keep the reply bubble separate from its context',
    (tester) async {
      final repository = _ChatRepository(
        friend,
        initialMessages: [
          SocialMessage(
            id: 'quoted-text',
            senderUid: currentUser.uid,
            receiverUid: friend.uid,
            kind: SocialMessageKind.text,
            text: '「引用」Mest：吃完我看看你的小肚——嗯嗯',
            sentAt: DateTime.now(),
          ),
        ],
      );
      await tester.pumpWidget(app(repository));
      await tester.pumpAndSettle();

      expect(find.text('嗯嗯'), findsOneWidget);
      final replyBubble = find.byKey(
        const ValueKey('chat-message-bubble-quoted-text'),
      );
      final quoteContext = find.byKey(
        const ValueKey('chat-quote-context-quoted-text'),
      );
      expect(replyBubble, findsOneWidget);
      expect(quoteContext, findsOneWidget);
      final replyRect = tester.getRect(replyBubble);
      final quoteRect = tester.getRect(quoteContext);
      expect(replyRect.bottom, lessThanOrEqualTo(quoteRect.top));
      expect(find.text('Mest：吃完我看看你的小肚'), findsOneWidget);
      expect(find.text('「引用」Mest：吃完我看看你的小肚——嗯嗯'), findsNothing);
      expect(find.byIcon(Icons.format_quote_rounded), findsNothing);
    },
  );

  testWidgets(
    'long pressing a sent text message opens an anchored action bar',
    (tester) async {
      final repository = _ChatRepository(
        friend,
        initialMessages: [
          SocialMessage(
            id: 'text-actions',
            senderUid: 'me',
            receiverUid: 'friend',
            kind: SocialMessageKind.text,
            text: '可以复制和撤回的消息',
            sentAt: DateTime.now(),
          ),
        ],
      );
      await tester.pumpWidget(app(repository));
      await tester.pumpAndSettle();

      await tester.longPress(
        find.byKey(const ValueKey('chat-message-bubble-text-actions')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('chat-message-action-popover')),
        findsOneWidget,
      );
      expect(find.text('复制'), findsOneWidget);
      expect(find.text('撤回'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);
      expect(find.text('转文字'), findsNothing);
    },
  );

  testWidgets('holding the voice button records, uploads and sends once', (
    tester,
  ) async {
    final repository = _ChatRepository(friend);
    final recorder = _FakeChatVoiceRecorder('C:\\temp\\voice-test.m4a');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(currentUser),
          socialRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ChatPage(
              uid: 'friend',
              voiceRecorder: recorder,
              voicePathFactory: () async => 'C:\\temp\\voice-test.m4a',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-voice-toggle')));
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('chat-hold-to-record'))),
    );
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump(const Duration(seconds: 1));
    expect(recorder.startCalls, 1);
    expect(find.textContaining('松开发送'), findsOneWidget);

    await gesture.up();
    await tester.pump();
    await tester.pump();

    expect(recorder.stopCalls, 1);
    expect(repository.uploadCalls, 1);
    expect(repository.lastUploadKind, SocialMessageKind.voice);
    expect(repository.sendCalls, 1);
    expect(repository.lastKind, SocialMessageKind.voice);
    expect(repository.lastMediaUrl, 'https://example.com/voice.m4a');
    expect(int.parse(repository.lastText!), greaterThanOrEqualTo(700));
  });

  test(
    'message timestamps follow calendar boundaries and omit redundant parts',
    () {
      final now = DateTime(2026, 7, 25, 18, 23);
      expect(
        formatChatMessageTimestamp(DateTime(2026, 7, 25, 8, 6), now: now),
        '08:06',
      );
      expect(
        formatChatMessageTimestamp(DateTime(2026, 7, 24, 8, 6), now: now),
        '昨天 08:06',
      );
      expect(
        formatChatMessageTimestamp(DateTime(2026, 7, 23, 8, 6), now: now),
        '前天 08:06',
      );
      expect(
        formatChatMessageTimestamp(DateTime(2026, 7, 20, 8, 6), now: now),
        '周一 08:06',
      );
      expect(
        formatChatMessageTimestamp(DateTime(2026, 7, 18, 8, 6), now: now),
        '18日 08:06',
      );
      expect(
        formatChatMessageTimestamp(DateTime(2026, 6, 30, 8, 6), now: now),
        '6月30日 08:06',
      );
      expect(
        formatChatMessageTimestamp(DateTime(2025, 12, 31, 8, 6), now: now),
        '2025年12月31日 08:06',
      );
      expect(
        formatChatMessageTimestamp(
          DateTime(2026, 7, 31, 18, 23),
          now: DateTime(2026, 8, 1, 9),
        ),
        '7月31日 18:23',
      );
    },
  );

  test(
    'message timestamps separate the first, next day and five-minute groups',
    () {
      SocialMessage message(String id, DateTime sentAt) => SocialMessage(
        id: id,
        senderUid: 'me',
        receiverUid: 'friend',
        kind: SocialMessageKind.text,
        sentAt: sentAt,
      );

      final first = message('first', DateTime(2026, 7, 25, 18));
      expect(shouldShowChatMessageTimestamp(null, first), isTrue);
      expect(
        shouldShowChatMessageTimestamp(
          first,
          message('nearby', DateTime(2026, 7, 25, 18, 4)),
        ),
        isFalse,
      );
      expect(
        shouldShowChatMessageTimestamp(
          first,
          message('later', DateTime(2026, 7, 25, 18, 5)),
        ),
        isTrue,
      );
      expect(
        shouldShowChatMessageTimestamp(
          first,
          message('tomorrow', DateTime(2026, 7, 26, 0, 1)),
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'video bubble shows duration and viewer uses integrated controls',
    (tester) async {
      final originalPlatform = VideoPlayerPlatform.instance;
      final videoPlatform = _FakeVideoPlayerPlatform(
        duration: const Duration(minutes: 1, seconds: 5),
      );
      VideoPlayerPlatform.instance = videoPlatform;
      addTearDown(() => VideoPlayerPlatform.instance = originalPlatform);
      final repository = _RefreshingVideoChatRepository(friend);

      await tester.pumpWidget(app(repository));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const ValueKey('chat-video-preview')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('chat-video-preview-play')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('chat-video-duration')), findsOneWidget);
      final thumbnail = tester.widget<ArtworkImage>(
        find.byKey(const ValueKey('chat-video-thumbnail')),
      );
      expect(
        thumbnail.uri,
        'assets/images/theme_playlists/shinchan/cover-01.jpg',
      );
      expect(find.text('01:05'), findsOneWidget);
      expect(videoPlatform.createCalls, 1);
      final videoBubble = tester.widget<Container>(
        find.byKey(const ValueKey('chat-message-bubble-video-message')),
      );
      expect(videoBubble.padding, EdgeInsets.zero);
      expect(videoBubble.decoration, isNull);

      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 100));

      final stableThumbnail = tester.widget<ArtworkImage>(
        find.byKey(const ValueKey('chat-video-thumbnail')),
      );
      expect(
        stableThumbnail.uri,
        'assets/images/theme_playlists/shinchan/cover-01.jpg',
      );
      expect(find.text('01:05'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(videoPlatform.createCalls, 1);

      await tester.tap(
        find.byKey(const ValueKey('chat-video-message-video-message')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const ValueKey('chat-video-controls')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-video-progress')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('chat-video-total-duration')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('chat-video-control-true')),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('暂停视频'));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('chat-video-control-false')),
        findsOneWidget,
      );
    },
  );
}

Finder _deliveryFinder(String prefix) {
  return find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> && key.value.startsWith(prefix);
  });
}

Finder _messageTextFinder(String text) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is Text && widget.data == text && widget.style?.fontSize == 38,
  );
}

class _ChatRepository extends Fake implements SocialRepository {
  _ChatRepository(this.friend, {this.initialMessages = const []});

  final SocialUser friend;
  final List<SocialMessage> initialMessages;
  final sendGate = Completer<SocialMessage>();
  int sendCalls = 0;
  SocialMessageKind? lastKind;
  String? lastText;
  String? lastMediaUrl;
  int uploadCalls = 0;
  SocialMessageKind? lastUploadKind;
  int deleteCalls = 0;

  @override
  Future<SocialUser> getUser(String uid) async => friend;

  @override
  Future<List<SocialMessage>> listMessages(String uid) async => initialMessages;

  @override
  Future<void> markRead(String uid) async {}

  @override
  Future<SocialMessage> sendMessage(
    String uid, {
    required SocialMessageKind kind,
    String text = '',
    String? mediaUrl,
    String? thumbnailUrl,
  }) {
    sendCalls += 1;
    lastKind = kind;
    lastText = text;
    lastMediaUrl = mediaUrl;
    return sendGate.future;
  }

  @override
  Future<SocialMessage> recallMessage(String uid, String messageId) async {
    final message = initialMessages.firstWhere(
      (candidate) => candidate.id == messageId,
    );
    return message.copyWith(text: '', recalled: true);
  }

  @override
  Future<void> deleteMessage(String uid, String messageId) async {
    deleteCalls += 1;
  }

  @override
  Future<SocialUpload> uploadMedia({
    required String path,
    required SocialMessageKind kind,
  }) async {
    uploadCalls += 1;
    lastUploadKind = kind;
    return const SocialUpload(
      cloudObjectId: 'cloud://voice/object.m4a',
      downloadUrl: 'https://example.com/voice.m4a',
    );
  }
}

class _PendingChatRepository extends _ChatRepository {
  _PendingChatRepository(super.friend);

  final messages = Completer<List<SocialMessage>>();

  @override
  Future<List<SocialMessage>> listMessages(String uid) => messages.future;
}

class _FakeChatVoiceRecorder implements ChatVoiceRecorder {
  _FakeChatVoiceRecorder(this.outputPath);

  final String outputPath;
  int startCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start(String path) async {
    startCalls += 1;
  }

  @override
  Future<String?> stop() async {
    stopCalls += 1;
    return outputPath;
  }

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
  }

  @override
  Future<void> dispose() async {}
}

class _RefreshingVideoChatRepository extends _ChatRepository {
  _RefreshingVideoChatRepository(super.friend);

  int listCalls = 0;

  @override
  Future<List<SocialMessage>> listMessages(String uid) async {
    listCalls += 1;
    return [
      SocialMessage(
        id: 'video-message',
        senderUid: 'me',
        receiverUid: 'friend',
        kind: SocialMessageKind.video,
        mediaUrl: 'https://example.com/video.mp4?token=$listCalls',
        thumbnailUrl: listCalls.isOdd
            ? 'assets/images/theme_playlists/shinchan/cover-01.jpg'
            : 'assets/images/theme_playlists/shinchan/cover-02.jpg',
        sentAt: DateTime.now(),
      ),
    ];
  }
}

class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  _FakeVideoPlayerPlatform({required this.duration});

  final Duration duration;
  var _nextPlayerId = 1;
  var createCalls = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    createCalls += 1;
    return _nextPlayerId++;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => Stream.value(
    VideoEvent(
      eventType: VideoEventType.initialized,
      duration: duration,
      size: const Size(1920, 1080),
    ),
  );

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const ColoredBox(color: Color(0xFF25202A));

  @override
  Future<void> dispose(int playerId) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}
}
