import 'dart:io';
import 'dart:ui' as ui;
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/experience/presentation/apple_audio_glyphs.dart';
import 'package:mesting_music/features/experience/presentation/beta_bottom_bar.dart';
import 'package:mesting_music/features/experience/presentation/floating_playback_pill.dart';
import 'package:mesting_music/features/experience/presentation/music_functions_page.dart';
import 'package:mesting_music/features/experience/presentation/playback_pill_artwork.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_messages_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/together/netease_together_controller.dart';
import 'package:mesting_music/features/music_platform/platform_backend_providers.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/shared/models/track.dart';

const _export = bool.fromEnvironment('EXPORT_UI_REFRESH_SCREENSHOTS');
const _song = Track(
  id: 'netease_1',
  title: '与朋友分享此刻的音乐',
  artist: '音乐旅人',
  album: '',
  duration: Duration(minutes: 3),
  audioAsset: '',
  lyricsAsset: '',
  coverAsset: 'assets/branding/mesting-app-icon.png',
  source: TrackSource.netease,
);

class _Music extends Fake implements NeteaseMusicRepository {}

/// Rendering this guest surface never starts real secure-storage restoration.
class _Guest extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => null;
}

class _Messages extends Fake implements NeteaseMessagesRepository {}

class _Player extends Fake implements NeteaseTogetherPlayer {}

class _Transport extends Fake implements MestingAudioHandler {
  int nexts = 0, toggles = 0;
  @override
  Future<void> skipToNext() async {
    nexts++;
  }

  @override
  Future<void> togglePlayPause() async {
    toggles++;
  }
}

class _Room extends NeteaseTogetherController {
  _Room()
    : super(
        music: _Music(),
        messages: _Messages(),
        player: _Player(),
        isCurrent: () => true,
        automaticTimer: false,
      );
  @override
  bool get current => true;
  @override
  NeteasePerson get self =>
      const NeteasePerson('me', '我', 'assets/branding/mesting-app-icon.png');
  @override
  Future<void> restore() async {}
  void show({bool active = true, String? peer = 'friend'}) {
    roomId = active ? 'fixture-room' : null;
    members = [
      self,
      if (peer != null)
        NeteasePerson(peer, '朋友', 'assets/branding/mesting-mark-master.png'),
    ];
    notifyListeners();
  }
}

final _owner = NotifierProvider<_Owner, _Room?>(_Owner.new);

// A notifier makes account/controller replacement follow the real Provider
// dependency path rather than mutating an already-disposed room in a test.
class _Owner extends Notifier<_Room?> {
  @override
  _Room? build() => null;
  void replace(_Room? room) => state = room;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (!_export) return;
    final font = await File('C:/Windows/Fonts/msyh.ttc').readAsBytes();
    for (final family in [
      'Roboto',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
    ]) {
      await (FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(font)))).load();
    }
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
          rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
        ))
        .load();
    await (FontLoader('MaterialIcons')..addFont(
          File.fromUri(
            File(
              Platform.resolvedExecutable,
            ).uri.resolve('../../material_fonts/MaterialIcons-Regular.otf'),
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
  });
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });
  Future<void> mount(
    WidgetTester tester,
    ProviderContainer container,
    Widget body, {
    bool dark = false,
    bool reduced = true,
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LiquidGlassWidgets.wrap(
          adaptiveQuality: false,
          brightnessResolver: Theme.maybeBrightnessOf,
          child: MaterialApp(
            theme: buildMestingTheme(
              musicThemePresetById(dark ? 'classic-dark' : 'classic'),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: child!,
            ),
            home: RepaintBoundary(
              key: const ValueKey('refresh-capture'),
              child: Builder(
                builder: (context) => Scaffold(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  body: body,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (_export) {
      await tester.runAsync(() async {
        // Precache the exact resized providers used by the mounted images.
        // Warming only the base asset leaves compact decode jobs pending.
        final images = tester.widgetList<Image>(find.byType(Image)).toList();
        final context = tester.element(find.byType(Scaffold).first);
        await Future.wait(
          images.map((image) => precacheImage(image.image, context)),
        );
      });
      await tester.pumpAndSettle();
    }
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!_export) return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('refresh-capture')),
      );
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
        '.codex-artifacts/2026-11-02-ui-refresh/captures/$name.png',
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  ProviderContainer container({_Transport? transport}) => ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      usesNeteaseProvider.overrideWithValue(false),
      platformAccountProvider.overrideWith(_Guest.new),
      neteaseTogetherControllerProvider.overrideWith(
        (ref) => ref.watch(_owner),
      ),
      currentTrackProvider.overrideWithValue(_song),
      currentMediaItemProvider.overrideWith(
        (ref) => Stream.value(_song.toMediaItem()),
      ),
      playbackStateProvider.overrideWith(
        (ref) => Stream.value(PlaybackState()),
      ),
      if (transport != null) audioHandlerProvider.overrideWithValue(transport),
    ],
  );

  testWidgets('AirPods Pro original reference comparison', (tester) async {
    final c = container();
    addTearDown(c.dispose);
    final source = await tester.runAsync(() async {
      final bytes = await File(
        '.codex-artifacts/2026-11-02-ui-refresh/icon-reference/user-original.png',
      ).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    });
    await mount(
      tester,
      c,
      Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('原始参考图 ×4'),
                CustomPaint(
                  size: const Size(160, 120),
                  painter: _Reference(source!),
                ),
              ],
            ),
            const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('AirPods Pro 原始轮廓'),
                SizedBox(
                  width: 160,
                  height: 120,
                  child: Center(
                    child: AppleAudioGlyph(
                      AppleAudioGlyphKind.earphones,
                      size: 128,
                      color: Color(0xFFB5C7D7),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      dark: true,
      size: const Size(390, 240),
    );
    await capture(tester, 'airpods-pro-reference');
    await tester.pumpWidget(const SizedBox());
    source.dispose();
  }, skip: !_export);

  testWidgets(
    'pill membership restores artwork, filters heartbeats and drops old accounts',
    (tester) async {
      final c = container(), room = _Room();
      addTearDown(c.dispose);
      addTearDown(room.dispose);
      c.read(_owner.notifier).replace(room);
      await mount(
        tester,
        c,
        const Center(child: PlaybackPillArtwork(track: _song, dimension: 32)),
      );
      expect(find.byKey(const ValueKey('pill-song-artwork')), findsOneWidget);
      room.show();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('pill-together-avatars')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('pill-together-peer-friend')),
        findsOneWidget,
      );
      final picture = tester.widget(
        find.byKey(const ValueKey('pill-together-avatars')),
      );
      room.show();
      await tester.pump();
      expect(
        identical(
          picture,
          tester.widget(find.byKey(const ValueKey('pill-together-avatars'))),
        ),
        true,
      );
      room.show(peer: null);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('pill-together-self-me')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('pill-together-peer-friend')),
        findsNothing,
      );
      room.show(peer: 'new');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('pill-together-peer-new')),
        findsOneWidget,
      );
      room.show(active: false);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pill-song-artwork')), findsOneWidget);
      room.show();
      await tester.pumpAndSettle();
      c.read(_owner.notifier).replace(null);
      await tester.pumpAndSettle();
      room.show(peer: 'obsolete');
      await tester.pump();
      expect(find.byKey(const ValueKey('pill-together-avatars')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('room changes retain interruptible normal-motion geometry', (
    tester,
  ) async {
    final c = container(), room = _Room();
    addTearDown(c.dispose);
    addTearDown(room.dispose);
    c.read(_owner.notifier).replace(room);
    await mount(
      tester,
      c,
      const Center(child: PlaybackPillArtwork(track: _song, dimension: 32)),
      reduced: false,
    );
    room.show();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    room.show(peer: null);
    await tester.pump();
    room.show(active: false);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pill-song-artwork')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  for (final dark in [false, true]) {
    testWidgets(
      'compact and expanded together pill controls remain usable dark=$dark',
      (tester) async {
        final transport = _Transport();
        // Use one transport for both production capsule variants.
        final scope = container(transport: transport), room = _Room()..show();
        addTearDown(scope.dispose);
        addTearDown(room.dispose);
        scope.read(_owner.notifier).replace(room);
        final text = TextEditingController(), focus = FocusNode();
        addTearDown(text.dispose);
        addTearDown(focus.dispose);
        await mount(
          tester,
          scope,
          Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Padding(
                padding: EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AppleAudioGlyph(
                      AppleAudioGlyphKind.earphones,
                      size: 40,
                      color: Colors.grey,
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(20),
                child: FloatingPlaybackPill(),
              ),
              const SizedBox(
                width: 240,
                child: FloatingPlaybackPill(compact: true),
              ),
              BetaMusicBottomBar(
                selectedIndex: 0,
                onTabSelected: (_) {},
                searchConfig: GlassSearchBarConfig(
                  onSearchToggle: (_) {},
                  controller: text,
                  focusNode: focus,
                ),
              ),
            ],
          ),
          dark: dark,
          size: const Size(320, 640),
        );
        expect(
          find.byKey(const ValueKey('pill-together-avatars')),
          findsNWidgets(2),
        );
        await tester.tap(find.bySemanticsLabel('播放').last);
        await tester.tap(find.bySemanticsLabel('下一首').last);
        await tester.pumpAndSettle();
        expect(transport.toggles, 1);
        expect(transport.nexts, 1);
        expect(tester.takeException(), isNull);
        await capture(tester, 'pill-and-navigation-${dark ? 'dark' : 'light'}');
        await tester.pumpWidget(const SizedBox());
      },
    );
    testWidgets('feature palette production rendering dark=$dark', (
      tester,
    ) async {
      final c = container();
      addTearDown(c.dispose);
      await mount(tester, c, const MusicFunctionsPage(), dark: dark);
      expect(tester.takeException(), isNull);
      await capture(tester, 'features-${dark ? 'dark' : 'light'}');
      await tester.pumpWidget(const SizedBox());
    });
  }
}

/// Display the provided reference without resynthesizing or retouching it.
class _Reference extends CustomPainter {
  const _Reference(this.image);
  final ui.Image image;
  @override
  void paint(Canvas canvas, Size size) => canvas.drawImageRect(
    image,
    const Rect.fromLTWH(333, 402, 40, 30),
    Offset.zero & size,
    Paint()..filterQuality = FilterQuality.none,
  );
  @override
  bool shouldRepaint(_Reference old) => old.image != image;
}
