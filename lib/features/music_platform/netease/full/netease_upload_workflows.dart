import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import '../netease_api.dart';
import '../../data/music_platform_api.dart';

/// Native NOS workflows. Tokens go only to the fixed upstream upload hosts;
/// cookies stay in NeteaseApi. Audio is uploaded in bounded 10 MiB chunks.
class NeteaseUploadWorkflows {
  const NeteaseUploadWorkflows(this.api, this.credential);
  final NeteaseApi api;
  final String credential;
  void _check() {
    if (api.session?.credentialId != credential) {
      throw const MusicPlatformException('账号已变化，上传已停止');
    }
  }

  Future<Map<String, dynamic>> _request(
    String path,
    Map<String, Object?> body, {
    bool weapi = false,
  }) {
    _check();
    return api.request(
      path,
      body,
      weapi: weapi,
      expectedCredential: credential,
    );
  }

  Future<Object> picture(Uint8List bytes) async {
    _check();
    final png = bytes.length > 8 && bytes[0] == 0x89 && bytes[1] == 0x50;
    final jpg = bytes.length > 3 && bytes[0] == 0xff && bytes[1] == 0xd8;
    if ((!png && !jpg) || bytes.length > 10 * 1024 * 1024) {
      throw const MusicPlatformException('请选择10MB以内的PNG或JPEG图片');
    }
    final allocation = MusicPlatformApi.objectMap(
      (await _request('/api/nos/token/alloc', {
        'bucket': 'yyimgs',
        'ext': png ? 'png' : 'jpg',
        'filename': 'cover.${png ? 'png' : 'jpg'}',
        'local': false,
        'nos_product': 0,
        'type': 'other',
        'return_body': r'{"code":200,"size":"$(ObjectSize)"}',
      }, weapi: true))['result'],
    );
    _check();
    if (allocation['objectKey'] == null ||
        allocation['token'] == null ||
        allocation['docId'] == null) {
      throw const MusicPlatformException('未取得图片上传凭证');
    }
    final request =
        http.Request(
            'POST',
            Uri.https(
              'nosup-hz1.127.net',
              '/yyimgs/${allocation['objectKey']}',
              {'offset': '0', 'complete': 'true', 'version': '1.0'},
            ),
          )
          ..followRedirects = false
          ..headers.addAll({
            'x-nos-token': '${allocation['token']}',
            'Content-Type': png ? 'image/png' : 'image/jpeg',
          })
          ..bodyBytes = bytes;
    final result = await api.client
        .send(request)
        .timeout(const Duration(seconds: 45));
    await result.stream.drain<void>();
    _check();
    if (result.statusCode != 200) {
      throw const MusicPlatformException('图片上传未完成，请重试');
    }
    return allocation['docId'] as Object;
  }

  /// Private pictures use the eapi allocation contract (including digest and
  /// file size), then `picinfo` on private/send. Upload credentials cannot
  /// redirect a music cookie or authorize an arbitrary upload host.
  Future<({String id, String format})> chatPicture(Uint8List bytes) async {
    _check();
    final png = bytes.length > 8 && bytes[0] == 0x89 && bytes[1] == 0x50;
    final jpeg = bytes.length > 3 && bytes[0] == 0xff && bytes[1] == 0xd8;
    if ((!png && !jpeg) || bytes.length > 10 * 1024 * 1024) {
      throw const MusicPlatformException('请选择10MB以内的PNG或JPEG图片');
    }
    final format = png ? 'png' : 'jpeg';
    final token = MusicPlatformApi.objectMap(
      (await _request('/api/nos/token/alloc', {
        'filename': 'message.${png ? 'png' : 'jpg'}',
        'local': 'false',
        'nos_product': 0,
        'fileSize': bytes.length,
        'type': 'image',
        'md5': md5.convert(bytes).toString(),
        'ext': '.${png ? 'png' : 'jpg'}',
      }))['result'],
    );
    _check();
    final key = '${token['objectKey'] ?? ''}';
    final bucket = '${token['bucket'] ?? 'yyimgs'}';
    final id = '${token['docId'] ?? ''}';
    if (!{'yyimgs', 'cloudmusic'}.contains(bucket) ||
        key.isEmpty ||
        key.contains('..') ||
        !RegExp(r'^\d+$').hasMatch(id) ||
        token['token'] == null) {
      throw const MusicPlatformException('未取得有效的图片上传凭证');
    }
    final upload =
        http.Request(
            'POST',
            Uri.https('nosup-hz1.127.net', '/$bucket/$key', {
              'version': '1.0',
              'offset': '0',
              'complete': 'true',
            }),
          )
          ..followRedirects = false
          ..headers.addAll({
            'x-nos-token': '${token['token']}',
            'Content-Type': 'image/$format',
          })
          ..bodyBytes = bytes;
    final response = await api.client
        .send(upload)
        .timeout(const Duration(seconds: 45));
    await response.stream.drain<void>();
    _check();
    if (response.statusCode != 200) {
      throw const MusicPlatformException('图片上传未完成，尚未发送');
    }
    return (id: id, format: format);
  }

  Future<void> voice(
    Map<Object?, Object?> metadata,
    Map<String, Object?> q,
  ) async {
    _check();
    final file = File('${metadata['path']}');
    final size = await file.length();
    if (size == 0 || size > 512 * 1024 * 1024 || size != metadata['length']) {
      throw const MusicPlatformException('音频文件已变化或超过512MB');
    }
    final name = '${q['songName'] ?? metadata['name']}';
    if (!RegExp(
      r'\.(mp3|flac)$',
      caseSensitive: false,
    ).hasMatch('${metadata['name']}')) {
      throw const MusicPlatformException('声音上传请选择 MP3 或 FLAC 文件');
    }
    final ext = '${metadata['name']}'.toLowerCase().endsWith('.flac')
        ? 'flac'
        : 'mp3';
    final token = MusicPlatformApi.objectMap(
      (await _request('/api/nos/token/alloc', {
        'bucket': 'ymusic',
        'ext': ext,
        'filename': name,
        'local': false,
        'nos_product': 0,
        'type': 'other',
      }, weapi: true))['result'],
    );
    if (token['objectKey'] == null ||
        token['token'] == null ||
        token['docId'] == null) {
      throw const MusicPlatformException('未取得声音上传凭证');
    }
    final key = '${token['objectKey']}';
    Future<http.Response> nos(
      String method,
      Map<String, String> params, {
      List<int>? bytes,
      String? body,
    }) async {
      _check();
      final request =
          http.Request(
              method,
              Uri.https('ymusic.nos-hz.163yun.com', '/$key', params),
            )
            ..followRedirects = false
            ..headers.addAll({
              'x-nos-token': '${token['token']}',
              'Content-Type': body == null
                  ? 'audio/mpeg'
                  : 'text/plain;charset=UTF-8',
              'X-Nos-Meta-Content-Type': 'audio/mpeg',
            });
      if (bytes != null) request.bodyBytes = bytes;
      if (body != null) request.body = body;
      final response = await api.client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(minutes: 2));
      _check();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const MusicPlatformException('声音上传未完成，请刷新列表确认后重试');
      }
      return response;
    }

    final started = await nos('POST', {'uploads': ''});
    final uploadId = RegExp(
      r'<UploadId>([^<]+)</UploadId>',
    ).firstMatch(started.body)?.group(1);
    if (uploadId == null) throw const MusicPlatformException('声音上传服务器未返回上传编号');
    final handle = await file.open();
    final etags = <String>[];
    try {
      for (var offset = 0; offset < size; offset += 10 * 1024 * 1024) {
        final chunk = await handle.read(min(10 * 1024 * 1024, size - offset));
        final response = await nos('PUT', {
          'partNumber': '${etags.length + 1}',
          'uploadId': uploadId,
        }, bytes: chunk);
        final etag = response.headers['etag'];
        if (etag == null) throw const MusicPlatformException('声音分片未获确认');
        etags.add(etag);
      }
    } finally {
      await handle.close();
    }
    final xml =
        '<CompleteMultipartUpload>${[for (var i = 0; i < etags.length; i++) '<Part><PartNumber>${i + 1}</PartNumber><ETag>${const HtmlEscape().convert(etags[i])}</ETag></Part>'].join()}</CompleteMultipartUpload>';
    await nos('POST', {'uploadId': uploadId}, body: xml);
    final voice = {
      'name': name,
      'autoPublish': q['autoPublish'] == 1 || q['autoPublish'] == '1',
      'autoPublishText': q['autoPublishText'] ?? '',
      'description': q['description'] ?? '',
      'voiceListId': q['voiceListId'],
      'coverImgId': q['coverImgId'],
      'dfsId': token['docId'],
      'categoryId': q['categoryId'],
      'secondCategoryId': q['secondCategoryId'],
      'composedSongs': '${q['composedSongs'] ?? ''}'
          .split(',')
          .where((s) => s.isNotEmpty)
          .toList(),
      'privacy': q['privacy'] == 1 || q['privacy'] == '1',
      'publishTime': q['publishTime'] ?? 0,
      'orderNo': q['orderNo'] ?? 1,
    };
    for (final path in [
      '/api/voice/workbench/voice/batch/upload/preCheck',
      '/api/voice/workbench/voice/batch/upload/v2',
    ]) {
      _check();
      await api.request(
        path,
        {
          'dupkey': _uuid(),
          'voiceData': jsonEncode([voice]),
        },
        expectedCredential: credential,
        additionalHeaders: {'x-nos-token': '${token['token']}'},
      );
    }
  }

  String _uuid() {
    final rng = Random.secure();
    final bytes = List.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
