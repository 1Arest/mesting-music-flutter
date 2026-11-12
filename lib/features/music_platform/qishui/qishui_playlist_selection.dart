import '../../../shared/models/track.dart';

/// A batch screen edits a private order draft. Track ids, rather than list
/// indices, own selection, so a drag cannot silently select another recording.
/// No server mutation occurs until the user explicitly submits the draft.
class QishuiPlaylistSelection {
  QishuiPlaylistSelection(Iterable<Track> tracks)
    : _tracks = List.of(tracks),
      _original = tracks.map((track) => track.id).toList();

  final List<Track> _tracks;
  final List<String> _original;
  final Set<String> _selected = {};

  List<Track> get tracks => List.unmodifiable(_tracks);
  List<Track> get selected =>
      _tracks.where((track) => _selected.contains(track.id)).toList();
  int get selectedCount => _selected.length;
  bool get allSelected =>
      _tracks.isNotEmpty && _selected.length == _tracks.length;
  bool contains(String id) => _selected.contains(id);

  bool get orderChanged {
    if (_tracks.length != _original.length) return true;
    for (var index = 0; index < _tracks.length; index++) {
      if (_tracks[index].id != _original[index]) return true;
    }
    return false;
  }

  void toggle(String id) {
    if (!_tracks.any((track) => track.id == id)) return;
    if (!_selected.remove(id)) _selected.add(id);
  }

  void toggleAll() {
    if (allSelected) {
      _selected.clear();
    } else {
      _selected.addAll(_tracks.map((track) => track.id));
    }
  }

  /// Matches ReorderableListView's insertion position before source removal.
  void move(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _tracks.length) return;
    if (newIndex > oldIndex) newIndex--;
    final destination = newIndex.clamp(0, _tracks.length - 1);
    _tracks.insert(destination, _tracks.removeAt(oldIndex));
  }

  /// A confirmed membership write changes the server baseline, while an
  /// unsaved drag order remains a separate draft. Keep remaining ids in their
  /// local order and append newly returned members, without reviving removals.
  void acceptMembership(Iterable<Track> latest) {
    final incoming = {for (final track in latest) track.id: track};
    final ordered = [
      for (final track in _tracks)
        if (incoming.containsKey(track.id)) incoming.remove(track.id)!,
      ...incoming.values,
    ];
    _tracks
      ..clear()
      ..addAll(ordered);
    _original
      ..clear()
      ..addAll(latest.map((track) => track.id));
    _selected.retainAll(_tracks.map((track) => track.id));
  }
}
