import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/features/auth/auth_providers.dart';
import 'package:mesting_music/features/auth/beta_entry_flow.dart';
import 'package:mesting_music/features/experience/presentation/editorial_widgets.dart';
import 'package:mesting_music/features/auth/account_capabilities.dart';
import 'package:mesting_music/features/auth/domain/auth_models.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/data/platform_comments_repository.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/platform_quality_providers.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_quality_button.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_comments_page.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_design.dart';
import 'package:mesting_music/features/settings/presentation/haptic_settings_page.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/shared/widgets/beta_content_reveal.dart';
import 'package:mesting_music/shared/widgets/beta_icon_button.dart';

const _export = bool.fromEnvironment('EXPORT_BETA_SCREENSHOTS');
const _identity = PlatformSession(userId: '18', token: 'one', nickname: '白糖');
const _track = Track(
  id: 'kugou_recording',
  title: '测试歌曲',
  artist: '歌手',
  album: '',
  duration: Duration(minutes: 3),
  audioAsset: '',
  coverAsset: '',
  lyricsAsset: '',
  source: TrackSource.kugou,
);
const _payload = {
  'status': 1,
  'data': {
    'hash_128': 'sd',
    'hash_320': 'hq',
    'hash_flac': 'sq',
    'hash_high': 'hi',
  },
};

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:18000');
}

class _Account extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => _identity;
  void replace(PlatformSession next) => state = AsyncData(next);
}

class _Auth extends AuthController {
  @override
  Future<AuthSession?> build() async => null;
}

class _Comments extends PlatformCommentsRepository {
  _Comments(MusicPlatformApi api) : super(api, _identity);
  final first = Completer<PlatformCommentPage>();
  @override
  Future<PlatformCommentPage> load(
    PlatformCommentResource resource, {
    int page = 1,
    PlatformComment? thread,
    String? hottestChildrenId,
  }) => page == 1
      ? first.future
      : Future.value(
          const PlatformCommentPage([
            PlatformComment(
              id: 'second',
              userId: 'other',
              nickname: '另一位听众',
              content: '第二页评论',
            ),
          ], false),
        );
}

MusicPlatformApi _api(Future<http.Response> Function(http.Request) action) =>
    MusicPlatformApi(server: _Server(), client: MockClient(action))
      ..session = _identity;
http.Response _reply([Map<String, dynamic> data = _payload]) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (!_export) return;
    final bytes = await File('C:/Windows/Fonts/msyh.ttc').readAsBytes();
    for (final family in [
      'Beta18QA',
      'Roboto',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
    ]) {
      await (FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
          rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
        ))
        .load();
    await (FontLoader('MaterialIcons')..addFont(
          File(
            'D:/flutter/mesting-beta5/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
  });
  late SharedPreferences preferences;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });
  ProviderContainer container(MusicPlatformApi api) => ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      musicPlatformApiProvider.overrideWithValue(api),
      platformAccountProvider.overrideWith(_Account.new),
      authControllerProvider.overrideWith(_Auth.new),
      showPlatformFeaturesProvider.overrideWithValue(true),
      currentTrackProvider.overrideWithValue(_track),
    ],
  );
  Future<ProviderContainer> pump(
    WidgetTester tester,
    Widget page, {
    MusicPlatformApi? api,
    bool dark = false,
    Size size = const Size(390, 844),
    double scale = 1,
    bool reduced = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var theme = buildMestingTheme(
      musicThemePresetById(dark ? 'classic-dark' : 'classic'),
    );
    if (_export) {
      theme = theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'Beta18QA'),
      );
    }
    final c = container(api ?? _api((_) async => _reply()));
    addTearDown(c.dispose);
    await c.read(platformAccountProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: theme,
          builder: (_, child) => MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(scale),
              disableAnimations: reduced,
            ),
            // Include navigator overlays and the shell's opaque canvas in QA.
            child: RepaintBoundary(
              key: const ValueKey('beta18-capture'),
              child: ColoredBox(
                color: theme.colorScheme.surface,
                child: child!,
              ),
            ),
          ),
          home: page,
        ),
      ),
    );
    await tester.pump();
    return c;
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!_export) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('beta18-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.5);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final folder = Directory(
          const String.fromEnvironment('BETA_SCREENSHOT_DIR'),
        )..createSync(recursive: true);
        File(
          '${folder.path}/$name.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  }

  Future<double> blueCoverage(WidgetTester tester, Finder control) async {
    final frame = find.byKey(const ValueKey('beta18-capture'));
    final boundary = tester.renderObject<RenderRepaintBoundary>(frame);
    return (await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        final rect = tester.getRect(control).shift(-tester.getTopLeft(frame));
        var blue = 0, total = 0;
        for (
          var y = (rect.top + 8).ceil().clamp(0, image.height);
          y < (rect.bottom - 8).floor().clamp(0, image.height);
          y++
        ) {
          for (
            var x = (rect.left + 12).ceil().clamp(0, image.width);
            x < (rect.right - 12).floor().clamp(0, image.width);
            x++
          ) {
            final index = 4 * (y * image.width + x);
            if (bytes[index + 2] > bytes[index] + 30 &&
                bytes[index + 2] > bytes[index + 1] + 10) {
              blue++;
            }
            total++;
          }
        }
        return total == 0 ? 0.0 : blue / total;
      } finally {
        image.dispose();
      }
    }))!;
  }

  test(
    'successful quality catalog survives close/reopen and follows token changes',
    () async {
      var requests = 0;
      final api = _api((_) async {
        requests++;
        return _reply();
      });
      final c = container(api);
      addTearDown(c.dispose);
      final provider = platformSongQualitiesProvider(_track.id);
      var listening = c.listen(provider, (_, _) {});
      await c.read(provider.future);
      listening.close();
      await c.pump();
      listening = c.listen(provider, (_, _) {});
      expect(c.read(provider).hasValue, true);
      await c.read(provider.future);
      expect(requests, 1);
      const next = PlatformSession(userId: '18', token: 'new-login');
      api.session = next;
      (c.read(platformAccountProvider.notifier) as _Account).replace(next);
      await c.pump();
      await c.read(provider.future);
      expect(requests, 2);
      listening.close();
    },
  );

  test(
    'failed quality loads remain retryable and old retained songs are bounded',
    () async {
      var fail = true, requests = 0;
      final api = _api((_) async {
        requests++;
        return fail ? _reply({'status': 0}) : _reply();
      });
      final c = container(api);
      addTearDown(c.dispose);
      final provider = platformSongQualitiesProvider('kugou_first');
      var sub = c.listen(provider, (_, _) {});
      await expectLater(
        c.read(provider.future),
        throwsA(isA<MusicPlatformException>()),
      );
      sub.close();
      await c.pump();
      fail = false;
      sub = c.listen(provider, (_, _) {});
      await c.read(provider.future);
      expect(requests, 2);
      sub.close();
      await c.pump();
      for (var index = 0; index < 65; index++) {
        final p = platformSongQualitiesProvider('kugou_$index');
        final s = c.listen(p, (_, _) {});
        await c.read(p.future);
        s.close();
        await c.pump();
      }
      final before = requests;
      await c.read(provider.future);
      expect(requests, before + 1);
    },
  );

  for (final dark in [false, true]) {
    for (final small in [false, true]) {
      testWidgets(
        'lightweight greeting keeps title readable and long name bounded $dark/$small',
        (tester) async {
          await preferences.setBool(BetaEntryFlow.completedKey, true);
          final c = await pump(
            tester,
            const Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: EditorialHeader('首页'),
              ),
            ),
            dark: dark,
            size: Size(small ? 320 : 390, 844),
            scale: small ? 1.6 : 1,
          );
          (c.read(platformAccountProvider.notifier) as _Account).replace(
            const PlatformSession(
              userId: '18',
              token: 'one',
              nickname: '很长的昵称也要保持舒适清晰',
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(
            find.byKey(const ValueKey('beta13-cold-greeting')),
            findsOneWidget,
          );
          expect(find.byIcon(CupertinoIcons.music_note), findsNothing);
          expect(tester.takeException(), isNull);
          await capture(tester, 'beta18-greeting-$dark-$small');
          await tester.pump(const Duration(seconds: 5));
          await tester.pump(const Duration(milliseconds: 350));
          expect(
            find.byKey(const ValueKey('beta13-cold-greeting')),
            findsNothing,
          );
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
    testWidgets(
      'quality loading reveals content and cached reopen avoids spinner $dark',
      (tester) async {
        final response = Completer<http.Response>();
        var calls = 0;
        final api = _api((request) {
          // Resource hashes alone no longer establish account playback rights.
          // Keep loading asynchronous, then supply strictly matching synthetic
          // streams for the new preflight without opening a real connection.
          if (request.url.path == '/song/url') {
            final quality = request.url.queryParameters['quality'];
            return Future.value(
              _reply({
                'status': 1,
                'data': {
                  'url': 'https://quality-fixture.invalid/$quality',
                  'quality': quality,
                  'fileSize': 4000000,
                  'bitrate': quality == '128'
                      ? 128000
                      : quality == '320'
                      ? 320000
                      : 960000,
                },
              }),
            );
          }
          calls++;
          return response.future;
        });
        final c = await pump(
          tester,
          Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => showPlatformQualityPicker(context, ref),
                child: const Text('音质'),
              ),
            ),
          ),
          api: api,
          dark: dark,
        );
        await tester.tap(find.text('音质'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
        await capture(tester, 'beta18-quality-loading-$dark');
        response.complete(_reply());
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Hi-Res'), findsOneWidget);
        final verifiedCalls = calls;
        final reveal = find.byType(BetaContentReveal);
        final opacity = tester.widget<Opacity>(
          find.descendant(of: reveal, matching: find.byType(Opacity)).first,
        );
        expect(opacity.opacity, allOf(greaterThan(0), lessThan(1)));
        await capture(tester, 'beta18-quality-reveal-$dark');
        await tester.pump(const Duration(milliseconds: 350));
        await capture(tester, 'beta18-quality-ready-$dark');
        await tester.tapAt(const Offset(8, 90));
        await tester.pumpAndSettle();
        await tester.tap(find.text('音质'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.byType(CupertinoActivityIndicator), findsNothing);
        expect(calls, verifiedCalls);
        await tester.pumpWidget(const SizedBox());
        // Dispose cached capability leases before widget-test timer invariants.
        c.dispose();
      },
    );
    testWidgets(
      'comments load without panel and retain old row state on append $dark',
      (tester) async {
        final api = _api((_) async => _reply());
        final repo = _Comments(api);
        await pump(
          tester,
          PlatformCommentsPage(
            resource: const PlatformCommentResource(
              kind: PlatformCommentKind.playlist,
              id: 'list',
              name: '测试歌单',
            ),
            repository: repo,
          ),
          dark: dark,
        );
        final loading = find.byKey(const ValueKey('comments-initial-loading'));
        expect(loading, findsOneWidget);
        expect(
          find.ancestor(of: loading, matching: find.byType(PlatformPanel)),
          findsNothing,
        );
        await capture(tester, 'beta18-comments-loading-$dark');
        repo.first.complete(
          const PlatformCommentPage([
            PlatformComment(
              id: 'first',
              userId: 'other',
              nickname: '听众',
              content: '喜欢这首歌的旋律。',
            ),
          ], true),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));
        expect(
          find.byKey(const ValueKey('comment-reveal-first')),
          findsOneWidget,
        );
        await capture(tester, 'beta18-comments-reveal-$dark');
        await tester.pump(const Duration(milliseconds: 400));
        final firstElement = tester.element(
          find.byKey(const ValueKey('comment-reveal-first')),
        );
        // A short first page can prefetch automatically. Existing keyed content
        // must retain its completed reveal instead of animating all rows again.
        if (find.text('加载更多').evaluate().isNotEmpty) {
          await tester.tap(find.text('加载更多'));
          await tester.pump();
        }
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          tester.element(find.byKey(const ValueKey('comment-reveal-first'))),
          same(firstElement),
        );
        await capture(tester, 'beta18-comments-ready-$dark');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'haptic blue action stays readable through a cancelled scroll press $dark',
      (tester) async {
        await pump(
          tester,
          const HapticSettingsPage(),
          dark: dark,
          size: const Size(320, 580),
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('haptics-preview')),
        );
        await tester.pumpAndSettle();
        final preview = find.byKey(const ValueKey('haptics-preview'));
        final baselineBlue = await blueCoverage(tester, preview);
        expect(baselineBlue, greaterThan(.25));
        final gesture = await tester.startGesture(tester.getCenter(preview));
        await tester.pump(const Duration(milliseconds: 180));
        await gesture.moveBy(const Offset(0, -55));
        await tester.pump(const Duration(milliseconds: 220));
        expect(await blueCoverage(tester, preview), greaterThan(.25));
        await capture(tester, 'beta18-haptics-scroll-$dark');
        await gesture.up();
        await tester.pumpAndSettle();
        expect(find.text('体验触感'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'icon press preserves small close glyph without a circular state overlay',
    (tester) async {
      var taps = 0;
      await pump(
        tester,
        Scaffold(
          body: Center(
            child: BetaIconButton(
              icon: const Icon(CupertinoIcons.xmark_circle_fill),
              tooltip: '关闭',
              onPressed: () => taps++,
            ),
          ),
        ),
      );
      final icon = find.byType(IconButton);
      final gesture = await tester.startGesture(tester.getCenter(icon));
      await tester.pump(const Duration(milliseconds: 80));
      final button = tester.widget<IconButton>(icon);
      expect(
        button.style!.overlayColor!.resolve({WidgetState.pressed}),
        Colors.transparent,
      );
      expect(find.byIcon(CupertinoIcons.xmark_circle_fill), findsOneWidget);
      expect(tester.getSize(icon).width, greaterThanOrEqualTo(48));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 180));
      expect(taps, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('reduced motion shows content immediately', (tester) async {
    await pump(
      tester,
      const Scaffold(body: BetaContentReveal(child: Text('已加载'))),
      reduced: true,
    );
    expect(find.text('已加载'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BetaContentReveal),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
