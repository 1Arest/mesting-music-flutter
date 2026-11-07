import 'package:audio_service/audio_service.dart';
import 'audio_origin.dart';
export 'audio_origin.dart';

enum TrackSource { local, kugou, netease, audius, jamendo, qishui }

final _audioTitleSuffix = RegExp(
  r'\.(?:mp3|flac|m4a|wav|aac|ogg|opus|wma|aiff|aif|alac|ape|dsf|dff)\s*$',
  caseSensitive: false,
);

/// Only a recognized file extension at the end is presentation noise. Text
/// such as "Live", "伴奏", punctuation and an extension inside a title survives.
String musicDisplayTitle(String title) {
  final match = _audioTitleSuffix.firstMatch(title);
  if (match == null || title.substring(0, match.start).trim().isEmpty) {
    return title;
  }
  return title.substring(0, match.start).trimRight();
}

class Track {
  const Track({
    required this.id,
    required String title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.audioAsset,
    required this.coverAsset,
    required this.lyricsAsset,
    this.source = TrackSource.local,
    this.provider = '本地',
    this.isPreview = false,
    this.externalUrl = '',
    this.licenseUrl = '',
    this.availabilityMessage = '',
    this.platformSongId = '',
    this.playbackQuality = '',
    this.audioHeaders = const {},
    this.audioBitrate = 0,
    this.audioOrigin,
    this.audioAlternatives = const [],
  }) : _sourceTitle = title;

  final String id;
  final String _sourceTitle;

  /// All consumers, including restored history and Android media metadata,
  /// use the same display name. Preserve the upstream value in persistence:
  /// stripping a known terminal audio extension must not rename a file or ID.
  String get title => musicDisplayTitle(_sourceTitle);
  final String artist;
  final String album;
  final Duration duration;
  final String audioAsset;

  /// Exact alternative URLs returned for this recording and quality. A new
  /// resolved primary clears old candidates unless the resolver supplies them.
  final List<String> audioAlternatives;
  final String coverAsset;
  final String lyricsAsset;
  final TrackSource source;
  final String provider;
  final bool isPreview;
  final String externalUrl;
  final String licenseUrl;
  final String availabilityMessage;

  /// Upstream mixsongid/album_audio_id, independent of the playable file hash.
  /// Optional for older local rows; comments can resolve it on demand.
  final String platformSongId;

  /// Actual quality returned by the platform, not the user's requested tier.
  /// Optional so older saved tracks and other sources remain compatible.
  final String playbackQuality;

  /// Anonymous CDN playback requirements only. Platform cookies and tokens
  /// must never be placed here: tracks also travel through history/media items.
  final Map<String, String> audioHeaders;
  final int audioBitrate;

  /// The resolved transport may differ from [source], which remains the
  /// catalogue/library identity used by likes, lyrics and listening reports.
  final AudioOrigin? audioOrigin;

  /// A saved recording keeps its original platform identity for library and
  /// listening synchronization, while its transport can be entirely offline.
  bool get hasLocalAudio =>
      audioAsset.startsWith('content://') || audioAsset.startsWith('file://');
  bool get isRemote => source != TrackSource.local && !hasLocalAudio;
  String get resolvedLyricsAsset {
    final value = lyricsAsset.trim();
    if (value.isNotEmpty) return value;
    if (source == TrackSource.kugou && id.startsWith('kugou_')) {
      final hash = id.substring('kugou_'.length);
      if (hash.isNotEmpty) {
        return Uri(
          scheme: 'mesting-lyrics',
          host: 'kugou',
          path: '/$hash',
          queryParameters: {'durationMs': '${duration.inMilliseconds}'},
        ).toString();
      }
    }
    return '';
  }

  bool get hasLyrics => resolvedLyricsAsset.isNotEmpty;
  bool get isPlayable => audioAsset.trim().isNotEmpty;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'title': _sourceTitle,
      'artist': artist,
      'album': album,
      'durationMs': duration.inMilliseconds,
      'audioAsset': audioAsset,
      if (audioAlternatives.isNotEmpty) 'audioAlternatives': audioAlternatives,
      'coverAsset': coverAsset,
      'lyricsAsset': resolvedLyricsAsset,
      'source': source.name,
      'provider': provider,
      'isPreview': isPreview,
      'externalUrl': externalUrl,
      'licenseUrl': licenseUrl,
      'availabilityMessage': availabilityMessage,
      'platformSongId': platformSongId,
      'playbackQuality': playbackQuality,
      'audioHeaders': publicAudioHeaders(audioHeaders),
      'audioBitrate': audioBitrate,
      if (audioOrigin != null) 'audioOrigin': audioOrigin!.toJson(),
    };
  }

  factory Track.fromJson(Map<String, Object?> json) {
    return Track(
      id: json['id']! as String,
      title: json['title']! as String,
      artist: json['artist']! as String,
      album: json['album']! as String,
      duration: Duration(milliseconds: json['durationMs']! as int),
      audioAsset: json['audioAsset']! as String,
      audioAlternatives: publicAudioAlternatives(json['audioAlternatives']),
      coverAsset: json['coverAsset']! as String,
      lyricsAsset: json['lyricsAsset']! as String,
      source: TrackSource.values.firstWhere(
        (source) => source.name == json['source'],
        orElse: () => TrackSource.local,
      ),
      provider: json['provider'] as String? ?? '本地',
      isPreview: json['isPreview'] as bool? ?? false,
      externalUrl: json['externalUrl'] as String? ?? '',
      licenseUrl: json['licenseUrl'] as String? ?? '',
      availabilityMessage: json['availabilityMessage'] as String? ?? '',
      platformSongId: json['platformSongId'] as String? ?? '',
      playbackQuality: json['playbackQuality'] as String? ?? '',
      audioHeaders: publicAudioHeaders(json['audioHeaders']),
      audioBitrate: json['audioBitrate'] as int? ?? 0,
      audioOrigin: AudioOrigin.fromJson(json['audioOrigin']),
    );
  }

  MediaItem toMediaItem({Uri? artUri}) {
    final resolvedArtwork =
        artUri ??
        ((isRemote ||
                coverAsset.startsWith('http') ||
                coverAsset.startsWith('file://'))
            ? Uri.tryParse(coverAsset)
            : null);
    return MediaItem(
      id: id,
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      artUri: resolvedArtwork,
      extras: {
        'audioAsset': audioAsset,
        if (audioAlternatives.isNotEmpty)
          'audioAlternatives': audioAlternatives,
        'coverAsset': coverAsset,
        'lyricsAsset': resolvedLyricsAsset,
        'source': source.name,
        'provider': provider,
        'isPreview': isPreview,
        'externalUrl': externalUrl,
        'availabilityMessage': availabilityMessage,
        'platformSongId': platformSongId,
        'playbackQuality': playbackQuality,
        'audioHeaders': publicAudioHeaders(audioHeaders),
        'audioBitrate': audioBitrate,
        if (audioOrigin != null) 'audioOrigin': audioOrigin!.toJson(),
      },
    );
  }

  Track copyWith({
    Duration? duration,
    String? audioAsset,
    String? coverAsset,
    String? lyricsAsset,
    bool? isPreview,
    String? availabilityMessage,
    String? platformSongId,
    String? playbackQuality,
    Map<String, String>? audioHeaders,
    int? audioBitrate,
    AudioOrigin? audioOrigin,
    List<String>? audioAlternatives,
  }) {
    return Track(
      id: id,
      title: _sourceTitle,
      artist: artist,
      album: album,
      duration: duration ?? this.duration,
      audioAsset: audioAsset ?? this.audioAsset,
      audioAlternatives:
          audioAlternatives ??
          (audioAsset == null ? this.audioAlternatives : const []),
      coverAsset: coverAsset ?? this.coverAsset,
      lyricsAsset: lyricsAsset ?? this.lyricsAsset,
      source: source,
      provider: provider,
      isPreview: isPreview ?? this.isPreview,
      externalUrl: externalUrl,
      licenseUrl: licenseUrl,
      availabilityMessage: availabilityMessage ?? this.availabilityMessage,
      platformSongId: platformSongId ?? this.platformSongId,
      playbackQuality: playbackQuality ?? this.playbackQuality,
      audioHeaders: audioHeaders ?? this.audioHeaders,
      audioBitrate: audioBitrate ?? this.audioBitrate,
      audioOrigin: audioOrigin ?? this.audioOrigin,
    );
  }
}

/// Allow only public media headers across persistence and playback boundaries.
/// Explicitly excludes Cookie/Authorization and rejects header injection.
Map<String, String> publicAudioHeaders(Object? value) {
  if (value is! Map) return const {};
  return Map.unmodifiable({
    for (final entry in value.entries)
      if ({
            'referer',
            'user-agent',
            'origin',
          }.contains('${entry.key}'.toLowerCase()) &&
          entry.value is String &&
          !RegExp(r'[\r\n]').hasMatch(entry.value as String))
        '${entry.key}': entry.value as String,
  });
}

/// Keep only a bounded list of absolute HTTP media URLs; never synthesize a CDN
/// hostname, change a signature, downgrade HTTPS or attach authentication.
List<String> publicAudioAlternatives(Object? value) {
  if (value is! List) return const [];
  return List.unmodifiable(
    value
        .whereType<String>()
        .where((text) {
          final uri = Uri.tryParse(text);
          return uri != null &&
              {'http', 'https'}.contains(uri.scheme) &&
              uri.host.isNotEmpty &&
              uri.userInfo.isEmpty;
        })
        .toSet()
        .take(2),
  );
}
