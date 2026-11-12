import 'dart:io';
import 'package:flutter/services.dart';

/// Host fonts are fixture dependencies, never packaged into Android assets.
Future<void> load147IconFonts() async {
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
