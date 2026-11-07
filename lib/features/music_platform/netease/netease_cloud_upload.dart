import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../data/music_platform_api.dart';
import '../platform_backend_providers.dart';
import 'netease_api.dart';

/// Streaming native upload. Music cookies only reach NeteaseApi; the NOS
/// request has an isolated token and no redirects, cookies or auth headers.
class NeteaseCloudUploader {
  const NeteaseCloudUploader(this.api, this.credential);
  final NeteaseApi api;
  final String credential;
  void _check() {
    if (api.session?.credentialId != credential) {
      throw const MusicPlatformException('账号已变化，上传已停止');
    }
  }

  Future<void> upload(Map<Object?, Object?> file) async {
    _check();
    final path = File('${file['path']}');
    final name = '${file['name']}';
    final digest = '${file['md5']}';
    final length = await path.length();
    if (length == 0 || length > 512 * 1024 * 1024 || length != file['length']) {
      throw const MusicPlatformException('上传文件已变化，请重新选择');
    }
    Future<Map<String, dynamic>> request(
      String path,
      Map<String, Object?> data, {
      bool weapi = false,
    }) {
      _check();
      return api.request(
        path,
        data,
        weapi: weapi,
        expectedCredential: credential,
      );
    }

    final checked = await request('/api/cloud/upload/check', {
      'bitrate': '${file['bitrate'] ?? 999000}',
      'ext': '',
      'length': length,
      'md5': digest,
      'songId': '0',
      'version': 1,
    });
    const bucket = 'jd-musicrep-privatecloud-audio-public';
    final allocation = await request('/api/nos/token/alloc', {
      'bucket': bucket,
      'ext': name.split('.').last.toLowerCase(),
      'filename': name,
      'local': false,
      'nos_product': 3,
      'type': 'audio',
      'md5': digest,
    }, weapi: true);
    final token = MusicPlatformApi.objectMap(allocation['result']);
    if (token['token'] == null ||
        token['objectKey'] == null ||
        token['resourceId'] == null) {
      throw const MusicPlatformException('网易云未返回上传凭证');
    }
    if (checked['needUpload'] == true) {
      _check();
      final discovery = await api.client
          .get(
            Uri.https('wanproxy.127.net', '/lbs', {
              'version': '1.0',
              'bucketname': bucket,
            }),
          )
          .timeout(const Duration(seconds: 15));
      final hosts = MusicPlatformApi.objectMap(
        jsonDecode(discovery.body),
      )['upload'];
      if (hosts is! List || hosts.isEmpty) {
        throw const MusicPlatformException('云盘上传服务器暂不可用');
      }
      final host = Uri.parse('${hosts.first}');
      // The token may only go to a NOS upload host returned by the fixed LBS.
      if (!host.host.endsWith('.127.net') || host.userInfo.isNotEmpty) {
        throw const MusicPlatformException('云盘上传地址无效');
      }
      final url = Uri.https(host.host, '/$bucket/${token['objectKey']}', {
        'offset': '0',
        'complete': 'true',
        'version': '1.0',
      });
      _check();
      final upload = http.StreamedRequest('POST', url)
        ..followRedirects = false
        ..headers.addAll({
          'x-nos-token': '${token['token']}',
          'Content-MD5': digest,
          'Content-Type': 'audio/mpeg',
        })
        ..contentLength = length;
      final response = api.client.send(upload);
      await upload.sink.addStream(path.openRead());
      await upload.sink.close();
      final completed = await response.timeout(const Duration(minutes: 3));
      await completed.stream.drain<void>();
      if (completed.statusCode != 200) {
        throw const MusicPlatformException('云盘上传未完成，请刷新云盘确认后重试');
      }
      _check();
    }
    final info = await request('/api/upload/cloud/info/v2', {
      'md5': digest,
      'songid': checked['songId'],
      'filename': name,
      'song': file['title'] ?? name,
      'album': file['album'] ?? '未知专辑',
      'artist': file['artist'] ?? '未知艺术家',
      'bitrate': '${file['bitrate'] ?? 999000}',
      'resourceId': token['resourceId'],
    });
    await request('/api/cloud/pub/v2', {'songid': info['songId']});
  }
}

Future<void> chooseAndUploadNeteaseCloud(
  BuildContext context,
  WidgetRef ref, {
  required bool Function() isCurrent,
}) async {
  final music = ref.read(neteaseMusicRepositoryProvider);
  final credential = music.credential;
  if (credential == null || !isCurrent()) return;
  final file = await const MethodChannel(
    'com.mesting.music/netease_cloud_file',
  ).invokeMapMethod<Object?, Object?>('pick');
  if (file == null) return;
  final temporary = File('${file['path']}');
  try {
    if (!context.mounted || !isCurrent()) return;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (c) => CupertinoAlertDialog(
        title: const Text('上传到网易云云盘？'),
        content: Text('${file['name']}\n上传至当前网易云账号，原文件保留。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('上传'),
          ),
        ],
      ),
    );
    if (confirmed != true || !isCurrent()) return;
    await NeteaseCloudUploader(music.api, credential).upload(file);
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}
