import '../../../core/cache/browse_artwork_projection.dart';
import 'qishui_models.dart';

/// The Soda browse cache is a presentation policy, not an HTTP GET cache.
/// Only catalogue/profile display data may survive process death. Playback
/// grants, uploader credentials, commerce and mutations always stay live.
class QishuiBrowseCachePolicy {
  static const schema = 'qishui-browse-v1';

  static bool allows(String path) =>
      const {
        '/luna/discover/mix',
        '/luna/feed',
        '/luna/feed/recommend',
        '/luna/feed/song-tab',
        '/luna/feed/mode',
        '/luna/feed/modes',
        '/luna/me',
        '/luna/me/playlist/v2',
        '/luna/playlist/detail',
        '/luna/me/recently-played-media',
        '/luna/search/track',
        '/luna/search/artist',
      }.contains(path) ||
      RegExp(r'^/luna/artists/[0-9]+(?:/tracks)?$').hasMatch(path);

  /// Query nonces are transport correlation, not different visible results.
  /// Modes, cursors, filters, counts and keywords remain part of the key.
  static Map<String, Object?> query(
    Map<String, Object?> body,
    Map<String, String> query,
  ) => {
    'body': {
      for (final e in body.entries)
        if (e.key != 'search_id') e.key: e.value,
    },
    'query': {
      for (final e in query.entries)
        if (e.key != 'search_id') e.key: e.value,
    },
  };

  /// A play-history write must not erase the persisted discovery screen on
  /// every song. Only presentation records affected by that mutation expire.
  static bool affectedBy(String mutation, String route) {
    if (mutation == '/luna/me/follow' ||
        mutation == '/luna/me/unfollow' ||
        mutation == '/luna/me/collection/artist' ||
        mutation == '/luna/me/collection/artist/delete') {
      return route == '/luna/me';
    }
    if (mutation == '/luna/me/recently-played-media') {
      return route == '/luna/me/recently-played-media';
    }
    if (mutation.contains('/playlist/') || mutation.contains('/collection/')) {
      return const {
        '/luna/me/playlist/v2',
        '/luna/playlist/detail',
        '/luna/me',
      }.contains(route);
    }
    return false;
  }

  static const _privateFields = {
    'cookie',
    'cookies',
    'set-cookie',
    'sessionid',
    'sessionid_ss',
    'token',
    'tokens',
    'access_token',
    'refresh_token',
    'msToken',
    'x-tt-token',
    'passport_csrf_token',
    'security_token',
    'play_auth',
    'playAuth',
    'PlayAuth',
    'player_info',
    'audio_headers',
    'access_key_id',
    'secret_access_key',
    'session_token',
    'session_key',
    'authorization',
    'play_info',
    'video_model',
    'audio_model',
    'play_url',
    'download_url',
    'media_url',
  };

  static bool _privateKey(Object? key) {
    final snake = '$key'
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (match) => '${match[1]}_${match[2]}',
        )
        .replaceAll('-', '_')
        .toLowerCase();
    return _privateFields.contains(key) ||
        _privateFields.contains(snake) ||
        RegExp(
          r'(^|_)(cookie|token|password|secret|credential|authorization)(_|$)',
        ).hasMatch(snake);
  }

  /// Strip non-display secrets from a defensive owned copy. The raw response
  /// still belongs to the live API; it is never modified by persistence.
  static Map<String, dynamic> display(Map<String, dynamic> value) {
    Object? copy(Object? item) {
      if (item is Map) {
        return <String, dynamic>{
          for (final entry in item.entries)
            if (!_privateKey(entry.key)) '${entry.key}': copy(entry.value),
        };
      }
      if (item is List) return [for (final child in item) copy(child)];
      return item;
    }

    final shown = copy(value) as Map<String, dynamic>;
    shown.remove(browseArtworkProjectionKey);
    final pictures = <String, String>{};
    final imageField = RegExp(
      'cover|artwork|avatar|pic|image|img',
      caseSensitive: false,
    );
    var visited = 0;
    void collect(Object? item, String path, int depth, bool image) {
      if (++visited > 100000 || depth > 18 || pictures.length >= 8192) return;
      if (image) {
        // Reuse the renderer's exact DTO resolver: a base URL needs its uri
        // and template, and alternative CDNs are not separate visible covers.
        pictures[path] = sodaPicture(item);
        return;
      }
      if (item is Map) {
        for (final entry in item.entries) {
          collect(
            entry.value,
            '$path.${entry.key}',
            depth + 1,
            imageField.hasMatch('${entry.key}'),
          );
        }
      } else if (item is List) {
        for (var i = 0; i < item.length; i++) {
          collect(item[i], '$path[$i]', depth + 1, false);
        }
      }
    }

    collect(shown, r'$', 0, false);
    shown[browseArtworkProjectionKey] = pictures;
    return shown;
  }
}
