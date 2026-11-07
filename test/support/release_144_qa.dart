import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';

const capture144 = bool.fromEnvironment('CAPTURE_144');
const capture144Key = ValueKey('release144-capture');

Future<void> initialize144QA() async {
  await LiquidGlassWidgets.initialize();
  if (!capture144) return;
  for (final name in [
    'MestingQA',
    'Roboto',
    'CupertinoSystemText',
    'CupertinoSystemDisplay',
  ]) {
    await (FontLoader(name)..addFont(
          File(
            'C:/Windows/Fonts/msyh.ttc',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
  }
  await (FontLoader('MaterialIcons')..addFont(
        File(
          'D:/CodexCache/flutter-3.41.9/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        ).readAsBytes().then(ByteData.sublistView),
      ))
      .load();
  await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
        rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
      ))
      .load();
}

ThemeData theme144(bool dark) {
  final theme = buildMestingTheme(
    musicThemePresetById(dark ? 'classic-dark' : 'classic'),
  );
  if (!capture144) return theme;
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: 'MestingQA'),
    listTileTheme: theme.listTileTheme.copyWith(
      titleTextStyle: TextStyle(
        fontFamily: 'MestingQA',
        fontSize: 16,
        color: theme.colorScheme.onSurface,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: 'MestingQA',
        fontSize: 13,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

Future<void> capture144UI(WidgetTester tester, String name) async {
  if (!capture144) return;
  // Let the real bundled image providers decode outside the fake test clock.
  // Capturing a readiness curtain would verify the palette but hide the very
  // room/member layout this render is meant to inspect.
  final imageWidgets = tester.widgetList<Image>(find.byType(Image)).toList();
  if (imageWidgets.isNotEmpty) {
    final context = tester.element(find.byType(Image).first);
    await tester.runAsync(
      () => Future.wait([
        for (final widget in imageWidgets) precacheImage(widget.image, context),
      ]),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }
  final imageFuture = tester
      .renderObject<RenderRepaintBoundary>(find.byKey(capture144Key))
      .toImage();
  await tester.runAsync(() async {
    final image = await imageFuture;
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final path = File('.codex-artifacts/2026-11-03-release144/ui/$name.png');
    await path.parent.create(recursive: true);
    await path.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Widget capture144Builder(BuildContext context, Widget? child) =>
    RepaintBoundary(key: capture144Key, child: child!);
