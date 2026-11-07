import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/features/music_platform/retained_kugou_scope.dart';
import 'package:mesting_music/features/music_platform/platform_backend_providers.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_messages_page.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_messages_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_user_page.dart';
import 'package:mesting_music/features/experience/presentation/player_artwork_transition.dart';
import 'package:mesting_music/features/player/presentation/player_visual_stages.dart';
import 'package:mesting_music/features/player/player_visual_style.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/features/experience/presentation/beta_bottom_bar.dart';
import 'package:mesting_music/features/experience/presentation/beta_music_shell.dart';
import 'package:mesting_music/features/experience/presentation/floating_playback_pill.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_comment_composer.dart';
import 'package:mesting_music/features/player/presentation/vinyl_disc.dart';
import 'package:mesting_music/shared/widgets/beta_anchored_menu.dart';
import 'package:mesting_music/shared/widgets/beta_root_tab_viewport.dart';
import 'package:mesting_music/shared/widgets/beta_edge_back.dart';

import 'support/personal_profile_fixture.dart';
import 'support/deterministic_audio_player.dart';
import 'support/release_143_qa.dart';

class _Messages extends NeteaseMessagesRepository {
  _Messages(super.music);
  @override
  Future<List<NeteaseChatMessage>> history(
    String peer, [
    int before = 0,
  ]) async => [
    NeteaseChatMessage.parse({
      'id': 901,
      'time': 1793629980000,
      'fromUser': {'userId': 8, 'nickname': '合成测试好友'},
      'toUser': {'userId': 7001},
      'msg': '{"type":1,"msg":"合成聊天"}',
    }),
  ];
}

void main() {
  setUpAll(initialize143QA);

  for (final label in ['最热', '全部']) {
    testWidgets('closing comment $label menu never focuses its composer', (
      tester,
    ) async {
      final draft = TextEditingController();
      final selected = <String>[];
      final navigation = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          builder: capture143Builder,
          theme: theme143(true),
          navigatorKey: navigation,
          home: BetaEdgeBack(
            child: Scaffold(
              body: Column(
                children: [
                  BetaAnchoredMenu<String>(
                    tooltip: '筛选',
                    value: label,
                    values: [label, '另一个选项'],
                    label: (value) => value,
                    onSelected: selected.add,
                  ),
                  const Spacer(),
                  PlatformCommentComposer(
                    controller: draft,
                    sending: false,
                    onSend: () {},
                    keyboardVisible: false,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final editable = find.byType(EditableText);
      final originalEditor = tester.element(editable);
      expect(tester.widget<EditableText>(editable).focusNode.hasFocus, false);
      // Android's Back/IME-hide keeps the editor focused. Restoring that route
      // after a menu must not issue another TextInput.show in this state.
      await tester.tap(find.byType(TextField));
      await tester.pump();
      tester.testTextInput.hide();
      expect(tester.testTextInput.isVisible, false);
      for (final select in [false, true]) {
        await tester.tap(find.byTooltip('筛选'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 450));
        if (select) {
          await tester.tap(find.text('另一个选项'));
        } else {
          navigation.currentState!.pop();
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(
          tester.testTextInput.isVisible,
          false,
          reason: 'Dismissal must not reopen a manually hidden keyboard.',
        );
        if (select) expect(selected, ['另一个选项']);
        expect(
          identical(tester.element(editable), originalEditor),
          true,
          reason: 'A popup must not remount the underlying editor or filter.',
        );
      }
      await capture143UI(tester, 'comments-menu-$label-closed');
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(tester.widget<EditableText>(editable).focusNode.hasFocus, true);
      await tester.pumpWidget(const SizedBox());
      draft.dispose();
    });
  }

  testWidgets('vinyl label stays round under the classic tonearm inset', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: capture143Builder,
        theme: theme143(true),
        home: Center(
          child: SizedBox(
            width: 240,
            height: 212,
            child: VinylDiscSurface(coverAsset: profileFixtureCover),
          ),
        ),
      ),
    );
    await tester.pump();
    final label = tester.getSize(find.byType(ClipOval));
    expect(label.width, closeTo(label.height, .01));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pump();
    await capture143UI(tester, 'vinyl-round');
  });

  for (final source in [TrackSource.netease, TrackSource.kugou]) {
    testWidgets(
      'active root tab scroll compacts capsule across its PageView ${source.name}',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final current = ScrollController(), hidden = ScrollController();
        final dependencies = (await tester.runAsync(() async {
          final handler = MestingAudioHandler(
            tracks: [],
            player: DeterministicAudioPlayer(),
          );
          final fixture = await PersonalProfileFixture.create(
            audioHandler: handler,
            extraOverrides: [
              savedKugouSessionProvider.overrideWith((ref) async => null),
              currentTrackProvider.overrideWithValue(
                Track(
                  id: '${source.name}_17',
                  platformSongId: '17',
                  source: source,
                  title: '合成测试歌曲',
                  artist: '合成艺术家',
                  album: '',
                  duration: const Duration(minutes: 4),
                  audioAsset: '',
                  lyricsAsset: '',
                  coverAsset: profileFixtureCover,
                ),
              ),
              currentMediaItemProvider.overrideWith(
                (ref) => Stream.value(
                  const MediaItem(id: 'synthetic', title: '测试歌曲'),
                ),
              ),
            ],
          );
          return (handler, fixture);
        }))!;
        final (handler, fixture) = dependencies;
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(() async {
            await fixture.dispose();
            await handler.debugDispose();
          });
          current.dispose();
          hidden.dispose();
        });
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: fixture.container,
            child: MaterialApp(
              builder: capture143Builder,
              theme: theme143(true),
              home: BetaMusicShell(
                location: '/profile',
                child: BetaRootTabViewport(
                  index: 0,
                  children: [
                    ListView(
                      controller: current,
                      children: const [SizedBox(height: 2500)],
                    ),
                    ListView(
                      controller: hidden,
                      children: const [SizedBox(height: 2500)],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.drag(
          find.byType(ListView).hitTestable(),
          const Offset(0, -330),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          tester
              .widget<BetaMusicBottomBar>(find.byType(BetaMusicBottomBar))
              .inline,
          true,
        );
        expect(
          tester
              .widget<FloatingPlaybackPill>(find.byType(FloatingPlaybackPill))
              .compact,
          true,
        );
        final compactRect = tester.getRect(find.byType(FloatingPlaybackPill));
        expect(
          compactRect.width,
          lessThan(300),
          reason: 'The real accessory must occupy its inline slot.',
        );
        await capture143UI(tester, 'capsule-compact-${source.name}');
        current.jumpTo(0);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          tester
              .widget<BetaMusicBottomBar>(find.byType(BetaMusicBottomBar))
              .inline,
          false,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'pending next cover retains the previous stage and rejects an old completion',
    (tester) async {
      final pending = <String, Completer<bool>>{};
      Track track(String id, String uri) => Track(
        id: id,
        title: id,
        artist: '合成',
        album: '',
        duration: Duration.zero,
        audioAsset: '',
        lyricsAsset: '',
        coverAsset: uri,
      );
      Future<void> mount(Track value) async {
        await tester.pumpWidget(
          MaterialApp(
            builder: capture143Builder,
            theme: theme143(true),
            home: Center(
              child: SizedBox.square(
                dimension: 240,
                child: PlayerArtworkTransition(
                  track: value,
                  style: PlayerVisualStyle.classic,
                  playing: false,
                  prepare: (uri) => (pending[uri] ??= Completer()).future,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      await mount(track('first', profileFixtureCover));
      await mount(track('second', 'https://example.test/two.jpg'));
      expect(
        tester
            .widget<PlayerArtworkStage>(find.byType(PlayerArtworkStage))
            .track
            .id,
        'first',
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      await capture143UI(tester, 'pending-cover-retained');
      await mount(track('third', 'https://example.test/three.jpg'));
      pending['https://example.test/two.jpg']!.complete(true);
      await tester.pump();
      expect(
        tester
            .widget<PlayerArtworkStage>(find.byType(PlayerArtworkStage))
            .track
            .id,
        'first',
      );
      pending['https://example.test/three.jpg']!.complete(false);
      await tester.pump();
      expect(find.text('封面加载失败，点击重试'), findsOneWidget);
      expect(
        tester
            .widget<PlayerArtworkStage>(find.byType(PlayerArtworkStage))
            .track
            .id,
        'first',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'chat friend avatar opens that public profile and preserves the draft on return',
    (tester) async {
      final fixture = (await tester.runAsync(
        () => PersonalProfileFixture.create(
          extraOverrides: [
            neteaseMessagesRepositoryProvider.overrideWith(
              (ref) => _Messages(ref.read(neteaseMusicRepositoryProvider)),
            ),
          ],
        ),
      ))!;
      final navigation = GlobalKey<NavigatorState>();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(fixture.dispose);
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: fixture.container,
          child: MaterialApp(
            builder: capture143Builder,
            theme: theme143(true),
            navigatorKey: navigation,
            home: const NeteaseChatPage(peer: NeteasePerson('8', '合成测试好友')),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(TextField), '未发送的草稿');
      await tester.tap(find.byType(NeteasePersonAvatar).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester
            .widget<NeteaseUserProfilePage>(find.byType(NeteaseUserProfilePage))
            .user
            .id,
        '8',
      );
      navigation.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('未发送的草稿'), findsOneWidget);
    },
  );
}
