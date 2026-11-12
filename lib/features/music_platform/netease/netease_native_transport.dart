import 'dart:convert';
import 'dart:io' show pid;
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import '../data/music_platform_api.dart';
import 'netease_native_log.dart';

/// Candidate Android BI adapter. Native-file receipt is checked separately
/// from HTTP/business status. It never falls back to a second write endpoint.
class NeteaseNativeTransport {
  static Future<Map<String, dynamic>> send({
    required http.Client client,
    required Map<String, String> cookies,
    required String deviceId,
    required Map<String, Object?> log,
    required DateTime eventTime,
    required int sequence,
  }) async {
    const version = '9.5.12';
    final identity = <String, String>{
      ...cookies,
      'os': 'android',
      'appver': version,
      'versioncode': '9005012',
      'deviceId': deviceId,
    };
    final json = Map<String, Object?>.from(log['json'] as Map)
      ..remove('mainsite')
      ..remove('mainsiteWeb')
      ..remove('content')
      ..addAll({'pid': pid, '_log_thoroughfare': 'bi'});
    if (log['action'] == 'play') json['lt'] = 1;
    final line =
        '${eventTime.millisecondsSinceEpoch ~/ 1000}\u0001'
        '${log['action']}\u0001${jsonEncode(json)}\n';
    // The official header contains a JSON cookie map. Do not export or persist
    // this file: it exists only for this bounded fixed-host request.
    final bytes = NeteaseNativeLog.encode(
      line: line,
      userInfo: jsonEncode(identity),
      sequence: sequence,
    );
    final random = Random.secure();
    final name = 'flush_bi_${pid}_${sequence}_${random.nextInt(0x7fffffff)}';
    final boundary =
        'mesting${random.nextInt(0x7fffffff)}${random.nextInt(0x7fffffff)}';
    final body = BytesBuilder()
      ..add(
        utf8.encode(
          '--$boundary\r\n'
          'Content-Disposition: form-data; name="file"; filename="$name"\r\n'
          'Content-Type: multipart/form-data\r\n\r\n',
        ),
      )
      ..add(bytes)
      ..add(utf8.encode('\r\n--$boundary--\r\n'));
    final request =
        http.Request(
            'POST',
            Uri.https(
              'clientlog3.music.163.com',
              '/api/clientlog/encrypt/upload',
              {'multiupload': 'false'},
            ),
          )
          ..followRedirects = false
          ..headers.addAll({
            'Cookie': identity.entries
                .map((e) => '${e.key}=${e.value}')
                .join('; '),
            'User-Agent': 'NeteaseMusic/9.5.12(9005012); Dalvik/2.1.0',
            'Accept': 'application/json',
            'Content-Type': 'multipart/form-data; boundary=$boundary',
          })
          ..bodyBytes = body.takeBytes();
    final response = await client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200 || response.bodyBytes.length > 65536) {
      throw const MusicPlatformException('网易云原生日志响应未确认');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) throw const FormatException('Invalid native receipt');
    final result = Map<String, dynamic>.from(decoded);
    final code = int.tryParse('${result['code']}');
    if (code != null && code != 200) {
      throw MusicPlatformException('网易云原生日志未接收（$code）', code: '$code');
    }
    var data = result['data'];
    if (data is String) data = jsonDecode(data);
    // code200 by itself does not establish that this file was accepted.
    if (code != 200 ||
        data is! Map ||
        data['successfiles'] is! List ||
        !(data['successfiles'] as List).contains(name)) {
      throw const MusicPlatformException('网易云原生日志文件回执未确认');
    }
    return result;
  }
}
