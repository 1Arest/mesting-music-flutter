import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'release_144_qa.dart' show theme144;
import 'release_147_qa.dart' show load147IconFonts;

const capture151 = bool.fromEnvironment('CAPTURE_151');
const _directory = String.fromEnvironment(
  'CAPTURE_151_DIR',
  defaultValue: '.codex-artifacts/2026-11-04-release151/ui-round1',
);
const _capture = ValueKey('qa151');

/// Host-only CJK font substitution. No desktop font enters the APK or source
/// assets; production continues using its existing system typography.
Future<void> initialize151QA() async {
  await LiquidGlassWidgets.initialize();
  if (!capture151) return;
  await load147IconFonts();
  for (final family in [
    'MestingQA151',
    'Roboto',
    'CupertinoSystemText',
    'CupertinoSystemDisplay',
  ]) {
    await (FontLoader(family)..addFont(
          File(
            'C:/Windows/Fonts/msyh.ttc',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
  }
}

ThemeData theme151(bool dark) {
  final theme = theme144(dark);
  return !capture151
      ? theme
      : theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'MestingQA151'),
          listTileTheme: theme.listTileTheme.copyWith(
            titleTextStyle: TextStyle(
              fontFamily: 'MestingQA151',
              fontSize: 16,
              color: theme.colorScheme.onSurface,
            ),
            subtitleTextStyle: TextStyle(
              fontFamily: 'MestingQA151',
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        );
}

Widget capture151Builder(Widget child) =>
    RepaintBoundary(key: _capture, child: child);

/// Capture the actual current frame without settling its transition away.
Future<void> shot151(WidgetTester tester, String name) async {
  if (!capture151) return;
  final frame = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  await tester.runAsync(() async {
    final image = await frame.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$_directory/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
