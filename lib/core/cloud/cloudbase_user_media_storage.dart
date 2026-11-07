import '../network/system_music_io_client.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../features/auth/domain/auth_models.dart';

class CloudBaseStoredMedia {
  const CloudBaseStoredMedia({required this.cloudObjectId, this.downloadUrl});

  final String cloudObjectId;
  final String? downloadUrl;
}

class CloudBaseMediaStorageException implements Exception {
  const CloudBaseMediaStorageException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CloudBaseUserMediaStorage {
  CloudBaseUserMediaStorage({
    required String environmentId,
    required AuthSessionProvider sessionProvider,
    http.Client? client,
    Duration requestTimeout = const Duration(seconds: 18),
  }) : _baseUrl = 'https://${environmentId.trim()}.api.tcloudbasegateway.com',
       _sessionProvider = sessionProvider,
       _client = client ?? SystemMusicIoClient(),
       _requestTimeout = requestTimeout;

  final String _baseUrl;
  final AuthSessionProvider _sessionProvider;
  final http.Client _client;
  final Duration _requestTimeout;

  Future<CloudBaseStoredMedia> upload({
    required String localPath,
    required String objectId,
    required String contentType,
    required int maximumBytes,
  }) async {
    final session = await _requireSession();
    final file = File(localPath);
    if (!await file.exists()) {
      throw const CloudBaseMediaStorageException('待上传的图片已不存在');
    }
    final length = await file.length();
    if (length <= 0 || length > maximumBytes) {
      throw const CloudBaseMediaStorageException('待上传的图片大小无效');
    }

    final records = await _storagePost('/v1/storages/get-objects-upload-info', [
      {'objectId': objectId},
    ], accessToken: session.accessToken);
    if (records.isEmpty || records.first is! Map) {
      throw const CloudBaseMediaStorageException('云端没有返回图片上传凭据');
    }
    final info = Map<String, Object?>.from(records.first! as Map);
    final uploadUrl = _text(info['uploadUrl']);
    final authorization = _text(info['authorization']);
    final token = _text(info['token']);
    final meta = _text(info['cloudObjectMeta']);
    final cloudObjectId = _text(info['cloudObjectId']);
    if (uploadUrl == null ||
        authorization == null ||
        token == null ||
        meta == null ||
        cloudObjectId == null) {
      throw CloudBaseMediaStorageException(
        _text(info['message']) ?? '云端返回的图片上传凭据不完整',
      );
    }

    late final http.Response response;
    try {
      response = await _client
          .put(
            Uri.parse(uploadUrl),
            headers: {
              'authorization': authorization,
              'x-cos-security-token': token,
              'x-cos-meta-fileid': meta,
              'content-type': contentType,
            },
            body: await file.readAsBytes(),
          )
          .timeout(const Duration(seconds: 30));
    } on SocketException {
      throw const CloudBaseMediaStorageException('网络不可用，图片尚未上传');
    } on TimeoutException {
      throw const CloudBaseMediaStorageException('图片上传超时，请稍后重试');
    } on http.ClientException {
      throw const CloudBaseMediaStorageException('暂时无法上传图片，请稍后重试');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const CloudBaseMediaStorageException('图片上传失败，请稍后重试');
    }
    return CloudBaseStoredMedia(
      cloudObjectId: cloudObjectId,
      downloadUrl:
          _text(info['downloadUrl']) ?? _text(info['downloadUrlEncoded']),
    );
  }

  Future<List<int>> download(
    String downloadUrl, {
    required int maximumBytes,
  }) async {
    late final http.Response response;
    try {
      response = await _client
          .get(Uri.parse(downloadUrl))
          .timeout(_requestTimeout);
    } on SocketException {
      throw const CloudBaseMediaStorageException('网络不可用，图片尚未恢复');
    } on TimeoutException {
      throw const CloudBaseMediaStorageException('图片恢复超时，请稍后重试');
    } on http.ClientException {
      throw const CloudBaseMediaStorageException('暂时无法恢复图片，请稍后重试');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const CloudBaseMediaStorageException('云端图片下载失败');
    }
    if (response.bodyBytes.isEmpty ||
        response.bodyBytes.length > maximumBytes) {
      throw const CloudBaseMediaStorageException('云端图片大小无效');
    }
    return response.bodyBytes;
  }

  Future<AuthSession> _requireSession() async {
    final session = await _sessionProvider();
    if (session == null || session.isExpired) {
      throw const CloudBaseMediaStorageException('登录状态已失效，请重新登录');
    }
    return session;
  }

  Future<List<Object?>> _storagePost(
    String path,
    List<Map<String, Object?>> body, {
    required String accessToken,
  }) async {
    late final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: {
              'content-type': 'application/json; charset=utf-8',
              'accept': 'application/json',
              'authorization': 'Bearer $accessToken',
            },
            body: jsonEncode(body),
          )
          .timeout(_requestTimeout);
    } on SocketException {
      throw const CloudBaseMediaStorageException('网络不可用，无法连接云存储');
    } on TimeoutException {
      throw const CloudBaseMediaStorageException('云存储响应超时，请稍后重试');
    } on http.ClientException {
      throw const CloudBaseMediaStorageException('暂时无法连接云存储');
    }

    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on Object {
      throw const CloudBaseMediaStorageException('云存储返回了无法识别的数据');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final payload = decoded is Map
          ? Map<String, Object?>.from(decoded)
          : const <String, Object?>{};
      throw CloudBaseMediaStorageException(
        _text(payload['message']) ?? '云存储请求失败',
      );
    }
    if (decoded is List) return List<Object?>.from(decoded);
    if (decoded is Map && decoded['data'] is List) {
      return List<Object?>.from(decoded['data']! as List);
    }
    throw const CloudBaseMediaStorageException('云存储返回的数据不完整');
  }
}

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
