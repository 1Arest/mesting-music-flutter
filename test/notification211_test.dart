import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/notifications/notification_bridge.dart';
import 'package:mesting_music/features/notifications/notification_coordinator.dart';
import 'package:mesting_music/features/notifications/notification_models.dart';
import 'package:mesting_music/features/notifications/notification_runner.dart';
import 'package:mesting_music/features/notifications/notification_sources.dart';

MusicNotice event(String id, {int time = 0}) => MusicNotice(
  id: id,
  platform: MusicPlatform.netease,
  kind: MusicNoticeKind.privateMessage,
  title: '朋友',
  body: '你好',
  time: time,
);

NoticeAccount account(
  MusicPlatform platform, [
  String token = 'private-test-token',
]) => NoticeAccount(
  PlatformSession(userId: '42', token: token, platform: platform),
);

class _Bridge extends MusicNotificationBridge {
  final calls = <(String, Map<String, Object?>?)>[];
  final feeds = <String, Object?>{};
  final owners = <String, String>{};
  Map<String, Object?> settings = {};
  bool leased = false, accept = true;
  int releases = 0;
  @override
  bool get supported => true;
  @override
  Future<Map<String, dynamic>> state() async => {'machine': 'device'};
  @override
  Future<T?> call<T>(String method, [Map<String, Object?>? args]) async {
    calls.add((method, args));
    Object? value;
    switch (method) {
      case 'bind':
        owners.addAll(Map<String, String>.from(args!['owners'] as Map));
      case 'begin':
        if (leased) return null;
        leased = true;
        value = {
          'lease': 'test-lease',
          'generation': 1,
          'json': jsonEncode({'feeds': feeds, 'settings': settings}),
        };
      case 'commit':
        value = accept;
      case 'release':
        leased = false;
        releases++;
    }
    return value as T?;
  }
}

class _Sources implements NoticeSourceBundle {
  _Sources(this.sources);
  final List<NoticeSource> sources;
  bool closed = false;
  @override
  List<NoticeSource> build() => sources;
  @override
  void close() => closed = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'first read baselines history; subsequent unseen events alert exactly once',
    () {
      final initial = NoticeDiff.apply(
        NoticeFeed('inbox', [event('old')], cursor: 'a'),
        null,
      );
      expect(initial.fresh, isEmpty);
      final next = NoticeDiff.apply(
        NoticeFeed('inbox', [
          event('new'),
          event('new'),
          event('old'),
        ], cursor: 'b'),
        initial.state,
      );
      expect(next.fresh.map((e) => e.id), ['new']);
      final repeated = NoticeDiff.apply(
        NoticeFeed('inbox', [event('new')], cursor: 'c'),
        next.state,
      );
      expect(repeated.fresh, isEmpty);
      expect(repeated.state['cursor'], 'c');
    },
  );
  test('cursor history is bounded without dropping the current snapshot', () {
    final result = NoticeDiff.apply(
      NoticeFeed('many', [for (var i = 0; i < 30; i++) event('new$i')]),
      {
        'initialized': true,
        'seen': [for (var i = 0; i < 600; i++) 'old$i'],
      },
    );
    expect(result.state['seen'], hasLength(500));
    expect((result.state['seen'] as List).first, 'new0');
  });
  test(
    'same UID and replaced credentials cannot share notification scopes',
    () {
      expect(
        account(MusicPlatform.netease, 'a').scope,
        isNot(account(MusicPlatform.netease, 'b').scope),
      );
      expect(
        account(MusicPlatform.netease).scope,
        isNot(account(MusicPlatform.kugou).scope),
      );
    },
  );
  test(
    'both retained platforms are polled without a selected UI platform',
    () async {
      final bridge = _Bridge();
      final seen = <MusicPlatform>[];
      final bundles = <_Sources>[];
      await MusicNoticeRunner(
        bridge: bridge,
        readAccount: (p) async => account(p),
        sourceFactory: (a, _) {
          seen.add(a.platform);
          final source = _Sources([
            NoticeSource(
              'inbox',
              (_) async => NoticeFeed('inbox', [event(a.platform.name)]),
            ),
          ]);
          bundles.add(source);
          return source;
        },
      ).poll();
      expect(seen.toSet(), noticePlatforms.toSet());
      expect(bridge.calls.where((e) => e.$1 == 'commit'), hasLength(2));
      expect(bundles.every((e) => e.closed), isTrue);
      expect(bridge.releases, 1);
      expect(
        jsonEncode(bridge.calls.map((c) => [c.$1, c.$2]).toList()),
        isNot(contains('private-test-token')),
      );
    },
  );
  test(
    'an unknown secure read does not revoke that platform as logged out',
    () async {
      final bridge = _Bridge();
      await MusicNoticeRunner(
        bridge: bridge,
        readAccount: (p) async {
          if (p == MusicPlatform.netease) {
            throw StateError('secure read failed');
          }
          return null;
        },
        sourceFactory: (_, _) => _Sources([]),
      ).poll();
      expect(bridge.owners.containsKey('netease'), isFalse);
      expect(bridge.owners['kugou'], '');
    },
  );
  test(
    'logout while a request is pending prevents its cursor and alert publication',
    () async {
      final bridge = _Bridge();
      final gate = Completer<void>();
      var loggedIn = true;
      final started = Completer<void>();
      final run = MusicNoticeRunner(
        bridge: bridge,
        readAccount: (p) async =>
            p == MusicPlatform.netease && loggedIn ? account(p) : null,
        sourceFactory: (_, _) => _Sources([
          NoticeSource('private', (_) async {
            started.complete();
            await gate.future;
            return NoticeFeed('private', [event('late')]);
          }),
        ]),
      ).poll();
      await started.future;
      loggedIn = false;
      gate.complete();
      await run;
      expect(bridge.calls.where((c) => c.$1 == 'commit'), isEmpty);
      expect(bridge.releases, 1);
    },
  );
  test(
    'failed feed preserves its cursor while another feed can complete',
    () async {
      final bridge = _Bridge();
      await MusicNoticeRunner(
        bridge: bridge,
        readAccount: (p) async =>
            p == MusicPlatform.netease ? account(p) : null,
        sourceFactory: (_, _) => _Sources([
          NoticeSource(
            'failed',
            (_) async => throw const FormatException('unavailable'),
          ),
          NoticeSource(
            'artist',
            (_) async => NoticeFeed('artist', [event('song')]),
          ),
        ]),
      ).poll();
      expect(
        bridge.calls.where((c) => c.$1 == 'commit').map((c) => c.$2!['feed']),
        ['artist'],
      );
      expect(
        bridge.calls.where((c) => c.$1 == 'error').single.$2!['feed'],
        'failed',
      );
    },
  );
  test(
    'disabled platform and category produce no requests for those feeds',
    () async {
      final bridge = _Bridge()
        ..settings = {'kugou': false, 'netease:artist': false};
      final seen = <String>[];
      await MusicNoticeRunner(
        bridge: bridge,
        readAccount: (p) async => account(p),
        sourceFactory: (a, _) => _Sources([
          NoticeSource('artist', (_) async {
            seen.add('${a.platform}:artist');
            return const NoticeFeed('artist', []);
          }, kind: MusicNoticeKind.artist),
          NoticeSource('private', (_) async {
            seen.add('${a.platform}:private');
            return const NoticeFeed('private', []);
          }, kind: MusicNoticeKind.privateMessage),
        ]),
      ).poll();
      expect(seen, ['MusicPlatform.netease:private']);
    },
  );
  test(
    'occupied native lease prevents a second poll from opening transports',
    () async {
      final bridge = _Bridge()..leased = true;
      var opened = false;
      await MusicNoticeRunner(
        bridge: bridge,
        readAccount: (p) async => account(p),
        sourceFactory: (_, _) {
          opened = true;
          return _Sources([]);
        },
      ).poll();
      expect(opened, isFalse);
      expect(bridge.releases, 0);
    },
  );
  test(
    'Kugou poll validates envelope and does not invent success on auth rejection',
    () {
      expect(
        () => parseKugouNoticePoll({
          'status': 0,
          'errcode': 20006,
        }, MusicPlatform.kugou),
        throwsFormatException,
      );
      expect(
        () =>
            parseKugouNoticePoll({'status': 1, 's': 'x'}, MusicPlatform.kugou),
        throwsFormatException,
      );
      final parsed = parseKugouNoticePoll({
        'status': 1,
        's': 'opaque-next',
        'list': [
          {
            'msgid': '1',
            'uid': 8,
            'addtime': 1700000000,
            'tag': '___CHAT:8:42___',
            'message': {'content': '你好', 'title': '朋友'},
          },
          {
            'msgid': '2',
            'md': 'watch',
            'message': {'content': '直播内容'},
          },
        ],
      }, MusicPlatform.kugou);
      expect(parsed.cursor, 'opaque-next');
      expect(parsed.events, hasLength(1));
      expect(parsed.events.single.kind, MusicNoticeKind.privateMessage);
      expect(parsed.events.single.time, 1700000000000);
    },
  );
  test('Kugou parameters keep Lite and standard authorizations distinct', () {
    const device = {'mid': 'mid', 'uuid': 'uuid', 'dfid': 'dfid'};
    final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);
    const lite = PlatformSession(userId: '42', token: 'lite');
    const standard = PlatformSession(
      userId: '42',
      token: 'lite',
      kugouStandardToken: 'standard',
    );
    expect(kugouNoticeParameters(lite, device, 'device', now)['appid'], '3116');
    expect(
      kugouNoticeParameters(standard, device, 'device', now)['appid'],
      '1005',
    );
    expect(
      kugouNoticeParameters(standard, device, 'device', now)['token'],
      'standard',
    );
    expect(
      () => kugouNoticeParameters(lite, {}, 'device', now),
      throwsFormatException,
    );
    expect(
      kugouNoticeSignature(lite, {'b': '2', 'a': '1'}, '{}'),
      kugouNoticeSignature(lite, {'a': '1', 'b': '2'}, '{}'),
    );
  });
  test(
    'shortcut routes are fixed and notification routes reject unknown platforms',
    () {
      expect(
        musicEntryRoute({'action': 'favorites'}),
        '/music/library?view=favorites',
      );
      expect(musicEntryRoute({'action': 'recognize'}), '/music/recognize');
      expect(musicEntryRoute({'action': 'search'}), '/music/search');
      expect(musicEntryRoute({'action': 'https://example.com'}), isNull);
      expect(
        musicEntryRoute({'action': 'notifications', 'platform': 'qishui'}),
        isNull,
      );
      final route = musicEntryRoute({
        'action': 'notifications',
        'platform': 'netease',
        'notice': 'a&path=/auth',
      })!;
      expect(Uri.parse(route).path, '/music/notifications');
      expect(Uri.parse(route).queryParameters['notice'], 'a&path=/auth');
    },
  );
}
