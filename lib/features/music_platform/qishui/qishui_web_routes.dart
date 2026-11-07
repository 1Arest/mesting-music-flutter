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
    if (write) {
      throw const QishuiException('当前扫码会话暂不支持此写入操作，请在汽水音乐App中操作');
    }
    final params = {...query};
    void copyFields(Iterable<String> keys) {
      for (final key in keys) {
        final value = body[key];
        if (value != null) params[key] = '$value';
      }
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
        copyFields(['q', 'cursor', 'search_id', 'search_method']);
        return QishuiWebRoute('/luna/pc/search/track', true, const {}, params);
      case '/luna/discover/mix':
        return QishuiWebRoute('/luna/pc/discover/mix', false, body, params);
      case '/luna/feed/mode':
        return QishuiWebRoute('/luna/pc/feed/mode', false, body, params);
      case '/luna/feed/song-tab':
        return QishuiWebRoute('/luna/pc/feed/song-tab', false, body, params);
      case '/luna/me/recently-played-media':
        return QishuiWebRoute(
          '/luna/pc/me/recently-played-media',
          true,
          const {},
          params,
        );
      case '/luna/media_v2':
        final items = body['media'];
        if (items is List && items.length == 1 && items.single is Map) {
          final row = items.single as Map;
          final id = '${row['id'] ?? ''}';
          if (id.isNotEmpty) {
            return QishuiWebRoute('/luna/pc/track_v2', true, const {}, {
              ...params,
              'track_id': id,
              'media_type': 'track',
              'queue_type': '',
            });
          }
        }
    }
    throw const QishuiException('当前扫码会话尚未接通此汽水接口，请在汽水音乐App中操作；原账号已保留');
  }
}
