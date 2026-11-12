import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../../../shared/models/track.dart';

/// Public song aggregates are independent of the selected UI account. These
/// fixed hosts receive no account cookies, tokens, listening logs or device IDs.
/// Kugou's public protocol constants match the embedded reader's request factory.
Future<Map<String, dynamic>> readOfficialSongCount(
  http.Client client,
  TrackSource source,
  String id, {
  DateTime? now,
}) async {
  final Uri uri;
  if (source == TrackSource.netease) {
    uri = Uri.https('music.163.com', '/api/song/red/count', {'songId': id});
  } else if (source == TrackSource.kugou) {
    final params = <String, String>{
      'appid': '3116',
      'clientver': '11440',
      'clienttime': '${(now ?? DateTime.now()).millisecondsSinceEpoch}',
      'dfid': '-',
      'mid': '-',
      'uuid': '-',
      'mixsongids': id,
    };
    const protocolSalt = 'LnT6xpN3khm36zse0QzvmgTZ3waWdRSA';
    final keys = params.keys.toList()..sort();
    final joined = keys.map((key) => '$key=${params[key]}').join();
    params['signature'] = md5
        .convert(utf8.encode('$protocolSalt$joined$protocolSalt'))
        .toString();
    uri = Uri.https(
      'gateway.kugou.com',
      '/count/v1/audio/mget_collect',
      params,
    );
  } else {
    return const {};
  }
  final response = await client.get(
    uri,
    headers: const {'User-Agent': 'Mozilla/5.0'},
  );
  if (response.statusCode != 200 || response.bodyBytes.length > 65536) {
    throw const FormatException('官方收藏人数暂不可用');
  }
  final payload = jsonDecode(utf8.decode(response.bodyBytes));
  if (payload is! Map<String, dynamic>) {
    throw const FormatException('官方收藏人数结构无效');
  }
  return payload;
}
