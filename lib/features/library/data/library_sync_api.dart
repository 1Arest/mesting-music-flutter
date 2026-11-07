import '../../../core/network/system_music_io_client.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../core/cloud/cloudbase_user_media_storage.dart';
import '../../../core/sync/library_sync_models.dart';
import '../../auth/domain/auth_models.dart';

abstract class LibrarySyncApi {
  Future<CloudLibrarySnapshot> synchronize(List<LibrarySyncMutation> mutations);
}

class LibrarySyncException implements Exception {
  const LibrarySyncException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

class CloudBaseLibrarySyncApi implements LibrarySyncApi {
  CloudBaseLibrarySyncApi({
    String? environmentId,
    String? apiBaseUrl,
    required AuthSessionProvider sessionProvider,
    http.Client? client,
    String functionName = 'social-api',
    String? actionPath,
    bool skipMediaUpload = false,
    Duration requestTimeout = const Duration(seconds: 15),
  }) : assert(
         (apiBaseUrl != null && apiBaseUrl.trim().isNotEmpty) ||
             (environmentId != null && environmentId.trim().isNotEmpty),
       ),
       _baseUrl = (apiBaseUrl != null && apiBaseUrl.trim().isNotEmpty)
           ? apiBaseUrl.replaceFirst(RegExp(r'/$'), '')
           : 'https://${environmentId!.trim()}.api.tcloudbasegateway.com',
       _sessionProvider = sessionProvider,
       _client = client ?? SystemMusicIoClient(),
       _mediaStorage = environmentId == null
           ? null
           : CloudBaseUserMediaStorage(
               environmentId: environmentId,
               sessionProvider: sessionProvider,
               client: client,
             ),
       _actionPath = actionPath ?? '/v1/functions/$functionName?webfn=true',
       _skipMediaUpload = skipMediaUpload,
       _requestTimeout = requestTimeout;

  final String _baseUrl;
  final AuthSessionProvider _sessionProvider;
  final http.Client _client;
  final CloudBaseUserMediaStorage? _mediaStorage;
  final String _actionPath;
  final bool _skipMediaUpload;
  final Duration _requestTimeout;

  @override
  Future<CloudLibrarySnapshot> synchronize(
    List<LibrarySyncMutation> mutations,
  ) async {
    final session = await _sessionProvider();
    if (session == null || session.isExpired) {
      throw const LibrarySyncException(
        '登录状态已失效，音乐资料将在下次登录后继续同步',
        code: 'unauthenticated',
      );
    }

    late final List<LibrarySyncMutation> preparedMutations;
    try {
      preparedMutations = await _prepareMutations(
        mutations,
        ownerId: session.user.uid,
      );
    } on CloudBaseMediaStorageException catch (error) {
      throw LibrarySyncException(error.message, code: 'media_upload_failed');
    }

    late final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_baseUrl$_actionPath'),
            headers: {
              'content-type': 'application/json; charset=utf-8',
              'accept': 'application/json',
              'authorization': 'Bearer ${session.accessToken}',
            },
            body: jsonEncode({
              'action': 'syncLibrary',
              'mutations': preparedMutations
                  .map((item) => item.toJson())
                  .toList(),
            }),
          )
          .timeout(_requestTimeout);
    } on HandshakeException {
      throw const LibrarySyncException('安全连接建立失败，音乐资料稍后继续同步');
    } on SocketException {
      throw const LibrarySyncException('网络连接不可用，音乐资料稍后继续同步');
    } on TimeoutException {
      throw const LibrarySyncException('云端同步响应较慢，稍后将自动重试');
    } on http.ClientException {
      throw const LibrarySyncException('暂时无法连接音乐资料云服务');
    }

    final payload = _decode(response);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] == false) {
      throw LibrarySyncException(
        _text(payload['message']) ?? '音乐资料云同步暂时不可用',
        code: _text(payload['code']),
      );
    }
    final data = _map(payload['data']);
    final snapshot = _map(data['snapshot']);
    if (snapshot.isEmpty && !data.containsKey('snapshot')) {
      throw const LibrarySyncException('云端返回的音乐资料不完整');
    }
    return CloudLibrarySnapshot.fromJson(snapshot);
  }

  Future<List<LibrarySyncMutation>> _prepareMutations(
    List<LibrarySyncMutation> mutations, {
    required String ownerId,
  }) async {
    final prepared = <LibrarySyncMutation>[];
    for (final mutation in mutations) {
      if (mutation.entityType != 'playlist' || mutation.operation != 'upsert') {
        prepared.add(mutation);
        continue;
      }
      final payload = Map<String, Object?>.from(mutation.payload);
      final stableCloudId = _text(payload['cover_cloud_id']);
      final coverAsset = _text(payload['cover_asset']);
      final localCover = _localFile(coverAsset);
      if (stableCloudId == null &&
          _isLocalFileReference(coverAsset) &&
          localCover == null) {
        payload['cover_asset'] = null;
      } else if (stableCloudId == null && localCover != null) {
        if (_skipMediaUpload) {
          payload['cover_asset'] = null;
          prepared.add(
            LibrarySyncMutation(
              localId: mutation.localId,
              entityType: mutation.entityType,
              entityId: mutation.entityId,
              operation: mutation.operation,
              payload: payload,
              createdAt: mutation.createdAt,
            ),
          );
          continue;
        }
        final extension = _safeImageExtension(localCover.path);
        final safeOwner = _safePathPart(ownerId);
        final safePlaylist = _safePathPart(mutation.entityId);
        final uploaded = await _mediaStorage!.upload(
          localPath: localCover.path,
          objectId:
              'user-playlist-covers/$safeOwner/$safePlaylist/'
              'cover_${DateTime.now().millisecondsSinceEpoch}$extension',
          contentType: _imageContentType(extension),
          maximumBytes: 10 * 1024 * 1024,
        );
        payload['cover_cloud_id'] = uploaded.cloudObjectId;
        payload['cover_asset'] = null;
      }
      prepared.add(
        LibrarySyncMutation(
          localId: mutation.localId,
          entityType: mutation.entityType,
          entityId: mutation.entityId,
          operation: mutation.operation,
          payload: payload,
          createdAt: mutation.createdAt,
        ),
      );
    }
    return prepared;
  }

  Map<String, Object?> _decode(http.Response response) {
    try {
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      if (value is Map) return Map<String, Object?>.from(value);
    } on Object {
      // Use the stable error below.
    }
    throw const LibrarySyncException('云端返回了无法识别的音乐资料');
  }
}

File? _localFile(String? value) {
  if (value == null) return null;
  File? file;
  if (value.startsWith('file://')) {
    file = File.fromUri(Uri.parse(value));
  } else if (value.startsWith('/') ||
      RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value)) {
    file = File(value);
  }
  return file != null && file.existsSync() ? file : null;
}

bool _isLocalFileReference(String? value) {
  if (value == null) return false;
  return value.startsWith('file://') ||
      value.startsWith('/') ||
      RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value);
}

String _safePathPart(String value) {
  final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  return safe.isEmpty ? 'item' : safe;
}

String _safeImageExtension(String path) {
  final normalized = path.replaceAll('\\', '/');
  final name = normalized.split('/').last;
  final dot = name.lastIndexOf('.');
  final extension = dot < 0 ? '' : name.substring(dot).toLowerCase();
  return const {'.jpg', '.jpeg', '.png', '.webp', '.gif'}.contains(extension)
      ? extension
      : '.jpg';
}

String _imageContentType(String extension) => switch (extension) {
  '.png' => 'image/png',
  '.webp' => 'image/webp',
  '.gif' => 'image/gif',
  _ => 'image/jpeg',
};

Map<String, Object?> _map(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : const {};

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
