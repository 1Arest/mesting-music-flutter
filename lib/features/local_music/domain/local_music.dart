import '../../../shared/models/track.dart';

/// Device-library identities are URI based, independently of any cloud account.
/// A local file is never relabelled as a Kugou recording to make it playable.
class LocalMusicEntry {
  const LocalMusicEntry({
    required this.id,
    required this.uri,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.folderId,
    required this.folderName,
    this.folderPath = '',
    this.artwork = '',
    this.available = true,
    this.origin = 'file',
  });

  final String id, uri, title, artist, album, folderId, folderName;
  final String folderPath, artwork, origin;
  final Duration duration;
  final bool available;
  static final _tracks = Expando<Track>('local-music-track');
  static final _searchTexts = Expando<String>('local-music-search');

  factory LocalMusicEntry.fromMap(Map<Object?, Object?> map) {
    String text(String key) => '${map[key] ?? ''}'.trim();
    final id = text('id');
    final uri = text('uri');
    final parsed = Uri.tryParse(uri);
    if (!id.startsWith('local_') ||
        parsed == null ||
        !const {'content', 'file'}.contains(parsed.scheme) ||
        parsed.path.isEmpty ||
        parsed.pathSegments.every((segment) => segment.isEmpty) ||
        (parsed.scheme == 'content' && parsed.host.isEmpty)) {
      throw const FormatException('本地音乐条目缺少有效的文件地址');
    }
    final milliseconds = int.tryParse('${map['durationMs']}') ?? 0;
    return LocalMusicEntry(
      id: id,
      uri: uri,
      title: text('title').isEmpty ? '未命名音频' : text('title'),
      artist: text('artist').isEmpty ? '未知歌手' : text('artist'),
      album: text('album').isEmpty ? '未知专辑' : text('album'),
      duration: Duration(milliseconds: milliseconds.clamp(0, 1 << 53)),
      folderId: text('folderId'),
      folderName: text('folderName').isEmpty ? '导入的文件' : text('folderName'),
      folderPath: text('folderPath'),
      artwork: text('artwork'),
      available: map['available'] != false,
      origin: text('origin'),
    );
  }

  /// Reading a row title must not construct a playback object. The immutable
  /// entry also reuses its track when it is later queued or played repeatedly.
  String get displayTitle => musicDisplayTitle(title);
  Track get track => _tracks[this] ??= Track(
    id: id,
    title: title,
    artist: artist,
    album: album,
    duration: duration,
    audioAsset: uri,
    coverAsset: artwork,
    lyricsAsset: '',
    source: TrackSource.local,
    provider: '本地音乐',
  );

  bool matches(String query) {
    final needle = query.trim().toLowerCase();
    return needle.isEmpty ||
        (_searchTexts[this] ??= '$title\n$artist\n$album\n$folderName'
                .toLowerCase())
            .contains(needle);
  }

  LocalMusicEntry withAvailability(bool value) => LocalMusicEntry(
    id: id,
    uri: uri,
    title: title,
    artist: artist,
    album: album,
    duration: duration,
    folderId: folderId,
    folderName: folderName,
    folderPath: folderPath,
    artwork: artwork,
    available: value,
    origin: origin,
  );
}

class LocalMusicFolder {
  const LocalMusicFolder(this.id, this.name, this.path, this.count);
  final String id, name, path;
  final int count;
}

class LocalMusicLibrary {
  const LocalMusicLibrary({
    this.entries = const [],
    this.permissionGranted = false,
    this.notice = '',
  }) : _preparedFolders = null;
  const LocalMusicLibrary._prepared({
    required this.entries,
    required this.permissionGranted,
    required this.notice,
    required List<LocalMusicFolder> folders,
  }) : _preparedFolders = folders;
  final List<LocalMusicEntry> entries;
  final bool permissionGranted;
  final String notice;
  final List<LocalMusicFolder>? _preparedFolders;
  static final _folderCache = Expando<List<LocalMusicFolder>>(
    'local-music-library-folders',
  );

  factory LocalMusicLibrary.fromMap(Map<Object?, Object?> map) {
    final entries = <LocalMusicEntry>[];
    final identities = <String>{};
    final rows = map['entries'];
    if (rows is List) {
      for (final row in rows.take(10000)) {
        if (row is! Map) continue;
        try {
          final entry = LocalMusicEntry.fromMap(row);
          if (identities.add(entry.id)) entries.add(entry);
        } on FormatException {
          // An obsolete entry must not hide the rest of an imported directory.
        }
      }
    }
    entries.sort((a, b) => a.title.compareTo(b.title));
    return LocalMusicLibrary._prepared(
      entries: List.unmodifiable(entries),
      permissionGranted: map['permissionGranted'] == true,
      notice: '${map['notice'] ?? ''}',
      folders: _groupLocalFolders(entries),
    );
  }

  /// A library is one immutable device snapshot. Parsed snapshots carry their
  /// worker-built groups; manually constructed snapshots group only once.
  List<LocalMusicFolder> get folders =>
      _preparedFolders ?? (_folderCache[this] ??= _groupLocalFolders(entries));
}

List<LocalMusicFolder> _groupLocalFolders(List<LocalMusicEntry> entries) {
  final groups = <String, _LocalFolderCount>{};
  for (final entry in entries) {
    final group = groups.putIfAbsent(
      entry.folderId,
      () => _LocalFolderCount(entry),
    );
    group.entry = entry;
    group.count++;
  }
  final folders = [
    for (final group in groups.values)
      LocalMusicFolder(
        group.entry.folderId,
        group.entry.folderName,
        group.entry.folderPath,
        group.count,
      ),
  ]..sort((a, b) => a.name.compareTo(b.name));
  return List.unmodifiable(folders);
}

class _LocalFolderCount {
  _LocalFolderCount(this.entry);
  LocalMusicEntry entry;
  int count = 0;
}

/// Complete derived collections, rather than a rendering window, remain the
/// source for search, folder contents and playback-all. Busy/artwork rebuilds
/// reuse the same result while a new device snapshot invalidates every query.
class LocalMusicView {
  const LocalMusicView({
    required this.entries,
    required this.available,
    required this.folders,
    required this.selectedFolder,
  });
  final List<LocalMusicEntry> entries, available;
  final List<LocalMusicFolder> folders;
  final LocalMusicFolder? selectedFolder;
}

class LocalMusicViewCache {
  LocalMusicLibrary? _library;
  final _views = <(String, String?), LocalMusicView>{};

  LocalMusicView select(
    LocalMusicLibrary library, {
    String query = '',
    String? folderId,
  }) {
    if (!identical(library, _library)) {
      _library = library;
      _views.clear();
    }
    final needle = query.trim().toLowerCase(),
        key = (query.trim().toLowerCase(), folderId);
    final cached = _views.remove(key);
    if (cached != null) {
      _views[key] = cached;
      return cached;
    }
    final matching = needle.isEmpty
        ? library.entries
        : library.entries
              .where((entry) => entry.matches(needle))
              .toList(growable: false);
    final entries = folderId == null
        ? matching
        : matching
              .where((entry) => entry.folderId == folderId)
              .toList(growable: false);
    final matchingFolders = needle.isEmpty
        ? null
        : matching.map((entry) => entry.folderId).toSet();
    final result = LocalMusicView(
      entries: List.unmodifiable(entries),
      available: List.unmodifiable(entries.where((entry) => entry.available)),
      folders: matchingFolders == null
          ? library.folders
          : List.unmodifiable(
              library.folders.where(
                (folder) => matchingFolders.contains(folder.id),
              ),
            ),
      selectedFolder: library.folders
          .where((folder) => folder.id == folderId)
          .firstOrNull,
    );
    if (_views.length >= 8) _views.remove(_views.keys.first);
    _views[key] = result;
    return result;
  }
}
