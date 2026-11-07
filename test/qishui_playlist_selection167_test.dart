import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_playlist_selection.dart';
import 'package:mesting_music/shared/models/track.dart';

Track song(String id, {String? title}) => Track(
  id: 'qishui_$id',
  title: title ?? id,
  artist: 'artist',
  album: 'album',
  duration: const Duration(minutes: 3),
  audioAsset: 'mesting-platform://qishui/$id',
  coverAsset: '',
  lyricsAsset: '',
  platformSongId: id,
  source: TrackSource.qishui,
);

void main() {
  test(
    'drag preserves selected recording identity and reverse drag is clean',
    () {
      final draft = QishuiPlaylistSelection([song('a'), song('b'), song('c')]);
      draft.toggle('qishui_a');
      draft.move(0, 3);
      expect(draft.tracks.map((track) => track.platformSongId), [
        'b',
        'c',
        'a',
      ]);
      expect(draft.selected.single.platformSongId, 'a');
      expect(draft.orderChanged, isTrue);
      draft.move(2, 0);
      expect(draft.orderChanged, isFalse);
      expect(draft.selected.single.platformSongId, 'a');
    },
  );

  test('server removal cannot be revived by a pending sort draft', () {
    final draft = QishuiPlaylistSelection([song('a'), song('b'), song('c')]);
    draft.toggle('qishui_a');
    draft.toggle('qishui_b');
    draft.move(2, 0);
    draft.acceptMembership([song('a', title: 'fresh metadata'), song('c')]);
    expect(draft.tracks.map((track) => track.platformSongId), ['c', 'a']);
    expect(draft.selected.map((track) => track.platformSongId), ['a']);
    expect(draft.tracks.last.title, 'fresh metadata');
    expect(draft.orderChanged, isTrue);
  });

  test(
    'server membership refresh keeps new songs and needs no invented order',
    () {
      final draft = QishuiPlaylistSelection([song('a'), song('b')]);
      draft.toggleAll();
      draft.acceptMembership([song('a'), song('b'), song('server-new')]);
      expect(draft.tracks.map((track) => track.platformSongId), [
        'a',
        'b',
        'server-new',
      ]);
      expect(draft.orderChanged, isFalse);
      expect(draft.selectedCount, 2);
      expect(draft.allSelected, isFalse);
      draft.toggleAll();
      expect(draft.allSelected, isTrue);
    },
  );

  test(
    'empty membership clears selection and cannot manufacture a selected id',
    () {
      final draft = QishuiPlaylistSelection([song('a')]);
      draft.toggleAll();
      draft.acceptMembership([]);
      draft.toggle('not-a-member');
      draft.toggleAll();
      expect(draft.selectedCount, 0);
      expect(draft.allSelected, isFalse);
      expect(draft.orderChanged, isFalse);
    },
  );
}
