enum PlaybackMode {
  sequential,
  list,
  single,
  random;

  String get label => switch (this) {
    PlaybackMode.sequential => '顺序播放',
    PlaybackMode.list => '列表循环',
    PlaybackMode.single => '单曲循环',
    PlaybackMode.random => '随机播放',
  };

  PlaybackMode get next =>
      PlaybackMode.values[(index + 1) % PlaybackMode.values.length];
}

/// System repeat/shuffle remain independent; app menus expose four clear modes.
/// Existing three-mode and v2 sessions still retain their saved preference.
enum PlaybackRepeat {
  off,
  all,
  one;

  String get label => switch (this) {
    off => '顺序播放',
    all => '列表循环',
    one => '单曲循环',
  };
}

class PlaybackOrder {
  const PlaybackOrder({this.repeat = PlaybackRepeat.off, this.shuffle = false});
  final PlaybackRepeat repeat;
  final bool shuffle;

  /// Shared wording for the queue controls, their HUD and the toolbar badge.
  String get label => legacy.label;
  PlaybackMode get legacy => repeat == PlaybackRepeat.one
      ? PlaybackMode.single
      : shuffle
      ? PlaybackMode.random
      : repeat == PlaybackRepeat.off
      ? PlaybackMode.sequential
      : PlaybackMode.list;
  PlaybackOrder copyWith({PlaybackRepeat? repeat, bool? shuffle}) =>
      PlaybackOrder(
        repeat: repeat ?? this.repeat,
        shuffle: shuffle ?? this.shuffle,
      );
  String get serialized => 'v2:${repeat.name}:${shuffle ? 1 : 0}';
  static PlaybackOrder fromLegacy(PlaybackMode mode) => PlaybackOrder(
    repeat: mode == PlaybackMode.single
        ? PlaybackRepeat.one
        : mode == PlaybackMode.sequential
        ? PlaybackRepeat.off
        : PlaybackRepeat.all,
    shuffle: mode == PlaybackMode.random,
  );
  static PlaybackOrder parse(String value) {
    final parts = value.split(':');
    if (parts.length == 3 && parts.first == 'v2') {
      return PlaybackOrder(
        repeat: PlaybackRepeat.values.firstWhere(
          (r) => r.name == parts[1],
          orElse: () => PlaybackRepeat.off,
        ),
        shuffle: parts[2] == '1',
      );
    }
    return fromLegacy(
      PlaybackMode.values.firstWhere(
        (m) => m.name == value,
        orElse: () => PlaybackMode.sequential,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlaybackOrder &&
      other.repeat == repeat &&
      other.shuffle == shuffle;
  @override
  int get hashCode => Object.hash(repeat, shuffle);
}
