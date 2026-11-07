import 'dart:convert';
import '../netease_extended_routes.dart';
import 'netease_native_routes.g.dart';

/// Composite workflows live in NeteaseFullRepository. This file only builds
/// the remaining single-request contracts whose upstream functions additionally
/// post-process their responses. Paths are copied from the fixed modules.
NeteaseRoute? neteaseCompleteContract(String route, Map<String, Object?> q) {
  final native = neteaseNativeRoute(route, q);
  if (native != null) return native;
  Object? get(String k, [Object? fallback]) => q[k] ?? fallback;
  NeteaseRoute make(String p, Map<String, Object?> d, [bool w = true]) =>
      (path: p, data: d, weapi: w);
  switch (route) {
    // Interoperable wire fields checked against the official client's room
    // requests. No upstream implementation or Wi-Fi identifier is copied.
    case '/listentogether/user/gps/report':
      return make('/api/listen/together/user/gps/report', {
        'roomId': get('roomId'),
        'latitude': get('latitude', 0),
        'longitude': get('longitude', 0),
        'opened': '${get('opened', false)}',
        'privacy': '${get('privacy', true)}',
      }, false);
    case '/listentogether/distance/get':
      return make('/api/listen/together/distance/get', {
        'roomId': get('roomId'),
        'otherUserId': get('otherUserId'),
      }, false);
    case '/listentogether/relation/statistics/get':
      return make('/api/listen/together/relation/statistics/get/v2', {
        'roomId': get('roomId'),
        'roomUserIds': jsonEncode(_ids(get('roomUserIds'))),
      }, false);
    case '/login/cellphone':
    case '/login':
    case '/login/qr/key':
    case '/login/qr/check':
    case '/login/refresh':
    case '/login/status':
    case '/user/detail':
    case '/playlist/tracks':
    case '/comment/new':
      // Existing adapter owns these normalized account/comment contracts.
      return null;
    case '/top/playlist':
      return make('/api/playlist/list', {
        'cat': get('cat', '全部'),
        'order': get('order', 'hot'),
        'limit': get('limit', 50),
        'offset': get('offset', 0),
        'total': true,
      });
    case '/top/list':
      return make('/api/playlist/v4/detail', {
        'id': get('id'),
        'n': '500',
        's': '0',
      }, false);
    case '/song/url':
    case '/check/music':
      return make('/api/song/enhance/player/url', {
        'ids': jsonEncode(_ids(get('id'))),
        'br': get('br', 999000),
      });
    case '/song/url/v1':
      return make('/api/song/enhance/player/url/v1', {
        'ids': jsonEncode(_ids(get('id'))),
        'level': get('level', 'standard'),
        'encodeType': 'flac',
      }, false);
    case '/verify/getQr':
      return make('/api/frontrisk/verify/getqrcode', {
        'verifyConfigId': get('vid'),
        'verifyType': get('type'),
        'token': get('token'),
        'params': jsonEncode({'event_id': get('evid'), 'sign': get('sign')}),
        'size': 150,
      });
    case '/verify/qrcodestatus':
      return make('/api/frontrisk/verify/qrcodestatus', {'qrCode': get('qr')});
    default:
      return null;
  }
}

List<int> _ids(Object? value) => (value is List ? value : '$value'.split(','))
    .map((v) => int.parse('$v'))
    .toList();
