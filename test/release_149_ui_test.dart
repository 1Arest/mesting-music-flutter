import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/auth/auth_providers.dart';
import 'package:mesting_music/features/auth/domain/auth_models.dart';
import 'package:mesting_music/features/experience/presentation/favorite_tracks_search.dart';
import 'package:mesting_music/features/library/data/favorite_track_window.dart';
import 'package:mesting_music/features/library/library_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_features_page.dart';
import 'package:mesting_music/features/music_platform/netease/netease_features_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_item_artwork.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_messages_page.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_messages_repository.dart';
import 'package:mesting_music/features/music_platform/platform_backend_providers.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_comment_composer.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_design.dart';
import 'package:mesting_music/features/social/domain/social_models.dart';
import 'package:mesting_music/features/social/presentation/social_messages_page.dart';
import 'package:mesting_music/features/social/presentation/social_widgets.dart';
import 'package:mesting_music/features/social/social_providers.dart';
import 'package:mesting_music/features/social/data/social_repository.dart';
import 'package:mesting_music/shared/models/song_list_memory.dart';
import 'package:mesting_music/shared/models/track_page.dart';
import 'package:mesting_music/shared/widgets/song_list_tools.dart';
import 'package:mesting_music/shared/widgets/music_activity_indicator.dart';
import 'support/personal_profile_fixture.dart';
import 'support/release_147_qa.dart';
import 'release_148_data_test.dart' show Metadata148;
import 'release_148_ui_test.dart' show mount148, shot148;
import 'release_146_ui_test.dart' show ready146;

const capture149 = bool.fromEnvironment('CAPTURE_148');

// Flutter's host-test default font has no Chinese subtitle glyphs. Limit this
// font substitution to captures; production/theme source remains untouched.
Widget inbox149() => capture149
    ? Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return Theme(
            data: theme.copyWith(
              listTileTheme: theme.listTileTheme.copyWith(
                subtitleTextStyle: theme.listTileTheme.subtitleTextStyle
                    ?.copyWith(fontFamily: 'MestingQA148'),
              ),
            ),
            child: const NeteaseMessagesPage(),
          );
        },
      )
    : const NeteaseMessagesPage();

class _Categories extends NeteaseFeaturesRepository {
  _Categories(super.music);
  @override
  Future<NeteaseBatch> load(
    NeteaseFeed feed, {
    int page = 1,
    int before = 0,
    String id = '',
    String category = '全部',
    String area = 'ALL',
    int artistArea = 1,
  }) async => const NeteaseBatch([
    NeteaseItem(id: '综艺', name: '综艺', kind: NeteaseEntity.category),
    NeteaseItem(id: '流行', name: '流行', kind: NeteaseEntity.category),
    NeteaseItem(id: '怀旧', name: '怀旧', kind: NeteaseEntity.category),
  ]);
}

class _CategoryImages extends NeteaseArtworkRepository {
  _CategoryImages(super.music);
  final gates = <String, Completer<String>>{};
  @override
  Future<String> category(
    String name, {
    bool refresh = false,
    String rejected = '',
  }) => gates.putIfAbsent(name, Completer<String>.new).future;
}

class _Inbox149 extends NeteaseMessagesRepository {
  _Inbox149(super.music);
  final pending = Completer<List<NeteaseConversation>>();
  var calls = 0;
  final person = const NeteasePerson(
    'friend149',
    '返回后仍在原位的好友',
    profileFixtureCover,
  );
  List<NeteaseConversation> get rows => [
    NeteaseConversation(
      person,
      NeteaseChatMessage(
        id: 'message149',
        from: person,
        to: const NeteasePerson('7001', '自己'),
        text: '保留这条会话',
        time: DateTime(2026, 11, 4),
      ),
      1,
    ),
  ];
  @override
  Future<List<NeteaseConversation>> conversations([int offset = 0]) =>
      calls++ == 0 ? Future.value(rows) : pending.future;
  @override
  Future<Map<String, int>> counts() async => {};
  @override
  Future<List<NeteaseChatMessage>> history(
    String peer, [
    int before = 0,
  ]) async => [];
}

class _User149 extends Notifier<AuthUser?> {
  @override
  AuthUser? build() => const AuthUser(uid: 'one', nickname: '一');
  void change() => state = const AuthUser(uid: 'two', nickname: '二');
}

class _Social149 implements SocialRepository {
  final waiting = Completer<List<SocialConversation>>();
  int calls = 0;
  @override
  Future<List<SocialConversation>> listConversations() => calls++ == 0
      ? Future.value([
          SocialConversation(
            peer: const SocialUser(uid: 'old-peer', nickname: '旧账号好友'),
            updatedAt: DateTime(2026, 11, 4),
          ),
        ])
      : waiting.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (capture149) {
      await load147IconFonts();
      for (final family in [
        'MestingQA148',
        'Roboto',
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
        'sans-serif',
      ]) {
        await (FontLoader(family)..addFont(
              File(
                'C:/Windows/Fonts/msyh.ttc',
              ).readAsBytes().then(ByteData.sublistView),
            ))
            .load();
      }
    }
  });
  test(
    'conversation refresh cache is invalidated by owner identity even with a retained repository',
    () async {
      final users = NotifierProvider<_User149, AuthUser?>(_User149.new);
      final repo = _Social149();
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWith((ref) => ref.watch(users)),
          socialRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      final first = container.listen(
        socialConversationsByOwnerProvider('one'),
        (_, _) {},
      );
      addTearDown(first.close);
      expect(
        (await container.read(
          socialConversationsByOwnerProvider('one').future,
        )).single.peer.uid,
        'old-peer',
      );
      container.read(users.notifier).change();
      final second = container.listen(
        socialConversationsByOwnerProvider('two'),
        (_, _) {},
      );
      addTearDown(second.close);
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(socialConversationsByOwnerProvider('two')).value,
        isNull,
      );
      expect(
        await container.read(socialConversationsByOwnerProvider('one').future),
        isEmpty,
      );
      repo.waiting.complete([]);
      expect(
        await container.read(socialConversationsByOwnerProvider('two').future),
        isEmpty,
      );
      expect(repo.calls, 2);
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      'narrow large text list hint retains tappable controls dark=$dark',
      (tester) async {
        final fixture = await PersonalProfileFixture.create();
        addTearDown(fixture.dispose);
        final store = SongListMemory(
          fixture.container.read(sharedPreferencesProvider),
        );
        addTearDown(store.dispose);
        store.remember('netease:7001', 'favorites:', fixture.tracks[15]);
        await mount148(
          tester,
          fixture,
          SongListOwnerScope(
            owner: 'netease:7001',
            memory: store,
            child: Scaffold(
              body: FavoriteTracksSearch(
                tracks: fixture.tracks,
                header: const Padding(
                  padding: EdgeInsets.all(22),
                  child: Text('我的喜欢'),
                ),
                onRefresh: () async {},
                onCreatePlaylist: () {},
              ),
            ),
          ),
          dark: dark,
          large: true,
        );
        await tester.pump();
        expect(
          tester.getSize(find.byKey(const ValueKey('song-list-dismiss'))).width,
          44,
        );
        await shot148(tester, 'bookmark-narrow-$dark');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'favorite list exposes its account bookmark above the chrome dark=$dark',
      (tester) async {
        final fixture = await PersonalProfileFixture.create();
        addTearDown(fixture.dispose);
        final store = SongListMemory(
          fixture.container.read(sharedPreferencesProvider),
        );
        addTearDown(store.dispose);
        store.remember('netease:7001', 'favorites:', fixture.tracks[15]);
        await store.flush();
        await mount148(
          tester,
          fixture,
          SongListOwnerScope(
            owner: 'netease:7001',
            memory: store,
            child: Scaffold(
              body: FavoriteTracksSearch(
                tracks: fixture.tracks,
                header: const Padding(
                  padding: EdgeInsets.all(22),
                  child: Text('674 首歌曲'),
                ),
                onRefresh: () async {},
                onCreatePlaylist: () {},
              ),
            ),
          ),
          dark: dark,
        );
        await tester.pump();
        await tester.pump();
        expect(
          find.byKey(const ValueKey('song-list-last-played')),
          findsOneWidget,
        );
        await shot148(tester, 'bookmark-favorites-$dark');
        await tester.tap(find.byKey(const ValueKey('song-list-last-played')));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byKey(const ValueKey('song-list-top')), findsOneWidget);
        await shot148(tester, 'bookmark-located-$dark');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'NetEase chat pop keeps inbox geometry while refresh waits dark=$dark',
      (tester) async {
        late _Inbox149 repository;
        final fixture = await PersonalProfileFixture.create(
          extraOverrides: [
            neteaseMessagesRepositoryProvider.overrideWith((ref) {
              repository = _Inbox149(ref.read(neteaseMusicRepositoryProvider));
              ref.onDispose(repository.dispose);
              return repository;
            }),
          ],
        );
        addTearDown(fixture.dispose);
        await mount148(tester, fixture, inbox149(), dark: dark);
        final friend = find.text(repository.person.name);
        expect(friend, findsOneWidget);
        final original = tester.getCenter(friend);
        await tester.tap(friend);
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        final destination = find.byType(NeteaseChatPage);
        Navigator.of(tester.element(destination)).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await shot148(tester, 'inbox-pop-$dark');
        await tester.pump(const Duration(milliseconds: 400));
        expect(repository.calls, 2);
        expect(tester.getCenter(friend).dy, closeTo(original.dy, .5));
        await shot148(tester, 'inbox-refresh-$dark');
        repository.pending.complete(repository.rows);
        await tester.pump();
        await tester.pump();
        expect(tester.getCenter(friend).dy, closeTo(original.dy, .5));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
    for (final resize in [false, true]) {
      testWidgets(
        'favorite search uses an unpanelled spinner above real keyboard insets resize=$resize dark=$dark',
        (tester) async {
          final gate = Completer<TrackPage>();
          addTearDown(() {
            if (!gate.isCompleted) {
              gate.complete(TrackPage([], offset: 0, hasMore: false));
            }
          });
          late PersonalProfileFixture fixture;
          final preview = StreamController<TrackPage>();
          addTearDown(preview.close);
          fixture = await PersonalProfileFixture.create(
            extraOverrides: [
              favoriteTrackWindowProvider.overrideWith((ref) {
                final window = FavoriteTrackWindow(
                  ref.read(libraryRepositoryProvider),
                  preview: preview.stream,
                  readPage: (offset, limit) => gate.future,
                );
                ref.onDispose(window.dispose);
                return window;
              }),
            ],
          );
          addTearDown(fixture.dispose);
          // The real library page initializes this provider before mounting
          // its search child; reproduce that boundary in this isolated page.
          fixture.container.read(favoriteTrackWindowProvider);
          await mount148(
            tester,
            fixture,
            Scaffold(
              resizeToAvoidBottomInset: resize,
              body: SafeArea(
                child: FavoriteTracksSearch(
                  tracks: fixture.tracks.take(30).toList(),
                  header: const Padding(
                    padding: EdgeInsets.all(22),
                    child: Text('674 首歌曲'),
                  ),
                  onRefresh: () async {},
                  onCreatePlaylist: () {},
                ),
              ),
            ),
            dark: dark,
          );
          preview.add(
            TrackPage(
              fixture.tracks.take(30).toList(),
              offset: 0,
              hasMore: true,
              total: 674,
            ),
          );
          await tester.pump();
          await tester.tap(find.byTooltip('搜索我的喜欢'));
          await tester.pump();
          tester.view.viewInsets = const FakeViewPadding(bottom: 310);
          tester.view.padding = const FakeViewPadding(top: 24);
          await tester.pump();
          await tester.enterText(find.byType(TextField), '测试');
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(PlatformPanel), findsNothing);
          expect(find.byType(MusicActivityIndicator), findsWidgets);
          final composer = tester.getRect(find.byType(PlatformCommentComposer));
          expect(composer.bottom, lessThanOrEqualTo(534.1));
          await shot148(tester, 'search-spinner-$resize-$dark');
          gate.complete(
            TrackPage([fixture.tracks[3]], offset: 0, hasMore: false, total: 1),
          );
          await tester.pump();
          await ready146(tester);
          expect(find.text('测试歌曲 3'), findsOneWidget);
          expect(find.byType(PlatformPanel), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
    testWidgets(
      'category metadata and images share their initial readiness boundary dark=$dark',
      (tester) async {
        final music = Metadata148((_, _) async => {});
        final images = _CategoryImages(music);
        final fixture = await PersonalProfileFixture.create(
          extraOverrides: [
            neteaseFeaturesProvider.overrideWithValue(_Categories(music)),
            neteaseArtworkRepositoryProvider.overrideWithValue(images),
          ],
        );
        addTearDown(fixture.dispose);
        await mount148(
          tester,
          fixture,
          const NeteaseFeaturesPage(feed: NeteaseFeed.categories),
          dark: dark,
        );
        expect(images.gates.length, 3);
        for (final gate in images.gates.values) {
          gate.complete(profileFixtureCover);
        }
        await tester.pump();
        await ready146(tester);
        expect(find.text('重试'), findsNothing);
        expect(find.byType(Image), findsNWidgets(3));
        await shot148(tester, 'category-ready-$dark');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'messages retain the same owners rows during background reload dark=$dark',
      (tester) async {
        var calls = 0;
        final gate = Completer<List<SocialConversation>>();
        SocialConversation row(String name) => SocialConversation(
          peer: SocialUser(
            uid: 'friend',
            nickname: name,
            avatarUrl: profileFixtureCover,
          ),
          updatedAt: DateTime(2026, 11, 4, 10),
          unreadCount: 3,
        );
        final fixture = await PersonalProfileFixture.create(
          extraOverrides: [
            currentUserProvider.overrideWithValue(
              const AuthUser(uid: 'ui-owner', nickname: '测试'),
            ),
            socialConversationsProvider.overrideWith(
              (_) =>
                  calls++ == 0 ? Future.value([row('好友列表已显示')]) : gate.future,
            ),
          ],
        );
        addTearDown(fixture.dispose);
        await mount148(
          tester,
          fixture,
          const Material(
            type: MaterialType.transparency,
            child: SocialMessagesPage(),
          ),
          dark: dark,
        );
        await tester.pump();
        await tester.pump();
        await ready146(tester);
        expect(find.text('好友列表已显示'), findsOneWidget);
        fixture.container.invalidate(socialConversationsProvider);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        expect(find.text('好友列表已显示'), findsOneWidget);
        expect(find.byType(SocialLoadingState), findsNothing);
        await shot148(tester, 'messages-retained-$dark');
        gate.complete([row('好友列表已更新')]);
        await tester.pump();
        await tester.pump();
        expect(find.text('好友列表已更新'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
