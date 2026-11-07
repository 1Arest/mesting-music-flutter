import 'dart:async';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'support/no_music_account_fixture.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/local_music/data/local_music_repository.dart';
import 'package:mesting_music/features/local_music/domain/local_music.dart';
import 'package:mesting_music/features/local_music/local_music_providers.dart';
import 'package:mesting_music/features/local_music/presentation/local_music_page.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';

Map<String, Object?> _entry({
  String id = 'one',
  String folder = 'recordings',
}) => {
  'id': 'local_$id',
  'uri': 'content://media/external/audio/media/$id',
  'title': id == 'one' ? '夜航.flac' : '晨光',
  'artist': '音乐旅人',
  'album': '旅途',
  'durationMs': 189000,
  'folderId': folder,
  'folderName': folder == 'recordings' ? '随身音乐' : '下载音乐',
  'folderPath': 'Music/$folder',
  'available': true,
};

class _Repository implements LocalMusicRepository {
  _Repository({LocalMusicLibrary? library})
    : library = library ?? const LocalMusicLibrary();
  LocalMusicLibrary library;
  Object? scanError;
  Object? prepareError;
  Completer<LocalMusicLibrary>? picker;
  int loads = 0, scans = 0, files = 0, directories = 0, refreshes = 0;
  @override
  Future<LocalMusicLibrary> load() async {
    loads++;
    return library;
  }

  @override
  Future<LocalMusicLibrary> scan() async {
    scans++;
    if (scanError case final error?) throw error;
    return library;
  }

  @override
  Future<LocalMusicLibrary> importFiles() async {
    files++;
    return picker == null ? library : picker!.future;
  }

  @override
  Future<LocalMusicLibrary> importDirectory() async {
    directories++;
    return library;
  }

  @override
  Future<LocalMusicLibrary> refresh() async {
    refreshes++;
    return library;
  }

  @override
  Future<LocalMusicLibrary> remove(String id) async => LocalMusicLibrary(
    entries: library.entries.where((entry) => entry.id != id).toList(),
  );
  @override
  Future<LocalMusicEntry> prepare(LocalMusicEntry entry) async {
    if (prepareError case final error?) throw error;
    return entry;
  }

  @override
  Future<String> artwork(String id) async => '';
  @override
  Future<void> openSettings() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  const followupExport = bool.fromEnvironment('EXPORT_FOLLOWUP_LOCAL');
  const export = bool.fromEnvironment('EXPORT_V107_LOCAL') || followupExport;
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (export) {
      final bytes = await File('C:/Windows/Fonts/msyh.ttc').readAsBytes();
      for (final font in [
        'Roboto',
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
        'LocalQA',
        'Noto Sans SC',
      ]) {
        await (FontLoader(
          font,
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
      await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
            rootBundle.load(
              'packages/cupertino_icons/assets/CupertinoIcons.ttf',
            ),
          ))
          .load();
    }
  });

  test(
    'local catalog rejects remote addresses and preserves valid, unique files',
    () {
      final library = LocalMusicLibrary.fromMap({
        'permissionGranted': true,
        'entries': [
          _entry(),
          _entry(),
          {..._entry(id: 'two'), 'uri': 'https://example.invalid/audio.mp3'},
          {..._entry(id: 'three'), 'id': 'kugou_forged'},
          {..._entry(id: 'bad-content'), 'uri': 'content:/missing-authority'},
          {..._entry(id: 'bad-file'), 'uri': 'file:'},
          {
            ..._entry(id: 'four'),
            'uri': 'file:///storage/emulated/0/Music/offline.flac',
          },
        ],
      });
      expect(library.entries, hasLength(2));
      expect(library.permissionGranted, isTrue);
      expect(library.entries.first.track.source.name, 'local');
      expect(library.entries.first.track.platformSongId, isEmpty);
      expect(library.entries.any((entry) => entry.track.title == '夜航'), isTrue);
    },
  );

  test(
    'folder identities, searches and unavailable entries survive restoration',
    () {
      final library = LocalMusicLibrary.fromMap({
        'entries': [
          _entry(),
          _entry(id: 'two'),
          {..._entry(id: 'three', folder: 'downloads'), 'available': false},
        ],
      });
      expect(
        library.folders.map((folder) => folder.count),
        containsAll([2, 1]),
      );
      expect(
        library.entries.where((entry) => entry.matches('音乐旅人')),
        hasLength(3),
      );
      expect(
        library.entries.where((entry) => entry.matches('夜航')),
        hasLength(1),
      );
      expect(
        library.entries.singleWhere((entry) => !entry.available).id,
        'local_three',
      );
    },
  );

  test(
    'channel commands retain content URIs and translate permission failures',
    () async {
      const channel = MethodChannel('test.mesting.local_music');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'scan') {
          throw PlatformException(
            code: 'permission_denied',
            message: '请授予音乐权限',
          );
        }
        if (call.method == 'prepare') return _entry();
        if (call.method == 'artwork') {
          return 'file:///private/artwork/local_one.jpg';
        }
        return {
          'entries': [_entry()],
        };
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final repository = AndroidLocalMusicRepository(channel: channel);
      final entry = (await repository.load()).entries.single;
      expect((await repository.prepare(entry)).uri, entry.uri);
      expect(await repository.artwork(entry.id), startsWith('file:'));
      await repository.importFiles();
      await repository.importDirectory();
      await repository.remove(entry.id);
      expect(calls.map((call) => call.method), [
        'load',
        'prepare',
        'artwork',
        'importFiles',
        'importDirectory',
        'remove',
      ]);
      expect(calls.last.arguments, {'id': entry.id});
      await expectLater(
        repository.scan(),
        throwsA(
          isA<LocalMusicException>().having(
            (error) => error.code,
            'code',
            'permission_denied',
          ),
        ),
      );
    },
  );

  test(
    'initialization loads index without initiating scans or permission requests',
    () async {
      final repository = _Repository();
      final container = ProviderContainer(
        overrides: [localMusicRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        localMusicControllerProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      await Future<void>.delayed(Duration.zero);
      expect(repository.loads, 1);
      expect(repository.scans, 0);
      expect(repository.files, 0);
      expect(container.read(localMusicControllerProvider).busy, isFalse);
    },
  );

  test(
    'cancelled file picker preserves existing catalog; late completion is safe after disposal',
    () async {
      final original = LocalMusicLibrary.fromMap({
        'entries': [_entry()],
      });
      final repository = _Repository(library: original);
      final container = ProviderContainer(
        overrides: [localMusicRepositoryProvider.overrideWithValue(repository)],
      );
      final subscription = container.listen(
        localMusicControllerProvider,
        (_, _) {},
      );
      await Future<void>.delayed(Duration.zero);
      final controller = container.read(localMusicControllerProvider.notifier);
      repository.picker = Completer<LocalMusicLibrary>();
      final cancelled = controller.importFiles();
      // Android reports cancellation as the unchanged index, not an empty one.
      repository.picker!.complete(original);
      await cancelled;
      expect(
        container.read(localMusicControllerProvider).library.entries.single.id,
        'local_one',
      );
      repository.picker = Completer<LocalMusicLibrary>();
      final pending = controller.importFiles();
      subscription.close();
      container.dispose();
      repository.picker!.complete(original);
      await pending;
    },
  );

  test(
    'failed permission request preserves catalog; picker coalesces mutations',
    () async {
      final repository = _Repository(
        library: LocalMusicLibrary.fromMap({
          'entries': [_entry()],
        }),
      );
      final container = ProviderContainer(
        overrides: [localMusicRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        localMusicControllerProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      await Future<void>.delayed(Duration.zero);
      final controller = container.read(localMusicControllerProvider.notifier);
      repository.scanError = const LocalMusicException(
        '权限被拒绝',
        code: 'permission_denied',
      );
      await controller.scan();
      expect(
        container.read(localMusicControllerProvider).library.entries,
        hasLength(1),
      );
      expect(
        container.read(localMusicControllerProvider).errorCode,
        'permission_denied',
      );
      repository.picker = Completer<LocalMusicLibrary>();
      final operation = controller.importFiles();
      await controller.refresh();
      expect(repository.refreshes, 0);
      expect(container.read(localMusicControllerProvider).busy, isTrue);
      repository.picker!.complete(repository.library);
      await operation;
      expect(container.read(localMusicControllerProvider).busy, isFalse);
      expect(container.read(localMusicControllerProvider).error, isEmpty);
    },
  );

  Future<void> mount(
    WidgetTester tester,
    _Repository repository, {
    bool dark = false,
    double scale = 1,
    double width = 390,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var theme = buildMestingTheme(
      musicThemePresetById(dark ? 'classic-dark' : 'classic'),
    );
    if (export) {
      theme = theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'LocalQA'),
        // ListTileTheme supplies its own subtitle TextStyle, which bypasses
        // textTheme in the host's Ahem font environment. Production keeps the
        // platform font; this QA-only override makes the Chinese legible.
        listTileTheme: theme.listTileTheme.copyWith(
          subtitleTextStyle: theme.listTileTheme.subtitleTextStyle?.copyWith(
            fontFamily: 'LocalQA',
          ),
        ),
      );
    }
    await tester.pumpWidget(
      LiquidGlassWidgets.wrap(
        adaptiveQuality: false,
        brightnessResolver: Theme.maybeBrightnessOf,
        child: ProviderScope(
          overrides: [
            platformAccountProvider.overrideWith(NoMusicAccountFixture.new),
            localMusicRepositoryProvider.overrideWithValue(repository),
            sharedPreferencesProvider.overrideWithValue(
              await SharedPreferences.getInstance(),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('zh', 'CN'),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: const [Locale('zh', 'CN')],
            theme: theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const RepaintBoundary(
              key: ValueKey('local-qa-capture'),
              child: LocalMusicPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!export) return;
    await tester.runAsync(() async {
      final image = await tester
          .renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('local-qa-capture')),
          )
          .toImage();
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.png,
      ))!.buffer.asUint8List();
      final directory = Directory(
        followupExport
            ? '.codex-artifacts/2026-10-28-followup-ui-sync/screens/local-music'
            : '.codex-artifacts/2026-10-28-release107/local-music',
      );
      await directory.create(recursive: true);
      await File('${directory.path}/$name.png').writeAsBytes(bytes);
      image.dispose();
    });
  }

  testWidgets(
    'empty library exposes actual scan and import choices without scanning',
    (tester) async {
      final repository = _Repository();
      await mount(tester, repository, width: 320, scale: 1.6);
      expect(find.text('扫描手机').hitTestable(), findsOneWidget);
      expect(find.text('导入文件'), findsOneWidget);
      expect(find.text('导入文件夹'), findsOneWidget);
      expect(repository.scans, 0);
      expect(tester.takeException(), isNull);
      await capture(tester, 'empty-light-320-large');
    },
  );

  testWidgets('file and folder import remain side by side at phone width', (
    tester,
  ) async {
    await mount(tester, _Repository(), width: 390);
    final file = tester.getCenter(find.text('导入文件'));
    final folder = tester.getCenter(find.text('导入文件夹'));
    expect(folder.dy, closeTo(file.dy, 1));
    expect(folder.dx, greaterThan(file.dx));
    expect(
      tester.getBottomRight(find.text('导入文件夹')).dx,
      lessThanOrEqualTo(370),
    );
    await capture(tester, 'import-actions-390');
  });

  testWidgets(
    'large text keeps folder import beside file import and horizontally reachable',
    (tester) async {
      final repository = _Repository();
      await mount(tester, repository, width: 320, scale: 1.6);
      expect(
        tester.getCenter(find.text('导入文件夹')).dy,
        tester.getCenter(find.text('导入文件')).dy,
      );
      await tester.ensureVisible(find.text('导入文件夹'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('导入文件夹'));
      await tester.pumpAndSettle();
      expect(repository.directories, 1);
      expect(repository.files, 0);
      expect(repository.scans, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'folders and search use real catalog and retain permission recovery',
    (tester) async {
      final repository = _Repository(
        library: LocalMusicLibrary.fromMap({
          'entries': [_entry(), _entry(id: 'two', folder: 'downloads')],
        }),
      );
      await mount(tester, repository, dark: true);
      expect(find.text('夜航').hitTestable(), findsOneWidget);
      await capture(tester, 'songs-dark');
      await tester.tap(find.text('文件夹'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('随身音乐').hitTestable(), findsOneWidget);
      expect(find.text('下载音乐').hitTestable(), findsOneWidget);
      await capture(tester, 'folders-dark');
      await tester.tap(find.text('随身音乐').hitTestable());
      await tester.pump();
      expect(find.text('夜航').hitTestable(), findsOneWidget);
      expect(find.text('晨光').hitTestable(), findsNothing);
      repository.scanError = const LocalMusicException(
        '请到设置中授予音乐权限',
        code: 'permission_permanently_denied',
      );
      await tester.tap(find.text('扫描手机').hitTestable());
      await tester.pump();
      expect(find.text('前往系统设置授权').hitTestable(), findsOneWidget);
      expect(find.text('夜航').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'search filters songs and folders and shows a recoverable empty folder result',
    (tester) async {
      final repository = _Repository(
        library: LocalMusicLibrary.fromMap({
          'entries': [_entry(), _entry(id: 'two', folder: 'downloads')],
        }),
      );
      await mount(tester, repository);
      await tester.enterText(find.byType(EditableText), '夜航');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('local_one')),
          matching: find.text('夜航').hitTestable(),
        ),
        findsOneWidget,
      );
      expect(find.text('晨光').hitTestable(), findsNothing);
      await tester.tap(find.text('文件夹'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('随身音乐').hitTestable(), findsOneWidget);
      expect(find.text('下载音乐').hitTestable(), findsNothing);
      await tester.enterText(find.byType(EditableText), '不存在');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('没有找到文件夹').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'revoked or removed file is marked unavailable without starting playback',
    (tester) async {
      final repository =
          _Repository(
              library: LocalMusicLibrary.fromMap({
                'entries': [_entry()],
              }),
            )
            ..prepareError = const LocalMusicException(
              '文件已移动、删除或授权已失效，请重新导入',
              code: 'unavailable',
            );
      await mount(tester, repository);
      await tester.tap(find.byKey(const ValueKey('local_one')));
      await tester.pump();
      expect(find.text('文件不可用 · 重新导入以恢复'), findsOneWidget);
      expect(find.text('文件暂时无法播放'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
