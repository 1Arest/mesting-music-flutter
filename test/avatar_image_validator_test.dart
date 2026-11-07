import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/security/avatar_image_validator.dart';

void main() {
  test('detects avatar type from bytes instead of filename', () async {
    final directory = await Directory.systemTemp.createTemp(
      'avatar_validation_',
    );
    try {
      final file = File('${directory.path}${Platform.pathSeparator}avatar.txt');
      await file.writeAsBytes(const [
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        0,
        0,
        0,
        0,
      ]);

      final result = await validateAvatarImage(file.path);

      expect(result.extension, '.png');
      expect(result.mimeType, 'image/png');
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('rejects a renamed non-image before upload', () async {
    final directory = await Directory.systemTemp.createTemp(
      'avatar_validation_',
    );
    try {
      final file = File('${directory.path}${Platform.pathSeparator}avatar.png');
      await file.writeAsString('not an image');

      await expectLater(
        validateAvatarImage(file.path),
        throwsA(
          isA<AvatarValidationException>().having(
            (error) => error.message,
            'message',
            contains('JPG、PNG 或 WebP'),
          ),
        ),
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('rejects an oversized image before reading it into memory', () async {
    final directory = await Directory.systemTemp.createTemp(
      'avatar_validation_',
    );
    try {
      final file = File('${directory.path}${Platform.pathSeparator}avatar.jpg');
      await file.writeAsBytes(const [0xFF, 0xD8, 0xFF, 0]);

      await expectLater(
        validateAvatarImage(file.path, maxBytes: 3),
        throwsA(
          isA<AvatarValidationException>().having(
            (error) => error.message,
            'message',
            contains('5 MB'),
          ),
        ),
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
