import '../../../core/network/system_music_io_client.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../core/cloud/cloudbase_user_media_storage.dart';
import '../../auth/domain/auth_models.dart';

class CloudProfileBackground {
  const CloudProfileBackground({
    required this.kind,
    required this.value,
    this.downloadUrl,
  });

  final String kind;
  final String value;
  final String? downloadUrl;
}

abstract class ProfileBackgroundSyncApi {
  Future<CloudProfileBackground?> load();

  Future<CloudProfileBackground> saveImage(String localPath);

  Future<CloudProfileBackground> savePreset(String presetId);

  Future<void> clear();

  Future<List<int>> downloadImage(String downloadUrl);
}

class ProfileBackgroundSyncException implements Exception {
  const ProfileBackgroundSyncException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

class CloudBaseProfileBackgroundSyncApi implements ProfileBackgroundSyncApi {
  CloudBaseProfileBackgroundSyncApi({
    required String environmentId,
    required AuthSessionProvider sessionProvider,
    http.Client? client,
    String functionName = 'social-api',
    Duration requestTimeout = const Duration(seconds: 15),
  }) : _baseUrl = 'https://${environmentId.trim()}.api.tcloudbasegateway.com',
       _sessionProvider = sessionProvider,
       _client = client ?? SystemMusicIoClient(),
       _storage = CloudBaseUserMediaStorage(
         environmentId: environmentId,
         sessionProvider: sessionProvider,
         client: client,
       ),
       _functionName = functionName,
       _requestTimeout = requestTimeout;

  final String _baseUrl;
  final AuthSessionProvider _sessionProvider;
  final http.Client _client;
  final CloudBaseUserMediaStorage _storage;
  final String _functionName;
  final Duration _requestTimeout;

  @override
  Future<CloudProfileBackground?> load() async {
    final data = await _call('getProfileBackground');
    return _background(data['profile_background']);
  }

  @override
  Future<CloudProfileBackground> saveImage(String localPath) async {
    final session = await _requireSession();
    final extension = _safeImageExtension(localPath);
    late final CloudBaseStoredMedia uploaded;
    try {
      uploaded = await _storage.upload(
        localPath: localPath,
        objectId:
            'user-profile-backgrounds/${_safePathPart(session.user.uid)}/'
            'background_${DateTime.now().millisecondsSinceEpoch}$extension',
        contentType: _imageContentType(extension),
        maximumBytes: 15 * 1024 * 1024,
      );
    } on CloudBaseMediaStorageException catch (error) {
      throw ProfileBackgroundSyncException(
        error.message,
        code: 'media_upload_failed',
      );
    }
    final data = await _call('setProfileBackground', {
      'kind': 'image',
      'value': uploaded.cloudObjectId,
    });
    final background = _background(data['profile_background']);
    if (background == null) {
      throw const ProfileBackgroundSyncException('云端没有返回主页背景资料');
    }
    return background;
  }

  @override
  Future<CloudProfileBackground> savePreset(String presetId) async {
    final data = await _call('setProfileBackground', {
      'kind': 'preset',
      'value': presetId,
    });
    final background = _background(data['profile_background']);
    if (background == null) {
      throw const ProfileBackgroundSyncException('云端没有返回主页背景资料');
    }
    return background;
  }

  @override
  Future<void> clear() async {
    await _call('setProfileBackground', const {'kind': null, 'value': null});
  }

  @override
  Future<List<int>> downloadImage(String downloadUrl) async {
    try {
      return await _storage.download(
        downloadUrl,
        maximumBytes: 15 * 1024 * 1024,
      );
    } on CloudBaseMediaStorageException catch (error) {
      throw ProfileBackgroundSyncException(
        error.message,
        code: 'media_download_failed',
      );
    }
  }

  Future<Map<String, Object?>> _call(
    String action, [
    Map<String, Object?> fields = const {},
  ]) async {
    final session = await _requireSession();
    late final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_baseUrl/v1/functions/$_functionName?webfn=true'),
            headers: {
              'content-type': 'application/json; charset=utf-8',
              'accept': 'application/json',
              'authorization': 'Bearer ${session.accessToken}',
            },
            body: jsonEncode({'action': action, ...fields}),
          )
          .timeout(_requestTimeout);
    } on HandshakeException {
      throw const ProfileBackgroundSyncException('安全连接建立失败，请稍后重试');
    } on SocketException {
      throw const ProfileBackgroundSyncException('网络不可用，主页背景尚未同步');
    } on TimeoutException {
      throw const ProfileBackgroundSyncException('主页背景云同步响应超时');
    } on http.ClientException {
      throw const ProfileBackgroundSyncException('暂时无法连接主页背景云服务');
    }

    Map<String, Object?> payload;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      payload = decoded is Map
          ? Map<String, Object?>.from(decoded)
          : const <String, Object?>{};
    } on Object {
      throw const ProfileBackgroundSyncException('云端返回了无法识别的主页背景资料');
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] == false) {
      throw ProfileBackgroundSyncException(
        _text(payload['message']) ?? '主页背景云同步失败，请稍后重试',
        code: _text(payload['code']),
      );
    }
    final data = payload['data'];
    return data is Map
        ? Map<String, Object?>.from(data)
        : const <String, Object?>{};
  }

  Future<AuthSession> _requireSession() async {
    final session = await _sessionProvider();
    if (session == null || session.isExpired) {
      throw const ProfileBackgroundSyncException('登录状态已失效，请重新登录');
    }
    return session;
  }

  CloudProfileBackground? _background(Object? value) {
    if (value is! Map) return null;
    final item = Map<String, Object?>.from(value);
    final kind = _text(item['kind']);
    final stableValue = _text(item['value']);
    if (kind == null || stableValue == null) return null;
    return CloudProfileBackground(
      kind: kind,
      value: stableValue,
      downloadUrl: _text(item['download_url']),
    );
  }
}

String _safePathPart(String value) {
  final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  return safe.isEmpty ? 'user' : safe;
}

String _safeImageExtension(String path) {
  final normalized = path.replaceAll('\\', '/');
  final dot = normalized.lastIndexOf('.');
  final extension = dot < 0 ? '' : normalized.substring(dot).toLowerCase();
  return const {'.jpg', '.jpeg', '.png', '.webp'}.contains(extension)
      ? extension
      : '.jpg';
}

String _imageContentType(String extension) => switch (extension) {
  '.png' => 'image/png',
  '.webp' => 'image/webp',
  _ => 'image/jpeg',
};

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
