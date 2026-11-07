import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/core/audio/audio_output_controller.dart';
import 'package:mesting_music/features/legal/domain/legal_documents.dart';
import 'package:mesting_music/features/experience/presentation/music_home_catalogues.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/data/platform_explore.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/platform_explore_providers.dart';

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:12345');
}

class _Account extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async =>
      const PlatformSession(userId: 'a', token: 'fixture-a');
  void change(PlatformSession? account) => state = AsyncData(account);
}

http.Response _response(Object data) => http.Response.bytes(
  utf8.encode(jsonEncode({'status': 1, 'data': data})),
  200,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'public release legal copy describes the current app without a Beta label',
    () {
      for (final document in [
        betaUserAgreementDocument,
        betaPrivacyPolicyDocument,
      ]) {
        expect(
          '${document.summary} ${document.sections.map((section) => section.body).join(' ')}',
          isNot(contains('Beta')),
        );
      }
    },
  );
  test(
    'theme and scene details send the actual upstream identifier fields',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/scene/module') {
          return _response({
            'content': [
              {
                'module_type': 3,
                'module_id': 'video',
                'extra': [
                  {'content_type': 2, 'tag_id': 'video-tag'},
                ],
              },
              {
                'module_type': 2,
                'module_id': 'music-real',
                'extra': [
                  {'content_type': 5, 'tag_id': 'book-tag'},
                  {'content_type': 6, 'tag_id': 'music-tag'},
                ],
              },
            ],
          });
        }
        return _response({
          'info': [
            {'hash': 'actual-recording', 'songname': '歌曲', 'singername': '歌手'},
          ],
        });
      });
      addTearDown(client.close);
      final repository = PlatformExploreRepository(
        MusicPlatformApi(server: _Server(), client: client),
      );
      await repository.tracks(
        const PlatformExploreItem(
          id: 'theme-7',
          title: '主题',
          cover: '',
          kind: PlatformExploreKind.theme,
        ),
      );
      expect(requests.single.url.path, '/theme/playlist/track');
      expect(requests.single.url.queryParameters['theme_id'], 'theme-7');
      expect(requests.single.url.queryParameters.containsKey('id'), isFalse);
      await repository.tracks(
        const PlatformExploreItem(
          id: 'work',
          moduleId: 'music-2',
          tag: 'instrumental',
          title: '专注',
          cover: '',
          kind: PlatformExploreKind.scene,
        ),
        page: 2,
      );
      expect(requests.last.url.path, '/scene/audio/list');
      expect(
        requests.last.url.queryParameters,
        containsPair('module_id', 'music-2'),
      );
      expect(
        requests.last.url.queryParameters,
        containsPair('tag', 'instrumental'),
      );
      expect(requests.last.url.queryParameters, containsPair('page', '2'));
      await repository.tracks(
        const PlatformExploreItem(
          id: 'work',
          title: '专注',
          cover: '',
          kind: PlatformExploreKind.scene,
        ),
      );
      expect(requests[requests.length - 2].url.path, '/scene/module');
      expect(requests.last.url.path, '/scene/audio/list');
      expect(requests.last.url.queryParameters, containsPair('id', 'work'));
      expect(
        requests.last.url.queryParameters,
        containsPair('module_id', 'music-real'),
      );
      expect(
        requests.last.url.queryParameters,
        containsPair('tag', 'music-tag'),
      );
      expect(
        requests.any((request) => request.url.path == '/scene/music'),
        isFalse,
      );
    },
  );

  test(
    'scene with no music module never falls through to videos, books or generic music',
    () async {
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        return _response({
          'content': [
            {
              'module_type': 3,
              'module_id': 'video',
              'extra': [
                {'content_type': 2, 'tag_id': 'v'},
              ],
            },
            {
              'module_type': 2,
              'module_id': 'books',
              'extra': [
                {'content_type': 5, 'tag_id': 'b'},
              ],
            },
          ],
        });
      });
      addTearDown(client.close);
      final repository = PlatformExploreRepository(
        MusicPlatformApi(server: _Server(), client: client),
      );
      await expectLater(
        repository.tracks(
          const PlatformExploreItem(
            id: 'scene',
            title: '场景',
            cover: '',
            kind: PlatformExploreKind.scene,
          ),
        ),
        throwsA(isA<MusicPlatformException>()),
      );
      expect(paths, ['/scene/module']);
    },
  );

  test(
    'theme aliases retain real names/covers and ignore unusable records',
    () async {
      final client = MockClient(
        (_) async => _response({
          'themes': [
            {
              'theme_id': 't1',
              'theme_name': '独立音乐',
              'theme_image': 'https://example.test/theme-{size}.jpg',
            },
            {'theme_name': '无标识'},
          ],
        }),
      );
      addTearDown(client.close);
      final items = await PlatformExploreRepository(
        MusicPlatformApi(server: _Server(), client: client),
      ).list(PlatformExploreKind.theme);
      expect(items.single.id, 't1');
      expect(items.single.title, '独立音乐');
      expect(items.single.cover, 'https://example.test/theme-400.jpg');
    },
  );

  test(
    'catalogue account switch discards an in-flight former account response',
    () async {
      final old = Completer<http.Response>();
      final started = Completer<void>();
      final client = MockClient((request) async {
        if (request.headers['Authorization']?.contains('userid=a') ?? false) {
          if (!started.isCompleted) started.complete();
          return old.future;
        }
        return _response({
          'info': [
            {'albumid': 'b-album', 'albumname': '账号 B'},
          ],
        });
      });
      addTearDown(client.close);
      final api = MusicPlatformApi(server: _Server(), client: client)
        ..session = const PlatformSession(userId: 'a', token: 'fixture-a');
      final container = ProviderContainer(
        overrides: [
          musicPlatformApiProvider.overrideWithValue(api),
          platformAccountProvider.overrideWith(_Account.new),
        ],
      );
      addTearDown(container.dispose);
      final pending = container.read(
        platformExploreProvider(PlatformExploreKind.album).future,
      );
      await started.future;
      const next = PlatformSession(userId: 'b', token: 'fixture-b');
      api.session = next;
      (container.read(platformAccountProvider.notifier) as _Account).change(
        next,
      );
      final result = await container.read(
        platformExploreProvider(PlatformExploreKind.album).future,
      );
      expect(result.single.id, 'b-album');
      old.complete(
        _response({
          'info': [
            {'albumid': 'a-album', 'albumname': '旧账号'},
          ],
        }),
      );
      await pending;
      expect(
        container
            .read(platformExploreProvider(PlatformExploreKind.album))
            .requireValue
            .single
            .id,
        'b-album',
      );
    },
  );

  test(
    'home consumes only music catalogue routes and filters non-music channels',
    () {
      expect(musicHomeCatalogueOrder.map((kind) => kind.path), [
        '/rank/list',
        '/top/album',
        '/theme/playlist',
        '/scene/lists',
      ]);
      for (final title in ['听书', '直播', '有声书专区', '短剧推荐']) {
        expect(
          isMusicHomeCatalogueItem(
            PlatformExploreItem(
              id: 'x',
              title: title,
              cover: '',
              kind: PlatformExploreKind.theme,
            ),
          ),
          isFalse,
        );
      }
      expect(
        isMusicHomeCatalogueItem(
          const PlatformExploreItem(
            id: 'x',
            title: '演唱会现场',
            cover: '',
            kind: PlatformExploreKind.theme,
          ),
        ),
        isTrue,
      );
    },
  );

  test(
    'a paused output preference is not represented as a selected real route',
    () {
      final output = AudioOutput.fromMap({
        'id': 'device:headset',
        'name': 'vivo TWS 5',
        'kind': 'headphones',
        'available': true,
        'pendingId': 'device:speaker',
        'routes': [
          {
            'id': 'device:speaker',
            'name': 'This phone',
            'kind': 'phone',
            'selectable': true,
            'selected': false,
          },
        ],
      });
      expect(output.pendingId, 'device:speaker');
      expect(output.id, 'device:headset');
      expect(output.routes.single.selected, isFalse);
      expect(output.routes.single.local, isTrue);
      expect(output.routes.single.name, '本机');
    },
  );
}
