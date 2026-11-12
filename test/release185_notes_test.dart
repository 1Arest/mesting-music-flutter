import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/app_update/domain/release_history.dart';

void main() {
  test(
    'all public versions have offline history and current APK notes match',
    () {
      final version = RegExp(
        r'^version: (\d+\.\d+\.\d+)\+(\d+)$',
        multiLine: true,
      ).firstMatch(File('pubspec.yaml').readAsStringSync())!;
      // A minor-version rollover must preserve the entire 1.0 history, rather
      // than interpreting 1.1.0 as an empty range of historical patch releases.
      final legacyLast = musicReleaseNotes.keys
          .map((key) => RegExp(r'^1\.0\.(\d+)$').firstMatch(key))
          .whereType<RegExpMatch>()
          .map((match) => int.parse(match[1]!))
          .fold<int>(0, (last, patch) => patch > last ? patch : last);
      for (var n = 1; n <= legacyLast; n++) {
        // v38 was a private native-debug candidate, never a public code59
        // delivery. Historical notes must not fabricate a formal release.
        if (n == 38) continue;
        final notes = notesForMusicVersion('1.0.$n');
        expect(notes, isNotEmpty, reason: 'v1.0.$n');
        expect(notes.every((s) => s.trim().isNotEmpty), true);
      }
      expect(musicReleaseNotes.keys.first, version[1]);
      final json =
          jsonDecode(File('assets/data/release-notes.json').readAsStringSync())
              as Map;
      expect(json['version'], version[1]);
      expect(json['versionCode'], int.parse(version[2]!));
      expect(json['releaseNotes'], notesForMusicVersion(version[1]!));
      expect(notesForMusicVersion('9.9.9'), isEmpty);
      expect(notesForMusicVersion('1.0.38'), isEmpty);
      expect(notesForMusicVersion('1.0.74').join(), contains('未完成稳定性验收'));
      expect(notesForMusicVersion('1.0.81').join(), contains('只读'));
    },
  );
}
