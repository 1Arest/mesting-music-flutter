import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('无内置本地音乐', () {
    test('发布资源清单不再包含本地音频、歌词或演示封面', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();

      expect(pubspec, isNot(contains('assets/audio/')));
      expect(pubspec, isNot(contains('assets/lyrics/')));
      expect(pubspec, isNot(contains('assets/images/covers/')));
    });

    test('内置歌曲资源目录已从工程移除', () {
      expect(Directory('assets/audio').existsSync(), isFalse);
      expect(Directory('assets/lyrics').existsSync(), isFalse);
      expect(Directory('assets/images/covers').existsSync(), isFalse);
    });
  });
}
