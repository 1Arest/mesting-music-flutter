import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/music_platform/data/platform_comments_repository.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/netease/full/netease_catalog.dart';
import 'package:mesting_music/features/music_platform/netease/full/netease_content.dart';
import 'package:mesting_music/features/music_platform/netease/full/netease_full_page.dart';
import 'package:mesting_music/features/music_platform/netease/full/netease_full_repository.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_messages_page.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_messages_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_comment_hugs_page.dart';
import 'package:mesting_music/features/music_platform/netease/netease_comments_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/together/together_record.dart';
import 'package:mesting_music/features/music_platform/netease/together/together_records_page.dart';
import 'package:mesting_music/features/music_platform/netease/together/together_records_repository.dart';
import 'package:mesting_music/features/music_platform/platform_backend_providers.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_comment_card.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_comments_page.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_lazy_list.dart';

import 'support/personal_profile_fixture.dart';
import 'support/release_144_qa.dart';

const _size = 3000;
const _resource = PlatformCommentResource(
  kind: PlatformCommentKind.song,
  id: '147-fixture',
  name: 'Offline fixture',
);

/// Count comparator reads separately from network or frame-rate assumptions.
/// Visible cards also read likes, so the assertion allows bounded viewport work.
class _CountedComment extends PlatformComment {
  _CountedComment(int index)
    : _rank = _size - index,
      super(
        id: 'c$index',
        userId: index % 100 == 0 ? '7001' : 'other',
        nickname: 'comment $index',
        content: 'Comment body $index',
      );
  static int reads = 0;
  final int _rank;
  @override
  int get likes {
    reads++;
    return _rank;
  }
}

class _Comments extends NeteaseCommentsRepository {
  _Comments(NeteaseMusicRepository music, PersonalProfileFixture fixture)
    : super(
        fixture.container.read(musicPlatformApiProvider),
        fixture.container.read(platformAccountProvider).value!,
        music,
      );
  final comments = List.generate(_size, _CountedComment.new);
  @override
  Future<PlatformCommentPage> loadSorted(
    PlatformCommentResource resource, {
    int page = 1,
    PlatformComment? thread,
    required PlatformCommentSort sort,
  }) async => PlatformCommentPage(comments, false);
  @override
  Future<Map<String, dynamic>> hugs(
    PlatformCommentResource resource,
    PlatformComment comment, {
    int page = 1,
    String cursor = '-1',
    String idCursor = '-1',
  }) async => {
    'data': {
      'users': List.generate(
        _size,
        (i) => {'userId': '${10000 + i}', 'nickname': 'hug $i'},
      ),
      'hasMore': false,
    },
  };
}

class _Messages extends NeteaseMessagesRepository {
  _Messages(super.music);
  int visibleCalls = 0;
  @override
  NeteaseConversation visibleConversation(NeteaseConversation value) {
    visibleCalls++;
    return super.visibleConversation(value);
  }

  @override
  Future<List<NeteaseConversation>> conversations([int offset = 0]) async =>
      List.generate(_size, (i) {
        final person = NeteasePerson('${10000 + i}', 'peer $i');
        return NeteaseConversation(
          person,
          NeteaseChatMessage(
            id: 'message$i',
            from: person,
            to: const NeteasePerson('7001', 'Self'),
            text: 'message $i',
            time: DateTime(2026, 11, 3),
          ),
          i == 0 ? 9 : 0,
        );
      });
  @override
  Future<Map<String, int>> counts() async => {};
  @override
  Future<List<NeteasePerson>> friends([int offset = 0]) async =>
      List.generate(_size, (i) => NeteasePerson('${10000 + i}', 'friend $i'));
  @override
  Future<List<NeteaseMessageNotice>> notices(
    NeteaseNoticeKind kind, [
    int before = -1,
    int offset = 0,
  ]) async => List.generate(
    _size,
    (i) => NeteaseMessageNotice(
      'notice$i',
      NeteasePerson('${10000 + i}', 'notice $i'),
      'Offline notice body',
      DateTime(2026, 11, 3),
    ),
  );
}

class _Records extends NeteaseTogetherRecordsRepository {
  _Records(super.music);
  @override
  void checkOwner() {}
  @override
  Future<NeteaseTogetherHistoryPageData> history({String? cursor}) async =>
      NeteaseTogetherHistoryPageData(
        records: List.generate(
          _size,
          (i) => NeteaseTogetherRecord(
            id: 'record$i',
            roomId: 'room$i',
            dateLabel: 'day ${i ~/ 20}',
            peer: NeteaseTogetherProfile(id: '${10000 + i}', name: 'record $i'),
            duration: const Duration(minutes: 3),
            songCount: 2,
          ),
        ),
        vip: true,
        hasMore: false,
      );
}

class _Full extends NeteaseFullRepository {
  _Full(super.music);
  int calls = 0;
  @override
  Future<Map<String, dynamic>> run(
    NeteaseEndpoint endpoint,
    Map<String, Object?> input,
  ) async {
    calls++;
    return {
      'items': List.generate(_size, (i) => {'id': '$i', 'name': 'result $i'}),
    };
  }
}

void main() {
  setUpAll(initialize144QA);

  Future<PersonalProfileFixture> fixture(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final value = await PersonalProfileFixture.create(
      extraOverrides: [
        neteaseMessagesRepositoryProvider.overrideWith((ref) {
          final repo = _Messages(ref.watch(neteaseMusicRepositoryProvider));
          ref.onDispose(repo.dispose);
          return repo;
        }),
        neteaseTogetherRecordsRepositoryProvider.overrideWith(
          (ref) => _Records(ref.watch(neteaseMusicRepositoryProvider)),
        ),
        neteaseFullRepositoryProvider.overrideWith(
          (ref) => _Full(ref.watch(neteaseMusicRepositoryProvider)),
        ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await value.dispose();
    });
    return value;
  }

  Future<void> mount(
    WidgetTester tester,
    PersonalProfileFixture fixture,
    Widget page, {
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: fixture.container,
        child: MaterialApp(theme: theme144(false), home: page),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    expect(tester.takeException(), isNull);
  }

  Future<void> end(WidgetTester tester) async {
    final state = tester.state<ScrollableState>(find.byType(Scrollable).first);
    // Variable-height rows may refine their end estimate after the first jump.
    for (var i = 0; i < 4; i++) {
      state.position.jumpTo(state.position.maxScrollExtent);
      await tester.pumpAndSettle();
    }
  }

  testWidgets('10000 retained rows create only the first and next viewports', (
    tester,
  ) async {
    var oldCreations = 0;
    final oldRows = List.generate(10000, (index) {
      oldCreations++;
      return Text('old $index');
    });
    expect(oldRows.length, 10000);
    expect(oldCreations, 10000);
    final created = <int>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: buildPlatformLazyList(
            header: const [SizedBox(height: 40, child: Text('Header'))],
            itemCount: 10000,
            itemBuilder: (_, index) {
              created.add(index);
              return SizedBox(height: 72, child: Text('row $index'));
            },
            footer: const [SizedBox(height: 60, child: Text('Final footer'))],
          ),
        ),
      ),
    );
    expect(created.length, lessThan(40));
    final first = created.length;
    expect(find.text('row 9999'), findsNothing);
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('row 9999'), findsNothing);
    expect(created.any((index) => index >= first), isTrue);
    expect(created.length, lessThan(80));
    // Evidence concerns Widget construction, not synthetic host GPU/FPS.
    debugPrint(
      'release147 lazy rows: old=$oldCreations first=$first '
      'afterScroll=${created.length} retained=10000',
    );
  });

  testWidgets('all rows and footer remain reachable in a complete collection', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: buildPlatformLazyList(
            header: const [Text('Header')],
            itemCount: 30,
            itemBuilder: (_, index) =>
                SizedBox(height: 72, child: Text('tail $index')),
            footer: const [Text('Final footer')],
          ),
        ),
      ),
    );
    await end(tester);
    expect(find.text('tail 29'), findsOneWidget);
    expect(find.text('Final footer'), findsOneWidget);
  });

  testWidgets('append retains focused editor and scroll controller', (
    tester,
  ) async {
    final text = TextEditingController();
    final focus = FocusNode();
    final scroll = ScrollController();
    addTearDown(text.dispose);
    addTearDown(focus.dispose);
    addTearDown(scroll.dispose);
    var count = 30;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setter) {
              update = setter;
              return buildPlatformLazyList(
                controller: scroll,
                header: [TextField(controller: text, focusNode: focus)],
                itemCount: count,
                itemBuilder: (_, index) =>
                    SizedBox(height: 72, child: Text('row $index')),
              );
            },
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Retained draft');
    update(() => count = 3000);
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    expect(text.text, 'Retained draft');
    expect(scroll.offset, 0);
  });

  testWidgets(
    'keyed rows retain editing state after index and header changes',
    (tester) async {
      var ids = [0, 1, 2];
      var showHeader = true;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setter) {
                update = setter;
                final indices = {
                  for (var i = 0; i < ids.length; i++)
                    ValueKey('editor-${ids[i]}'): i,
                };
                return buildPlatformLazyList(
                  header: [if (showHeader) const Text('Header')],
                  itemCount: ids.length,
                  findItemIndex: (key) => indices[key],
                  itemBuilder: (_, index) => TextFormField(
                    key: ValueKey('editor-${ids[index]}'),
                    initialValue: 'initial ${ids[index]}',
                  ),
                );
              },
            ),
          ),
        ),
      );
      final row = find.byKey(const ValueKey('editor-1'));
      final state = tester.state(row);
      await tester.enterText(row, 'Retained row draft');
      update(() {
        ids = [1, 0, 2];
        showHeader = false;
      });
      await tester.pump();
      expect(identical(tester.state(row), state), isTrue);
      expect(find.text('Retained row draft'), findsOneWidget);
    },
  );

  testWidgets('3000 comments remain lazy and reply does not sort them again', (
    tester,
  ) async {
    final f = await fixture(tester);
    final comments = _Comments(
      f.container.read(neteaseMusicRepositoryProvider),
      f,
    );
    _CountedComment.reads = 0;
    await mount(
      tester,
      f,
      PlatformCommentsPage(resource: _resource, repository: comments),
    );
    expect(find.byType(PlatformCommentCard).evaluate().length, lessThan(25));
    expect(_CountedComment.reads, greaterThanOrEqualTo(_size - 1));
    final before = _CountedComment.reads;
    await tester.tap(find.text('回复').first);
    await tester.pumpAndSettle();
    expect(_CountedComment.reads - before, lessThan(100));
    expect(find.text('回复 comment 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('3000 conversations cache matches and refresh unread revision', (
    tester,
  ) async {
    final f = await fixture(tester);
    await mount(tester, f, const NeteaseMessagesPage());
    final repo =
        f.container.read(neteaseMessagesRepositoryProvider) as _Messages;
    expect(find.byType(NeteasePersonAvatar).evaluate().length, lessThan(30));
    expect(repo.visibleCalls, _size);
    expect(find.text('9'), findsOneWidget);
    repo.reads.displayed('10000', DateTime(2026, 11, 3));
    await tester.pumpAndSettle();
    expect(repo.visibleCalls, _size * 2);
    expect(find.text('9'), findsNothing);
    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('peer 2999'), findsNothing);
    expect(find.byType(NeteasePersonAvatar).evaluate().length, lessThan(35));
  });

  testWidgets('3000 friends stay lazy over successive viewports', (
    tester,
  ) async {
    final f = await fixture(tester);
    await mount(tester, f, const NeteaseFriendsPage());
    expect(find.byType(NeteasePersonAvatar).evaluate().length, lessThan(30));
    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('friend 2999'), findsNothing);
    expect(find.byType(NeteasePersonAvatar).evaluate().length, lessThan(35));
  });

  testWidgets('3000 notices keep successive viewports bounded', (tester) async {
    final f = await fixture(tester);
    await mount(
      tester,
      f,
      const NeteaseNoticesPage(initial: NeteaseNoticeKind.notices),
    );
    expect(find.byType(NeteasePersonAvatar).evaluate().length, lessThan(50));
    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('notice 2999'), findsNothing);
    expect(find.byType(NeteasePersonAvatar).evaluate().length, lessThan(50));
  });

  testWidgets('3000 hugs keep header actions and bounded viewports', (
    tester,
  ) async {
    final f = await fixture(tester);
    final comments = _Comments(
      f.container.read(neteaseMusicRepositoryProvider),
      f,
    );
    await mount(
      tester,
      f,
      NeteaseCommentHugsPage(
        repository: comments,
        resource: _resource,
        comment: comments.comments.first,
      ),
    );
    expect(find.byType(NeteasePersonAvatar).evaluate().length, lessThan(30));
    expect(find.text('送一个拥抱'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('hug 2999'), findsNothing);
    expect(find.byType(NeteasePersonAvatar).evaluate().length, lessThan(35));
  });

  testWidgets('3000 together records retain lazy date groups', (tester) async {
    final f = await fixture(tester);
    await mount(tester, f, const NeteaseTogetherHistoryPage());
    expect(find.byType(ListTile).evaluate().length, lessThan(25));
    expect(find.text('day 0'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('together-history-record-record2999')),
      findsNothing,
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.byType(ListTile).evaluate().length, lessThan(25));
  });

  testWidgets('3000 general results keep viewports bounded', (tester) async {
    final f = await fixture(tester);
    await mount(
      tester,
      f,
      const NeteaseFullTaskPage(
        endpoint: NeteaseEndpoint(
          route: '/fixture/collection',
          title: 'Offline collection',
          tab: '我的',
          category: '测试',
          description: '',
          parameters: [],
          write: false,
        ),
      ),
      settle: false,
    );
    final api = f.container.read(neteaseFullRepositoryProvider) as _Full;
    expect(api.calls, 1);
    expect(find.byType(ListTile).evaluate().length, lessThan(30));
    expect(find.text('result 0'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    // This task surface retains ambient glass/search motion. Pump a bounded
    // animation interval, as its existing UI suite does, rather than waiting
    // for the whole application chrome to stop scheduling frames.
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('result 2999'), findsNothing);
    expect(find.byType(ListTile).evaluate().length, lessThan(35));
  });

  testWidgets('3000 detail rows keep viewports bounded', (tester) async {
    final f = await fixture(tester);
    await mount(
      tester,
      f,
      NeteaseContentDetailPage(
        row: NeteaseContentRow(
          id: 'detail',
          title: 'Offline detail',
          kind: 'content',
          raw: {
            'items': List.generate(
              _size,
              (i) => {'id': '$i', 'name': 'detail $i'},
            ),
          },
        ),
      ),
    );
    expect(find.byType(ListTile).evaluate().length, lessThan(30));
    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('detail 2999'), findsNothing);
    expect(find.byType(ListTile).evaluate().length, lessThan(35));
  });
}
