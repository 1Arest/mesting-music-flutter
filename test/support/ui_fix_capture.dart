import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const uiFixCaptureDirectory = String.fromEnvironment('UI_FIX_CAPTURE_DIR');
const uiFixCaptureKey = ValueKey('ui-fix-capture');

/// Optional host-only screenshots; CI does not depend on a desktop font or a
/// writable artifacts directory. No host fonts are bundled into the product.
Future<void> initializeUiFixCapture() async {
  if (uiFixCaptureDirectory.isEmpty) return;
  const fontPath = String.fromEnvironment(
    'UI_FIX_FONT',
    defaultValue: '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
  );
  final fontBytes = File(fontPath).readAsBytes().then(ByteData.sublistView);
  for (final family in [
    'UiFixCJK',
    'Roboto',
    'CupertinoSystemText',
    'CupertinoSystemDisplay',
  ]) {
    await (FontLoader(family)..addFont(fontBytes)).load();
  }
  await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
        rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
      ))
      .load();
}

Future<void> captureUiFix(WidgetTester tester, String name) async {
  if (uiFixCaptureDirectory.isEmpty) return;
  // Image decode runs on real I/O; pumpAndSettle alone can finish before
  // transparent portraits have painted their first frame in a widget test.
  final context = tester.element(find.byKey(uiFixCaptureKey));
  final providers = tester
      .widgetList<Image>(find.byType(Image))
      .map((image) => image.image)
      .toList();
  var decoded = false;
  final pending = Future.wait(
    providers.map((provider) => precacheImage(provider, context)),
  ).then((_) => decoded = true);
  // Animated WebP emits its first image on a scheduler frame. Keep pumping
  // while real decode I/O completes rather than awaiting it without frames.
  for (var attempt = 0; attempt < 100 && !decoded; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(decoded, true, reason: 'preview assets finish decoding');
  await pending;
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(uiFixCaptureKey),
  );
  await tester.runAsync(() async {
    final frame = await boundary.toImage(pixelRatio: 2);
    final bytes = await frame.toByteData(format: ui.ImageByteFormat.png);
    final target = File('$uiFixCaptureDirectory/$name.png');
    await target.parent.create(recursive: true);
    await target.writeAsBytes(bytes!.buffer.asUint8List());
    frame.dispose();
  });
}
