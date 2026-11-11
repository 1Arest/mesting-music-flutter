import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/app_update/domain/release_history.dart';

void main() {
  test(
    'all public versions have offline history and current APK notes match',
    () {
      for (var n = 1; n <= 90; n++) {
        // v38 was a private native-debug candidate, never a public code59
        // delivery. Historical notes must not fabricate a formal release.
        if (n == 38) continue;
        final notes = notesForMusicVersion('1.0.$n');
        expect(notes, isNotEmpty, reason: 'v1.0.$n');
        expect(notes.every((s) => s.trim().isNotEmpty), true);
      }
      expect(musicReleaseNotes.keys.first, '1.0.91');
      final json =
          jsonDecode(File('assets/data/release-notes.json').readAsStringSync())
              as Map;
      expect(json['version'], '1.0.91');
      expect(json['versionCode'], 112);
      expect(json['releaseNotes'], notesForMusicVersion('1.0.91'));
      expect(notesForMusicVersion('9.9.9'), isEmpty);
      expect(notesForMusicVersion('1.0.38'), isEmpty);
      expect(notesForMusicVersion('1.0.74').join(), contains('未完成稳定性验收'));
      expect(notesForMusicVersion('1.0.81').join(), contains('只读'));
    },
  );
}
