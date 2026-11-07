import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/auth/auth_providers.dart';
import 'package:mesting_music/features/auth/domain/auth_models.dart';
import 'package:mesting_music/features/social/domain/chat_message_actions.dart';
import 'package:mesting_music/features/social/domain/social_models.dart';
import 'package:mesting_music/features/social/domain/track_share.dart';
import 'package:mesting_music/features/social/presentation/saved_messages_page.dart';
import 'package:mesting_music/features/social/presentation/social_widgets.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('saved cloud media waits for its playable download address', () {
    const cloudObjectId = 'cloud://music-env/social-media/me/voice.m4a';

    expect(playableSavedMessageMediaUrl(cloudObjectId, null), isEmpty);
    expect(
      playableSavedMessageMediaUrl(
        cloudObjectId,
        'https://cdn.example/social-media/me/voice.m4a',
      ),
      'https://cdn.example/social-media/me/voice.m4a',
    );
    expect(
      playableSavedMessageMediaUrl('file:///C:/temp/saved-voice.m4a', null),
      'file:///C:/temp/saved-voice.m4a',
    );
  });

  test(
    'saved media refreshes and downloads a stable local playback file',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'mesting-saved-media-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final mediaFile = File(
        '${directory.path}${Platform.pathSeparator}voice.m4a',
      );
      var forcedRefresh = false;
      String? downloadedUrl;
      String? downloadKey;

      final source = await prepareSavedMessageMediaForPlayback(
        rawValue: 'cloud://music-env/social-media/me/voice.m4a',
        resolve: (value, {forceRefresh = false}) async {
          forcedRefresh = forceRefresh;
          expect(value, 'cloud://music-env/social-media/me/voice.m4a');
          return 'https://cdn.example/social-media/me/voice.m4a?signature=fresh';
        },
        download: (url, cacheKey) async {
          downloadedUrl = url;
          downloadKey = cacheKey;
          await mediaFile.writeAsBytes(const [0, 1, 2, 3], flush: true);
          return mediaFile;
        },
      );

      expect(forcedRefresh, isTrue);
      expect(
        downloadedUrl,
        'https://cdn.example/social-media/me/voice.m4a?signature=fresh',
      );
      expect(
        downloadKey,
        'https://cdn.example/social-media/me/voice.m4a?signature=fresh',
      );
      expect(source, mediaFile.path);
    },
  );

  test(
    'saved media reuses the source already working in the conversation',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'mesting-saved-media-reuse-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final mediaFile = File(
        '${directory.path}${Platform.pathSeparator}voice.m4a',
      );
      await mediaFile.writeAsBytes(const [0, 1, 2, 3], flush: true);
      var resolverCalls = 0;

      final source = await prepareSavedMessageMediaForPlayback(
        rawValue: 'cloud://music-env/social-media/me/voice.m4a',
        resolvedValue: 'https://cdn.example/conversation/voice.m4a',
        resolve: (_, {forceRefresh = false}) async {
          resolverCalls++;
          return null;
        },
        download: (url, cacheKey) async {
          expect(url, 'https://cdn.example/conversation/voice.m4a');
          expect(cacheKey, url);
          return mediaFile;
        },
      );

      expect(source, mediaFile.path);
      expect(resolverCalls, 0);
    },
  );

  test(
    'saved media refreshes only after the conversation source fails',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'mesting-saved-media-fallback-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final mediaFile = File(
        '${directory.path}${Platform.pathSeparator}video.mp4',
      );
      await mediaFile.writeAsBytes(const [0, 1, 2, 3], flush: true);
      final downloadedUrls = <String>[];

      final source = await prepareSavedMessageMediaForPlayback(
        rawValue: 'cloud://music-env/social-media/me/video.mp4',
        resolvedValue: 'https://cdn.example/expired/video.mp4',
        resolve: (_, {forceRefresh = false}) async {
          expect(forceRefresh, isTrue);
          return 'https://cdn.example/fresh/video.mp4';
        },
        download: (url, cacheKey) async {
          expect(cacheKey, url);
          downloadedUrls.add(url);
          if (url.contains('/expired/')) throw Exception('expired');
          return mediaFile;
        },
      );

      expect(source, mediaFile.path);
      expect(downloadedUrls, [
        'https://cdn.example/expired/video.mp4',
        'https://cdn.example/fresh/video.mp4',
      ]);
    },
  );

  testWidgets('saved messages page exposes the stored message collection', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    await writeSavedChatMessages(preferences, 'me', [
      SavedChatMessage(
        id: 'saved-message',
        conversationUid: 'friend',
        senderUid: 'friend',
        authorName: 'Mest',
        kind: SocialMessageKind.text,
        text: '这条消息已经被收藏',
        sentAt: DateTime(2026, 8, 27, 20, 20),
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(
            const AuthUser(uid: 'me', nickname: 'Mesting'),
          ),
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
        child: const MaterialApp(home: Scaffold(body: SavedMessagesPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('收藏消息'), findsOneWidget);
    expect(find.byKey(const ValueKey('saved-messages-list')), findsOneWidget);
    expect(find.text('Mest'), findsOneWidget);
    expect(find.text('这条消息已经被收藏'), findsOneWidget);
    expect(find.byType(SocialHeaderButton), findsNothing);
  });

  testWidgets('long press removes a saved entry from both collection stores', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final savedMessage = SavedChatMessage(
      id: 'saved-message',
      conversationUid: 'friend',
      senderUid: 'friend',
      authorName: 'Mest',
      kind: SocialMessageKind.text,
      text: '需要删除的收藏',
      sentAt: DateTime(2026, 8, 29, 12, 9),
    );
    final remainingMessage = SavedChatMessage(
      id: 'remaining-message',
      conversationUid: 'friend',
      senderUid: 'friend',
      authorName: 'Mest',
      kind: SocialMessageKind.text,
      text: '继续保留的收藏',
      sentAt: DateTime(2026, 8, 28, 12, 9),
    );
    await writeSavedChatMessageIds(preferences, 'me', {
      savedMessage.id,
      remainingMessage.id,
    });
    await writeSavedChatMessages(preferences, 'me', [
      savedMessage,
      remainingMessage,
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(
            const AuthUser(uid: 'me', nickname: 'Mesting'),
          ),
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
        child: const MaterialApp(home: Scaffold(body: SavedMessagesPage())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(
      find.byKey(const ValueKey('saved-message-row-saved-message')),
    );
    await tester.pumpAndSettle();

    expect(find.text('收藏操作'), findsOneWidget);
    expect(find.text('删除收藏'), findsOneWidget);
    expect(find.textContaining('不会删除好友会话里的原消息'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('delete-saved-message-saved-message')),
    );
    await tester.pumpAndSettle();

    expect(find.text('需要删除的收藏'), findsNothing);
    expect(find.text('继续保留的收藏'), findsOneWidget);
    expect(find.text('已删除收藏'), findsOneWidget);
    expect(readSavedChatMessageIds(preferences, 'me'), <String>{
      remainingMessage.id,
    });
    expect(
      readSavedChatMessages(preferences, 'me').map((message) => message.id),
      <String>[remainingMessage.id],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a saved message opens its own detail instead of the chat', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    await writeSavedChatMessages(preferences, 'me', [
      SavedChatMessage(
        id: 'saved-message',
        conversationUid: 'friend',
        senderUid: 'friend',
        authorName: 'Mest',
        kind: SocialMessageKind.text,
        text: '这条消息已经被收藏',
        sentAt: DateTime(2026, 8, 27, 20, 20),
      ),
    ]);
    final router = GoRouter(
      initialLocation: '/saved',
      routes: [
        GoRoute(
          path: '/saved',
          builder: (context, state) =>
              const Scaffold(body: SavedMessagesPage()),
        ),
        GoRoute(
          path: '/social/saved-messages/:messageId',
          builder: (context, state) => Scaffold(
            body: SavedMessageDetailPage(
              messageId: state.pathParameters['messageId']!,
            ),
          ),
        ),
        GoRoute(
          path: '/social/chat/:uid',
          builder: (context, state) =>
              const Scaffold(body: Text('original-chat-page')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(
            const AuthUser(uid: 'me', nickname: 'Mesting'),
          ),
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('saved-message-row-saved-message')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('saved-message-detail')), findsOneWidget);
    expect(find.text('收藏详情'), findsOneWidget);
    expect(find.text('这条消息已经被收藏'), findsOneWidget);
    expect(find.text('original-chat-page'), findsNothing);
  });

  testWidgets('saved song snapshot exposes the real playback action', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    const track = Track(
      id: 'saved-track',
      title: '收藏的歌曲',
      artist: 'Mesti',
      album: '收藏歌单',
      duration: Duration(minutes: 3),
      audioAsset: 'https://example.com/saved-track.mp3',
      coverAsset: '',
      lyricsAsset: '',
    );
    await writeSavedChatMessages(preferences, 'me', [
      SavedChatMessage(
        id: 'saved-track-message',
        conversationUid: 'friend',
        senderUid: 'friend',
        authorName: 'Mest',
        kind: SocialMessageKind.text,
        text: encodeTrackShareMessage(track),
        sentAt: DateTime(2026, 8, 28, 1),
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(
            const AuthUser(uid: 'me', nickname: 'Mesting'),
          ),
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SavedMessageDetailPage(messageId: 'saved-track-message'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey('saved-message-shared-track-play-saved-track-message'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('saved voice and video snapshots expose media playback entries', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();

    Widget detail(String messageId) => ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(
          const AuthUser(uid: 'me', nickname: 'Mesting'),
        ),
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
      child: MaterialApp(
        home: Scaffold(body: SavedMessageDetailPage(messageId: messageId)),
      ),
    );

    await writeSavedChatMessages(preferences, 'me', [
      SavedChatMessage(
        id: 'saved-voice-message',
        conversationUid: 'friend',
        senderUid: 'friend',
        authorName: 'Mest',
        kind: SocialMessageKind.voice,
        text: '3200',
        mediaUrl: 'file:///C:/temp/saved-voice.m4a',
        sentAt: DateTime(2026, 8, 28, 1),
      ),
    ]);
    await tester.pumpWidget(detail('saved-voice-message'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const ValueKey('saved-message-voice-message-saved-voice-message'),
      ),
      findsOneWidget,
    );

    await writeSavedChatMessages(preferences, 'me', [
      SavedChatMessage(
        id: 'saved-video-message',
        conversationUid: 'friend',
        senderUid: 'friend',
        authorName: 'Mest',
        kind: SocialMessageKind.video,
        text: '',
        mediaUrl: 'file:///C:/temp/saved-video.mp4',
        sentAt: DateTime(2026, 8, 28, 1),
      ),
    ]);
    await tester.pumpWidget(detail('saved-video-message'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const ValueKey('saved-message-video-message-saved-video-message'),
      ),
      findsOneWidget,
    );
  });
}
