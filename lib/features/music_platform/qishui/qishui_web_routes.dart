import 'qishui_api.dart';

/// Explicit protocol translation backed by the pinned PC references. There is
/// no generic '/pc' prefix fallback, cross-domain Cookie transplant, or silent
/// use of another account. Unimplemented write/rights endpoints fail locally.
class QishuiWebRoute {
  const QishuiWebRoute(this.path, this.get, this.body, this.query);
  final String path;
  final bool get;
  final Map<String, Object?> body;
  final Map<String, String> query;

  static QishuiWebRoute resolve(
    String path,
    Map<String, Object?> body,
    Map<String, String> query,
    bool write,
  ) {
    // Explicit pinned PC contracts; every mutation is signed over its final
    // bytes. Never guess a '/pc' prefix (playlist ordering is an exception).
    if (write) {
      final target = switch (path) {
        '/luna/me/playlist' => '/luna/pc/me/playlist',
        '/luna/me/playlist/update' => '/luna/pc/me/playlist/update',
        '/luna/me/playlist/media/append' => '/luna/pc/me/playlist/media/append',
        '/luna/me/playlist/media/delete' => '/luna/pc/me/playlist/media/delete',
        '/luna/me/playlist/media/sort' => '/luna/me/playlist/media/sort',
        '/luna/me/collection/media' => '/luna/pc/me/collection/media',
        '/luna/me/collection/media/delete' =>
          '/luna/pc/me/collection/media/delete',
        '/luna/me/recently-played-media' => '/luna/pc/me/recently-played-media',
        _ => null,
      };
      if (target == null) throw const QishuiException('此汽水写入操作尚未完成适配');
      return QishuiWebRoute(target, false, body, query);
    }
    final params = {...query};
    void copyFields(Iterable<String> keys) {
      for (final key in keys) {
        final value = body[key];
        if (value != null) params[key] = '$value';
      }
    }

    // Pinned PC artist reads (baka-plugins qishui.js / TuneWeave catalog).
    // The mobile tracks endpoint is POST, whereas this exact PC endpoint is
    // GET. Restrict the identifier instead of blindly rewriting any URL.
    final artist = RegExp(
      r'^/luna/artists/([0-9]{1,32})(/tracks)?$',
    ).firstMatch(path);
    if (artist != null) {
      copyFields(['cursor', 'count']);
      return QishuiWebRoute(
        '/luna/pc/artists/${artist[1]}${artist[2] ?? ''}',
        true,
        const {},
        params,
      );
    }

    switch (path) {
      case '/luna/me':
        return QishuiWebRoute('/luna/pc/me', true, const {}, params);
      case '/luna/me/playlist/v2':
        copyFields(['cursor', 'count']);
        return QishuiWebRoute('/luna/pc/me/playlist', true, const {}, params);
      case '/luna/playlist/detail':
        copyFields(['playlist_id', 'cursor', 'count']);
        return QishuiWebRoute(
          '/luna/pc/playlist/detail',
          true,
          const {},
          params,
        );
      case '/luna/search/track':
      case '/luna/search/artist':
        copyFields([
          'q',
          'cursor',
          'search_id',
          'search_method',
          'debug_params',
          'from_search_id',
          'search_scene',
        ]);
        return QishuiWebRoute(
          path == '/luna/search/track'
              ? '/luna/pc/search/track'
              : '/luna/pc/search/artist',
          true,
          const {},
          params,
        );
      case '/luna/video/uploader':
        // The official IMAGE uploader uses this name too (UploadType.Image=0,
        // UploadScene.Default=0). Never guess a '/pc/video/uploader' endpoint.
        copyFields(['track_id', 'upload_type', 'scene']);
        return QishuiWebRoute(path, true, const {}, params);
      case '/luna/discover/mix':
        return QishuiWebRoute('/luna/pc/discover/mix', false, body, params);
      case '/luna/feed/mode':
        return QishuiWebRoute('/luna/pc/feed/mode', false, body, params);
      case '/luna/feed/song-tab':
        return QishuiWebRoute('/luna/pc/feed/song-tab', false, body, params);
      case '/luna/me/recently-played-media':
        copyFields(['cursor', 'count']);
        return QishuiWebRoute(
          '/luna/pc/me/recently-played-media',
          true,
          const {},
          params,
        );
      case '/luna/media_v2':
        // Full-track resolution below uses the signed PC application contract.
        final items = body['media'];
        if (items is List && items.length == 1 && items.single is Map) {
          final row = items.single as Map;
          final id = '${row['id'] ?? ''}';
          if (id.isNotEmpty) {
            return QishuiWebRoute('/luna/pc/track_v2', false, {
              'track_id': id,
              'media_type': 'track',
              'queue_type': 'favorite_track_playlist',
              'scene_name': 'library',
            }, params);
          }
        }
      case '/luna/commerce/v2/check_download':
        // Verified 19.0.0 read DTO, also served by api.qishui.com. This check
        // never consumes quota; a required debit is a separate user operation.
        return QishuiWebRoute(path, false, body, params);
      case '/luna/commerce/v2/commerce_info':
        // Read already earned account benefits using the pinned PC welfare
        // contract. This does not enable apply/gain/ad-task writes.
        return QishuiWebRoute(path, false, body, params);
    }
    throw const QishuiException('当前扫码会话尚未接通此汽水接口，请在汽水音乐App中操作；原账号已保留');
  }
}
